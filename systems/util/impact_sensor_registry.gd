class_name ImpactSensorRegistry
extends RefCounted

## Attaches an ImpactSensor to every RigidBody3D in ImpactSensor.GROUP_IMPACT.

const DEFAULT_MIN_DV: float = 2.0

var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree
	_tree.node_added.connect(_on_node_added)


## Sweeps bodies already in the tree. Safe to call more than once.
func scan() -> void:
	for body in _tree.get_nodes_in_group(ImpactSensor.GROUP_IMPACT):
		if body is RigidBody3D:
			ImpactSensor.attach(body, DEFAULT_MIN_DV)


func _on_node_added(node: Node) -> void:
	if not node is RigidBody3D:
		return
	# deferred: groups and metadata set in _ready are not visible yet
	_try_attach.call_deferred(node)


func _try_attach(node: Node) -> void:
	var body := node as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree():
		return

	if not body.is_in_group(ImpactSensor.GROUP_IMPACT):
		return

	ImpactSensor.attach(body, DEFAULT_MIN_DV)
