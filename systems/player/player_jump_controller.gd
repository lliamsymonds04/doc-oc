class_name PlayerJumpController
extends RefCounted


## Launch result for a ground jump; the calling state applies it:
## velocity on the player, arc via AirState.begin_launch(), effects via charge.
class LaunchData:
	var velocity := Vector3.ZERO
	var rising_gravity := 1.0
	var charge := 0.0


var player: PlayerController
var config: JumpConfig

## charge state; GroundedState reads is_holding_jump for the crouch offset
var is_holding_jump := false
var hold_time := 0.0


func _init(p: PlayerController, jump_config: JumpConfig) -> void:
	player = p
	config = jump_config


## advance the charge timer; GroundedState calls this each physics tick
func tick_hold(dt: float) -> void:
	if is_holding_jump:
		hold_time += dt


func begin_hold() -> void:
	is_holding_jump = true
	hold_time = 0.0


func cancel_hold() -> void:
	is_holding_jump = false
	hold_time = 0.0


## pure jump math: builds the launch velocity and charge from hold time.
func create_launch(direction: Vector3) -> LaunchData:
	var data := LaunchData.new()

	if hold_time < config.dash_jump_ceiling:
		data.charge = 0.0
	else:
		data.charge = clampf(hold_time / config.max_jump_hold_time, 0.0, 1.0)

	var vertical := lerpf(config.dash_vertical_velocity, config.hop_vertical_velocity, data.charge)
	var horizontal := lerpf(
		config.dash_horizontal_velocity, config.hop_horizontal_velocity, data.charge
	)

	# with no stick input, commit forward so a tap is always a dash, never a pop
	var dir := direction
	if dir.length_squared() < 0.01:
		dir = player.camera_controller.get_input_direction(Vector2(0, -1))

	var velocity := Vector3(0.0, vertical, 0.0)

	# max-blend so running dashes and standing dashes launch at the same speed
	var hvel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var along := hvel.dot(dir)
	var perp := hvel - dir * along
	var launch := dir * maxf(along, horizontal) + perp * 0.35
	velocity.x = launch.x
	velocity.z = launch.z

	data.velocity = velocity
	data.rising_gravity = lerpf(
		config.dash_gravity_multiplier, config.hop_gravity_multiplier, data.charge
	)
	return data


## wall jump velocity from climb input; caller applies it and transitions to AIR
func wall_jump_velocity(input_dir: Vector2) -> Vector3:
	var p := player
	if input_dir.y < 0:
		return Vector3.UP * config.wall_jump_upward_velocity
	if input_dir.x != 0:
		return p.basis.x * input_dir.x * config.wall_jump_sideways_velocity
	if input_dir.y > 0:
		return p.basis.z * config.wall_jump_backward_velocity
	return Vector3.ZERO
