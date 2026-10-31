class_name EnemyController
extends CharacterBody3D

## IDLE -> WINDUP -> SWING -> RECOVERY -> IDLE.
enum Phase { IDLE, WINDUP, SWING, RECOVERY }

## Enemies register here; throw homing scans it for cone targets.
const ENEMY_GROUP := &"enemy"

## Own layer so the player (layer 2, mask 1) passes through; the mask keeps
## world (layer 1) and enemy-vs-enemy contacts.
const ENEMY_LAYER := 8
const ENEMY_MASK := 1 | ENEMY_LAYER

## Anticipation and release shapes for the windup telegraph.
const SQUASH := Vector3(1.25, 0.75, 1.25)
const STRETCH := Vector3(0.85, 1.25, 0.85)

@export var damage_flash_duration: float = 0.2
@export var health_bar: HealthBar
@export_group("ragdoll")
@export var dead_body_cleanup_time: float = 10.0
@export var upright_speed: float = 5.0
@export var ragdoll_mass: float = 3.0
@export var impact_min_dv: float = 4.0  # min velocity jump (m/s) for an impact to hurt
@export var impact_damage_per_dv: float = 2.0
@export_group("movement")
@export var move_speed: float = 3.0
@export var accel: float = 5.0
@export_group("attack")
@export var attack_detection_range = 2.0
## Telegraph: the enemy plants its feet and only winds up.
@export var attack_windup: float = 0.35
## Committed swing; damage lands on its first frame.
@export var attack_swing: float = 0.12
## Recovery doubles as the cooldown before another windup can start.
@export var attack_cooldown: float = 1.0
@export var attack_damage: float = 10.0

var _ragdoll: EnemyRagdollController
var _damage_flash: DamageFlashUtil
var _ragdoll_flash: DamageFlashUtil
var _death_timer: float
var _target: PlayerController
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _mesh_rest_position: Vector3
var _squash_tween: Tween

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hitbox: CollisionShape3D = $Hitbox


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = ENEMY_MASK
	_mesh_rest_position = mesh.position

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

	if _phase != Phase.IDLE:
		_phase_timer -= dt
		if _phase_timer <= 0.0:
			_advance_phase()

	var velocity_target := Vector3(0.0, 0.0, 0.0)
	# windup and swing are committed: the enemy plants its feet for both
	if not _ragdoll.is_ragdoll() and _phase != Phase.WINDUP and _phase != Phase.SWING:
		var target := _get_target()
		if target != null:
			var to := target.global_position - global_position
			to.y = 0.0
			if to.length_squared() > 0.01 and to.length() > 1.5:
				velocity_target = to.normalized() * 5.0

			if _phase == Phase.IDLE and _target_in_range(target):
				_start_attack()

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
	_cancel_attack()
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


func _start_attack() -> void:
	_phase = Phase.WINDUP
	_phase_timer = attack_windup
	_play_squash()


func _advance_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_phase = Phase.SWING
			_phase_timer = attack_swing
			_strike()
		Phase.SWING:
			_phase = Phase.RECOVERY
			_phase_timer = attack_cooldown
		Phase.RECOVERY:
			_phase = Phase.IDLE
			_phase_timer = 0.0


## Range is re-checked here so a target that left during the windup is not hit.
func _strike() -> void:
	var target := _get_target()
	if target != null and _target_in_range(target):
		target.take_damage(attack_damage)


func _target_in_range(target: PlayerController) -> bool:
	var to := target.global_position - global_position
	to.y = 0.0
	return to.length() < attack_detection_range


func _cancel_attack() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_stop_squash()


## Anticipate through the windup, release into the swing, snap back on recovery.
## Durations mirror the phase timers so the shape peaks on the frame damage lands.
func _play_squash() -> void:
	_stop_squash()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween_scale(tw, SQUASH, attack_windup)
	_tween_scale(tw, STRETCH, attack_swing)
	_tween_scale(tw, Vector3.ONE, attack_swing)
	_squash_tween = tw


func _stop_squash() -> void:
	if _squash_tween:
		_squash_tween.kill()
		_squash_tween = null
	mesh.scale = Vector3.ONE
	mesh.position = _mesh_rest_position


## CapsuleMesh's origin is its centre, so a vertical scale has to lift the node
## as well or the base floats off the ground.
func _tween_scale(tw: Tween, target: Vector3, duration: float) -> void:
	tw.tween_property(mesh, "scale", target, duration)
	tw.parallel().tween_property(mesh, "position:y", _mesh_rest_position.y * target.y, duration)
