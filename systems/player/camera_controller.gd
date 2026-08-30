extends SpringArm3D
class_name CameraController

@export var sensitivity: float = 0.02

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * sensitivity
		rotation_degrees.x -= event.relative.y * sensitivity
		rotation_degrees.x = clampf(rotation_degrees.x, -70, 70)

func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, global_rotation.y)

func get_input_direction(input_dir: Vector2) -> Vector3:
	var b := get_flat_basis()
	var direction := b.x * input_dir.x + b.z * input_dir.y
	if direction.length_squared() > 0.0:
		return direction.normalized()
	return direction
