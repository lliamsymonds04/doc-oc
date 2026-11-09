class_name DeathScreen
extends Control

## Fades in over the run once the player dies and offers a restart.

## Seconds the corpse falls before the screen starts to fade in.
@export var fade_delay: float = 1.0
@export var fade_time: float = 0.8

@onready var time_value: Label = $Center/Stats/TimeValue
@onready var kills_value: Label = $Center/Stats/KillsValue
@onready var play_again_button: Button = $Center/PlayAgain


func _ready() -> void:
	play_again_button.disabled = true
	play_again_button.pressed.connect(_on_play_again)


func show_result(time_text: String, kills: int) -> void:
	time_value.text = time_text
	kills_value.text = str(kills)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var tween := create_tween()
	tween.tween_interval(fade_delay)
	tween.tween_property(self, "modulate:a", 1.0, fade_time)
	tween.tween_callback(_reveal_play_again)


## Keyboard fallback for when the pointer is not usable.
func _reveal_play_again() -> void:
	play_again_button.disabled = false
	play_again_button.grab_focus()


func _on_play_again() -> void:
	get_tree().reload_current_scene()
