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

@export_category("Trail")
@export var trail_strength: float = 0.06    # forward/back (local Z)
@export var trail_strength_side: float = 0.1   # strafing (local X)
@export var trail_strength_vert: float = 0.02   # jumping/falling (local Y)
@export var trail_rate: float = 5.0
@export var max_trail: float = 0.8
@export var max_trail_side: float = 1.0
@export var max_trail_vert: float = 0.3
@onready var cam: Camera3D = $CameraShakePivot/Camera3D

var _trauma: float = 0.0
var _current_speed: float = 0.0
var _trail := Vector3.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam.fov = base_fov

func add_trauma(amount: float) -> void:
	_trauma = min(_trauma + amount, 1.0)

func set_current_speed(value: float) -> void:
	_current_speed = max(value, 0.0)

func update_motion(dt: float, velocity: Vector3) -> void:
	var local_vel: Vector3 = global_transform.basis.inverse() * velocity

	var target := Vector3(
		clampf(-local_vel.x * trail_strength_side, -max_trail_side, max_trail_side),
		clampf(-local_vel.y * trail_strength_vert, -max_trail_vert, max_trail_vert),
		clampf(-local_vel.z * trail_strength, -max_trail, max_trail)
	)
	_trail = _trail.lerp(target, 1.0 - exp(-trail_rate * dt))
	$CameraShakePivot.position = _trail

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
