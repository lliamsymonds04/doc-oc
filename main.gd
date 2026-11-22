extends Node3D

var _navigation := NavigationRegion3D.new()
var _navigation_layout: Dictionary
var _navigation_baking := false
var _impact_registry: ImpactSensorRegistry

@onready var _pillars: PillarHandler = $PillarHandler
@onready var _boxes: BoxHandler = $BoxHandler
@onready var _gem: FloatingGem = $gem2
@onready var _healing: HealingGemSpawner = $HealingGem
@onready var _hud: Hud = $Hud
@onready var _enemies: EnemySpawner = $EnemySpawner


func _ready() -> void:
	var tree = get_tree()

	EnemyController.kill_count = 0

	_impact_registry = ImpactSensorRegistry.new(tree)
	_impact_registry.scan()

	for body in tree.get_nodes_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(body)

	tree.node_added.connect(on_node_added)
	_gem.hit_landed.connect(on_gem_hit)
	_healing.heal_player.connect(on_heal_player)

	_build_level()


func _on_player_died() -> void:
	create_tween().tween_property($AmbientMusic, "volume_linear", 0.0, 0.6)


func _exit_tree() -> void:
	if _impact_registry != null:
		_impact_registry.detach()


func on_node_added(node: Node) -> void:
	if node.is_in_group(VelocityTrail.GROUP_TRAIL):
		VelocityTrail.attach(node)


func on_gem_hit(_position: Vector3, _normal: Vector3) -> void:
	_pillars.rise_pillars()
	_update_navigation()
	_enemies.begin()
	_hud.start_timer()
	_healing.begin()


func on_heal_player(amount: float) -> void:
	var player := (
		get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
	)
	if player:
		player.heal(amount)


func _build_level() -> void:
	_pillars.spawn()

	# new colliders only reach the physics space after a step, and the floor is a CSG
	# shape built deferred: the box placement raycasts against both
	await get_tree().physics_frame
	await get_tree().physics_frame

	_boxes.spawn()
	add_child(_navigation)
	_update_navigation()

	var refresh := Timer.new()
	refresh.wait_time = 1.0
	refresh.timeout.connect(_update_navigation)
	add_child(refresh)
	refresh.start()


func _update_navigation() -> void:
	if not _navigation.is_inside_tree() or _navigation_baking:
		return

	var floor_node: CSGBox3D = $Floor
	var floor_y := floor_node.global_position.y + floor_node.size.y * 0.5
	var layout := {}
	var obstacles: Array[CollisionShape3D] = []
	for child in _boxes.get_children():
		var box := child as RigidBody3D
		if box == null or (box.collision_layer & 1) == 0:
			continue
		var collider: CollisionShape3D = box.get_node("CollisionShape3D")
		if collider.global_position.y > floor_y + 2.0:
			continue
		layout[box.get_instance_id()] = [
			collider.global_position.snapped(Vector3.ONE * 0.5),
			collider.global_rotation.snapped(Vector3.ONE * 0.25),
		]
		obstacles.append(collider)

	layout[&"pillars_risen"] = _pillars.pillars_risen
	if layout == _navigation_layout:
		return
	_navigation_layout = layout

	var source := NavigationMeshSourceGeometryData3D.new()
	var half := floor_node.size * 0.5
	var a := Vector3(-half.x, half.y, -half.z)
	var b := Vector3(half.x, half.y, -half.z)
	var c := Vector3(half.x, half.y, half.z)
	var d := Vector3(-half.x, half.y, half.z)
	source.add_faces(PackedVector3Array([a, b, c, a, c, d]), floor_node.global_transform)
	for collider in obstacles:
		_add_navigation_obstacle(source, collider, floor_y)
	if _pillars.pillars_risen:
		for pillar in _pillars.pillars:
			_add_navigation_obstacle(source, pillar.get_node("CollisionShape3D"), floor_y)

	var navigation_mesh := NavigationMesh.new()
	# The orb is the widest enemy. Leave extra space for steering at corners.
	navigation_mesh.agent_radius = 1.25
	_navigation_baking = true
	NavigationServer3D.bake_from_source_geometry_data_async(
		navigation_mesh, source, _finish_navigation_bake.bind(navigation_mesh)
	)


func _add_navigation_obstacle(
	source: NavigationMeshSourceGeometryData3D, collider: CollisionShape3D, floor_y: float
) -> void:
	var bounds := (collider.shape as BoxShape3D).size * 0.5
	var center := collider.global_position
	# Project the box's world-space bounds onto the floor. Pillars rise straight up.
	var span := (
		collider.global_basis.x.abs() * bounds.x
		+ collider.global_basis.y.abs() * bounds.y
		+ collider.global_basis.z.abs() * bounds.z
	)
	var outline := PackedVector3Array(
		[
			center + Vector3(-span.x, 0, -span.z),
			center + Vector3(span.x, 0, -span.z),
			center + Vector3(span.x, 0, span.z),
			center + Vector3(-span.x, 0, span.z),
		]
	)
	source.add_projected_obstruction(outline, floor_y - 0.5, 2.0, false)


func _finish_navigation_bake(navigation_mesh: NavigationMesh) -> void:
	_navigation.navigation_mesh = navigation_mesh
	_navigation_baking = false
