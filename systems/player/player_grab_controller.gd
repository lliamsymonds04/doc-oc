extends RefCounted
class_name PlayerGrabController

var player: PlayerController
var last_attack_time: float = -INF
const HOLD_OFFSET := Vector3(0.6, 1.2, -0.8)
const HOLD_DRAG_SENS := 0.02  # mouse pixels -> world meters, feel-driven
const WHEEL_NOTCH_SENS := 0.3  # notches -> world meters of height, feel-driven
const MAX_HOLD_DRAG := 2.4  # hold position can move this far from its default, relative to the player
const MAX_GRAB_SPIN := 15.0  # rad/s cap for the rotation servo
const MIN_Z_HOLD_OFFSET := -0.6  # hold position z axis limit

var grabs: Dictionary = {}  # mount -> body
var grab_offsets: Dictionary = {}  # mount -> body-local grip point; fixed at grab time
var hold_offsets: Dictionary = {}  # mount -> mount-local hold position; mouse drag moves this
var grab_relative_rotations: Dictionary = {}  # mount -> Quaternion (body basis relative to player basis)
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

	# fast path: join instantly when the crosshair rests on a body the other arm holds;
	# otherwise the punch below now sweeps with a HELD_LAYER-inclusive mask and joins at contact
	var join_body := _aimed_held_body(15.0)
	if join_body != null:
		_join_grab(mount, join_body)
		last_attack_time = now
		return

	# mask includes HELD_LAYER so the sweep can join a body the other arm already holds
	mount.arm.start_punch(target, ~player.collision_layer)
	last_attack_time = now

func release_grab(side_dir: int) -> void:
	var mount := _get_mount_for_side(side_dir)
	if mount == null or not is_mount_grabbing(mount):
		return

	var body: RigidBody3D = grabs[mount]
	grabs.erase(mount)
	grab_offsets.erase(mount)
	hold_offsets.erase(mount)
	grab_relative_rotations.erase(mount)
	if not grabs.values().has(body):
		body.collision_layer = original_layers[body]
		original_layers.erase(body)

func physics_update(mouse_delta: Vector2, wheel_delta := 0.0) -> void:
	_apply_mouse_drag(mouse_delta, wheel_delta)
	# two arms on one body: per-mount velocity writes would overwrite the other arm's error
	var err_sum := {}    # body -> Vector3
	var err_count := {}  # body -> int

	for mount in grabs.keys():
		if not is_mount_grabbing(mount):
			continue
		if not mount in grab_offsets:
			continue
		var body: RigidBody3D = grabs[mount]
		var offset: Vector3 = grab_offsets[mount]

		var grip_world: Vector3 = body.to_global(offset)
		var anchor: Vector3 = mount.to_global(hold_offsets[mount])

		mount.set_target(grip_world)
		mount.set_apply_floor(false)

		var error := anchor - grip_world
		err_sum[body] = err_sum.get(body, Vector3.ZERO) + error
		err_count[body] = err_count.get(body, 0) + 1

		# rotation servo: keep the body's orientation locked relative to the player
		var dt := player.get_physics_process_delta_time()
		var target_q: Quaternion = player.global_transform.basis.get_rotation_quaternion() * grab_relative_rotations[mount]
		var current_q := body.global_transform.basis.get_rotation_quaternion()

		# delta in WORLD frame: target = q_err * current, because angular_velocity is global-space
		var q_err := target_q * current_q.inverse()
		if q_err.w < 0.0:
			q_err = -q_err  # take the shortest path around

		var axis := Vector3(q_err.x, q_err.y, q_err.z)
		var angle := q_err.get_angle()
		if angle > 0.001 and axis.length() > 0.001:
			# P-gain below 1.0/dt keeps it stable instead of oscillating
			body.angular_velocity = (axis.normalized() * angle / dt * 0.7).limit_length(MAX_GRAB_SPIN)
		else:
			body.angular_velocity = Vector3.ZERO

	for body in err_sum:
		body.linear_velocity = (err_sum[body] / err_count[body]) * 15

## Mouse motion moves the hold position relative to the player; the servo pulls the body
## so its fixed grip point lands there, and the arm target simply follows that point.
## Mouse X = lateral (flat cam X), mouse Y = depth (flat cam Z), wheel = height (world UP).
func _apply_mouse_drag(mouse_delta: Vector2, wheel_delta: float) -> void:
	if mouse_delta == Vector2.ZERO and is_zero_approx(wheel_delta):
		return
	if grabs.is_empty():
		return

	if not player.is_idle():
		return

	var cam_basis: Basis = player.camera_controller.get_flat_basis()
	var world_delta: Vector3 = \
		cam_basis.x * mouse_delta.x * HOLD_DRAG_SENS + \
		cam_basis.z * mouse_delta.y * HOLD_DRAG_SENS + \
		-Vector3.UP * wheel_delta * WHEEL_NOTCH_SENS

	for mount in grabs:
		var local_delta: Vector3 = mount.global_transform.basis.inverse() * world_delta
		var default := _default_hold_offset(mount)
		var moved: Vector3 = (hold_offsets[mount] as Vector3) + local_delta - default
		var new_offset := default + moved.limit_length(MAX_HOLD_DRAG)

		# apply limit on the z axis
		new_offset.z = minf(new_offset.z, MIN_Z_HOLD_OFFSET)
		hold_offsets[mount] = new_offset

func _default_hold_offset(mount: ArmMount) -> Vector3:
	return Vector3(HOLD_OFFSET.x * sign(mount.position.x), HOLD_OFFSET.y, HOLD_OFFSET.z)

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
	var hold_offset := _default_hold_offset(mount)
	hold_offsets[mount] = hold_offset
	grab_offsets[mount] = body.to_local(mount.to_global(hold_offset))
	grab_relative_rotations[mount] = \
		player.global_transform.basis.get_rotation_quaternion().inverse() \
		* body.global_transform.basis.get_rotation_quaternion()
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
	hold_offsets[mount] = _default_hold_offset(mount)
	grab_relative_rotations[mount] = \
		player.global_transform.basis.get_rotation_quaternion().inverse() \
		* body.global_transform.basis.get_rotation_quaternion()
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
