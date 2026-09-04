class_name WallClimbConfig
extends Resource

## Angles are stored in degrees; states convert to radians/dots at init time.

@export_group("Rays")
@export var wall_offset: float = 2.0
@export var wall_raycast_dist: float = 5.0
@export var ledge_ray_offset: float = 3.0
@export var ledge_ray_length: float = 5.0

@export_group("Mount Detection")
@export var wall_climb_debounce_time: float = 0.5
## max angle (deg) between a wall normal and the player's facing
## for the hit to count as a mountable wall
@export var wall_mount_max_angle_deg: float = 60.0
## min dot between a wall surface normal and the player's facing
## for the surface to be trusted as "the wall in front"
@export var min_wall_facing_angle_deg: float = 60.0
## max angle (deg) between the correction ray's normal and the
## average wall normal before the hit is considered glancing
@export var max_wall_normal_deviation_angle_deg: float = 70.0
## min dot between a ledge hit's normal and straight up
@export var ledge_min_up_angle_deg: float = 60.0
## downward speed above which the wall climb debounce is bypassed
@export var fall_speed_wall_debounce_bypass: float = -0.2

@export_group("Correction")
@export var wall_offset_correction_rate: float = 10.0

@export_group("Tilt")
@export var wall_max_tilt_deg: float = 5.0
@export var wall_tilt_smoothing_speed: float = 2.0

@export_group("Ledge Dismount")
@export var mount_velocity_impulse: float = 5.0
@export var ledge_dismount_foot_stagger: float = 0.2

@export_group("Cornering")
@export var inside_corner_duration: float = 1.0
@export var outside_corner_duration: float = 0.7
@export var corner_step_min_displacement: float = 0.5
@export var outside_corner_ray_lateral_offset: float = 1.0
@export var outside_corner_ray_reach: float = 2.5
@export var outside_corner_ray_depth: float = 3.0
@export var inside_corner_min_normal_diff_angle_deg: float = 70.0
@export var outside_corner_min_side_angle_deg: float = 65.0
@export var outside_corner_max_parallel_angle_deg: float = 45.0
