class_name MeleeAttackConfig
extends EnemyAttackConfig

## Reaching this close starts the attack.
@export var detection_range: float = 2.0
## Telegraph: the enemy plants its feet and only winds up.
@export var windup: float = 0.5
## Committed swing; damage lands halfway through it.
@export var swing: float = 0.5
## Recovery doubles as the cooldown before another windup can start.
@export var cooldown: float = 1.25
@export var damage: float = 10.0
