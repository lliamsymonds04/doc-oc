@tool

class_name Trail
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

@export var trail_lifetime: float = 0.5

# When false, existing points keep aging out but no new ones are recorded;
# re-enabling starts a fresh trail with no leftover tail.
@export var emitting: bool = true:
	set = _set_emitting

# Records by distance, not frames, so trail length is framerate-independent.
@export var min_point_distance: float = 0.05

# When set, the trail follows this node instead of its own transform, so it can
# be spawned at the scene root and outlive its target.
@export var target: Node3D

var position_history: Array[Vector3] = []
var _expiry_times: Array[float] = []
var _last_recorded: Vector3
var _elapsed := 0.0


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
	if not is_inside_tree() or material_override == null:
		return

	# Bake the Curve into a 1-pixel-tall texture the shader can sample; no
	# curve assigned means a linear 1 -> 0 taper toward the tail.
	var bytes := PackedByteArray()
	bytes.resize(CURVE_SAMPLES)
	for i in CURVE_SAMPLES:
		var t := float(i) / float(CURVE_SAMPLES - 1)
		var sample := width_curve.sample_baked(t) if width_curve != null else 1.0 - t
		bytes[i] = clampi(int(round(sample * 255.0)), 0, 255)

	var image := Image.create_from_data(CURVE_SAMPLES, 1, false, Image.FORMAT_R8, bytes)
	material_override.set_shader_parameter("WIDTH_CURVE", ImageTexture.create_from_image(image))


func _update_width(value: float) -> void:
	trail_width = value
	if not is_inside_tree() or material_override == null:
		return

	material_override.set_shader_parameter("TRAIL_WIDTH", value)


func _set_emitting(value: bool) -> void:
	emitting = value
	if not value or not is_inside_tree():
		return
	position_history.clear()
	_expiry_times.clear()
	# Reset so the first recorded point starts here, not at the stale position.
	_last_recorded = _tracked_position()


func _tracked_position() -> Vector3:
	# A freed or unset target leaves the trail in place to recede by lifetime.
	return target.global_position if is_instance_valid(target) else global_position


func _adjust_history_size() -> void:
	if position_history.size() != max_points:
		var previous_size := position_history.size()
		position_history.resize(max_points)
		_expiry_times.resize(max_points)
		for i in range(previous_size, max_points):
			position_history[i] = _tracked_position()
			# Padding uses a past expiry time so it drops out on the next frame.
			_expiry_times[i] = -1.0


func _ready() -> void:
	_adjust_history_size()
	_last_recorded = _tracked_position()
	_update_max_points(max_points)
	_update_color(color)
	_update_billboard(billboard)
	_update_curve(width_curve)
	_update_width(trail_width)


func _process(delta: float) -> void:
	_elapsed += delta

	while not _expiry_times.is_empty() and _expiry_times.back() < _elapsed:
		_expiry_times.pop_back()
		position_history.pop_back()

	var tracked := _tracked_position()

	# The shader indexes two points minimum; degenerate padding stays invisible.
	while position_history.size() < 2:
		position_history.push_back(tracked)
		_expiry_times.push_back(-1.0)

	var dist_sq := min_point_distance * min_point_distance
	if emitting and _last_recorded.distance_squared_to(tracked) > dist_sq:
		_last_recorded = tracked
		position_history.push_front(tracked)
		_expiry_times.push_front(_elapsed + trail_lifetime)
		if position_history.size() > max_points:
			position_history.pop_back()
			_expiry_times.pop_back()

	if material_override:
		var packed := PackedVector3Array(position_history)
		packed.resize(TOTAL_MAX_POINTS)
		material_override.set_shader_parameter("positions", packed)
		material_override.set_shader_parameter("POINT_COUNT", position_history.size())
