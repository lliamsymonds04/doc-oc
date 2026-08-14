extends PlayerState
class_name WallClimbState

func exit() -> void:
	var p := player

	p.wall_climb_debounce = p.wall_climb_debounce_time
	for mount in p.arm_mounts:
		mount.wall_surface_normal = Vector3.ZERO

func physics_update(dt: float) -> void:
	var p := player

	var valid_normals := 0
	var average_normal := Vector3.ZERO
	for mount in p.arm_mounts:
		if mount.wall_surface_normal != Vector3.ZERO:
			average_normal += mount.wall_surface_normal
			valid_normals += 1

	if valid_normals > 0:
		average_normal /= valid_normals

		var up_vector := (Vector3.UP - average_normal * average_normal.dot(Vector3.UP)).normalized()
		var right_vector := up_vector.cross(average_normal)

		var direction := up_vector * -input_dir.y + right_vector * input_dir.x
		if direction.length_squared() > 0.0:
			p.velocity = direction.normalized() * p.speed
		else:
			p.velocity.x = move_toward(p.velocity.x, 0, p.speed * dt)
			p.velocity.z = move_toward(p.velocity.z, 0, p.speed * dt)
			p.velocity.y = move_toward(p.velocity.y, 0, p.speed * dt)

		var goal_direction = -average_normal
		var goal_yaw := atan2(-goal_direction.x, -goal_direction.z)
		p.rotation.y = lerp_angle(p.rotation.y, goal_yaw, dt * p.turn_speed)

		# wall offset logic
		var space := p.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(p.position, p.position + -average_normal * p.wall_offset * p.wall_raycast_dist, ~2)

		var result := space.intersect_ray(query)
		if not result.is_empty():
			var hit_pos := result["position"] as Vector3
			var distance_from_wall := (hit_pos - p.position).length()
			var distance_error := distance_from_wall - p.wall_offset

			var target_normal_vel: Vector3 = -average_normal * distance_error * p.wall_offset_correction_rate
			var normal_comp := average_normal * p.velocity.dot(average_normal)
			p.velocity += (target_normal_vel - normal_comp) * minf(1.0, dt * p.wall_offset_correction_rate)
	else:
		p.velocity = Vector3.ZERO
	update_wall_arms(dt)

	# wall discmount logic
	if input_dir.y < 0:
		var ledge_result = _detect_ledge(average_normal)
		if ledge_result != null:
			_dismount_to_ledge(ledge_result)
	elif input_dir.y > 0:
		_check_floor_from_wall()

func update_wall_arms(dt: float) -> void:
	var p := player

	var best_mount: ArmMount = null
	var furthest_distance := 0.0
	var best_hit = null

	for mount in p.arm_mounts:
		if mount.arm.is_stepping:
			mount.arm.advance_step(dt)
			continue

		var hit = mount.update_wall_climb(p.velocity)
		var diagonal_grounded = mount.vertical_mount.arm.is_grounded() and mount.horizontal_mount.arm.is_grounded()
		var can_step = diagonal_grounded or mount.arm.is_fully_extended()
		if mount.step_target != null and can_step:
			var current_pos = mount.target.global_position

			var dist = (current_pos - mount.step_target).length()
			if dist > furthest_distance and dist >= mount.raycast_config.max_target_displacement:
				furthest_distance = dist
				best_mount = mount
				best_hit = hit

	if best_mount != null:
		best_mount.arm.start_step(best_mount.step_target)
		best_mount.wall_surface_normal = best_hit.normal

func _detect_ledge(wall_normal: Vector3) -> Variant:
	var p := player

	if wall_normal == Vector3.ZERO:
		return null

	var space := p.get_world_3d().direct_space_state
	var start := p.position + Vector3.UP * p.ledge_ray_offset
	var end := start - wall_normal * p.ledge_ray_length + Vector3.DOWN * p.ledge_ray_offset
	var query := PhysicsRayQueryParameters3D.create(start, end, ~2)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	if (result["normal"] as Vector3).y < 0.5:
		return null

	return result

func _dismount_to_ledge(ledge_result: Dictionary) -> void:
	var p := player

	p.set_state(p.StateID.GROUNDED)

	p.velocity += Vector3.UP * p.mount_velocity_impulse

	var ledge_pos := ledge_result["position"] as Vector3
	var right := p.global_transform.basis.x
	var step_count := 0

	for mount in p.arm_mounts:
		if not mount.is_leg:
			continue

		var foot_pos := ledge_pos + right * mount.anchor.position.x
		var surface = mount._get_surface_hit(foot_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if surface != null:
			foot_pos = (surface["position"] as Vector3)

		if step_count > 0:
			mount.arm.start_step(foot_pos, 0.2 * step_count)
		else:
			mount.arm.start_step(foot_pos)

		step_count += 1

func _check_floor_from_wall() -> void:
	var p := player

	var mount_hits = {}
	for mount in p.arm_mounts:
		if not mount.is_leg:
			continue

		var anchor_pos := mount.anchor.global_position

		var hit = mount._get_surface_hit(anchor_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if hit != null:
			mount_hits[mount] = hit

	if mount_hits.size() == 2:
		p.set_state(p.StateID.GROUNDED)
