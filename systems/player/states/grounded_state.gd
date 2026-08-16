class_name GroundedState
extends PlayerState

func enter() -> void:
	var p := player
	for mount in p.arm_mounts:
		mount.set_apply_floor(true)

		if not mount.is_leg:
			if mount.idle_target:
				mount.arm.start_step(mount.to_global(mount.compute_idle_target()))

func physics_update(dt: float) -> void:
	var p := player

	p.rotation.y = p.spring_arm.global_rotation.y
	p.spring_arm.rotation.y = 0.0

	if not p.is_on_floor():
		p.velocity += p.get_gravity() * dt

	var cam_yaw := p.rotation.y
	var forward := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))

	var direction := forward * -input_dir.y + right * input_dir.x
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
		p.velocity.x = direction.x * p.speed
		p.velocity.z = direction.z * p.speed
	else:
		p.velocity.x = move_toward(p.velocity.x, 0, p.speed * dt)
		p.velocity.z = move_toward(p.velocity.z, 0, p.speed * dt)

	_update_body_y_offset(dt)
	_update_arms(dt)
	try_mount_wall()

	if p.wall_climb_debounce > 0.0:
		p.wall_climb_debounce -= dt

func _update_arms(dt: float) -> void:
	var p := player

	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	for mount in p.arm_mounts:
		mount.update_step(p.velocity, dt)
		if mount.can_step():
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)


func _calculate_average_target_y() -> Variant:
	var p := player

	var total_y = 0
	var grounded_legs = 0

	for mount in p.arm_mounts:
		var arm := mount.arm
		if not arm.is_grounded():
			continue

		total_y += arm.target_node.global_position.y
		grounded_legs += 1

	if grounded_legs == 0:
		return null

	return total_y / grounded_legs

func _update_body_y_offset(dt:float) -> void:
	var p := player

	#calculate camera pitch
	var camera_pitch = p.spring_arm.rotation_degrees.x
	var effective_pitch = camera_pitch - p.neutral_pitch
	if abs(effective_pitch) > p.min_height_change_look_threshold:
		var goal_y_offset = p.max_y_offset if effective_pitch > 0 else p.min_y_offset
		p.body_y_offset = lerp(p.body_y_offset, goal_y_offset, dt * p.height_change_rate)

	var average_y = _calculate_average_target_y()
	if average_y == null:
		return

	var goal_y = average_y + p.body_y_offset
	var current_y = p.global_position.y
	var height_error = goal_y - current_y
	var target_y_vel = height_error * p.hover_speed
	p.velocity.y = lerp(p.velocity.y, target_y_vel, dt*p.hover_speed)

func try_mount_wall() -> void:
	var p := player

	if p.wall_climb_debounce > 0.0:
		return

	var wall_detection_count = 0
	var wall_hits := {}

	for mount in p.arm_mounts:
		# wall raycasts
		if not mount.is_leg and mount.wall_target != null and mount.arm.is_stepping == false:
			var hit = mount.get_wall_hit_pos(Vector3.ZERO)
			wall_hits[mount] = hit

			if hit != null:
				wall_detection_count += 1

	if wall_detection_count > 1:
		p.set_state(p.StateID.WALL_CLIMB)
		for mount in p.arm_mounts:
			if mount.is_leg or mount.arm.is_stepping:
				continue

			mount.set_apply_floor(false)
			var hit = wall_hits[mount]
			if hit != null:
				mount.arm.start_step(hit.position)
				mount.wall_surface_normal = hit.normal
