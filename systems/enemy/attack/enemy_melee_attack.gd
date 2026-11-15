class_name EnemyMeleeAttack
extends EnemyAttack

## IDLE -> WINDUP -> SWING -> RECOVERY -> IDLE.
enum Phase { IDLE, WINDUP, SWING, RECOVERY }

var _config: MeleeAttackConfig
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
## The visual's clips; a scene without one still plants its feet and swings.
var _anim: AnimationPlayer
var _impact_timer: float = 0.0
var _impact_pending := false


func _init(e: EnemyController, config: MeleeAttackConfig) -> void:
	super(e)
	_config = config
	_anim = e.mesh.find_child("AnimationPlayer", true, false) as AnimationPlayer


func can_start(dist: float) -> bool:
	return _phase == Phase.IDLE and dist < _config.detection_range


func start() -> void:
	_phase = Phase.WINDUP
	_phase_timer = _config.windup
	_play("Windup")


func physics_update(dt: float) -> void:
	if _phase == Phase.IDLE:
		return

	if _phase == Phase.SWING and _impact_pending:
		_impact_timer -= dt
		if _impact_timer <= 0.0:
			_strike()

	_phase_timer -= dt
	if _phase_timer <= 0.0:
		_advance_phase()


func cancel() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_impact_pending = false
	_play("Reset")


func is_committed() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.SWING


func _advance_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_phase = Phase.SWING
			_phase_timer = _config.swing
			_play("Attack")
			_impact_timer = _config.swing * 0.5
			_impact_pending = true
		Phase.SWING:
			_phase = Phase.RECOVERY
			_phase_timer = _config.cooldown
			_play("Recover")
		Phase.RECOVERY:
			_phase = Phase.IDLE
			_phase_timer = 0.0
			_play("Reset")


## Range is re-checked here so a target that left during the windup is not hit.
func _strike() -> void:
	_impact_pending = false
	var target := enemy.get_target()
	if target == null:
		return

	var to := target.global_position - enemy.global_position
	to.y = 0.0
	if to.length() < _config.detection_range:
		target.take_damage(_config.damage, to.normalized())


## Plays a clip when the visual has an animator; scenes without one just plant
## their feet and swing on the phase timers.
func _play(clip: StringName) -> void:
	if _anim:
		_anim.play(clip)
