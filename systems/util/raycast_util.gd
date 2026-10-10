class_name RaycastUtil
extends RefCounted

# ============================================================================
# Debug visualization - safe to call even when DebugRayDrawer is not in tree.
# If no DebugRayDrawer node exists (production), these are no-ops.
# duration == 0.0 -> 1 frame, duration > 0.0 -> lingering (e.g. 0.5)
# ============================================================================


## Generic coloured line. Use for any ray debugging.
## [param thickness] <0 -> use drawer's default_thickness, 0 -> 1px line, >0 -> tube radius.
static func debug_ray(
	from: Vector3,
	to: Vector3,
	color: Color = Color.WHITE,
	duration: float = 0.0,
	thickness: float = -1.0
) -> void:
	var drawer = DebugRayDrawer.instance
	if drawer == null:
		return
	drawer.draw_ray(from, to, color, duration, thickness)


## Wrapper around [method shape_cast] that also draws the swept ray.
## Draws [param hit_color] to the hit point (plus normal) or [param miss_color] for the full motion.
## [param thickness] controls tube radius (see [method DebugRayDrawer.draw_ray]).
static func shape_cast_debug(
	space: PhysicsDirectSpaceState3D,
	shape: Shape3D,
	origin: Vector3,
	motion: Vector3,
	mask: int,
	duration: float = 0.0,
	hit_color: Color = Color.GREEN,
	miss_color: Color = Color.RED,
	thickness: float = -1.0
) -> Variant:
	var result = shape_cast(space, shape, origin, motion, mask)
	var drawer = DebugRayDrawer.instance
	if drawer != null:
		if result != null:
			var hit_pos: Vector3 = result["position"]
			var hit_n: Vector3 = result["normal"]
			drawer.draw_ray(origin, hit_pos, hit_color, duration, thickness)
			drawer.draw_hit(hit_pos, hit_n, hit_color, duration, 0.4, thickness)
			if shape is SphereShape3D:
				drawer.draw_sphere(
					hit_pos, (shape as SphereShape3D).radius, hit_color, duration, thickness
				)
		else:
			drawer.draw_ray(origin, origin + motion, miss_color, duration, thickness)
	return result


## Simple physics ray (not shape). Useful for quick wall/ground checks.
static func raycast_debug(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	mask: int,
	duration: float = 0.0,
	hit_color: Color = Color.GREEN,
	miss_color: Color = Color.RED,
	thickness: float = -1.0
) -> Dictionary:
	var params = PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit = space.intersect_ray(params)
	var drawer = DebugRayDrawer.instance
	if drawer != null:
		if not hit.is_empty():
			drawer.draw_ray(from, hit["position"], hit_color, duration, thickness)
			drawer.draw_hit(hit["position"], hit["normal"], hit_color, duration, 0.4, thickness)
		else:
			drawer.draw_ray(from, to, miss_color, duration, thickness)
	return hit


static func shape_cast(
	space: PhysicsDirectSpaceState3D, shape: Shape3D, origin: Vector3, motion: Vector3, mask: int
) -> Variant:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = mask
	params.motion = motion

	var sweep := space.cast_motion(params)
	var safe: float = sweep[0]  # [safe_fraction, unsafe_fraction]
	if safe >= 1.0:
		var overlap_rest := space.get_rest_info(params)
		if overlap_rest.is_empty():
			return null
		return {
			"position": overlap_rest["point"],
			"normal": overlap_rest["normal"],
			"collider": instance_from_id(overlap_rest["collider_id"])
		}

	params.transform = Transform3D(Basis.IDENTITY, origin + motion * safe)
	var rest := space.get_rest_info(params)
	if rest.is_empty():
		# absolute nudge: 0.02 world units past the safe point, not 0.02 of the motion,
		# so a longer cast can't push the shape center through a (concave) surface
		params.transform = Transform3D(
			Basis.IDENTITY, origin + motion * safe + motion.normalized() * 0.02
		)
		rest = space.get_rest_info(params)
	if rest.is_empty():
		return null

	return {
		"position": rest["point"],
		"normal": rest["normal"],
		"collider": instance_from_id(rest["collider_id"])
	}
