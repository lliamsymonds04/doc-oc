class_name DashTrailVFX
extends OneShotVFX

@onready var _lines: GPUParticles3D = $Lines


## direction: world-space unit vector the dash travels along
func play(direction: Vector3) -> void:
	var material := _lines.process_material as ParticleProcessMaterial
	if material:
		# the emitters live in local space, so convert before writing
		var world_dir := direction.normalized()
		assert(not world_dir.is_zero_approx(), "DashTrailVFX.play needs a non-zero direction")
		material.direction = _lines.global_basis.inverse() * world_dir

	restart_emitters()
