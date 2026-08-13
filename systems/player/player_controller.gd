extends CharacterBody3D


@export var speed = 5.0
@export var jump_velocity = 4.5
@export var arm_mounts: Array[ArmMount] = []
@export var raycast_config: ArmRaycastConfig

@export_category("Hover")
@export var hover_speed = 3.0
@export var min_y_offset = 2.5
@export var max_y_offset = 4.0
@export var min_height_change_look_threshold = 10.0
@export var height_change_rate = 1.0
@export var neutral_pitch = -5.0

@export_category("Wall Climb")
@export var wall_offset: float = 1.0
@export var wall_raycast_dist: float = 5.0
@export var ledge_ray_offset: float = 3.0
@export var ledge_ray_length: float = 5.0
@export var wall_climb_debounce_time: float = 0.5

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

enum PlayerState { GROUNDED, WALL_CLIMB }
var state: PlayerState = PlayerState.GROUNDED
var wall_climb_debounce: float = 0.0

var body_y_offset = (min_y_offset + max_y_offset)/2.0

func _ready() -> void:
	for mount in arm_mounts:
		mount.raycast_config = raycast_config
		var arm = mount.init()
		arms.append(arm)

func _set_state(new_state: PlayerState) -> void:
	if new_state == self.state:
		return
	state = new_state

func _physics_process(dt: float) -> void:
	var input_dir := Input.get_vector("left", "right", "forward", "back")

	if state == PlayerState.GROUNDED:
		rotation.y = spring_arm.global_rotation.y
		spring_arm.rotation.y = 0.0

		# Add the gravity.
		if not is_on_floor():
			velocity += get_gravity() * dt


		var cam_yaw := rotation.y
		var forward := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))

		# input_dir.y is -1 when pressing forward (W), so negate it to move along
		# the camera's forward vector. Normalizing keeps diagonal speed consistent.
		var direction := forward * -input_dir.y + right * input_dir.x
		if direction.length_squared() > 0.0:
			direction = direction.normalized()
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed * dt)
			velocity.z = move_toward(velocity.z, 0, speed * dt)

		_update_body_y_offset(dt)
		_update_arms(dt)

		if wall_climb_debounce > 0.0:
			wall_climb_debounce -= dt

	elif state == PlayerState.WALL_CLIMB:

		var valid_normals := 0
		var average_normal := Vector3.ZERO
		for mount in arm_mounts:
			if mount.wall_surface_normal != Vector3.ZERO:
				average_normal += mount.wall_surface_normal
				valid_normals += 1


		if valid_normals > 0:
			average_normal /= valid_normals

			var up_vector := (Vector3.UP - average_normal * average_normal.dot(Vector3.UP)).normalized()
			var right_vector := up_vector.cross(average_normal)

			var direction := up_vector * -input_dir.y + right_vector * input_dir.x
			if direction.length_squared() > 0.0:
				velocity = direction.normalized() * speed
			else:
				velocity.x = move_toward(velocity.x, 0, speed * dt)
				velocity.z = move_toward(velocity.z, 0, speed * dt)
				velocity.y = move_toward(velocity.y, 0, speed * dt)
		else:
			velocity = Vector3.ZERO

		# wall offset logic
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(position, position + -average_normal * wall_offset * wall_raycast_dist, ~2)

		var result := space.intersect_ray(query)
		if not result.is_empty():
			var hit_pos := result["position"] as Vector3
			var distance_from_wall := (hit_pos - position).length()
			var distance_error := distance_from_wall - wall_offset

			var target_normal_vel: Vector3 = -average_normal * distance_error * hover_speed
			var normal_comp := average_normal * velocity.dot(average_normal)
			velocity += (target_normal_vel - normal_comp) * minf(1.0, dt * hover_speed)

		update_wall_arms(dt)

		var ledge_result = _detect_ledge(average_normal)
		if ledge_result != null:
			_dismount_to_ledge(ledge_result)

	move_and_slide()

func _update_arms(dt: float) -> void:
	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	for mount in arm_mounts:
		mount.update_step(velocity, dt)
		if mount.can_step():
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)

	try_mount_wall()

