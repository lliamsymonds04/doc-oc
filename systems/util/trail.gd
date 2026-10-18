@tool

extends MeshInstance3D

const CURVE_SAMPLES := 16
const TOTAL_MAX_POINTS := 100

@export_range(3, 100, 2, "prefer_slider") var max_points: int = 30:
	set = _update_max_points

@export var color: Color = Color(0.8, 0.8, 0.8, 0.5):
	set = _update_color

@export var billboard: bool = false:
	set = _update_billboard

@export var width_curve: Curve:
	set = _update_curve

@export var trail_width: float = 0.2:
	set = _update_width

var position_history: Array[Vector3] = []


func _update_max_points(value: int) -> void:
	max_points = value
	if not is_inside_tree() or material_override == null:
		return

	material_override.set_shader_parameter("MAX_POINTS", value)
	_adjust_history_size()


func _update_color(value: Color) -> void:
	color = value
	if not is_inside_tree() or material_override == null:
		return

	material_override.set_shader_parameter("TRAIL_COLOR", value)


func _update_billboard(value: bool) -> void:
	billboard = value
	if not is_inside_tree() or material_override == null:
		return

	material_override.set_shader_parameter("BILLBOARD", value)


func _update_curve(value: Curve) -> void:
	width_curve = value
	if not is_inside_tree() or material_override == null or width_curve == null:
		return

	# Bake the Curve into a 1-pixel-tall texture the shader can sample.
	var bytes := PackedByteArray()
	bytes.resize(CURVE_SAMPLES)
	for i in CURVE_SAMPLES:
		var t := float(i) / float(CURVE_SAMPLES - 1)
		bytes[i] = clampi(int(round(width_curve.sample_baked(t) * 255.0)), 0, 255)

	var image := Image.create_from_data(CURVE_SAMPLES, 1, false, Image.FORMAT_R8, bytes)
	material_override.set_shader_parameter("WIDTH_CURVE", ImageTexture.create_from_image(image))


func _update_width(value: float) -> void:
	trail_width = value
	if not is_inside_tree() or material_override == null:
		return

	material_override.set_shader_parameter("TRAIL_WIDTH", value)


func _adjust_history_size() -> void:
	if position_history.size() != max_points:
		position_history.resize(max_points)
		position_history.fill(global_position)


func _ready() -> void:
	_adjust_history_size()
	_update_max_points(max_points)
	_update_color(color)
	_update_billboard(billboard)
	_update_curve(width_curve)
	_update_width(trail_width)


func _process(_delta: float) -> void:
	position_history.push_front(global_position)
	position_history.resize(max_points)

	if material_override:
		var packed := PackedVector3Array(position_history)
		packed.resize(TOTAL_MAX_POINTS)
		material_override.set_shader_parameter("positions", packed)
