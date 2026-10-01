extends RefCounted
class_name PlayerGrabController

var player: PlayerController
var last_attack_time: float = -INF
const HOLD_OFFSET := Vector3(0.6, 1.2, -0.8)

var grabs: Dictionary = {}  # mount -> body
var grab_offsets: Dictionary = {}
var original_layers: Dictionary = {}  # body -> original collision_layer

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

	# punches can't hit held bodies (cast_mask excludes HELD_LAYER) — join via a held-visible aim ray
	var join_body := _aimed_held_body(15.0)
	if join_body != null:
		_join_grab(mount, join_body)
		last_attack_time = now
		return

	mount.arm.start_punch(target)
	last_attack_time = now

func release_grab(side_dir: int) -> void:
	var mount := _get_mount_for_side(side_dir)
	if mount == null or not is_mount_grabbing(mount):
		return

	var body: RigidBody3D = grabs[mount]
	grabs.erase(mount)
	grab_offsets.erase(mount)
	if not grabs.values().has(body):
		body.collision_layer = original_layers[body]
		original_layers.erase(body)

func physics_update() -> void:
	for mount in grabs.keys():
		if not is_mount_grabbing(mount):
			continue
		if not mount in grab_offsets:
			continue
		var body: RigidBody3D = grabs[mount]
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

func _aimed_held_body(max_dist: float) -> RigidBody3D:
	var from := player.camera_controller.cam.global_position
	var to := from + player.camera_controller.get_camera_direction() * max_dist
	# includes HELD_LAYER, unlike cast_mask
	var params := PhysicsRayQueryParameters3D.create(from, to, ~player.collision_layer)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var collider = hit["collider"]
	return collider if grabs.values().has(collider) else null

## grab_offsets values are body-local; physics_update does body.to_global(offset).
func _join_grab(mount: ArmMount, body: RigidBody3D) -> void:
	var side_dir: int = sign(mount.position.x)
	var hold_offset := Vector3(HOLD_OFFSET.x * side_dir, HOLD_OFFSET.y, HOLD_OFFSET.z)
	grab_offsets[mount] = body.to_local(mount.to_global(hold_offset))
	grabs[mount] = body


func arm_hit_detected(hit: Vector3, _normal: Vector3, collider: Object, mount: ArmMount) -> void:
	if not player.is_in_grab_mode:
		return

	if not collider is RigidBody3D:
		return

	if grabs.has(mount):
		return

	var body = collider as RigidBody3D
	grab_offsets[mount] = body.to_local(hit)
	grabs[mount] = body
	# HELD_LAYER kills the player-vs-body pair: the player's mask doesn't include it
	if not original_layers.has(body):
		original_layers[body] = body.collision_layer
	body.collision_layer = player.HELD_LAYER

func is_mount_grabbing(mount: ArmMount) -> bool:
	return grabs.has(mount)

func is_grabbing() -> bool:
	return not grabs.is_empty()

func _get_now() -> float:
	return Time.get_ticks_msec() / 1000.0
