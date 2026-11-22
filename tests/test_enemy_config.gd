extends Node3D

## Headless checks for enemy config, attacks, and pursuit. Run with:
##   godot --headless --path . res://tests/test_enemy_config.tscn
## Exits non-zero when any check fails.

const ENEMY_SCENE := preload("res://systems/enemy/axe_bot.tscn")
const ARENA_SCENE := preload("res://main.tscn")
const PLAYER_SCENE := preload("res://systems/player/player.tscn")
const BARREL_SCENE := preload("res://assets/barrel_template.tscn")

var _failures := 0


func _ready() -> void:
	_test_missing_attack_falls_back()
	_test_melee_config_maps_to_melee()
	_test_slam_config_maps_to_slam()
	_test_scene_default_uses_melee()
	_test_slam_lead_shrinks_on_short_dive()
	_test_can_start_respects_range()
	await _test_hop_launches()
	_test_damage_camera()
	await _test_player_slam_damage()
	await get_tree().process_frame
	await _test_barrel_blast()
	await get_tree().process_frame
	await _test_barrel_impact_after_throw()
	await get_tree().process_frame
	await _test_enemy_pursuit()

	if _failures == 0:
		print("All enemy config checks passed.")
	else:
		printerr("%d enemy config check(s) failed." % _failures)
	get_tree().quit(_failures)


## A config resource saved without an attack used to leave the enemy holding the
## do-nothing base strategy, so it closed in and never swung.
func _test_missing_attack_falls_back() -> void:
	var enemy := _spawn(EnemyConfig.new())
	_check(enemy._attack is EnemyMeleeAttack, "empty attack slot falls back to melee")
	_despawn(enemy)


func _test_melee_config_maps_to_melee() -> void:
	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	var enemy := _spawn(config)
	_check(enemy._attack is EnemyMeleeAttack, "melee config maps to EnemyMeleeAttack")
	_despawn(enemy)


func _test_slam_config_maps_to_slam() -> void:
	var config := EnemyConfig.new()
	config.attack = SlamAttackConfig.new()
	var enemy := _spawn(config)
	_check(enemy._attack is EnemySlamAttack, "slam config maps to EnemySlamAttack")
	_despawn(enemy)


func _test_scene_default_uses_melee() -> void:
	var enemy := ENEMY_SCENE.instantiate() as EnemyController
	add_child(enemy)
	_check(enemy._attack is EnemyMeleeAttack, "axe_bot.tscn defaults to melee")
	_despawn(enemy)


func _test_slam_lead_shrinks_on_short_dive() -> void:
	var config := EnemyConfig.new()
	var slam_config := SlamAttackConfig.new()
	slam_config.slam_lead = 4.0
	config.attack = slam_config
	var enemy := _spawn(config)
	var slam := enemy._attack as EnemySlamAttack

	slam._dive_height = 4.0
	_check(is_equal_approx(slam._slam_lead(), 4.0), "a full dive keeps the configured lead")

	slam._dive_height = 0.5
	_check(slam._slam_lead() < 1.0, "a short dive pulls the lead in")
	_despawn(enemy)


func _test_can_start_respects_range() -> void:
	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	config.attack.detection_range = 2.0
	var enemy := _spawn(config)
	_check(enemy._attack.can_start(1.0), "attack starts inside detection range")
	_check(not enemy._attack.can_start(2.5), "attack does not start out of range")
	_despawn(enemy)


## A hop has to leave the floor upward and carry the walk speed forward; the
## rest timer is what spaces the arcs out.
func _test_hop_launches() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)
	add_child(ground)

	var config := EnemyConfig.new()
	config.attack = MeleeAttackConfig.new()
	config.hop_height = 1.2
	config.move_speed = 4.0
	config.hop_rest = 0.2
	var enemy := _spawn(config)
	enemy.global_position = Vector3(0.0, 0.1, 0.0)
	for i in 30:
		await get_tree().physics_frame
		if enemy.is_on_floor():
			break

	enemy.velocity = Vector3.ZERO
	var hop := enemy.get_movement() as HopMovement
	var carry := hop.desired_velocity(1.0 / 60.0, 5.0, Vector3.FORWARD)
	_check(enemy.is_on_floor(), "hop test enemy is grounded")
	_check(enemy.velocity.y > 2.0, "a hop launches the body upward")
	_check(is_equal_approx(carry.length(), config.move_speed), "a hop carries walk speed")
	_check(hop._rest > 0.0, "a hop starts the ground rest")

	_despawn(enemy)
	ground.queue_free()


