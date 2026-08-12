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

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

enum PlayerState { GROUNDED, WALL_CLIMB }
var state: PlayerState = PlayerState.GROUNDED

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
	elif state == PlayerState.WALL_CLIMB:
		velocity = Vector3.ZERO
		update_wall_arms(dt)

		var valid_normals := 0
		var average_normal := Vector3.ZERO
		for mount in arm_mounts:
			if mount.wall_surface_normal != Vector3.ZERO:
				average_normal += mount.wall_surface_normal
				valid_normals += 1


		if valid_normals > 0:
			average_normal /= valid_normals

			#cross the normal with the right vector to get the up vector
			var up_vector := (Vector3.UP - average_normal * average_normal.dot(Vector3.UP)).normalized()
			var right_vector := up_vector.cross(average_normal)

			var direction := up_vector * -input_dir.y + right_vector * input_dir.x
			if direction.length_squared() > 0.0:
				direction = direction.normalized()
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
				velocity.y = direction.y * speed
			else:
				velocity.x = move_toward(velocity.x, 0, speed * dt)
				velocity.z = move_toward(velocity.z, 0, speed * dt)
				velocity.y = move_toward(velocity.y, 0, speed * dt)

	move_and_slide()

func _update_arms(dt: float) -> void:
	var grounded_legs := _number_of_grounded_legs()
	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	for mount in arm_mounts:
		mount.update_step(velocity, dt)
		if mount.can_step(grounded_legs):
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)

	try_mount_wall()

func try_mount_wall() -> void:
	if state != PlayerState.GROUNDED:
		return

	var wall_detection_count = 0
	var wall_hits := {}

	for mount in arm_mounts:
		# wall raycasts
		if not mount.is_leg and mount.wall_target != null and mount.arm.is_stepping == false:
			var hit = mount.get_wall_hit_pos()
			wall_hits[mount] = hit

			if hit != null:
				wall_detection_count += 1

	if wall_detection_count > 1:
		_set_state(PlayerState.WALL_CLIMB)
		for mount in arm_mounts:
			if mount.is_leg or mount.arm.is_stepping:
				continue

			var hit = wall_hits[mount]
			if hit != null:
				var hit_pos = hit as Vector3
				mount.arm.start_step(hit_pos)


func update_wall_arms(dt: float) -> void:
	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	for mount in arm_mounts:
		if mount.arm.is_stepping:
			mount.arm.advance_step(dt)
			continue

		mount.update_wall_climb(velocity)
		if mount.step_target != null:
			var current_pos = mount.target.global_position

			var dist = (current_pos - mount.step_target).length()
			if dist > furthest_distance and dist >= mount.raycast_config.max_target_displacement:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)

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

func _number_of_grounded_legs() -> int:
	var grounded_legs = 0
	for arm in arms:
		if arm.is_grounded():
			grounded_legs += 1
	return grounded_legs
