extends RefCounted
class_name PlayerGrabController

var player: PlayerController
var last_attack_time: float = -INF
var config: PlayerGrabConfig

var grabs: Dictionary = {}  # mount -> body
var grab_offsets: Dictionary = {}  # mount -> body-local grip point; fixed at grab time
var hold_offsets: Dictionary = {}  # mount -> mount-local hold position; mouse drag moves this
var grab_relative_rotations: Dictionary = {}  # body -> Quaternion (body basis relative to player basis); fixed at the first grab
var original_layers: Dictionary = {}  # body -> original collision_layer
var _mouse_up_speed := 0.0  # smoothed upward mouse pixels per physics tick, for the release flick
var _grab_audio_player: AudioStreamPlayer3D

func _init(p: PlayerController, grab_config: PlayerGrabConfig) -> void:
	player = p
	config = grab_config

	_grab_audio_player = AudioStreamPlayer3D.new()
	_grab_audio_player.stream = config.grab_sound
	p.add_child(_grab_audio_player)

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected.bind(mount))

func try_grab(side_dir: int) -> void:
	var now = _get_now()
	if not PlayerPunchUtil.punch_allowed(player, last_attack_time, config.grab_debounce, now):
		return

	var p := player

	var mount := _get_mount_for_side(side_dir)
	if mount == null or is_mount_grabbing(mount):
		return

	var target = _get_target(side_dir)  # same aim-point math as attack

	# fast path: join instantly when the crosshair rests on a body the other arm holds;
	# otherwise the punch below sweeps with a HELD_LAYER-inclusive mask and joins at contact
	var join_hit := _aimed_held_body(config.grab_cast_range)
	if not join_hit.is_empty():
		_register_grab(mount, join_hit["collider"] as RigidBody3D, join_hit["position"])
		last_attack_time = now
		return

	# mask includes HELD_LAYER so the sweep can join a body the other arm already holds
	mount.arm.start_punch(target, ~player.collision_layer)
	AudioUtil.play_with_pitch(_grab_audio_player)
	last_attack_time = now

func release_grab(side_dir: int) -> void:
	_release_mount(_get_mount_for_side(side_dir))

## Mode switch can end a hold without a mouse release; drop every grab so each
## arm's pole constraints and each body's collision layer are restored.
func release_all() -> void:
	for mount in grabs.keys():
		_release_mount(mount as ArmMount)

func _release_mount(mount: ArmMount) -> void:
	if mount == null or not is_mount_grabbing(mount):
		return

	var body: RigidBody3D = grabs[mount]

	# flick skipped while the other arm still holds the body; the servo
	# overwrites its velocity every tick
	var still_held := false
	for m in grabs:
		if m != mount and grabs[m] == body:
			still_held = true
			break
	if not still_held and _mouse_up_speed > config.RELEASE_MOUSE_UP_THRESHOLD:
		var throw_speed := clampf(_mouse_up_speed * config.RELEASE_THROW_SENS, 0.0, config.RELEASE_THROW_MAX_SPEED)
		var throw_dir := -player.camera_controller.get_flat_basis().z
		# release runs outside the physics loop, so the servo's last chase velocity
		# is stale; zero its vertical part or it dominates the throw
		body.linear_velocity.y = 0.0
		body.linear_velocity += throw_dir * throw_speed
		body.linear_velocity.y += maxf(config.THROW_RELEASE_VELOCITY_Y - throw_speed * config.THROW_Y_Z_DROPOFF,
			config.THROW_RELEASE_VELOCITY_Y_MIN)
	_mouse_up_speed = 0.0

	grabs.erase(mount)
	grab_offsets.erase(mount)
	hold_offsets.erase(mount)
	if not grabs.values().has(body):
		grab_relative_rotations.erase(body)
		body.collision_layer = original_layers[body]
		original_layers.erase(body)
	mount.set_apply_pole(true)
	# the per-tick set_apply_floor(false) in physics_update only gets restored here;
	# air keeps the floor off so dangling arms match AirState.enter
	mount.set_apply_floor(not player.is_airborne())

func physics_update(mouse_delta: Vector2, wheel_delta := 0.0) -> void:
	_sample_mouse_y_speed(mouse_delta)
	_apply_mouse_drag(mouse_delta, wheel_delta)
	# two arms on one body: per-mount body writes would overwrite the other arm's error
	var err_sum := {}    # body -> Vector3
	var err_count := {}  # body -> int

	for mount in grabs.keys():
		if not is_mount_grabbing(mount):
			continue
		if not mount in grab_offsets:
			continue
		var body: RigidBody3D = grabs[mount]
		var offset: Vector3 = grab_offsets[mount]

		var grip_world: Vector3 = body.to_global(offset)
		var anchor: Vector3 = mount.to_global(hold_offsets[mount])

		mount.set_target(grip_world)
		mount.set_apply_floor(false)

		var error := anchor - grip_world
		err_sum[body] = err_sum.get(body, Vector3.ZERO) + error
		err_count[body] = err_count.get(body, 0) + 1

	for body_key in err_sum:
		var body := body_key as RigidBody3D
		body.linear_velocity = (err_sum[body] / err_count[body]) * 15

		# rotation servo: keep the body's orientation locked relative to the player
		var target_q: Quaternion = player.global_transform.basis.get_rotation_quaternion() \
			* (grab_relative_rotations[body] as Quaternion)
		var current_q := body.global_transform.basis.get_rotation_quaternion()

		# delta in WORLD frame: target = q_err * current, because angular_velocity is global-space
		var q_err := target_q * current_q.inverse()
		if q_err.w < 0.0:
			q_err = -q_err  # take the shortest path around

		var axis := Vector3(q_err.x, q_err.y, q_err.z)
		var angle := q_err.get_angle()
		if angle > 0.001 and axis.length() > 0.001:
			body.angular_velocity = (axis.normalized() * angle * config.ROTATION_SERVO_GAIN).limit_length(config.MAX_GRAB_SPIN)
		else:
			body.angular_velocity = Vector3.ZERO

