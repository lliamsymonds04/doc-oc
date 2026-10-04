extends CanvasLayer
class_name Hud

@onready var mode_handler: ModeHandler = $ModeButtons

func _on_mode_changed(new_mode: PlayerController.Mode) -> void:
	mode_handler.display_mode(new_mode)
