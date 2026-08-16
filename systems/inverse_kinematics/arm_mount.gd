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
@onready var target: Node3D = $Target
@onready var wall_target: Node3D = $WallTarget

var raycast_config: ArmRaycastConfig
var arm: BasicArm
var step_target: Variant
var anchor: Node3D
var wall_surface_normal: Vector3 = Vector3.ZERO
var _sway_time: float = 0.0

func _process(delta: float) -> void:
	_sway_time += delta

func init() -> BasicArm:
	anchor = target.duplicate()
	anchor.name = "anchor"
	add_child(anchor)

	if vertical_mount == null or horizontal_mount == null:
		push_error("vertical and horizontal mount must be set")
		return null

	target.top_level = true

	arm = BasicArm.new()
	arm.name = "arm_%s" % name
	arm.is_leg = is_leg
	arm.target_node = target
	arm.position = Vector3.ZERO
	arm.target = target.position
	arm.anchor = anchor
	arm.pole = pole
	add_child(arm)

	return arm

func compute_idle_target() -> Vector3:
	var idle_pos = to_local(idle_target.global_position)
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
		return

	if is_leg:
		var target_pos := target.global_position
		var anchor_pos := anchor.global_position

		# velocity anchor_lead_time
		var velocity_xz := Vector3(velocity.x, 0, velocity.z)
		velocity_xz *= raycast_config.anchor_lead_time
		anchor_pos += velocity_xz

		var hit = _get_surface_hit(anchor_pos, Vector3.DOWN, raycast_config.step_raycast_distance)
		if hit != null:
			var hit_pos: Vector3 = hit.position
			var target_displacement:= hit_pos - target_pos
			var disp := target_displacement.length()
			if disp > raycast_config.max_target_displacement:
				step_target = hit_pos

		arm.target = arm.to_local(target_pos)
	elif idle_target != null:
		arm.target = compute_idle_target()

func can_step() -> bool:
	return step_target != null and ((arm.is_grounded() and horizontal_mount.arm.is_grounded()) or arm.is_fully_extended())

func get_step_distance() -> float:
	if step_target == null:
		return INF
	return (step_target - arm.anchor.global_position).length()

func get_wall_hit_pos(velocity: Vector3) -> Variant:
	var wall_target_pos := wall_target.global_position
	var cast_dir := -global_transform.basis.z
	var cast_pos = wall_target_pos + raycast_config.anchor_lead_time * velocity
	var hit = _get_surface_hit(cast_pos, cast_dir, raycast_config.wall_raycast_distance)

	return hit

func update_wall_climb(velocity: Vector3) -> Variant:
	var hit = get_wall_hit_pos(velocity)
	step_target = null
	var target_pos := arm.target_node.global_position
	if hit != null:
		var hit_pos: Vector3 = hit.position
		var distance := (hit_pos - target_pos).length()

		if distance > raycast_config.max_target_displacement:
			step_target = hit_pos

	arm.target = arm.to_local(target_pos)
	return hit

func _get_surface_hit(from: Vector3, direction: Vector3, distance: float) -> Variant:
	var space := get_world_3d().direct_space_state
	var ray_origin = from - direction * distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction * distance * 2, ~2)

	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	return {
		"position": result["position"],
		"normal": result["normal"],
	}

func set_apply_floor(should_apply: bool) -> void:
	arm.solver.should_apply_floor = should_apply
