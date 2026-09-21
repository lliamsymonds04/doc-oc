extends CharacterBody3D
class_name PlayerController


@export var movement: MovementConfig
@export var hover: HoverConfig
@export var grounded: GroundedConfig
@export var air: AirConfig
@export var jump: JumpConfig
@export var wall_climb: WallClimbConfig
@export var arm_mounts: Array[ArmMount] = []
@export var leg_mounts: Array[ArmMount] = []
@export var raycast_config: ArmRaycastConfig

@export_category("visuals")
@export var step_vfx: PackedScene
@export var step_trauma: float = 0.3
@export var sprint_step_trauma: float = 0.15

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

## Mask for casts originating on the player: everything except the player's own layer.
func cast_mask() -> int:
	return ~collision_layer

func _init() -> void:
	if movement == null:
		movement = MovementConfig.new()
	if hover == null:
		hover = HoverConfig.new()
	if grounded == null:
		grounded = GroundedConfig.new()
	if air == null:
		air = AirConfig.new()
	if jump == null:
		jump = JumpConfig.new()
	if wall_climb == null:
		wall_climb = WallClimbConfig.new()

func _ready() -> void:
	for mount in arm_mounts + leg_mounts:
		mount.player = self
		mount.is_leg = leg_mounts.has(mount)
		mount.raycast_config = raycast_config
		var arm = mount.init(self)
		arms.append(arm)

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

func is_sprinting() -> bool:
	return _current is GroundedState and _current.is_sprinting

func current_state() -> PlayerState:
	return _current

func is_in_state(id: StateID) -> bool:
	return _current == _states[id]

func is_airborne() -> bool:
	return _current is AirState

func is_wall_climbing() -> bool:
	return _current is WallClimbState


func set_state(id: StateID) -> void:
	if _current == _states[id]:
		return
	if _current:
		_current.exit()

	for mount in all_mounts():
		mount.arm.is_moving = false

	_current = _states[id]
	_current.enter()

func _physics_process(dt: float) -> void:
	if _current == null:
		return

	_current.input_dir = Input.get_vector("left", "right", "forward", "back")
	_current.physics_update(dt)

	move_and_slide()
	camera_controller.update_motion(dt,velocity)

func _process(dt: float) -> void:
	if _current:
		_current.frame_update(dt)

	var horizontal_velocity = velocity * Vector3(1,0,1)
	var hs := horizontal_velocity.length()

	if _current.input_dir.length() == 0 and _current != _states[StateID.AIR]:
		hs = 0.0

	camera_controller.set_current_speed(hs)

func play_jump_effects(strength: float) -> void:
	AudioUtil.play_with_pitch(_jump_audio_player)
	camera_controller.add_trauma(strength * strength)
