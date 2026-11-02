class_name RingEffect
extends MeshInstance3D

const SHADER_PATH: String = "res://shaders/ring_shader.gdshader"
const HALO_HEIGHT: float = 0.3
const SEGMENTS: int = 48
const GROW_TIME: float = 0.25
const FADE_TIME: float = 0.2
const INTENSITY: float = 1.5
const COLOR: Color = Color(1.0, 0.49411765, 0.05882353)

var _material := ShaderMaterial.new()
var _tween: Tween


func _init() -> void:
	mesh = _halo_mesh()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter("CURVE", _alpha_curve())
	_material.set_shader_parameter("RING_COLOR", COLOR)
	_material.set_shader_parameter("MESH_HEIGHT", HALO_HEIGHT)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func show_at(pos: Vector3, radius: float, grow_time: float = GROW_TIME) -> void:
	global_position = pos + Vector3.UP * HALO_HEIGHT * 0.5
	visible = true
	_set_brightness(1.0)

	scale = Vector3(0.001, 1.0, 0.001)
	reset_physics_interpolation()
	_restart_tween()
	var grow := _tween.tween_property(self, "scale", Vector3(radius, 1.0, radius), grow_time)
	grow.set_trans(Tween.TRANS_CUBIC)
	grow.set_ease(Tween.EASE_OUT)


func fade_out() -> void:
	if not visible:
		return

	_restart_tween()
	_tween.tween_method(_set_brightness, 1.0, 0.0, FADE_TIME)
	_tween.tween_callback(_on_faded)


func _set_brightness(amount: float) -> void:
	_material.set_shader_parameter("INTENSITY", INTENSITY * amount)


func _on_faded() -> void:
	visible = false


func _restart_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()


static func _halo_mesh() -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = HALO_HEIGHT
	cylinder.radial_segments = SEGMENTS
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	return cylinder


static func _alpha_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))

	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
