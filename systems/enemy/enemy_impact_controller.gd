class_name EnemyImpactController
extends Node

## Deals damage to the enemy when its ragdoll body takes a hard impact.
## Lives as a child of the ragdoll body and polls contact impulses

const DAMAGE_COOLDOWN: float = 0.2  # seconds between damage applications

var _enemy: EnemyController
var _body: RigidBody3D
var _min_dv: float
var _damage_per_dv: float
var _last_damage_physics_frame: int = -100

func _init(enemy: EnemyController, body: RigidBody3D, min_dv: float, damage_per_dv: float) -> void:
	_enemy = enemy
	_body = body
	_min_dv = min_dv
	_damage_per_dv = damage_per_dv

	body.contact_monitor = true
	body.max_contacts_reported = 8

	body.add_child(self)


func _physics_process(_dt: float) -> void:
	if _body.freeze or _enemy.is_dead():
		return

	var frame := Engine.get_physics_frames()
	if frame - _last_damage_physics_frame \
			< DAMAGE_COOLDOWN * Engine.get_physics_ticks_per_second():
		return

	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	for i in state.get_contact_count():
		# impulse / mass = equivalent velocity change -> mass-independent tuning
		var dv := state.get_contact_impulse(i).length() / _body.mass
		if dv < _min_dv:
			continue

		_last_damage_physics_frame = frame
		_enemy.take_damage(dv * _damage_per_dv)
		break  # one damage application per step is plenty
