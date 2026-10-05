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
var _crack_decal_parent: Node3D

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

	# Decals live at scene root so they don't move around with the player.
	_crack_decal_parent = p.get_tree().current_scene

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected)

func try_attack() -> void:
	var now = _get_now()
	var p := player
	if not PlayerPunchUtil.punch_allowed(p, last_attack_time, config.attack_debounce, now):
		return

	for mount in p.arm_mounts:
		if mount == prev_attack_mount:
			continue

		var side_dir: int = sign(mount.position.x)
		var attack_target = _get_target(side_dir)

		mount.arm.start_punch(attack_target)
		AudioUtil.play_with_pitch(_attack_audio_player)

		attack_tilt_y = side_dir * deg_to_rad(config.attack_tilt_degrees)

		prev_attack_mount = mount
		last_attack_time = now

		var gs := p.grounded_state()
		var look_turn := absf(angle_difference(p.rotation.y, p.camera_controller.global_rotation.y))
		if not gs.is_camera_aligned and look_turn <= deg_to_rad(config.max_force_align_turn_degrees):
			gs.force_align = true

		return

func arm_hit_detected(hit: Vector3, normal: Vector3, collider: Object) -> void:
	if player.is_in_grab_mode():
		return

	var is_enemy_hit: bool = collider is EnemyController or collider.is_in_group("enemy_corpse")
	if is_enemy_hit:
		player.attack_hit.emit(hit, normal, collider)
		_hit_audio_player.stream = player.attack_config.enemy_hit_sound
	else:
		_hit_audio_player.stream = player.attack_config.surface_hit_sound

	AudioUtil.play_with_pitch(_hit_audio_player)

	if not is_enemy_hit and not collider is RigidBody3D:
		CrackDecal.spawn(_crack_decal_parent, hit, normal)

	if collider is EnemyController:
		var enemy: EnemyController = collider

		enemy.take_damage(player.attack_config.damage)

		if enemy.is_dead():
			var death_body := enemy.get_death_body()
			if death_body:
				_impulse_rigid_body(death_body, hit)

	elif collider is RigidBody3D:
		_impulse_rigid_body(collider, hit)

	player.camera_controller.add_trauma(player.attack_config.hit_trauma)
	player.camera_controller.kick_fov(player.attack_config.hit_fov_kick)

	if _hit_vfx:
		_hit_vfx.play(hit, normal)

func process(_dt: float):
	var now = _get_now()
	if attack_tilt_y != 0.0 and now - last_attack_time >= config.tilt_reset_time:
		attack_tilt_y = 0.0

func _get_now() -> float:
	return PlayerPunchUtil.get_now()

func _get_target(side_dir: int = 0) -> Vector3:
	return PlayerPunchUtil.get_punch_target(player, side_dir, config.attack_cast_range)

func _impulse_rigid_body(body: RigidBody3D, hit_point: Vector3) -> void:
	var local_hit_point = body.to_local(hit_point)
	var impulse = Vector3.ZERO

	var hit_dir = player.camera_controller.get_camera_direction()
	impulse = hit_dir * player.attack_config.impulse_strength
	impulse.y = max(impulse.y, player.attack_config.impulse_min_y)
	body.apply_impulse(impulse,local_hit_point)
