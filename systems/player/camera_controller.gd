class_name CameraController
extends SpringArm3D

const CAMERA_GROUP := &"camera_controller"
const IMPACT_BLEND_RATE := 24.0

@export var sensitivity: float = 0.02

@export_category("Trauma")
@export var max_trauma_offset: float = 0.25
@export var max_trauma_roll: float = 3.5

@export_category("Fov")
@export var base_fov: float = 75.0
@export var max_fov: float = 94.0
@export var speed_at_max_fov: float = 22.0
@export var fov_change_rate: float = 4.0
@export_range(0.1, 4.0, 0.05) var fov_curve_exponent: float = 1.0
@export var fov_kick_recovery: float = 2.8

@export_category("Trail")
@export var trail_strength: float = 0.06  # forward/back (local Z)
@export var trail_strength_side: float = 0.1  # strafing (local X)
@export var trail_strength_vert: float = 0.02  # jumping/falling (local Y)
@export var trail_rate: float = 5.0
@export var max_trail: float = 0.8
@export var max_trail_side: float = 1.0
@export var max_trail_vert: float = 0.3

@export_category("Sprint")
@export var sprint_blend_rate: float = 5.0
@export var sprint_y_offset: float = 2.0
@export var sprint_pitch_offset_deg = 12.0

@export_category("Attack Aim")
@export var aim_pitch_offset_deg: float = 15.0
@export var aim_fov: float = 60.0
@export var aim_blend_rate: float = 8.0
@export var aim_forward_offset: float = 2.0
@export var aim_up_offset: float = 1.5

@export_category("Rear View")
## Camera yaw relative to the body at which the body stops turning with the camera,
## so an orbiting camera looking back sees the character's front. 180 = directly ahead.
@export var rear_view_deg: float = 150.0
## Camera yaw at which camera-driven body lean starts fading out toward that limit.
@export var rear_view_blend_deg: float = 120.0

@export_category("Hit")
@export var cast_sphere_radius: float = 0.1

## Raw mouse delta accumulated since the last physics tick (pixels). Snapshot of
## _pending_mouse published for systems that need mouse motion without owning the accumulator.
var mouse_delta_physics := Vector2.ZERO
var wheel_delta_physics := 0.0

var _trauma: float = 0.0
var _shake_time := 0.0
var _shake_noise := FastNoiseLite.new()
var _current_speed: float = 0.0
var _fov_kick: float = 0.0
var _speed_fov: float
var _impact_fov := 0.0
var _damage_roll := 0.0
var _impact_roll := 0.0
var _slam_fov := 0.0
var _slam_jolt := 0.0
var _impact_y := 0.0
var _trail := Vector3.ZERO
var _pending_mouse := Vector2.ZERO
var _pending_wheel := 0.0  # notches since last physics tick, + = wheel-up

var _sprinting: bool = false
var _sprint_weight: float = 0.0
var _aim_weight: float = 0.0

var _cast_sphere: SphereShape3D

# CameraOffset exists so the SpringArm can own its transform
# CameraShakePivot below it is free for effects
@onready var camera_pivot: Node3D = $CameraOffset/CameraShakePivot
@onready var cam: Camera3D = $CameraOffset/CameraShakePivot/Camera3D
@onready var _player: PlayerController = get_parent()


func _ready() -> void:
	add_to_group(CAMERA_GROUP)
	# Yaw must land before the player's alignment step in the same tick, or the body
	# runs a tick behind the camera and its limbs jitter against the view.
	process_physics_priority = -1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam.fov = base_fov
	_speed_fov = base_fov
	_shake_noise.frequency = 1.0
	_shake_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

	_cast_sphere = SphereShape3D.new()
	_cast_sphere.radius = cast_sphere_radius


func add_trauma(amount: float, peak: float = 1.0) -> void:
	_trauma = minf(_trauma + amount, maxf(_trauma, peak))


func kick_fov(amount: float) -> void:
	_fov_kick = amount


func kick_damage_roll(hit_dir: Vector3, weight: float) -> void:
	_damage_roll = -hit_dir.normalized().dot(get_flat_basis().x) * 2.4 * weight


func play_heavy_impact(strength := 1.0) -> void:
	var trauma := 1.35 * strength
	add_trauma(trauma, trauma)
	_slam_fov = minf(_slam_fov, -12.0 * strength)
	_slam_jolt = minf(_slam_jolt, -0.18 * strength)


func set_current_speed(value: float) -> void:
	_current_speed = max(value, 0.0)


func set_sprinting(active: bool) -> void:
	_sprinting = active


func get_speed() -> float:
	return _current_speed


func get_player() -> PlayerController:
	return _player


func get_camera_direction() -> Vector3:
	return -cam.global_transform.basis.z


func get_pitch() -> float:
	return asin(get_camera_direction().y)


