extends Panel
class_name SquareButton

@onready var flash_panel: Panel = $Panel

var _flash_tween: Tween


## Fades the flash overlay in and out over [param duration] seconds.
func flash(duration: float = 0.25) -> void:
	if _flash_tween:
		_flash_tween.kill()  # restart cleanly if triggered again mid-fade
	flash_panel.visible = true
	flash_panel.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_panel, "modulate:a", 0.0, duration)
	_flash_tween.tween_callback(_hide_flash_panel)


func _hide_flash_panel() -> void:
	flash_panel.visible = false
