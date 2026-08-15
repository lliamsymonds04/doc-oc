extends CharacterBody3D
class_name PlayerController


@export var speed = 5.0
@export var jump_velocity = 4.5
@export var turn_speed = 5.0
@export var arm_mounts: Array[ArmMount] = []
@export var raycast_config: ArmRaycastConfig

@export_category("Hover")
@export var hover_speed = 3.0
@export var min_y_offset = 2.5
@export var max_y_offset = 4.0
@export var min_height_change_look_threshold = 10.0
@export var height_change_rate = 1.0
@export var neutral_pitch = -5.0

@export_category("Wall Climb")
@export var wall_offset: float = 2.0
@export var wall_raycast_dist: float = 5.0
@export var ledge_ray_offset: float = 3.0
@export var ledge_ray_length: float = 5.0
@export var wall_climb_debounce_time: float = 0.5
@export var mount_velocity_impulse: float = 5.0
@export var wall_offset_correction_rate: float = 10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var arms: Array[BasicArm] = []

enum StateID { GROUNDED, WALL_CLIMB }
var wall_climb_debounce: float = 0.0

var _states: Dictionary = {}
var _current: PlayerState

var body_y_offset = (min_y_offset + max_y_offset)/2.0

func _ready() -> void:
	for mount in arm_mounts:
		mount.raycast_config = raycast_config
		var arm = mount.init()
		arms.append(arm)

	_states[StateID.GROUNDED] = GroundedState.new(self)
	_states[StateID.WALL_CLIMB] = WallClimbState.new(self)
	_current = _states[StateID.GROUNDED]

func set_state(id: StateID) -> void:
	if _current == _states[id]:
		return
	if _current:
		_current.exit()
	_current = _states[id]
	_current.enter()

func _physics_process(dt: float) -> void:
	if _current == null:
		return

	_current.input_dir = Input.get_vector("left", "right", "forward", "back")
	_current.physics_update(dt)

	move_and_slide()
