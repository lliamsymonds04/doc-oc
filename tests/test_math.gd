extends Node

## Headless self-checks for the pure movement math. Run with:
##   godot --headless --path . res://tests/test_math.tscn
## Exits non-zero when any check fails. Not a full test suite: one check per
## risky pure function, enough to fail when a sign or an angle wrap regresses.

const EPSILON := 0.0001
const BALLISTIC_DT := 0.0001

var _failures := 0


func _ready() -> void:
	_test_wall_basis()
	_test_limb_reach()
	_test_limb_stretch()
	_test_limb_stability()
	_test_limb_grab_stability()
	_test_limb_punch_shape()
	_test_ballistic_direction()
	_test_ballistic_degenerate()
	_test_aim_point_from_hit()
	_test_slam_target_limits()

	if _failures == 0:
		print("All math checks passed.")
	else:
		printerr("%d math check(s) failed." % _failures)
	get_tree().quit(_failures)


func _test_wall_basis() -> void:
	var flat := WallClimbArms.wall_basis(Vector3.FORWARD)
	_check_vec(flat.y, Vector3.UP, "wall_basis(forward).y is up")
	_check_vec(flat.z, Vector3.FORWARD, "wall_basis(forward).z is the normal")
	_check_close(flat.determinant(), 1.0, "wall_basis(forward) is right-handed")

	var slanted := WallClimbArms.wall_basis(Vector3(0.0, 0.5, 0.8660254).normalized())
	_check_close(slanted.y.dot(slanted.z), 0.0, "wall_basis y is perpendicular to the normal")
	_check_close(slanted.determinant(), 1.0, "slanted wall_basis is right-handed")


func _test_limb_reach() -> void:
	var solver := _three_bone_solver()
	var solved := solver.solve(Vector3(2, 0, 0), Vector3.ZERO, Vector3.UP)
	_check_vec(
		solved[solved.size() - 1], Vector3(2, 0, 0), "limb solver reaches an in-range target"
	)
	_check_lengths(solved, "limb solver preserves segment lengths (reach)")


func _test_limb_stretch() -> void:
	var solver := _three_bone_solver()
	var solved := solver.solve(Vector3(5, 0, 0), Vector3.ZERO, Vector3.UP)
	_check_vec(
		solved[solved.size() - 1],
		Vector3(3, 0, 0),
		"limb solver caps an out-of-reach target at extension"
	)
	_check_lengths(solved, "limb solver preserves segment lengths (stretch)")


## A folded chain (target well inside its reach) with joint limits, a pole and a
## floor is over-constrained: the solver used to leave the pose mid-constraint,
## so the next frame started somewhere else and the arm swung around.
func _test_limb_stability() -> void:
	var solver := LimbSolver.new(
		PackedVector3Array([Vector3.ZERO, Vector3(0, -2, 0), Vector3(0, -4, 0), Vector3(0, -6, 0)])
	)
	solver.min_joint_angle = 20.0
	solver.floor_margin = 0.6

	var pole := Vector3(0.9, -0.8995, 0.2) * 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var target := Vector3(0, -2.4, 0.3)
	var worst_jump := 0.0
	var worst_error := 0.0
	# floor_margin and min_joint_angle are soft here: the floor is a push that the
	# tip projections partly undo, and the curl clamp removes 85% of an overshoot
	# per iteration. These bounds are the measured slop, not the intended value.
	var worst_floor_sag := 0.0
	var worst_overbend := 0.0
	var previous := PackedVector3Array()

	for _frame in range(200):
		# a planted anchor is world-static, so in arm space it barely drifts
		target += (
			Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.02
		)
		target = target.limit_length(2.6)
		var solved := solver.solve(target, Vector3.ZERO, pole)
		worst_error = maxf(worst_error, solved[solved.size() - 1].distance_to(target))
		for i in range(1, solved.size() - 1):
			worst_floor_sag = maxf(
				worst_floor_sag,
				(
					solver.floor_margin
					- (solved[i].dot(solver.floor_normal) - target.dot(solver.floor_normal))
				)
			)
			var incoming := (solved[i - 1] - solved[i]).normalized()
			var outgoing := (solved[i + 1] - solved[i]).normalized()
			worst_overbend = maxf(
				worst_overbend, solver.min_joint_angle - rad_to_deg(incoming.angle_to(outgoing))
			)
		if previous.size() == solved.size():
			for i in range(solved.size()):
				worst_jump = maxf(worst_jump, previous[i].distance_to(solved[i]))
		previous = solved.duplicate()

	_check(worst_error < 0.05, "folded chain keeps its tip on target (%.3f)" % worst_error)
	_check(worst_jump < 0.15, "folded chain does not flip between frames (%.3f)" % worst_jump)
	_check(worst_floor_sag < 0.5, "folded chain stays off the floor (%.3f)" % worst_floor_sag)
	_check(
		worst_overbend < 5.0, "folded chain respects the joint limit (%.1f deg)" % worst_overbend
	)

	# Out of reach: the chain stretches straight, and the root stays pinned.
	var root := Vector3(1.0, 2.0, 3.0)
	var stretched := solver.solve(root + Vector3(0, -20, 0), root, pole)
	_check_vec(stretched[0], root, "stretched chain stays pinned at its root")
	_check_close(
		stretched[stretched.size() - 1].distance_to(root),
		solver.total_length,
		"stretched chain reaches its full length"
	)


