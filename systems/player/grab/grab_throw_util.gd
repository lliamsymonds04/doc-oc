class_name GrabThrowUtil
extends RefCounted


static func apply_throw(
	body: RigidBody3D, throw_speed: float, flat_basis: Basis, config: PlayerGrabConfig
) -> void:
	var throw_dir := -flat_basis.z

	body.linear_velocity.y = 0.0
	body.linear_velocity += throw_dir * throw_speed
	body.linear_velocity.y += maxf(
		config.throw_release_velocity_y - throw_speed * config.throw_y_z_dropoff,
		config.throw_release_velocity_y_min
	)
	apply_spin(body, config)


static func apply_spin(body: RigidBody3D, config: PlayerGrabConfig) -> void:
	var vel := body.linear_velocity
	if vel.length() < 0.1:
		return
	var dir := vel.normalized()
	# looking_at needs an up vector not parallel to the direction;
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	body.angular_velocity = basis.x * (vel.length() * config.release_spin_sens)


## Enemy closest to the aim axis inside the crosshair cone, or null.
static func find_homing_target(
	enemies: Array[Node],
	from: Vector3,
	aim_dir: Vector3,
	exclude: Array[Object],
	config: PlayerGrabConfig
) -> Node3D:
	var best_dot := cos(deg_to_rad(config.throw_homing_cone_deg))
	var best: Node3D = null
	for candidate in enemies:
		var enemy := candidate as EnemyController
		if enemy == null or not enemy.is_inside_tree():
			continue

		var target: Node3D = enemy
		if enemy.is_ragdolled():
			target = enemy.get_ragdoll()

		if exclude.has(target):
			continue
		var to_target := target.global_position - from
		var dist := to_target.length()
		if dist < 0.001 or dist > config.throw_homing_range:
			continue
		var dot := (to_target / dist).dot(aim_dir)
		if dot > best_dot:
			best_dot = dot
			best = target

	return best


## Unit velocity direction whose ballistic arc passes through `to` at `speed`, or
## the direct line of sight when the target is out of reach at that speed.
static func ballistic_aim_dir(to: Vector3, speed: float, gravity_y: float) -> Vector3:
	var g := -gravity_y
	if g <= 0.0:
		return to.normalized()
	var flat := Vector2(to.x, to.z)
	var d := flat.length()
	if d < 0.001:
		return Vector3.UP if to.y > 0.0 else Vector3.DOWN
	var s2 := speed * speed
	# the lower of the two roots: flat arc rather than a lob
	var disc := s2 * s2 - g * (g * d * d + 2.0 * to.y * s2)
	if disc < 0.0:
		return to.normalized()  # faster than any arc can reach; best effort
	var dir_flat := Vector3(flat.x / d, 0.0, flat.y / d)
	return (dir_flat + Vector3.UP * ((s2 - sqrt(disc)) / (g * d))).normalized()


## Fallback to the crosshair when there is nothing usable to hit.
static func aim_point_from_hit(
	hit: Dictionary, from: Vector3, aim_dir: Vector3, config: PlayerGrabConfig
) -> Vector3:
	var fallback := from + aim_dir * config.throw_homing_fallback_dist
	if hit.is_empty():
		return fallback
	var hit_pos := hit["position"] as Vector3
	# shape-cast hits carry no distance key, so measure it off the hit point
	if from.distance_to(hit_pos) < config.throw_homing_min_surface_dist:
		return fallback
	# aim just off the face rather than into it
	return hit_pos + (hit["normal"] as Vector3) * 0.05
