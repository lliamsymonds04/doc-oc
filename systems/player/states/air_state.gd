class_name AirState
extends PlayerState


func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt


	var probe_hits := 0
	for mount in p.leg_mounts:
		var probe_pos := mount.ground_probe.global_position
		var hit = mount.get_surface_hit(probe_pos, Vector3.DOWN, p.raycast_config.step_raycast_distance)
		if hit:
			probe_hits += 1

	if probe_hits > 0:
		p.set_state(p.StateID.GROUNDED)
