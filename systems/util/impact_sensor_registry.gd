class_name ImpactSensorRegistry
extends RefCounted

## Attaches impact behaviour to every RigidBody3D in a registered group, mapping
## each group to a factory called as `factory.call(body, DEFAULT_MIN_DV)`.

const DEFAULT_MIN_DV: float = 2.0
const BEHAVIOURS_META := &"impact_behaviours"

var _factories: Dictionary = {}
var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree
	_factories[ImpactSensor.GROUP_IMPACT] = _damage_enemy_on_impact
	_tree.node_added.connect(_on_node_added)


## Sweeps bodies already in the tree. Safe to call more than once.
func scan() -> void:
	for group in _factories:
		for body in _tree.get_nodes_in_group(group):
			if body is RigidBody3D:
				_attach(body, group)


func _damage_enemy_on_impact(body: RigidBody3D, min_dv: float) -> void:
	EnemyUtil.attach_impact_damage(body, min_dv)


func _on_node_added(node: Node) -> void:
	if not node is RigidBody3D:
		return
	# deferred: groups and metadata set in _ready are not visible yet
	_try_attach.call_deferred(node)


func _try_attach(node: Node) -> void:
	var body := node as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree():
		return

	for group in _factories:
		if body.is_in_group(group):
			_attach(body, group)


func _attach(body: RigidBody3D, group: StringName) -> void:
	var attached: Array = body.get_meta(BEHAVIOURS_META, [])
	if group in attached:
		return

	attached.append(group)
	body.set_meta(BEHAVIOURS_META, attached)
	_factories[group].call(body, DEFAULT_MIN_DV)
