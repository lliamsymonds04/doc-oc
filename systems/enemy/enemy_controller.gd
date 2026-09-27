extends CharacterBody3D
class_name EnemyController

@export var damage_flash_duration: float = 0.2

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@export var health_bar: HealthBar

const damage_shader = preload("res://shaders/damage_shader.gdshader")

var _shader_mat: ShaderMaterial
var _tween: Tween

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
	# wait 0.5 seconds before healing
	await get_tree().create_timer(0.5).timeout
	health_controller.health += 0.01
	health_controller.apply_heal(100.0)

func _flash() -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", 1.0)
	_tween = create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, damage_flash_duration)
