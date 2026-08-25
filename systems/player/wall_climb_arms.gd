class_name WallClimbArms
extends RefCounted

enum CorneringType {
	NONE,
	INSIDE,
	OUTSIDE,
}

const CORNERING_DURATIONS: Dictionary = {
	CorneringType.INSIDE: 1.0,
	CorneringType.OUTSIDE: 0.7,
}

var player: PlayerController

# cornering machinery — owned here so selection and effects stay together
var wall_normal: Vector3 = Vector3.ZERO
var is_cornering: bool = false
var cornering_timer: float = 0.0
var cornering_target_normal: Vector3 = Vector3.ZERO
var cornering_target_pos: Vector3 = Vector3.ZERO
var debounces: Dictionary = {}


func _init(p: PlayerController) -> void:
	player = p
	for mount in player.arm_mounts:
		debounces[mount] = 0

func reset() -> void:
	is_cornering = false
	cornering_timer = 0.0
	cornering_target_normal = Vector3.ZERO
	cornering_target_pos = Vector3.ZERO
	for mount in player.arm_mounts:
		debounces[mount] = 0

# cornering re-trigger countdown
func tick(dt: float) -> void:
	for mount in debounces:
		if debounces[mount] > 0:
			debounces[mount] -= dt

# lerp toward the cornering target and travel to it; also keeps the facing normal
func update_cornering(dt: float) -> void:
	var p := player

	cornering_timer -= dt
	if cornering_timer <= 0:
		is_cornering = false

	var remaining := maxf(cornering_timer, dt)
	var weight := dt / remaining

	# lerp the y rotation to the cornering target
	var goal_yaw := atan2(-cornering_target_normal.x, -cornering_target_normal.z)
	p.rotation.y = lerp_angle(p.rotation.y, goal_yaw, weight)

	# move the player towards the cornering target
	var direction := cornering_target_pos - p.position
	if direction.length_squared() > 0.0:
		p.velocity = direction / remaining
	else:
		p.velocity = Vector3.ZERO

	wall_normal = p.basis.z

# advance stepping arms and pick the best arm step for this frame
func update_arms(dt: float, input_dir: Vector2, average_normal: Vector3) -> void:
	var p := player

	# best candidate this frame — kept local to the selection pass
	var best_mount: ArmMount = null
	var best_hit = null
	var best_dist := 0.0
	var cornering_mode: CorneringType = CorneringType.NONE

	var right := wall_basis(wall_normal).x

	for mount in p.arm_mounts:
		var hit = mount.update_wall_climb(p.velocity)

		if mount.arm.is_stepping:
			mount.arm.advance_step(dt)
			mount.target_world = mount.arm.target_world
			continue

		if not _can_step(mount):
			continue

		var side_dir := (right * input_dir.x).normalized()
		var can_corner: bool = debounces[mount] <= 0 \
			and (mount.wall_probe.global_position - p.global_position).dot(side_dir) > 0

		# inside corner: cast sideways toward the adjoining surface
		if can_corner:
			var cand = _try_inside_corner(mount, side_dir, best_dist)
			if cand != null:
				best_mount = cand.mount
				best_hit = cand.hit
				best_dist = cand.dist
				cornering_mode = cand.mode
				continue

		if mount.step_target != null:
			var cand = _pick(mount, hit, mount.raycast_config.max_target_displacement, CorneringType.NONE, best_dist)
			if cand != null:
				best_mount = cand.mount
				best_hit = cand.hit
				best_dist = cand.dist
				cornering_mode = cand.mode
		elif can_corner:
			# outside corner: cast around the wall's edge
			var cand = _try_outside_corner(mount, side_dir, average_normal, best_dist)
			if cand != null:
				best_mount = cand.mount
				best_hit = cand.hit
				best_dist = cand.dist
				cornering_mode = cand.mode

	if best_mount != null:
		_commit_step(best_mount, best_hit, cornering_mode)

func _can_step(mount: ArmMount) -> bool:
	var horizontal_grounded = mount.horizontal_mount.arm.is_grounded()
	var diagonal_grounded = mount.vertical_mount.arm.is_grounded() and horizontal_grounded
	return diagonal_grounded or mount.arm.is_fully_extended()

# build a winning candidate dict {mount, hit, mode, dist} when it beats best_dist
func _pick(mount: ArmMount, hit, min_dist: float, mode: CorneringType, best_dist: float):
	if mount.step_target == null:
		return null
	var dist: float = (mount.target_world - mount.step_target).length()
	if dist > best_dist and dist >= min_dist:
		return {"mount": mount, "hit": hit, "mode": mode, "dist": dist}
	return null

func _try_inside_corner(mount: ArmMount, side_dir: Vector3, best_dist: float):
	var p := player
	var ray_end: Vector3 = mount.wall_probe.global_position + side_dir * p.raycast_config.wall_inside_cornering_raycast_distance
	var motion := ray_end - mount.global_position
	var side_result = mount.get_surface_hit(mount.global_position, motion.normalized(), motion.length())
	if not side_result:
		return null

	var new_normal: Vector3 = side_result["normal"]
	var current_normal: Vector3 = mount.wall_surface_normal
	# only use surfaces angled differently from the current one
	if new_normal.dot(current_normal) >= 0.3:
		return null

	# set the target even if this candidate loses — the normal-step fallthrough
	# below reads mount.step_target, so a rejected corner becomes a plain step
	mount.step_target = side_result["position"]
	return _pick(mount, side_result, 0.5, CorneringType.INSIDE, best_dist)

func _try_outside_corner(mount: ArmMount, side_dir: Vector3, average_normal: Vector3, best_dist: float):
	var p := player
	var space := p.get_world_3d().direct_space_state

	var d := 1.0
	var ray_origin := mount.wall_probe.global_position + side_dir * d
	var motion := -side_dir * (d + 2.5) - average_normal * 3.0

	# only cast if the ray origin is actually visible from the mount
	var visible_query := PhysicsRayQueryParameters3D.create(mount.global_position, ray_origin, ~2)
	var visible := space.intersect_ray(visible_query).is_empty()

	var side_result = mount.get_surface_hit(ray_origin, motion.normalized(), motion.length())
	if not visible or not side_result:
		return null

	var hit_normal: Vector3 = side_result["normal"]
	if hit_normal.dot(side_dir) <= 0.4 or wall_normal.dot(hit_normal) >= 0.7:
		return null

	mount.step_target = side_result["position"]
	return _pick(mount, side_result, 0.5, CorneringType.OUTSIDE, best_dist)

func _commit_step(best_mount: ArmMount, best_hit, cornering_mode: CorneringType) -> void:
	var p := player

	if cornering_mode != CorneringType.NONE:
		var debounce_time = CORNERING_DURATIONS[cornering_mode]
		debounces[best_mount] = debounce_time
		if not is_cornering:
			is_cornering = true
			cornering_timer = debounce_time
			cornering_target_normal = -best_hit.normal
			cornering_target_pos = best_mount.step_target + best_hit.normal * p.wall_offset
			cornering_target_pos.y = p.position.y

	best_mount.arm.start_step(best_mount.step_target, 0.0, best_hit.normal)
	best_mount.wall_surface_normal = best_hit.normal

static func wall_basis(normal: Vector3) -> Basis:
	var up := (Vector3.UP - normal * normal.dot(Vector3.UP)).normalized()
	var right := up.cross(normal)
	return Basis(right, up, normal)
