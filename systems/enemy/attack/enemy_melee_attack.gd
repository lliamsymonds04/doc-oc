class_name EnemyMeleeAttack
extends EnemyAttack

## IDLE -> WINDUP -> SWING -> RECOVERY -> IDLE.
enum Phase { IDLE, WINDUP, SWING, RECOVERY }

const SWING_SOUND := preload("res://assets/audio/enemy/sword_swing.ogg")

var _config: MeleeAttackConfig
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
## The visual's clips; a scene without one still plants its feet and swings.
var _anim: AnimationPlayer
## Ribbon on the axe head; the visual without one swings bare.
var _trail: AxeTrail
## Whiff at the start of every swing.
var _audio: AudioStreamPlayer3D
var _impact_timer: float = 0.0
var _impact_pending := false


func _init(e: EnemyController, config: MeleeAttackConfig) -> void:
	super(e)
	_config = config
	_anim = e.mesh.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_trail = e.find_child("AxeTrail", true, false) as AxeTrail

	_audio = AudioStreamPlayer3D.new()
	_audio.bus = AudioUtil.SFX_BUS
	_audio.stream = SWING_SOUND
	e.add_child(_audio)


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
	_set_trail(false)
	_play("Reset")


func is_committed() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.SWING


func _advance_phase() -> void:
	match _phase:
		Phase.WINDUP:
			_phase = Phase.SWING
			_phase_timer = _config.swing
			_set_trail(true)
			AudioUtil.play_with_pitch(_audio)
			_play("Attack")
			_impact_timer = _config.swing * 0.5
			_impact_pending = true
		Phase.SWING:
			_phase = Phase.RECOVERY
			_phase_timer = _config.cooldown
			_set_trail(false)
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
	if to.length() < _config.detection_range and enemy.has_clear_target(target):
		to.y = 0.0
		target.take_damage(_config.damage, to.normalized())


## Plays a clip when the visual has an animator; scenes without one just plant
## their feet and swing on the phase timers.
func _play(clip: StringName) -> void:
	if _anim:
		_anim.play(clip)


## Only the swing leaves a ribbon; windup and recovery hold the axe still.
func _set_trail(on: bool) -> void:
	if _trail != null:
		_trail.set_emitting(on)
