class_name PlayerTackleController
extends RefCounted

# below this the tackle has effectively stalled; pushing from a near-zero velocity
# just flings the player somewhere arbitrary
const MIN_PUSH_SOURCE_SPEED: float = 0.5

var player: PlayerController
var config: PlayerTackleConfig

var _sphere: SphereShape3D
var _carried: RigidBody3D
var _original_layer: int
var _carry_remaining: float = 0.0


func _init(p: PlayerController, tackle_config: PlayerTackleConfig) -> void:
	player = p
	config = tackle_config
	_sphere = SphereShape3D.new()
	_sphere.radius = config.detect_radius


func is_tackling() -> bool:
	return _carried != null


## Ticked from PlayerController._physics_process: after the state has set velocity,
## before move_and_slide(), so contact resolves in the tick it is predicted.
func physics_update(dt: float) -> void:
	if _carried != null and not is_instance_valid(_carried):
		_carried = null  # corpse cleanup queue_free'd the body mid-carry

	if _carried == null:
		_scan_contact(dt)
		return

	_update_carry(dt)


## Hand placement has to happen after the state's frame_update, which rewrites every
## arm target with its idle pose; same reason PlayerGrabController has a frame pass.
func frame_update() -> void:
	if _carried == null:
		return

	var grip := _grip_world()
	var right := player.global_transform.basis.x
	for mount in player.arm_mounts:
		if mount.arm.is_moving or player.grab_controller.is_mount_grabbing(mount):
			continue
		var side := signf(mount.position.x)
		mount.set_target(grip + right * side * config.grip_side_offset)


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
	# ragdoll first, so everything below deals with one node: the proxy RigidBody3D
	enemy.initiate_ragdoll(false)

	var body := enemy.get_ragdoll()
	_carried = body
	_carry_remaining = config.carry_time
	_original_layer = body.collision_layer
	# HELD_LAYER keeps it out of cast_mask() and out of the player's way while carried
	body.collision_layer = player.HELD_LAYER

	# deferred write lands after activate()'s deferred unfreeze; matching the dash
	# speed here stops the body being left behind before the magnet takes over
	body.call_deferred("set", "linear_velocity", player.velocity)

	_strike()


func _strike() -> void:
	var aim := _carry_anchor() + Vector3.UP * config.aim_height
	for mount in player.arm_mounts:
		var side := signf(mount.position.x)
		var side_aim := aim + player.global_transform.basis.x * side * config.grip_side_offset
		mount.set_apply_floor(false)
		# explicit mask: the carried body is on HELD_LAYER, excluded from cast_mask()
		mount.arm.start_punch(side_aim, ~player.collision_layer)


func _update_carry(dt: float) -> void:
	# nothing in AIR advances limb motion, so the tackle has to tick the punches itself
	for mount in player.arm_mounts:
		if mount.arm.is_moving:
			mount.arm.advance_move(dt)

	var anchor := _carry_anchor()
	var error := anchor - _carried.global_position
	_carried.linear_velocity = (error * config.carry_gain).limit_length(config.max_carry_speed)
	_carried.angular_velocity = Vector3.ZERO

	_carry_remaining -= dt
	if _carry_remaining <= 0.0:
		_release()


func _release() -> void:
	var body := _carried
	_carried = null

	for mount in player.arm_mounts:
		mount.set_apply_floor(not player.is_airborne())

	body.collision_layer = _original_layer
	var enemy: EnemyController = body.get_meta(EnemyRagdollController.ENEMY_META)
	if not enemy.is_dead():
		enemy.initiate_get_up()

	_apply_release_push()


## Follow-through: keep the exit direction but overwrite the magnitude with the
## configured push so the tackle never ends on a weakling dribble of speed.
func _apply_release_push() -> void:
	var dir := player.velocity
	var speed := dir.length()
	if speed < MIN_PUSH_SOURCE_SPEED:
		return
	player.velocity = dir / speed * config.release_push_speed


func _carry_anchor() -> Vector3:
	return player.global_position + player.global_transform.basis * config.carry_offset


func _grip_world() -> Vector3:
	return _carried.get_global_transform_interpolated().origin + Vector3.UP * config.aim_height
