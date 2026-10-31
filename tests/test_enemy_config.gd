extends Node

## Headless check for the EnemyConfig -> EnemyAttack mapping. Run with:
##   godot --headless --path . res://tests/test_enemy_config.tscn
## Exits non-zero when any check fails.

const ENEMY_SCENE := preload("res://systems/enemy/basic_enemy.tscn")

var _failures := 0


func _ready() -> void:
	_test_missing_attack_falls_back()
	_test_melee_config_maps_to_melee()
	_test_no_config_uses_defaults()
	_test_can_start_respects_range()

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


func _test_no_config_uses_defaults() -> void:
	var enemy := ENEMY_SCENE.instantiate() as EnemyController
	add_child(enemy)
	_check(enemy._attack is EnemyMeleeAttack, "no config at all still attacks")
	enemy.queue_free()


func _test_can_start_respects_range() -> void:
	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	config.attack.detection_range = 2.0
	var enemy := _spawn(config)
	_check(enemy._attack.can_start(1.0), "attack starts inside detection range")
	_check(not enemy._attack.can_start(2.5), "attack does not start out of range")
	enemy.queue_free()


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
