class_name Fireball
extends Node3D

const SCENE := preload("res://systems/enemy/projectile/fireball.tscn")
const IMPACT_SCENE := preload("res://assets/vfx/fireball_impact.tscn")
const IMPACT_LIFETIME: float = 1.2

@export var radius: float = 0.35
@export var max_lifetime: float = 4.0
@export_flags_3d_physics var hit_mask: int = 1 | 2

var _velocity: Vector3
var _life: float
var _damage: float
var _shape := SphereShape3D.new()

@onready var _flame: GPUParticles3D = $Flame


static func spawn(
	config: FireballAttackConfig, parent: Node, from: Vector3, to: Vector3
) -> Fireball:
	var fireball := SCENE.instantiate() as Fireball
	fireball._damage = config.fireball_damage
	parent.add_child(fireball)
	fireball._launch(from, to - from, config.fireball_speed)
	return fireball


func _ready() -> void:
	_shape.radius = radius


func _launch(from: Vector3, dir: Vector3, speed: float) -> void:
	global_position = from
	_velocity = dir.normalized() * speed
	reset_physics_interpolation()

	_flame.emitting = true


func _physics_process(dt: float) -> void:
	_life += dt
	if _life > max_lifetime:
		queue_free()
		return

	var motion := _velocity * dt
	var hit: Variant = RaycastUtil.shape_cast(
		get_world_3d().direct_space_state, _shape, global_position, motion, hit_mask
	)

	if hit == null:
		global_position += motion
		return

	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	global_position = hit["position"]
	_explode(normal, collider)


func _explode(normal: Vector3, collider: Object) -> void:
	var player := collider as PlayerController
	if player != null:
		player.take_damage(_damage)

	var impact := IMPACT_SCENE.instantiate() as ImpactVFX
	# root, not the fireball: the burst has to outlive this node
	get_tree().current_scene.add_child(impact)
	impact.play(global_position, normal)
	# nothing else owns the burst, so it would sit in the tree forever
	get_tree().create_timer(IMPACT_LIFETIME).timeout.connect(impact.queue_free)

	queue_free()
