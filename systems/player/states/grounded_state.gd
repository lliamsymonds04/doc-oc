class_name GroundedState
extends PlayerState

const GROUNDED_DEBOUNCE_TIME := 1.2
const WALK_TILT_X := deg_to_rad(10)
const WALK_TILT_Z := deg_to_rad(10)
const TILT_SPEED := 1.0

var grounded_debounce := 0.0

func enter() -> void:
	grounded_debounce = GROUNDED_DEBOUNCE_TIME

	var p := player
	for mount in p.leg_mounts:
		mount.set_apply_floor(true)

	for mount in p.arm_mounts:
		if mount.idle_target:
			var idle_pos := mount.compute_idle_target()
			var end_effector_pos := mount.arm.solver.get_end_effector()
			var dist := (idle_pos - end_effector_pos).length()
			if dist > 1.0:
				mount.arm.start_step(mount.to_global(idle_pos))
			else:
				mount.sync_from_arm()

func physics_update(dt: float) -> void:
	var p := player

	p.rotation.y = p.camera_controller.global_rotation.y
	p.camera_controller.rotation.y = 0

	if not p.is_on_floor():
		p.velocity += p.get_gravity() * dt

	var direction := p.camera_controller.get_input_direction(input_dir)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
		p.velocity.x = direction.x * p.speed
		p.velocity.z = direction.z * p.speed
	else:
		p.velocity.x = move_toward(p.velocity.x, 0, p.speed * dt)
		p.velocity.z = move_toward(p.velocity.z, 0, p.speed * dt)

	_update_tilt(dt)

	_update_legs(dt)
	_update_arms(dt)

	_update_body_y_offset(dt)

	p.mount_prober.try_mount_wall(input_dir, p.velocity)

	if p.wall_climb_debounce > 0.0:
		p.wall_climb_debounce -= dt

	if grounded_debounce > 0.0:
		grounded_debounce -= dt
		if grounded_debounce < 0.0:
			for mount in p.arm_mounts:
				mount.set_apply_floor(true)

	if Input.is_action_just_pressed("jump"):
		p.velocity.y = p.jump_velocity
		p.set_state(p.StateID.AIR)


func _update_tilt(dt: float) -> void:
	var p := player

	var dir := input_dir
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	var current_tilt_x := p.tilt_pivot.rotation.x
	var current_tilt_z := p.tilt_pivot.rotation.z

	var target_tilt_x := dir.y * WALK_TILT_X
	var target_tilt_z := -dir.x * WALK_TILT_Z

	var tilted_x = lerp(current_tilt_x, target_tilt_x, dt * TILT_SPEED)
	var tilted_z = lerp(current_tilt_z, target_tilt_z, dt * TILT_SPEED)

	p.tilt_pivot.rotation.x = tilted_x
	p.tilt_pivot.rotation.z = tilted_z

func _update_legs(dt: float) -> void:
	var p := player

	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	for mount in p.leg_mounts:
		mount.update_step(p.velocity, dt)
		var can_step: bool = mount.step_target != null and ((mount.arm.is_grounded()
			and mount.horizontal_mount.arm.is_grounded()) or mount.arm.is_fully_extended())

		if can_step:
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)

	var probe_hits := p.mount_prober.get_leg_probe_hits()
	if probe_hits.size() == 0  and grounded_debounce <= 0.0:
		p.set_state(p.StateID.AIR)

func _update_arms(dt: float) -> void:
	var p := player
	for mount in p.arm_mounts:
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

func _update_body_y_offset(dt:float) -> void:
	var p := player

	#calculate camera pitch
	var camera_pitch = p.camera_controller.rotation_degrees.x
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
