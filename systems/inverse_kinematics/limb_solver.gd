class_name LimbSolver
extends RefCounted

## Closed-form planar IK for a three-bone limb. The bend plane is the
## root->target axis plus the pole, or the chain's carried bend when the pole is
## off. Root, bone lengths and the tip are exact by construction.

var joints: PackedVector3Array
var lengths: PackedFloat32Array
var total_length: float
var min_joint_angle: float = 0.0  # interior angle lower bound, in degrees

## Floor plane normal in the solver's local space. The plane passes through the
## target, so `floor_margin` is measured from the target's own plane.
var floor_normal: Vector3 = Vector3.UP
var floor_margin: float = 0.0
var should_apply_floor: bool = true

## false while grabbing: the pole stops choosing the bend plane, so the chain
## keeps its side. The joint limits still apply.
var use_pole_constraints: bool = true

## Arms only: the middle joint must curl the same way as the first, so the limb
## stays a C instead of an S. Off for legs, which cannot S.
var enforce_inward_bend: bool = false

## With `enforce_inward_bend`: how far the first joint bends off straight, in
## degrees, to keep a visible elbow. Dropped when the target is out of reach.
var inward_bend_min: float = 0.0

## Bend plane carried across solves. Re-deriving it from the pose lets a
## mirrored pose flip the plane and the plane flip the pose back forever.
var _plane_normal := Vector3.ZERO

## Scratch pose for `_pose_at`, reused to avoid a per-call allocation.
var _pose := PackedVector3Array()


func _init(p_joints: PackedVector3Array):
	joints = p_joints
	_pose.resize(p_joints.size())
	lengths = PackedFloat32Array()
	total_length = 0.0
	for i in range(p_joints.size() - 1):
		lengths.append((p_joints[i + 1] - p_joints[i]).length())
		total_length += lengths[i]


