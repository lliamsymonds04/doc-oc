class_name HopMovement
extends EnemyMovement

const LANDING_VFX := preload("res://assets/vfx/smoke_puff.tscn")
const LANDING_SOUND := preload("res://assets/audio/enemy/robot-hop.ogg")
## Anticipation and release shapes, shared with the melee telegraph.
const SQUASH := Vector3(1.25, 0.75, 1.25)
const STRETCH := Vector3(0.85, 1.25, 0.85)
## Exponential rate (1/s) the shape eases at; high enough to pop.
const DEFORM_RATE := 25.0

## Heading locked in at the last launch, so the arc is not steerable.
var _dir := Vector3.FORWARD
## Ground time left before the next hop.
var _rest := 0.0
## Whether the body was airborne on the previous frame.
var _airborne := false
## Landing burst, parked world-space under the enemy.
var _landing_vfx: ImpactVFX
## Thud at the feet on each touchdown.
var _audio: AudioStreamPlayer3D


func _init(e: EnemyController) -> void:
	super(e)

	_landing_vfx = LANDING_VFX.instantiate() as ImpactVFX
	_landing_vfx.top_level = true
	enemy.add_child(_landing_vfx)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = LANDING_SOUND
	enemy.add_child(_audio)


## Hops instead of walking: crouch on the floor, then one ballistic arc toward the
## target. Launch speed is written straight to the body and returned, so the
## controller's lerp toward it is a no-op on that frame.
func desired_velocity(dt: float, dist: float, forward: Vector3) -> Vector3:
	if not enemy.is_on_floor():
		return _dir * enemy.config.move_speed

	# landing: drop the carried speed so the rest reads as a stop, not a slide
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0

	_rest = maxf(_rest - dt, 0.0)
	if _rest > 0.0 or dist <= enemy.config.stop_distance:
		return Vector3.ZERO

	_dir = forward
	enemy.velocity.x = _dir.x * enemy.config.move_speed
	enemy.velocity.z = _dir.z * enemy.config.move_speed
	enemy.velocity.y = sqrt(2.0 * enemy.get_gravity().length() * enemy.config.hop_height)
	_rest = enemy.config.hop_rest
	return _dir * enemy.config.move_speed


func after_slide(dt: float) -> void:
	_touchdown()
	_squash(dt)


## Touchdown is detected outside the attack branch: starting the slam preempts the
## hop on the very frame the bot lands, which used to swallow that thud.
func _touchdown() -> void:
	if not enemy.is_on_floor():
		_airborne = true
		return

	if _airborne:
		_airborne = false
		_landing_vfx.play(enemy.global_position, enemy.get_floor_normal())
		AudioUtil.play_with_pitch(_audio)


## Squash while loading the next hop, stretch on the way up, upright in between.
## Scales about the feet, so scenes with hop_height keep their mesh pivot on the
## floor (slam_enemy.tscn wraps the model in an empty Mesh node for this).
func _squash(dt: float) -> void:
	var target := Vector3.ONE
	if enemy.velocity.y > 0.0:
		target = STRETCH
	elif enemy.is_on_floor() and _rest > 0.0:
		target = SQUASH

	enemy.mesh.scale = enemy.mesh.scale.lerp(target, 1.0 - exp(-DEFORM_RATE * dt))
