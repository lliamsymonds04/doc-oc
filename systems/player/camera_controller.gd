extends SpringArm3D
class_name CameraController

@export var sensitivity: float = 0.02
@export_category("Trauma")
@export var max_trauma_offset: float = 0.05
@export var max_trauma_roll: float = 1.4

@export_category("Fov")
@export var base_fov: float = 75.0
@export var max_fov: float = 90.0
@export var speed_at_max_fov: float = 10.0
@export var fov_change_rate: float = 2.0
@export_range(0.1,4.0,0.05) var fov_curve_exponent: float = 0.5

@onready var cam: Camera3D = $CameraShakePivot/Camera3D

var _trauma: float = 0.0
var _current_speed: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam.fov = base_fov

func add_trauma(amount: float) -> void:
	_trauma = min(_trauma + amount, 1.0)

func set_current_speed(value: float) -> void:
	_current_speed = max(value, 0.0)

func _process(dt: float) -> void:
	if _trauma > 0:
		_trauma = max(_trauma-dt*2.5, 0.0)
		var shake = _trauma * _trauma
		cam.position = Vector3(
			randf_range(-1,1) * max_trauma_offset * shake,
			randf_range(-1,1) * max_trauma_offset * shake,
			0
		)
		cam.rotation_degrees.z = randf_range(-1,1) * max_trauma_roll * shake
	else:
		cam.position = Vector3.ZERO
		cam.rotation_degrees.z = 0

	# handle fov
	var speed_float = min(_current_speed/speed_at_max_fov, 1.0)
	speed_float = pow(speed_float,fov_curve_exponent)
	var target_fov = lerpf(base_fov, max_fov, speed_float)
	var current_fov = cam.fov
	cam.fov = lerpf(current_fov, target_fov, dt*fov_change_rate)

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
