extends RefCounted
class_name AudioUtil

static func play_with_pitch(player: AudioStreamPlayer3D, deviation: float = 0.05) -> void:
	if player == null:
		return
	player.pitch_scale = 1.0 + randf_range(-deviation, deviation)
	player.play()