func solve(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	if root.distance_to(target) > total_length:
		return _stretch_to(target, root)

	if joints.size() == 4:
		return _solve_three_bone(target, root, pole)

	push_error("LimbSolver expects three limb bones, got %d" % (joints.size() - 1))
	return _stretch_to(target, root)


func set_pole_constraints(enabled: bool) -> void:
	use_pole_constraints = enabled


func get_end_effector() -> Vector3:
	return joints[joints.size() - 1]


## Straight pose for an out-of-reach target; the tip stops at full length.
func _stretch_to(target: Vector3, root: Vector3) -> PackedVector3Array:
	joints[0] = root
	for i in range(joints.size() - 1):
		joints[i + 1] = _stretch(joints[i], target, lengths[i])
	return joints


## Unit axis root->target, or the current first bone when the target is on the root.
func _target_axis(to_target: Vector3, root: Vector3) -> Vector3:
	if to_target.length_squared() > 0.00000001:
		return to_target.normalized()
	var bone := joints[1] - root
	if bone.length_squared() > 0.00000001:
		return bone.normalized()
	return Vector3.DOWN


## Unit normal of the bend plane, pointing at the side the bend should take.
func _bend_normal(u: Vector3, root: Vector3, pole: Vector3) -> Vector3:
	if use_pole_constraints:
		var pole_lat := pole - root
		pole_lat -= u * pole_lat.dot(u)
		if pole_lat.length_squared() > 0.0001:
			_plane_normal = pole_lat.normalized()
			return _plane_normal
	# Pole off (grab) or parallel to the target axis: carry the plane the chain
	# already had rather than reading it back out of the pose.
	var carried := _plane_normal - u * _plane_normal.dot(u)
	if carried.length_squared() > 0.0001:
		_plane_normal = carried.normalized()
		return _plane_normal
	for i in range(joints.size() - 2, 0, -1):
		var chain_lat := joints[i] - root
		chain_lat -= u * chain_lat.dot(u)
		if chain_lat.length_squared() > 0.0001:
			_plane_normal = chain_lat.normalized()
			return _plane_normal
	var fallback := Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT
	_plane_normal = u.cross(fallback).normalized()
	return _plane_normal


## First bone's angle off the target axis, read from the current pose so the next
## solve continues from it instead of choosing a new pose.
func _current_angle(u: Vector3, n: Vector3, root: Vector3) -> float:
	var bone := joints[1] - root
	if bone.length_squared() < 0.00000001:
		return 0.0
	return atan2(bone.dot(n), bone.dot(u))


## Three bones: the first bone's angle is the free parameter, the last two are
## a triangle solved in closed form. The angle is carried from the previous pose
## and clamped into the interval the joint limits and the floor allow.
func _solve_three_bone(target: Vector3, root: Vector3, pole: Vector3) -> PackedVector3Array:
	var to_target := target - root
	var r := maxf(to_target.length(), 0.0001)
	var u := _target_axis(to_target, root)
	var n := _bend_normal(u, root, pole)
	var b1 := lengths[0]
	var b2 := lengths[1]
	var b3 := lengths[2]

	# The elbow's interior angle grows with the first joint's distance to the
	# target, so its limit is an exact lower bound on the first bone's angle.
	var d_min := sqrt(
		maxf(b2 * b2 + b3 * b3 - 2.0 * b2 * b3 * cos(deg_to_rad(min_joint_angle)), 0.0)
	)
	var a_lo := acos(clampf((r * r + b1 * b1 - d_min * d_min) / (2.0 * r * b1), -1.0, 1.0))
	a_lo = maxf(a_lo, 0.0)  # the first joint must stay on the pole side
	var reach := (b2 + b3) * (b2 + b3)
	var a_hi := acos(clampf((r * r + b1 * b1 - reach) / (2.0 * r * b1), -1.0, 1.0))
	a_hi = maxf(a_hi, a_lo)

	var a := clampf(_current_angle(u, n, root), a_lo, a_hi)
	if _slack(_pose_at(a, target, root, u, n), target, root, n) < 0.0:
		a = _choose_angle(a, a_lo, a_hi, target, root, u, n)
	_assign(_pose_at(a, target, root, u, n))
	return joints


## One planar pose: bone 1 at angle `a` from the target axis, the last two bones
## bent toward `n` around the triangle root->joint->target.
func _pose_at(
	a: float, target: Vector3, root: Vector3, u: Vector3, n: Vector3
) -> PackedVector3Array:
	var j1 := root + (u * cos(a) + n * sin(a)) * lengths[0]
	var to_target := target - j1
	var d := maxf(to_target.length(), 0.0001)
	var b2 := lengths[1]
	var b3 := lengths[2]
	var elbow := acos(clampf((b2 * b2 + d * d - b3 * b3) / (2.0 * b2 * d), -1.0, 1.0))
	var s2 := Basis(u.cross(n), elbow) * (to_target / d)
	_pose[0] = root
	_pose[1] = j1
	_pose[2] = j1 + s2 * b2
	_pose[3] = target
	return _pose


## Smallest margin over the joint limits, the pole side and the floor; negative
## means the pose violates something.
func _slack(pose: PackedVector3Array, target: Vector3, root: Vector3, n: Vector3) -> float:
	var limit := deg_to_rad(min_joint_angle)
	var slack := minf(
		(root - pose[1]).angle_to(pose[2] - pose[1]) - limit,
		(pose[1] - pose[2]).angle_to(target - pose[2]) - limit,
	)
	for i in range(1, pose.size() - 1):
		# Interior joints stay on the pole side of the root->target axis. A knee
		# that crosses it points backwards and reads as an S or a hyperextension.
		slack = minf(slack, (pose[i] - root).dot(n))
		if should_apply_floor:
			slack = minf(slack, pose[i].dot(floor_normal) - target.dot(floor_normal) - floor_margin)
	if enforce_inward_bend and pose.size() >= 4:
		var axis := (target - root).normalized().cross(n)
		var d1 := (pose[1] - root).normalized()
		var d2 := (pose[2] - pose[1]).normalized()
		var d3 := (target - pose[2]).normalized()
		var turn1 := atan2(d1.cross(d2).dot(axis), d1.dot(d2))
		var turn2 := atan2(d2.cross(d3).dot(axis), d2.dot(d3))
		# matching turn signs at both joints is a C; opposite is the S we forbid.
		# The bend at the first joint must also clear `inward_bend_min` unless the
		# target is out of reach, where the best pose bends as far as it can.
		var bend := turn1 if turn2 > 0.0 else -turn1
		slack = minf(slack, bend - deg_to_rad(inward_bend_min))
	return slack


## Nearest angle to `a` that satisfies every constraint. The feasible set is a
## band that can close again near full extension, so each side is searched
## separately and the nearer edge wins.
func _choose_angle(
	a: float, a_lo: float, a_hi: float, target: Vector3, root: Vector3, u: Vector3, n: Vector3
) -> float:
	var before := _edge_angle(a, a_lo, target, root, u, n)
	var after := _edge_angle(a, a_hi, target, root, u, n)
	if is_nan(before):
		return after if not is_nan(after) else _least_bad_angle(a_lo, a_hi, target, root, u, n)
	if is_nan(after):
		return before
	return before if absf(a - before) <= absf(after - a) else after


## First feasible angle walking from `a` toward `limit`, refined to the edge by
## bisection; NAN when the whole way is infeasible.
func _edge_angle(
	a: float, limit: float, target: Vector3, root: Vector3, u: Vector3, n: Vector3
) -> float:
	const SAMPLES := 48
	var last := a
	for i in range(1, SAMPLES + 1):
		var probe := lerpf(a, limit, float(i) / SAMPLES)
		if _slack(_pose_at(probe, target, root, u, n), target, root, n) >= 0.0:
			for _refine in range(10):
				var mid := (last + probe) * 0.5
				if _slack(_pose_at(mid, target, root, u, n), target, root, n) >= 0.0:
					probe = mid
				else:
					last = mid
			return probe
		last = probe
	return NAN


## Nothing in the interval is feasible: the angle that violates the least. The
## joint limits outrank the pole side and the floor, so the compromise keeps the
## bones legal and gives up clearance instead.
func _least_bad_angle(
	a_lo: float, a_hi: float, target: Vector3, root: Vector3, u: Vector3, n: Vector3
) -> float:
	const SAMPLES := 32
	var limit := deg_to_rad(min_joint_angle)
	var best := a_lo
	var best_limit := -INF
	var best_slack := -INF
	for i in range(SAMPLES + 1):
		var probe := lerpf(a_lo, a_hi, float(i) / SAMPLES)
		var pose := _pose_at(probe, target, root, u, n)
		var limit_slack := (
			minf(
				(root - pose[1]).angle_to(pose[2] - pose[1]),
				(pose[1] - pose[2]).angle_to(target - pose[2]),
			)
			- limit
		)
		var slack := _slack(pose, target, root, n)
		if (
			limit_slack > best_limit
			or (is_equal_approx(limit_slack, best_limit) and slack > best_slack)
		):
			best_limit = limit_slack
			best_slack = slack
			best = probe
	return best


func _assign(pose: PackedVector3Array) -> void:
	for i in range(joints.size()):
		joints[i] = pose[i]


func _stretch(a: Vector3, b: Vector3, length: float) -> Vector3:
	return a.lerp(b, length / maxf(a.distance_to(b), 0.0001))
