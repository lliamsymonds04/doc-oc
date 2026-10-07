extends RefCounted
class_name EnemyRagdollController


# Owns the rigid proxy body that replaces the enemy's CharacterBody when it dies.
const ENEMY_META := "enemy"

var _mesh: MeshInstance3D
var _hitbox: CollisionShape3D
var _enemy: EnemyController
var _body: RigidBody3D
var _body_collision: CollisionShape3D
var _is_ragdoll := false
var _reallign_body := false

var _upright_speed: float


func _init(enemy: EnemyController, upright_speed: float) -> void:
	_enemy = enemy
	_hitbox = enemy.hitbox
	_mesh = enemy.mesh
	_upright_speed = upright_speed

	_create_body()

func get_body() -> RigidBody3D:
	return _body

func get_enemy() -> EnemyController:
	return _enemy

func is_ragdoll() -> bool:
	return _is_ragdoll

func activate() -> void:
	_is_ragdoll = true
	_body.global_transform = _enemy.global_transform
	_body.reset_physics_interpolation()
	_body.visible = true
	_body_collision.set_deferred("disabled", false)
	_body.set_deferred("freeze", false)
	_enemy.visible = false
	_enemy.hitbox.set_deferred("disabled", true)
	_enemy.set_physics_process(false)

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

	_reallign_body = true

func _create_body() -> void:
	_body = RigidBody3D.new()
	_body.visible = false
	_body.freeze = true
	# lets attack/grab controllers identify the proxy as an enemy without a subclass
	_body.set_meta(ENEMY_META, _enemy)

	var corpse_mesh := MeshInstance3D.new()
	corpse_mesh.mesh = _mesh.mesh
	corpse_mesh.position = _mesh.position
	_body.add_child(corpse_mesh)

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
