class_name MotorSound
extends AudioStreamPlayer3D

## Speed (m/s) above which the motor counts as running.
const MIN_SPEED := 0.3
## Seconds the ramp takes in either direction.
const FADE_TIME := 0.2
## Ends the fade inaudible rather than at the last dB.
const SILENT_DB := -60.0

## Steady-state level while moving.
@export var running_db: float = -6.0
## Random per-instance detune, so a crowd of bots does not phase into one drone.
@export var pitch_deviation: float = 0.05

var _enemy: EnemyController


func _ready() -> void:
	_enemy = get_parent() as EnemyController
	if _enemy == null:
		push_error("MotorSound must sit on an EnemyController, got: %s" % get_parent())

	pitch_scale = 1.0 + randf_range(-pitch_deviation, pitch_deviation)
	volume_db = SILENT_DB


## Reads the body's own velocity, so nothing has to tell the motor to start.
## Ramping the level instead of tweening it makes play/stop follow the level, so a
## clip that ran out mid-walk restarts instead of going quiet for good.
func _physics_process(dt: float) -> void:
	var moving := _enemy != null and not _enemy.is_ragdolled()
	moving = moving and _enemy.velocity.length() > MIN_SPEED

	var target := running_db if moving else SILENT_DB
	volume_db = move_toward(volume_db, target, (running_db - SILENT_DB) / FADE_TIME * dt)

	if volume_db > SILENT_DB and not playing:
		play()
	elif volume_db <= SILENT_DB and playing:
		stop()
