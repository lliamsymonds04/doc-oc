extends CharacterBody3D


@export var speed = 5.0
@export var jump_velocity = 4.5
@export var arm_mounts: Array[ArmMount] = []

@export_category("Hover")
@export var hover_speed = 3.0
@export var min_y_offset = 2.5
@export var max_y_offset = 4.0
@export var min_height_change_look_threshold = 10.0
@export var height_change_rate = 1.0
@export var neutral_pitch = -5.0

@export_category("Raycast")
@export var raycast_distance: float = 10.0
@export var max_target_displacement: float = 2.0
@export var anchor_lead_time: float = 0.4
@export var wall_raycast_distance: float = 2.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

var body_y_offset = (min_y_offset + max_y_offset)/2.0

func _ready() -> void:
	for mount in arm_mounts:
		var arm = mount.init()
		arms.append(arm)

func _physics_process(dt: float) -> void:
	# Transfer the camera's horizontal rotation to the player. The spring arm is
	# a child of the player, so clear its local yaw afterward to avoid compounding
	# the rotation every frame. Its pitch remains independent for camera aiming.
	rotation.y = spring_arm.global_rotation.y
	spring_arm.rotation.y = 0.0

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * dt

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("left", "right", "forward", "back")

	# rotation.y is in radians, and sin()/cos() expect radians.
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

	move_and_slide()

func _update_arms(dt: float) -> void:
	var grounded_legs := _number_of_grounded_legs()
	var best_arm: BasicArm = null
	var furthest_distance := 0.0
	var best_arm_hit_pos := Vector3.ZERO

	var wall_detection_count := 0

	for mount in arm_mounts:
		mount.update_step(velocity, dt)
		if mount.can_step(grounded_legs):
			var dist = mount.get_step_distance()
			if dist > furthest_distance:
				furthest_distance = dist
				best_arm = mount.arm
				best_arm_hit_pos = mount.step_target

		# wall raycasts
		if mount.wall_target != null and mount.arm.is_stepping == false:
			var wall_target_pos := mount.wall_target.global_position
			var cast_dir := -global_transform.basis.z
			var hit = mount.get_surface_hit(wall_target_pos, cast_dir, wall_raycast_distance)

			if hit != null:
				wall_detection_count += 1

	if best_arm != null:
		best_arm.start_step(best_arm_hit_pos)

	if wall_detection_count > 1:
		print("wall time")

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
