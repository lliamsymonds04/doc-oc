class_name PauseMenu
extends Control

enum View { MAIN, SETTINGS, CONTROLS }

const BUTTON_NAMES = ["Resume", "Settings", "Controls", "Quit"]
const GRID_COLUMNS := 2
const BUTTON_TWEEN_TRANS := Tween.TRANS_CUBIC
const BUTTON_TWEEN_EASE := Tween.EASE_OUT
const SUBMENU_FADE_DURATION := 0.15

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
@export_range(0.0, 1.0) var pause_music_scale: float = 0.25

var is_paused: bool = false
var blur_tween: Tween
var buttons: Array[Control] = []

var _view: View = View.MAIN
var _button_tweens: Array[Tween] = []
var _view_tween: Tween
var _music_duck: float = 1.0

@onready var blur_rect = $BlurRect
@onready var grid = $GridContainer
@onready var settings_panel: PauseSettingsPanel = $SettingsPanel
@onready var controls_panel: PauseControlsPanel = $ControlsPanel
@onready var audio_player = $AudioStreamPlayer2D
@onready var menu_cursor: MenuCursor = $MenuCursor


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GameSettings.apply_audio()
	get_window().focus_entered.connect(_apply_mouse_mode)

	settings_panel.visible = false
	controls_panel.visible = false
	settings_panel.back_pressed.connect(_show_view.bind(View.MAIN))
	controls_panel.back_pressed.connect(_show_view.bind(View.MAIN))

	if button_scene:
		_spawn_buttons()


func _exit_tree() -> void:
	GameSettings.set_music_duck(1.0)


func toggle_pause(new: bool) -> void:
	if not new and _view == View.SETTINGS:
		GameSettings.save()

	is_paused = new
	get_tree().paused = is_paused

	_blur_tween()


func _resume():
	toggle_pause(false)


func _quit() -> void:
	GameSettings.save()
	get_tree().quit()


func _on_button_pressed(button_name: String) -> void:
	match button_name:
		"Resume":
			_resume()
		"Settings":
			_show_view(View.SETTINGS)
		"Controls":
			_show_view(View.CONTROLS)
		"Quit":
			_quit()


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause"):
		# the death screen owns the pointer once the player is down
		if _player_dead():
			return
		if is_paused and _view != View.MAIN:
			_show_view(View.MAIN)
		else:
			toggle_pause(not is_paused)
		get_viewport().set_input_as_handled()


func _show_view(target: View) -> void:
	if _view == View.SETTINGS and target != View.SETTINGS:
		GameSettings.save()

	_view = target
	_kill_view_tween()

	grid.visible = target == View.MAIN
	settings_panel.visible = target == View.SETTINGS
	controls_panel.visible = target == View.CONTROLS

	var active: Control
	match target:
		View.MAIN:
			_kill_button_tweens()
			for button in buttons:
				button.position = Vector2.ZERO
				button.modulate.a = 1.0
			active = grid
		View.SETTINGS:
			settings_panel.refresh()
			active = settings_panel
		View.CONTROLS:
			active = controls_panel

	active.modulate.a = 0.0
	_view_tween = create_tween()
	_view_tween.tween_property(active, "modulate:a", 1.0, SUBMENU_FADE_DURATION)


func _player_dead() -> bool:
	var player := (
		get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as PlayerController
	)
	return player != null and player.is_dead()


func _blur_tween() -> void:
	var blur_target = blur_strength if is_paused else 0.0
	var color_mix_target = color_mix if is_paused else 0.0
	var music_target := pause_music_scale if is_paused else 1.0

	if blur_tween:
		blur_tween.kill()

	blur_tween = create_tween().set_parallel(true)
	blur_tween.tween_property(
		blur_rect, "material:shader_parameter/blur_amount", blur_target, blur_tween_duration
	)
	blur_tween.tween_property(
		blur_rect, "material:shader_parameter/mix_amount", color_mix_target, blur_tween_duration
	)
	blur_tween.tween_method(_set_music_duck, _music_duck, music_target, blur_tween_duration)

	_apply_mouse_mode()

	if is_paused:
		_kill_view_tween()
		_view = View.MAIN
		grid.visible = true
		grid.modulate.a = 1.0
		settings_panel.visible = false
		controls_panel.visible = false
		visible = true
		_animate_buttons_in()
	else:
		blur_tween.finished.connect(_on_close_finished)
		if _view == View.MAIN:
			_animate_buttons_out()
		else:
			_fade_active_submenu_out()


func _on_close_finished() -> void:
	if is_paused:
		return
	visible = false
	settings_panel.visible = false
	controls_panel.visible = false
	grid.visible = true
	_view = View.MAIN


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


func _kill_button_tweens() -> void:
	for tw in _button_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_button_tweens.clear()


func _kill_view_tween() -> void:
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()


func _animate_buttons_in() -> void:
	_play_sound(open_sound)
	_kill_button_tweens()
	for i in buttons.size():
		var button := buttons[i]
		var dir := _diagonal_dir(i)
		button.position = dir * button_outset
		button.modulate.a = 0.0

		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(button, "position", Vector2.ZERO, button_tween_duration)
			. set_trans(BUTTON_TWEEN_TRANS)
			. set_ease(BUTTON_TWEEN_EASE)
		)
		tw.tween_property(button, "modulate:a", 1.0, button_fade_duration)
		_button_tweens.append(tw)


func _animate_buttons_out() -> void:
	_play_sound(close_sound)
	_kill_button_tweens()
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
		_button_tweens.append(tw)


func _fade_active_submenu_out() -> void:
	_play_sound(close_sound)
	_kill_view_tween()
	var active: Control = settings_panel if _view == View.SETTINGS else controls_panel
	_view_tween = create_tween()
	_view_tween.tween_property(active, "modulate:a", 0.0, SUBMENU_FADE_DURATION)


func _set_music_duck(scale: float) -> void:
	_music_duck = scale
	GameSettings.set_music_duck(scale)
