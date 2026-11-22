class_name AudioUtil
extends RefCounted

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"


static func play_with_pitch(player, deviation: float = 0.05) -> void:
	if player == null:
		return
	player.pitch_scale = 1.0 + randf_range(-deviation, deviation)
	player.play()
