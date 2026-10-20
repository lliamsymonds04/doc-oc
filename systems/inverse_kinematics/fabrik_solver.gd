class_name FabrikSolver
extends RefCounted

# how far off anti-parallel bend/pole has to be before the side is re-chosen
const ANTIPARALLEL_BAND: float = 0.35
# fraction of a joint's lateral offset it must be past the axis to get mirrored
const C_CURVE_DEAD_BAND: float = 0.02
# fraction of a joint-limit overshoot removed per iteration; hard clamping every
# iteration makes the chain orbit its limits instead of settling
const CLAMP_SOFTNESS: float = 0.85

var joints: PackedVector3Array
var lengths: PackedFloat32Array
var total_length: float
var bend_hint := Vector3.ZERO
var tolerance: float = 0.01
var max_iterations: int = 10
var min_joint_angle: float = 0.0  # soft lower bound: see CLAMP_SOFTNESS

## Floor plane normal in the solver's local joint space.
var floor_normal: Vector3 = Vector3.UP
var floor_margin: float = 0.0

## Hinge axis per interior joint, in the previous segment's local frame
var hinge_axes: Array[Vector3] = []
var should_apply_floor: bool = true

## false while grabbing: skips pole alignment, C-curve mirroring and curl clamps,
## leaving pure FABRIK (length/root/tip). set_pole_constraints seeds the bend on disable.
var use_pole_constraints: bool = true


func _init(p_joints: PackedVector3Array):
	joints = p_joints
	lengths = PackedFloat32Array()
	total_length = 0.0
	for i in range(p_joints.size() - 1):
		lengths.append((p_joints[i + 1] - p_joints[i]).length())
		total_length += lengths[i]


## Rotates the whole chain about the root-target axis so the bend faces the pole.
func apply_pole(target: Vector3, root: Vector3, pole: Vector3) -> void:
	var axis := target - root
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()

	var pole_vec := pole - root
	pole_vec -= axis * pole_vec.dot(axis)
	if pole_vec.length_squared() < 0.0001:
		return
	pole_vec = pole_vec.normalized()

	var bend_vec := joints[(joints.size() - 1) / 2.0] - root
	bend_vec -= axis * bend_vec.dot(axis)
	if bend_vec.length_squared() < 0.0001:
		bend_vec = bend_hint
	# Collinear singularity: FABRIK stays straight forever unless we seed a bend.
	if bend_vec.length_squared() < 0.0001:
		_seed_bend_toward_pole(root, axis, pole_vec)
		bend_vec = pole_vec
	else:
		bend_vec = bend_vec.normalized()

	# Shortest-arc alignment, except near anti-parallel where the cross product is
	# numerical noise and the chain would snap to whichever side it lands on:
	# take the full turn instead. Basis(axis, PI) is the same rotation as
	# Basis(axis, -PI), so the side it ends up on is not a choice being made here.
	var angle := atan2(axis.dot(bend_vec.cross(pole_vec)), bend_vec.dot(pole_vec))
	if absf(angle) > PI - ANTIPARALLEL_BAND:
		angle = PI

	var rot := Basis(axis, angle)
	for i in range(1, joints.size()):
		joints[i] = root + rot * (joints[i] - root)
	bend_hint = rot * bend_vec


func _max_segment_error() -> float:
	var worst := 0.0
	for i in range(joints.size() - 1):
		worst = maxf(worst, absf(joints[i + 1].distance_to(joints[i]) - lengths[i]))
	return worst


## Nudges interior joints off the root-target line toward the pole.
func _seed_bend_toward_pole(root: Vector3, axis: Vector3, pole_dir: Vector3) -> void:
	var bend_seed := 0.01
	for i in range(1, joints.size() - 1):
		var offset: Vector3 = joints[i] - root
		var along := axis * offset.dot(axis)
		joints[i] = root + along + pole_dir * bend_seed


func _apply_floor(floor_origin: Vector3) -> void:
	if floor_margin == 0.0:
		return

	for i in range(1, joints.size() - 1):
		var signed_dist := joints[i].dot(floor_normal) - floor_origin.dot(floor_normal)
		if signed_dist < floor_margin:
			joints[i] += floor_normal * (floor_margin - signed_dist)


