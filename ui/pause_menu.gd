extends Control
class_name PauseMenu

@export_range(0.0, 10.0) var blur_strength = 3.0
@export_range(0.0, 1.0) var color_mix = 0.15
@export_range(0.0, 2.0) var blur_tween_duration = 0.4
@export var button_scene: PackedScene
@export var button_outset: float = 300.0
@export_range(0.05, 2.0) var button_tween_duration := 0.5
@export_range(0.05, 2.0) var button_fade_duration := 0.35

@export_category("Sound")
@export var open_sound: AudioStreamOggVorbis
@export var close_sound: AudioStreamOggVorbis
@export_range(-10.0, 5.0) var sound_volume: float = -5.0

@onready var blur_rect = $BlurRect
@onready var grid = $GridContainer
@onready var audio_player = $AudioStreamPlayer2D

var is_paused: bool = false
var blur_tween: Tween

const BUTTON_NAMES = ["Resume", "Settings", "Main Menu", "Quit"]
const GRID_COLUMNS := 2
const BUTTON_TWEEN_TRANS := Tween.TRANS_CUBIC
const BUTTON_TWEEN_EASE := Tween.EASE_OUT

var buttons: Array[Control] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if button_scene:
		_spawn_buttons()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		is_paused = not is_paused
		get_tree().paused = is_paused

		_blur_tween()

		get_viewport().set_input_as_handled()

func _blur_tween() -> void:
	var blur_target = blur_strength if is_paused else 0.0
	var color_mix_target = color_mix if is_paused else 0.0

	if blur_tween:
		blur_tween.kill()

	blur_tween = create_tween().set_parallel(true)
	blur_tween.tween_property(blur_rect, "material:shader_parameter/blur_amount", blur_target, blur_tween_duration)
	blur_tween.tween_property(blur_rect, "material:shader_parameter/mix_amount", color_mix_target, blur_tween_duration)

	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = true
		_animate_buttons_in()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		blur_tween.finished.connect(func(): visible = false)
		_animate_buttons_out()

func _spawn_buttons() -> void:
	for i in BUTTON_NAMES.size():
		var button = button_scene.instantiate()
		button.text = BUTTON_NAMES[i]

		var wrapper := Control.new()
		wrapper.custom_minimum_size = button.custom_minimum_size

		var dir := _diagonal_dir(i)
		button.position = dir * button_outset
		button.modulate.a = 0.0

		grid.add_child(wrapper)
		wrapper.add_child(button)
		buttons.append(button)

func _play_sound(sound: AudioStreamOggVorbis) -> void:
	if sound != null:
		audio_player.stream = sound
		audio_player.volume_db = sound_volume
		AudioUtil.play_with_pitch(audio_player)

func _diagonal_dir(i: int) -> Vector2:
	var col := i % GRID_COLUMNS
	var row := floori(i / float(GRID_COLUMNS))
	# map cell coords (0,0)..(1,1) to corner directions (-1,-1)..(1,1)
	return Vector2(col, row) * 2.0 - Vector2.ONE

func _animate_buttons_in() -> void:
	_play_sound(open_sound)
	for i in buttons.size():
		var button := buttons[i]

		var tw := create_tween().set_parallel(true)
		tw.tween_property(button, "position", Vector2.ZERO, button_tween_duration).set_trans(BUTTON_TWEEN_TRANS).set_ease(BUTTON_TWEEN_EASE)
		tw.tween_property(button, "modulate:a", 1.0, button_fade_duration)

func _animate_buttons_out() -> void:
	_play_sound(close_sound)
	for i in buttons.size():
		var button := buttons[i]
		var dir := _diagonal_dir(i)

		var tw := create_tween().set_parallel(true)
		tw.tween_property(button, "position", dir * button_outset, button_tween_duration).set_trans(BUTTON_TWEEN_TRANS).set_ease(BUTTON_TWEEN_EASE)
		tw.tween_property(button, "modulate:a", 0.0, button_fade_duration)
