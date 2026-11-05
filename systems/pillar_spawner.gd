class_name PillarHandler
extends Node3D

@export var extent := 128.0
@export var cell_size := 9.0
@export var cluster_frequency := 0.12
@export var target_pillars := 34
@export var min_height := 15.0
@export var max_height := 60.0
@export var pillar_template: PackedScene = preload("res://assets/pillar_template.tscn")
@export var center_radius := 2.0
@export var pillar_gradient_colour: Gradient


func _ready() -> void:
	var steps := maxi(int(extent / cell_size), 1)
	var half := steps / 2.0

	var mask := FastNoiseLite.new()
	mask.seed = randi()
	mask.frequency = cluster_frequency
	mask.fractal_octaves = 3
	var img := mask.get_seamless_image(steps, steps)

	# x, z in cells, noise value in .z
	var spots: Array[Vector3] = []
	for ix in steps:
		for iz in steps:
			var dx := ix + 0.5 - half
			var dz := iz + 0.5 - half
			if dx * dx + dz * dz < center_radius * center_radius:
				continue
			spots.append(Vector3(dx, dz, img.get_pixel(ix, iz).r))

	# keep only the densest cells, so the count is the same every seed
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	if spots.is_empty():
		return
	var keep := mini(target_pillars, spots.size())
	var cutoff := spots[keep - 1].z
	var span := maxf(spots[0].z - cutoff, 0.001)

	for i in keep:
		var spot := spots[i]
		# 0 at the group edge, 1 at its core
		var t := (spot.z - cutoff) / span
		var pillar := pillar_template.instantiate()
		pillar.position = Vector3(spot.x * cell_size, 0, spot.y * cell_size)
		pillar.scale = Vector3(cell_size, lerpf(min_height, max_height, t), cell_size)

		if pillar_gradient_colour:
			var mesh: MeshInstance3D = pillar.get_child(0)
			if mesh:
				var mat := mesh.material_override as StandardMaterial3D
				mat.albedo_color = pillar_gradient_colour.sample(t)

		add_child(pillar)
