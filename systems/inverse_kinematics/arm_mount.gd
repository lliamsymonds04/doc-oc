extends Node3D
class_name ArmMount

@export var is_leg: bool = true
@export var idle_target: Node3D
@export var idle_sway: float = 0.0
@export var idle_sway_speed: float = 1.0

@onready var pole: Node3D = $Pole
@onready var target: Node3D = $Target

var arm: BasicArm

func init() -> BasicArm:
	var anchor = target.duplicate()
	anchor.name = "anchor"
	add_child(anchor)

	target.top_level = true

	arm = BasicArm.new()
	arm.name = "arm_%s" % name
	arm.is_leg = is_leg
	arm.target_node = target
	arm.position = Vector3.ZERO
	arm.target = target.position
	arm.anchor = anchor
	arm.pole = pole
	add_child(arm)

	return arm

func compute_idle_target() -> Vector3:
	var idle_pos = to_local(idle_target.global_position)
	if idle_sway != 0.0:
		idle_pos += Vector3.RIGHT * sin(Time.get_ticks_msec() * idle_sway_speed * 0.001) * idle_sway
	return idle_pos
