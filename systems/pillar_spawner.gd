class_name PillarHandler
extends Node3D

@export var extent := 128.0
@export var cell_size := 9.0
@export var cluster_frequency := 0.12
@export var sparsity := 0.7
@export var min_height := 15.0
@export var max_height := 60.0
@export var pillar_template: PackedScene = preload("res://assets/pillar_template.tscn")
@export var center_radius := 2.0
@export var pillar_gradient_colour: Gradient


func _ready() -> void:
	var mask := FastNoiseLite.new()
	mask.seed = randi()
	mask.frequency = cluster_frequency
	mask.fractal_octaves = 3

	var steps := maxi(int(extent / cell_size), 1)
	var img := mask.get_seamless_image(steps, steps)
	var half := steps / 2.0

	for ix in steps:
		for iz in steps:
			var dx := ix + 0.5 - half
			var dz := iz + 0.5 - half
			if dx * dx + dz * dz < center_radius * center_radius:
				continue

			var nv := img.get_pixel(ix, iz).r
			if nv < sparsity:
				continue
			# 0 at the group edge, 1 at its core
			var t := (nv - sparsity) / maxf(1.0 - sparsity, 0.001)
			var pillar := pillar_template.instantiate()
			var height := lerpf(min_height, max_height, t)
			pillar.position = Vector3(dx * cell_size, 0, dz * cell_size)
			pillar.scale = Vector3(cell_size, height, cell_size)

			if pillar_gradient_colour:
				var mesh: MeshInstance3D = pillar.get_child(0)
				if mesh:
					var mat := mesh.material_override as StandardMaterial3D
					mat.albedo_color = pillar_gradient_colour.sample(t)

			add_child(pillar)
