class_name EnemyImpactController
extends Node

## Deals damage to the enemy when its ragdoll body takes a hard impact.
## Lives as a child of the ragdoll body and polls contact impulses

const EFFECT_COOLDOWN: float = 0.2  # seconds between damage applications
const IMPACT_DV: float = 15.0
const BASE_DECAL_SIZE_FACTOR: float = 1.5
const MAX_DECAL_SIZE_FACTOR: float = 3.0
const SHAKE_DV: float = 8.0  # min contact dv that counts as a shake-worthy wall hit
const SHAKE_STRENGTH: float = 1.0  # max trauma at point-blank, max-dv hits
const SHAKE_DV_REF: float = 2.0  # dv multiple (of SHAKE_DV) that shakes at full strength
const SHAKE_MAX_DIST: float = 32.0  # m from the camera; beyond this hits don't shake
const WALL_NORMAL_DOT_UP: float = 0.7  # contacts with |normal.y| above this are floor/ceiling
const IMPACT_AUDIO_STREAM: AudioStream = preload("res://assets/audio/hit_impact.ogg")
const DEFAULT_VOL: float = -5.0
const VOL_RANGE: float = 10.0

var _enemy: EnemyController
var _body: RigidBody3D
var _impact_audio_player: AudioStreamPlayer3D
var _min_dv: float
var _damage_per_dv: float
var _last_impact_physics_frame: int = -100

func _init(enemy: EnemyController, body: RigidBody3D, min_dv: float, damage_per_dv: float) -> void:
	_enemy = enemy
	_body = body
	_min_dv = min_dv
	_damage_per_dv = damage_per_dv

	body.contact_monitor = true
	body.max_contacts_reported = 8

	_impact_audio_player = AudioStreamPlayer3D.new()
	_impact_audio_player.set_stream(IMPACT_AUDIO_STREAM)
	_impact_audio_player.volume_db = DEFAULT_VOL
	_body.add_child(_impact_audio_player)

	_body.add_child(self)


func _physics_process(_dt: float) -> void:
	if _body.freeze:
		return

	var frame := Engine.get_physics_frames()
	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	for i in state.get_contact_count():
		# impulse / mass = equivalent velocity change -> mass-independent tuning
		var dv := state.get_contact_impulse(i).length() / _body.mass
		if dv < _min_dv:
			continue

		if frame - _last_impact_physics_frame \
			<= EFFECT_COOLDOWN * Engine.get_physics_ticks_per_second():
			return
		_last_impact_physics_frame = frame

		if not _enemy.is_dead():
			_enemy.take_damage(dv * _damage_per_dv)
			_spawn_crack_decal(dv, state, i)

		_shake_camera(dv, state.get_contact_local_normal(i))


		var vol_offset: float = clampf((dv - _min_dv)/IMPACT_DV - 1, 0, 1)
		_impact_audio_player.volume_db = DEFAULT_VOL + vol_offset * VOL_RANGE
		AudioUtil.play_with_pitch(_impact_audio_player)

		break


func _spawn_crack_decal(dv: float, state: PhysicsDirectBodyState3D, i: int) -> void:
	if dv < IMPACT_DV:
		return

	var strength = minf(dv/IMPACT_DV * BASE_DECAL_SIZE_FACTOR, MAX_DECAL_SIZE_FACTOR)

	CrackDecal.spawn(
		state.get_contact_collider_object(i),
		state.get_contact_local_position(i),
		state.get_contact_local_normal(i),
		strength,
	)


func _shake_camera(dv: float, normal: Vector3) -> void:
	# near-vertical contact normals are floor/ceiling hits; only walls shake
	if absf(normal.y) > WALL_NORMAL_DOT_UP:
		return

	var cam_ctrl := _body.get_tree().get_first_node_in_group("camera_controller") as CameraController
	if cam_ctrl == null:
		return

	var dist := _body.global_position.distance_to(cam_ctrl.cam.global_position)
	if dist >= SHAKE_MAX_DIST:
		return

	var impact := minf(dv / SHAKE_DV, 1.0)
	cam_ctrl.add_trauma(SHAKE_STRENGTH * impact * pow(0.5, dist / SHAKE_MAX_DIST))