func _test_damage_camera() -> void:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	add_child(player)
	var camera := player.camera_controller
	player.take_damage(10.0, Vector3.RIGHT)

	camera._process(1.0 / 60.0)
	var first_fov := camera.cam.fov
	var shake_position := camera.cam.position
	var shake_roll := camera.cam.rotation.z
	camera._process(0.0)
	_check(
		(
			camera.cam.position.is_equal_approx(shake_position)
			and is_equal_approx(camera.cam.rotation.z, shake_roll)
		),
		"trauma samples don't change without elapsed time"
	)
	var peak_offset := shake_position.length()
	for i in 5:
		camera._process(1.0 / 60.0)
		peak_offset = maxf(peak_offset, camera.cam.position.length())
	_check(peak_offset >= 0.03, "a light hit shakes the camera by at least 3 cm")
	_check(camera.cam.fov < first_fov, "hurt FOV eases in over multiple frames")
	for i in 15:
		camera._process(1.0 / 60.0)
	_check(camera.cam.position.is_zero_approx(), "trauma offset settles back to zero")
	_check(camera.cam.fov < camera.base_fov - 0.5, "hurt FOV remains visible after 350 ms")
	player.queue_free()


func _test_player_slam_damage() -> void:
	var impact_point := Vector3(20.0, 0.0, 0.0)
	var terrain := StaticBody3D.new()
	terrain.position = impact_point
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24, 1, 24)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	terrain.add_child(floor_shape)

	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.5, 5, 4)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(-1.5, 2.5, 0)
	terrain.add_child(wall_shape)
	add_child(terrain)

	var player := PLAYER_SCENE.instantiate() as PlayerController
	add_child(player)
	player.position = impact_point + Vector3.UP * 5.0
	player.set_physics_process(false)
	player.set_state(PlayerController.StateID.AIR)

	var near := _spawn(EnemyConfig.new())
	var behind_wall := _spawn(EnemyConfig.new())
	var far := _spawn(EnemyConfig.new())
	near.position = impact_point + Vector3.RIGHT * 2.0
	behind_wall.position = impact_point + Vector3.LEFT * 3.0
	far.position = impact_point + Vector3.RIGHT * 8.0
	for enemy in [near, behind_wall, far]:
		enemy.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var slam := player.air_state()
	var camera := player.camera_controller
	slam._air_time = player.air.slam_min_air_time
	camera.cam.global_basis = Basis(Vector3.RIGHT, -PI / 2.0)
	camera.cam.global_position = impact_point + Vector3.UP * 8.0 + Vector3.LEFT * 3.0
	_check(slam.get_slam_offset() == Vector3.ZERO, "a wall blocks the dive even with clear aim")
	camera.cam.global_position = impact_point + Vector3.UP * 8.0
	var offset := slam.get_slam_offset()
	_check(offset.is_equal_approx(Vector3.DOWN * 5.0), "clear ground is a valid slam target")

	slam._slam_distance_left = offset.length()
	slam._play_slam_wind()
	player.velocity = offset.normalized() * player.air.slam_speed
	camera._update_fov(0.1)
	var dive_fov := camera.cam.fov
	_check(dive_fov > camera.base_fov, "a vertical slam widens on descent")
	camera._aim_weight = 1.0
	camera._update_fov(0.1)
	var aimed_dive_fov := camera.cam.fov
	_check(aimed_dive_fov < dive_fov, "aiming zooms in during a slam")
	camera._aim_weight = 0.0
	camera._update_fov(0.1)
	dive_fov = camera.cam.fov
	_check(dive_fov > aimed_dive_fov, "releasing aim widens FOV during a slam")
	slam.move_slam(0.25)
	camera._update_fov(1.0 / 60.0)
	_check(
		camera.cam.fov < dive_fov and camera.cam.fov > camera.base_fov,
		"slam impact eases from the dive FOV instead of snapping"
	)

	_check(not player.is_airborne(), "player slam lands on the floor")
	_check(slam._audio_player.playing, "slam triggers the landing sound")
	_check(
		slam._audio_player.global_position.distance_to(impact_point) < 0.5,
		"slam landing sound plays at the impact point"
	)
	camera._update_fov(0.1)
	var impact_fov := camera.cam.fov
	_check(impact_fov < camera.base_fov, "slam zooms in on impact")
	camera._update_fov(0.1)
	_check(camera.cam.fov > impact_fov, "slam FOV widens back toward baseline")
	var slam_trauma := player.camera_controller._trauma
	player.camera_controller.add_trauma(0.1)
	_check(slam_trauma > 1.0, "slam shake exceeds a normal hit")
	_check(player.camera_controller._trauma >= slam_trauma, "regular shake cannot cut slam shake")
	var health := near.health_controller
	_check(
		is_equal_approx(health.max_health - health.health, player.air.slam_damage),
		"slam damages nearby enemy once"
	)
	_check(
		behind_wall.health_controller.health == behind_wall.health_controller.max_health,
		"cover blocks slam damage"
	)
	_check(
		far.health_controller.health == far.health_controller.max_health,
		"slam misses enemies out of range"
	)
	for enemy in [near, behind_wall, far]:
		_despawn(enemy)
	player.queue_free()
	terrain.queue_free()


