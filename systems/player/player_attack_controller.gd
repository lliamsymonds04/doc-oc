extends RefCounted
class_name PlayerAttackController

var player: PlayerController
var prev_attack_mount: ArmMount
var last_attack_time: float = -INF
var attack_tilt_y: float = 0.0

var config: PlayerAttackConfig

var _attack_audio_player: AudioStreamPlayer3D
var _hit_audio_player: AudioStreamPlayer3D

var _hit_vfx: ImpactVFX

func _init(p: PlayerController, attack_config: PlayerAttackConfig) -> void:
	player = p
	config = attack_config

	_attack_audio_player = AudioStreamPlayer3D.new()
	_attack_audio_player.stream = config.attack_sound
	p.add_child(_attack_audio_player)

	_hit_audio_player = AudioStreamPlayer3D.new()
	p.add_child(_hit_audio_player)

	if config.hit_vfx_scene != null:
		_hit_vfx = config.hit_vfx_scene.instantiate() as ImpactVFX
		_hit_vfx.top_level = true
		p.add_child(_hit_vfx)

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected)

func try_attack() -> void:
	var now = _get_now()
	if now - last_attack_time < config.attack_debounce:
		return

	var p := player
	if p.is_sprinting():
		return

	var cam_hit := p.camera_controller.get_camera_center_hit(config.attack_cast_range)
	var attack_target: Vector3
	if cam_hit.is_empty():
		var cam_pos = p.camera_controller.cam.global_position
		var cam_dir = p.camera_controller.get_camera_direction()
		attack_target = cam_pos + cam_dir * config.attack_cast_range
	else:
		attack_target = cam_hit["position"]

	for mount in p.arm_mounts:
		if mount == prev_attack_mount:
			continue

		mount.arm.start_punch(attack_target)
		AudioUtil.play_with_pitch(_attack_audio_player)

		var side_dir = sign(mount.position.x)
		attack_tilt_y = side_dir * deg_to_rad(config.attack_tilt_degrees)

		prev_attack_mount = mount
		last_attack_time = now
		var gs := p.grounded_state()
		var look_turn := absf(angle_difference(p.rotation.y, p.camera_controller.global_rotation.y))
		# gate on the real turn size: looking backwards must not spin the body,
		# the planted legs misbehave through a 180 degree turn
		if not gs.is_camera_aligned and look_turn <= deg_to_rad(config.max_force_align_turn_degrees):
			gs.force_align = true
		return

func arm_hit_detected(hit: Vector3, normal: Vector3, collider: Object) -> void:
	if collider is EnemyController:
		# _hit_audio_player.stream
		AudioUtil.play_with_pitch(_hit_audio_player)
	else:
		_hit_audio_player.stream = player.attack.surface_hit_sound
		AudioUtil.play_with_pitch(_hit_audio_player)

	if _hit_vfx:
		_hit_vfx.play(hit, normal)

func process(_dt: float):
	var now = _get_now()
	if attack_tilt_y != 0.0 and now - last_attack_time >= config.tilt_reset_time:
		attack_tilt_y = 0.0


func _get_now() -> float:
	return Time.get_ticks_msec() / 1000.0
