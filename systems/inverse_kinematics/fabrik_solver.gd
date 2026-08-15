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
var should_apply_floor: bool = true

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

	var rot := Basis(axis, atan2(axis.dot(bend_vec.cross(pole_vec)), bend_vec.dot(pole_vec)))
	for i in range(1, joints.size()):
		joints[i] = root + rot * (joints[i] - root)
	bend_hint = pole_vec


## Nudges interior joints off the root-target line toward the pole.
func _seed_bend_toward_pole(root: Vector3, axis: Vector3, pole_dir: Vector3) -> void:
	var seed := 0.01
	for i in range(1, joints.size() - 1):
		var offset: Vector3 = joints[i] - root
		var along := axis * offset.dot(axis)
		joints[i] = root + along + pole_dir * seed


func _apply_floor(floor_y: float, margin: float) -> void:
	for i in range(1, joints.size() - 1):
		if joints[i].y < floor_y + margin:
			joints[i].y = floor_y + margin


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
		if lat.dot(pole_lat) < 0.0:
			joints[i] = root + along - lat


## Clamp outgoing bone at interior joint `i` to signed curl in [-max_dev, 0].
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
	signed = clampf(signed, -max_dev, 0.0)
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


## Post-pass convenience for external callers / debugging.
func apply_hinge_constraints(pole: Vector3) -> void:
	if joints.size() < 3 or hinge_axes.is_empty():
		return
	var max_dev := deg_to_rad(180.0 - min_joint_angle)
	var global_hinge := _global_hinge(joints[0], joints[joints.size() - 1], pole)
	for i in range(1, joints.size() - 1):
		_clamp_outgoing(i, global_hinge, max_dev)


func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	if root.distance_to(target) > total_length:
		for i in range(joints.size() - 1):
			joints[i + 1] = _stretch(joints[i], target, lengths[i])
		return joints

	var max_dev := deg_to_rad(180.0 - min_joint_angle)
	var has_hinges := not hinge_axes.is_empty() and joints.size() >= 3

	apply_pole(target, root, pole)

	for _iter in range(max_iterations):
		var global_hinge := _global_hinge(root, target, pole) if has_hinges else Vector3.ZERO

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
			_apply_floor(target.y, floor_y_margin)

		apply_pole(target, root, pole)

		if has_hinges:
			# Guarantee C-curve after pole align (catches any residual S-bend).
			_enforce_c_curve(root, target, pole)
			joints[0] = root
			for i in range(joints.size() - 1):
				joints[i + 1] = _stretch(joints[i], joints[i + 1], lengths[i])
			global_hinge = _global_hinge(root, target, pole)
			for i in range(1, joints.size() - 1):
				_clamp_outgoing(i, global_hinge, max_dev)

		if joints[joints.size() - 1].distance_to(target) < tolerance:
			break

	return joints


## Returns the point `length` away from `a` toward `b`.
func _stretch(a: Vector3, b: Vector3, length: float) -> Vector3:
	return a.lerp(b, length / maxf(a.distance_to(b), 0.0001))


func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]