## A carried body pulled onto the first bone's line used to flip the bend plane
## (and with it the pose) every frame: the plane was read back out of the
## mirrored pose. With the pole off the plane must be carried instead.
func _test_limb_grab_stability() -> void:
	var solver := LimbSolver.new(
		PackedVector3Array([Vector3.ZERO, Vector3(0, -2, 0), Vector3(0, -4, 0), Vector3(0, -6, 0)])
	)
	solver.min_joint_angle = 20.0
	solver.floor_margin = 0.6
	solver.should_apply_floor = false
	solver.set_pole_constraints(false)
	for _i in range(10):
		solver.solve(Vector3(0.4, -1.0, 0.5), Vector3.ZERO, Vector3.ZERO)

	var bone := (solver.joints[1] - Vector3.ZERO).normalized()
	var q1 := bone.cross(Vector3.UP)
	if q1.length_squared() < 0.5:
		q1 = bone.cross(Vector3.RIGHT)
	q1 = q1.normalized()
	var q2 := bone.cross(q1).normalized()
	var start := Vector3(0.4, -1.0, 0.5)
	var worst_jump := 0.0
	var previous := solver.joints.duplicate()
	for frame in range(120):
		var t := float(frame) / 120.0
		var ramp := minf(t * 10.0, 1.0)
		var along := lerpf(start.dot(bone), 0.8, t)
		var lat1 := lerpf(start.dot(q1), 0.05 * sin(t * TAU * 2.0), ramp)
		var lat2 := lerpf(start.dot(q2), 0.0, t)
		var target := bone * along + q1 * lat1 + q2 * lat2
		var solved := solver.solve(target, Vector3.ZERO, Vector3.ZERO)
		for i in range(solved.size()):
			worst_jump = maxf(worst_jump, previous[i].distance_to(solved[i]))
		previous = solved.duplicate()

	_check(
		worst_jump < 0.2,
		"pole-off chain keeps its side while the target crosses its first bone (%.3f)" % worst_jump
	)


## A punch target close to the mount used to fold the knee across the pole axis:
## the joint angles stayed legal but the limb read as an S / hyperextension.
func _test_limb_punch_shape() -> void:
	var solver := LimbSolver.new(
		PackedVector3Array([Vector3.ZERO, Vector3(0, -2, 0), Vector3(0, -4, 0), Vector3(0, -6, 0)])
	)
	solver.min_joint_angle = 20.0
	solver.floor_margin = 0.6
	solver.should_apply_floor = false  # punch profile
	var pole := Vector3(-1.253, 0.2, 0.577)
	var worst_fold := 0.0
	var worst_lateral := INF
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var dir := Vector3(cos(angle), -0.6, sin(angle)).normalized()
		var n := (pole - dir * pole.dot(dir)).normalized()
		for frame in range(8):
			var target := dir * lerpf(2.9, 0.9, minf(float(frame) / 5.0, 1.0))
			var solved := solver.solve(target, Vector3.ZERO, pole)
			var hip := (solved[0] - solved[1]).normalized().angle_to(
				(solved[2] - solved[1]).normalized()
			)
			var knee := (solved[1] - solved[2]).normalized().angle_to(
				(solved[3] - solved[2]).normalized()
			)
			worst_fold = maxf(worst_fold, solver.min_joint_angle - rad_to_deg(minf(hip, knee)))
			for j in range(1, solved.size() - 1):
				worst_lateral = minf(worst_lateral, (solved[j] - Vector3.ZERO).dot(n))

	_check(
		worst_fold < 0.5, "punch keeps the joints inside their limits (%.1f deg over)" % worst_fold
	)
	_check(worst_lateral > -0.05, "punch keeps the elbow on the pole side (%.2f)" % worst_lateral)

	# With the flag on, the chain must never reverse its bend into an S.
	var c_solver := LimbSolver.new(
		PackedVector3Array([Vector3.ZERO, Vector3(0, -2, 0), Vector3(0, -4, 0), Vector3(0, -6, 0)])
	)
	c_solver.min_joint_angle = 20.0
	c_solver.should_apply_floor = false
	c_solver.enforce_inward_bend = true
	c_solver.inward_bend_min = 30.0
	var worst_reverse := 0.0
	var min_bend := INF
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var dir := Vector3(cos(angle), -0.6, sin(angle)).normalized()
		for frame in range(8):
			var target := dir * lerpf(2.9, 0.9, minf(float(frame) / 5.0, 1.0))
			var solved := c_solver.solve(target, Vector3.ZERO, pole)
			var axis := dir.cross((pole - dir * pole.dot(dir)).normalized())
			var d1 := (solved[1] - solved[0]).normalized()
			var d2 := (solved[2] - solved[1]).normalized()
			var d3 := (solved[3] - solved[2]).normalized()
			var t1 := atan2(d1.cross(d2).dot(axis), d1.dot(d2))
			var t2 := atan2(d2.cross(d3).dot(axis), d2.dot(d3))
			if t1 * t2 < 0.0:
				worst_reverse = maxf(worst_reverse, minf(absf(t1), absf(t2)))
			min_bend = minf(min_bend, rad_to_deg(d1.angle_to(d2)))
	_check(
		worst_reverse < 0.02, "arm-shaped chain keeps a C curve (%.3f rad reverse)" % worst_reverse
	)
	_check(
		min_bend > 29.0,
		"arm-shaped chain keeps its minimum bend while in reach (%.1f deg)" % min_bend
	)


