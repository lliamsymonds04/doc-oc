class_name EnemyMovement
extends RefCounted

## One locomotion mode for an enemy, driven by the controller's physics step.
## Subclasses own their vertical rule, horizontal target, and landing response.

var enemy: EnemyController


func _init(e: EnemyController) -> void:
	enemy = e


## Vertical for this frame, before the attack step. Gravity by default.
func apply_vertical(dt: float) -> void:
	enemy.velocity += enemy.get_gravity() * dt


## Horizontal chase velocity; only called while the attack is not committed.
func desired_velocity(_dt: float, dist: float, forward: Vector3) -> Vector3:
	if dist > enemy.config.stop_distance:
		return forward * enemy.config.move_speed
	return Vector3.ZERO


## After `move_and_slide()`; landing responses live here.
func after_slide(_dt: float) -> void:
	pass
