extends CharacterBody3D
class_name EnemyController

@export var damage_flash_duration: float = 0.2

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D

const damage_shader = preload("res://shaders/damage_shader.gdshader")

var _shader_mat: ShaderMaterial
var _tween: Tween

func _ready() -> void:
	# create the shader material overlay
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = damage_shader
	mesh.material_overlay = _shader_mat

func take_damage(dmg: float) -> void:
	health_controller.apply_damage(dmg)
	_flash()

func _flash() -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", 1.0)
	_tween = create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, damage_flash_duration)