## Mouse X = lateral (flat cam X), mouse Y = height (world UP), wheel = depth
## (flat cam Z; wheel-up pushes the body away, wheel-down pulls it in).
func _apply_mouse_drag(mouse_delta: Vector2, wheel_delta: float) -> void:
	if mouse_delta == Vector2.ZERO and is_zero_approx(wheel_delta):
		return
	if grabs.is_empty():
		return

	if not player.is_idle():
		return

	var cam_basis: Basis = player.camera_controller.get_flat_basis()
	var world_delta: Vector3 = \
		cam_basis.x * mouse_delta.x * config.HOLD_DRAG_SENS_X * player.camera_controller.sensitivity + \
		-Vector3.UP * mouse_delta.y * config.HOLD_DRAG_SENS_Y * player.camera_controller.sensitivity + \
		-cam_basis.z * wheel_delta * config.HOLD_WHEEL_SENS

	for mount in grabs:
		var local_delta: Vector3 = mount.global_transform.basis.inverse() * world_delta
		var default := _default_hold_offset(mount)
		var moved: Vector3 = (hold_offsets[mount] as Vector3) + local_delta - default
		var new_offset := default + moved.limit_length(config.MAX_HOLD_DRAG)
		hold_offsets[mount] = new_offset

func _default_hold_offset(mount: ArmMount) -> Vector3:
	return Vector3(config.HOLD_OFFSET.x * sign(mount.position.x), config.HOLD_OFFSET.y, config.HOLD_OFFSET.z)

## Exponential average of upward mouse pixels per physics tick while holding;
## read at release so an upward stroke right before letting go throws the body.
func _sample_mouse_y_speed(mouse_delta: Vector2) -> void:
	if grabs.is_empty():
		_mouse_up_speed = 0.0
		return
	# input stores Y down-positive; flip so up-mouse increases the tracker
	var sample := maxf(-mouse_delta.y, 0.0)
	_mouse_up_speed = lerpf(_mouse_up_speed, sample, config.RELEASE_MOUSE_SAMPLE)

func _get_target(side_dir: int = 0) -> Vector3:
	return PlayerPunchUtil.get_punch_target(player, side_dir, config.grab_cast_range)

func _get_mount_for_side(side_dir: int) -> ArmMount:
	for mount in player.arm_mounts:
		if sign(mount.position.x) == side_dir:
			return mount
	return null

## Returns the full ray hit for a held body under the crosshair, or an empty Dictionary.
## Keeps hit["position"] so the joining arm can grip the actual surface point.
func _aimed_held_body(max_dist: float) -> Dictionary:
	var from := player.camera_controller.cam.global_position
	var to := from + player.camera_controller.get_camera_direction() * max_dist
	# includes HELD_LAYER, unlike cast_mask
	var params := PhysicsRayQueryParameters3D.create(from, to, ~player.collision_layer)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return {}
	var collider = hit["collider"]
	return hit if grabs.values().has(collider) else {}

## grab_offsets values are body-local; physics_update does body.to_global(offset).
func _register_grab(mount: ArmMount, body: RigidBody3D, hit_pos: Vector3) -> void:
	# hit_pos is a real body surface contact, not the hold anchor
	grab_offsets[mount] = body.to_local(hit_pos)
	hold_offsets[mount] = _default_hold_offset(mount)
	# first grab on a body fixes its held orientation; a second arm keeps that lock
	if not grab_relative_rotations.has(body):
		grab_relative_rotations[body] = \
			player.global_transform.basis.get_rotation_quaternion().inverse() \
			* body.global_transform.basis.get_rotation_quaternion()
	grabs[mount] = body
	# pole off for the hold: the elbow keeps its bend plane instead of being re-aimed
	mount.set_apply_pole(false)


func arm_hit_detected(hit: Vector3, _normal: Vector3, collider: Object, mount: ArmMount) -> void:
	if not player.is_in_grab_mode():
		return

	if not collider is RigidBody3D:
		return

	if grabs.has(mount):
		return

	var body = collider as RigidBody3D
	_register_grab(mount, body, hit)
	# HELD_LAYER kills the player-vs-body pair: the player's mask doesn't include it
	if not original_layers.has(body):
		original_layers[body] = body.collision_layer
	body.collision_layer = player.HELD_LAYER

func is_mount_grabbing(mount: ArmMount) -> bool:
	return grabs.has(mount)

## Per render frame: re-aim grabbing arms using the interpolated mount/body transforms.
## physics_update bakes the grip target with authoritative transforms at physics tick rate;
## with physics interpolation on, that target oscillates against what is rendered.
func frame_update() -> void:
	for mount in grabs:
		if not mount in grab_offsets:
			continue
		var body: RigidBody3D = grabs[mount]
		var grip_world: Vector3 = body.get_global_transform_interpolated() \
			* (grab_offsets[mount] as Vector3)
		var arm: BasicArm = mount.arm
		arm.target = arm.get_global_transform_interpolated().affine_inverse() * grip_world

func is_grabbing() -> bool:
	return not grabs.is_empty()

func _get_now() -> float:
	return PlayerPunchUtil.get_now()
