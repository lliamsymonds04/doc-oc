class_name EnemyController
extends CharacterBody3D

## Enemies register here; throw homing scans it for cone targets.
const ENEMY_GROUP := &"enemy"

## Own layer so the player (layer 2, mask 1) passes through; the mask keeps
## world (layer 1) and enemy-vs-enemy contacts.
const ENEMY_LAYER := 8
const ENEMY_MASK := 1 | ENEMY_LAYER
const DEATH_SOUND := preload("res://assets/audio/enemy/enemy_death.wav")

## Kills this run; main.gd resets it on scene start and the death screen reads it.
static var kill_count := 0

@export var config: EnemyConfig
@export var health_bar: HealthBar

var _navigation_iteration := 0
var _navigation_goal := Vector2.ZERO
var _navigation_path := PackedVector3Array()
var _waypoint_index := 0
var _ragdoll: EnemyRagdollController
var _attack: EnemyAttack
var _movement: EnemyMovement
var _damage_flash: DamageFlashUtil
var _ragdoll_flash: DamageFlashUtil
var _death_timer: float
var _target: PlayerController

@onready var health_controller: HealthController = $HealthController
## Whatever holds the visual: a plain mesh, or an imported model scene wrapping one.
@onready var mesh: Node3D = $Mesh
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
	var ragdoll_mesh: Node3D = _ragdoll.get_ragdoll_mesh()
	_ragdoll_flash = DamageFlashUtil.new(ragdoll_body, ragdoll_mesh, config.damage_flash_duration)
	for child: MeshInstance3D in ragdoll_mesh.find_children("*", "MeshInstance3D", true, false):
		_ragdoll_flash.add_mesh(child)

	_damage_flash = DamageFlashUtil.new(self, mesh, config.damage_flash_duration)
	for child: MeshInstance3D in mesh.find_children("*", "MeshInstance3D", true, false):
		_damage_flash.add_mesh(child)

	EnemyUtil.attach_self_damage(
		self, ragdoll_body, config.impact_min_dv, config.impact_damage_per_dv
	)
	EnemyUtil.attach_impact_damage(ragdoll_body, config.impact_min_dv)

	_movement = _create_movement()


## Maps the injected movement config to its locomotion mode. The modes are
## exclusive, so a config that sets two of them is a mistake and hover wins.
func _create_movement() -> EnemyMovement:
	var hovering := config.hover_height > 0.0
	var hopping := config.hop_height > 0.0

	if hovering and hopping:
		push_error("EnemyConfig sets both hover_height and hop_height, hover wins: %s" % config)

	if hovering:
		return HoverMovement.new(self)

	if hopping:
		return HopMovement.new(self)

	return WalkMovement.new(self)


## Maps the injected attack config to its strategy.
func _create_attack() -> EnemyAttack:
	var attack_config := config.attack
	if attack_config == null:
		attack_config = MeleeAttackConfig.new()

	if attack_config is FireballAttackConfig:
		return EnemyFireballAttack.new(self, attack_config as FireballAttackConfig)

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


func get_movement() -> EnemyMovement:
	return _movement


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

	_movement.apply_vertical(dt)

	_attack.physics_update(dt)

	var velocity_target := Vector3.ZERO
	var target := get_target()
	var walker := _movement as WalkMovement
	if walker != null and (target == null or _ragdoll.is_ragdoll()):
		walker.cancel_climb()
	if _ragdoll.is_ragdoll():
		_navigation_iteration = 0
	else:
		var to := Vector3.ZERO
		if target != null:
			to = target.global_position - global_position

		if _attack.is_committed():
			_turn_toward(_attack.committed_facing(to), dt, _attack.committed_turn_speed())
			velocity_target = _attack.committed_velocity()
		elif target != null:
			if _attack.can_start(to.length()) and (walker == null or has_clear_target(target)):
				_turn_toward(to, dt, config.turn_speed)
				_attack.start()
			else:
				velocity_target = _chase(target, dt)

		if walker != null and _attack.is_committed():
			walker.hold_wall()

	var k := 1.0 - exp(-config.accel * dt)
	velocity.x = lerpf(velocity.x, velocity_target.x, k)
	velocity.z = lerpf(velocity.z, velocity_target.z, k)

	move_and_slide()
	_movement.after_slide(dt)


