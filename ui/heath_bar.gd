extends Sprite3D
class_name HealthBar

@onready var sub_viewport: SubViewport = $SubViewport
@onready var health_control: Control = $SubViewport/HealthControl
@onready var progress_bar: ProgressBar = $SubViewport/HealthControl/ProgressBar

func _ready() -> void:
	# Control layout isn't resolved until after the first frame
	await get_tree().process_frame
	_size_viewport_to_bar()
	progress_bar.value = progress_bar.max_value
	visible = false


func _size_viewport_to_bar() -> void:
	# Expand margins draw outside the control rect, so they'd be clipped without padding
	var background: StyleBox = progress_bar.get_theme_stylebox("background")
	var expand := Vector2(
		background.get_expand_margin(SIDE_LEFT) + background.get_expand_margin(SIDE_RIGHT),
		background.get_expand_margin(SIDE_TOP) + background.get_expand_margin(SIDE_BOTTOM)
	)

	sub_viewport.size = Vector2i(progress_bar.size + expand)


func set_health_float(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	# full health hides the bar entirely
	visible = value < 1.0
	progress_bar.value = progress_bar.max_value * value
