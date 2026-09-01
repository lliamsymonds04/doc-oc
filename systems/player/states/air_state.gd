class_name AirState
extends PlayerState

const HAND_VELOCITY_OFFSET_SCALE: float = 0.05
const HAND_VELOCITY_OFFSET_MAX: float = 1.0

const TILT_PIVOT_ROTATION_SPEED: float = 60.0
const TILT_PIVOT_ROTATION_SCALE : float = 0.02
const TILT_FORWARD_LIMIT: float = deg_to_rad(30.0)
const TILT_BACKWARD_LIMIT: float = deg_to_rad(30.0)
const TILT_SIDEWAYS_LIMIT: float = deg_to_rad(20.0)
const LANDING_TRAUMA: float = 0.6
const HARD_LANDING_SPEED: float = -15.0
const HARD_LANDING_TRAUMA_MULTIPLIER: float = 1.5

var _audio_player: AudioStreamPlayer3D
var light_landing_sound := preload("res://assets/audio/light_landing.ogg")
var hard_landing_sound := preload("res://assets/audio/hard_landing.ogg")

func _init(p: PlayerController) -> void:
	super._init(p)

	# create sound player
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.top_level = true
	p.add_child(_audio_player)

func enter() -> void:
	var p := player

	for mount in p.all_mounts():
		var idle_pos = mount.compute_idle_target()

		mount.arm.target = idle_pos
		mount.set_apply_floor(false)

func calculate_hand_velocity_offset(velocity: Vector3) -> Vector3:
	var mag = velocity.length()
	var new_mag = min(mag * HAND_VELOCITY_OFFSET_SCALE, HAND_VELOCITY_OFFSET_MAX)
	return velocity.normalized() * new_mag

func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt

	_update_tilt(dt)
	_update_arms()

	var direction := p.camera_controller.get_input_direction(input_dir)

	var hvel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var speed := hvel.length()

	if speed > p.air_speed:
		# Fast: bleed off excess speed, then steer with what's left.
		if p.air_drag > 0.0:
			var new_speed := move_toward(speed, p.air_speed, p.air_drag * dt)
			hvel *= new_speed / speed
			speed = new_speed
		if direction.length_squared() > 0.0:
			# Heavy feel: turn authority fades as speed rises above air_speed.
			var authority: float = clampf(p.air_speed / speed, p.min_turn_authority, 1.0)
			var angle := hvel.signed_angle_to(direction, Vector3.UP)
			var turn: float = minf(p.air_turn_speed * authority * dt, absf(angle))
			hvel = hvel.rotated(Vector3.UP, signf(angle) * turn)
	else:
		# Slow: normal control.
		if direction.length_squared() > 0.0:
			hvel = hvel.lerp(direction * p.air_speed, dt * p.air_accel)
		else:
			hvel = hvel.lerp(Vector3.ZERO, dt * p.air_accel)

	p.velocity.x = hvel.x
	p.velocity.z = hvel.z

	var is_grounded = _check_grounded()
	if is_grounded:
		return

	p.mount_prober.try_mount_wall(input_dir, p.velocity)

func _update_tilt(dt: float) -> void:
	var p := player

	var velocityRotation := p.velocity.y * TILT_PIVOT_ROTATION_SCALE

	if velocityRotation < -TILT_FORWARD_LIMIT:
		velocityRotation = -TILT_FORWARD_LIMIT
	if velocityRotation > TILT_BACKWARD_LIMIT:
		velocityRotation = TILT_BACKWARD_LIMIT

	p.rotation.y = p.camera_controller.global_rotation.y
	p.camera_controller.rotation.y = 0

	var current_rot_x := p.tilt_pivot.rotation.x
	var new_rot_x = lerp(current_rot_x, velocityRotation, dt * TILT_PIVOT_ROTATION_SPEED)
	p.tilt_pivot.rotation.x = new_rot_x

	# sideways tilt
	var right: Vector3 = p.global_transform.basis.x
	var side_speed: float = p.velocity.dot(right)
	var current_rot_z := p.tilt_pivot.rotation.z
	var target_rot_z = min(-side_speed * TILT_PIVOT_ROTATION_SCALE, TILT_SIDEWAYS_LIMIT)
	var new_rot_z = lerp(current_rot_z, target_rot_z, dt * TILT_PIVOT_ROTATION_SPEED)
	p.tilt_pivot.rotation.z = new_rot_z

func _update_arms() -> void:
	var p := player

	var hand_velocity_offset = calculate_hand_velocity_offset(p.velocity)
	for mount in p.all_mounts():
		mount.arm.target = mount.compute_idle_target() + hand_velocity_offset

func _check_grounded() -> bool:
	var p := player

	var probe_hits := p.mount_prober.get_leg_probe_hits()
	if probe_hits.size() >= 1 and p.velocity.y <= 0.0:
		for mount in p.leg_mounts:
			if probe_hits.has(mount):
				var hit_pos: Vector3 = probe_hits[mount]["position"]
				if hit_pos:
					mount.set_target(hit_pos)

			else:
				mount.sync_from_arm()

		for mount in p.arm_mounts:
			mount.set_target(mount.compute_idle_target())

		_transition_to_grounded()

		return true

	return false

func _transition_to_grounded() -> void:
	var p := player
	p.set_state(p.StateID.GROUNDED)

	var trauma := LANDING_TRAUMA
	if p.velocity.y <= HARD_LANDING_SPEED:
		_audio_player.stream = hard_landing_sound
		trauma *= HARD_LANDING_TRAUMA_MULTIPLIER
	else:
		_audio_player.stream = light_landing_sound
	AudioUtil.play_with_pitch(_audio_player)

	p.camera_controller.add_trauma(trauma)
