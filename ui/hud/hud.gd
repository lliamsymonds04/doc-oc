extends CanvasLayer
class_name Hud

@onready var mode_handler: ModeHandler = $ModeButtons
@onready var crosshair_controller: CrosshairController = $Crosshair


func _on_mode_changed(new_mode: PlayerController.Mode) -> void:
	mode_handler.display_mode(new_mode)
	match new_mode:
		PlayerController.Mode.ATTACK:
			crosshair_controller.set_mode(CrosshairController.Mode.ATTACK)
		PlayerController.Mode.GRAB:
			crosshair_controller.set_mode(CrosshairController.Mode.GRAB)


func _on_attack_hit(_hit_point: Vector3, _normal: Vector3, _collider: Object) -> void:
	crosshair_controller.flash_hit()


func _on_grabbing_changed(active: bool) -> void:
	crosshair_controller.set_hold(active)
