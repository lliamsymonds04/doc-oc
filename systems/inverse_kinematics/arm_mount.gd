extends Node3D
class_name ArmMount

@export var is_leg: bool = true
# the mount above this
@export var vertical_mount: ArmMount
# the mount to the side of this
@export var horizontal_mount: ArmMount

@export var footstep_volume: float = -5.0
@export var footstep_effect_debounce: float = 0.15

@export var servo_volume: float = -15.0
@export var servo_debounce: float = 0.1

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
var step_effect_debounce: float = 0.0
var last_effect_time: float = -INF

var target_world: Vector3
var _cached_target_world: Vector3

func _process(dt: float) -> void:
	_sway_time += dt
	if step_effect_debounce > 0.0:
		step_effect_debounce -= dt

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

func _step_effect_suppressed() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return now - horizontal_mount.last_effect_time < EFFECT_SAME_BEAT_WINDOW \
		or now - diagonal_mount.last_effect_time < EFFECT_SAME_BEAT_WINDOW

func _stamp_effect() -> void:
	last_effect_time = Time.get_ticks_msec() / 1000.0

func _play_landed_sound(pos, _normal) -> void:
	if _step_effect_suppressed():
		return

	_audio_player.reset_physics_interpolation()
	_audio_player.position = pos
	_audio_player.volume_db = footstep_volume
	step_effect_debounce = footstep_effect_debounce
	_stamp_effect()

	AudioUtil.play_with_pitch(_audio_player)

func _play_servo(_pos, _normal) -> void:
	if _step_effect_suppressed():
		return

	_servo_player.volume_db = servo_volume
	step_effect_debounce = servo_debounce
	_stamp_effect()

	AudioUtil.play_with_pitch(_servo_player)

func _shake_camera(_pos: Vector3, _normal: Vector3) -> void:
	if _step_effect_suppressed():
		return

	step_effect_debounce = footstep_effect_debounce
	_stamp_effect()
	var trauma = player.sprint_step_trauma if player.is_sprinting() else player.step_trauma
	player.camera_controller.add_trauma(trauma)

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

func update_ground_step_target(velocity: Vector3) -> void:
	step_target = null

	_cached_target_world = target_world
	var velocity_xz := Vector3(velocity.x, 0, velocity.z) * raycast_config.anchor_lead_time
	var probe_pos := ground_probe.global_position + velocity_xz
	var hit = get_surface_hit(probe_pos, Vector3.DOWN, raycast_config.step_raycast_distance)
	if hit != null and hit.normal.angle_to(Vector3.UP) <= MAX_GROUND_NORMAL_ANGLE:
		var hit_pos: Vector3 = hit.position
		var disp := (hit_pos - _cached_target_world).length()
		if disp > raycast_config.max_target_displacement:
			step_target = hit_pos
	set_target(_cached_target_world)

func update_step(velocity: Vector3, dt: float) -> void:
	step_target = null

	if arm.is_stepping:
		arm.advance_step(dt)
		sync_from_arm()
		return

	if is_leg:
		update_ground_step_target(velocity)
	elif idle_target != null:
		arm.target = compute_idle_target()

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
