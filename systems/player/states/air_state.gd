class_name AirState
extends PlayerState

const SLAM_IMPACT_VFX := preload("res://assets/vfx/ground_slam_impact.tscn")

var light_landing_sound := preload("res://assets/audio/light_landing.ogg")
var hard_landing_sound := preload("res://assets/audio/hard_landing.ogg")
var landing_vfx_scene := preload("res://assets/vfx/landing_vfx.tscn")
var air_debounce := 0.0
var launch_grace := 0.0

# gravity arc for this air entry; enter() defaults it, begin_launch() shapes it for a jump
var jump_gravity_multiplier := 1.0
var fall_gravity_multiplier := 1.0

var _air_time := 0.0
var _slam_distance_left := 0.0
var _audio_player: AudioStreamPlayer3D
var _slam_wind: AudioStreamPlayer
var _slam_wind_tween: Tween
var _landing_vfx: ImpactVFX


func _init(p: PlayerController) -> void:
	super._init(p)

	# create sound player
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.top_level = true
	p.add_child(_audio_player)

	_slam_wind = AudioStreamPlayer.new()
	_slam_wind.stream = preload("res://assets/audio/ground_slam_wind.ogg")
	p.add_child(_slam_wind)

	# create landing vfx
	_landing_vfx = landing_vfx_scene.instantiate() as ImpactVFX
	_landing_vfx.top_level = true
	p.add_child(_landing_vfx)


func enter() -> void:
	var p := player
	air_debounce = p.air.air_debounce

	jump_gravity_multiplier = 1.0
	fall_gravity_multiplier = p.jump.fall_gravity_multiplier
	launch_grace = 0.0
	_air_time = 0.0

	for mount in p.all_mounts():
		mount.set_apply_floor(false)


func exit() -> void:
	cancel_slam()
	# the tackle keeps punching across the landing; its trails must survive
	if player.tackle_controller.is_tackling():
		return
	for mount in player.all_mounts():
		mount.arm.set_end_effector_trail(false)


## Called by GroundedState right after set_state(AIR); the single launch path
## for every jump (dash or hop), so launch-only effects go here, not in enter()
func begin_launch(rising_gravity: float) -> void:
	jump_gravity_multiplier = rising_gravity
	launch_grace = player.air.launch_grace_time

	for mount in player.all_mounts():
		mount.arm.set_end_effector_trail(true)
		mount.arm.set_trail_style(player.air.trail_width, player.air.trail_transparency)


func gravity_scale() -> float:
	var scale := jump_gravity_multiplier
	if player.velocity.y <= 0.0:
		scale *= fall_gravity_multiplier
	return scale


func calculate_hand_velocity_offset(velocity: Vector3) -> Vector3:
	var c := player.air
	var mag = velocity.length()
	var new_mag = min(mag * c.hand_velocity_offset_scale, c.hand_velocity_offset_max)
	return velocity.normalized() * new_mag


func is_slamming() -> bool:
	return _slam_distance_left > 0.0


func cancel_slam() -> void:
	if not is_slamming():
		return
	_slam_distance_left = 0.0
	_slam_wind_tween.kill()
	_slam_wind_tween = _slam_wind.create_tween()
	_slam_wind_tween.tween_property(_slam_wind, "volume_linear", 0.0, 0.12)
	_slam_wind_tween.tween_callback(_slam_wind.stop)


func _play_slam_wind() -> void:
	if _slam_wind_tween != null:
		_slam_wind_tween.kill()
	_slam_wind.volume_linear = 0.0
	_slam_wind.play()
	_slam_wind_tween = _slam_wind.create_tween()
	_slam_wind_tween.tween_property(_slam_wind, "volume_linear", 0.5, 0.08)


static func is_slam_offset_valid(offset: Vector3, config: AirConfig) -> bool:
	return (
		offset.length_squared() <= config.slam_max_distance * config.slam_max_distance
		and offset.normalized().dot(Vector3.DOWN) >= sin(deg_to_rad(config.slam_min_depression_deg))
	)


func get_slam_offset() -> Vector3:
	var p := player
	if _air_time < p.air.slam_min_air_time or p.tackle_controller.is_tackling():
		return Vector3.ZERO

	var camera := p.camera_controller
	var origin := camera.cam.global_position
	var ray_length := p.air.slam_max_distance + origin.distance_to(p.global_position)
	var end := origin + camera.get_camera_direction() * ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, end, p.collision_mask, [p.get_rid()])
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	var min_floor_dot := cos(p.floor_max_angle)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < min_floor_dot:
		return Vector3.ZERO

	var offset: Vector3 = hit.position - p.global_position
	if not is_slam_offset_valid(offset, p.air):
		return Vector3.ZERO

	var impact := p.move_and_collide(offset, true)
	if impact == null or impact.get_normal().dot(Vector3.UP) < min_floor_dot:
		return Vector3.ZERO
	return offset


func move_slam(dt: float) -> void:
	var p := player
	var motion := (p.velocity * dt).limit_length(_slam_distance_left)
	var impact := p.move_and_collide(motion)
	var distance_left := _slam_distance_left - motion.length()
	if impact == null and distance_left > p.safe_margin:
		_slam_distance_left = distance_left
		return

	cancel_slam()
	if impact != null and impact.get_normal().dot(Vector3.UP) >= cos(p.floor_max_angle):
		_slam_impact(impact.get_position(), impact.get_normal())
		_land(p.mount_prober.get_leg_probe_hits(), impact)
		var barrel := impact.get_collider() as ExplosiveBarrel
		if barrel != null:
			barrel.detonate(impact.get_position(), impact.get_normal())
	p.velocity = Vector3.ZERO


