extends PlayerState
class_name WallClimbState

var min_wall_facing_dot: float
var max_wall_normal_deviation_dot: float
var ledge_min_up_dot: float
var ledge_dismount_foot_stagger: float
var max_tilt_rad: float
var tilt_smoothing_speed: float

var average_normal: Vector3 = Vector3.ZERO
var arms: WallClimbArms


func exit() -> void:
	var p := player

	p.wall_climb_debounce = p.wall_climb.wall_climb_debounce_time
	for mount in p.all_mounts():
		mount.wall_surface_normal = Vector3.ZERO

	arms.reset()

func _init(p: PlayerController) -> void:
	super._init(p)
	var c := p.wall_climb
	min_wall_facing_dot = cos(deg_to_rad(c.min_wall_facing_angle_deg))
	max_wall_normal_deviation_dot = cos(deg_to_rad(c.max_wall_normal_deviation_angle_deg))
	ledge_min_up_dot = cos(deg_to_rad(c.ledge_min_up_angle_deg))
	ledge_dismount_foot_stagger = c.ledge_dismount_foot_stagger
	max_tilt_rad = deg_to_rad(c.wall_max_tilt_deg)
	tilt_smoothing_speed = c.wall_tilt_smoothing_speed
	arms = WallClimbArms.new(p)

func physics_update(dt: float) -> void:
	var p := player

	_update_tilt(dt)

	arms.tick(dt)

	if _update_average_normal():
		if arms.is_cornering:
			arms.update_cornering(dt)
		else:
			_apply_movement(dt)
	else:
		p.velocity = Vector3.ZERO
		arms.wall_normal = p.basis.z

	arms.update_arms(dt, input_dir, average_normal)

	var dismounted := false
	# wall dismount logic
	if input_dir.y < 0:
		var ledge_result = _detect_ledge(average_normal)
		if ledge_result != null:
			dismounted = true
			_dismount_to_ledge(ledge_result)
	elif input_dir.y > 0:
		_check_floor_from_wall()

	if dismounted:
		return

	if Input.is_action_just_pressed("jump"):
		if input_dir.y < 0:
			p.velocity = Vector3.UP * p.jump.wall_jump_upward_velocity
		elif input_dir.x != 0:
			p.velocity = p.basis.x * input_dir.x * p.jump.wall_jump_sideways_velocity
		elif input_dir.y > 0:
			p.velocity = p.basis.z * p.jump.wall_jump_backward_velocity
		else:
			p.velocity = Vector3.ZERO

		p.set_state(p.StateID.AIR)
		p.play_jump_effects(0.5)

func _update_average_normal() -> bool:
	average_normal = Vector3.ZERO
	var valid_normals := 0
	for mount in player.all_mounts():
		if mount.wall_surface_normal != Vector3.ZERO:
			average_normal += mount.wall_surface_normal
			valid_normals += 1
	if valid_normals > 0:
		average_normal = average_normal.normalized()
	return valid_normals > 0

func _apply_movement(dt: float) -> void:
	var p := player
	var space := p.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(p.position, p.position + -p.basis.z * p.wall_climb.wall_offset * p.wall_climb.wall_raycast_dist, ~2)
	var result := space.intersect_ray(query)

	# core rule: always face the wall directly in front (lerped), reject glancing hits
	var goal_direction := -p.basis.z
	if not result.is_empty():
		var surface_normal := result["normal"] as Vector3
		# only trust normals pointing back at us; glancing side hits would whip the player
		if surface_normal.dot(p.basis.z) > min_wall_facing_dot:
			goal_direction = -surface_normal

	arms.wall_normal = -goal_direction

	# B: movement basis from average_normal (stable at corner steps, follows slopes)
	var b := WallClimbArms.wall_basis(average_normal)
	var direction := b.y * -input_dir.y + b.x * input_dir.x
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	# ramp toward the target velocity like the grounded state so acceleration
	# and deceleration are smoothed instead of an instantaneous step
	var w := 1.0 - exp(-p.movement.accel * dt)
	var target := direction * p.movement.speed
	p.velocity.x = lerpf(p.velocity.x, target.x, w)
	p.velocity.y = lerpf(p.velocity.y, target.y, w)
	p.velocity.z = lerpf(p.velocity.z, target.z, w)

	# wall offset still corrects toward gripped wall (after movement so it isn't overwritten)
	if not result.is_empty():
		var surface_normal := result["normal"] as Vector3
		if surface_normal.dot(average_normal) >= max_wall_normal_deviation_dot:
			var hit_pos: Vector3 = result["position"] as Vector3
			var distance_from_wall: float = (hit_pos - p.position).length()
			var distance_error := distance_from_wall - p.wall_climb.wall_offset
			var target_normal_vel: Vector3 = -average_normal * distance_error * p.wall_climb.wall_offset_correction_rate
			var normal_comp := average_normal * p.velocity.dot(average_normal)
			p.velocity += (target_normal_vel - normal_comp) * minf(1.0, dt * p.wall_climb.wall_offset_correction_rate)

	var goal_yaw := atan2(-goal_direction.x, -goal_direction.z)
	p.rotation.y = lerp_angle(p.rotation.y, goal_yaw, dt * p.movement.turn_speed)

func _detect_ledge(wall_normal: Vector3) -> Variant:
	var p := player

	if wall_normal == Vector3.ZERO:
		return null

	var space := p.get_world_3d().direct_space_state
	var start := p.position + Vector3.UP * p.wall_climb.ledge_ray_offset
	var end := start - wall_normal * p.wall_climb.ledge_ray_length + Vector3.DOWN * p.wall_climb.ledge_ray_offset
	var query := PhysicsRayQueryParameters3D.create(start, end, ~2)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	if (result["normal"] as Vector3).y < ledge_min_up_dot:
		return null

	return result

func _dismount_to_ledge(ledge_result: Dictionary) -> void:
	var p := player

	p.set_state(p.StateID.GROUNDED)

	p.velocity += Vector3.UP * p.wall_climb.mount_velocity_impulse

	var ledge_pos := ledge_result["position"] as Vector3
	var right := p.global_transform.basis.x
	var step_count := 0

	for mount in p.leg_mounts:
		var foot_pos := ledge_pos + right * mount.ground_probe.position.x
		var surface = mount.get_surface_hit(foot_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if surface != null:
			foot_pos = (surface["position"] as Vector3)

		if step_count > 0:
			mount.arm.start_step(foot_pos, ledge_dismount_foot_stagger * step_count)
		else:
			mount.arm.start_step(foot_pos)

		step_count += 1

func _check_floor_from_wall() -> bool:
	var p := player

	var leg_probe_hits := p.mount_prober.get_leg_probe_hits()
	if leg_probe_hits.size() == 2:
		p.set_state(p.StateID.GROUNDED)
		return true

	return false

func _update_tilt(dt: float) -> void:
	var p := player

	var dir := input_dir
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	var current_tilt_x := p.tilt_pivot.rotation.x
	var current_tilt_z := p.tilt_pivot.rotation.z

	var target_tilt_x := dir.y * max_tilt_rad
	var target_tilt_z := -dir.x * max_tilt_rad

	var tilted_x = lerp(current_tilt_x, target_tilt_x, dt * tilt_smoothing_speed)
	var tilted_z = lerp(current_tilt_z, target_tilt_z, dt * tilt_smoothing_speed)

	p.tilt_pivot.rotation.x = tilted_x
	p.tilt_pivot.rotation.z = tilted_z
