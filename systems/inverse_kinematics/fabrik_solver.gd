class_name FabrikSolver
extends RefCounted

var joints: PackedVector3Array
var lengths: PackedFloat32Array
var total_length: float
var bend_hint := Vector3.ZERO
var tolerance: float = 0.01
var max_iterations: int = 10
var floor_y_margin: float = 0.0
var min_joint_angle: float = 0.0

## Hinge axis per interior joint, in the previous segment's local frame
var hinge_axes: Array[Vector3] = []

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

	var bend_vec := joints[(joints.size() - 1) / 2] - root
	bend_vec -= axis * bend_vec.dot(axis)
	if bend_vec.length_squared() < 0.0001:
		bend_vec = bend_hint
	if bend_vec.length_squared() < 0.0001:
		return
	bend_vec = bend_vec.normalized()

	var pole_vec := pole - root
	pole_vec -= axis * pole_vec.dot(axis)
	if pole_vec.length_squared() < 0.0001:
		return
	pole_vec = pole_vec.normalized()

	var rot := Basis(axis, atan2(axis.dot(bend_vec.cross(pole_vec)), bend_vec.dot(pole_vec)))
	for i in range(1, joints.size()):
		joints[i] = root + rot * (joints[i] - root)
	bend_hint = pole_vec

func _apply_floor(floor_y: float, margin: float) -> void:
	for i in range(1, joints.size() - 1):
		if joints[i].y < floor_y + margin:
			joints[i].y = floor_y + margin

## Projects each interior joint onto its hinge axis and clamps the joint angle
## to min_joint_angle. The bend plane is re-derived from the pole every call.
func apply_hinge_constraints(pole: Vector3) -> void:
	if joints.size() < 3 or hinge_axes.is_empty():
		return

	var max_dev := deg_to_rad(180.0 - min_joint_angle)
	var cos_limit := cos(max_dev)
	var sin_dev := sin(max_dev)
	var prev_dir := (joints[1] - joints[0]).normalized()

	for i in range(1, joints.size() - 1):
		var axis_local: Vector3 = hinge_axes[i - 1] if i - 1 < hinge_axes.size() else Vector3.UP

		# Frame of the parent segment: ref = pole projected perpendicular to it,
		# side = prev_dir x ref. World axes fall back when the pole is colinear.
		var ref := pole - joints[i]
		ref -= prev_dir * ref.dot(prev_dir)
		if ref.length_squared() < 0.0001:
			ref = Vector3.UP - prev_dir * Vector3.UP.dot(prev_dir)
		if ref.length_squared() < 0.0001:
			ref = Vector3.RIGHT
		ref = ref.normalized()

		var side := prev_dir.cross(ref).normalized()
		var hinge_axis := (side * axis_local.x + ref * axis_local.y + prev_dir * axis_local.z).normalized()

		# Remove swing along the hinge axis, then clamp the fold angle
		# (a hairpin with no defined direction falls back to the pole).
		var constrained := (joints[i + 1] - joints[i]).normalized()
		constrained -= hinge_axis * constrained.dot(hinge_axis)
		if constrained.length_squared() < 0.0001:
			constrained = prev_dir
		constrained = constrained.normalized()

		if constrained.dot(prev_dir) < cos_limit:
			var perp := constrained - prev_dir * constrained.dot(prev_dir)
			if perp.length_squared() < 0.0001:
				perp = ref
			constrained = (prev_dir * cos_limit + perp.normalized() * sin_dev).normalized()

		joints[i + 1] = joints[i] + constrained * lengths[i]
		prev_dir = constrained

func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	if root.distance_to(target) > total_length:
		for i in range(joints.size() - 1):
			joints[i + 1] = _stretch(joints[i], target, lengths[i])
		return joints

	for _iter in range(max_iterations):
		joints[joints.size() - 1] = target
		for i in range(joints.size() - 2, -1, -1):
			joints[i] = _stretch(joints[i + 1], joints[i], lengths[i])
		joints[0] = root
		for i in range(joints.size() - 1):
			joints[i + 1] = _stretch(joints[i], joints[i + 1], lengths[i])

		_apply_floor(target.y, floor_y_margin)
		apply_pole(target, root, pole)
		apply_hinge_constraints(pole)

		if joints[joints.size() - 1].distance_to(target) < tolerance:
			break

	return joints

## Returns the point `len` away from `a` toward `b`.
func _stretch(a: Vector3, b: Vector3, len: float) -> Vector3:
	return a.lerp(b, len / maxf(a.distance_to(b), 0.0001))

func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]
