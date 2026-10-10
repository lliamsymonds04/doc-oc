class_name DamageFlashUtil
extends RefCounted

const DAMAGE_SHADER := preload("res://shaders/damage_shader.gdshader")

var flash_duration: float

var _node: Node
var _shader_mat: ShaderMaterial
var _tween: Tween


func _init(node: Node, mesh: MeshInstance3D, duration: float = 0.2) -> void:
	_node = node
	flash_duration = duration

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = DAMAGE_SHADER
	mesh.material_overlay = _shader_mat


func flash(strength: float = 1.0) -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", clampf(strength, 0.0, 1.0))
	_tween = _node.create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, flash_duration)
