extends Node

## Headless self-checks for the HUD health bar. Run with:
##   godot --headless --path . res://tests/test_health_bar.tscn
## Exits non-zero when any check fails. One check for the rule that can regress
## without looking broken: the pale trail never leads the red bar.

const HEALTH_BAR := preload("res://ui/hud/player_health_bar.tscn")
const EPSILON := 0.0001

var _failures := 0


func _ready() -> void:
	await _test_trail_never_leads()

	if _failures == 0:
		print("All health bar checks passed.")
	else:
		printerr("%d health bar check(s) failed." % _failures)
	get_tree().quit(_failures)


func _test_trail_never_leads() -> void:
	var bar := await _new_bar()
	var health := bar.get_node("Bar/TrailBar/HealthBar") as ProgressBar
	var trail := bar.get_node("Bar/TrailBar") as ProgressBar
	_check_close(health.value, 1.0, "bar starts full")
	# first value must snap: a sentinel of 0 instead of -1 would count 0 -> 250
	bar.set_health(1.0, 250.0)
	_check(bar.get_node("HealthLabel").text == "250/250", "first value snaps the label")

	bar.set_health(0.4, 100.0)
	await _settle(health, 0.4)
	await _settle(trail, 0.4)
	_check_close(health.value, 0.4, "red bar reaches the damage ratio")
	_check(bar.get_node("Bar/TrailBar/Flash").visible, "a hit flashes the bar")
	await _settle_text(bar.get_node("HealthLabel"), "40/100")
	_check(trail.value >= health.value, "trail stays ahead of the red bar while draining")

	bar.set_health(0.9, 100.0)
	_check_close(trail.value, 0.9, "heal snaps the trail up instead of draining it")
	await _settle(health, 0.9)
	_check_close(health.value, 0.9, "red bar reaches the heal ratio")
	_check(trail.value >= health.value, "trail stays ahead of the red bar after a heal")

	bar.queue_free()


func _new_bar() -> PlayerHealthBar:
	var bar: PlayerHealthBar = HEALTH_BAR.instantiate()
	bar.health_tween_duration = 0.05
	bar.trail_tween_duration = 0.05
	bar.health_text_tween_duration = 0.05
	bar.shake_tween_duration = 0.001
	bar.pop_duration = 0.001
	bar.pop_recover_duration = 0.001
	add_child(bar)
	# _ready waits a frame before it has a fill stylebox
	await get_tree().process_frame
	await get_tree().process_frame
	return bar


## Headless frames are not a fixed length, so wait for the value, not a frame count.
func _settle_text(label: Label, expected: String) -> void:
	for _i in range(600):
		if label.text == expected:
			return
		await get_tree().process_frame
	_check(false, "label never reached %s (stuck at %s)" % [expected, label.text])


func _settle(node: Range, target: float) -> void:
	for _i in range(600):
		if absf(node.value - target) <= EPSILON:
			return
		await get_tree().process_frame
	_check(false, "%s never reached %f (stuck at %f)" % [node.name, target, node.value])


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
		return
	_failures += 1
	printerr("[FAIL] ", message)


func _check_close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPSILON, "%s (got %f, want %f)" % [message, actual, expected])
