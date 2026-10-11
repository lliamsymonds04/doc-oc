class_name GrabThrowHoming
extends RefCounted

## Soft homing handler for released throws: picks an aim point at release and
## steers the body toward it for a short window.

var player: PlayerController
var config: PlayerGrabConfig

var _body: RigidBody3D
# _target_node wins when set; otherwise we steer at _target_point
var _target_node: Node3D
var _target_point := Vector3.ZERO
var _expire := -INF
var _last_tick := -INF


func _init(p: PlayerController, grab_config: PlayerGrabConfig) -> void:
	player = p
	config = grab_config


## Cone-scan along the crosshair for an enemy; steering targets the surface under
## the crosshair, then a point along the crosshair, when none is found.
## exclude must list the thrown body plus anything still gripped by other arms.
func start(body: RigidBody3D, exclude: Array[Object]) -> void:
	var from := player.camera_controller.cam.global_position
	var aim_dir := player.camera_controller.get_camera_direction()
	var target := GrabThrowUtil.find_homing_target(
		player.get_tree().get_nodes_in_group(EnemyController.ENEMY_GROUP),
		from,
		aim_dir,
		exclude,
		config
	)
	_target_node = target
	_target_point = Vector3.ZERO
	if target == null:
		if config.throw_homing_fallback_dist <= 0.0:
			return
		_target_point = GrabThrowUtil.aim_point_from_hit(
			player.camera_controller.get_camera_center_hit(config.throw_homing_surface_range),
			from,
			aim_dir,
			config
		)

	var now := PlayerPunchUtil.get_now()
	_body = body
	_expire = now + config.throw_homing_time
	_last_tick = now


func stop() -> void:
	_body = null
	_target_node = null
	_target_point = Vector3.ZERO
	_expire = -INF
	_last_tick = -INF


## Curves velocity toward the aim point, preserving its speed.
func physics_tick() -> void:
	if _body == null:
		return

	var now := PlayerPunchUtil.get_now()
	if not is_instance_valid(_body) or now >= _expire:
		stop()
		return

	var aim_point := _target_point
	if _target_node != null:
		if not is_instance_valid(_target_node):
			stop()
			return
		aim_point = _target_node.global_position + Vector3.UP * config.throw_homing_aim_height

	var dt := now - _last_tick
	_last_tick = now
	var vel := _body.linear_velocity
	var speed := vel.length()
	if speed < 0.1 or dt <= 0.0:
		return

	var to_target := aim_point - _body.global_position
	# nothing left to correct once the body is at or past the point
	if to_target.dot(vel) <= 0.0 or to_target.length() < config.throw_homing_stop_dist:
		stop()
		return

	var target_dir := GrabThrowUtil.ballistic_aim_dir(to_target, speed, _body.get_gravity().y)
	var weight := 1.0 - exp(-config.throw_homing_steer * dt)
	var new_vel := vel.normalized().slerp(target_dir, weight).normalized() * speed
	# blending Y keeps some launch arc; the solver owns the vertical aim
	new_vel.y = lerpf(vel.y, new_vel.y, config.throw_homing_y_steer)
	_body.linear_velocity = new_vel
