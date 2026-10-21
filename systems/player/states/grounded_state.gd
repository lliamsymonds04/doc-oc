class_name GroundedState
extends PlayerState

var grounded_debounce_time: float
var walk_tilt_x: float
var walk_tilt_z: float
var sprint_tilt_x: float
var tilt_speed: float
var align_angle: float
var disalign_angle: float
var force_align: bool = false

var grounded_debounce := 0.0
var jump_debounce := 0.0
var keep_sprint := false
var body_y_offset := 0.0
var is_camera_aligned := false
var is_sprinting := false
var leg_probe_hits: Dictionary = {}
var floor_normal := Vector3.UP


func _init(p: PlayerController) -> void:
	super._init(p)
	var c := p.grounded
	grounded_debounce_time = c.grounded_debounce_time
	walk_tilt_x = deg_to_rad(c.walk_tilt_x_deg)
	walk_tilt_z = deg_to_rad(c.walk_tilt_z_deg)
	sprint_tilt_x = -deg_to_rad(c.sprint_tilt_x_deg)
	tilt_speed = c.tilt_speed
	align_angle = deg_to_rad(c.align_angle_deg)
	disalign_angle = deg_to_rad(c.disalign_angle_deg)


func enter() -> void:
	var p := player
	keep_sprint = false

	grounded_debounce = grounded_debounce_time
	jump_debounce = p.grounded.jump_debounce_time
	p.jump_controller.cancel_hold()
	body_y_offset = (p.hover.min_y_offset + p.hover.max_y_offset) / 2.0
	is_camera_aligned = absf(p.camera_controller.rotation.y) <= align_angle
	floor_normal = Vector3.UP

	for mount in p.leg_mounts:
		mount.set_apply_floor(true)

	# arms only use the floor while sprinting turns them into legs
	for mount in p.arm_mounts:
		mount.set_apply_floor(mount.is_leg)

	# sprinting limbs are legs, so they plant on landing instead of returning to idle
	if is_sprinting:
		_plant_sprint_limbs()
	else:
		for mount in p.arm_mounts:
			if mount.idle_target:
				var idle_pos := mount.compute_idle_target()
				var end_effector_pos := mount.arm.solver.get_end_effector()
				var dist := (idle_pos - end_effector_pos).length()
				if dist > 1.0:
					var params := StepParams.new()
					params.emit_landed = false
					mount.arm.start_step(mount.to_global(idle_pos), params)


func exit() -> void:
	if is_sprinting and not keep_sprint:
		is_sprinting = false
		_set_arms_as_legs(false)
	keep_sprint = false


func physics_update(dt: float) -> void:
	var p := player

	if not p.is_on_floor():
		p.velocity += p.get_gravity() * dt

	var speed := p.movement.speed
	if is_sprinting:
		speed *= p.grounded.sprint_multiplier

	var direction := p.camera_controller.get_input_direction(input_dir)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var w := 1.0 - exp(-p.movement.accel * dt)
	var target := direction * speed
	p.velocity.x = lerpf(p.velocity.x, target.x, w)
	p.velocity.z = lerpf(p.velocity.z, target.z, w)

	_update_camera_alignment(dt, direction.length_squared() > 0.0)

	_update_tilt(dt)

	_update_legs(dt)
	_update_arms(dt)

	if not p.is_in_state(p.StateID.GROUNDED):
		return

	var mounted = p.mount_prober.try_mount_wall(input_dir, p.velocity)
	if mounted:
		return

	if p.wall_climb_debounce > 0.0:
		p.wall_climb_debounce -= dt

	if grounded_debounce > 0.0:
		grounded_debounce -= dt
		if grounded_debounce < 0.0:
			for mount in p.arm_mounts:
				mount.set_apply_floor(mount.is_leg)

	_update_floor_normal(dt)

	p.jump_controller.tick_hold(dt)
	if p.jump_controller.is_holding_jump:
		body_y_offset = 0.5
	else:
		_calculate_y_body_offset(dt)

	_update_body_y_offset(dt)
	_handle_jump(direction, dt)
	_handle_input()


