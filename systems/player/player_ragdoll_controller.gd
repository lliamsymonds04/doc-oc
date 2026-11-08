class_name PlayerRagdollController
extends RefCounted

## Replaces the player's CharacterBody with a rigid body ragdoll when they die.

const TORSO_MASS := 30.0
const BONE_MASS := 2.0

var _player: PlayerController
var _root: Node
var _torso: RigidBody3D


func _init(player: PlayerController) -> void:
	_player = player


# shortcut: bodies and joints are never freed, free them when a respawn or restart exists
func activate(launch: Vector3 = Vector3.ZERO) -> void:
	_root = _player.get_parent()
	_create_torso()
	for mount in _player.all_mounts():
		_create_limb(mount.arm)
	# only the torso is kicked; the pinned limbs trail behind and whip
	_torso.linear_velocity += launch
	_detach_camera()
	_stop_player()


func _create_limb(arm: BasicArm) -> void:
	var parent := _torso
	for i in range(arm.num_limbs):
		var bone := _create_bone(arm, i)
		_pin(parent, bone, arm.global_transform * arm.solver.joints[i])
		parent = bone

	_attach_mesh(parent, arm.joint_meshes[arm.num_limbs])


func _create_bone(arm: BasicArm, index: int) -> RigidBody3D:
	var mesh: MeshInstance3D = arm.limb_meshes[index]
	var bone := _new_body(BONE_MASS)

	var capsule := CapsuleShape3D.new()
	capsule.radius = arm.limb_radius
	capsule.height = arm.limb_length
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	bone.add_child(shape)

	_root.add_child(bone)
	bone.global_transform = mesh.global_transform
	bone.linear_velocity = _player.velocity
	bone.reset_physics_interpolation()

	# taken from this mesh's transform, so the duplicate needs no offset
	var copy := mesh.duplicate() as MeshInstance3D
	copy.transform = Transform3D.IDENTITY
	bone.add_child(copy)
	_attach_mesh(bone, arm.joint_meshes[index])

	return bone


func _create_torso() -> void:
	_torso = _new_body(TORSO_MASS)

	var shape := CollisionShape3D.new()
	shape.shape = _player.hitbox.shape
	shape.position = _player.hitbox.position
	_torso.add_child(shape)

	_root.add_child(_torso)
	_torso.global_transform = _player.global_transform
	_torso.linear_velocity = _player.velocity
	_torso.reset_physics_interpolation()

	_attach_mesh(_torso, _player.bean)


func _new_body(mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.continuous_cd = true
	body.collision_layer = _player.collision_layer
	# the player layer is not in its own mask, so ragdoll parts pass through each other
	body.collision_mask = _player.collision_mask
	return body


func _attach_mesh(body: RigidBody3D, mesh: MeshInstance3D) -> void:
	var copy := mesh.duplicate() as MeshInstance3D
	copy.transform = body.global_transform.inverse() * mesh.global_transform
	body.add_child(copy)


func _pin(a: RigidBody3D, b: RigidBody3D, pivot: Vector3) -> void:
	var joint := PinJoint3D.new()
	_root.add_child(joint)
	joint.global_position = pivot
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)


# reparent keeps the world transform, so the camera stays where the player died
func _detach_camera() -> void:
	_player.camera_controller.reparent(_root)


func _stop_player() -> void:
	_player.hitbox.set_deferred("disabled", true)
	_player.tilt_pivot.visible = false
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	for mount in _player.all_mounts():
		mount.set_process(false)
		mount.arm.set_process(false)
