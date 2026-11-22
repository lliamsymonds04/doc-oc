class_name GameSettings
extends RefCounted

## Persistent user settings for audio bus volumes and camera sensitivity.

const CONFIG_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_CONTROLS := "controls"

const DEFAULT_VOLUME := 1.0
const DEFAULT_SENSITIVITY_SCALE := 1.0
const MIN_SENSITIVITY_SCALE := 0.1
const MAX_SENSITIVITY_SCALE := 3.0

static var _loaded := false
static var _master_volume := DEFAULT_VOLUME
static var _music_volume := DEFAULT_VOLUME
static var _music_duck := 1.0
static var _sfx_volume := DEFAULT_VOLUME
static var _sensitivity_scale := DEFAULT_SENSITIVITY_SCALE


static func get_master_volume() -> float:
	_ensure_loaded()
	return _master_volume


static func get_music_volume() -> float:
	_ensure_loaded()
	return _music_volume


static func get_sfx_volume() -> float:
	_ensure_loaded()
	return _sfx_volume


static func get_sensitivity_scale() -> float:
	_ensure_loaded()
	return _sensitivity_scale


static func set_master_volume(value: float) -> void:
	_ensure_loaded()
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_bus(&"Master", _master_volume)


static func set_music_volume(value: float) -> void:
	_ensure_loaded()
	_music_volume = clampf(value, 0.0, 1.0)
	_apply_bus(AudioUtil.MUSIC_BUS, _music_volume * _music_duck)


static func set_music_duck(scale: float) -> void:
	_ensure_loaded()
	_music_duck = clampf(scale, 0.0, 1.0)
	_apply_bus(AudioUtil.MUSIC_BUS, _music_volume * _music_duck)


static func set_sfx_volume(value: float) -> void:
	_ensure_loaded()
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(AudioUtil.SFX_BUS, _sfx_volume)


static func set_sensitivity_scale(value: float, tree: SceneTree = null) -> void:
	_ensure_loaded()
	_sensitivity_scale = clampf(value, MIN_SENSITIVITY_SCALE, MAX_SENSITIVITY_SCALE)
	if tree != null:
		apply_sensitivity(tree)


static func apply_audio() -> void:
	_ensure_loaded()
	_apply_bus(&"Master", _master_volume)
	_apply_bus(AudioUtil.MUSIC_BUS, _music_volume * _music_duck)
	_apply_bus(AudioUtil.SFX_BUS, _sfx_volume)


static func apply_sensitivity(tree: SceneTree) -> void:
	_ensure_loaded()
	for node in tree.get_nodes_in_group(CameraController.CAMERA_GROUP):
		var camera := node as CameraController
		if camera != null:
			camera.apply_sensitivity_scale(_sensitivity_scale)


static func save() -> void:
	_ensure_loaded()
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_AUDIO, "master_volume", _master_volume)
	cfg.set_value(SECTION_AUDIO, "music_volume", _music_volume)
	cfg.set_value(SECTION_AUDIO, "sfx_volume", _sfx_volume)
	cfg.set_value(SECTION_CONTROLS, "sensitivity_scale", _sensitivity_scale)
	cfg.save(CONFIG_PATH)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_master_volume = clampf(
		float(cfg.get_value(SECTION_AUDIO, "master_volume", DEFAULT_VOLUME)), 0.0, 1.0
	)
	_music_volume = clampf(
		float(cfg.get_value(SECTION_AUDIO, "music_volume", DEFAULT_VOLUME)), 0.0, 1.0
	)
	_sfx_volume = clampf(
		float(cfg.get_value(SECTION_AUDIO, "sfx_volume", DEFAULT_VOLUME)), 0.0, 1.0
	)
	_sensitivity_scale = clampf(
		float(cfg.get_value(SECTION_CONTROLS, "sensitivity_scale", DEFAULT_SENSITIVITY_SCALE)),
		MIN_SENSITIVITY_SCALE,
		MAX_SENSITIVITY_SCALE
	)


static func _apply_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var muted := linear <= 0.0001
	AudioServer.set_bus_mute(idx, muted)
	if not muted:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
