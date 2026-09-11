extends Control
class_name PauseMenu

var is_paused: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		is_paused = not is_paused
		get_tree().paused = is_paused
		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		get_viewport().set_input_as_handled()
