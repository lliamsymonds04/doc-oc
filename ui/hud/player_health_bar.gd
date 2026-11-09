class_name PlayerHealthBar
extends Control

## Player health readout: red front bar with a pale trail that drains behind it.

@export var health_tween_duration: float = 0.1
@export var trail_tween_duration: float = 0.45
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
var _trail_tween: Tween
var _shake_tween: Tween
var _pop_tween: Tween
var _rest_position: Vector2
var _fill_style: StyleBoxFlat

@onready var trail_bar: ProgressBar = $TrailBar
@onready var health_bar: ProgressBar = $TrailBar/HealthBar


func _ready() -> void:
	# anchored position and size aren't resolved until the first frame
	await get_tree().process_frame
	_rest_position = position
	pivot_offset = size / 2.0
	# duplicate: the scene's stylebox is shared by every instance, and the gradient
	# tween writes to it
	_fill_style = (health_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	if health_gradient != null:
		_fill_style.bg_color = health_gradient.sample(1.0)


func set_health(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)

	if ratio < health_bar.value:
		_shake()
		_pop()

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
			self, "position", _rest_position + Vector2(-mag, 0), shake_tween_duration
		)
		_shake_tween.tween_property(
			self, "position", _rest_position + Vector2(mag, 0), shake_tween_duration
		)
		mag *= shake_strength_decay
	_shake_tween.tween_property(self, "position", _rest_position, shake_tween_duration)


func _pop() -> void:
	if _pop_tween != null:
		_pop_tween.kill()

	_pop_tween = create_tween()
	(
		_pop_tween
		. tween_property(self, "scale", pop_scale, pop_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_pop_tween
		. tween_property(self, "scale", Vector2.ONE, pop_recover_duration)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
