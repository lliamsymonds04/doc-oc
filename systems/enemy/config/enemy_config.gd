class_name EnemyConfig
extends Resource

@export_group("Movement")
## Speed while closing in on the target.
@export var move_speed: float = 3.0
## Exponential rate horizontal velocity chases its target. Higher = snappier.
@export var accel: float = 5.0
## Distance the enemy stops closing in at, instead of walking into the target.
@export var stop_distance: float = 1.5

@export_group("Attack")
@export var attack: EnemyAttackConfig

@export_group("Visuals")
@export var damage_flash_duration: float = 0.2

@export_group("Ragdoll")
@export var dead_body_cleanup_time: float = 10.0
@export var upright_speed: float = 5.0
@export var ragdoll_mass: float = 3.0
## Min velocity jump (m/s) for an impact to hurt.
@export var impact_min_dv: float = 4.0
@export var impact_damage_per_dv: float = 2.0
