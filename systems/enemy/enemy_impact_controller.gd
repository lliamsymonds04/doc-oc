class_name EnemyImpactController
extends RefCounted

## Deals damage to the enemy when its ragdoll body takes a hard impact.
## Wraps an ImpactSensor on the ragdoll body and applies damage on impacts.

var _sensor: ImpactSensor


func _init(enemy: EnemyController, body: RigidBody3D, min_dv: float, damage_per_dv: float) -> void:
	_sensor = ImpactSensor.attach(body, min_dv)
	_sensor.impacted.connect(
		func(dv: float, _position: Vector3, _normal: Vector3, _collider: Object) -> void:
			if not enemy.is_dead():
				enemy.take_damage(dv * damage_per_dv)
	)
