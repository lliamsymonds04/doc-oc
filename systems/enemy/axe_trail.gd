class_name AxeTrail
extends Node3D

## Bone the axe hangs off in axe-bot.glb; the ribbon rides its tip.
const BONE := "Axe"
## Marker in the enemy scene that marks the axe head at rest pose; only its
## position matters, and it can be dragged in the editor to re-aim the ribbon.
const MARKER := "AxeTip"

## Same look as the player's arm sweep, so both read as one effect.
@export var trail_color: Color = Color(1, 0, 0)
@export var trail_width: float = 0.25
@export var trail_lifetime: float = 0.2

var _skeleton: Skeleton3D
var _bone: int = -1
## Marker position in bone space, taken once at rest pose, so the ribbon then
## follows the animated bone from there.
var _tip_offset := Vector3.ZERO
var _trail: Trail


func _ready() -> void:
	var enemy := get_parent() as EnemyController
	if enemy == null:
		push_error("AxeTrail must sit on an EnemyController")
		return

	var marker := enemy.find_child(MARKER, true, false) as Node3D
	if marker == null:
		push_error("AxeTrail needs a '%s' marker in the enemy scene" % MARKER)
		return

	# enemy.mesh is @onready, so it is still null while this child's _ready runs
	var mesh: Node3D = enemy.get_node(^"Mesh")
	_skeleton = mesh.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		push_error("AxeTrail needs a Skeleton3D under %s" % mesh.name)
		return

	_bone = _skeleton.find_bone(BONE)
	if _bone < 0:
		push_error("AxeTrail: %s has no '%s' bone" % [mesh.name, BONE])
		return

	var rest := _skeleton.global_transform * _skeleton.get_bone_global_rest(_bone)
	_tip_offset = rest.affine_inverse() * marker.global_position

	_trail = Trail.create()
	_trail.color = trail_color
	_trail.trail_width = trail_width
	_trail.trail_lifetime = trail_lifetime
	# the shader displaces the ribbon past its mesh bounds, which the culler
	# does not know about
	_trail.extra_cull_margin = 4.0
	_trail.emitting = false
	add_child(_trail)


## Follows the animated bone, so the ribbon traces the swing for free.
func _process(_dt: float) -> void:
	if _bone < 0:
		return

	var pose := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)
	global_position = pose * _tip_offset


func set_emitting(on: bool) -> void:
	if _trail != null:
		_trail.emitting = on
