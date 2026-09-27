extends Sprite3D
class_name HealthBar

@onready var sub_viewport: SubViewport = $SubViewport
@onready var health_control: Control = $SubViewport/HealthControl
@onready var trail_bar: ProgressBar = $SubViewport/HealthControl/TrailBar
@onready var health_bar: ProgressBar = $SubViewport/HealthControl/TrailBar/HealthBar

@export var health_tween_duration: float = 0.1
@export var trail_tween_duration: float = 0.5

var _health_tween: Tween
var _trail_tween: Tween

func _ready() -> void:
	# Control layout isn't resolved until after the first frame
	await get_tree().process_frame
	_size_viewport_to_bar()
	health_bar.value = health_bar.max_value
	trail_bar.value = 0.0
	visible = false


func _size_viewport_to_bar() -> void:
	# Expand margins draw outside the control rect, so they'd be clipped without padding
	var background: StyleBox = trail_bar.get_theme_stylebox("background")
	var expand := Vector2(
		background.get_expand_margin(SIDE_LEFT) + background.get_expand_margin(SIDE_RIGHT),
		background.get_expand_margin(SIDE_TOP) + background.get_expand_margin(SIDE_BOTTOM)
	)

	sub_viewport.size = Vector2i(trail_bar.size + expand)


func set_health_float(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	# full health hides the bar entirely
	visible = value < 1.0

	if _health_tween != null:
		_health_tween.stop()
	_health_tween = get_tree().create_tween()
	var target = health_bar.max_value * value
	_health_tween.tween_property(health_bar, "value", target, health_tween_duration)

	if _trail_tween != null:
		_trail_tween.stop()
	_trail_tween = get_tree().create_tween()
	_trail_tween.tween_property(trail_bar, "value", target, trail_tween_duration)
