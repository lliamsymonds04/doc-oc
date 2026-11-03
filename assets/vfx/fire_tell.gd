class_name FireTell
extends Node3D

## Charge-up played at the muzzle through a ranged attack's windup: the glow
## grows and embers converge until the shot leaves.

var _tween: Tween

@onready var _glow: MeshInstance3D = $Glow
@onready var _charge: GPUParticles3D = $Charge


func _ready() -> void:
	stop()


## Grows the glow over `duration`; call it when the windup starts.
func start(duration: float) -> void:
	stop()

	visible = true
	_glow.scale = Vector3.ONE * 0.05

	# The emitter idled for a whole cooldown; without this its first burst reuses
	# the muzzle transform from the previous shot before catching up.
	reset_physics_interpolation()
	_glow.reset_physics_interpolation()
	_charge.reset_physics_interpolation()
	_charge.emitting = true
	_charge.restart()

	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_glow, "scale", Vector3.ONE, duration)


func stop() -> void:
	if _tween:
		_tween.kill()
		_tween = null

	visible = false
	if is_instance_valid(_charge):
		_charge.emitting = false
