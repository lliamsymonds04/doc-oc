extends CharacterBody3D
class_name PlayerController


@export var speed = 5.0
@export var turn_speed = 10.0
@export var arm_mounts: Array[ArmMount] = []
@export var leg_mounts: Array[ArmMount] = []
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

@export_category("Air")
@export var air_accel: float = 5.0
@export var air_speed: float = 5.0


@onready var arms: Array[BasicArm] = []
@onready var tilt_pivot: Node3D = $TiltPivot
@onready var Bean: Node3D = $TiltPivot/Bean
@onready var camera_controller: CameraController = $CameraController

enum StateID { GROUNDED, WALL_CLIMB, AIR }
var wall_climb_debounce: float = 0.0

var _states: Dictionary = {}
var _current: PlayerState

var mount_prober: MountProber

var body_y_offset = (min_y_offset + max_y_offset)/2.0

func _ready() -> void:
	for mount in arm_mounts + leg_mounts:
		mount.player = self
		mount.is_leg = leg_mounts.has(mount)
		mount.raycast_config = raycast_config
		var arm = mount.init()
		arms.append(arm)

	mount_prober = MountProber.new()
	mount_prober.init(self)

	_states[StateID.GROUNDED] = GroundedState.new(self)
	_states[StateID.WALL_CLIMB] = WallClimbState.new(self)
	_states[StateID.AIR] = AirState.new(self)
	_current = _states[StateID.GROUNDED]

func all_mounts() -> Array[ArmMount]:
	return leg_mounts + arm_mounts

func set_state(id: StateID) -> void:
	if _current == _states[id]:
		return
	if _current:
		_current.exit()

	for mount in all_mounts():
		mount.arm.is_stepping = false

	_current = _states[id]
	_current.enter()

func _physics_process(dt: float) -> void:
	if _current == null:
		return

	_current.input_dir = Input.get_vector("left", "right", "forward", "back")
	_current.physics_update(dt)

	move_and_slide()
