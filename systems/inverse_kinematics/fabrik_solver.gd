class_name FabrikSolver
extends RefCounted

var joints: PackedVector3Array
var lengths: PackedFloat32Array
var total_length: float
var bend_hint := Vector3.ZERO
var tolerance: float = 0.01
var max_iterations: int = 10

func _init(p_joints: PackedVector3Array):
	joints = p_joints
	lengths = PackedFloat32Array()
	total_length = 0.0
	for i in range(p_joints.size() - 1):
		lengths.append((p_joints[i + 1] - p_joints[i]).length())
		total_length += lengths[i]

func apply_pole(target: Vector3, root: Vector3, pole: Vector3) -> void:
	var axis := target - root
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()

	var bend_point := joints[int((joints.size() - 1) * 0.5)]
	var bend_vec := bend_point - root
	bend_vec -= axis * bend_vec.dot(axis)

	if bend_vec.length_squared() < 0.0001:
		if bend_hint.length_squared() < 0.0001:
			return
		bend_vec = bend_hint
	bend_vec = bend_vec.normalized()

	var pole_vec := pole - root
	pole_vec -= axis * pole_vec.dot(axis)
	if pole_vec.length_squared() < 0.0001:
		return
	pole_vec = pole_vec.normalized()

	var angle := atan2(
		axis.dot(bend_vec.cross(pole_vec)),
		bend_vec.dot(pole_vec)
	)

	var rot := Basis(axis, angle)
	for i in range(1, joints.size()):
		joints[i] = root + rot * (joints[i] - root)

	bend_hint = pole_vec

func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	var dist_to_target = root.distance_to(target)

	if dist_to_target > total_length:
		for i in range(joints.size() - 1):
			var r = joints[i].distance_to(target)
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i + 1] = joints[i].lerp(target, lam)
		return joints

	for _iter in range(max_iterations):
		if joints[joints.size() - 1].distance_to(target) < tolerance:
			return joints

		joints[joints.size() - 1] = target
		for i in range(joints.size() - 2, -1, -1):
			var r = joints[i].distance_to(joints[i + 1])
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i] = joints[i + 1].lerp(joints[i], lam)

		joints[0] = root
		for i in range(joints.size() - 1):
			var r = joints[i].distance_to(joints[i + 1])
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i + 1] = joints[i].lerp(joints[i + 1], lam)

		apply_pole(target, root, pole)

	return joints

func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]