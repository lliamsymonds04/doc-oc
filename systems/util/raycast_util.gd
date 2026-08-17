extends RefCounted
class_name RaycastUtil

static func shape_cast(space: PhysicsDirectSpaceState3D, shape: Shape3D, origin: Vector3, motion: Vector3, mask: int) -> Variant:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = mask
	params.motion = motion

	var sweep := space.cast_motion(params)
	var safe: float = sweep[0]  # [safe_fraction, unsafe_fraction]
	if safe >= 1.0:
		return null

	params.transform = Transform3D(Basis.IDENTITY, origin + motion * safe)
	var rest := space.get_rest_info(params)
	if rest.is_empty():
		params.transform = Transform3D(Basis.IDENTITY, origin + motion * minf(safe + 0.02, 1.0))
		rest = space.get_rest_info(params)
	if rest.is_empty():
		return null

	return {"position": rest["point"], "normal": rest["normal"]}
