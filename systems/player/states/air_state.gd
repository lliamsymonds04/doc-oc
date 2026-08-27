class_name AirState
extends PlayerState

const HAND_VELOCITY_OFFSET_SCALE: float = 0.05
const HAND_VELOCITY_OFFSET_MAX: float = 1.0

func enter() -> void:
	var p := player

	for mount in p.all_mounts():
		var idle_pos = mount.compute_idle_target()

		mount.arm.target = idle_pos
		mount.set_apply_floor(false)

func calculate_hand_velocity_offset(velocity: Vector3) -> Vector3:
	var mag = velocity.length()
	var new_mag = min(mag * HAND_VELOCITY_OFFSET_SCALE, HAND_VELOCITY_OFFSET_MAX)
	return velocity.normalized() * new_mag

func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt

	var velocityRotation := p.velocity.y/40

	p.rotation.y = p.camera_controller.global_rotation.y
	p.camera_controller.rotation.y = 0

	var current_rot_x := p.camera_controller.rotation.x
	var new_rot_x = lerp(current_rot_x, velocityRotation, dt * 60.0)
	p.rotation.x = new_rot_x

	var mount_hit_positions: Dictionary

	var probe_hits := 0
	for mount in p.leg_mounts:
		var probe_pos := mount.ground_probe.global_position
		var hit = mount.get_surface_hit(probe_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if hit:
			probe_hits += 1
			mount_hit_positions[mount] = hit["position"]

	var hand_velocity_offset = calculate_hand_velocity_offset(p.velocity)
	for mount in p.all_mounts():
		mount.arm.target = mount.compute_idle_target() + hand_velocity_offset


	if probe_hits >= 1 and p.velocity.y <= 0.0:
		for mount in p.leg_mounts:
			if mount_hit_positions.has(mount):
				var hit_pos: Vector3 = mount_hit_positions[mount]
				if hit_pos:
					mount.set_target(hit_pos)

			else:
				mount.sync_from_arm()

		for mount in p.arm_mounts:
			mount.set_target(mount.compute_idle_target())

		p.set_state(p.StateID.GROUNDED)
