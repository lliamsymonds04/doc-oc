class_name PlayerAttackController
extends RefCounted

## Heavy multipliers and the two-arm hit guard are live only for the swing itself, not
## the whole debounce: a tackle punch inside that window is a separate hit.
const SWING_WINDOW: float = 0.3
## One impact effect per arm, so a heavy can show two hits at once.
const HIT_VFX_POOL_SIZE: int = 2

var player: PlayerController
var prev_attack_mount: ArmMount
var last_attack_time: float = -INF
var combo_count: int = 0
var attack_tilt_y: float = 0.0
## Lean actually written to the body; blended to `_tilt_x_target` in process().
var attack_tilt_x: float = 0.0

var config: PlayerAttackConfig

## Debounce gating the *next* punch; longer after a heavy.
var _tilt_x_target: float = 0.0
var _debounce: float = 0.0
var _heavy_active: bool = false
## Latched by the first landing hit of a swing; a heavy's second arm only shows VFX.
var _damaged_this_swing: bool = false
var _hit_sound_played: bool = false

var _attack_audio_player: AudioStreamPlayer3D
var _hit_audio_player: AudioStreamPlayer3D
var _hit_vfx_pool: Array[ImpactVFX] = []
var _hit_vfx_next: int = 0
var _crack_decal_parent: Node3D
var _aiming_at_enemy_in_range: bool = false


func _init(p: PlayerController, attack_config: PlayerAttackConfig) -> void:
	player = p
	config = attack_config
	_debounce = config.attack_debounce

	_attack_audio_player = AudioStreamPlayer3D.new()
	_attack_audio_player.stream = config.attack_sound
	p.add_child(_attack_audio_player)

	_hit_audio_player = AudioStreamPlayer3D.new()
	p.add_child(_hit_audio_player)

	if config.hit_vfx_scene != null:
		for i in HIT_VFX_POOL_SIZE:
			var vfx := config.hit_vfx_scene.instantiate() as ImpactVFX
			vfx.top_level = true
			p.add_child(vfx)
			_hit_vfx_pool.append(vfx)

	# Decals live at scene root so they don't move around with the player.
	_crack_decal_parent = p.get_tree().current_scene

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected)


func try_attack() -> void:
	var now = PlayerPunchUtil.get_now()
	var p := player
	if not PlayerPunchUtil.punch_allowed(p, last_attack_time, _debounce, now):
		return

	if now - last_attack_time > config.combo_reset_time:
		combo_count = 0
	combo_count += 1

	var is_heavy := combo_count % maxi(config.heavy_attack_every, 1) == 0
	_debounce = config.heavy_attack_debounce if is_heavy else config.attack_debounce
	_heavy_active = is_heavy
	_damaged_this_swing = false
	_hit_sound_played = false

	var gs := p.grounded_state()
	var look_turn := absf(angle_difference(p.rotation.y, p.camera_controller.global_rotation.y))
	if not gs.is_camera_aligned and look_turn <= deg_to_rad(config.max_force_align_turn_degrees):
		gs.force_align = true

	if is_heavy:
		for mount in p.arm_mounts:
			_start_punch(mount, true)
		# restart the alternation so the next normal punch picks a clean arm
		prev_attack_mount = null
	else:
		for mount in p.arm_mounts:
			if mount == prev_attack_mount:
				continue
			_start_punch(mount, false)
			prev_attack_mount = mount
			break

	last_attack_time = now


func _start_punch(mount: ArmMount, is_heavy: bool) -> void:
	var side_dir: int = sign(mount.position.x)
	var attack_target = PlayerPunchUtil.get_punch_target(player, side_dir, config.attack_cast_range)

	mount.arm.start_punch(attack_target)
	mount.arm.set_end_effector_trail(true)
	mount.arm.set_trail_style(config.trail_width, config.trail_transparency)
	AudioUtil.play_with_pitch(_attack_audio_player)
	var kick := _swing_kick(is_heavy)
	if kick != 0.0:
		player.camera_controller.kick_fov(kick)

	if is_heavy:
		# negative rotation.x tips the body forward (model faces -Z)
		_tilt_x_target = -deg_to_rad(config.heavy_tilt_degrees)
		attack_tilt_y = 0.0
	else:
		_tilt_x_target = 0.0
		attack_tilt_y = side_dir * deg_to_rad(config.attack_tilt_degrees)


## 1.0 for a normal punch, the heavy multiplier while the heavy swing is live.
func _heavy(mult: float) -> float:
	return mult if _heavy_active and _swing_live() else 1.0


