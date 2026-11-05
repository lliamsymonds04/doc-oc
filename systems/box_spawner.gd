class_name BoxHandler
extends Node3D

## Scatters grabbable crates over the floor at level start, skipping any spot a
## pillar, enemy or other crate already occupies.

const GROUND_CLEARANCE := 0.15  # metres above the floor; the crate drops this far
const PROBE_MARGIN := 0.2  # keeps crates from spawning flush against anything
const FLOOR_SNAP := 0.5  # a ray hit above this is a pillar or an enemy, not the floor

@export var extent := 128.0
@export var cell_size := 6.0
@export var target_boxes := 25
@export var jitter := 0.3  # fraction of cell_size a crate may wander from its cell
@export var min_size := 1.0
@export var max_size := 1.75
@export var mass_per_volume := 1.0
@export var center_radius := 2.0  # clear cells around this node, same units as PillarHandler
@export var spawn_seed := 0  # 0 randomises every run
@export var box_template: PackedScene = preload("res://assets/box_template.tscn")
@export var palette := PackedColorArray(
	[
		Color(0.72, 0.63, 0.5),
		Color(0.55, 0.46, 0.36),
		Color(0.62, 0.6, 0.57),
		Color(0.45, 0.42, 0.38),
	]
)

var _probe := BoxShape3D.new()


func spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed if spawn_seed != 0 else randi()

	var cells := _build_cells(rng)
	var spawned := 0
	for cell in cells:
		if spawned >= target_boxes:
			break
		var size := rng.randf_range(min_size, max_size)
		var spot: Variant = _try_place(cell, size)
		if spot == null:
			continue
		_spawn(spot, size, rng)
		spawned += 1

	if spawned == 0:
		push_warning("BoxHandler spawned nothing; check the floor's collision and center_radius")


## Candidate positions in this node's space, shuffled so a small target count
## still spreads over the whole field.
func _build_cells(rng: RandomNumberGenerator) -> Array[Vector2]:
	var steps := maxi(int(extent / cell_size), 1)
	var half := steps / 2.0
	var reach := jitter * cell_size

	var cells: Array[Vector2] = []
	for ix in steps:
		for iz in steps:
			var dx := ix + 0.5 - half
			var dz := iz + 0.5 - half
			if dx * dx + dz * dz < center_radius * center_radius:
				continue
			var x := dx * cell_size + rng.randf_range(-reach, reach)
			var z := dz * cell_size + rng.randf_range(-reach, reach)
			cells.append(Vector2(x, z))

	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp

	return cells


## World-space crate centre for a cell, or null when the spot is taken.
func _try_place(cell: Vector2, size: float) -> Variant:
	var from := to_global(Vector3(cell.x, 100.0, cell.y))
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 150.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["position"].y > FLOOR_SNAP:
		return null

	var ground: float = hit["position"].y
	var center := to_global(Vector3(cell.x, ground + size * 0.5 + GROUND_CLEARANCE, cell.y))
	if not _is_clear(center, size):
		return null
	return center


func _is_clear(center: Vector3, size: float) -> bool:
	_probe.size = Vector3.ONE * (size + PROBE_MARGIN)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.collision_mask = 1
	# the probe sits high enough that the floor itself never registers as a hit
	params.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * PROBE_MARGIN * 0.5)
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _spawn(spot: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var box := box_template.instantiate() as RigidBody3D
	box.position = spot
	box.mass = size * size * size * mass_per_volume

	var mesh: MeshInstance3D = box.get_node("MeshInstance3D")
	(mesh.mesh as BoxMesh).size = Vector3.ONE * size
	var mat := mesh.material_override as StandardMaterial3D
	if palette.size() > 0:
		mat.albedo_color = palette[rng.randi_range(0, palette.size() - 1)]

	var col: CollisionShape3D = box.get_node("CollisionShape3D")
	(col.shape as BoxShape3D).size = Vector3.ONE * size

	add_child(box)
