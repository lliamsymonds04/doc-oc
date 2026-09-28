class_name PlayerAttackConfig
extends Resource

@export var damage: float = 30.0
@export_group("Timing")
@export var attack_debounce: float = 0.5
@export var tilt_reset_time: float = 0.3

@export_group("Casting")
## How far the punch raycast reaches, in meters.
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
@export_range(0, -10, -0.5) var hit_fov_kick: float = -2.0

@export_group("Impulse Physics")
@export var impulse_strength: float = 7.0
@export var impulse_min_y: float = 1.0
