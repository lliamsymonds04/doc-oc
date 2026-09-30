class_name AirState
extends PlayerState

var _audio_player: AudioStreamPlayer3D
var light_landing_sound := preload("res://assets/audio/light_landing.ogg")
var hard_landing_sound := preload("res://assets/audio/hard_landing.ogg")

var landing_vfx_scene := preload("res://assets/vfx/landing_vfx.tscn")
var _landing_vfx: ImpactVFX

var air_debounce := 0.0

func _init(p: PlayerController) -> void:
	super._init(p)

	# create sound player
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.top_level = true
	p.add_child(_audio_player)

	# create landing vfx
	_landing_vfx = landing_vfx_scene.instantiate() as ImpactVFX
	_landing_vfx.top_level = true
	p.add_child(_landing_vfx)

func enter() -> void:
	var p := player
	air_debounce = p.air.air_debounce

	for mount in p.all_mounts():
		mount.set_apply_floor(false)

func calculate_hand_velocity_offset(velocity: Vector3) -> Vector3:
	var c := player.air
	var mag = velocity.length()
	var new_mag = min(mag * c.hand_velocity_offset_scale, c.hand_velocity_offset_max)
	return velocity.normalized() * new_mag

func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt

	_update_tilt(dt)
	_update_camera_alignment(dt)

	var direction := p.camera_controller.get_input_direction(input_dir)

	var hvel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var speed := hvel.length()

	if speed > p.air.air_speed:
		# Fast: bleed off excess speed, then steer with what's left.
		if p.air.air_drag > 0.0:
			var new_speed := move_toward(speed, p.air.air_speed, p.air.air_drag * dt)
			hvel *= new_speed / speed
			speed = new_speed
		if direction.length_squared() > 0.0:
			# Heavy feel: turn authority fades as speed rises above air_speed.
			var authority: float = clampf(p.air.air_speed / speed, p.air.min_turn_authority, 1.0)
			var angle := hvel.signed_angle_to(direction, Vector3.UP)
			var turn: float = minf(p.air.air_turn_speed * authority * dt, absf(angle))
			hvel = hvel.rotated(Vector3.UP, signf(angle) * turn)
	else:
		# Slow: normal control.
		if direction.length_squared() > 0.0:
			hvel = hvel.lerp(direction * p.air.air_speed, dt * p.air.air_accel)
		else:
			hvel = hvel.lerp(Vector3.ZERO, dt * p.air.air_accel)

	p.velocity.x = hvel.x
	p.velocity.z = hvel.z

	if air_debounce > 0.0:
		air_debounce -= dt
		return
	else:
		var is_grounded = _check_grounded()
		if is_grounded:
			return

	var wall_mounted = p.mount_prober.try_mount_wall(input_dir, p.velocity)
	if wall_mounted:
		_play_landed_effect()

func _update_camera_alignment(dt: float) -> void:
	var p := player
	var target_yaw := p.camera_controller.global_rotation.y
	var new_yaw := lerp_angle(p.rotation.y, target_yaw, p.air.air_turn_speed * dt)
	var delta := angle_difference(p.rotation.y, new_yaw)

	p.rotation.y = new_yaw
	p.camera_controller.rotation.y -= delta

func _update_tilt(dt: float) -> void:
	var p := player

	var velocityRotation := p.velocity.y * p.air.air_tilt_rotation_scale
	var forward_limit := deg_to_rad(p.air.air_tilt_forward_limit_deg)
	var backward_limit := deg_to_rad(p.air.air_tilt_backward_limit_deg)

	if velocityRotation < -forward_limit:
		velocityRotation = -forward_limit
	if velocityRotation > backward_limit:
		velocityRotation = backward_limit


	var current_rot_x := p.tilt_pivot.rotation.x
	var new_rot_x = lerp(current_rot_x, velocityRotation, dt * p.air.air_tilt_rotation_speed)
	p.tilt_pivot.rotation.x = new_rot_x

	# sideways tilt
	var right: Vector3 = p.global_transform.basis.x
	var side_speed: float = p.velocity.dot(right)
	var sideways_limit := deg_to_rad(p.air.air_tilt_sideways_limit_deg)
	var current_rot_z := p.tilt_pivot.rotation.z
	var target_rot_z = min(-side_speed * p.air.air_tilt_rotation_scale, sideways_limit)
	var new_rot_z = lerp(current_rot_z, target_rot_z, dt * p.air.air_tilt_rotation_speed)
	p.tilt_pivot.rotation.z = new_rot_z

func frame_update(dt: float) -> void:
	var p := player

	var world_offset := calculate_hand_velocity_offset(p.velocity)
	for mount in p.all_mounts():
		if p.grab_controller.is_mount_grabbing(mount):
			continue
		mount.update_idle_target(dt, p.air.arm_target_speed, world_offset)

func _check_grounded() -> bool:
	var p := player

	var probe_hits := p.mount_prober.get_leg_probe_hits()
	if probe_hits.size() >= 1 and p.velocity.y <= 0.0:
		for mount in p.leg_mounts:
			if probe_hits.has(mount):
				var hit_pos: Vector3 = probe_hits[mount]["position"]
				if hit_pos:
					mount.set_target(hit_pos)

		for mount in p.arm_mounts:
			if p.grab_controller.is_mount_grabbing(mount):
				continue
			mount.set_target(mount.to_global(mount.compute_idle_target()))

		p.set_state(p.StateID.GROUNDED)
		_play_landed_effect()

		return true

	return false

func _play_landed_effect() -> void:
	var p := player

	var trauma := p.air.landing_trauma
	var speed = p.velocity.length()
	var is_hard_landing = speed >= p.air.hard_landing_speed

	if is_hard_landing:
		_audio_player.stream = hard_landing_sound
		trauma *= p.air.hard_landing_trauma_multiplier
	else:
		_audio_player.stream = light_landing_sound

	AudioUtil.play_with_pitch(_audio_player)
	p.camera_controller.add_trauma(trauma)

	var v_dir := p.velocity.normalized()
	# cast from the player in direction of velocity
	var space_state = p.get_world_3d().direct_space_state
	var player_pos := p.position
	var query := PhysicsRayQueryParameters3D.create(player_pos, player_pos + v_dir * p.air.landing_vfx_raycast_distance, p.cast_mask())
	var result = space_state.intersect_ray(query)

	if result:
		_landing_vfx.play(result.position, result.normal)
