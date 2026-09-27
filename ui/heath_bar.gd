extends Sprite3D
class_name HealthBar

@onready var sub_viewport: SubViewport = $SubViewport
@onready var health_control: Control = $SubViewport/HealthControl
@onready var trail_bar: ProgressBar = $SubViewport/HealthControl/TrailBar
@onready var health_bar: ProgressBar = $SubViewport/HealthControl/TrailBar/HealthBar
@onready var flash_panel: Panel = $SubViewport/HealthControl/TrailBar/Flash

@export var health_tween_duration: float = 0.1
@export var trail_tween_duration: float = 0.5
@export var shake_tween_duration: float = 0.04
@export var flash_tween_duration: float = 0.05
@export var trail_heal_color: Color = Color(0.55, 0.95, 0.75, 1.0)

# heal tuning
@export var heal_front_tween_duration: float = 0.3
@export var heal_catchup_tween_duration: float = 0.7
@export var trail_color_fade_duration: float = 0.15
@export var heal_pop_amount: float = 0.03   # fraction of max_value
@export var heal_pop_duration: float = 0.15
@export var heal_pulse_mag: float = 1.5
@export var heal_pulse_duration: float = 0.07

var _health_tween: Tween
var _trail_tween: Tween
var _shake_tween: Tween
var _flash_tween: Tween
var _trail_color_tween: Tween
var _pop_tween: Tween
var _control_origin: Vector2
var _trail_color: Color

func _ready() -> void:
	# Control layout isn't resolved until after the first frame
	await get_tree().process_frame
	_size_viewport_to_bar()
	health_bar.value = health_bar.max_value
	trail_bar.value = 0.0
	visible = false
	_control_origin = health_control.position
	_trail_color = trail_bar.get_theme_stylebox("fill").bg_color


func _size_viewport_to_bar() -> void:
	# Expand margins draw outside the control rect, so they'd be clipped without padding
	var background: StyleBox = trail_bar.get_theme_stylebox("background")
	var expand := Vector2(
		background.get_expand_margin(SIDE_LEFT) + background.get_expand_margin(SIDE_RIGHT),
		background.get_expand_margin(SIDE_TOP) + background.get_expand_margin(SIDE_BOTTOM)
	)

	sub_viewport.size = Vector2i(trail_bar.size + expand)


func _set_trail_fill_color(to: Color, duration: float) -> void:
	# instant switch when duration is zero
	if duration <= 0.0:
		if _trail_color_tween:
			_trail_color_tween.kill()
		trail_bar.get_theme_stylebox("fill").bg_color = to
		return
	if _trail_color_tween:
		_trail_color_tween.kill()
	_trail_color_tween = create_tween()
	_trail_color_tween.tween_property(trail_bar.get_theme_stylebox("fill"), "bg_color", to, duration)


func damage_health_bar_tween(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	# full health hides the bar entirely
	visible = value < 1.0
	# hit response needs the damage color back immediately
	_set_trail_fill_color(_trail_color, 0.0)

	if _health_tween != null:
		_health_tween.kill()
	_health_tween = get_tree().create_tween()
	var target = health_bar.max_value * value
	_health_tween.tween_property(health_bar, "value", target, health_tween_duration)

	if _trail_tween != null:
		_trail_tween.kill()
	_trail_tween = get_tree().create_tween()
	_trail_tween.tween_property(trail_bar, "value", target, trail_tween_duration)

	_trail_tween.finished.connect(func() -> void:
		visible = value > 0.0
	)

	shake_health_bar()
	flash()


func heal_health_bar_tween(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	visible = value > 0.0
	_set_trail_fill_color(trail_heal_color, trail_color_fade_duration)
	flash(trail_heal_color)
	_heal_pulse()

	var target = health_bar.max_value * value

	# for the heal tween, the health bar and trail are swapped
	if _health_tween != null:
		_health_tween.kill()
	_health_tween = get_tree().create_tween()
	_health_tween.tween_property(trail_bar, "value", target, heal_front_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if _trail_tween != null:
		_trail_tween.kill()
	_trail_tween = get_tree().create_tween()
	_trail_tween.tween_property(health_bar, "value", target, heal_catchup_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_trail_tween.finished.connect(func() -> void:
		visible = value < 1.0
		_set_trail_fill_color(_trail_color, trail_color_fade_duration)
	)


func _heal_pulse() -> void:
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()

	_shake_tween = get_tree().create_tween()
	_shake_tween.tween_property(health_control, "position",
			_control_origin + Vector2(0, heal_pulse_mag), heal_pulse_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(health_control, "position",
			_control_origin, heal_pulse_duration)


func shake_health_bar(shake_iters: int = 3, shake_mag: float = 6, strengh_decay: float = 0.7) -> void:
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()

	_shake_tween = get_tree().create_tween()
	for i in range(shake_iters):
		_shake_tween.tween_property(health_control, "position", _control_origin + Vector2(-shake_mag, 0), shake_tween_duration)
		_shake_tween.tween_property(health_control, "position", _control_origin + Vector2(shake_mag, 0), shake_tween_duration)
		shake_mag *= strengh_decay

	_shake_tween.tween_property(health_control, "position", _control_origin, shake_tween_duration)


func flash(tint: Color = Color(1.0, 1.0, 1.0, 1.0)) -> void:
	if _flash_tween:
		_flash_tween.kill()
	flash_panel.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	flash_panel.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_panel, "modulate:a", 0.0, flash_tween_duration)