func _handle_input() -> void:
	var p := player

	var want_sprint := Input.is_action_pressed("sprint")
	if want_sprint and !is_sprinting:
		is_sprinting = true
		_set_arms_as_legs(true)
		p.camera_controller.set_sprinting(true)
	elif is_sprinting and !want_sprint:
		is_sprinting = false
		_set_arms_as_legs(false)
		p.camera_controller.set_sprinting(false)

	if Input.is_action_just_pressed("left-click"):
		if player.is_in_grab_mode():
			p.grab_controller.try_grab(-1)
		else:
			p.attack_controller.try_attack()

	if Input.is_action_just_pressed("right-click"):
		if player.is_in_grab_mode():
			p.grab_controller.try_grab(1)

	if Input.is_action_just_released("left-click"):
		if player.is_in_grab_mode():
			p.grab_controller.release_grab(-1)

	if Input.is_action_just_released("right-click"):
		if player.is_in_grab_mode():
			p.grab_controller.release_grab(1)


func frame_update(dt: float) -> void:
	for mount in player.all_mounts():
		if player.grab_controller.is_mount_grabbing(mount):
			continue
		if mount.is_leg:
			mount.update_planted_target()
		else:
			mount.update_idle_target(dt, player.grounded.arm_idle_lerp_speed)


func _update_camera_alignment(dt: float, is_moving: bool) -> void:
	var p := player

	if is_moving or force_align:
		if is_camera_aligned:
			p.rotation.y = p.camera_controller.global_rotation.y
			p.camera_controller.rotation.y = 0
		else:
			var target_yaw := p.camera_controller.global_rotation.y
			var new_yaw := lerp_angle(p.rotation.y, target_yaw, p.movement.turn_speed * dt)
			var delta := angle_difference(p.rotation.y, new_yaw)

			p.rotation.y = new_yaw
			# cancel the body's rotation in the camera's local yaw so its
			# world-space direction stays fixed while the body turns under it
			p.camera_controller.rotation.y -= delta

			if absf(p.camera_controller.rotation.y) <= align_angle:
				is_camera_aligned = true
				force_align = false
	elif absf(p.camera_controller.rotation.y) >= disalign_angle:
		is_camera_aligned = false


func _handle_jump(direction: Vector3, dt: float) -> void:
	var p := player

	if jump_debounce > 0.0:
		jump_debounce -= dt
		return

	if Input.is_action_just_pressed("jump"):
		p.jump_controller.begin_hold()

	if Input.is_action_just_released("jump"):
		var launch := p.jump_controller.create_launch(direction)
		# keep_sprint must be set before set_state(): set_state runs exit(), which reads it
		keep_sprint = true
		p.velocity = launch.velocity
		p.set_state(p.StateID.AIR)
		p.air_state().begin_launch(launch.rising_gravity)
		p.play_jump_effects(launch.charge)
		p.camera_controller.kick_fov(lerpf(5.0, 0.0, launch.charge))


func _update_tilt(dt: float) -> void:
	var p := player
	var c := p.grounded

	var dir := input_dir
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	var current_tilt_x := p.tilt_pivot.rotation.x
	var current_tilt_z := p.tilt_pivot.rotation.z
	var current_tilt_y := p.tilt_pivot.rotation.y

	# camera influence
	var camera_pitch = p.camera_controller.get_pitch() * p.grounded.cam_pitch_tilt_mult
	var camera_yaw = p.camera_controller.rotation.y * p.grounded.cam_yaw_tilt_mult

	# targets
	var target_tilt_x: float = dir.y * walk_tilt_x
	var target_tilt_z: float = -dir.x * walk_tilt_z
	var target_tilt_y: float = p.attack_controller.attack_tilt_y + camera_yaw

	if is_sprinting:
		target_tilt_x *= c.sprint_tilt_multiplier
		if dir.y <= 0.0:
			target_tilt_x += sprint_tilt_x
		target_tilt_z *= c.sprint_tilt_multiplier
	else:
		target_tilt_x += camera_pitch

	var tilted_x = lerp(current_tilt_x, target_tilt_x, dt * tilt_speed)
	var tilted_z = lerp(current_tilt_z, target_tilt_z, dt * tilt_speed)
	var tilted_y = lerp(
		current_tilt_y, target_tilt_y, dt * tilt_speed * p.grounded.yaw_tilt_speed_multiplier
	)

	p.tilt_pivot.rotation.x = tilted_x
	p.tilt_pivot.rotation.z = tilted_z
	p.tilt_pivot.rotation.y = tilted_y


