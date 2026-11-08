class_name EnemySpawner
extends Node3D

## Spawns waves once main.gd calls begin() when the gem breaks.

## A ray hit above this is a prop or a pillar, not the floor.
const FLOOR_SNAP := 0.5
const PROBE_SIZE := 1.4  # fits an enemy capsule
const PROBE_HEIGHT := 1.0  # high enough that the floor is never the hit
## Enemies start this far under the floor and slide up, so nothing pops in mid-air.
const SPAWN_DEPTH := 0.6
const RISE_TIME := 0.45
const MAX_TRIES := 12  # placement attempts before one enemy is given up on

@export var entries: Array[EnemySpawnEntry] = []

@export_group("When")
## Seconds after begin() before the first wave; covers the 3 s pillar rise.
@export var start_delay := 3.0
@export var wave_interval := 10.0
## A single wave when false.
@export var endless := true

@export_group("Where")
## Half-width of the square this node scatters enemies over.
@export var extent := 45.0
## Keeps the middle of the field empty, matching the pillar and crate clears.
@export var clear_radius := 14.0
@export var min_player_distance := 12.0
## 0 randomises every run.
@export var spawn_seed := 0

@export_group("How many")
@export var max_alive := 20

@export_group("Debug")
## Starts the waves without breaking the gem; KEY_NONE disables it.
@export var debug_key: Key = KEY_F8

var _rng := RandomNumberGenerator.new()
var _probe := BoxShape3D.new()
var _running := false
var _wave := 0


func _ready() -> void:
	_rng.seed = spawn_seed if spawn_seed != 0 else randi()


## Ignored while the loop is already running.
func begin() -> void:
	if _running:
		return
	_running = true
	_run()


## Stops the wave loop; enemies already spawned are left alone.
func cancel() -> void:
	_running = false


## Living enemies this spawner owns; corpses waiting on their cleanup timer are excluded.
func alive_count() -> int:
	var alive := 0
	for node in get_tree().get_nodes_in_group(EnemyController.ENEMY_GROUP):
		var enemy := node as EnemyController
		if enemy and not enemy.is_dead() and is_ancestor_of(enemy):
			alive += 1
	return alive


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if debug_key == KEY_NONE or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == debug_key:
		begin()


func _run() -> void:
	await _wait(start_delay)
	while _running:
		_wave += 1
		_spawn_wave()
		if not endless:
			_running = false
			return
		await _wait(wave_interval)


## Pausable, so the pause menu stops the waves too.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _spawn_wave() -> void:
	var budget := max_alive - alive_count()

	for entry in entries:
		if budget <= 0:
			return
		if entry == null or entry.scene == null or entry.first_wave > _wave:
			continue

		var count := mini(_rng.randi_range(entry.count_min, entry.count_max), budget)
		for i in count:
			var spot: Variant = _find_spot()
			if spot == null:
				continue
			_spawn(entry, spot)
			budget -= 1


## Clear floor point for one enemy, or null when every attempt failed.
func _find_spot() -> Variant:
	var player := get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as Node3D

	for attempt in MAX_TRIES:
		var local := Vector3(
			_rng.randf_range(-extent, extent), 0.0, _rng.randf_range(-extent, extent)
		)
		if Vector2(local.x, local.z).length() < clear_radius:
			continue

		var point := to_global(local)
		if player and point.distance_to(player.global_position) < min_player_distance:
			continue

		var ground: Variant = _ground(point)
		if ground == null or not _is_clear(ground):
			continue
		return ground

	return null


## Null when the ray lands on a prop or pillar instead of the floor.
func _ground(point: Vector3) -> Variant:
	var from := point + Vector3.UP * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 150.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["position"].y > FLOOR_SNAP:
		return null
	return hit["position"]


func _is_clear(ground: Vector3) -> bool:
	_probe.size = Vector3.ONE * PROBE_SIZE
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.collision_mask = 1
	params.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * PROBE_HEIGHT)
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _spawn(entry: EnemySpawnEntry, ground: Vector3) -> void:
	var enemy := entry.scene.instantiate() as EnemyController
	if enemy == null:
		push_error("EnemySpawnEntry.scene is not an EnemyController: %s" % entry.scene)
		return

	# the scene's own config is shared by every instance of that scene
	if entry.config:
		enemy.config = entry.config.duplicate()

	var spot := to_local(ground)
	enemy.position = spot - Vector3.UP * SPAWN_DEPTH
	add_child(enemy)

	# the rise has physics off, so the enemy has to come out already aimed
	_face_player(enemy)

	# held still until the rise ends, so gravity cannot drag it back underground
	enemy.set_physics_process(false)
	enemy.hitbox.set_deferred("disabled", true)

	var tween := create_tween()
	tween.tween_property(enemy, "position", spot, RISE_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_release.bind(enemy))


func _release(enemy: EnemyController) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.hitbox.set_deferred("disabled", false)
	enemy.set_physics_process(true)


func _face_player(enemy: EnemyController) -> void:
	var player := get_tree().get_first_node_in_group(PlayerController.PLAYER_GROUP) as Node3D
	if player == null:
		return
	var to := player.global_position - enemy.global_position
	# yaw convention mirrors EnemyController._turn_toward
	enemy.global_rotation.y = atan2(-to.x, -to.z)
