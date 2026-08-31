class_name GroundedState
extends PlayerState

const GROUNDED_DEBOUNCE_TIME := 1.2
const WALK_TILT_X := deg_to_rad(10)
const WALK_TILT_Z := deg_to_rad(10)
const TILT_SPEED := 1.0
const ALIGN_ANGLE := deg_to_rad(1.0)
const DISALIGN_ANGLE := deg_to_rad(2.0)

var grounded_debounce := 0.0
var is_holding_jump := false
var jump_hold_time := 0.0
var body_y_offset := 0.0
var is_camera_aligned := false

func enter() -> void:
	var p := player

	grounded_debounce = GROUNDED_DEBOUNCE_TIME
	jump_hold_time = 0.0
	is_holding_jump = false
	body_y_offset = (p.min_y_offset + p.max_y_offset) / 2.0
	is_camera_aligned = absf(p.camera_controller.rotation.y) <= ALIGN_ANGLE

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

	_update_camera_alignment(dt, direction.length_squared() > 0.0)

	_update_tilt(dt)

	_update_legs(dt)
	_update_arms(dt)

	p.mount_prober.try_mount_wall(input_dir, p.velocity)

	if p.wall_climb_debounce > 0.0:
		p.wall_climb_debounce -= dt

	if grounded_debounce > 0.0:
		grounded_debounce -= dt
		if grounded_debounce < 0.0:
			for mount in p.arm_mounts:
				mount.set_apply_floor(true)

	if is_holding_jump:
		jump_hold_time += dt
		body_y_offset = 0.5
	else:
		_calculate_y_body_offset()

	_update_body_y_offset(dt)
	_handle_jump(direction)


func _update_camera_alignment(dt: float, is_moving: bool) -> void:
	var p := player

	if is_moving:
		if is_camera_aligned:
			p.rotation.y = p.camera_controller.global_rotation.y
			p.camera_controller.rotation.y = 0
		else:
			var target_yaw := p.camera_controller.global_rotation.y
			var new_yaw := lerp_angle(p.rotation.y, target_yaw, p.turn_speed * dt)
			var delta := angle_difference(p.rotation.y, new_yaw)

			p.rotation.y = new_yaw
			# cancel the body's rotation in the camera's local yaw so its
			# world-space direction stays fixed while the body turns under it
			p.camera_controller.rotation.y -= delta

			if absf(p.camera_controller.rotation.y) <= ALIGN_ANGLE:
				is_camera_aligned = true
	elif absf(p.camera_controller.rotation.y) >= DISALIGN_ANGLE:
		is_camera_aligned = false


func _handle_jump(direction: Vector3):
	var p := player

	if Input.is_action_just_pressed("jump"):
		is_holding_jump = true
		jump_hold_time = 0.0

	if Input.is_action_just_released("jump"):
		var charge_f = min(jump_hold_time/p.max_jump_hold_time, 1.0)
		var jump_charge = lerp(p.min_jump_charge, 1.0, charge_f)

		p.velocity.y = p.jump_vertical_velocity * jump_charge
		p.velocity += direction * p.jump_horizontal_velocity
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

func _calculate_y_body_offset() -> void:
	var p := player

	var camera_pitch = p.camera_controller.rotation_degrees.x
	var effective_pitch = camera_pitch - p.neutral_pitch
	if abs(effective_pitch) > p.min_height_change_look_threshold:
		body_y_offset = p.max_y_offset if effective_pitch > 0 else p.min_y_offset


func _update_body_y_offset(dt:float) -> void:
	var p := player

	var average_y = _calculate_average_target_y()
	if average_y == null:
		return

	var goal_y = average_y + body_y_offset
	var current_y = p.global_position.y
	var height_error = goal_y - current_y
	var target_y_vel = height_error * p.hover_speed
	p.velocity.y = lerp(p.velocity.y, target_y_vel, dt*p.hover_speed)
