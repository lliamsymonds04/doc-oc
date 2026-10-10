extends RefCounted
class_name GrabThrowMeter

## Upward-mouse meter for held bodies.

var _up_speed := 0.0
var _fov_charge := 0.0


func tick(mouse_delta: Vector2, holding: bool, config: PlayerGrabConfig) -> void:
	_sample_mouse_y_speed(mouse_delta, holding, config)
	_update_fov_charge(mouse_delta, holding, config)


## Smoothed up-pixels per physics tick
func flick_pixels() -> float:
	return _up_speed


## Throw speed in m/s for the current flick strength.
func throw_speed(config: PlayerGrabConfig) -> float:
	return clampf(_up_speed * config.RELEASE_THROW_SENS, 0.0, config.RELEASE_THROW_MAX_SPEED)


func reset_flick() -> void:
	_up_speed = 0.0


## FOV widen for the current charge, 0.0 when uncharged.
func fov_kick(config: PlayerGrabConfig) -> float:
	if _fov_charge <= 0.0:
		return 0.0
	return config.charge_fov_kick * (_fov_charge / config.RELEASE_THROW_MAX_SPEED)


func _sample_mouse_y_speed(mouse_delta: Vector2, holding: bool, config: PlayerGrabConfig) -> void:
	if not holding:
		_up_speed = 0.0
		return

	var sample := maxf(-mouse_delta.y, 0.0)
	_up_speed = lerpf(_up_speed, sample, config.RELEASE_MOUSE_SAMPLE)


func _update_fov_charge(mouse_delta: Vector2, holding: bool, config: PlayerGrabConfig) -> void:
	if not holding:
		_fov_charge = move_toward(_fov_charge, 0.0, config.FOV_CHARGE_DECAY_PER_TICK)
	else:
		_charge_fov_mouse(mouse_delta, config)


func _charge_fov_mouse(mouse_delta: Vector2, config: PlayerGrabConfig) -> void:
	var up_pixels := maxf(-mouse_delta.y, 0.0)
	if up_pixels > 0.0:
		_fov_charge = minf(
			_fov_charge + up_pixels * config.RELEASE_THROW_SENS, config.RELEASE_THROW_MAX_SPEED
		)
	else:
		_fov_charge = move_toward(_fov_charge, 0.0, config.FOV_CHARGE_DECAY_PER_TICK)
