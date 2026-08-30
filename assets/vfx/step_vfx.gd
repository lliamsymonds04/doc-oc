class_name StepVFX
extends Node3D

var _particles: Array[GPUParticles3D] = []

func play(global_pos: Vector3, normal := Vector3.UP) -> void:
	global_position = global_pos
	if not normal.is_equal_approx(Vector3.UP):
		var fwd := global_basis.z
		var right := fwd.cross(normal).normalized()
		fwd = normal.cross(right).normalized()
		global_basis = Basis(right, normal, fwd) * Basis(Vector3.RIGHT, 0)

	reset_physics_interpolation()

	for p in _particles:
		p.restart()

func _ready() -> void:
	for child in find_children("*", "GPUParticles3D", true, false):
		var p := child as GPUParticles3D
		p.emitting = false
		_particles.append(p)
