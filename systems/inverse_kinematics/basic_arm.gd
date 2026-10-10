extends Node3D
class_name BasicArm

signal move_finished(pos: Vector3)
signal step_landed(pos: Vector3, normal: Vector3)
signal step_started(pos: Vector3, normal: Vector3)
signal hit_detected(pos: Vector3, normal: Vector3, collider: Object)

@export_category("Limbs")
@export var num_limbs: int = 3
@export var limb_length: float = 2.0
@export var limb_radius: float = 0.15
@export var joint_radius: float = 0.25

@export_category("Step_effects")
@export var step_duration: float = 0.25
@export var lift_height: float = 0.8
@export var floor_margin: float = 0.6
@export var min_joint_angle: float = 20.0

@export_category("Attack")
@export var punch_duration: float = 0.15
@export var punch_ease_curve: float = 2.0
@export var hit_probe_margin: float = 0.1  # extra radius beyond joint_radius for the hit sphere

const GROUNDED_DISTANCE_CHECK: float = 0.2

var target: Vector3 = Vector3.ZERO
var target_world: Vector3 = Vector3.ZERO
var pole: Node3D
var is_leg: bool = false


class MotionProfile:
	var duration: float = 0.25
	var delay: float = 0.0  # hold at start position before moving
	var speed_multiplier: float = 1.0
	var arc_height: float = 0.0
	var arc_axis: Vector3 = Vector3.UP
	var ease_curve: float = 1.0  # Godot's ease(): 1.0 = linear
	var floor_normal: Variant = null  # null = don't touch solver.floor_normal
	var detect_hits: bool = false
	var cast_mask: int = -1  # -1 = use the arm's default cast_mask


## state
var is_moving := false
var _profile: MotionProfile
var _move_start: Vector3
var _move_end: Vector3
var _move_progress: float = 0.0
var _hit_this_move: bool = false
var _prev_probe_pos: Vector3 = Vector3.ZERO  # world-space fist position last frame
var _probe_shape: SphereShape3D

## Physics mask for the hit probe; ignores the owner's layers.
## Set by ArmMount from PlayerController.cast_mask().
var cast_mask: int = ~0

var _emit_step_landed := false
var solver: FabrikSolver
var limb_meshes: Array[MeshInstance3D] = []
var joint_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	# Initial straight-line pose toward the target, in local space.
	# joints[0] is the root, followed by one point per limb end.
	var positions := PackedVector3Array([Vector3.ZERO])
	var target_dir := pole.position.normalized()
	for i in range(num_limbs):
		positions.append(positions[i] + target_dir * limb_length)

	solver = FabrikSolver.new(positions)
	solver.floor_margin = floor_margin
	solver.min_joint_angle = min_joint_angle
	move_finished.connect(_on_move_finished)

	for i in range(num_limbs - 1):
		solver.hinge_axes.append(Vector3.RIGHT)

	_probe_shape = SphereShape3D.new()
	_probe_shape.radius = joint_radius + hit_probe_margin

	_build_visualizer()


## public methods
func is_grounded() -> bool:
	if is_moving:
		return false

	var end_effector := solver.get_end_effector()
	var target_pos := to_local(target_world)
	var distance := (end_effector - target_pos).length()
	return distance <= GROUNDED_DISTANCE_CHECK


func is_fully_extended(length_percent: float = 1.0) -> bool:
	var mount_pos := solver.joints[0]
	var target_pos := to_local(target_world)
	var distance := (mount_pos - target_pos).length()
	return distance > solver.total_length * length_percent


func begin_move(to: Vector3, profile: MotionProfile) -> void:
	is_moving = true
	_profile = profile
	_move_start = to_global(solver.get_end_effector())
	_move_end = to
	_move_progress = -maxf(profile.delay, 0.0) * profile.speed_multiplier / profile.duration
	_hit_this_move = false
	_prev_probe_pos = _move_start

	if profile.floor_normal != null:
		solver.floor_normal = _to_local_dir(profile.floor_normal)


