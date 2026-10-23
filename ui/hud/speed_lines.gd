class_name SpeedLines
extends ColorRect

## Full-screen speed-line overlay. Intensity follows the player's horizontal
## speed, so it fades in as they move and is invisible when standing still.

const PHASE_WRAP := 1024.0

@export_category("Fade")
@export var intensity_scalar: float = 0.8
@export var blend_rate: float = 6.0

@export_category("Flow")
@export var slow_flow_speed: float = 8.0
@export var fast_flow_speed: float = 12.0

@export_category("Radius")
@export var slow_inner_radius: float = 0.4
@export var fast_inner_radius: float = 0.32

@export_category("Speed Threshold")
@export var min_speed_thresh_mult: float = 0.95
@export var max_speed_thresh_mult: float = 1.5

var _camera: CameraController
var _intensity := 0.0
var _weight := 0.0
var _flow_phase := 0.0

@onready var _material: ShaderMaterial = material as ShaderMaterial


func _ready() -> void:
	visible = false


func _process(dt: float) -> void:
	if _camera == null:
		_camera = get_tree().get_first_node_in_group("camera_controller") as CameraController
		if _camera == null:
			return

	var player := _camera.get_player()
	var full_speed := (
		player.movement.speed * player.grounded.sprint_multiplier * max_speed_thresh_mult
	)
	# Lines start at walk speed and reach full intensity at sprint speed.
	var start_fraction := (player.movement.speed * min_speed_thresh_mult) / full_speed

	var weight := clampf(_camera.get_speed() / full_speed, 0.0, 1.0)
	weight = clampf((weight - start_fraction) / (1.0 - start_fraction), 0.0, 1.0)

	_weight = lerpf(_weight, weight, 1.0 - exp(-blend_rate * dt))
	_intensity = _weight * intensity_scalar

	visible = _intensity > 0.001
	if not visible:
		return

	var flow_speed := lerpf(slow_flow_speed, fast_flow_speed, _weight)
	_flow_phase = fmod(_flow_phase - flow_speed * dt, PHASE_WRAP)

	_material.set_shader_parameter("intensity", _intensity)
	_material.set_shader_parameter("flow_phase", _flow_phase)
	_material.set_shader_parameter(
		"inner_radius", lerpf(slow_inner_radius, fast_inner_radius, _weight)
	)
