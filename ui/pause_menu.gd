extends Control
class_name PauseMenu

@export_range(0.0, 10.0) var blur_strength = 3.0
@export_range(0.0, 1.0) var color_mix = 0.15
@export_range(0.0, 2.0) var blur_tween_duration = 0.4

@onready var blur_rect = $BlurRect

var is_paused: bool = false
var blur_tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		is_paused = not is_paused
		get_tree().paused = is_paused

		var blur_target = blur_strength if is_paused else 0.0
		var color_mix_target = color_mix if is_paused else 0.0

		if blur_tween:
			blur_tween.kill()

		blur_tween = create_tween().set_parallel(true)
		blur_tween.tween_property(blur_rect, "material:shader_parameter/blur_amount", blur_target, blur_tween_duration)
		blur_tween.tween_property(blur_rect, "material:shader_parameter/mix_amount", color_mix_target, blur_tween_duration)

		if is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			visible = true
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			blur_tween.finished.connect(func(): visible = false)

		get_viewport().set_input_as_handled()
