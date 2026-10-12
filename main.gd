extends Node3D

## Scene root of the playable level. Owns level-scoped services.

var _impact_registry: ImpactSensorRegistry


func _ready() -> void:
	_impact_registry = ImpactSensorRegistry.new(get_tree())
	_impact_registry.scan()
