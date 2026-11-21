class_name HealingGemSpawner
extends Node3D

## Drops a healing gem on a random risen pillar, then again a minute after it breaks.

## Emitted when a gem is broken, carrying the health it is worth.
signal heal_player(amount: float)

@export var pillars: PillarHandler
@export var gem_scene: PackedScene = preload("res://systems/gem/healing_gem.tscn")
@export var heal_amount := 50.0
## Seconds into the run before the first gem shows.
@export var first_delay := 30.0
## Wait after a gem breaks before the next one.
@export var respawn_delay := 60.0
## Clearance above the pillar top, so the bobbing gem never clips the block.
@export var hover_height := 2.0

var _running := false


## Called when the run starts; ignored while the loop is already running.
func begin() -> void:
	if _running:
		return
	_running = true
	_loop()


func _loop() -> void:
	await _wait(first_delay)
	while _running:
		var gem := _spawn()
		if gem == null:
			return
		await gem.hit_landed
		var shockwave := RingEffect.new(Color(0.25, 1.0, 0.45))
		add_child(shockwave)
		shockwave.play_once(gem.global_position, 8.0, 0.55)
		heal_player.emit(heal_amount)
		await _wait(respawn_delay)


## Pausable, so the pause menu stops the respawn clock too.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


## Null when there is nowhere to put it.
func _spawn() -> FloatingGem:
	if pillars == null or pillars.pillars.is_empty():
		return null
	var pillar: Node3D = pillars.pillars[randi() % pillars.pillars.size()]
	var box := (pillar.get_node("CollisionShape3D").shape as BoxShape3D).size

	var gem := gem_scene.instantiate() as FloatingGem
	gem.position = to_local(pillar.global_position + Vector3.UP * (box.y + hover_height))
	add_child(gem)
	return gem
