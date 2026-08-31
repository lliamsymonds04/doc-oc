extends SpringArm3D
class_name CameraController

@export var sensitivity: float = 0.02
@export var max_trauma_offset: float = 0.05
@export var max_trauma_roll: float = 1.4

@onready var cam: Camera3D = $CameraShakePivot/Camera3D

var trauma: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func add_trauma(amount: float) -> void:
	trauma = min(trauma + amount, 1.0)

func _process(dt: float) -> void:
	if trauma > 0:
		trauma = max(trauma-dt*2.5, 0.0)
		var shake = trauma * trauma
		cam.position = Vector3(
			randf_range(-1,1) * max_trauma_offset * shake,
			randf_range(-1,1) * max_trauma_offset * shake,
			0
		)
		cam.rotation_degrees.z = randf_range(-1,1) * max_trauma_roll * shake
	else:
		cam.position = Vector3.ZERO
		cam.rotation_degrees.z = 0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * sensitivity
		rotation_degrees.x -= event.relative.y * sensitivity
		rotation_degrees.x = clampf(rotation_degrees.x, -70, 70)
		rotation.y = wrapf(rotation.y, -PI, PI)

func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, global_rotation.y)

func get_input_direction(input_dir: Vector2) -> Vector3:
	var b := get_flat_basis()
	var direction := b.x * input_dir.x + b.z * input_dir.y
	if direction.length_squared() > 0.0:
		return direction.normalized()
	return direction
