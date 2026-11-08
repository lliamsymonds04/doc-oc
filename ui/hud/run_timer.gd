class_name RunTimer
extends Label

## Run clock. Hidden until start() is called on the first gem hit, then counts
## up as mm:ss and freezes where it is when the player dies.

@export_category("Intro")
## Pixels the clock slides down from; it fades in over the same span.
@export var intro_distance: float = 40.0
@export var intro_time: float = 0.4

var _elapsed := 0.0
var _running := false
var _rest_y := 0.0
var _intro: Tween


func _ready() -> void:
	_rest_y = position.y


func start() -> void:
	_elapsed = 0.0
	_running = true
	visible = true
	_refresh()
	_play_intro()


func stop() -> void:
	_running = false


func _play_intro() -> void:
	if _intro != null:
		_intro.kill()
	position.y = _rest_y - intro_distance
	modulate.a = 0.0
	_intro = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_intro.tween_property(self, "position:y", _rest_y, intro_time)
	_intro.tween_property(self, "modulate:a", 1.0, intro_time)


func _process(dt: float) -> void:
	if not _running:
		return
	_elapsed += dt
	_refresh()


func _refresh() -> void:
	var total := int(_elapsed)
	text = "%02d:%02d" % [total / 60, total % 60]
