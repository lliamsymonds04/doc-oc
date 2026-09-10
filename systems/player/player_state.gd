class_name PlayerState
extends RefCounted

var player: PlayerController
var input_dir: Vector2

func _init(p: PlayerController) -> void:
	player = p

func enter() -> void:
	pass

func exit() -> void:
	pass

func physics_update(_dt: float) -> void:
	pass

func frame_update(_dt: float) -> void:
	pass
