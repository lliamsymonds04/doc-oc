extends RefCounted
class_name PlayerPunchUtil


static func get_now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func get_punch_target(p: PlayerController, side_dir: int, max_dist: float) -> Vector3:
	var attack_offset = (
		p.camera_controller.global_transform.basis.x * side_dir * p.attack_config.attack_side_offset
	)

	var cam_hit := p.camera_controller.get_camera_center_hit(max_dist, attack_offset)
	if cam_hit.is_empty():
		var cam_pos = p.camera_controller.cam.global_position
		var cam_dir = p.camera_controller.get_camera_direction()
		return cam_pos + cam_dir * max_dist
	else:
		return cam_hit["position"] + attack_offset


static func punch_allowed(
	p: PlayerController, last_attack_time: float, debounce: float, now: float
) -> bool:
	return now - last_attack_time >= debounce and not p.is_sprinting()
