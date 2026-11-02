class_name SlamAttackConfig
extends EnemyAttackConfig

## Reaching this close starts the slam. Wider than melee: the leap covers the gap.
@export var detection_range: float = 6.0

@export_group("Aim")
## Yaw rate (rad/s) while committed; faster than the walk turn.
@export var turn_speed: float = 12.0

@export_group("Leap")
## Wait on the ground before the jump.
@export var windup: float = 0.4
## Hover this high above the launch point; the launch speed is derived from it.
@export var hover_height: float = 4.0
## Horizontal chase speed while airborne.
@export var air_speed: float = 10.0
## Hover duration; the warning ring grows over exactly this long.
@export var hover_time: float = 0.35

@export_group("Slam")
@export var slam_speed: float = 30.0
## How far in front of the hover point the slam lands. A short dive pulls it in,
## capped by the attack's MAX_TILT_DEG so the sideways speed stays sane.
@export var slam_lead: float = 4.0
## Radius of the shape-cast shockwave on landing.
@export var slam_radius: float = 3.0
@export var damage: float = 25.0
## Recovery doubles as the cooldown before another slam can start.
@export var cooldown: float = 1.5
