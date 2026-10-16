class_name PlayerTackleConfig
extends Resource

@export_group("Detection")
## Sweep shape radius; tune to the player capsule radius plus a small skin so contact
## is detected a tick before move_and_slide() reaches the enemy.
@export var detect_radius: float = 0.6
## Height above the player origin to start the sweep.
@export var probe_height: float = 0.0
## Minimum horizontal speed that still counts as a tackle.
@export var min_dash_speed: float = 12.0

@export_group("Carry")
@export var carry_time: float = 0.4
## Where the carried enemy rides, relative to the player basis: -Z is forward, so a
## negative z sits in front and a negative y sits below the player's centre.
@export var carry_offset := Vector3(0.0, 0.35, -2.0)
@export var carry_gain := 15.0  # m/s per metre of error
@export var max_carry_speed := 30.0  # must exceed dash_horizontal_velocity (22)
## Speed the player exits the tackle with: keeps the direction of their velocity
## at release, replaces its magnitude.
@export var release_push_speed := 13.0

@export_group("Attack")
## Height above the carried body's origin both arms reach for and stay pinned to.
@export var aim_height: float = 0.5
## Lateral distance between the two grip points, per arm, along the player's right axis.
@export var grip_side_offset: float = 0.35
