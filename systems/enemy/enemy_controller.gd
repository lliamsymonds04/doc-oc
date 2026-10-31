class_name EnemyController
extends CharacterBody3D

## Enemies register here; throw homing scans it for cone targets.
const ENEMY_GROUP := &"enemy"

@export var damage_flash_duration: float = 0.2
@export var dead_body_cleanup_time: float = 10.0
@export var upright_speed: float = 5.0
@export var ragdoll_mass: float = 3.0
@export var impact_min_dv: float = 4.0  # min velocity jump (m/s) for an impact to hurt
@export var impact_damage_per_dv: float = 2.0
@export var accel: float = 5.0
@export var health_bar: HealthBar

var _ragdoll: EnemyRagdollController
var _damage_flash: DamageFlashUtil
var _ragdoll_flash: DamageFlashUtil
var _death_timer: float
var _target: PlayerController

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hitbox: CollisionShape3D = $Hitbox


func _ready() -> void:
	add_to_group(ENEMY_GROUP)
	health_controller.damage_taken.connect(_on_damage_taken)
	health_controller.healed.connect(_on_healed)
	health_controller.died.connect(_on_death)

	_ragdoll = EnemyRagdollController.new(self, upright_speed, ragdoll_mass)
	var ragdoll_body: RigidBody3D = _ragdoll.get_body()
	var ragdoll_mesh: MeshInstance3D = _ragdoll.get_ragdoll_mesh()
	_ragdoll_flash = DamageFlashUtil.new(ragdoll_body, ragdoll_mesh, damage_flash_duration)
	_damage_flash = DamageFlashUtil.new(self, mesh, damage_flash_duration)

	EnemyUtil.attach_self_damage(self, ragdoll_body, impact_min_dv, impact_damage_per_dv)
	EnemyUtil.attach_impact_damage(ragdoll_body, impact_min_dv)


func take_damage(dmg: float) -> void:
	health_controller.apply_damage(dmg)

	if is_dead():
		initiate_ragdoll(false)


## Shoves `dir`-ward at `speed`; `dir` is flattened and `lift` only pops a grounded enemy.
func apply_knockback(dir: Vector3, speed: float, lift: float) -> void:
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = maxf(velocity.y, lift)


func is_dead() -> bool:
	return health_controller.is_dead()


func get_ragdoll() -> RigidBody3D:
	return _ragdoll.get_body()


func is_ragdolled() -> bool:
	return _ragdoll.is_ragdoll()


func initiate_get_up() -> void:
	if _ragdoll.is_ragdoll():
		_ragdoll.initiate_get_up()


func unragdoll() -> void:
	_ragdoll.unragdoll()


func cancel_get_up() -> void:
	_ragdoll.cancel_get_up()


func _physics_process(dt: float) -> void:
	_ragdoll.make_body_upright(dt)

	velocity += get_gravity() * dt

	var velocity_target := Vector3(0.0, 0.0, 0.0)
	if not _ragdoll.is_ragdoll():
		var target := _get_target()
		if target != null:
			var to := target.global_position - global_position
			to.y = 0.0
			if to.length_squared() > 0.01:
				velocity_target = to.normalized() * 5.0

	var k := 1.0 - exp(-accel * dt)
	velocity.x = lerpf(velocity.x, velocity_target.x, k)
	velocity.z = lerpf(velocity.z, velocity_target.z, k)
	move_and_slide()


func _process(dt: float) -> void:
	if _death_timer > 0.0:
		_death_timer -= dt
		if _death_timer <= 0.0:
			_ragdoll.get_body().queue_free()
			queue_free()


func _on_damage_taken(_dmg: float) -> void:
	if health_bar:
		health_bar.damage_health_bar_tween(health_controller.get_health_float())

	flash()


func _on_healed(_heal: float) -> void:
	if health_bar:
		health_bar.heal_health_bar_tween(health_controller.get_health_float())


func _on_death() -> void:
	if health_bar:
		health_bar.play_death()

	_death_timer = dead_body_cleanup_time


func initiate_ragdoll(should_get_up: bool = true) -> void:
	if _ragdoll.is_ragdoll():
		return
	_ragdoll.activate()

	if should_get_up:
		_ragdoll.initiate_get_up()


func flash(strength: float = 1.0) -> void:
	_ragdoll_flash.flash(strength)
	_damage_flash.flash(strength)


func _get_target() -> PlayerController:
	if is_instance_valid(_target):
		return _target
	_target = get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
	return _target
