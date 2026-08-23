extends PlayerState
class_name WallClimbState

var average_normal: Vector3 = Vector3.ZERO
var mount_normal_change_debounces: Dictionary = {}

const MOUNT_NORMAL_CHANGE_DEBOUNCE_TIME: float = 1.6
const NORMAL_SIMILARITY_THRESHOLD: float = 0.7

const CORNERING_TIMER_DURATION: float = 1.5
enum CorneringType {
	INSIDE,
	OUTSIDE,
}

var is_cornering: bool = false
var cornering_timer: float = 0.0
var cornering_target_normal: Vector3 = Vector3.ZERO
var cornering_target_pos: Vector3 = Vector3.ZERO

func exit() -> void:
	var p := player

	p.wall_climb_debounce = p.wall_climb_debounce_time
	for mount in p.arm_mounts:
		mount.wall_surface_normal = Vector3.ZERO
		mount_normal_change_debounces[mount] = 0

func _init(p: PlayerController) -> void:
	super._init(p)
	mount_normal_change_debounces = {}
	for mount in p.arm_mounts:
		mount_normal_change_debounces[mount] = 0

func physics_update(dt: float) -> void:
	var p := player

	var valid_normals := 0
	average_normal = Vector3.ZERO
	for mount in p.arm_mounts:
		if mount_normal_change_debounces[mount] > 0:
			mount_normal_change_debounces[mount] -= dt

		if mount.wall_surface_normal != Vector3.ZERO:
			average_normal += mount.wall_surface_normal
			valid_normals += 1

	if valid_normals > 0:
		average_normal = average_normal.normalized()

		if is_cornering:
			cornering_timer -= dt
			if cornering_timer <= 0:
				is_cornering = false

			var remaining := maxf(cornering_timer, dt)
			var weight := dt / remaining

			# lerp the y rotation to the cornering target
			var goal_yaw := atan2(-cornering_target_normal.x, -cornering_target_normal.z)
			p.rotation.y = lerp_angle(p.rotation.y, goal_yaw, weight)

			# move the player towards the cornering target
			var direction := cornering_target_pos - p.position
			if direction.length_squared() > 0.0:
				p.velocity = direction / remaining
			else:
				p.velocity = Vector3.ZERO

		else:
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

			# wall offset logic
			var space := p.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(p.position, p.position + -average_normal * p.wall_offset * p.wall_raycast_dist, ~2)

			var result := space.intersect_ray(query)
			if not result.is_empty():
				# check the surface normal is facing the player
				var surface_normal := result["normal"] as Vector3
				var angle := rad_to_deg(acos(surface_normal.dot(average_normal)))

				if angle >= 15.0:
					goal_direction = -surface_normal

				if surface_normal.dot(average_normal) >= cos(deg_to_rad(70)):
					var hit_pos := result["position"] as Vector3
					var distance_from_wall := (hit_pos - p.position).length()
					var distance_error := distance_from_wall - p.wall_offset

					var target_normal_vel: Vector3 = -average_normal * distance_error * p.wall_offset_correction_rate
					var normal_comp := average_normal * p.velocity.dot(average_normal)
					p.velocity += (target_normal_vel - normal_comp) * minf(1.0, dt * p.wall_offset_correction_rate)

			var goal_yaw := atan2(-goal_direction.x, -goal_direction.z)
			p.rotation.y = lerp_angle(p.rotation.y, goal_yaw, dt * p.turn_speed)

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

	var up_vector := (Vector3.UP - average_normal * average_normal.dot(Vector3.UP)).normalized()
	var right_vector := up_vector.cross(average_normal)

	var space := p.get_world_3d().direct_space_state

	for mount in p.arm_mounts:
		if mount.arm.is_stepping:
			mount.arm.advance_step(dt)
			continue

		var hit = mount.update_wall_climb(p.velocity)
		var horizontal_grounded = mount.horizontal_mount.arm.is_grounded()
		var diagonal_grounded = mount.vertical_mount.arm.is_grounded() and horizontal_grounded
		var can_step = diagonal_grounded or mount.arm.is_fully_extended()
		if can_step:
			# cast sideways inside to turn the corner
			var wall_target_pos := mount.wall_target.global_position
			var side_dir := (right_vector * input_dir.x).normalized()
			var is_on_strafe_side := (wall_target_pos - p.global_position).dot(side_dir) > 0
			if is_on_strafe_side:
				var ray_end: Vector3 = wall_target_pos + side_dir * p.raycast_config.wall_inside_cornering_raycast_distance
				var mount_pos := mount.global_position
				var motion := ray_end - mount_pos
				var side_result = mount.get_surface_hit(mount_pos, motion.normalized(), motion.length())

				if side_result:
					var side_hit_pos: Vector3 = side_result["position"]
					var new_normal: Vector3 = side_result["normal"]
					var current_normal: Vector3 = mount.wall_surface_normal

					# check the normal is from a different surface angle
					if new_normal.dot(current_normal) < 0.3:
						mount.step_target = side_hit_pos
						var current_pos = mount.target.global_position
						var dist = (current_pos - mount.step_target).length()
						if dist > furthest_distance and dist >= 0.5:
							furthest_distance = dist
							best_mount = mount
							best_hit = side_result

							continue

			if mount.step_target != null:
				var current_pos = mount.target.global_position

				var dist = (current_pos - mount.step_target).length()
				if dist > furthest_distance and dist >= mount.raycast_config.max_target_displacement:
					furthest_distance = dist
					best_mount = mount
					best_hit = hit
			elif is_on_strafe_side:
				# outside wall cornering
				var ray_origin := wall_target_pos - average_normal * p.raycast_config.wall_raycast_distance
				ray_origin += side_dir * 1.0 # offset the origin to be horizontally ahead of the body
				var ray_end := ray_origin + -side_dir * p.raycast_config.wall_outside_ray_lead

				var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, ~2)
				var result := space.intersect_ray(query)
				if not result.is_empty():
					var hit_pos: Vector3 = result["position"]

					# check if the hit pos is visible by the wall target
					var visible_query := PhysicsRayQueryParameters3D.create(wall_target_pos, hit_pos, ~2)
					var visible := space.intersect_ray(visible_query).is_empty()
					if not visible:
						continue

					mount.step_target = hit_pos
					var current_pos = mount.target.global_position
					var dist = (current_pos - mount.step_target).length()
					if dist > furthest_distance and dist >= 0.5:
						furthest_distance = dist
						best_mount = mount
						best_hit = result


	if best_mount != null:
		var is_corner_step: bool = best_hit.normal.dot(average_normal) < NORMAL_SIMILARITY_THRESHOLD

		var normal_change: bool = best_mount.wall_surface_normal.dot(best_hit.normal) < NORMAL_SIMILARITY_THRESHOLD
		if normal_change and mount_normal_change_debounces[best_mount] > 0:
			return

		if is_corner_step:
			mount_normal_change_debounces[best_mount] = MOUNT_NORMAL_CHANGE_DEBOUNCE_TIME
			if not is_cornering:
				is_cornering = true
				cornering_timer = CORNERING_TIMER_DURATION
				cornering_target_normal = -best_hit.normal
				cornering_target_pos = best_mount.step_target + best_hit.normal * p.wall_offset
				cornering_target_pos.y = p.position.y

		best_mount.arm.start_step(best_mount.step_target, 0.0, best_hit.normal)
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
		var surface = mount.get_surface_hit(foot_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
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

		var hit = mount.get_surface_hit(anchor_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if hit != null:
			mount_hits[mount] = hit

	if mount_hits.size() == 2:
		p.set_state(p.StateID.GROUNDED)
