extends Node3D
class_name ArmMount

@export var is_leg: bool = true
# the mount above this
@export var vertical_mount: ArmMount
# the mount to the side of this
@export var horizontal_mount: ArmMount

@export var footstep_volume: float = -5.0

@export var servo_volume: float = -15.0

const EFFECT_SAME_BEAT_WINDOW: float = 0.15
# how far off straight-up a ground surface normal can be and still count as ground
const MAX_GROUND_NORMAL_ANGLE: float = deg_to_rad(60.0)

@export_category("Idle targeting")
@export var idle_sway_x: float = 0.0
@export var idle_sway_y: float = 0.0
@export var idle_sway_speed: float = 1.0
@export var idle_sway_y_mult: float = 2.0
@export_range(-3.1416, 3.1416) var sway_phase: float = 0.0

@onready var pole: Node3D = $Pole
@onready var ground_probe: Node3D = $GroundProbe
@onready var wall_probe: Node3D = $WallProbe
@onready var idle_target: Node3D = $IdleTarget

var diagonal_mount: ArmMount
var raycast_config: ArmRaycastConfig
var player: PlayerController
var arm: BasicArm
var _vfx: ImpactVFX
var _cast_sphere: SphereShape3D
var _audio_player: AudioStreamPlayer3D
var _servo_player: AudioStreamPlayer3D


var step_target: Variant
var wall_surface_normal: Vector3 = Vector3.ZERO
var _sway_time: float = 0.0
var last_landed_time: float = -INF
var last_servo_time: float = -INF

func _process(dt: float) -> void:
	_sway_time += dt

func init(p: PlayerController) -> BasicArm:
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

	if p.step_vfx != null:
		_vfx = p.step_vfx.instantiate() as ImpactVFX
		_vfx.top_level = true
		add_child(_vfx)
		arm.step_landed.connect(_vfx.play)

	if p.step_sound != null:
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.stream = p.step_sound
		_audio_player.top_level = true
		add_child(_audio_player)
		arm.step_landed.connect(_play_landed_sound)

	arm.step_landed.connect(_shake_camera)

	if p.servo_sound != null:
		_servo_player = AudioStreamPlayer3D.new()
		_servo_player.stream = p.servo_sound
		add_child(_servo_player)
		arm.step_started.connect(_play_servo)

	diagonal_mount = horizontal_mount.vertical_mount

	return arm

func update_idle_target(dt: float, lerp_speed := 0.0, world_offset := Vector3.ZERO) -> void:
	if arm == null or arm.is_moving:
		return

	var desired := compute_idle_target()
	if world_offset != Vector3.ZERO:
		desired += global_transform.basis.inverse() * world_offset

	if lerp_speed > 0.0:
		arm.target = arm.target.lerp(desired, lerp_speed * dt)
	else:
		arm.target = desired

	arm.target_world = arm.to_global(arm.target)

func update_planted_target() -> void:
	if arm == null or arm.is_moving:
		return
	arm.target = arm.to_local(arm.target_world)

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

func update_ground_step_target(velocity: Vector3, force := false) -> void:
	step_target = null

	var velocity_xz := Vector3(velocity.x, 0, velocity.z) * raycast_config.anchor_lead_time
	var probe_pos: Vector3 = ground_probe.global_position + velocity_xz + Vector3.UP * raycast_config.probe_vertical_offset
	var hit = get_surface_hit(probe_pos, Vector3.DOWN, raycast_config.step_raycast_distance + raycast_config.probe_vertical_offset)

	if hit != null and hit.normal.angle_to(Vector3.UP) <= MAX_GROUND_NORMAL_ANGLE:
		var hit_pos: Vector3 = hit.position
		var max_disp := raycast_config.max_target_displacement
		if player.is_sprinting():
			max_disp *= raycast_config.sprint_displacement_mult
		var disp := (hit_pos - arm.target_world).length()
		if disp > max_disp or force:
			step_target = hit_pos

func update_step(velocity: Vector3, dt: float) -> void:
	step_target = null

	if arm.is_moving:
		arm.advance_move(dt)
		return

	if is_leg:
		update_ground_step_target(velocity)

func _step_effect_suppressed(is_servo: bool) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if is_servo:
		return now - horizontal_mount.last_servo_time < EFFECT_SAME_BEAT_WINDOW \
			or now - diagonal_mount.last_servo_time < EFFECT_SAME_BEAT_WINDOW
	return now - horizontal_mount.last_landed_time < EFFECT_SAME_BEAT_WINDOW \
		or now - diagonal_mount.last_landed_time < EFFECT_SAME_BEAT_WINDOW

func _stamp_landed() -> void:
	last_landed_time = Time.get_ticks_msec() / 1000.0

func _stamp_servo() -> void:
	last_servo_time = Time.get_ticks_msec() / 1000.0

func _play_landed_sound(pos, _normal) -> void:
	if _step_effect_suppressed(false):
		return

	_audio_player.reset_physics_interpolation()
	_audio_player.position = pos
	_audio_player.volume_db = footstep_volume
	_stamp_landed()

	AudioUtil.play_with_pitch(_audio_player)

func _play_servo(_pos, _normal) -> void:
	if _step_effect_suppressed(true):
		return

	_servo_player.volume_db = servo_volume
	_stamp_servo()

	AudioUtil.play_with_pitch(_servo_player)

func _shake_camera(_pos: Vector3, _normal: Vector3) -> void:
	if _step_effect_suppressed(false):
		return

	_stamp_landed()
	var trauma = player.sprint_step_trauma if player.is_sprinting() else player.step_trauma
	player.camera_controller.add_trauma(trauma)

func get_step_distance() -> float:
	if step_target == null:
		return INF
	return (step_target - ground_probe.global_position).length()

func get_wall_hit_pos(velocity: Vector3) -> Variant:
	var wall_probe_pos := wall_probe.global_position
	# yaw-only direction: ignores tilt_pivot lean so wall rays stay perpendicular
	var cast_dir := -player.basis.z
	var cast_pos = wall_probe_pos + raycast_config.anchor_lead_time * velocity
	var hit = get_surface_hit(cast_pos, cast_dir, raycast_config.wall_raycast_distance)
	return hit

func update_wall_climb(velocity: Vector3) -> Variant:
	var hit = get_wall_hit_pos(velocity)
	step_target = null
	if hit != null:
		# keep wall_surface_normal in sync with what we actually grip
		wall_surface_normal = hit.normal
		var hit_pos: Vector3 = hit.position
		var distance := (hit_pos - arm.target_world).length()
		if distance > raycast_config.max_target_displacement:
			step_target = hit_pos
	elif not arm.is_moving:
		# not touching anything and not mid-step: not a valid grip
		wall_surface_normal = Vector3.ZERO
	# the grip is world-static, so re-project it into the moving mount's local space
	update_planted_target()
	return hit

func get_surface_hit(from: Vector3, direction: Vector3, distance: float) -> Variant:
	var space := get_world_3d().direct_space_state
	return RaycastUtil.shape_cast(space, _cast_sphere, from, direction * distance, ~2)

func set_target(world_pos: Vector3) -> void:
	if arm:
		arm.target_world = world_pos
		arm.target = arm.to_local(world_pos)

func set_apply_floor(should_apply: bool) -> void:
	arm.solver.should_apply_floor = should_apply
