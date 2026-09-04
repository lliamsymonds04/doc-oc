class_name JumpConfig
extends Resource

@export_group("Grounded Jump")
@export var jump_vertical_velocity: float = 20.0
@export var jump_horizontal_velocity: float = 8.0
@export var max_jump_hold_time: float = 0.6
@export var min_jump_charge: float = 0.5

@export_group("Wall Jump")
@export var wall_jump_upward_velocity: float = 15.0
@export var wall_jump_backward_velocity: float = 15.0
@export var wall_jump_sideways_velocity: float = 15.0
