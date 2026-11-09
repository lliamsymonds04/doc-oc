class_name PauseMenu
extends Control

const BUTTON_NAMES = ["Resume", "Settings", "Main Menu", "Quit"]
const GRID_COLUMNS := 2
const BUTTON_TWEEN_TRANS := Tween.TRANS_CUBIC
const BUTTON_TWEEN_EASE := Tween.EASE_OUT

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

var is_paused: bool = false
var blur_tween: Tween
var buttons: Array[Control] = []

@onready var blur_rect = $BlurRect
@onready var grid = $GridContainer
@onready var audio_player = $AudioStreamPlayer2D
@onready var menu_cursor: MenuCursor = $MenuCursor


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	get_window().focus_entered.connect(_apply_mouse_mode)

	if button_scene:
		_spawn_buttons()


func toggle_pause(new: bool) -> void:
	is_paused = new
	get_tree().paused = is_paused

	_blur_tween()


func _placeholder() -> void:
	pass


func _resume():
	toggle_pause(false)


func _quit() -> void:
	get_tree().quit()


func _on_button_pressed(button_name: String) -> void:
	match button_name:
		"Resume":
			_resume()
		"Settings":
			_placeholder()
		"Main Menu":
			_placeholder()
		"Quit":
			_quit()


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		# the death screen owns the pointer once the player is down
		if _player_dead():
			return
		toggle_pause(not is_paused)
		get_viewport().set_input_as_handled()


func _player_dead() -> bool:
	var player := (
		get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
	)
	return player != null and player.is_dead()


func _blur_tween() -> void:
	var blur_target = blur_strength if is_paused else 0.0
	var color_mix_target = color_mix if is_paused else 0.0

	if blur_tween:
		blur_tween.kill()

	blur_tween = create_tween().set_parallel(true)
	blur_tween.tween_property(
		blur_rect, "material:shader_parameter/blur_amount", blur_target, blur_tween_duration
	)
	blur_tween.tween_property(
		blur_rect, "material:shader_parameter/mix_amount", color_mix_target, blur_tween_duration
	)

	_apply_mouse_mode()

	if is_paused:
		visible = true
		_animate_buttons_in()
	else:
		blur_tween.finished.connect(func(): visible = false)
		_animate_buttons_out()


func _apply_mouse_mode() -> void:
	# regaining focus must not capture the pointer back from the death screen
	if _player_dead():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		menu_cursor.set_native_hidden(false)
		return

	if is_paused:
		# visible pointers keep moving; the native image is blanked so MenuCursor is
		# the only cursor drawn. CONFINED_HIDDEN freezes the pointer on Wayland.
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
		menu_cursor.set_native_hidden(true)
		return

	menu_cursor.set_native_hidden(false)

	# re-setting CAPTURED is a no-op, so bounce through VISIBLE to force a fresh grab
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_buttons() -> void:
	for i in BUTTON_NAMES.size():
		var button = button_scene.instantiate()
		button.text = BUTTON_NAMES[i]

		var wrapper := Control.new()
		wrapper.custom_minimum_size = button.custom_minimum_size

		var dir := _diagonal_dir(i)
		button.position = dir * button_outset
		button.modulate.a = 0.0

		button.pressed.connect(_on_button_pressed.bind(BUTTON_NAMES[i]))

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
		(
			tw
			. tween_property(button, "position", Vector2.ZERO, button_tween_duration)
			. set_trans(BUTTON_TWEEN_TRANS)
			. set_ease(BUTTON_TWEEN_EASE)
		)
		tw.tween_property(button, "modulate:a", 1.0, button_fade_duration)


func _animate_buttons_out() -> void:
	_play_sound(close_sound)
	for i in buttons.size():
		var button := buttons[i]
		var dir := _diagonal_dir(i)

		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(button, "position", dir * button_outset, button_tween_duration)
			. set_trans(BUTTON_TWEEN_TRANS)
			. set_ease(BUTTON_TWEEN_EASE)
		)
		tw.tween_property(button, "modulate:a", 0.0, button_fade_duration)
