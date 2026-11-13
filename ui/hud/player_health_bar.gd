class_name PlayerHealthBar
extends Control

## Player health readout: red front bar with a pale trail that drains behind it.

@export var health_tween_duration: float = 0.1
@export var trail_tween_duration: float = 0.45
## White overlay fade on a hit, the same tell the enemy bars use.
@export var flash_tween_duration: float = 0.05
## The number lags the bar on purpose, so the count is readable on a fast hit.
@export var health_text_tween_duration: float = 0.4
## Fill colour sampled by health fraction: 0 = empty, 1 = full.
@export var health_gradient: Gradient

@export_category("Shake")
@export var shake_iters: int = 3
@export var shake_mag: float = 6.0
@export var shake_strength_decay: float = 0.7
@export var shake_tween_duration: float = 0.04

@export_category("Hit pop")
## Scale the bar snaps to on a hit: narrower and taller, then eases back to normal.
@export var pop_scale: Vector2 = Vector2(0.9, 1.3)
@export var pop_duration: float = 0.06
@export var pop_recover_duration: float = 0.15

var _health_tween: Tween
var _text_tween: Tween
var _trail_tween: Tween
var _flash_tween: Tween
var _shake_tween: Tween
var _pop_tween: Tween
var _rest_position: Vector2
var _fill_style: StyleBoxFlat
## -1 until the first set_health, which snaps instead of counting up from 0.
var _shown_health: float = -1.0
var _max_health: float = 100.0

@onready var bar_control: Control = $Bar
@onready var trail_bar: ProgressBar = $Bar/TrailBar
@onready var health_bar: ProgressBar = $Bar/TrailBar/HealthBar
@onready var flash_panel: Panel = $Bar/TrailBar/Flash
@onready var health_label: Label = $HealthLabel


func _ready() -> void:
	# anchored position and size aren't resolved until the first frame
	await get_tree().process_frame
	_rest_position = bar_control.position
	bar_control.pivot_offset = bar_control.size / 2.0
	# duplicate: the scene's stylebox is shared by every instance, and the gradient
	# tween writes to it
	_fill_style = (health_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	if health_gradient != null:
		_fill_style.bg_color = health_gradient.sample(1.0)


func set_health(ratio: float, max_health: float) -> void:
	_max_health = max_health
	_animate_health_text(ratio * max_health)

	ratio = clampf(ratio, 0.0, 1.0)

	if ratio < health_bar.value:
		_shake()
		_pop()
		flash()

	if _health_tween != null:
		_health_tween.kill()
	_health_tween = create_tween()
	_health_tween.tween_property(health_bar, "value", ratio, health_tween_duration)
	if health_gradient != null and _fill_style != null:
		_health_tween.parallel().tween_property(
			_fill_style, "bg_color", health_gradient.sample(ratio), health_tween_duration
		)

	if _trail_tween != null:
		_trail_tween.kill()
	if ratio >= trail_bar.value:
		# nothing to drain: snap so the pale trail never leads the red bar
		trail_bar.value = ratio
		return
	_trail_tween = create_tween()
	_trail_tween.tween_property(trail_bar, "value", ratio, trail_tween_duration)


func _animate_health_text(target: float) -> void:
	if _text_tween != null:
		_text_tween.kill()
	if _shown_health < 0.0:
		_set_shown_health(target)
		return
	_text_tween = create_tween()
	_text_tween.tween_method(_set_shown_health, _shown_health, target, health_text_tween_duration)


func _set_shown_health(value: float) -> void:
	_shown_health = value
	health_label.text = "%d/%d" % [roundi(value), roundi(_max_health)]


func flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	flash_panel.modulate = Color.WHITE
	flash_panel.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_panel, "modulate:a", 0.0, flash_tween_duration)


func _shake() -> void:
	# _rest_position is only valid once the first frame has settled the layout
	if _fill_style == null:
		return

	if _shake_tween != null:
		_shake_tween.kill()

	_shake_tween = create_tween()
	var mag := shake_mag
	for _i in range(shake_iters):
		_shake_tween.tween_property(
			bar_control, "position", _rest_position + Vector2(-mag, 0), shake_tween_duration
		)
		_shake_tween.tween_property(
			bar_control, "position", _rest_position + Vector2(mag, 0), shake_tween_duration
		)
		mag *= shake_strength_decay
	_shake_tween.tween_property(bar_control, "position", _rest_position, shake_tween_duration)


func _pop() -> void:
	if _pop_tween != null:
		_pop_tween.kill()

	_pop_tween = create_tween()
	(
		_pop_tween
		. tween_property(bar_control, "scale", pop_scale, pop_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_pop_tween
		. tween_property(bar_control, "scale", Vector2.ONE, pop_recover_duration)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
