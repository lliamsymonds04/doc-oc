extends Node3D
class_name Dummy

@export var enemy_scene: PackedScene
@export var respawn_time: float = 3.0

var respawn_timer: float

func _ready() -> void:
	if enemy_scene:
		spawn_dummy()

func spawn_dummy() -> void:
	var dummy = enemy_scene.instantiate()
	add_child(dummy)

	var enemy_controller: EnemyController = dummy
	var hc = enemy_controller.health_controller
	enemy_controller.health_controller.died.connect(_start_respawn_timer)

	dummy.position = Vector3.UP * 0.1

	await get_tree().process_frame
	hc.health = 0.01
	enemy_controller.health_bar.set_bar_positions(0.0)
	hc.apply_heal(hc.max_health)

func _start_respawn_timer() -> void:
	respawn_timer = respawn_time

func _process(delta: float) -> void:
	if respawn_timer > 0:
		respawn_timer -= delta
		if respawn_timer <= 0:
			spawn_dummy()
			respawn_timer = 0
