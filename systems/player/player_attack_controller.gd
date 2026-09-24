extends RefCounted
class_name PlayerAttackController

const ATTACK_DEBOUNCE: float = 0.5
const ATTACK_CAST_RANGE: float = 15.0
const ATTACK_TILT_ANGLE: float = deg_to_rad(15.0)
const TILT_RESET_TIME: float = 0.3

var player: PlayerController
var prev_attack_mount: ArmMount
var last_attack_time: float = -INF
var attack_tilt_y: float = 0.0

func _init(p: PlayerController) -> void:
	player = p

func try_attack() -> void:
	var now = _get_now()
	if now - last_attack_time < ATTACK_DEBOUNCE:
		return

	var p := player
	if p.is_sprinting():
		return

	var cam_hit := p.camera_controller.get_camera_center_hit(ATTACK_CAST_RANGE)
	var attack_target: Vector3
	if cam_hit.is_empty():
		var cam_pos = p.camera_controller.cam.global_position
		var cam_dir = p.camera_controller.get_camera_direction()
		attack_target = cam_pos + cam_dir * ATTACK_CAST_RANGE
	else:
		attack_target = cam_hit["position"]

	for mount in p.arm_mounts:
		if mount == prev_attack_mount:
			continue

		mount.arm.start_punch(attack_target)
		var side_dir = sign(mount.position.x)
		attack_tilt_y = side_dir * ATTACK_TILT_ANGLE

		prev_attack_mount = mount
		last_attack_time = now
		return

func process(_dt: float):
	var now = _get_now()
	if attack_tilt_y != 0.0 and now - last_attack_time >= TILT_RESET_TIME:
		attack_tilt_y = 0.0


func _get_now() -> float:
	return Time.get_ticks_msec() / 1000.0
