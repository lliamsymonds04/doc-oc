class_name PlayerTackleConfig
extends Resource

@export_group("Detection")
## Detection lands at (0.5 + detect_radius) horizontally; 0.5 is the shared radius of
## the player and enemy capsules.
@export var detect_radius: float = 0.9
## Above the player origin, which sits at the feet. Probing at 0 registers only once
## the two capsules already overlap.
@export var probe_height: float = 1.0
## Horizontal only; falling speed never triggers a tackle.
@export var min_dash_speed: float = 12.0

@export_group("Windup")
## Player and enemy capsules are radius 0.5 each, so anything above ~1.0 is visible
## separation.
@export var carry_clearance: float = 1.4
## Added on top of the arms' punch duration, which the windup otherwise tracks.
@export var launch_delay: float = 0.00

@export_group("Launch")
## Written to linear_velocity rather than applied as an impulse, so it ignores each
## enemy's ragdoll mass. Tuned near release_push_speed to keep pace briefly.
@export var launch_speed: float = 24.0
@export var launch_up_speed: float = 3.0
## Keeps a low dash from launching the body into the floor.
@export var snap_lift: float = 0.4
## rad/s about the player's right axis; sign is randomised per tackle.
@export var tumble_speed: float = 9.0

@export_group("Float")
## Also the window the body is held on HELD_LAYER, so it can neither hit the player
## nor be found by casts.
@export var float_time: float = 0.35
@export var float_gravity_scale: float = 0.5
## Bleeds the launch speed off so the body lands nearby rather than sailing away.
@export var float_linear_damp: float = 3.0

@export_group("Punch")
## Divides BasicArm.punch_duration. The windup is derived from it, so this scales the
## whole move, not just the jab.
@export var punch_speed_multiplier: float = 2.5
## Height above the enemy origin.
@export var aim_height: float = 0.5
## Measured from the player, not the enemy, so forward motion can't swallow it.
@export var punch_distance: float = 3.0
## Per arm, so the gap between the two fists is double this.
@export var grip_side_offset: float = 0.35

@export_group("Exit")
## Replaces the magnitude only; direction comes from the player's velocity.
@export var release_push_speed := 25.0
## A floor, not a set value: a steeper dive keeps its own upward speed.
@export var release_lift: float = 2.0

@export_group("Feedback")
@export var launch_trauma: float = 0.8
@export_range(0, -10, -0.5) var launch_fov_kick: float = -3.0
@export var impact_sound: AudioStreamOggVorbis = preload("res://assets/audio/hit_impact.ogg")
