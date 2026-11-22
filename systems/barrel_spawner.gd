extends BoxHandler


func _init() -> void:
	box_template = preload("res://assets/barrel_template.tscn")
	palette = PackedColorArray()


func _size_prop(barrel: RigidBody3D, size: float) -> void:
	assert(barrel is ExplosiveBarrel, "Barrel spawner needs an ExplosiveBarrel scene")
	var mesh: MeshInstance3D = barrel.get_node("MeshInstance3D")
	mesh.scale = Vector3.ONE * size

	var col: CollisionShape3D = barrel.get_node("CollisionShape3D")
	var cylinder := col.shape as CylinderShape3D
	cylinder.radius = size * 0.5
	cylinder.height = size
