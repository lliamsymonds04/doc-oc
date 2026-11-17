extends Node

## Headless check for the EnemyConfig -> EnemyAttack mapping. Run with:
##   godot --headless --path . res://tests/test_enemy_config.tscn
## Exits non-zero when any check fails.

const ENEMY_SCENE := preload("res://systems/enemy/axe_bot.tscn")

var _failures := 0


func _ready() -> void:
	_test_missing_attack_falls_back()
	_test_melee_config_maps_to_melee()
	_test_slam_config_maps_to_slam()
	_test_scene_default_uses_melee()
	_test_slam_lead_shrinks_on_short_dive()
	_test_can_start_respects_range()
	await _test_hop_launches()

	if _failures == 0:
		print("All enemy config checks passed.")
	else:
		printerr("%d enemy config check(s) failed." % _failures)
	get_tree().quit(_failures)


## A config resource saved without an attack used to leave the enemy holding the
## do-nothing base strategy, so it closed in and never swung.
func _test_missing_attack_falls_back() -> void:
	var enemy := _spawn(EnemyConfig.new())
	_check(enemy._attack is EnemyMeleeAttack, "empty attack slot falls back to melee")
	enemy.queue_free()


func _test_melee_config_maps_to_melee() -> void:
	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	var enemy := _spawn(config)
	_check(enemy._attack is EnemyMeleeAttack, "melee config maps to EnemyMeleeAttack")
	enemy.queue_free()


func _test_slam_config_maps_to_slam() -> void:
	var config := EnemyConfig.new()
	config.attack = SlamAttackConfig.new()
	var enemy := _spawn(config)
	_check(enemy._attack is EnemySlamAttack, "slam config maps to EnemySlamAttack")
	enemy.queue_free()


func _test_scene_default_uses_melee() -> void:
	var enemy := ENEMY_SCENE.instantiate() as EnemyController
	add_child(enemy)
	_check(enemy._attack is EnemyMeleeAttack, "axe_bot.tscn defaults to melee")
	enemy.queue_free()


func _test_slam_lead_shrinks_on_short_dive() -> void:
	var config := EnemyConfig.new()
	var slam_config := SlamAttackConfig.new()
	slam_config.slam_lead = 4.0
	config.attack = slam_config
	var enemy := _spawn(config)
	var slam := enemy._attack as EnemySlamAttack

	slam._dive_height = 4.0
	_check(is_equal_approx(slam._slam_lead(), 4.0), "a full dive keeps the configured lead")

	slam._dive_height = 0.5
	_check(slam._slam_lead() < 1.0, "a short dive pulls the lead in")
	enemy.queue_free()


func _test_can_start_respects_range() -> void:
	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	config.attack.detection_range = 2.0
	var enemy := _spawn(config)
	_check(enemy._attack.can_start(1.0), "attack starts inside detection range")
	_check(not enemy._attack.can_start(2.5), "attack does not start out of range")
	enemy.queue_free()


## A hop has to leave the floor upward and carry the walk speed forward; the
## rest timer is what spaces the arcs out.
func _test_hop_launches() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)
	add_child(ground)

	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	config.hop_height = 1.2
	config.move_speed = 4.0
	config.hop_rest = 0.2
	var enemy := _spawn(config)
	enemy.global_position = Vector3(0.0, 0.1, 0.0)
	for i in 30:
		await get_tree().physics_frame
		if enemy.is_on_floor():
			break

	enemy.velocity = Vector3.ZERO
	var hop := enemy.get_movement() as HopMovement
	var carry := hop.desired_velocity(1.0 / 60.0, 5.0, Vector3.FORWARD)
	_check(enemy.is_on_floor(), "hop test enemy is grounded")
	_check(enemy.velocity.y > 2.0, "a hop launches the body upward")
	_check(is_equal_approx(carry.length(), config.move_speed), "a hop carries walk speed")
	_check(hop._rest > 0.0, "a hop starts the ground rest")

	enemy.queue_free()
	ground.queue_free()


## `config` is assigned after the scene's `_init()` and before `_ready()`, which
## is the order that broke the old fallback.
func _spawn(config: EnemyConfig) -> EnemyController:
	var enemy := ENEMY_SCENE.instantiate() as EnemyController
	enemy.config = config
	add_child(enemy)
	return enemy


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
		return
	_failures += 1
	printerr("[FAIL] ", message)
