class_name WalkMovement
extends EnemyMovement

const CLIMB_PROBE_REACH := 1.5
const CLIMB_MOUNT_TIME := 0.4
const MIN_CLIMB_HEIGHT := 1.0

var _wall := RID()
var _climb_direction := Vector3.ZERO
var _mount_timer := 0.0


func climb_target(target: PlayerController) -> Dictionary:
	var height := target.global_position.y - enemy.global_position.y
	var from := target.global_position + Vector3.UP * 0.2
	if target.is_wall_climbing() and (height >= MIN_CLIMB_HEIGHT or _wall.is_valid()):
		var reach := target.wall_climb.wall_offset * target.wall_climb.wall_raycast_dist
		var wall := _ray(from, from - target.global_basis.z * reach)
		if _is_wall(wall):
			return wall

	if height < MIN_CLIMB_HEIGHT:
		return {}

	var surface := _ray(from, from - Vector3.UP * 2.0)
	if not surface.is_empty():
		var point: Vector3 = surface["position"]
		if point.y > enemy.global_position.y + MIN_CLIMB_HEIGHT:
			return surface

	return {}


func climb(heading: Vector3, wall: RID, target: PlayerController, dt: float) -> bool:
	if _mount_timer > 0.0:
		_mount_timer = maxf(_mount_timer - dt, 0.0)
		enemy.velocity.y = enemy.config.climb_speed
		return true

	if not wall.is_valid() and not _wall.is_valid():
		return false

	var hit := _probe_wall(_climb_direction if _wall.is_valid() else heading)
	if _is_wall(hit) and (hit["rid"] == wall or hit["rid"] == _wall):
		_wall = hit["rid"]
		_climb_direction = -hit["normal"]
		_climb_direction.y = 0.0
		_climb_direction = _climb_direction.normalized()
		var speed := enemy.config.climb_speed
		enemy.velocity.y = speed
		if target.is_wall_climbing() and wall == _wall:
			var height := target.global_position.y - enemy.global_position.y
			enemy.velocity.y = clampf(height * 4.0, -speed, speed)
		return true

	if _wall.is_valid():
		_wall = RID()
		_mount_timer = CLIMB_MOUNT_TIME
		enemy.velocity.y = enemy.config.climb_speed
		return true

	return false


func climb_direction(wall_heading: Vector3) -> Vector3:
	if not _wall.is_valid():
		return _climb_direction

	var sideways := wall_heading.slide(_climb_direction).limit_length()
	return (_climb_direction + sideways).normalized()


func hold_wall() -> void:
	if _wall.is_valid() and not enemy.is_on_floor():
		var hit := _probe_wall(_climb_direction)
		if _is_wall(hit) and hit["rid"] == _wall:
			enemy.velocity.y = 0.0
			return

	cancel_climb()


func cancel_climb() -> void:
	_wall = RID()
	_mount_timer = 0.0


func _probe_wall(heading: Vector3) -> Dictionary:
	var from := enemy.global_position + Vector3.UP * 0.1
	return _ray(from, from + heading * CLIMB_PROBE_REACH)


func _is_wall(hit: Dictionary) -> bool:
	return not hit.is_empty() and absf(hit["normal"].y) < enemy.config.climb_max_normal_y


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return enemy.get_world_3d().direct_space_state.intersect_ray(query)
