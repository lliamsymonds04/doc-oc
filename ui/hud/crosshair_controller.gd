class_name CrosshairController
extends Control

enum Mode { ATTACK, GRAB, HOLD }

@export var hit_display_time: float = 0.2

var mode_crosshairs: Dictionary[Mode, TextureRect] = {}
var mode: Mode = Mode.ATTACK
var hit_timer: float = 0.0
var enemy_in_range: bool = false

@onready var dot: TextureRect = $Dot
@onready var circle: TextureRect = $Circle
@onready var hit: TextureRect = $Hit
@onready var hold: TextureRect = $Hold


func _ready() -> void:
	mode_crosshairs = {
		Mode.ATTACK: dot,
		Mode.GRAB: circle,
		Mode.HOLD: hold,
	}
	update_crosshair()


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	update_crosshair()


func set_hold(active: bool) -> void:
	## While anything is held, HOLD wins;
	mode = Mode.HOLD if active else Mode.GRAB
	update_crosshair()


## Red tint applies to the attack dot and grab circle, but not hold or hit flash.
func set_enemy_in_range(in_range: bool) -> void:
	enemy_in_range = in_range
	update_crosshair()


## Aiming at a living enemy within attack range -> red, unless holding or flashing.
func _is_red() -> bool:
	return enemy_in_range and mode != Mode.HOLD and hit_timer <= 0.0


func flash_hit() -> void:
	hit_timer = hit_display_time
	update_crosshair()


func _process(delta: float) -> void:
	if hit_timer > 0.0:
		hit_timer -= delta
		if hit_timer <= 0.0:
			update_crosshair()


func update_crosshair() -> void:
	var crosshair: TextureRect = hit if hit_timer > 0.0 else mode_crosshairs[mode]
	var tint_color := Color.RED if _is_red() else Color.WHITE
	for other_crosshair: TextureRect in [dot, circle, hit, hold]:
		other_crosshair.visible = other_crosshair == crosshair
		other_crosshair.modulate = tint_color
