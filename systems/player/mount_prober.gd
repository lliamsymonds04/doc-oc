extends RefCounted
class_name MountProber

var player: PlayerController

func init(p: PlayerController):
	player = p

const VERTICAL_SURFACE_NORMAL_CHECK := acos(deg_to_rad(45))

func try_mount_wall(input: Vector2, player_velocity: Vector3) -> bool:
	var p := player

	if p.wall_climb_debounce > 0.0 and player_velocity.y > p.wall_climb.fall_speed_wall_debounce_bypass:
		return false

	# Player must be holding forwards
	if input.y >= 0.0:
		return false

	var wall_detection_count = 0
	var wall_hits := {}

	for mount in p.arm_mounts:
		# wall raycasts
		if mount.wall_probe != null and mount.arm.is_stepping == false:
			var hit = mount.get_wall_hit_pos(Vector3.ZERO)
			wall_hits[mount] = hit

			if hit != null and (hit.normal as Vector3).dot(p.basis.z) > cos(deg_to_rad(p.wall_climb.wall_mount_max_angle_deg)):
				wall_detection_count += 1

	if wall_detection_count > 1:
		p.set_state(p.StateID.WALL_CLIMB)
		for mount in p.arm_mounts:
			if mount.arm.is_stepping:
				continue

			var hit = wall_hits[mount]
			if hit != null:
				mount.arm.start_step(hit.position, 0.0, hit.normal)
				mount.wall_surface_normal = hit.normal

		return true

	return false

func get_leg_probe_hits() -> Dictionary:
	var probe_hits := {}

	for mount in player.leg_mounts:
		var probe_pos := mount.ground_probe.global_position
		var hit = mount.get_surface_hit(probe_pos, Vector3.DOWN, player.raycast_config.step_raycast_distance)
		if hit:
			## check the surface normal
			if (hit.normal as Vector3).dot(Vector3.UP) < VERTICAL_SURFACE_NORMAL_CHECK:
				continue
			probe_hits[mount] = hit

	return probe_hits