func update_motion(dt: float, velocity: Vector3) -> void:
	var local_vel: Vector3 = global_transform.basis.inverse() * velocity

	var target := Vector3(
		clampf(-local_vel.x * trail_strength_side, -max_trail_side, max_trail_side),
		clampf(-local_vel.y * trail_strength_vert, -max_trail_vert, max_trail_vert),
		clampf(-local_vel.z * trail_strength, -max_trail, max_trail)
	)
	_trail = _trail.lerp(target, 1.0 - exp(-trail_rate * dt))

	var aim_offset := -get_flat_basis().z * aim_forward_offset + Vector3.UP * aim_up_offset
	var world_offset := Vector3.UP * sprint_y_offset * _sprint_weight + aim_offset * _aim_weight
	camera_pivot.position = _trail + global_transform.basis.inverse() * world_offset


func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, global_rotation.y)


func is_rear_view() -> bool:
	return absf(rotation.y) >= deg_to_rad(rear_view_deg)


## 0 below rear_view_blend_deg, 1 at rear_view_deg, smooth in between.
func rear_view_blend() -> float:
	return smoothstep(deg_to_rad(rear_view_blend_deg), deg_to_rad(rear_view_deg), absf(rotation.y))


func get_camera_center_hit(dist: float = 1000.0, offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var cam_pos = cam.global_position + offset
	var dir = get_camera_direction()
	var motion = dir * dist
	var space := get_world_3d().direct_space_state
	var hit_result = RaycastUtil.shape_cast(
		space, _cast_sphere, cam_pos, motion, _player.cast_mask()
	)

	return hit_result if hit_result != null else {}


func _process(dt: float) -> void:
	_shake_time += dt * 12.0
	if _trauma > 0:
		_trauma = maxf(_trauma - dt * 2.0, 0.0)
		var shake := pow(_trauma, 1.5)
		cam.position = Vector3(
			_shake_noise.get_noise_2d(_shake_time, 0.0) * max_trauma_offset * shake,
			_shake_noise.get_noise_2d(_shake_time, 17.0) * max_trauma_offset * shake,
			0.0
		)
		cam.rotation_degrees.z = (
			_shake_noise.get_noise_2d(_shake_time, 31.0) * max_trauma_roll * shake
		)
	else:
		cam.position = Vector3.ZERO
		cam.rotation_degrees.z = 0.0

	var impact_blend := 1.0 - exp(-IMPACT_BLEND_RATE * dt)
	_impact_y = lerpf(_impact_y, _slam_jolt, impact_blend)
	_impact_roll = lerpf(_impact_roll, _damage_roll, impact_blend)
	cam.position.y += _impact_y
	cam.rotation_degrees.z += _impact_roll
	_slam_jolt *= exp(-8.0 * dt)
	_damage_roll *= exp(-6.0 * dt)

	_sprint_weight = lerpf(
		_sprint_weight, 1.0 if _sprinting else 0.0, 1.0 - exp(-sprint_blend_rate * dt)
	)

	var want_aim := (
		Input.is_action_pressed("right-click") and not _player.is_in_grab_mode() and not _sprinting
	)
	_aim_weight = lerpf(_aim_weight, 1.0 if want_aim else 0.0, 1.0 - exp(-aim_blend_rate * dt))
	_update_fov(dt)

	cam.rotation_degrees.x = -(
		sprint_pitch_offset_deg * _sprint_weight + aim_pitch_offset_deg * _aim_weight
	)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pending_mouse += event.relative
	elif (
		event is InputEventMouseButton
		and event.pressed
		and (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
	):
		_pending_wheel += (
			event.factor * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		)


func _update_fov(dt: float) -> void:
	var slamming := _player.is_airborne() and _player.air_state().is_slamming()
	if slamming:
		# Ignore the dive's horizontal speed so angled and vertical slams get the same kick.
		_slam_fov = 8.0
	else:
		var speed_fraction := minf(_current_speed / speed_at_max_fov, 1.0)
		var motion_fov := lerpf(base_fov, max_fov, pow(speed_fraction, fov_curve_exponent))
		_speed_fov = lerpf(_speed_fov, motion_fov, 1.0 - exp(-fov_change_rate * dt))

	_impact_fov = lerpf(_impact_fov, _fov_kick + _slam_fov, 1.0 - exp(-IMPACT_BLEND_RATE * dt))
	cam.fov = lerpf(_speed_fov, aim_fov, _aim_weight) + _impact_fov
	var recovery := exp(-fov_kick_recovery * dt)
	_fov_kick *= recovery
	if not slamming:
		_slam_fov *= recovery


func _physics_process(_dt: float) -> void:
	rotation_degrees.y -= _pending_mouse.x * sensitivity
	rotation_degrees.x -= _pending_mouse.y * sensitivity
	rotation_degrees.x = clampf(rotation_degrees.x, -70, 70)
	rotation.y = wrapf(rotation.y, -PI, PI)
	mouse_delta_physics = _pending_mouse
	_pending_mouse = Vector2.ZERO
	wheel_delta_physics = _pending_wheel
	_pending_wheel = 0.0


func get_input_direction(input_dir: Vector2) -> Vector3:
	var b := get_flat_basis()
	var direction := b.x * input_dir.x + b.z * input_dir.y
	if direction.length_squared() > 0.0:
		return direction.normalized()
	return direction