func _chase(target: PlayerController, dt: float) -> Vector3:
	var goal := target.global_position
	var walker := _movement as WalkMovement
	var wall := {}
	if walker != null:
		wall = walker.climb_target(target)
		if not wall.is_empty():
			goal = wall["position"]

	var waypoint := _chase_waypoint(goal)
	var detour := _waypoint_index < _navigation_path.size() - 1

	var heading := waypoint - global_position
	heading.y = 0.0
	if walker != null:
		if wall.is_empty() and target.global_position.y < global_position.y - 1.0:
			walker.cancel_climb()
		var wall_heading := goal - global_position
		wall_heading.y = 0.0
		if walker.climb(wall_heading.normalized(), wall.get("rid", RID()), target, dt):
			var direction := walker.climb_direction(wall_heading)
			_turn_toward(direction, dt, config.turn_speed)
			return direction * config.move_speed

	_turn_toward(heading, dt, config.turn_speed)
	var offset := target.global_position - global_position
	var distance := offset.length()
	if config.horizontal_stop_distance:
		distance = Vector2(offset.x, offset.z).length()
	var blocked := distance <= config.stop_distance and not has_clear_target(target)
	if detour or not wall.is_empty() or blocked:
		distance = INF
	if config.horizontal_stop_distance and distance < INF:
		var gap := distance - config.stop_distance
		var speed := minf(absf(gap) * config.accel * 0.25, config.move_speed)
		if gap < 0.0:
			# Step out from underneath a player who moved inside the stopping gap.
			var away := Vector3(-offset.x, 0.0, -offset.z).normalized()
			if away.is_zero_approx():
				away = global_basis.z
				away.y = 0.0
			return away.normalized() * speed
		return heading.normalized() * speed

	return _movement.desired_velocity(dt, distance, heading.normalized())


func _chase_waypoint(goal: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if iteration == 0 or _on_elevated_floor(map):
		_navigation_iteration = 0
		_navigation_path.clear()
		_waypoint_index = 0
		return goal

	var goal_xz := Vector2(goal.x, goal.z)
	if iteration != _navigation_iteration or goal_xz.distance_to(_navigation_goal) > 0.5:
		_navigation_iteration = iteration
		_navigation_goal = goal_xz
		_navigation_path = NavigationServer3D.map_get_path(map, global_position, goal, true)
		# The first point is the projected start. Steer toward the first corner.
		_waypoint_index = 1

	# The route lies on the floor, so hovering and hopping must not affect
	# whether the enemy has reached a waypoint.
	while _waypoint_index < _navigation_path.size():
		var point := _navigation_path[_waypoint_index]
		var offset := Vector2(point.x - global_position.x, point.z - global_position.z)
		if offset.length_squared() > 0.36:
			return point
		_waypoint_index += 1

	return goal


func _on_elevated_floor(map: RID) -> bool:
	if not is_on_floor():
		return false
	var ground := NavigationServer3D.map_get_closest_point(map, global_position)
	return global_position.y > ground.y + 1.0


func has_clear_target(target: PlayerController) -> bool:
	var to := target.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(hitbox.global_position, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _turn_toward(to: Vector3, dt: float, turn_speed: float) -> void:
	if Vector2(to.x, to.z).length_squared() < 0.000001 or turn_speed <= 0.0:
		return

	var goal_yaw := atan2(-to.x, -to.z)
	var step := turn_speed * dt
	rotation.y += clampf(angle_difference(rotation.y, goal_yaw), -step, step)


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
	kill_count += 1

	var death_audio := AudioStreamPlayer3D.new()
	death_audio.stream = DEATH_SOUND
	var audio_parent: Node3D = _ragdoll.get_body() if is_ragdolled() else self
	audio_parent.add_child(death_audio)
	death_audio.play()

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
	if not is_instance_valid(_target):
		_target = (
			get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
		)
	# otherwise enemies would keep swinging at the death spot forever
	if is_instance_valid(_target) and _target.is_dead():
		return null
	return _target
