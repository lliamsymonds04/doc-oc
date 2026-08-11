extends Node3D
class_name ArmMount

@export var is_leg: bool = true

@export_category("Idle targeting")
@export var idle_target: Node3D
@export var idle_sway_x: float = 0.0
@export var idle_sway_y: float = 0.0
@export var idle_sway_speed: float = 1.0
@export var idle_sway_y_mult: float = 2.0
@export_range(-3.1416, 3.1416) var sway_phase: float = 0.0

@onready var pole: Node3D = $Pole
@onready var target: Node3D = $Target

var arm: BasicArm

var _sway_time: float = 0.0

func _process(delta: float) -> void:
	_sway_time += delta

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
	var t := _sway_time * idle_sway_speed
	if idle_sway_x != 0.0:
		idle_pos += Vector3.RIGHT * sin(t + sway_phase) * idle_sway_x
	if idle_sway_y != 0.0:
		idle_pos += Vector3.UP * sin(t * idle_sway_y_mult + sway_phase) * idle_sway_y
	return idle_pos
