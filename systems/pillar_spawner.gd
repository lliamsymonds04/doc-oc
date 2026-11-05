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

@export_group("rise_animation")
@export var rise_duration := 3.0
@export var rise_downset := -10
@export var rise_trauma := 2.8
@export var rise_shake_decay := 2.5  # mirrors CameraController's trauma decay

var pillars: Array[Node3D] = []
var pillars_risen = false
# >0 while the rise shake is fed to the camera
var _shake_time := 0.0


func spawn() -> void:
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
		var height := lerpf(min_height, max_height, t)
		var box := Vector3(cell_size, height, cell_size)
		var pillar := pillar_template.instantiate()
		pillar.position = Vector3(spot.x * cell_size, rise_downset - max_height, spot.y * cell_size)

		var mesh: MeshInstance3D = pillar.get_node("MeshInstance3D")
		(mesh.mesh as BoxMesh).size = box
		mesh.position.y = height * 0.5

		var col: CollisionShape3D = pillar.get_node("CollisionShape3D")
		(col.shape as BoxShape3D).size = box
		col.position.y = height * 0.5

		if pillar_gradient_colour:
			var mat := mesh.material_override as StandardMaterial3D
			mat.albedo_color = pillar_gradient_colour.sample(t)

		pillars.append(pillar)

		add_child(pillar)


func rise_pillars():
	_shake_time = rise_duration
	for pillar in pillars:
		var tween = get_tree().create_tween()
		tween.tween_property(
			pillar, "position", Vector3(pillar.position.x, 0, pillar.position.z), rise_duration
		)


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		var cam := (
			get_tree().get_first_node_in_group(CameraController.CAMERA_GROUP) as CameraController
		)
		if cam:
			# feeding at the decay rate holds the trauma level instead of fading
			cam.add_trauma(rise_trauma * rise_shake_decay * delta)

	if pillars_risen:
		return
	if Input.is_action_just_pressed("left-click"):
		pillars_risen = true
		rise_pillars()