## Global hinge for a C-curve with apexes toward the pole.
## Right-hand positive rotation swings a bone toward the pole, so valid knee/elbow
## curls use signed angles in [-max_dev, 0].
func _global_hinge(root: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var axis := target - root
	if axis.length_squared() < 0.0001:
		return Vector3.ZERO
	axis = axis.normalized()
	var pole_lat := pole - root
	pole_lat -= axis * pole_lat.dot(axis)
	if pole_lat.length_squared() < 0.0001:
		return Vector3.ZERO
	return axis.cross(pole_lat.normalized()).normalized()


## Mirror interior joints that sit on the wrong side of root→target onto the pole side.
func _enforce_c_curve(root: Vector3, target: Vector3, pole: Vector3) -> void:
	var axis := target - root
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()
	var pole_lat := pole - root
	pole_lat -= axis * pole_lat.dot(axis)
	if pole_lat.length_squared() < 0.0001:
		return
	pole_lat = pole_lat.normalized()
	for i in range(1, joints.size() - 1):
		var offset: Vector3 = joints[i] - root
		var along := axis * offset.dot(axis)
		var lat := offset - along
		# Dead band: a joint sitting on the axis has no side, and mirroring it
		# every iteration chatters against the floor and hinge clamps.
		if lat.dot(pole_lat) < -C_CURVE_DEAD_BAND * lat.length():
			joints[i] = root + along - lat


## Clamp outgoing bone at interior joint `i` toward a signed curl in
## [-max_dev, 0]. Soft: each call removes CLAMP_SOFTNESS of the overshoot, so a
## joint can sit up to (1 - CLAMP_SOFTNESS) of it past the limit.
func _clamp_outgoing(i: int, global_hinge: Vector3, max_dev: float) -> void:
	if global_hinge.length_squared() < 0.0001:
		return
	if i < 1 or i >= joints.size() - 1:
		return

	var prev_dir := (joints[i] - joints[i - 1]).normalized()
	var hinge_axis := global_hinge - prev_dir * global_hinge.dot(prev_dir)
	if hinge_axis.length_squared() < 0.0001:
		hinge_axis = global_hinge
	else:
		hinge_axis = hinge_axis.normalized()

	var out_dir := prev_dir - hinge_axis * prev_dir.dot(hinge_axis)
	if out_dir.length_squared() < 0.0001:
		out_dir = prev_dir
	out_dir = out_dir.normalized()

	var child := joints[i + 1] - joints[i]
	child -= hinge_axis * child.dot(hinge_axis)
	if child.length_squared() < 0.0001:
		child = out_dir
	else:
		child = child.normalized()

	var signed := atan2(hinge_axis.dot(out_dir.cross(child)), out_dir.dot(child))
	signed = lerpf(signed, clampf(signed, -max_dev, 0.0), CLAMP_SOFTNESS)
	joints[i + 1] = joints[i] + (Basis(hinge_axis, signed) * out_dir).normalized() * lengths[i]


## Clamp incoming bone at interior joint `i` (backward pass). Moves joints[i-1].
func _clamp_incoming(i: int, global_hinge: Vector3, max_dev: float) -> void:
	if global_hinge.length_squared() < 0.0001:
		return
	if i < 1 or i >= joints.size() - 1:
		return

	var next_dir := (joints[i + 1] - joints[i]).normalized()
	var hinge_axis := global_hinge - next_dir * global_hinge.dot(next_dir)
	if hinge_axis.length_squared() < 0.0001:
		hinge_axis = global_hinge
	else:
		hinge_axis = hinge_axis.normalized()

	var child := next_dir - hinge_axis * next_dir.dot(hinge_axis)
	if child.length_squared() < 0.0001:
		return
	child = child.normalized()

	var prev := joints[i] - joints[i - 1]
	prev -= hinge_axis * prev.dot(hinge_axis)
	if prev.length_squared() < 0.0001:
		prev = child
	else:
		prev = prev.normalized()

	var signed := atan2(hinge_axis.dot(prev.cross(child)), prev.dot(child))
	var clamped := clampf(signed, -max_dev, 0.0)
	var rot := Basis(hinge_axis, clamped - signed)
	var new_prev := (rot * prev).normalized()
	joints[i - 1] = joints[i] - new_prev * lengths[i - 1]


func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	if root.distance_to(target) > total_length:
		joints[0] = root
		for i in range(joints.size() - 1):
			joints[i + 1] = _stretch(joints[i], target, lengths[i])
		return joints

	var max_dev := deg_to_rad(180.0 - min_joint_angle)
	var has_hinges := not hinge_axes.is_empty() and joints.size() >= 3 and use_pole_constraints

	for _iter in range(max_iterations):
		var global_hinge := _global_hinge(root, target, pole) if has_hinges else Vector3.ZERO

		# Realign every iteration, not just once: without it the chain twists away
		# from the pole across a long reach and swings to the wrong side.
		if use_pole_constraints:
			apply_pole(target, root, pole)

		if has_hinges:
			# Guarantee C-curve before the projections, never after: mirroring or
			# clamping on the way out leaves the tip off-target, so the next frame
			# starts from a pose that is not a solution and the chain swings.
			_enforce_c_curve(root, target, pole)
			joints[0] = root
			for i in range(joints.size() - 1):
				joints[i + 1] = _stretch(joints[i], joints[i + 1], lengths[i])
			global_hinge = _global_hinge(root, target, pole)
			for i in range(1, joints.size() - 1):
				_clamp_outgoing(i, global_hinge, max_dev)

		# Backward: tip → root
		joints[joints.size() - 1] = target
		for i in range(joints.size() - 2, -1, -1):
			joints[i] = _stretch(joints[i + 1], joints[i], lengths[i])
			if has_hinges and i + 1 >= 1 and i + 1 <= joints.size() - 2:
				_clamp_incoming(i + 1, global_hinge, max_dev)

		# Forward: root → tip
		joints[0] = root
		for i in range(joints.size() - 1):
			joints[i + 1] = _stretch(joints[i], joints[i + 1], lengths[i])
			if has_hinges and i >= 1 and i <= joints.size() - 2:
				_clamp_outgoing(i, global_hinge, max_dev)

		if should_apply_floor:
			_apply_floor(target)

		if joints[joints.size() - 1].distance_to(target) < tolerance:
			break

	# A floor correction on the final iteration detaches the chain. Re-run pure
	# FABRIK (root and tip pinned) so the returned pose is a valid limb again;
	# re-projecting from one end alone would drag the root off the mount.
	if _max_segment_error() > 0.05:
		for _restore in range(4):
			joints[joints.size() - 1] = target
			for i in range(joints.size() - 2, -1, -1):
				joints[i] = _stretch(joints[i + 1], joints[i], lengths[i])
			joints[0] = root
			for i in range(joints.size() - 1):
				joints[i + 1] = _stretch(joints[i], joints[i + 1], lengths[i])

	return joints


## Turns the pole machinery (alignment, C-curve mirror, curl clamps) on/off.
## Disabling seeds the bend toward the pole once first: from a straight chain,
## pure FABRIK folds accordion-style along the root->target line and never converges.
func set_pole_constraints(enabled: bool, target: Vector3, root: Vector3, pole: Vector3) -> void:
	use_pole_constraints = enabled
	if enabled:
		return
	var axis := target - root
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()
	var bend_vec := joints[(joints.size() - 1) / 2] - root
	bend_vec -= axis * bend_vec.dot(axis)
	if bend_vec.length_squared() >= 0.0025:
		return  # chain already has a bend; keep it
	var pole_lat := pole - root
	pole_lat -= axis * pole_lat.dot(axis)
	if pole_lat.length_squared() < 0.0001:
		return
	_seed_bend_toward_pole(root, axis, pole_lat.normalized())


## Returns the point `length` away from `a` toward `b`.
func _stretch(a: Vector3, b: Vector3, length: float) -> Vector3:
	return a.lerp(b, length / maxf(a.distance_to(b), 0.0001))


func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]