func _update_legs(dt: float) -> void:
	var p := player

	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	var mounts: Array[ArmMount] = p.leg_mounts
	if is_sprinting:
		mounts = p.all_mounts()

	for mount in mounts:
		if p.grab_controller.is_mount_grabbing(mount):
			if mount.arm.is_moving:
				mount.arm.advance_move(dt)
			continue
		mount.update_step(p.velocity, dt)
		var other_mounts_grounded := false
		var is_horizontal_mount_grounded := mount.horizontal_mount.arm.is_grounded()
		if is_sprinting:
			var is_diagonal_grounded := mount.diagonal_mount.arm.is_grounded()
			other_mounts_grounded = is_horizontal_mount_grounded and is_diagonal_grounded
		else:
			other_mounts_grounded = is_horizontal_mount_grounded

		var can_step: bool = (
			mount.step_target != null
			and (
				(mount.arm.is_grounded() and other_mounts_grounded) or mount.arm.is_fully_extended()
			)
		)

		if can_step:
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		var params := StepParams.new()
		if is_sprinting:
			params.speed_multiplier = p.grounded.sprint_speed_step_multiplier
		best_arm.start_step(best_arm_hit_pos, params)

	leg_probe_hits = p.mount_prober.get_leg_probe_hits()
	if leg_probe_hits.size() == 0 and grounded_debounce <= 0.0:
		p.set_state(p.StateID.AIR)


func _update_arms(dt: float) -> void:
	if is_sprinting:
		return

	var p := player
	for mount in p.arm_mounts:
		if p.grab_controller.is_mount_grabbing(mount):
			if mount.arm.is_moving:
				mount.arm.advance_move(dt)
			continue
		mount.update_step(p.velocity, dt)


func _calculate_average_target_y() -> Variant:
	var p := player

	var total_y = 0
	var grounded_legs = 0

	for mount in p.leg_mounts:
		var arm := mount.arm
		if not arm.is_grounded():
			continue

		total_y += arm.target_world.y
		grounded_legs += 1

	if grounded_legs == 0:
		return null

	return total_y / grounded_legs


func _calculate_y_body_offset(dt: float) -> void:
	var p := player

	if Input.is_action_pressed("up"):
		body_y_offset = min(body_y_offset + p.hover.target_change_rate * dt, p.hover.max_y_offset)
	if Input.is_action_pressed("down"):
		body_y_offset = max(body_y_offset - p.hover.target_change_rate * dt, p.hover.min_y_offset)


func _update_floor_normal(dt: float) -> void:
	var p := player
	var avg := Vector3.ZERO

	var hits := leg_probe_hits.values()
	if hits.size() == 0:
		return

	for hit in hits:
		avg += hit.normal

	avg = avg.normalized()
	var w := 1.0 - exp(-p.grounded.normal_smoothing_rate * dt)
	floor_normal = floor_normal.lerp(avg, w).normalized()


func _update_body_y_offset(dt: float) -> void:
	var p := player

	var average_y = _calculate_average_target_y()
	if average_y == null:
		return

	var goal_y = average_y + body_y_offset
	var current_y = p.global_position.y
	var height_error = goal_y - current_y

	var tracking := p.hover.hover_speed * p.hover.damping * 4.0  # 4 is critical damping factor here
	var w := 1.0 - exp(-tracking * dt)

	var gravity_ff := -p.get_gravity().y / tracking

	var climb_ff := 0.0
	if floor_normal.y > 0.2:
		climb_ff = -(p.velocity.x * floor_normal.x + p.velocity.z * floor_normal.z) / floor_normal.y

	var target_y_vel = height_error * p.hover.hover_speed + gravity_ff + climb_ff
	p.velocity.y = lerp(p.velocity.y, target_y_vel, w)


func _set_arms_as_legs(active: bool) -> void:
	for mount in player.arm_mounts:
		mount.is_leg = active
		mount.set_apply_floor(active)
		if not active:
			var params := StepParams.new()
			params.emit_landed = false
			mount.arm.start_step(mount.to_global(mount.compute_idle_target()), params)

	if active:
		_plant_sprint_limbs()


func _plant_sprint_limbs() -> void:
	var p := player
	var run_speed := p.movement.speed * p.grounded.sprint_multiplier
	var lead_vel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if lead_vel.length() > run_speed:
		lead_vel = lead_vel.normalized() * run_speed

	for mount in p.arm_mounts:
		mount.is_leg = true
		if p.grab_controller.is_mount_grabbing(mount):
			continue
		mount.update_ground_step_target(lead_vel, true)
		if mount.step_target == null:
			continue
		var params := StepParams.new()
		params.speed_multiplier = p.grounded.sprint_speed_step_multiplier
		mount.arm.start_step(mount.step_target, params)
