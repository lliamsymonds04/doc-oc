class_name GroundedConfig
extends Resource

@export_group("Debounce")
@export var grounded_debounce_time: float = 1.2

@export_group("Tilt")
@export var walk_tilt_x_deg: float = 10.0
@export var walk_tilt_z_deg: float = 5.0
@export var tilt_speed: float = 2.0
@export var sprint_tilt_x_deg: float = 20.0
@export var sprint_tilt_multiplier: float = 2.0
@export var normal_smoothing_rate: float = 10.0

@export_group("Camera Alignment")
@export var align_angle_deg: float = 1.0
@export var disalign_angle_deg: float = 2.0

@export_group("Sprint")
@export var sprint_multiplier: float = 1.6
@export var sprint_speed_step_multiplier: float = 1.4
