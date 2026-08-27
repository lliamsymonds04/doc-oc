class_name AirState
extends PlayerState

func enter() -> void:
	var p := player

	for mount in p.all_mounts():
		var idle_pos = mount.compute_idle_target()

		mount.arm.target = idle_pos
		mount.set_apply_floor(false)

func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt

	p.rotation.y = p.spring_arm.global_rotation.y
	p.spring_arm.rotation.y = 0.0

	var mount_hit_positions: Dictionary

	var probe_hits := 0
	for mount in p.leg_mounts:
		var probe_pos := mount.ground_probe.global_position
		var hit = mount.get_surface_hit(probe_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if hit:
			probe_hits += 1
			mount_hit_positions[mount] = hit["position"]

	for mount in p.all_mounts():
		mount.arm.target = mount.compute_idle_target()

	if probe_hits >= 1 and p.velocity.y <= 0.0:
		for mount in p.leg_mounts:
			# Plant at the actual ground contact instead of the current tip, so the
			# first update_step finds no displacement and doesn't start a landing step.
			if mount_hit_positions.has(mount):
				var hit_pos: Vector3 = mount_hit_positions[mount]
				if hit_pos:
					mount.set_target(hit_pos)

			else:
				mount.sync_from_arm()

		for mount in p.arm_mounts:
			mount.set_target(mount.compute_idle_target())

		p.set_state(p.StateID.GROUNDED)
