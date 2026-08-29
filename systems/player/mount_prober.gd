extends RefCounted
class_name MountProber

const WALL_MOUNT_MAX_ANGLE_DEG := 60.0
const FALL_SPEED_WALL_DEBOUNCE_BYPASS := -0.2

var player: PlayerController

func init(p: PlayerController):
	player = p


func try_mount_wall(input: Vector2, player_velocity: Vector3) -> void:
	var p := player

	if p.wall_climb_debounce > 0.0 and player_velocity.y > FALL_SPEED_WALL_DEBOUNCE_BYPASS:
		return

	# Player must be holding forwards
	if input.y >= 0.0:
		return

	var wall_detection_count = 0
	var wall_hits := {}

	for mount in p.arm_mounts:
		# wall raycasts
		if mount.wall_probe != null and mount.arm.is_stepping == false:
			var hit = mount.get_wall_hit_pos(Vector3.ZERO)
			wall_hits[mount] = hit

			if hit != null and (hit.normal as Vector3).dot(p.basis.z) > cos(deg_to_rad(WALL_MOUNT_MAX_ANGLE_DEG)):
				wall_detection_count += 1

	if wall_detection_count > 1:
		p.set_state(p.StateID.WALL_CLIMB)
		for mount in p.arm_mounts:
			if mount.arm.is_stepping:
				continue

			mount.set_apply_floor(false)
			var hit = wall_hits[mount]
			if hit != null:
				mount.arm.start_step(hit.position)
				mount.wall_surface_normal = hit.normal

func get_leg_probe_hits() -> Dictionary:
	var probe_hits := {}

	for mount in player.leg_mounts:
		var probe_pos := mount.ground_probe.global_position
		var hit = mount.get_surface_hit(probe_pos, Vector3.DOWN, player.raycast_config.step_raycast_distance)
		if hit:
			probe_hits[mount] = hit

	return probe_hits
