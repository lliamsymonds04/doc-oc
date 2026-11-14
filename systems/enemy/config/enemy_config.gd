class_name EnemyConfig
extends Resource

@export_group("Movement")
## Speed while closing in on the target.
@export var move_speed: float = 3.0
## Exponential rate horizontal velocity chases its target. Higher = snappier.
@export var accel: float = 5.0
## Yaw rate (rad/s) toward the target.
@export var turn_speed: float = 4.0
## Distance the enemy stops closing in at, instead of walking into the target.
@export var stop_distance: float = 1.5
## Upward speed while the climb holds, and the speed of the mount pop.
@export var climb_speed: float = 3.0
## Largest |normal.y| still counted as a wall; above it a floor or ceiling.
@export var climb_max_normal_y: float = 0.3

@export_group("Hover")
## Altitude held above the floor; 0 keeps the enemy walking.
@export var hover_height: float = 0.0
## Spring rate pulling back to that altitude. Lower = lazier bob.
@export var hover_stiffness: float = 6.0
## Peak elevation swing around hover_height; 0 holds a flat altitude.
@export var hover_bob_height: float = 0.0
## Bob rate (rad/s); a full up-down cycle is TAU / this.
@export var hover_bob_speed: float = 2.0

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