func _test_barrel_blast() -> void:
	var barrel := BARREL_SCENE.instantiate() as ExplosiveBarrel
	barrel.freeze = true
	add_child(barrel)
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.position = Vector3(0, 0, 2)
	add_child(player)
	player.set_physics_process(false)

	var near := _spawn(EnemyConfig.new())
	var covered := _spawn(EnemyConfig.new())
	near.position = Vector3(3, 0, 0)
	covered.position = Vector3(-3, 0, 0)
	near.set_physics_process(false)
	covered.set_physics_process(false)

	var held := _spawn(EnemyConfig.new())
	held.position = Vector3(0, 0, -3)
	held.initiate_ragdoll(false)
	held.get_ragdoll().collision_layer = PlayerController.HELD_LAYER

	var wall := StaticBody3D.new()
	wall.position = Vector3(-1.5, 0, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 5, 5)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var damage := barrel.blast_damage
	var player_health := player._health_controller.health
	for i in 2:
		player.attack_controller.arm_hit_detected(Vector3.BACK * 0.5, Vector3.BACK, barrel)
	_check(barrel.is_queued_for_deletion(), "a punch detonates an unarmed barrel")
	_check(player._health_controller.health == player_health - damage, "blast damages player once")
	_check(near.is_ragdolled(), "blast ragdolls a surviving enemy")
	var near_health := near.health_controller
	_check(near_health.health == near_health.max_health - damage, "blast damages enemy once")
	var held_health := held.health_controller
	_check(held_health.health == held_health.max_health - damage, "blast damages a held enemy")
	var covered_health := covered.health_controller
	_check(covered_health.health == covered_health.max_health, "cover blocks the barrel blast")
	await get_tree().physics_frame
	var velocity := near.get_ragdoll().linear_velocity
	_check(velocity.x > 0.0 and velocity.y > 0.0, "blast launches the ragdoll outward and up")

	_despawn(near)
	_despawn(covered)
	_despawn(held)
	player.queue_free()
	wall.queue_free()


func _test_barrel_impact_after_throw() -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	for x in [-1.7, 1.7]:
		var wall := StaticBody3D.new()
		wall.position.x = x
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.25, 5, 5)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		wall.add_child(collider)
		fixture.add_child(wall)

	var barrel := BARREL_SCENE.instantiate() as ExplosiveBarrel
	barrel.position.x = 0.8
	barrel.gravity_scale = 0.0
	fixture.add_child(barrel)
	var impacts: Array[float] = []
	ImpactSensor.attach(barrel, barrel.min_impact_dv).impacted.connect(
		func(dv: float, _point: Vector3, _normal: Vector3, _collider: Object) -> void:
			impacts.append(dv)
	)
	barrel.linear_velocity = Vector3.RIGHT * 48.0
	for i in 8:
		await get_tree().physics_frame
		if not impacts.is_empty():
			break
	_check(not impacts.is_empty(), "unarmed barrel reports a hard impact")
	if not impacts.is_empty():
		GrabThrowUtil.apply_throw(
			barrel, 48.0, Basis.looking_at(Vector3.LEFT), PlayerGrabConfig.new()
		)
		for i in 8:
			await get_tree().physics_frame
			if not is_instance_valid(barrel):
				break
		_check(not is_instance_valid(barrel), "thrown barrel explodes during the impact cooldown")
	fixture.queue_free()


