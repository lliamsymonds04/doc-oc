class_name PlayerAttackConfig
extends Resource

@export var damage: float = 30.0
@export_group("Timing")
@export var attack_debounce: float = 0.5
@export var tilt_reset_time: float = 0.3

@export_group("Casting")
@export var attack_cast_range: float = 15.0
## Body tilt per punch, in degrees (positive = lean into the punch).
@export var attack_tilt_degrees: float = 15.0
## Largest camera-to-body turn (degrees) that still triggers a forced body
## realignment; larger turns would misbehave through a 180 degree pivot.
@export var max_force_align_turn_degrees: float = 100.0
@export var attack_side_offset: float = 0.1

@export_group("Feedback")
@export var attack_sound: AudioStreamOggVorbis = preload("res://assets/audio/throw_robot_punch.ogg")
@export var surface_hit_sound: AudioStreamOggVorbis = preload("res://assets/audio/metal_attack.ogg")
@export var enemy_hit_sound: AudioStreamOggVorbis = preload("res://assets/audio/cyber_punch.ogg")
@export var hit_vfx_scene: PackedScene = preload("res://assets/vfx/step.tscn")
@export var hit_trauma: float = 0.7
@export_range(-10, 0, 0.5) var hit_fov_kick: float = -2.0
## Wind-up kick on a heavy swing; + = widen. Hits narrow, so the two beats differ.
@export var swing_fov_kick: float = 1.5
## Gem hits widen instead of narrowing, so they get their own kick.
@export var gem_fov_kick: float = 8.0

@export_group("Impulse Physics")
@export var impulse_strength: float = 7.0
@export var impulse_min_y: float = 1.0

@export_group("Knockback")
## Horizontal shove on a living enemy hit, in m/s.
@export var knockback_speed: float = 4.0
## Upward pop, applied only when the enemy is on the ground.
@export var knockback_lift: float = 1.5
## Horizontal multiplier on the shove once the enemy dies, so corpses fly further.
@export var death_knockback_multiplier: float = 2.5

@export_group("Heavy Attack")
## Every Nth punch in a combo becomes a two-armed heavy attack.
@export_range(1, 20, 1) var heavy_attack_every: int = 3
## Idle gap (s) between punches that ends the combo and resets the counter.
@export var combo_reset_time: float = 1.0
## Recovery after a heavy (s), used instead of attack_debounce.
@export var heavy_attack_debounce: float = 1.0
## Forward lean into a heavy swing, in degrees (positive = lean forward).
@export var heavy_tilt_degrees: float = 25.0
## How long the heavy lean holds (s); outlasts tilt_reset_time so a whiff reads.
@export var heavy_tilt_reset_time: float = 0.45
## Blend rate (1/s) of the heavy lean, independent of the slower walk/camera tilt.
@export var heavy_tilt_rate: float = 14.0
## Blend rate (1/s) of the lean falling back to zero; slower reads as follow-through.
@export var heavy_tilt_release_rate: float = 5.0
## Multipliers on the base values above, applied only while a heavy is live.
@export var heavy_damage_multiplier: float = 2.5
@export var heavy_knockback_multiplier: float = 2.0
@export var heavy_lift_multiplier: float = 1.5
@export var heavy_trauma_multiplier: float = 1.4
@export var heavy_fov_kick_multiplier: float = 2.5
@export var heavy_impulse_multiplier: float = 2.0

@export_group("Visuals")
@export var trail_width: float = 0.4
@export var trail_transparency: float = 0.4
