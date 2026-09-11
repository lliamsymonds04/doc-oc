class_name HoverConfig
extends Resource

@export_group("Hover")
@export var hover_speed: float = 4.0
@export var damping: float = 0.7

@export_group("Body Offset")
@export var min_y_offset: float = 0.1
@export var max_y_offset: float = 2.5
@export var height_change_rate: float = 3.0
@export var target_change_rate: float = 2.0
