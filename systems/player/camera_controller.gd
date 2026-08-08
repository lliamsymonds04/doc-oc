extends SpringArm3D

@export var sensitivity: float = 0.02

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * sensitivity
		rotation_degrees.x -= event.relative.y * sensitivity
		rotation_degrees.x = clampf(rotation_degrees.x, -70, 70)
