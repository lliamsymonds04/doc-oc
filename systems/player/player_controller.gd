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
@export var air_accel: float = 2.0
@export var air_speed: float = 5.0
@export var air_turn_speed: float = 4.0
@export var min_turn_authority: float = 0.15
@export var air_drag: float = 5.0

@export_category("Jump")
@export var jump_vertical_velocity = 25.0
@export var jump_horizontal_velocity = 12.0
@export var max_jump_hold_time = 0.6
@export var min_jump_charge = 0.5

@export_category("visuals")
@export var step_vfx: PackedScene
@export var step_trauma: float = 0.3

@export_category("Audio")
@export var step_sound: AudioStreamOggVorbis
@export var servo_sound: AudioStreamOggVorbis

@onready var arms: Array[BasicArm] = []
@onready var tilt_pivot: Node3D = $TiltPivot
@onready var Bean: Node3D = $TiltPivot/Bean
@onready var camera_controller: CameraController = $CameraController

enum StateID { GROUNDED, WALL_CLIMB, AIR }
var wall_climb_debounce: float = 0.0

var _states: Dictionary = {}
var _current: PlayerState

var mount_prober: MountProber
var _jump_audio_player: AudioStreamPlayer3D

func _ready() -> void:
	for mount in arm_mounts + leg_mounts:
		mount.player = self
		mount.is_leg = leg_mounts.has(mount)
		mount.raycast_config = raycast_config
		var arm = mount.init(self)
		arms.append(arm)

		mount.arm.step_landed.connect(func(_pos, _normal):
			camera_controller.add_trauma(0.3)
		)

	mount_prober = MountProber.new()
	mount_prober.init(self)

	_states[StateID.GROUNDED] = GroundedState.new(self)
	_states[StateID.WALL_CLIMB] = WallClimbState.new(self)
	_states[StateID.AIR] = AirState.new(self)
	_current = _states[StateID.GROUNDED]

	## create jump audio stream
	_jump_audio_player = AudioStreamPlayer3D.new()
	_jump_audio_player.stream = preload("res://assets/audio/robot_jump.ogg")
	add_child(_jump_audio_player)

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

func _process(_dt: float) -> void:
	var horizontal_velocity = velocity * Vector3(1,0,1)
	var hs := horizontal_velocity.length()

	if _current.input_dir.length() == 0 and _current != _states[StateID.AIR]:
		hs = 0.0

	camera_controller.set_current_speed(hs)

func play_jump_effects(strength: float) -> void:
	AudioUtil.play_with_pitch(_jump_audio_player)
	camera_controller.add_trauma(strength * strength)
