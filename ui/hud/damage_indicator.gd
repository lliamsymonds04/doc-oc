class_name DamageIndicator
extends ColorRect

## Screen-edge damage feedback: a directional flash per hit, plus an all-around
## glow that grows as health drops.

@export var peak_intensity: float = 0.65
@export var hold_time: float = 0.08
@export var fade_time: float = 0.4
## Health fraction where the all-around glow starts; it is full at zero health.
@export var low_health_threshold: float = 0.6

var _intensity := 0.0
var _buildup := 0.0
var _tween: Tween

@onready var _material: ShaderMaterial = material as ShaderMaterial


## angle: screen-space radians, 0 = right, positive turns downward.
## weight: 0..1 severity, scales how strong the flash is.
func flash(angle: float, weight: float) -> void:
	var peak := peak_intensity * weight
	_material.set_shader_parameter("angle", angle)
	if _tween != null:
		_tween.kill()
	# peak now, not after the hold: tween_method only sets the value when it starts
	_set_intensity(peak)
	_tween = create_tween()
	_tween.tween_interval(hold_time)
	_tween.tween_method(_set_intensity, peak, 0.0, fade_time)


## ratio: health fraction (0..1). The edge glow fills in as it drops.
func set_health(ratio: float) -> void:
	_buildup = clampf((low_health_threshold - ratio) / low_health_threshold, 0.0, 1.0)
	_material.set_shader_parameter("buildup", _buildup)
	_update_visible()


func _set_intensity(value: float) -> void:
	_intensity = value
	_material.set_shader_parameter("intensity", value)
	_update_visible()


func _update_visible() -> void:
	visible = _intensity > 0.001 or _buildup > 0.001
