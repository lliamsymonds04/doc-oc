extends CharacterBody3D


@export var speed = 5.0
@export var jump_velocity = 4.5
@export var arm_mounts: Array[Node3D] = []
@export var arm_scene: PackedScene

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

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

		target.top_level = true

		var arm := arm_scene.instantiate() as BasicArm
		arm.target_node = target
		arm.position = Vector3.ZERO
		arm.target = target.position
		arm.pole = pole
		mount.add_child(arm)
		arms.append(arm)

func _physics_process(delta: float) -> void:
	# Transfer the camera's horizontal rotation to the player. The spring arm is
	# a child of the player, so clear its local yaw afterward to avoid compounding
	# the rotation every frame. Its pitch remains independent for camera aiming.
	rotation.y = spring_arm.global_rotation.y
	spring_arm.rotation.y = 0.0

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

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
		velocity.x = move_toward(velocity.x, 0, speed * delta)
		velocity.z = move_toward(velocity.z, 0, speed * delta)

	move_and_slide()
	update_arms(delta)

func update_arms(delta: float) -> void:
	for arm in arms:
		arm.target = arm.to_local(arm.target_node.global_position)
