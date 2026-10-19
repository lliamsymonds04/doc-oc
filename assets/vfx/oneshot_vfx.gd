class_name OneShotVFX
extends Node3D

## Particle emitters owned by this effect's scene, cached on ready.
## Scene scripts call restart_emitters(); the caller never touches the children.
var _emitters: Array[GPUParticles3D] = []


func _ready() -> void:
	# one-shot emitters must start idle, in case the scene was saved mid-burst
	for child in find_children("*", "GPUParticles3D", true, false):
		var emitter := child as GPUParticles3D
		emitter.emitting = false
		_emitters.append(emitter)


func restart_emitters() -> void:
	reset_physics_interpolation()

	for emitter in _emitters:
		emitter.restart()
