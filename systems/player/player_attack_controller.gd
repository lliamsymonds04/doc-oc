extends RefCounted
class_name PlayerAttackController

const ATTACK_DEBOUNCE: float = 0.5
const ATTACK_CAST_RANGE: float = 15.0
const ATTACK_TILT_ANGLE: float = deg_to_rad(15.0)
const TILT_RESET_TIME: float = 0.3
const MAX_FORCE_ALIGN_TURN: float = deg_to_rad(100.0)

var player: PlayerController
var prev_attack_mount: ArmMount
var last_attack_time: float = -INF
var attack_tilt_y: float = 0.0

var _attack_audio_player: AudioStreamPlayer3D
var _attack_sound := preload("res://assets/audio/small_servo.ogg")

var _hit_vfx_scene := preload("res://assets/vfx/step.tscn")
var _hit_vfx: ImpactVFX

func _init(p: PlayerController) -> void:
	player = p

	_attack_audio_player = AudioStreamPlayer3D.new()
	_attack_audio_player.stream = _attack_sound
	p.add_child(_attack_audio_player)

	_hit_vfx = _hit_vfx_scene.instantiate() as ImpactVFX
	_hit_vfx.top_level = true
	p.add_child(_hit_vfx)

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected)

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
		AudioUtil.play_with_pitch(_attack_audio_player)

		var side_dir = sign(mount.position.x)
		attack_tilt_y = side_dir * ATTACK_TILT_ANGLE

		prev_attack_mount = mount
		last_attack_time = now
		var gs := p.grounded_state()
		var look_turn := absf(angle_difference(p.rotation.y, p.camera_controller.global_rotation.y))
		# gate on the real turn size: looking backwards must not spin the body,
		# the planted legs misbehave through a 180 degree turn
		if not gs.is_camera_aligned and look_turn <= MAX_FORCE_ALIGN_TURN:
			gs.force_align = true
		return

func arm_hit_detected(hit: Vector3, normal: Vector3, collider: Object) -> void:
	if collider is EnemyController:
		print("hit an enemy")
	else:
		print("regular hit")

	if _hit_vfx:
		_hit_vfx.play(hit, normal)

func process(_dt: float):
	var now = _get_now()
	if attack_tilt_y != 0.0 and now - last_attack_time >= TILT_RESET_TIME:
		attack_tilt_y = 0.0


func _get_now() -> float:
	return Time.get_ticks_msec() / 1000.0
