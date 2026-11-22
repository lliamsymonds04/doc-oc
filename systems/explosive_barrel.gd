class_name ExplosiveBarrel
extends RigidBody3D

const BURST_SCENE := preload("res://assets/vfx/barrel_explosion.tscn")
const SHAKE_RANGE := 40.0
const FULL_SHAKE_RANGE := 15.0

@export_range(0.1, 40.0, 0.1, "or_greater", "suffix:m/s") var min_impact_dv := 10.0
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var blast_radius := 5.0
@export var blast_damage := 50.0
@export var blast_impulse := 36.0

var armed := false:
	set(value):
		armed = value
		if armed:
			_armed_frame = Engine.get_physics_frames()

var _armed_frame := -1


func _ready() -> void:
	var sensor := ImpactSensor.attach(self, min_impact_dv)
	sensor.decals_enabled = false
	sensor.hard_contact.connect(_on_impact)
	sleeping_state_changed.connect(_on_sleep_changed)


func _on_sleep_changed() -> void:
	if sleeping:
		armed = false


func _on_impact(point: Vector3, normal: Vector3) -> void:
	# On the release tick the sensor can still see contacts from before the throw.
	if armed and Engine.get_physics_frames() > _armed_frame:
		detonate(point, normal)


func detonate(point: Vector3, normal: Vector3) -> void:
	if is_queued_for_deletion():
		return
	queue_free()
	armed = false

	var center := global_position
	_damage_targets(center)
	_shake_camera(center)

	var burst := BURST_SCENE.instantiate() as BarrelExplosionVFX
	get_tree().current_scene.add_child(burst)
	burst.play(center, point, normal, blast_radius)


func _shake_camera(center: Vector3) -> void:
	var camera := (
		get_tree().get_first_node_in_group(CameraController.CAMERA_GROUP) as CameraController
	)
	if camera == null:
		return

	var distance := camera.cam.global_position.distance_to(center)
	var falloff := 1.0 - smoothstep(FULL_SHAKE_RANGE, SHAKE_RANGE, distance)
	if falloff > 0.0:
		camera.play_heavy_impact(1.5 * falloff)


func _damage_targets(center: Vector3) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = sphere
	overlap.transform = Transform3D(Basis.IDENTITY, center)
	overlap.collision_mask = (
		EnemyController.ENEMY_LAYER | PlayerController.PLAYER_LAYER | PlayerController.HELD_LAYER
	)

	var space := get_world_3d().direct_space_state
	var damaged := {}
	for hit in space.intersect_shape(overlap):
		var body := hit.collider as Node3D
		var player := body as PlayerController
		var enemy := EnemyUtil.resolve_enemy(body) if player == null else null
		var target: Node3D = player if player != null else enemy
		if target == null or damaged.has(target):
			continue
		if player.is_dead() if player != null else enemy.is_dead():
			continue

		var hitbox := player.hitbox if player != null else enemy.hitbox
		var target_pos := body.to_global(hitbox.position)
		var cover := PhysicsRayQueryParameters3D.create(center, target_pos, 1, [get_rid()])
		if not space.intersect_ray(cover).is_empty():
			continue

		damaged[target] = true
		var direction := (target_pos - center).normalized()
		if player != null:
			player.take_damage(blast_damage, direction)
		else:
			_blast_enemy(enemy, direction)


func _blast_enemy(enemy: EnemyController, direction: Vector3) -> void:
	enemy.take_damage(blast_damage)
	enemy.initiate_ragdoll(false)
	direction.y = maxf(direction.y, 0.45)
	var ragdoll := enemy.get_ragdoll()
	# The proxy is unfrozen by a deferred call when ragdoll activates.
	ragdoll.apply_central_impulse.call_deferred(direction.normalized() * blast_impulse)
	if not enemy.is_dead() and ragdoll.collision_layer != PlayerController.HELD_LAYER:
		enemy.initiate_get_up.call_deferred()
