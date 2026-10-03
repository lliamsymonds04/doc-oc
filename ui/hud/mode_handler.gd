extends Control
class_name ModeHandler

@onready var active_box: VBoxContainer = $ActiveBox
@onready var active_button: Panel = $ActiveBox/ActivePanel
@onready var inactive_button: Panel = $InactivePanel
@onready var active_icon: TextureRect = $ActiveBox/ActivePanel/Texture
@onready var inactive_icon: TextureRect = $InactivePanel/Texture

@export var mode: int = 0
enum Mode {
	ATTACK,
	GRAB
}

@export_category("Visuals")
@export var attack_icon: Texture2D = preload("res://assets/ui/icons/attack_icon.svg")
@export var grab_icon: Texture2D = preload("res://assets/ui/icons/grab_icon.svg")
@export var pos_tween_duration: float = 0.15
@export var active_box_tween_offset_x: float = 3.0
@export var active_box_tween_offset_y: float = 10.0
@export var inactive_box_tween_offset: float = 7.0


var active_button_tween: Tween
var inactive_button_tween: Tween
var active_box_starting_position: Vector2
var inactive_box_starting_position: Vector2

func _ready() -> void:
	mode = Mode.ATTACK

	active_icon.texture = attack_icon
	inactive_icon.texture = grab_icon

	active_box_starting_position = active_box.position
	inactive_box_starting_position = inactive_button.position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mode-switch"):
		mode = (mode + 1) % 2
		active_icon.texture = [attack_icon, grab_icon][mode]
		inactive_icon.texture = [grab_icon, attack_icon][mode]

		#tween active box up then down
		active_button_tween = get_tree().create_tween()
		active_button_tween.tween_property(active_box, "position", active_box_starting_position
			+ Vector2(active_box_tween_offset_x, -active_box_tween_offset_y), pos_tween_duration)
		active_button_tween.tween_property(active_box, "position", active_box_starting_position, pos_tween_duration)

		#tween inactive box down then up
		inactive_button_tween = get_tree().create_tween()
		inactive_button_tween.tween_property(inactive_button, "position", inactive_box_starting_position
			+ Vector2(0, inactive_box_tween_offset), pos_tween_duration)
		inactive_button_tween.tween_property(inactive_button, "position", inactive_box_starting_position, pos_tween_duration)

		# play the white flash overlay on both buttons
		active_button.flash()
		inactive_button.flash()
