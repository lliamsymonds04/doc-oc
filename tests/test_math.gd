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
	_test_fabrik_reach()
	_test_fabrik_stretch()
	_test_fabrik_stability()
	_test_ballistic_direction()
	_test_ballistic_degenerate()
	_test_aim_point_from_hit()

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


func _test_fabrik_reach() -> void:
	var solver := _two_bone_solver()
	var solved := solver.solve(Vector3(1, 0, 0), Vector3.ZERO, Vector3.UP)
	# solve() stops inside solver.tolerance, so that is the accuracy contract
	_check_vec(
		solved[solved.size() - 1],
		Vector3(1, 0, 0),
		"FABRIK reaches an in-range target",
		solver.tolerance
	)
	_check_lengths(solved, "FABRIK preserves segment lengths (reach)")


func _test_fabrik_stretch() -> void:
	var solver := _two_bone_solver()
	var solved := solver.solve(Vector3(5, 0, 0), Vector3.ZERO, Vector3.UP)
	_check_vec(
		solved[solved.size() - 1],
		Vector3(2, 0, 0),
		"FABRIK caps an out-of-reach target at extension"
	)
	_check_lengths(solved, "FABRIK preserves segment lengths (stretch)")


## A folded chain (target well inside its reach) with joint limits, a pole and a
## floor is over-constrained: the solver used to leave the pose mid-constraint,
## so the next frame started somewhere else and the arm swung around.
func _test_fabrik_stability() -> void:
	var solver := FabrikSolver.new(
		PackedVector3Array([Vector3.ZERO, Vector3(0, -2, 0), Vector3(0, -4, 0), Vector3(0, -6, 0)])
	)
	solver.min_joint_angle = 20.0
	solver.floor_margin = 0.6
	solver.hinge_axes.append(Vector3.RIGHT)
	solver.hinge_axes.append(Vector3.RIGHT)

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


func _two_bone_solver() -> FabrikSolver:
	var joints := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)])
	return FabrikSolver.new(joints)


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
