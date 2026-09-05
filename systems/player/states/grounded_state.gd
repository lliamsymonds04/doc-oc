class_name GroundedState
extends PlayerState

var grounded_debounce_time: float
var walk_tilt_x: float
var walk_tilt_z: float
var sprint_tilt_x: float
var tilt_speed: float
var align_angle: float
var disalign_angle: float

var grounded_debounce := 0.0
var is_holding_jump := false
var jump_hold_time := 0.0
var body_y_offset := 0.0
var is_camera_aligned := false
var is_sprinting := false

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

	grounded_debounce = grounded_debounce_time
	jump_hold_time = 0.0
	is_holding_jump = false
	body_y_offset = (p.hover.min_y_offset + p.hover.max_y_offset) / 2.0
	is_camera_aligned = absf(p.camera_controller.rotation.y) <= align_angle

	for mount in p.leg_mounts:
		mount.set_apply_floor(true)

	for mount in p.arm_mounts:
		if mount.idle_target:
			var idle_pos := mount.compute_idle_target()
			var end_effector_pos := mount.arm.solver.get_end_effector()
			var dist := (idle_pos - end_effector_pos).length()
			if dist > 1.0:
				mount.arm.start_step(mount.to_global(idle_pos), 0.0, Vector3.UP, false)
			else:
				mount.sync_from_arm()

func exit() -> void:
	if is_sprinting:
		is_sprinting = false
		_set_arms_as_legs(false)

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

	# ramp toward the target velocity so acceleration is a real, sustained
	# signal instead of an instantaneous step (feeds the camera's pitch/trail)
	var w := 1.0 - exp(-p.movement.accel * dt)
	var target := direction * speed
	p.velocity.x = lerpf(p.velocity.x, target.x, w)
	p.velocity.z = lerpf(p.velocity.z, target.z, w)

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
		_calculate_y_body_offset(dt)

	_update_body_y_offset(dt)
	_handle_jump(direction)

	var want_sprint := Input.is_action_pressed("sprint")
	if want_sprint and !is_sprinting:
		is_sprinting = true
		_set_arms_as_legs(true)
	elif is_sprinting and !want_sprint:
		is_sprinting = false
		_set_arms_as_legs(false)


func _update_camera_alignment(dt: float, is_moving: bool) -> void:
	var p := player

	if is_moving:
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
	elif absf(p.camera_controller.rotation.y) >= disalign_angle:
		is_camera_aligned = false


func _handle_jump(direction: Vector3):
	var p := player

	if Input.is_action_just_pressed("jump"):
		is_holding_jump = true
		jump_hold_time = 0.0

	if Input.is_action_just_released("jump"):
		var charge_f = min(jump_hold_time/p.jump.max_jump_hold_time, 1.0)
		var jump_charge = lerp(p.jump.min_jump_charge, 1.0, charge_f)

		p.velocity.y = p.jump.jump_vertical_velocity * jump_charge
		p.velocity += direction * p.jump.jump_horizontal_velocity
		p.set_state(p.StateID.AIR)
		p.play_jump_effects(jump_charge)

func _update_tilt(dt: float) -> void:
	var p := player
	var c := p.grounded

	var dir := input_dir
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	var current_tilt_x := p.tilt_pivot.rotation.x
	var current_tilt_z := p.tilt_pivot.rotation.z

	var target_tilt_x := dir.y * walk_tilt_x
	var target_tilt_z := -dir.x * walk_tilt_z

	if is_sprinting:
		target_tilt_x *= c.sprint_tilt_multiplier
		if dir.y <= 0.0:
			target_tilt_x += sprint_tilt_x
		target_tilt_z *= c.sprint_tilt_multiplier

	var tilted_x = lerp(current_tilt_x, target_tilt_x, dt * tilt_speed)
	var tilted_z = lerp(current_tilt_z, target_tilt_z, dt * tilt_speed)

	p.tilt_pivot.rotation.x = tilted_x
	p.tilt_pivot.rotation.z = tilted_z

func _update_legs(dt: float) -> void:
	var p := player

	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	var mounts: Array[ArmMount] = p.leg_mounts
	if is_sprinting:
		mounts = p.all_mounts()

	for mount in mounts:
		mount.update_step(p.velocity, dt)
		var other_mounts_grounded := false
		var is_horizontal_mount_grounded := mount.horizontal_mount.arm.is_grounded()
		if is_sprinting:
			var is_diagonal_grounded := mount.diagonal_mount.arm.is_grounded()
			other_mounts_grounded = is_horizontal_mount_grounded and is_diagonal_grounded
		else:
			other_mounts_grounded = is_horizontal_mount_grounded

		var can_step: bool = mount.step_target != null and ((mount.arm.is_grounded()
			and other_mounts_grounded) or mount.arm.is_fully_extended())

		if can_step:
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		var step_speed_mult := 1.0
		if is_sprinting:
			step_speed_mult = p.grounded.sprint_speed_step_multiplier

		best_arm.start_step(best_arm_hit_pos, 0.0, Vector3.UP, true, step_speed_mult)

	var probe_hits := p.mount_prober.get_leg_probe_hits()
	if probe_hits.size() == 0  and grounded_debounce <= 0.0:
		p.set_state(p.StateID.AIR)

func _update_arms(dt: float) -> void:
	if is_sprinting:
		return

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

func _calculate_y_body_offset(dt: float) -> void:
	var p := player

	if Input.is_action_pressed("up"):
		body_y_offset = min(body_y_offset + p.hover.target_change_rate * dt, p.hover.max_y_offset)
	if Input.is_action_pressed("down"):
		body_y_offset = max(body_y_offset - p.hover.target_change_rate * dt, p.hover.min_y_offset)


func _update_body_y_offset(dt:float) -> void:
	var p := player

	var average_y = _calculate_average_target_y()
	if average_y == null:
		return

	var goal_y = average_y + body_y_offset
	var current_y = p.global_position.y
	var height_error = goal_y - current_y
	var target_y_vel = height_error * p.hover.hover_speed
	p.velocity.y = lerp(p.velocity.y, target_y_vel, dt*p.hover.hover_speed)

func _set_arms_as_legs(active: bool) -> void:
	for mount in player.arm_mounts:
		mount.is_leg = active
		if not active:
			mount.arm.start_step(mount.to_global(mount.compute_idle_target()),0.0, Vector3.UP, false)

		else:
			mount.update_ground_step_target(player.velocity)
			var step_target = mount.step_target
			if step_target:
				mount.arm.start_step(step_target)
