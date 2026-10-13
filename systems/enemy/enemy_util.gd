class_name EnemyUtil
extends RefCounted

## Damage per m/s of impact velocity change.
const DEFAULT_PROJECTILE_DAMAGE_PER_DV: float = 2.0
const RAGDOLL_DV_THRESHOLD: float = 10.0


static func attach_impact_damage(
	body: RigidBody3D, min_dv: float, damage_per_dv: float = DEFAULT_PROJECTILE_DAMAGE_PER_DV
) -> void:
	ImpactSensor.attach(body, min_dv).impacted.connect(
		func(dv: float, _position: Vector3, _normal: Vector3, collider: Object) -> void:
			var enemy := resolve_enemy(collider)
			if enemy == null or enemy.is_dead():
				return

			enemy.take_damage(dv * damage_per_dv)

			if not enemy.is_dead():
				if dv > RAGDOLL_DV_THRESHOLD:
					enemy.initiate_ragdoll()
	)


## Silent until the ragdoll body is unfrozen by `swap_to_ragdoll()`.
static func attach_self_damage(
	enemy: EnemyController, body: RigidBody3D, min_dv: float, damage_per_dv: float
) -> void:
	ImpactSensor.attach(body, min_dv).impacted.connect(
		func(dv: float, _position: Vector3, _normal: Vector3, _collider: Object) -> void:
			if not enemy.is_dead():
				enemy.take_damage(dv * damage_per_dv)
	)


static func resolve_enemy(collider: Object) -> EnemyController:
	var node := collider as Node
	while node != null:
		if node is EnemyController:
			return node
		if node.is_in_group(EnemyController.ENEMY_GROUP):
			return node as EnemyController
		if node.has_meta(EnemyRagdollController.ENEMY_META):
			return node.get_meta(EnemyRagdollController.ENEMY_META) as EnemyController

		node = node.get_parent()

	return null
