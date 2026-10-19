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
