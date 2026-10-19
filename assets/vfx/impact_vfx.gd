class_name ImpactVFX
extends OneShotVFX


func play(global_pos: Vector3, normal := Vector3.UP) -> void:
	global_position = global_pos
	if not normal.is_equal_approx(Vector3.UP):
		var fwd := global_basis.z
		var right := fwd.cross(normal)
		if right.length_squared() < 0.001:
			# fwd is zero or (anti)parallel to the surface normal, so the cross
			# product degenerates and the basis would be singular (det == 0).
			# Fall back to a world axis that can't be parallel to the normal.
			var fallback: Vector3 = (
				Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.9 else Vector3.UP
			)
			right = fallback.cross(normal)
		right = right.normalized()
		fwd = normal.cross(right).normalized()
		global_basis = Basis(right, normal, fwd)
	else:
		global_basis = Basis.IDENTITY

	restart_emitters()