func _test_enemy_pursuit() -> void:
	var arena := ARENA_SCENE.instantiate() as Node3D
	var boxes: BoxHandler = arena.get_node("BoxHandler")
	boxes.target_boxes = 1
	boxes.spawn_seed = 1
	var pillars: PillarHandler = arena.get_node("PillarHandler")
	pillars.target_pillars = 1
	add_child(arena)
	var player: PlayerController = arena.get_node("Player")
	player.set_physics_process(false)
	for i in 120:
		await get_tree().physics_frame
		if boxes.get_child_count() == 1:
			break

	var crate := boxes.get_child(0) as RigidBody3D if boxes.get_child_count() == 1 else null
	_check(crate != null, "pursuit arena has a crate")
	if crate == null:
		arena.queue_free()
		return
	crate.freeze = true
	var floor_node: CSGBox3D = arena.get_node("Floor")
	var floor_y := floor_node.global_position.y + floor_node.size.y * 0.5
	var crate_base := Vector3(crate.global_position.x, floor_y, crate.global_position.z)
	var start := crate_base + Vector3.LEFT * 4.0
	var goal := crate_base + Vector3.RIGHT * 4.0
	player.global_position = goal

	var map := arena.get_world_3d().navigation_map
	var deadline := Time.get_ticks_msec() + 3000
	var path := PackedVector3Array()
	while path.size() < 3 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			path = NavigationServer3D.map_get_path(map, start, goal, true)
	_check(path.size() >= 3, "arena bakes a route around the crate")

	var enemy := _spawn(EnemyConfig.new())
	enemy.global_position = start
	for i in 240:
		await get_tree().physics_frame
		if enemy.global_position.x > crate_base.x + 1.0:
			break
	_check(enemy.global_position.x > crate_base.x + 1.0, "axe bot rounds the crate")
	_despawn(enemy)

	var pillar := pillars.pillars[0]
	pillar.global_position = Vector3(0.0, 0.0, -60.0)
	pillars.pillars_risen = true
	var face := pillar.global_position + Vector3.LEFT * pillars.cell_size * 0.5
	player.global_position = face + Vector3(-2.0, 4.0, -1.5)
	player.rotation.y = -PI * 0.5
	player.set_state(PlayerController.StateID.WALL_CLIMB)
	enemy = _spawn(EnemyConfig.new())
	enemy.global_position = face + Vector3(-0.75, floor_y, -1.5)
	for i in 90:
		await get_tree().physics_frame
		if enemy.global_position.y > 1.0:
			break
	_check(enemy.global_position.y > 1.0, "axe bot starts climbing after the player")

	player.global_position.z += 3.0
	var health := player._health_controller.health
	for i in 180:
		await get_tree().physics_frame
		if player._health_controller.health < health:
			break
	_check(
		absf(enemy.global_position.z - player.global_position.z) < 1.5,
		"axe bot follows the player sideways on the wall"
	)
	_check(player._health_controller.health < health, "axe bot lands a swing while on the wall")
	_despawn(enemy)
	arena.queue_free()


## `config` is assigned after the scene's `_init()` and before `_ready()`, which
## is the order that broke the old fallback.
func _spawn(config: EnemyConfig) -> EnemyController:
	var enemy := ENEMY_SCENE.instantiate() as EnemyController
	enemy.config = config
	add_child(enemy)
	return enemy


func _despawn(enemy: EnemyController) -> void:
	enemy.get_ragdoll().queue_free()
	enemy.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
		return
	_failures += 1
	printerr("[FAIL] ", message)
