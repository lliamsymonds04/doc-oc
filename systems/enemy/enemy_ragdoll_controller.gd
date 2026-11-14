class_name EnemyRagdollController
extends RefCounted

const REST_LINEAR_SPEED := 0.5  # m/s below which the proxy counts as settled

# Owns the rigid proxy body that replaces the enemy's CharacterBody when it dies.
const ENEMY_META := "enemy"

var get_up_delay: float = 1.0

# original enemy nodes
var _mesh: Node3D
var _hitbox: CollisionShape3D
var _enemy: EnemyController
var _health_bar: HealthBar
var _health_bar_local_xform: Transform3D

# ragdoll nodes
var _body: RigidBody3D
var _body_collision: CollisionShape3D
var _ragdoll_mesh: Node3D

var _is_ragdoll := false
var _reallign_body := false
var _upright_speed: float
var _downed_seq: float = 0


func _init(enemy: EnemyController, upright_speed: float, ragdoll_mass: float) -> void:
	_enemy = enemy
	_hitbox = enemy.hitbox
	_mesh = enemy.mesh
	_health_bar = enemy.health_bar
	_upright_speed = upright_speed

	_create_body(ragdoll_mass)


func get_body() -> RigidBody3D:
	return _body


func get_ragdoll_mesh() -> Node3D:
	return _ragdoll_mesh


func is_ragdoll() -> bool:
	return _is_ragdoll


func activate() -> void:
	_is_ragdoll = true
	_body.global_transform = _enemy.global_transform
	_body.reset_physics_interpolation()
	_body.visible = true
	_body_collision.set_deferred("disabled", false)
	_body.set_deferred("freeze", false)
	_body.gravity_scale = 1.0
	_enemy.visible = false
	_enemy.hitbox.set_deferred("disabled", true)
	_enemy.set_physics_process(false)

	if _health_bar:
		_health_bar_local_xform = _health_bar.transform
		_health_bar.reparent(_body)
		_health_bar.sync_sprite_origin()


func deactivate() -> void:
	_is_ragdoll = false
	_body.visible = false
	var xform := _body.global_transform
	_body_collision.set_deferred("disabled", true)
	_body.set_deferred("freeze", true)

	_enemy.global_transform = xform
	_enemy.reset_physics_interpolation()
	_enemy.visible = true
	_enemy.hitbox.set_deferred("disabled", false)
	_enemy.set_physics_process(true)
	_enemy.velocity = _body.linear_velocity

	if _health_bar and _health_bar.get_parent() == _body:
		_health_bar.reparent(_enemy)
		_health_bar.transform = _health_bar_local_xform
		_health_bar.sync_sprite_origin()

	_reallign_body = true


## Snaps back to the CharacterBody now, unlike initiate_get_up() which waits for the body to settle.
func unragdoll() -> void:
	# a pending get_up would deactivate again later and teleport the enemy back here
	cancel_get_up()
	if _is_ragdoll:
		deactivate()


func initiate_get_up() -> void:
	_downed_seq += 1
	var seq := _downed_seq

	var calm := 0
	while is_instance_valid(_body):
		if absf(_body.linear_velocity.y) <= REST_LINEAR_SPEED:
			calm += 1
		else:
			calm = 0
		if calm >= 3:
			break
		await _wait(0.1)
	await _wait(get_up_delay)

	if seq != _downed_seq or not is_instance_valid(_enemy):
		return
	if not _enemy.is_dead():
		deactivate()


func cancel_get_up() -> void:
	_downed_seq += 1


func _wait(sec: float) -> void:
	await _enemy.get_tree().create_timer(sec, false).timeout


func _create_body(ragdoll_mass: float) -> void:
	_body = RigidBody3D.new()
	_body.visible = false
	_body.freeze = true
	_body.mass = ragdoll_mass
	_body.continuous_cd = true
	_body.add_to_group(VelocityTrail.GROUP_TRAIL)

	_body.collision_layer = _enemy.collision_layer
	_body.collision_mask = _enemy.collision_mask
	_body.set_meta(ENEMY_META, _enemy)

	_ragdoll_mesh = _mesh.duplicate() as Node3D
	_body.add_child(_ragdoll_mesh)

	var corpse_shape := CollisionShape3D.new()
	corpse_shape.shape = _hitbox.shape
	corpse_shape.position = _hitbox.position
	_body.add_child(corpse_shape)
	_body_collision = corpse_shape

	_enemy.get_parent().add_child(_body)
	_body.global_transform = _enemy.global_transform
	corpse_shape.disabled = true


func make_body_upright(dt: float) -> void:
	if not _reallign_body:
		return

	var current_up := _enemy.global_transform.basis.y.normalized()
	var tilt := current_up.angle_to(Vector3.UP)
	if tilt < 0.02:
		_reallign_body = false
		return

	var fix := Quaternion(current_up, Vector3.UP)
	var step := Quaternion.IDENTITY.slerp(fix, clampf(_upright_speed * dt, 0.0, 1.0))
	var rot = step * _enemy.global_transform.basis.get_rotation_quaternion()
	_enemy.global_transform.basis = Basis(rot)
