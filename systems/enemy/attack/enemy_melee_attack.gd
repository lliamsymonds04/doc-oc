class_name EnemyMeleeAttack
extends EnemyAttack

## IDLE -> WINDUP -> SWING -> RECOVERY -> IDLE.
enum Phase { IDLE, WINDUP, SWING, RECOVERY }

## Anticipation and release shapes for the windup telegraph.
const SQUASH := Vector3(1.25, 0.75, 1.25)
const STRETCH := Vector3(0.85, 1.25, 0.85)

var _config: MeleeAttackConfig
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _mesh_rest_position: Vector3
var _squash_tween: Tween


func _init(e: EnemyController, config: MeleeAttackConfig) -> void:
	super(e)
	_config = config
	_mesh_rest_position = e.mesh.position


func can_start(dist: float) -> bool:
	return _phase == Phase.IDLE and dist < _config.detection_range


func start() -> void:
	_phase = Phase.WINDUP
	_phase_timer = _config.windup
	_play_squash()


func physics_update(dt: float) -> void:
	if _phase == Phase.IDLE:
		return

	_phase_timer -= dt
	if _phase_timer <= 0.0:
		_advance_phase()


func cancel() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_stop_squash()


func is_committed() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.SWING


func _advance_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_phase = Phase.SWING
			_phase_timer = _config.swing
			_strike()
		Phase.SWING:
			_phase = Phase.RECOVERY
			_phase_timer = _config.cooldown
		Phase.RECOVERY:
			_phase = Phase.IDLE
			_phase_timer = 0.0


## Range is re-checked here so a target that left during the windup is not hit.
func _strike() -> void:
	var target := enemy.get_target()
	if target != null and _target_in_range(target):
		target.take_damage(_config.damage)


func _target_in_range(target: PlayerController) -> bool:
	var to := target.global_position - enemy.global_position
	to.y = 0.0
	return to.length() < _config.detection_range


## Anticipate through the windup, release into the swing, snap back on recovery.
## Durations mirror the phase timers so the shape peaks on the frame damage lands.
func _play_squash() -> void:
	_stop_squash()
	var tw := enemy.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween_scale(tw, SQUASH, _config.windup)
	_tween_scale(tw, STRETCH, _config.swing)
	_tween_scale(tw, Vector3.ONE, _config.swing)
	_squash_tween = tw


func _stop_squash() -> void:
	if _squash_tween:
		_squash_tween.kill()
		_squash_tween = null
	enemy.mesh.scale = Vector3.ONE
	enemy.mesh.position = _mesh_rest_position


## CapsuleMesh's origin is its centre, so a vertical scale has to lift the node
## as well or the base floats off the ground.
func _tween_scale(tw: Tween, target: Vector3, duration: float) -> void:
	tw.tween_property(enemy.mesh, "scale", target, duration)
	tw.parallel().tween_property(
		enemy.mesh, "position:y", _mesh_rest_position.y * target.y, duration
	)