func try_mount_wall() -> void:
	if state != PlayerState.GROUNDED or wall_climb_debounce > 0.0:
		return

	var wall_detection_count = 0
	var wall_hits := {}

	for mount in arm_mounts:
		# wall raycasts
		if not mount.is_leg and mount.wall_target != null and mount.arm.is_stepping == false:
			var hit = mount.get_wall_hit_pos(Vector3.ZERO)
			wall_hits[mount] = hit

			if hit != null:
				wall_detection_count += 1

	if wall_detection_count > 1:
		_set_state(PlayerState.WALL_CLIMB)
		wall_climb_debounce = wall_climb_debounce_time
		for mount in arm_mounts:
			if mount.is_leg or mount.arm.is_stepping:
				continue

			mount.set_apply_floor(false)
			var hit = wall_hits[mount]
			if hit != null:
				mount.arm.start_step(hit.position)
				mount.wall_surface_normal = hit.normal


func update_wall_arms(dt: float) -> void:
	var best_mount: ArmMount = null
	var furthest_distance := 0.0
	var best_hit = null

	for mount in arm_mounts:
		if mount.arm.is_stepping:
			mount.arm.advance_step(dt)
			continue

		var hit = mount.update_wall_climb(velocity)
		var diagonal_grounded = mount.vertical_mount.arm.is_grounded() and mount.horizontal_mount.arm.is_grounded()
		var can_step = diagonal_grounded or mount.arm.is_fully_extended()
		if mount.step_target != null and can_step:
			var current_pos = mount.target.global_position

			var dist = (current_pos - mount.step_target).length()
			if dist > furthest_distance and dist >= mount.raycast_config.max_target_displacement:
				furthest_distance = dist
				best_mount = mount
				best_hit = hit

	if best_mount != null:
		best_mount.arm.start_step(best_mount.step_target)
		best_mount.wall_surface_normal = best_hit.normal

func _detect_ledge(wall_normal: Vector3) -> Variant:
	if wall_normal == Vector3.ZERO:
		return null

	var space := get_world_3d().direct_space_state
	var start := position + Vector3.UP * ledge_ray_offset
	var end := start - wall_normal * ledge_ray_length + Vector3.DOWN * ledge_ray_offset * 0.5
	var query := PhysicsRayQueryParameters3D.create(start, end, ~2)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	if (result["normal"] as Vector3).y < 0.5:
		return null

	return result

func _dismount_to_ledge(ledge_result: Dictionary) -> void:
	if state != PlayerState.WALL_CLIMB:
		return

	_set_state(PlayerState.GROUNDED)

	for mount in arm_mounts:
		mount.wall_surface_normal = Vector3.ZERO
		mount.set_apply_floor(true)

	var ledge_pos := ledge_result["position"] as Vector3
	var right := global_transform.basis.x
	var step_count := 0

	for mount in arm_mounts:
		if not mount.is_leg:
			if mount.idle_target:
				mount.arm.start_step(mount.to_global(mount.compute_idle_target()), 0.2)
			continue

		var foot_pos := ledge_pos + right * mount.anchor.position.x
		var surface = mount._get_surface_hit(foot_pos, Vector3.DOWN, raycast_config.step_raycast_distance)
		if surface != null:
			foot_pos = (surface["position"] as Vector3)

		if step_count > 0:
			mount.arm.start_step(foot_pos, 0.2 * step_count)
		else:
			mount.arm.start_step(foot_pos)

		step_count += 1

func _calculate_average_target_y() -> Variant:
	var total_y = 0
	var grounded_legs = 0

	for arm in arms:
		if not arm.is_grounded():
			continue

		total_y += arm.target_node.global_position.y
		grounded_legs += 1

	if grounded_legs == 0:
		return null

	return total_y / grounded_legs

func _update_body_y_offset(dt:float) -> void:
	#calculate camera pitch
	var camera_pitch = spring_arm.rotation_degrees.x
	var effective_pitch = camera_pitch - neutral_pitch
	if abs(effective_pitch) > min_height_change_look_threshold:
		var goal_y_offset = max_y_offset if effective_pitch > 0 else min_y_offset
		body_y_offset = lerp(body_y_offset, goal_y_offset, dt * height_change_rate)

	var average_y = _calculate_average_target_y()
	if average_y == null:
		return

	var goal_y = average_y + body_y_offset
	var current_y = global_position.y
	var height_error = goal_y - current_y
	var target_y_vel = height_error * hover_speed
	velocity.y = lerp(velocity.y, target_y_vel, dt*hover_speed)
