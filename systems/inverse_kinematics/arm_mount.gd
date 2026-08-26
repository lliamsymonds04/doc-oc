extends Node3D
class_name ArmMount

@export var is_leg: bool = true
# the mount above this
@export var vertical_mount: ArmMount
# the mount to the side of this
@export var horizontal_mount: ArmMount

@export_category("Idle targeting")
@export var idle_target: Node3D
@export var idle_sway_x: float = 0.0
@export var idle_sway_y: float = 0.0
@export var idle_sway_speed: float = 1.0
@export var idle_sway_y_mult: float = 2.0
@export_range(-3.1416, 3.1416) var sway_phase: float = 0.0

@onready var pole: Node3D = $Pole
@onready var ground_probe: Node3D = $GroundProbe
@onready var wall_probe: Node3D = $WallProbe

var raycast_config: ArmRaycastConfig
var _cast_sphere: SphereShape3D
var arm: BasicArm
var step_target: Variant
var wall_surface_normal: Vector3 = Vector3.ZERO
var _sway_time: float = 0.0

var target_world: Vector3
var _cached_target_world: Vector3

func _process(delta: float) -> void:
	_sway_time += delta

func init() -> BasicArm:
	if vertical_mount == null or horizontal_mount == null:
		push_error("vertical and horizontal mount must be set")
		return null

	arm = BasicArm.new()
	arm.name = "arm_%s" % name
	arm.is_leg = is_leg
	arm.position = Vector3.ZERO
	arm.pole = pole
	add_child(arm)
	set_target(ground_probe.global_position)

	_cast_sphere = SphereShape3D.new()
	_cast_sphere.radius = raycast_config.shape_cast_radius

	return arm

func compute_idle_target() -> Vector3:
	if idle_target == null:
		return ground_probe.position

	var idle_pos = idle_target.position
	var t := _sway_time * idle_sway_speed
	if idle_sway_x != 0.0:
		idle_pos += Vector3.RIGHT * sin(t + sway_phase) * idle_sway_x
	if idle_sway_y != 0.0:
		idle_pos += Vector3.UP * sin(t * idle_sway_y_mult + sway_phase) * idle_sway_y
	return idle_pos

func update_step(velocity: Vector3, dt: float) -> void:
	step_target = null

	if arm.is_stepping:
		arm.advance_step(dt)
		sync_from_arm()
		return

	if is_leg:
		_cached_target_world = target_world
		var velocity_xz := Vector3(velocity.x, 0, velocity.z) * raycast_config.anchor_lead_time
		var probe_pos := ground_probe.global_position + velocity_xz
		var hit = get_surface_hit(probe_pos, Vector3.DOWN, raycast_config.step_raycast_distance)
		if hit != null:
			var hit_pos: Vector3 = hit.position
			var disp := (hit_pos - _cached_target_world).length()
			if disp > raycast_config.max_target_displacement:
				step_target = hit_pos
		set_target(_cached_target_world)
	elif idle_target != null:
		arm.target = compute_idle_target()

func get_step_distance() -> float:
	if step_target == null:
		return INF
	return (step_target - ground_probe.global_position).length()

func get_wall_hit_pos(velocity: Vector3) -> Variant:
	var wall_probe_pos := wall_probe.global_position
	var cast_dir := -global_transform.basis.z
	var cast_pos = wall_probe_pos + raycast_config.anchor_lead_time * velocity
	var hit = get_surface_hit(cast_pos, cast_dir, raycast_config.wall_raycast_distance)
	return hit

func update_wall_climb(velocity: Vector3) -> Variant:
	var hit = get_wall_hit_pos(velocity)
	step_target = null
	# Use arm's world pos as authority — mount.target_world can be stale
	# if the arm was advanced directly via WallClimbState (no mount sync).
	sync_from_arm()
	if hit != null:
		# keep wall_surface_normal in sync with what we actually grip
		wall_surface_normal = hit.normal
		var hit_pos: Vector3 = hit.position
		var distance := (hit_pos - _cached_target_world).length()
		if distance > raycast_config.max_target_displacement:
			step_target = hit_pos
	elif not arm.is_stepping:
		# not touching anything and not mid-step: not a valid grip
		wall_surface_normal = Vector3.ZERO
	set_target(_cached_target_world)
	return hit

func get_surface_hit(from: Vector3, direction: Vector3, distance: float) -> Variant:
	var space := get_world_3d().direct_space_state
	return RaycastUtil.shape_cast(space, _cast_sphere, from, direction * distance, ~2)

func set_target(world_pos: Vector3) -> void:
	target_world = world_pos
	_cached_target_world = world_pos
	if arm:
		arm.target_world = world_pos
		arm.target = to_local(world_pos)

func sync_from_arm() -> void:
	if arm:
		set_target(arm.target_world)

func set_apply_floor(should_apply: bool) -> void:
	arm.solver.should_apply_floor = should_apply
