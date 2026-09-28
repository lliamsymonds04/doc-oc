extends CharacterBody3D
class_name EnemyController

@export var damage_flash_duration: float = 0.2

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@export var health_bar: HealthBar

const damage_shader = preload("res://shaders/damage_shader.gdshader")

var _shader_mat: ShaderMaterial
var _tween: Tween
var _death_body: RigidBody3D

func _ready() -> void:
	# create the shader material overlay
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = damage_shader
	mesh.material_overlay = _shader_mat

	health_controller.damage_taken.connect(_on_damage_taken)
	health_controller.healed.connect(_on_healed)
	health_controller.died.connect(_on_death)

func take_damage(dmg: float) -> void:
	health_controller.apply_damage(dmg)

	if is_dead():
		_create_fake_body()

func is_dead() -> bool:
	return health_controller.is_dead()

func get_death_body() -> RigidBody3D:
	return _death_body

func _physics_process(dt: float) -> void:
	velocity += get_gravity() * dt

func _on_damage_taken(_dmg: float) -> void:
	if health_bar:
		health_bar.damage_health_bar_tween(health_controller.get_health_float())

	_flash()

func _on_healed(_heal: float) -> void:
	if health_bar:
		health_bar.heal_health_bar_tween(health_controller.get_health_float())

func _on_death() -> void:
	if health_bar:
		health_bar.play_death()

func _create_fake_body() -> void:
	visible = false
	$CollisionShape3D.set_deferred("disabled", true)
	set_physics_process(false)

	_death_body = RigidBody3D.new()

	var corpse_mesh := MeshInstance3D.new()
	corpse_mesh.mesh = mesh.mesh
	_death_body.add_child(corpse_mesh)

	var corpse_shape := CollisionShape3D.new()
	corpse_shape.shape = $CollisionShape3D.shape
	_death_body.add_child(corpse_shape)

	get_parent().add_child(_death_body)
	_death_body.global_transform = global_transform
	_death_body.add_to_group("enemy_corpse")


func _flash() -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", 1.0)
	_tween = create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, damage_flash_duration)
