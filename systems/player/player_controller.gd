class_name PlayerController
extends CharacterBody3D

## the hud listens to this; wiring lives in main.tscn
signal mode_changed(mode: Mode)

## the hud listens to this; wiring lives in main.tscn
signal attack_hit(hit_point: Vector3, normal: Vector3, collider: Object)

## the hud listens to this; wiring lives in main.tscn.
## emitted on the 0 <-> any grab transition, so it stays true while any arm holds
signal grabbing_changed(active: bool)

enum StateID { GROUNDED, WALL_CLIMB, AIR }

enum Mode { ATTACK, GRAB }

## Layer bodies are moved to while held; excluded from player casts via cast_mask.
const HELD_LAYER := 4

@export var movement: MovementConfig
@export var hover: HoverConfig
@export var grounded: GroundedConfig
@export var air: AirConfig
@export var jump: JumpConfig
@export var wall_climb: WallClimbConfig
@export var attack_config: PlayerAttackConfig
@export var grab: PlayerGrabConfig
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

var wall_climb_debounce: float = 0.0

var mount_prober: MountProber
var attack_controller: PlayerAttackController
var grab_controller: PlayerGrabController

var _states: Dictionary = {}
var _current: PlayerState
var _mode: Mode = Mode.ATTACK
var _jump_audio_player: AudioStreamPlayer3D
var _hit_vfx: ImpactVFX

@onready var arms: Array[BasicArm] = []
@onready var tilt_pivot: Node3D = $TiltPivot
@onready var bean: Node3D = $TiltPivot/Bean
@onready var camera_controller: CameraController = $CameraController


## Mask for casts originating on the player: everything except the player's own layer
## and held bodies.
func cast_mask() -> int:
	return ~(collision_layer | HELD_LAYER)


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
	if attack_config == null:
		attack_config = PlayerAttackConfig.new()
	if grab == null:
		grab = PlayerGrabConfig.new()


func _ready() -> void:
	for mount in arm_mounts + leg_mounts:
		mount.player = self
		mount.is_leg = leg_mounts.has(mount)
		mount.raycast_config = raycast_config
		var arm = mount.init(self)
		arms.append(arm)

	mount_prober = MountProber.new(self)
	attack_controller = PlayerAttackController.new(self, attack_config)
	grab_controller = PlayerGrabController.new(self, grab)

	_states[StateID.GROUNDED] = GroundedState.new(self)
	_states[StateID.WALL_CLIMB] = WallClimbState.new(self)
	_states[StateID.AIR] = AirState.new(self)
	_current = _states[StateID.GROUNDED]

	_jump_audio_player = AudioStreamPlayer3D.new()
	_jump_audio_player.stream = preload("res://assets/audio/robot_jump.ogg")
	add_child(_jump_audio_player)

	if step_vfx != null:
		_hit_vfx = step_vfx.instantiate() as ImpactVFX
		_hit_vfx.top_level = true
		add_child(_hit_vfx)


func all_mounts() -> Array[ArmMount]:
	return leg_mounts + arm_mounts


func is_sprinting() -> bool:
	return _current is GroundedState and _current.is_sprinting


func current_state() -> PlayerState:
	return _current


func grounded_state() -> GroundedState:
	return _states[StateID.GROUNDED]


func air_state() -> AirState:
	return _states[StateID.AIR]


func wall_climb_state() -> WallClimbState:
	return _states[StateID.WALL_CLIMB]


func is_in_state(id: StateID) -> bool:
	return _current == _states[id]


func is_airborne() -> bool:
	return _current is AirState


func is_in_grab_mode() -> bool:
	return _mode == Mode.GRAB


func set_mode(new_mode: Mode) -> void:
	if new_mode == _mode:
		return
	_mode = new_mode

	if _mode != Mode.GRAB:
		grab_controller.release_all()
	mode_changed.emit(_mode)
	camera_controller.kick_fov(grab.mode_switch_fov_kick)


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mode-switch"):
		set_mode(Mode.GRAB if _mode == Mode.ATTACK else Mode.ATTACK)


func _physics_process(dt: float) -> void:
	if _current == null:
		return

	_current.input_dir = Input.get_vector("left", "right", "forward", "back")
	_current.physics_update(dt)
	grab_controller.physics_update(
		camera_controller.mouse_delta_physics, camera_controller.wheel_delta_physics
	)

	move_and_slide()
	camera_controller.update_motion(dt, velocity)


func _process(dt: float) -> void:
	if _current:
		_current.frame_update(dt)
	grab_controller.frame_update()

	var horizontal_velocity = velocity * Vector3(1, 0, 1)
	var hs := horizontal_velocity.length()

	if _current.input_dir.length() == 0 and _current != _states[StateID.AIR]:
		hs = 0.0

	camera_controller.set_current_speed(hs)
	attack_controller.process(dt)


func play_jump_effects(strength: float) -> void:
	AudioUtil.play_with_pitch(_jump_audio_player)
	camera_controller.add_trauma(strength * strength)
