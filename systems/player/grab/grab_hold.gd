extends RefCounted
class_name GrabHold

var mount: ArmMount
var body: RigidBody3D
var grip_offset: Vector3  # body-local grip point; fixed at grab time
var hold_offset: Vector3  # mount-local hold position; mouse drag moves this

func _init(p_mount: ArmMount, p_body: RigidBody3D, p_grip_offset: Vector3,
		config: PlayerGrabConfig) -> void:
	mount = p_mount
	body = p_body
	grip_offset = p_grip_offset
	hold_offset = _default_hold_offset(config)

func grip_world() -> Vector3:
	return body.to_global(grip_offset)

func grip_world_interpolated() -> Vector3:
	return body.get_global_transform_interpolated() * grip_offset

func hold_world() -> Vector3:
	return mount.to_global(hold_offset)

func drag_hold(world_delta: Vector3, config: PlayerGrabConfig) -> void:
	var local_delta: Vector3 = mount.global_transform.basis.inverse() * world_delta
	var default := _default_hold_offset(config)
	var moved: Vector3 = hold_offset + local_delta - default
	hold_offset = default + moved.limit_length(config.MAX_HOLD_DRAG)

func _default_hold_offset(config: PlayerGrabConfig) -> Vector3:
	return Vector3(config.HOLD_OFFSET.x * sign(mount.position.x),
		config.HOLD_OFFSET.y, config.HOLD_OFFSET.z)
