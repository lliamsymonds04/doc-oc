extends Node3D

## Scene root of the playable level. Owns level-scoped services.

var _impact_registry: ImpactSensorRegistry


func _ready() -> void:
	var tree = get_tree()

	_impact_registry = ImpactSensorRegistry.new(tree)
	_impact_registry.scan()

	for body in tree.get_nodes_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(body)

	tree.node_added.connect(on_node_added)


func _exit_tree() -> void:
	if _impact_registry != null:
		_impact_registry.detach()


func on_node_added(node: Node) -> void:
	if node.is_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(node)
