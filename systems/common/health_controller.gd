extends Node
class_name HealthController

signal damage_taken(dmg: float)
signal died()

@export var max_health: float = 100.0

var health: float

func _ready() -> void:
	health = max_health

func apply_damage(dmg: float) -> void:
	health = max(health - dmg, 0.0)
	damage_taken.emit(dmg)
	if is_dead():
		died.emit()

func is_dead() -> bool:
	return health <= 0.0

func get_health_float() -> float:
	return health/max_health
