class_name ImpactSensor
extends Node

## Detects hard impacts on a RigidBody3D by polling contact impulses and emits
## `impacted`. Optionally plays impact audio, shakes the camera and spawns crack
## decals.

signal impacted(dv: float, local_position: Vector3, local_normal: Vector3, collider: Object)

const SENSOR_META := &"impact_sensor"
const GROUP_IMPACT := &"impact_group"  # membership marks a body as sensored
const EFFECT_COOLDOWN: float = 0.2  # seconds between impact events
const IMPACT_DV: float = 5.0
const BASE_DECAL_SIZE_FACTOR: float = 1.5
const MAX_DECAL_SIZE_FACTOR: float = 3.0
const SHAKE_STRENGTH: float = 1.0  # max trauma at point-blank, max-dv hits
const SHAKE_DV: float = 10.0  # m/s of dv that shakes at full strength
const SHAKE_MAX_DIST: float = 32.0  # m from the camera; beyond this hits don't shake
const WALL_NORMAL_DOT_UP: float = 0.7  # contacts with |normal.y| above this are floor/ceiling
const DEFAULT_AUDIO_STREAM: AudioStream = preload("res://assets/audio/hit_impact.ogg")
const DEFAULT_VOL: float = -5.0
const VOL_RANGE: float = 10.0

var min_dv: float
var audio_stream: AudioStream = DEFAULT_AUDIO_STREAM  # null disables impact audio
var camera_shake_enabled := true
var decals_enabled := true
var audio_enabled := true

var _body: RigidBody3D
var _audio_player: AudioStreamPlayer3D
var _last_impact_physics_frame: int = -100


static func attach(body: RigidBody3D, min_vel_change: float) -> ImpactSensor:
	# get_meta's default must not be null: absent and nil are indistinguishable
	if body.has_meta(SENSOR_META):
		var existing := body.get_meta(SENSOR_META) as ImpactSensor
		if is_instance_valid(existing):
			return existing

	return ImpactSensor.new(body, min_vel_change)


func _init(body: RigidBody3D, min_vel_change: float) -> void:
	min_dv = min_vel_change
	_body = body

	body.contact_monitor = true
	body.max_contacts_reported = 8

	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.stream = audio_stream
	_audio_player.volume_db = DEFAULT_VOL
	add_child(_audio_player)

	body.set_meta(SENSOR_META, self)
	body.add_child(self)


func _physics_process(_dt: float) -> void:
	if _body.freeze:
		return

	var frame := Engine.get_physics_frames()
	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	for i in state.get_contact_count():
		# impulse / mass = equivalent velocity change -> mass-independent tuning
		var dv := state.get_contact_impulse(i).length() / _body.mass
		if dv < min_dv:
			continue

		if (
			frame - _last_impact_physics_frame
			<= EFFECT_COOLDOWN * Engine.get_physics_ticks_per_second()
		):
			return
		_last_impact_physics_frame = frame

		(
			impacted
			. emit(
				dv,
				state.get_contact_local_position(i),
				state.get_contact_local_normal(i),
				state.get_contact_collider_object(i),
			)
		)

		_play_audio(dv)
		_shake_camera(dv, state.get_contact_local_normal(i))
		_spawn_crack_decal(dv, state, i)

		break


func _play_audio(dv: float) -> void:
	if not audio_enabled:
		return

	var vol_offset: float = clampf((dv - min_dv) / IMPACT_DV - 1, 0, 1)
	_audio_player.volume_db = DEFAULT_VOL + vol_offset * VOL_RANGE
	AudioUtil.play_with_pitch(_audio_player)


func _spawn_crack_decal(dv: float, state: PhysicsDirectBodyState3D, i: int) -> void:
	if not decals_enabled or dv < IMPACT_DV:
		return

	var strength = minf(dv / IMPACT_DV * BASE_DECAL_SIZE_FACTOR, MAX_DECAL_SIZE_FACTOR)

	var object := state.get_contact_collider_object(i)
	if object == null:
		return

	if object is CharacterBody3D or object is RigidBody3D:
		return

	(
		CrackDecal
		. spawn(
			object,
			state.get_contact_local_position(i),
			state.get_contact_local_normal(i),
			strength,
		)
	)


func _shake_camera(dv: float, normal: Vector3) -> void:
	if not camera_shake_enabled:
		return

	# near-vertical contact normals are floor/ceiling hits; only walls shake
	if absf(normal.y) > WALL_NORMAL_DOT_UP:
		return

	var cam_ctrl := (
		_body.get_tree().get_first_node_in_group(CameraController.CAMERA_GROUP) as CameraController
	)
	if cam_ctrl == null:
		return

	var dist := _body.global_position.distance_to(cam_ctrl.cam.global_position)
	if dist >= SHAKE_MAX_DIST:
		return

	var impact := minf(dv / SHAKE_DV, 1.0)
	cam_ctrl.add_trauma(SHAKE_STRENGTH * impact * pow(0.5, dist / SHAKE_MAX_DIST))
