class_name SmokeSquare
extends Node3D

## Flat square of ground smoke covering a pillar's footprint. One instance per
## pillar; it fires a single burst, then frees itself.

## A one-shot burst spreads its births across the lifetime, so this many
## lifetimes covers the last puff being born and fading.
const FREE_AFTER_LIFETIMES := 1.5


## Half the side of the square footprint, in world units.
func play(half_size: float) -> void:
	var smoke := $Smoke as GPUParticles3D
	var mat := smoke.process_material as ParticleProcessMaterial
	mat.emission_box_extents = Vector3(half_size, 0.05, half_size)
	smoke.reset_physics_interpolation()
	smoke.restart()
	var timer := get_tree().create_timer(smoke.lifetime * FREE_AFTER_LIFETIMES)
	timer.timeout.connect(queue_free)
