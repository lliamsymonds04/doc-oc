extends RefCounted
class_name PlayerGrabController

var player: PlayerController
var last_attack_time: float = -INF
const HOLD_OFFSET := Vector3(0.6, 1.2, -0.8)

var mounts_grabbed_bodies: Dictionary = {}
var grab_offsets: Dictionary = {}

func _init(p: PlayerController) -> void:
	player = p

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected.bind(mount))

func try_grab(side_dir: int) -> void:
	var now = _get_now()
	if now - last_attack_time < 0.5:
		return

	var p := player
	if p.is_sprinting():
		return

	var mount := _get_mount_for_side(side_dir)
	if mount == null or is_mount_grabbing(mount):
		return

	var target = _get_target(side_dir)  # same aim-point math as attack
	mount.arm.start_punch(target)
	last_attack_time = now

func physics_update() -> void:
	for mount in mounts_grabbed_bodies.keys():
		if not is_mount_grabbing(mount):
			continue
		if not mount in grab_offsets:
			continue
		var body: RigidBody3D = mounts_grabbed_bodies[mount]
		var offset: Vector3 = grab_offsets[mount]

		var grip_world: Vector3 = body.to_global(offset)
		var side_dir: int = sign(mount.position.x)
		var hold_offset := Vector3(HOLD_OFFSET.x * side_dir, HOLD_OFFSET.y, HOLD_OFFSET.z)
		var anchor: Vector3 = mount.to_global(hold_offset)

		mount.set_target(grip_world)
		mount.set_apply_floor(false)

		# velocity magnet
		var error := anchor - grip_world
		body.linear_velocity = error * 15

func _get_target(side_dir: int = 0) -> Vector3:
	var p := player
	var attack_offset = p.camera_controller.global_transform.basis.x * side_dir * p.attack_config.attack_side_offset

	var cam_hit := p.camera_controller.get_camera_center_hit(15, attack_offset)
	if cam_hit.is_empty():
		var cam_pos = p.camera_controller.cam.global_position
		var cam_dir = p.camera_controller.get_camera_direction()
		return cam_pos + cam_dir * 15
	else:
		return cam_hit["position"] + attack_offset

func _get_mount_for_side(side_dir: int) -> ArmMount:
	for mount in player.arm_mounts:
		if sign(mount.position.x) == side_dir:
			return mount
	return null


func arm_hit_detected(hit: Vector3, normal: Vector3, collider: Object, mount: ArmMount) -> void:
	if not player.is_in_grab_mode:
		return

	if not collider is RigidBody3D:
		return

	if mounts_grabbed_bodies.has(mount):
		return

	var body = collider as RigidBody3D
	grab_offsets[mount] = body.to_local(hit)
	mounts_grabbed_bodies[mount] = body
	print("hit")

func is_mount_grabbing(mount: ArmMount) -> bool:
	return mounts_grabbed_bodies.has(mount)

func is_grabbing() -> bool:
	return not mounts_grabbed_bodies.is_empty()

func _get_now() -> float:
	return Time.get_ticks_msec() / 1000.0
