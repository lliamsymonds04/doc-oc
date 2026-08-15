extends Node3D
class_name BasicArm

@export var num_limbs: int = 3
@export var limb_length: float = 2.0
@export var limb_radius: float = 0.15
@export var joint_radius: float = 0.25
@export var step_duration: float = 0.25
@export var lift_height: float = 0.8
@export var joint_y_margin: float = 0.6
@export var min_joint_angle: float = 20.0

const GROUNDED_DISTANCE_CHECK: float = 0.2

var target: Vector3 = Vector3.ZERO
var target_node: Node3D
var pole: Node3D
var anchor: Node3D
var is_leg: bool = false

## state
var is_stepping = false
var step_start: Vector3
var step_end: Vector3
var step_normal: Vector3 = Vector3.UP
var step_progress: float = 0.0

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
	solver.floor_y_margin = joint_y_margin
	solver.min_joint_angle = min_joint_angle

	for i in range(num_limbs - 1):
		solver.hinge_axes.append(Vector3.RIGHT)

	_build_visualizer()

## public methods
func is_grounded() -> bool:
	if is_stepping:
		return false

	var end_effector := solver.get_end_effector()
	var target_pos := to_local(target_node.global_position)
	var distance := (end_effector - target_pos).length()
	return distance <= GROUNDED_DISTANCE_CHECK

func is_fully_extended() -> bool:
	var mount_pos := solver.joints[0]
	var target_pos := to_local(target_node.global_position)
	var distance := (mount_pos - target_pos).length()
	return distance > solver.total_length

func start_step(to: Vector3, delay := 0.0, surface_normal := Vector3.UP) -> void:
	is_stepping = true
	step_start = to_global(solver.get_end_effector())
	step_end = to
	step_progress = -maxf(delay, 0.0) / step_duration
	step_normal = surface_normal

func advance_step(dt: float) -> void:
	step_progress += dt / step_duration
	if step_progress < 0.0:
		target = to_local(step_start)
		return  # waiting out the stagger delay; foot holds its start position

	step_progress = minf(step_progress, 1.0)
	var base := step_start.lerp(step_end, step_progress)
	var height := lift_height * sin(step_progress * PI)
	var step_pos = base + step_normal * height
	target_node.global_position = step_pos
	target = to_local(step_pos)

	if step_progress >= 1.0:
		is_stepping = false


## private methods
func _physics_process(_delta: float) -> void:
	var solved := solver.solve(target, Vector3.ZERO, pole.position)
	_update_visualizer(solved)

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
