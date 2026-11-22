class_name Hud
extends CanvasLayer

@onready var mode_handler: ModeHandler = $ModeButtons
@onready var crosshair_controller: CrosshairController = $Crosshair
@onready var run_timer: RunTimer = $RunTimer
@onready var health_bar: PlayerHealthBar = $PlayerHealthBar
@onready var death_screen: DeathScreen = $DeathScreen
@onready var damage_indicator: DamageIndicator = $DamageIndicator


func start_timer() -> void:
	run_timer.start()


func _on_player_died() -> void:
	run_timer.stop()
	death_screen.show_result(run_timer.text, EnemyController.kill_count)


func _on_player_health_changed(current: float, max_health: float) -> void:
	var ratio := current / max_health
	health_bar.set_health(ratio, max_health)
	damage_indicator.set_health(ratio)


func _on_player_damage_direction(angle: float, weight: float) -> void:
	damage_indicator.flash(angle, weight)


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


func _on_aim_at_enemy_changed(in_range: bool) -> void:
	crosshair_controller.set_enemy_in_range(in_range)


func _on_slam_target_changed(active: bool) -> void:
	crosshair_controller.set_slam_target(active)
