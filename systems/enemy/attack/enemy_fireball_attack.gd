class_name EnemyFireballAttack
extends EnemyAttack

## IDLE -> WINDUP -> RECOVERY -> IDLE. The tell charges at the muzzle through
## the windup, then a fireball is launched along the aim snapshot.

enum Phase { IDLE, WINDUP, RECOVERY }

const TELL_SCENE := preload("res://assets/vfx/fire_tell.tscn")
const WORLD_MASK: int = 1

var _config: FireballAttackConfig
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _tell: FireTell


func _init(e: EnemyController, config: FireballAttackConfig) -> void:
	super(e)
	_config = config

	_tell = TELL_SCENE.instantiate() as FireTell
	_tell.position = Vector3(0.0, _config.muzzle_height, -_config.muzzle_forward)
	e.add_child(_tell)


func can_start(dist: float) -> bool:
	if _phase != Phase.IDLE or dist >= _config.detection_range:
		return false

	return _has_line_of_sight()


func start() -> void:
	_phase = Phase.WINDUP
	_phase_timer = _config.windup
	_tell.start(_config.windup)


func physics_update(dt: float) -> void:
	if _phase == Phase.IDLE:
		return

	_phase_timer -= dt
	if _phase_timer > 0.0:
		return

	match _phase:
		Phase.WINDUP:
			_phase = Phase.RECOVERY
			_phase_timer = _config.recovery
			_fire()
		Phase.RECOVERY:
			cancel()


func cancel() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_tell.stop()


func is_committed() -> bool:
	return _phase == Phase.WINDUP


## Aim keeps tracking through the windup, so a strafing target is still hit.
func committed_turn_speed() -> float:
	return _config.turn_speed


## Aim snapshot at release: the player can dodge once the fireball is out.
func _fire() -> void:
	_tell.stop()

	var target := enemy.get_target()
	if target == null:
		return

	var from := _muzzle()
	# root, not the enemy: the shot has to outlive its shooter
	Fireball.spawn(_config, enemy.get_tree().current_scene, from, _lead_point(from, target))


## Aim point for a straight shot: |P + V*t - M| = s*t, for a player holding
## this velocity. Flattened so a falling player isn't led below the floor.
func _lead_point(from: Vector3, target: PlayerController) -> Vector3:
	var aim := target.global_position + Vector3.UP * _config.aim_height
	var d := aim - from
	var v := Vector3(target.velocity.x, 0.0, target.velocity.z)

	var a := v.dot(v) - _config.fireball_speed * _config.fireball_speed
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var t := -1.0

	if absf(a) < 0.001:
		# |v| == speed: no t^2 term, the quadratic collapses to linear
		if absf(b) > 0.001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			t = (-b - sqrt(disc)) / (2.0 * a)

	# player outruns the ball: fire at where they are instead
	if t <= 0.0:
		return aim

	return aim + v * t


## The tell is parented to the enemy, so its transform is already the muzzle.
func _muzzle() -> Vector3:
	return _tell.global_position


func _has_line_of_sight() -> bool:
	var target := enemy.get_target()
	if target == null:
		return false

	var to := target.global_position + Vector3.UP * _config.aim_height
	var params := PhysicsRayQueryParameters3D.create(_muzzle(), to, WORLD_MASK)
	return enemy.get_world_3d().direct_space_state.intersect_ray(params).is_empty()
