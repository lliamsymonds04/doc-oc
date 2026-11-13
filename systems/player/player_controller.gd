class_name PlayerController
extends CharacterBody3D

signal mode_changed(mode: Mode)
signal attack_hit(hit_point: Vector3, normal: Vector3, collider: Object)
## emitted when the crosshair aim target gains/loses a living enemy in attack range
signal aim_at_enemy_changed(in_range: bool)
## emitted on the 0 <-> any grab transition, so it stays true while any arm holds
signal grabbing_changed(active: bool)
## emitted once when the player's health runs out
signal died
## emitted on every health change, carrying current health and the maximum
signal health_changed(current: float, max_health: float)
## emitted when a hit with a known direction lands, carrying the screen-space angle
## the hit came from (radians, 0 = right, +y down) and the reaction weight (0.3..1)
signal damage_direction(angle: float, weight: float)

enum StateID { GROUNDED, WALL_CLIMB, AIR }

enum Mode { ATTACK, GRAB }

## Layer bodies are moved to while held; excluded from player casts via cast_mask.
const HELD_LAYER := 4
## Layer the arena border sits on; excluded from player casts so it cannot be climbed.
const BORDER_LAYER := 16
const PLAYER_GROUP := &"player"

@export var movement: MovementConfig
@export var hover: HoverConfig
@export var grounded: GroundedConfig
@export var air: AirConfig
@export var jump: JumpConfig
@export var wall_climb: WallClimbConfig
@export var attack_config: PlayerAttackConfig
@export var grab: PlayerGrabConfig
@export var tackle: PlayerTackleConfig
@export var arm_mounts: Array[ArmMount] = []
@export var leg_mounts: Array[ArmMount] = []
@export var raycast_config: ArmRaycastConfig

@export_category("visuals")
@export var step_vfx: PackedScene
@export var step_trauma: float = 0.3
@export var sprint_step_trauma: float = 0.15
@export var damage_flash_duration: float = 0.1
@export var damage_flash_intensity: float = 0.2
## Fraction of max health at which the hurt reaction (flash, shake, FOV kick) is full.
@export var damage_full_reaction_percent: float = 0.3
@export var damage_trauma: float = 1.5
@export var damage_fov_kick: float = -3.0
## Speed the corpse is thrown at when the killing hit came with a direction (m/s).
@export var death_knockback: float = 6.0

@export_category("Audio")
@export var step_sound: AudioStreamOggVorbis
@export var servo_sound: AudioStreamOggVorbis
@export var damage_sound: AudioStreamOggVorbis = preload("res://assets/audio/hit_impact.ogg")

var wall_climb_debounce: float = 0.0

var mount_prober: MountProber
var attack_controller: PlayerAttackController
var grab_controller: PlayerGrabController
var tackle_controller: PlayerTackleController
var jump_controller: PlayerJumpController

var _states: Dictionary = {}
var _current: PlayerState
var _mode: Mode = Mode.ATTACK
var _jump_audio_player: AudioStreamPlayer3D
var _damage_audio_player: AudioStreamPlayer3D
var _hit_vfx: ImpactVFX
var _damage_flash: DamageFlashUtil
var _ragdoll: PlayerRagdollController
var _hit_dir := Vector3.ZERO

@onready var tilt_pivot: Node3D = $TiltPivot
@onready var hitbox: CollisionShape3D = $Hitbox
@onready var bean: MeshInstance3D = $TiltPivot/Bean
@onready var camera_controller: CameraController = $CameraController
@onready var _health_controller: HealthController = $HealthController


## Mask for casts originating on the player: everything except the player's own layer,
## held bodies, and the border.
func cast_mask() -> int:
	return ~(collision_layer | HELD_LAYER | BORDER_LAYER)


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
	if tackle == null:
		tackle = PlayerTackleConfig.new()


func _ready() -> void:
	add_to_group(PLAYER_GROUP)
	for mount in arm_mounts + leg_mounts:
		mount.player = self
		mount.is_leg = leg_mounts.has(mount)
		mount.raycast_config = raycast_config
		mount.init(self)

	mount_prober = MountProber.new(self)
	attack_controller = PlayerAttackController.new(self, attack_config)
	grab_controller = PlayerGrabController.new(self, grab)
	tackle_controller = PlayerTackleController.new(self, tackle)
	_ragdoll = PlayerRagdollController.new(self)

	_states[StateID.GROUNDED] = GroundedState.new(self)
	_states[StateID.WALL_CLIMB] = WallClimbState.new(self)
	_states[StateID.AIR] = AirState.new(self)
	jump_controller = PlayerJumpController.new(self, jump)
	_current = _states[StateID.GROUNDED]
	_current.enter()

	_jump_audio_player = AudioStreamPlayer3D.new()
	_jump_audio_player.stream = preload("res://assets/audio/robot_jump.ogg")
	add_child(_jump_audio_player)

	_damage_audio_player = AudioStreamPlayer3D.new()
	_damage_audio_player.stream = damage_sound
	add_child(_damage_audio_player)

	_health_controller.damage_taken.connect(_on_damage_taken)
	_health_controller.healed.connect(_on_healed)
	_health_controller.died.connect(_on_death)
	# deferred: the HUD's own onready nodes aren't resolved this early
	_sync_health.call_deferred()

	# arm meshes only exist after mount.init(), so collect them here, not in _init
	_damage_flash = DamageFlashUtil.new(self, bean, damage_flash_duration)
	for mount in all_mounts():
		for limb_mesh: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
			_damage_flash.add_mesh(limb_mesh)

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


func take_damage(dmg: float, hit_dir: Vector3 = Vector3.ZERO) -> void:
	_hit_dir = hit_dir
	_health_controller.apply_damage(dmg)
	print("damage taken: " + str(dmg) + "")


func is_dead() -> bool:
	return _health_controller.is_dead()


func _on_damage_taken(dmg: float) -> void:
	# floor keeps a light hit audible and visible
	var reference := _health_controller.max_health * damage_full_reaction_percent
	var weight := clampf(dmg / reference, 0.3, 1.0)
	_damage_flash.flash(damage_flash_intensity * weight)
	camera_controller.add_trauma(damage_trauma * weight)
	camera_controller.kick_fov(damage_fov_kick * weight)
	AudioUtil.play_with_pitch(_damage_audio_player, 0.08)
	if _hit_dir != Vector3.ZERO:
		# hit_dir is the push direction, so flip it to aim at the source. Yaw only,
		# so the screen angle means: top = in front, bottom = behind.
		var flat := camera_controller.get_flat_basis()
		var source := -_hit_dir
		damage_direction.emit(atan2(-source.dot(-flat.z), source.dot(flat.x)), weight)
	_sync_health()


func _on_healed(_heal: float) -> void:
	_sync_health()


func _sync_health() -> void:
	health_changed.emit(_health_controller.health, _health_controller.max_health)


func _on_death() -> void:
	print("dead")
	grab_controller.release_all()
	tackle_controller.cancel()
	_ragdoll.activate(_hit_dir.normalized() * death_knockback)
	died.emit()


func set_state(id: StateID) -> void:
	if _current == _states[id]:
		return
	if _current:
		_current.exit()

	# the tackle drives the arms itself while winding up; don't cancel its punch
	if not tackle_controller.is_tackling():
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
	tackle_controller.physics_update(dt)
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
	# only a committed vertical hop shakes the camera; dashes read through FOV instead
	var shake := maxf(strength - 0.6, 0.0) / 0.4
	camera_controller.add_trauma(shake * shake)