func advance_move(dt: float) -> void:
	if not is_moving or _profile == null:
		return

	_move_progress += dt / _profile.duration * _profile.speed_multiplier
	if _move_progress < 0.0:
		target = to_local(_move_start)
		target_world = _move_start
		return  # waiting out the stagger delay; foot holds its start position

	_move_progress = minf(_move_progress, 1.0)
	var t := ease(_move_progress, _profile.ease_curve)
	var base := _move_start.lerp(_move_end, t)
	var height := _profile.arc_height * sin(_move_progress * PI)
	var pos := base + _profile.arc_axis * height
	target_world = pos
	target = to_local(pos)

	if _profile.detect_hits:
		if not _hit_this_move:
			var hit_result: Variant = query_end_effector(pos)
			if hit_result:
				_hit_this_move = true
				hit_detected.emit(
					hit_result["position"], hit_result["normal"], hit_result["collider"]
				)
		_prev_probe_pos = pos

	if _move_progress >= 1.0:
		is_moving = false
		move_finished.emit(_move_end)


func start_step(to: Vector3, params: StepParams = null) -> void:
	if params == null:
		params = StepParams.new()

	var profile := MotionProfile.new()
	profile.duration = step_duration
	profile.delay = params.delay
	profile.speed_multiplier = params.speed_multiplier
	profile.arc_height = lift_height
	profile.arc_axis = params.surface_normal
	profile.floor_normal = params.surface_normal
	_emit_step_landed = params.emit_landed

	begin_move(to, profile)

	step_started.emit(_move_start, params.surface_normal)


func start_punch(to: Vector3, p_cast_mask: int = -1) -> void:
	var profile := MotionProfile.new()
	profile.duration = punch_duration
	profile.ease_curve = punch_ease_curve
	profile.detect_hits = true
	profile.cast_mask = p_cast_mask

	begin_move(to, profile)


## Owns the solver call convention (root at the arm origin, pole in arm-local space)
## so external callers can't diverge from what _process passes to solve().
func set_pole_constraints(enabled: bool) -> void:
	solver.set_pole_constraints(enabled, target, Vector3.ZERO, pole.position)


func query_end_effector(to: Vector3) -> Variant:
	if solver == null:
		return null

	# perform a spatial query
	var space := get_world_3d().direct_space_state

	var motion := to - _prev_probe_pos
	if motion.length() < 0.001:
		return null

	return (
		RaycastUtil
		. shape_cast(
			space,
			_probe_shape,
			_prev_probe_pos,
			motion,
			_profile.cast_mask if _profile.cast_mask != -1 else cast_mask,
		)
	)


## private methods
func _process(_delta: float) -> void:
	if solver == null or pole == null:
		return
	var solved := solver.solve(target, Vector3.ZERO, pole.position)
	_update_visualizer(solved)


func _on_move_finished(pos: Vector3) -> void:
	if _emit_step_landed:
		_emit_step_landed = false
		step_landed.emit(pos, _profile.arc_axis)


## Converts a world-space direction into the solver's local space.
func _to_local_dir(world_dir: Vector3) -> Vector3:
	return (global_transform.basis.inverse() * world_dir).normalized()


func _build_visualizer() -> void:
	var limb_mat := StandardMaterial3D.new()
	limb_mat.albedo_color = Color(0.3, 0.52, 1.0)
	limb_mat.roughness = 0.45

	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(1.0, 0.55, 0.12)
	joint_mat.roughness = 0.45

	var end_effector_mat := StandardMaterial3D.new()
	end_effector_mat.albedo_color = Color(1.0, 1.0, 0.1)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = limb_radius
	cylinder.bottom_radius = limb_radius
	cylinder.height = limb_length

	for i in range(num_limbs):
		var seg := MeshInstance3D.new()
		seg.mesh = cylinder
		seg.material_override = limb_mat
		add_child(seg)
		limb_meshes.append(seg)

	var sphere := SphereMesh.new()
	sphere.radius = joint_radius
	sphere.height = joint_radius * 2

	for i in range(num_limbs + 1):
		var joint := MeshInstance3D.new()
		joint.mesh = sphere
		if i == num_limbs:
			joint.material_override = end_effector_mat
		else:
			joint.material_override = joint_mat
		add_child(joint)
		joint_meshes.append(joint)


func _update_visualizer(joints: PackedVector3Array) -> void:
	for i in range(limb_meshes.size()):
		var a := joints[i]
		var b := joints[i + 1]
		var arm_len := a.distance_to(b)
		var seg := limb_meshes[i]
		if arm_len < 0.0001:
			seg.scale = Vector3.ZERO
			continue
		seg.position = (a + b) * 0.5
		seg.basis = _basis_aligned_to((b - a) / arm_len)

	for i in range(joint_meshes.size()):
		var joint := joint_meshes[i]
		joint.position = joints[i]


## Returns a right-handed basis whose local Y axis points along `dir`.
func _basis_aligned_to(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(dir)
	return Basis(x, dir, z)
