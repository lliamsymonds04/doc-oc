extends CharacterBody3D


@export var speed = 5.0
@export var jump_velocity = 4.5
@export var arm_mounts: Array[Node3D] = []

@export_category("Hover")
@export var hover_speed = 3.0
@export var min_y_offset = 2.0
@export var max_y_offset = 4.0
@export var min_height_change_look_threshold = 10.0
@export var height_change_rate = 1.0
@export var neutral_pitch = -5.0

@export_category("Raycast")
@export var raycast_distance: float = 10.0
@export var max_target_displacement: float = 3.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

var body_y_offset = (min_y_offset + max_y_offset)/2.0

func _ready() -> void:
	for mount in arm_mounts:
		var target: Node3D = mount.get_node("Target") as Node3D
		if not target:
			push_warning("%s is missing child 'target'" % mount.name)
			continue

		var pole := mount.get_node("Pole") as Node3D
		if not pole:
			push_warning("%s is missing child 'pole'" % mount.name)
			continue

		var anchor = target.duplicate()
		anchor.name = "anchor"
		mount.add_child(anchor)


		target.top_level = true

		var arm := BasicArm.new()
		arm.target_node = target
		arm.position = Vector3.ZERO
		arm.target = target.position
		arm.anchor = anchor
		arm.pole = pole
		mount.add_child(arm)
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
	for arm in arms:
		var target_pos := arm.target_node.global_position
		var anchor_pos := arm.anchor.global_position
		var desired: Vector3 = target_pos

		if arm.is_stepping:
			arm.advance_step(dt)
			continue

		var hit = _surface_hit(anchor_pos)
		if hit is Vector3:
			var hit_pos := hit as Vector3
			var target_displacement:= hit_pos - target_pos
			if target_displacement.length() > max_target_displacement:
				arm.start_step(hit_pos)

		arm.target = arm.to_local(desired)

func _calculate_average_target_y() -> Variant:
	var total_y = 0
	var grounded_arms = 0

	for arm in arms:
		if not arm.is_grounded():
			continue

		total_y += arm.target_node.global_position.y
		grounded_arms += 1

	if grounded_arms == 0:
		return null

	return total_y / grounded_arms

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


func _surface_hit(from: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	var ray_origin = from + Vector3.UP * raycast_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + Vector3.DOWN * raycast_distance * 2, ~2)

	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	return result["position"]
