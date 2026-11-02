class_name EnemyController
extends CharacterBody3D

## Enemies register here; throw homing scans it for cone targets.
const ENEMY_GROUP := &"enemy"

## Own layer so the player (layer 2, mask 1) passes through; the mask keeps
## world (layer 1) and enemy-vs-enemy contacts.
const ENEMY_LAYER := 8
const ENEMY_MASK := 1 | ENEMY_LAYER

@export var config: EnemyConfig
@export var health_bar: HealthBar

var _ragdoll: EnemyRagdollController
var _attack: EnemyAttack
var _damage_flash: DamageFlashUtil
var _ragdoll_flash: DamageFlashUtil
var _death_timer: float
var _target: PlayerController

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hitbox: CollisionShape3D = $Hitbox


func _init() -> void:
	if config == null:
		config = EnemyConfig.new()


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = ENEMY_MASK

	add_to_group(ENEMY_GROUP)
	health_controller.damage_taken.connect(_on_damage_taken)
	health_controller.healed.connect(_on_healed)
	health_controller.died.connect(_on_death)

	_attack = _create_attack()

	_ragdoll = EnemyRagdollController.new(self, config.upright_speed, config.ragdoll_mass)
	var ragdoll_body: RigidBody3D = _ragdoll.get_body()
	var ragdoll_mesh: MeshInstance3D = _ragdoll.get_ragdoll_mesh()
	_ragdoll_flash = DamageFlashUtil.new(ragdoll_body, ragdoll_mesh, config.damage_flash_duration)
	_damage_flash = DamageFlashUtil.new(self, mesh, config.damage_flash_duration)

	EnemyUtil.attach_self_damage(
		self, ragdoll_body, config.impact_min_dv, config.impact_damage_per_dv
	)
	EnemyUtil.attach_impact_damage(ragdoll_body, config.impact_min_dv)


## Maps the injected attack config to its strategy.
func _create_attack() -> EnemyAttack:
	var attack_config := config.attack
	if attack_config == null:
		attack_config = MeleeAttackConfig.new()

	if attack_config is SlamAttackConfig:
		return EnemySlamAttack.new(self, attack_config as SlamAttackConfig)

	if attack_config is MeleeAttackConfig:
		return EnemyMeleeAttack.new(self, attack_config as MeleeAttackConfig)

	push_error("EnemyConfig.attack has no strategy: %s" % attack_config)
	return EnemyAttack.new(self)


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

	_attack.physics_update(dt)

	var velocity_target := Vector3.ZERO
	if not _ragdoll.is_ragdoll():
		if _attack.is_committed():
			velocity_target = _attack.committed_velocity()
		else:
			var target := get_target()
			if target != null:
				var to := target.global_position - global_position
				to.y = 0.0
				var dist := to.length()
				if dist > config.stop_distance:
					velocity_target = to.normalized() * config.move_speed

				if _attack.can_start(dist):
					_attack.start()

	var k := 1.0 - exp(-config.accel * dt)
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

	_death_timer = config.dead_body_cleanup_time


func initiate_ragdoll(should_get_up: bool = true) -> void:
	if _ragdoll.is_ragdoll():
		return
	_attack.cancel()
	_ragdoll.activate()

	if should_get_up:
		_ragdoll.initiate_get_up()


func flash(strength: float = 1.0) -> void:
	_ragdoll_flash.flash(strength)
	_damage_flash.flash(strength)


## The attack strategies and anyone re-checking range share this lookup.
func get_target() -> PlayerController:
	if is_instance_valid(_target):
		return _target
	_target = get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
	return _target
