class_name BarrelExplosionVFX
extends OneShotVFX

@onready var _flash_light: OmniLight3D = $FlashLight
@onready var _sound: AudioStreamPlayer3D = $BlastSound


func play(center: Vector3, contact_point: Vector3, contact_normal: Vector3, radius: float) -> void:
	global_position = center
	restart_emitters()

	var normal := contact_normal.normalized()
	assert(normal.is_normalized())
	var wave := RingEffect.new(Color(1.0, 0.74, 0.43, 0.82))
	add_child(wave)
	wave.play_once(contact_point + normal * 0.06, radius, 0.27, normal)
	_sound.play()

	_flash_light.light_energy = 6.0
	var fade := create_tween()
	(
		fade
		. tween_property(_flash_light, "light_energy", 0.0, 0.17)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	get_tree().create_timer(2.6, false).timeout.connect(queue_free)
