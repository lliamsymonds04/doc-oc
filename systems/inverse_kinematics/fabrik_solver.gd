class_name FabrikSolver
extends RefCounted

var joints: PackedVector3Array
var lengths: PackedFloat32Array
var total_length: float
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
	var axis := (target - root).normalized()

	for i in range(1,joints.size() - 1):
		var joint_vector := joints[i] - root
		var pole_vector := pole - root

		joint_vector -= axis * joint_vector.dot(axis)
		pole_vector -= axis * pole_vector.dot(axis)

		if joint_vector.length_squared() < 0.0001:
			continue
		if pole_vector.length_squared() < 0.0001:
			continue


		joint_vector = joint_vector.normalized()
		pole_vector = pole_vector.normalized()

		var angle := atan2(
			axis.dot(joint_vector.cross(pole_vector)),
			joint_vector.dot(pole_vector)
		)

		joints[i] = root + Basis(axis, angle) * (joints[i] - root)

func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	var dist_to_target = root.distance_to(target)

	# Unreachable: stretch the chain straight toward the target.
	if dist_to_target > total_length:
		for i in range(joints.size() - 1):
			var r = joints[i].distance_to(target)
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i + 1] = joints[i].lerp(target, lam)
		return joints

	# Reachable: alternate backward/forward passes until the end effector
	# is within tolerance of the target or we run out of iterations.
	for _iter in range(max_iterations):
		if joints[joints.size() - 1].distance_to(target) < tolerance:
			return joints

		# Backward pass: end -> root
		joints[joints.size() - 1] = target
		for i in range(joints.size() - 2, -1, -1):
			var r = joints[i].distance_to(joints[i + 1])
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i] = joints[i + 1].lerp(joints[i], lam)


		# Forward pass: root -> end
		joints[0] = root
		for i in range(joints.size() - 1):
			var r = joints[i].distance_to(joints[i + 1])
			var lam = lengths[i] / maxf(r, 0.0001)
			joints[i + 1] = joints[i].lerp(joints[i + 1], lam)

		apply_pole(target, root, pole)

	return joints

func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]
