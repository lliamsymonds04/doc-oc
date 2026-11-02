class_name EnemyAttack
extends RefCounted

## One attack pattern for an enemy, driven by the controller's physics step.
## Subclasses own their own phases and timing; the controller only asks whether
## the enemy may start, and whether it is still rooted in place.

var enemy: EnemyController


func _init(e: EnemyController) -> void:
	enemy = e


## True when the enemy is free to start this attack and `dist` is in reach.
func can_start(_dist: float) -> bool:
	return false


## Only called once `can_start()` returned true.
func start() -> void:
	pass


func physics_update(_dt: float) -> void:
	pass


## Drops an in-progress attack, so `can_start()` may return true again.
func cancel() -> void:
	pass


## True while the enemy must plant its feet: telegraphing or releasing.
func is_committed() -> bool:
	return false


## Horizontal chase allowed while committed; ZERO keeps the feet planted.
func committed_velocity() -> Vector3:
	return Vector3.ZERO


## Yaw rate (rad/s) while committed; ZERO holds the facing.
func committed_turn_speed() -> float:
	return 0.0


## What to face while committed; `to_target` is the offset to the player.
func committed_facing(to_target: Vector3) -> Vector3:
	return to_target
