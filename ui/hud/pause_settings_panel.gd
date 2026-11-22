class_name PauseSettingsPanel
extends PanelContainer

signal back_pressed

@onready var master_slider: HSlider = $Margin/Content/Sliders/MasterSlider
@onready var master_value: Label = $Margin/Content/Sliders/MasterValue
@onready var music_slider: HSlider = $Margin/Content/Sliders/MusicSlider
@onready var music_value: Label = $Margin/Content/Sliders/MusicValue
@onready var sfx_slider: HSlider = $Margin/Content/Sliders/SfxSlider
@onready var sfx_value: Label = $Margin/Content/Sliders/SfxValue
@onready var sensitivity_slider: HSlider = $Margin/Content/Sliders/SensitivitySlider
@onready var sensitivity_value: Label = $Margin/Content/Sliders/SensitivityValue
@onready var back_button: Button = $Margin/Content/BackButton
@onready var sfx_preview: AudioStreamPlayer2D = $SfxPreview


func _ready() -> void:
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	master_slider.drag_ended.connect(_on_slider_drag_ended)
	music_slider.drag_ended.connect(_on_slider_drag_ended)
	sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	sensitivity_slider.drag_ended.connect(_on_slider_drag_ended)

	back_button.pressed.connect(_on_back_pressed)
	refresh()


func refresh() -> void:
	var master := GameSettings.get_master_volume()
	var music := GameSettings.get_music_volume()
	var sfx := GameSettings.get_sfx_volume()
	var sens := GameSettings.get_sensitivity_scale()

	master_slider.set_value_no_signal(master)
	music_slider.set_value_no_signal(music)
	sfx_slider.set_value_no_signal(sfx)
	sensitivity_slider.set_value_no_signal(sens)

	_update_percent_label(master_value, master)
	_update_percent_label(music_value, music)
	_update_percent_label(sfx_value, sfx)
	_update_sensitivity_label(sens)


func _on_master_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_update_percent_label(master_value, value)


func _on_music_changed(value: float) -> void:
	GameSettings.set_music_volume(value)
	_update_percent_label(music_value, value)


func _on_sfx_changed(value: float) -> void:
	GameSettings.set_sfx_volume(value)
	_update_percent_label(sfx_value, value)


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_sensitivity_scale(value, get_tree())
	_update_sensitivity_label(value)


func _on_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		GameSettings.save()


func _on_sfx_drag_ended(value_changed: bool) -> void:
	if value_changed:
		GameSettings.save()
		AudioUtil.play_with_pitch(sfx_preview)


func _on_back_pressed() -> void:
	GameSettings.save()
	back_pressed.emit()


func _update_percent_label(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)


func _update_sensitivity_label(value: float) -> void:
	sensitivity_value.text = "%.2fx" % value
