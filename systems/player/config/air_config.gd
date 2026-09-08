class_name AirConfig
extends Resource

@export_group("Movement")
@export var air_accel: float = 2.0
@export var air_speed: float = 5.0
@export var air_turn_speed: float = 4.0
@export var min_turn_authority: float = 0.15
@export var air_drag: float = 5.0

@export_group("Arms")
@export var arm_target_speed: float = 8.0
@export var hand_velocity_offset_scale: float = 0.05
@export var hand_velocity_offset_max: float = 1.0

@export_group("Tilt")
@export var air_tilt_rotation_speed: float = 60.0
@export var air_tilt_rotation_scale: float = 0.02
@export var air_tilt_forward_limit_deg: float = 30.0
@export var air_tilt_backward_limit_deg: float = 30.0
@export var air_tilt_sideways_limit_deg: float = 20.0

@export_group("Landing")
@export var landing_trauma: float = 0.6
@export var hard_landing_speed: float = 17.0
@export var hard_landing_trauma_multiplier: float = 1.5
@export var landing_vfx_raycast_distance: float = 5.0
