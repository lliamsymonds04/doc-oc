class_name JumpConfig
extends Resource

@export_group("Grounded Jump")
@export var max_jump_hold_time: float = 0.7
@export var dash_jump_ceiling: float = 0.2
## Charge 0: flat, fast launch.
@export var dash_vertical_velocity: float = 8.0
@export var dash_horizontal_velocity: float = 22.0
## Charge 1: the high, floaty hop.
@export var hop_vertical_velocity: float = 20.0
@export var hop_horizontal_velocity: float = 10.0

@export_group("Jump Gravity")
@export var dash_gravity_multiplier: float = 2.6
@export var hop_gravity_multiplier: float = 1.0
## Extra scale applied once falling, so there is no hang time at the apex.
@export var fall_gravity_multiplier: float = 1.6

@export_group("Wall Jump")
@export var wall_jump_upward_velocity: float = 15.0
@export var wall_jump_backward_velocity: float = 15.0
@export var wall_jump_sideways_velocity: float = 15.0

@export_group("Vfx")
@export var dash_vfx: PackedScene = preload("res://assets/vfx/dash_particles.tscn")