func _swing_live() -> bool:
	return PlayerPunchUtil.get_now() - last_attack_time <= SWING_WINDOW


## Only the heavy widens on the wind-up; firing this every punch would strobe the fov.
func _swing_kick(is_heavy: bool) -> float:
	if not is_heavy:
		return 0.0
	return config.swing_fov_kick * config.heavy_fov_kick_multiplier


func arm_hit_detected(hit: Vector3, normal: Vector3, collider: Object) -> void:
	if player.is_in_grab_mode():
		return

	var enemy := EnemyUtil.resolve_enemy(collider)
	if enemy:
		player.attack_hit.emit(hit, normal, collider)

	# One swing lands once: both arms may connect, but only the first hit plays
	# audio or deals damage. Each arm still gets its own effect from the pool.
	var can_land := _swing_live() and not _damaged_this_swing

	if not _hit_sound_played:
		_hit_sound_played = true
		_hit_audio_player.stream = (config.enemy_hit_sound if enemy else config.surface_hit_sound)
		AudioUtil.play_with_pitch(_hit_audio_player)

	if enemy == null and not collider is RigidBody3D:
		CrackDecal.spawn(_crack_decal_parent, hit, normal)

	if enemy and can_land:
		_damaged_this_swing = true
		_damage_enemy(collider, enemy, hit)
	elif enemy == null and collider is RigidBody3D:
		_impulse_rigid_body(collider, hit)

	player.camera_controller.add_trauma(config.hit_trauma * _heavy(config.heavy_trauma_multiplier))
	player.camera_controller.kick_fov(
		config.hit_fov_kick * _heavy(config.heavy_fov_kick_multiplier)
	)

	_spawn_hit_vfx(hit, normal)


func _spawn_hit_vfx(hit: Vector3, normal: Vector3) -> void:
	if _hit_vfx_pool.is_empty():
		return
	_hit_vfx_pool[_hit_vfx_next].play(hit, normal)
	_hit_vfx_next = (_hit_vfx_next + 1) % _hit_vfx_pool.size()


func _damage_enemy(collider: Object, enemy: EnemyController, hit: Vector3) -> void:
	var damage := config.damage * _heavy(config.heavy_damage_multiplier)

	if collider is EnemyController:
		enemy.apply_knockback(
			enemy.global_position - player.global_position,
			config.knockback_speed * _heavy(config.heavy_knockback_multiplier),
			config.knockback_lift * _heavy(config.heavy_lift_multiplier)
		)
		enemy.take_damage(damage)
		if enemy.is_dead():
			var corpse_vel := enemy.velocity
			corpse_vel.x *= config.death_knockback_multiplier
			corpse_vel.z *= config.death_knockback_multiplier
			# deferred to land after activate()'s deferred unfreeze
			enemy.get_ragdoll().set_deferred("linear_velocity", corpse_vel)
		return

	enemy.take_damage(damage)
	if collider is RigidBody3D:
		_impulse_rigid_body(collider, hit)


func process(dt: float):
	var now = PlayerPunchUtil.get_now()
	var tilt_hold := config.heavy_tilt_reset_time if _heavy_active else config.tilt_reset_time
	if now - last_attack_time >= tilt_hold:
		_tilt_x_target = 0.0
		attack_tilt_y = 0.0
	var rate := config.heavy_tilt_rate if _tilt_x_target != 0.0 else config.heavy_tilt_release_rate
	attack_tilt_x = lerpf(attack_tilt_x, _tilt_x_target, 1.0 - exp(-rate * dt))
	_update_aim_enemy_state()


func _update_aim_enemy_state() -> void:
	var in_range: bool = false
	var hit = player.camera_controller.get_camera_center_hit(config.attack_cast_range)
	if not hit.is_empty():
		var enemy := EnemyUtil.resolve_enemy(hit["collider"])
		in_range = enemy != null and not enemy.is_dead()
	var changed := in_range != _aiming_at_enemy_in_range
	_aiming_at_enemy_in_range = in_range
	if changed:
		player.aim_at_enemy_changed.emit(in_range)


func _impulse_rigid_body(body: RigidBody3D, hit_point: Vector3) -> void:
	var local_hit_point = body.to_local(hit_point)
	var impulse = Vector3.ZERO

	var hit_dir = player.camera_controller.get_camera_direction()
	impulse = hit_dir * config.impulse_strength * _heavy(config.heavy_impulse_multiplier)
	impulse.y = max(impulse.y, player.attack_config.impulse_min_y)
	body.call_deferred("apply_impulse", impulse, local_hit_point)
