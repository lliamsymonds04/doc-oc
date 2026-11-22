class_name EnemySlamAttack
extends EnemyAttack

enum Phase { IDLE, WINDUP, LEAP, HOVER, SLAM, RECOVERY }

const SHAPE_HEIGHT: float = 2.0
## Backstop for a slam that never finds a floor (e.g. over a pit).
const SLAM_TIMEOUT: float = 3.0
const FLOOR_PROBE: float = 50.0
const WORLD_MASK: int = 1
const MAX_TILT_DEG: float = 60.0
const JUMP_MARGIN: float = 1.05
const SLAM_SOUND := preload("res://assets/audio/enemy/slam_dive.wav")

var _config: SlamAttackConfig
var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _ground_y: float = 0.0
## The config height until hover measures the real floor.
var _dive_height: float = 0.0
var _slam_point: Vector3
## Floor normal under the slam point, for the impact decal.
var _landing_normal: Vector3 = Vector3.UP
var _slam_drift_velocity: Vector3
var _shape_cast: ShapeCast3D
var _telegraph: RingEffect
var _audio: AudioStreamPlayer3D


func _init(e: EnemyController, config: SlamAttackConfig) -> void:
	super(e)
	_config = config

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = SLAM_SOUND
	e.add_child(_audio)

	var cylinder := CylinderShape3D.new()
	cylinder.radius = config.slam_radius
	cylinder.height = SHAPE_HEIGHT

	_shape_cast = ShapeCast3D.new()
	_shape_cast.shape = cylinder
	_shape_cast.position = Vector3.UP * (SHAPE_HEIGHT * 0.5)
	_shape_cast.collide_with_areas = false
	_shape_cast.enabled = false
	e.add_child(_shape_cast)

	_telegraph = RingEffect.new()
	_telegraph.top_level = true
	e.add_child(_telegraph)


func can_start(dist: float) -> bool:
	if not enemy.is_on_floor():
		return false

	return _phase == Phase.IDLE and dist < _config.detection_range


func start() -> void:
	_phase = Phase.WINDUP
	_phase_timer = _config.windup


func physics_update(dt: float) -> void:
	if _phase == Phase.IDLE:
		return

	_phase_timer -= dt

	match _phase:
		Phase.WINDUP:
			if _phase_timer <= 0.0:
				_begin_leap()
		Phase.LEAP:
			var hovered := enemy.global_position.y >= _ground_y + _config.hover_height
			if hovered or enemy.velocity.y <= 0.0:
				_begin_hover()
		Phase.HOVER:
			enemy.velocity.y = 0.0
			if _phase_timer <= 0.0:
				_begin_slam()
		Phase.SLAM:
			enemy.velocity.y = -_config.slam_speed
			_slam_drift_velocity = _slam_drift()
			enemy.velocity.x = _slam_drift_velocity.x
			enemy.velocity.z = _slam_drift_velocity.z
			if _phase_timer <= 0.0 or enemy.is_on_floor():
				_impact()
		Phase.RECOVERY:
			if _phase_timer <= 0.0:
				cancel()


func cancel() -> void:
	_clear_telegraph()
	_slam_drift_velocity = Vector3.ZERO
	_phase = Phase.IDLE
	_phase_timer = 0.0
	enemy.velocity.y = 0.0


func is_committed() -> bool:
	return _phase != Phase.IDLE and _phase != Phase.RECOVERY


## Chase on the way up only: the fall is a committed drop, not a homing slam.
func committed_velocity() -> Vector3:
	if _phase == Phase.SLAM:
		return _slam_drift_velocity
	if _phase != Phase.LEAP:
		return Vector3.ZERO

	var target := enemy.get_target()
	if target == null:
		return Vector3.ZERO

	var to := target.global_position - enemy.global_position
	to.y = 0.0
	if to.length() <= _slam_lead():
		return Vector3.ZERO

	return to.normalized() * _config.air_speed


## The dive keeps the aim it left hover with.
func committed_turn_speed() -> float:
	return 0.0 if _phase == Phase.SLAM else _config.turn_speed