func _slam_impact(point: Vector3, normal: Vector3) -> void:
	var p := player
	var parent := p.get_tree().current_scene
	var shockwave := RingEffect.new()
	parent.add_child(shockwave)
	shockwave.play_once(point, p.air.slam_radius, 0.35, normal)
	CrackDecal.spawn(parent, point, normal, 2.5)

	var burst := SLAM_IMPACT_VFX.instantiate() as ImpactVFX
	parent.add_child(burst)
	burst.play(point + normal * 0.2, normal)
	p.get_tree().create_timer(1.4, false).timeout.connect(burst.queue_free)

	var sphere := SphereShape3D.new()
	sphere.radius = p.air.slam_radius
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = sphere
	overlap.transform = Transform3D(Basis.IDENTITY, point)
	overlap.collision_mask = EnemyController.ENEMY_LAYER

	var space := p.get_world_3d().direct_space_state
	var damaged := {}
	for hit in space.intersect_shape(overlap):
		var body := hit.collider as Node3D
		var enemy := EnemyUtil.resolve_enemy(body)
		if enemy == null or enemy.is_dead() or damaged.has(enemy):
			continue

		var cover := PhysicsRayQueryParameters3D.create(
			point + normal * 0.05, body.to_global(enemy.hitbox.position), p.collision_mask
		)
		if not space.intersect_ray(cover).is_empty():
			continue

		damaged[enemy] = true
		enemy.take_damage(p.air.slam_damage)


func physics_update(dt: float) -> void:
	var p := player
	_air_time += dt
	if not is_slamming() and Input.is_action_just_pressed("jump"):
		var offset := get_slam_offset()
		if offset != Vector3.ZERO:
			_slam_distance_left = offset.length()
			p.velocity = offset.normalized() * p.air.slam_speed
			_play_slam_wind()
	var slamming := is_slamming()
	if not slamming:
		p.velocity += p.get_gravity() * gravity_scale() * dt

	_update_tilt(dt)
	_update_camera_alignment(dt)
	if slamming:
		return

	var direction := p.camera_controller.get_input_direction(input_dir)

	var hvel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var speed := hvel.length()

	if launch_grace > 0.0:
		launch_grace -= dt
	elif speed > p.air.air_speed and not p.tackle_controller.is_tackling():
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

	var is_grounded = _check_grounded()
	if is_grounded:
		return

	var wall_mounted = p.mount_prober.try_mount_wall(input_dir, p.velocity)
	if wall_mounted:
		_play_landed_effect()


func _update_camera_alignment(dt: float) -> void:
	var p := player

	if p.camera_controller.is_rear_view():
		return

	var target_yaw := p.camera_controller.global_rotation.y
	var new_yaw := lerp_angle(p.rotation.y, target_yaw, p.air.air_turn_speed * dt)
	var delta := angle_difference(p.rotation.y, new_yaw)

	p.rotation.y = new_yaw
	p.camera_controller.rotation.y -= delta


func _update_tilt(dt: float) -> void:
	var p := player

	var velocity_rotation := p.velocity.y * p.air.air_tilt_rotation_scale
	var forward_limit := deg_to_rad(p.air.air_tilt_forward_limit_deg)
	var backward_limit := deg_to_rad(p.air.air_tilt_backward_limit_deg)

	if velocity_rotation < -forward_limit:
		velocity_rotation = -forward_limit
	if velocity_rotation > backward_limit:
		velocity_rotation = backward_limit

	var current_rot_x := p.tilt_pivot.rotation.x
	var new_rot_x = lerp(current_rot_x, velocity_rotation, dt * p.air.air_tilt_rotation_speed)
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
	if probe_hits.size() != 2 or p.velocity.y > 0.0:
		return false

	_land(probe_hits)
	return true


func _land(probe_hits: Dictionary, impact: KinematicCollision3D = null) -> void:
	var p := player
	for mount in p.leg_mounts:
		if probe_hits.has(mount):
			var hit_pos: Vector3 = probe_hits[mount]["position"]
			if hit_pos:
				mount.set_target(hit_pos)

	# sprinting upper limbs are legs: let GroundedState plant them instead
	if not p.grounded_state().is_sprinting:
		for mount in p.arm_mounts:
			if p.grab_controller.is_mount_grabbing(mount):
				continue
			mount.set_target(mount.to_global(mount.compute_idle_target()))

	p.set_state(p.StateID.GROUNDED)
	_play_landed_effect(impact)


func _play_landed_effect(impact: KinematicCollision3D = null) -> void:
	var p := player
	_audio_player.global_position = impact.get_position() if impact != null else p.global_position
	_audio_player.reset_physics_interpolation()

	if impact != null:
		_audio_player.stream = hard_landing_sound
		AudioUtil.play_with_pitch(_audio_player)
		p.camera_controller.play_heavy_impact()
		return

	var trauma := p.air.landing_trauma
	if p.velocity.y <= -p.air.hard_landing_speed:
		_audio_player.stream = hard_landing_sound
		trauma *= p.air.hard_landing_trauma_multiplier

		var v_dir := p.velocity.normalized()
		var space_state := p.get_world_3d().direct_space_state
		var player_pos := p.position
		var query := PhysicsRayQueryParameters3D.create(
			player_pos, player_pos + v_dir * p.air.landing_vfx_raycast_distance, p.cast_mask()
		)
		var result := space_state.intersect_ray(query)
		if result:
			_landing_vfx.play(result.position, result.normal)
	else:
		_audio_player.stream = light_landing_sound

	AudioUtil.play_with_pitch(_audio_player)
	p.camera_controller.add_trauma(trauma)
