class_name PlayerAttackConfig
extends Resource

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

@export_group("Feedback")
@export var attack_sound: AudioStreamOggVorbis = preload("res://assets/audio/small_servo.ogg")
@export var hit_vfx_scene: PackedScene = preload("res://assets/vfx/step.tscn")