## Hover onward faces the dive point, not the player.
func committed_facing(to_target: Vector3) -> Vector3:
	if _phase != Phase.HOVER:
		return to_target

	var to := _slam_point - enemy.global_position
	to.y = 0.0
	return to


func _begin_leap() -> void:
	_phase = Phase.LEAP
	_ground_y = enemy.global_position.y
	_dive_height = _config.hover_height
	var gravity := enemy.get_gravity().length()
	enemy.velocity.y = sqrt(2.0 * gravity * _config.hover_height) * JUMP_MARGIN


func _begin_hover() -> void:
	_phase = Phase.HOVER
	_phase_timer = _config.hover_time
	enemy.velocity.y = 0.0
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0

	_aim_dive()


## Aims at the floor under the lead: the warning and the landing must agree.
func _aim_dive() -> void:
	var base := Vector3(enemy.global_position.x, _ground_y, enemy.global_position.z)
	var dir := _slam_direction()
	_landing_normal = Vector3.UP

	# the lead needs the drop and the drop needs the lead: aim once from the guess,
	# then re-aim from the floor that aim actually finds
	var hit := _floor_under(base + dir * _slam_lead())
	if hit.is_empty():
		# nothing to land on
		_slam_point = base + dir * _slam_lead()
		return

	var floor_y := (hit["position"] as Vector3).y
	_landing_normal = hit["normal"] as Vector3
	_dive_height = maxf(enemy.global_position.y - floor_y, 0.0)

	_slam_point = base + dir * _slam_lead()
	_slam_point.y = floor_y
	_telegraph.show_at(_slam_point, _config.slam_radius, _config.hover_time)


func _begin_slam() -> void:
	_phase = Phase.SLAM
	_phase_timer = SLAM_TIMEOUT
	enemy.velocity.y = -_config.slam_speed
	_slam_drift_velocity = Vector3.ZERO
	AudioUtil.play_with_pitch(_audio)


func _impact() -> void:
	_phase = Phase.RECOVERY
	_phase_timer = _config.cooldown
	enemy.velocity.y = 0.0

	_damage_in_radius()
	_clear_telegraph()
	CrackDecal.spawn(enemy.get_tree().current_scene, enemy.global_position, _landing_normal, 1.5)


func _clear_telegraph() -> void:
	_telegraph.fade_out()


## Aim snapshot: the player can move during the dive, so this must not update.
func _slam_direction() -> Vector3:
	var target := enemy.get_target()
	if target == null:
		return Vector3.ZERO

	var to := target.global_position - enemy.global_position
	to.y = 0.0
	if to.length() < 0.001:
		return Vector3.ZERO
	return to.normalized()


func _slam_drift() -> Vector3:
	var to := _slam_point - enemy.global_position
	to.y = 0.0
	var distance := to.length()
	if distance < 0.1:
		return Vector3.ZERO
	return to / distance * _horizontal_speed()


## Forward travel: the configured lead
func _slam_lead() -> float:
	return minf(_config.slam_lead, _dive_height * tan(deg_to_rad(MAX_TILT_DEG)))


func _horizontal_speed() -> float:
	var fall_time := maxf(_dive_height / maxf(_config.slam_speed, 0.001), 0.01)
	return _slam_lead() / fall_time


## Floor hit under `point`, empty when nothing is down there.
func _floor_under(point: Vector3) -> Dictionary:
	var from := point + Vector3.UP * 0.5
	var params := PhysicsRayQueryParameters3D.create(
		from, from - Vector3.UP * FLOOR_PROBE, WORLD_MASK
	)
	return enemy.get_world_3d().direct_space_state.intersect_ray(params)


## Mask comes from the target, so no world or enemy layers are queried.
func _damage_in_radius() -> void:
	var target := enemy.get_target()
	if target == null or not enemy.has_clear_target(target):
		return

	_shape_cast.collision_mask = target.collision_layer
	_shape_cast.force_shapecast_update()

	var hit := {}
	for i in _shape_cast.get_collision_count():
		var player := _shape_cast.get_collider(i) as PlayerController
		if player == null or hit.has(player.get_instance_id()):
			continue
		hit[player.get_instance_id()] = true
		var away := player.global_position - enemy.global_position
		away.y = 0.0
		player.take_damage(_config.damage, away.normalized())
