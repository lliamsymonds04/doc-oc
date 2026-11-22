@tool
class_name TextureButtonHelper
extends Button

@export var hover_color := Color(1.25, 1.25, 1.25)
@export var pressed_color := Color(0.7, 0.7, 0.7)

@export_category("Tweens")
@export var hover_size_factor := 1.05
@export var scale_tween_duration := 0.1
@export var pressed_size_factor := 0.95

@export_category("Sounds")
@export var hover_sound: AudioStreamOggVorbis
@export var pressed_sound: AudioStreamOggVorbis
@export_range(-10, 5) var hover_volume = -5.0
@export_range(-10, 5) var pressed_volume = 0.0

var effect_tween: Tween
var hovered := false

@onready var audio_player = $AudioStreamPlayer2D


func _ready() -> void:
	self.mouse_entered.connect(_mouse_entered)
	self.mouse_exited.connect(_mouse_exited)
	self.button_down.connect(_on_button_down)
	self.button_up.connect(_on_button_up)
	self.resized.connect(_update_pivot)

	_update_pivot()

	# only texture styleboxes can be tinted per-state; plain theme buttons keep their own look
	var normal := get_theme_stylebox("normal") as StyleBoxTexture
	if normal == null:
		return

	var variants := {
		"hover": hover_color,
		"pressed": pressed_color,
	}
	for state: String in variants:
		var sb: StyleBoxTexture = normal.duplicate()
		sb.modulate_color = variants[state]
		add_theme_stylebox_override(state, sb)


func _update_pivot() -> void:
	pivot_offset = size / 2.0  # scale tweens grow from the centre, not the corner


func _animate_scale(t: float) -> void:
	if effect_tween != null:
		effect_tween.stop()
	effect_tween = create_tween()
	effect_tween.tween_property(self, "scale", Vector2(t, t), scale_tween_duration)


func _play_sound(sound: AudioStreamOggVorbis, volume: float) -> void:
	if sound != null:
		audio_player.stream = sound
		audio_player.volume_db = volume
		AudioUtil.play_with_pitch(audio_player)


func _mouse_entered() -> void:
	if disabled:
		return
	_animate_scale(hover_size_factor)
	hovered = true
	_play_sound(hover_sound, hover_volume)


func _mouse_exited() -> void:
	_animate_scale(1.0)
	hovered = false


func _on_button_down() -> void:
	if disabled:
		return
	_animate_scale(pressed_size_factor)
	_play_sound(pressed_sound, pressed_volume)


func _on_button_up() -> void:
	_animate_scale(hover_size_factor if is_hovered() else 1.0)
