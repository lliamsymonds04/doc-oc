class_name FireballAttackConfig
extends EnemyAttackConfig

## Shooting starts inside this range.
@export var detection_range: float = 14.0

@export_group("Aim")
## Yaw rate (rad/s) while committed; faster than the walk turn.
@export var turn_speed: float = 8.0
## Height above the enemy's feet the fireball leaves from.
@export var muzzle_height: float = 1.5
## How far in front of the visor it spawns, keeping the shot clear of the body.
@export var muzzle_forward: float = 0.5
## Height above the player's feet to aim at (their chest).
@export var aim_height: float = 1.0

@export_group("Shot")
## Telegraph: the tell charges at the muzzle and only the aim tracks.
@export var windup: float = 0.6
@export var fireball_speed: float = 18.0
@export var fireball_damage: float = 15.0
## Recovery doubles as the cooldown before another windup can start.
@export var recovery: float = 1.5
