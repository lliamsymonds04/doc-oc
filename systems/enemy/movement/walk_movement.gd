class_name WalkMovement
extends EnemyMovement

## Probe length from the feet, short enough that it can't see a wall from mid-air.
const CLIMB_PROBE_REACH := 0.8
## Upward pop after the wall ends, long enough to clear the lip.
const CLIMB_MOUNT_TIME := 0.15

var _climbing := false
var _climbing_prev := false
var _mount_timer := 0.0


## Climb is decided inside the chase branch, so it has to clear on any frame that
## skips the branch (committed attack, no target, ragdolled).
func apply_vertical(dt: float) -> void:
	_climbing = false
	super(dt)


func desired_velocity(dt: float, dist: float, forward: Vector3) -> Vector3:
	_climbing = (
		enemy.is_on_wall()
		and absf(enemy.get_wall_normal().y) < enemy.config.climb_max_normal_y
		and _wall_ahead_of_feet(forward)
	)

	# the mount pop carries the body over the lip even inside stop_distance
	if _mount_timer > 0.0:
		return forward * enemy.config.move_speed
	return super(dt, dist, forward)


func before_slide(dt: float) -> void:
	if _climbing_prev and not _climbing:
		_mount_timer = CLIMB_MOUNT_TIME
	_climbing_prev = _climbing

	if _climbing or _mount_timer > 0.0:
		enemy.velocity.y = enemy.config.climb_speed
	_mount_timer = maxf(_mount_timer - dt, 0.0)


func _wall_ahead_of_feet(forward: Vector3) -> bool:
	var from := enemy.global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * CLIMB_PROBE_REACH, 1)
	return not enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
