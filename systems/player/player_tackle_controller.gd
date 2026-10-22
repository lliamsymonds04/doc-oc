class_name PlayerTackleController
extends RefCounted

enum Phase { IDLE, WINDUP, FLOATING }

const MIN_PUSH_SOURCE_SPEED: float = 0.5

var player: PlayerController
var config: PlayerTackleConfig

var _sphere: SphereShape3D
var _body: RigidBody3D
var _original_layer: int
var _original_gravity_scale: float
var _original_linear_damp: float
var _phase: Phase = Phase.IDLE
var _timer: float = 0.0

var _impact_player: AudioStreamPlayer3D


func _init(p: PlayerController, tackle_config: PlayerTackleConfig) -> void:
	player = p
	config = tackle_config
	_sphere = SphereShape3D.new()
	_sphere.radius = config.detect_radius

	_impact_player = AudioStreamPlayer3D.new()
	_impact_player.stream = config.impact_sound
	p.add_child(_impact_player)


func is_tackling() -> bool:
	return _phase == Phase.WINDUP


func physics_update(dt: float) -> void:
	if _phase != Phase.IDLE and not is_instance_valid(_body):
		_abort()  # corpse cleanup freed the body mid-tackle

	if _phase == Phase.IDLE:
		_scan_contact(dt)
		return

	# nothing in AIR advances limb motion, so the tackle has to tick the punches itself
	for mount in player.arm_mounts:
		if mount.arm.is_moving:
			mount.arm.retarget_move(_punch_aim(mount))
			mount.arm.advance_move(dt)

	_timer -= dt
	if _timer > 0.0:
		if _phase == Phase.WINDUP:
			_ride_with_player()
		return

	if _phase == Phase.WINDUP:
		_launch()
	else:
		_end_float()


func _scan_contact(dt: float) -> void:
	var p := player
	if not p.is_airborne():
		return

	var hvel := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if hvel.length() < config.min_dash_speed:
		return

	var origin := p.global_position + Vector3.UP * config.probe_height
	var hit = RaycastUtil.shape_cast(
		p.get_world_3d().direct_space_state, _sphere, origin, p.velocity * dt, p.cast_mask()
	)
	if hit == null:
		return

	var enemy := EnemyUtil.resolve_enemy(hit["collider"])
	if enemy == null or enemy.is_dead():
		return

	_begin(enemy)


func _begin(enemy: EnemyController) -> void:
	# ragdoll first: everything below operates on the proxy RigidBody3D
	enemy.initiate_ragdoll(false)

	_body = enemy.get_ragdoll()
	_original_layer = _body.collision_layer
	_original_gravity_scale = _body.gravity_scale
	_original_linear_damp = _body.linear_damp
	_body.collision_layer = player.HELD_LAYER

	# deferred because activate() unfreezes the body with set_deferred too
	_apply_ride.call_deferred(_clearance_push(), player.velocity)

	_phase = Phase.WINDUP
	_timer = _windup_time()

	_strike()


func _strike() -> void:
	for mount in player.arm_mounts:
		mount.set_apply_floor(false)
		mount.arm.start_punch(
			_punch_aim(mount), ~player.collision_layer, config.punch_speed_multiplier
		)
		mount.arm.set_end_effector_trail(true)
		mount.arm.set_trail_style(
			player.attack_config.trail_width, player.attack_config.trail_transparency
		)


func _windup_time() -> float:
	var longest := 0.0
	for mount in player.arm_mounts:
		longest = maxf(longest, mount.arm.punch_duration / config.punch_speed_multiplier)
	return longest + config.launch_delay


func _ride_with_player() -> void:
	_body.linear_velocity = player.velocity
	_body.angular_velocity = Vector3.ZERO


## Signed along the tackle direction
func _clearance_push() -> Vector3:
	var forward := _flat_forward()
	var offset := _body.global_position - player.global_position
	var ahead := Vector3(offset.x, 0.0, offset.z).dot(forward)
	var overlap := config.carry_clearance - ahead
	if overlap <= 0.0:
		return Vector3.ZERO
	return forward * overlap


func _apply_ride(push: Vector3, velocity: Vector3) -> void:
	if not is_instance_valid(_body):
		return

	if push != Vector3.ZERO:
		_body.global_position += push
		_body.reset_physics_interpolation()
	_body.linear_velocity = velocity


## Relative to the player, not the enemy; physics_update re-aims it every tick.
func _punch_aim(mount: ArmMount) -> Vector3:
	var aim := player.global_position + _flat_forward() * config.punch_distance
	aim.y = _body.global_position.y + config.aim_height
	aim += player.global_transform.basis.x * signf(mount.position.x) * config.grip_side_offset
	return aim


func _flat_forward() -> Vector3:
	var forward := player.camera_controller.get_camera_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -player.global_transform.basis.z
		forward.y = 0.0
	return forward.normalized()


func _launch() -> void:
	var horizontal := _flat_forward()

	# clears the ground without dragging a body already above the player down to them
	var pos := _body.global_position
	pos.y = maxf(player.global_position.y + config.snap_lift, pos.y)

	var velocity := horizontal * config.launch_speed + Vector3.UP * config.launch_up_speed
	var spin := (
		player.global_transform.basis.x * randf_range(-config.tumble_speed, config.tumble_speed)
	)
	_body.gravity_scale = config.float_gravity_scale
	_body.linear_damp = config.float_linear_damp

	# deferred for the same reason as _apply_ride
	_apply_launch_state.call_deferred(pos, velocity, spin)

	_apply_release_push()
	_juice()

	_phase = Phase.FLOATING
	_timer = config.float_time


## Order matters: reset_physics_interpolation() has to follow the teleport.
func _apply_launch_state(pos: Vector3, velocity: Vector3, spin: Vector3) -> void:
	if not is_instance_valid(_body):
		return

	_body.global_position = pos
	_body.linear_velocity = velocity
	_body.angular_velocity = spin
	_body.reset_physics_interpolation()


func _end_float() -> void:
	var body := _body
	_body = null
	_phase = Phase.IDLE

	body.collision_layer = _original_layer
	body.gravity_scale = _original_gravity_scale
	body.linear_damp = _original_linear_damp
	var enemy: EnemyController = body.get_meta(EnemyRagdollController.ENEMY_META)
	if not enemy.is_dead():
		enemy.initiate_get_up()


func _abort() -> void:
	_body = null
	_phase = Phase.IDLE
	_timer = 0.0


func _apply_release_push() -> void:
	var dir := player.velocity
	var speed := dir.length()
	if speed < MIN_PUSH_SOURCE_SPEED:
		return
	player.velocity = dir / speed * config.release_push_speed
	player.velocity.y = maxf(player.velocity.y, config.release_lift)


func _juice() -> void:
	player.camera_controller.add_trauma(config.launch_trauma)
	player.camera_controller.kick_fov(config.launch_fov_kick)
	AudioUtil.play_with_pitch(_impact_player)
