class_name MeleeAttackConfig
extends EnemyAttackConfig

## Reaching this close starts the attack.
@export var detection_range: float = 2.0
## Telegraph: the enemy plants its feet and only winds up.
@export var windup: float = 0.35
## Committed swing; damage lands on its first frame.
@export var swing: float = 0.12
## Recovery doubles as the cooldown before another windup can start.
@export var cooldown: float = 1.0
@export var damage: float = 10.0
