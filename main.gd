extends Node3D

var _impact_registry: ImpactSensorRegistry

@onready var _pillars: PillarHandler = $PillarHandler
@onready var _boxes: BoxHandler = $BoxHandler
@onready var _gem: FloatingGem = $gem2
@onready var _enemies: EnemySpawner = $EnemySpawner


func _ready() -> void:
	var tree = get_tree()

	_impact_registry = ImpactSensorRegistry.new(tree)
	_impact_registry.scan()

	for body in tree.get_nodes_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(body)

	tree.node_added.connect(on_node_added)
	_gem.hit_landed.connect(on_gem_hit)

	_build_level()


func _exit_tree() -> void:
	if _impact_registry != null:
		_impact_registry.detach()


func on_node_added(node: Node) -> void:
	if node.is_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(node)


func on_gem_hit(_position: Vector3, _normal: Vector3) -> void:
	_pillars.rise_pillars()
	_enemies.begin()


func _build_level() -> void:
	_pillars.spawn()

	# new colliders only reach the physics space after a step, and the floor is a CSG
	# shape built deferred: the box placement raycasts against both
	await get_tree().physics_frame
	await get_tree().physics_frame

	_boxes.spawn()