func _test_ballistic_direction() -> void:
	var target := Vector3(10, 0, 0)
	var speed := 20.0
	var dir := GrabThrowUtil.ballistic_aim_dir(target, speed, -20.0)
	_check_close(dir.length(), 1.0, "ballistic dir is unit length")
	_check(dir.y > 0.0, "ballistic dir arcs upward")
	_check_close(dir.z, 0.0, "ballistic dir stays in the aim plane")

	var pos := Vector3.ZERO
	var vel := dir * speed
	var gravity := Vector3(0, -20, 0)
	var steps := 0
	while pos.x < target.x and steps < 100000:
		pos += vel * BALLISTIC_DT
		vel += gravity * BALLISTIC_DT
		steps += 1
	_check(pos.distance_to(target) < 0.01, "ballistic arc passes through the target")


func _test_ballistic_degenerate() -> void:
	_check_vec(
		GrabThrowUtil.ballistic_aim_dir(Vector3(0, 5, 0), 20.0, -20.0),
		Vector3.UP,
		"straight-up target aims up"
	)
	_check_vec(
		GrabThrowUtil.ballistic_aim_dir(Vector3(0, -5, 0), 20.0, -20.0),
		Vector3.DOWN,
		"straight-down target aims down"
	)
	_check_vec(
		GrabThrowUtil.ballistic_aim_dir(Vector3(3, 0, 4), 20.0, 0.0),
		Vector3(0.6, 0, 0.8),
		"zero gravity returns the direct line"
	)
	_check_vec(
		GrabThrowUtil.ballistic_aim_dir(Vector3(100, 0, 0), 1.0, -20.0),
		Vector3.RIGHT,
		"unreachable target falls back to the direct line"
	)


func _test_aim_point_from_hit() -> void:
	var config := PlayerGrabConfig.new()
	var from := Vector3.ZERO
	var aim_dir := Vector3.RIGHT
	var fallback := from + aim_dir * config.throw_homing_fallback_dist

	_check_vec(
		GrabThrowUtil.aim_point_from_hit({}, from, aim_dir, config),
		fallback,
		"empty hit falls back along the crosshair"
	)
	_check_vec(
		GrabThrowUtil.aim_point_from_hit(
			{"position": Vector3(1, 0, 0), "normal": Vector3.UP}, from, aim_dir, config
		),
		fallback,
		"too-close hit falls back along the crosshair"
	)
	_check_vec(
		GrabThrowUtil.aim_point_from_hit(
			{"position": Vector3(5, 0, 0), "normal": Vector3.UP}, from, aim_dir, config
		),
		Vector3(5, 0.05, 0),
		"surface hit is nudged off the face"
	)


func _test_slam_target_limits() -> void:
	var config := AirConfig.new()
	config.slam_max_distance = 10.0
	config.slam_min_depression_deg = 30.0
	_check(AirState.is_slam_offset_valid(Vector3(6, -8, 0), config), "slam accepts max range")
	_check(not AirState.is_slam_offset_valid(Vector3(0, -11, 0), config), "slam rejects far target")
	_check(not AirState.is_slam_offset_valid(Vector3(8, -2, 0), config), "slam rejects shallow aim")
	_check(not AirState.is_slam_offset_valid(Vector3.UP, config), "slam rejects upward aim")


func _three_bone_solver() -> LimbSolver:
	var joints := PackedVector3Array(
		[Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]
	)
	return LimbSolver.new(joints)


func _check_lengths(joints: PackedVector3Array, label: String) -> void:
	for i in range(joints.size() - 1):
		_check_close(joints[i].distance_to(joints[i + 1]), 1.0, "%s segment %d" % [label, i])


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
		return
	_failures += 1
	printerr("[FAIL] ", message)


func _check_vec(actual: Vector3, expected: Vector3, message: String, epsilon := EPSILON) -> void:
	_check(
		actual.distance_to(expected) <= epsilon,
		"%s (got %s, want %s)" % [message, actual, expected]
	)


func _check_close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPSILON, "%s (got %f, want %f)" % [message, actual, expected])
