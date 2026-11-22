class_name PlayerGrabController
extends RefCounted

var player: PlayerController
var last_attack_time: float = -INF
var config: PlayerGrabConfig

var grabs: Dictionary = {}  # mount -> GrabHold
var grab_relative_rotations: Dictionary = {}  # body -> Quaternion, relative to player basis
var original_layers: Dictionary = {}  # body -> original collision_layer
var _throw_meter := GrabThrowMeter.new()
var _throw_homing: GrabThrowHoming
var _grab_attempt_player: AudioStreamPlayer3D
var _grab_success_player: AudioStreamPlayer3D
var _release_player: AudioStreamPlayer3D


func _init(p: PlayerController, grab_config: PlayerGrabConfig) -> void:
	player = p
	config = grab_config
	_throw_homing = GrabThrowHoming.new(player, config)

	_grab_attempt_player = AudioStreamPlayer3D.new()
	_grab_attempt_player.bus = AudioUtil.SFX_BUS
	_grab_attempt_player.stream = config.grab_attempted_sound
	p.add_child(_grab_attempt_player)

	_grab_success_player = AudioStreamPlayer3D.new()
	_grab_success_player.bus = AudioUtil.SFX_BUS
	_grab_success_player.stream = config.grab_sound
	p.add_child(_grab_success_player)

	_release_player = AudioStreamPlayer3D.new()
	_release_player.bus = AudioUtil.SFX_BUS
	p.add_child(_release_player)

	for mount in p.all_mounts():
		mount.arm.hit_detected.connect(arm_hit_detected.bind(mount))


func try_grab(side_dir: int) -> void:
	var now = PlayerPunchUtil.get_now()
	if not PlayerPunchUtil.punch_allowed(player, last_attack_time, config.grab_debounce, now):
		return

	var mount := _get_mount_for_side(side_dir)
	if mount == null or is_mount_grabbing(mount):
		return

	# same aim-point math as attack
	var target = PlayerPunchUtil.get_punch_target(player, side_dir, config.grab_cast_range)

	var join_hit := _aimed_held_body(config.grab_cast_range)
	if not join_hit.is_empty():
		_register_grab(mount, join_hit["collider"] as RigidBody3D, join_hit["position"])
		last_attack_time = now
		return

	last_attack_time = now
	mount.arm.start_punch(target, ~player.collision_layer)
	player.camera_controller.kick_fov(config.grab_fov_kick)
	AudioUtil.play_with_pitch(_grab_attempt_player)


func release_grab(side_dir: int) -> void:
	_release_mount(_get_mount_for_side(side_dir))


func release_all() -> void:
	for mount in grabs.keys():
		_release_mount(mount as ArmMount)


func _on_grabbed_body_exiting(body: Node3D) -> void:
	for mount in grabs.keys():
		if (grabs[mount] as GrabHold).body == body:
			_release_mount(mount as ArmMount)


func _release_mount(mount: ArmMount) -> void:
	if mount == null or not is_mount_grabbing(mount):
		return

	var hold: GrabHold = grabs[mount]
	var body: RigidBody3D = hold.body

	var still_held := _grip_count(body) > 1
	var throw := not still_held and _throw_meter.flick_pixels() > config.release_mouse_up_threshold
	if throw:
		GrabThrowUtil.apply_throw(
			body,
			_throw_meter.throw_speed(config),
			player.camera_controller.get_flat_basis(),
			config
		)
		_throw_homing.start(body, _homing_exclude(body))
	_throw_meter.reset_flick()
	_release_player.stream = config.release_throw_sound if throw else config.release_normal_sound
	AudioUtil.play_with_pitch(_release_player)

	grabs.erase(mount)
	if _grip_count(body) == 0:
		grab_relative_rotations.erase(body)
		body.collision_layer = original_layers[body]
		original_layers.erase(body)

		# a thrown enemy gets up after it settles; a plain release converts them back now
		if body.has_meta(EnemyRagdollController.ENEMY_META):
			var enemy: EnemyController = body.get_meta(EnemyRagdollController.ENEMY_META)
			if not enemy.is_dead():
				if throw:
					enemy.initiate_get_up()
				else:
					enemy.unragdoll()

	mount.set_apply_pole(true)

	if grabs.is_empty():
		player.grabbing_changed.emit(false)


func carry_magnet_factor(body: RigidBody3D, grip_count: int) -> float:
	var t := clampf(body.mass / grip_count / config.carry_weight_mass_ref, 0.0, 1.0)
	return lerpf(1.0, config.carry_magnet_min, t)


func physics_update(mouse_delta: Vector2, wheel_delta := 0.0) -> void:
	_throw_homing.physics_tick()
	_throw_meter.tick(mouse_delta, not grabs.is_empty(), config)
	var fov_kick := _throw_meter.fov_kick(config)
	if fov_kick != 0.0:
		player.camera_controller.kick_fov(fov_kick)
	_apply_mouse_drag(mouse_delta, wheel_delta)
	# two arms on one body: per-mount body writes would overwrite the other arm's error
	var err_sum := {}  # body -> Vector3
	var err_count := {}  # body -> int

	for hold_value in grabs.values():
		var hold := hold_value as GrabHold
		var grip_world: Vector3 = hold.grip_world()
		var anchor: Vector3 = hold.hold_world()

		hold.mount.set_target(grip_world)

		var error := anchor - grip_world
		err_sum[hold.body] = err_sum.get(hold.body, Vector3.ZERO) + error
		err_count[hold.body] = err_count.get(hold.body, 0) + 1

	for body_key in err_sum:
		var body := body_key as RigidBody3D
		body.linear_velocity = (
			(
				(err_sum[body] / err_count[body])
				* config.magnet_gain
				* carry_magnet_factor(body, err_count[body])
			)
			. limit_length(config.max_magnet_speed)
		)

		# rotation servo: keep the body's orientation locked relative to the player
		var target_q: Quaternion = (
			player.global_transform.basis.get_rotation_quaternion()
			* (grab_relative_rotations[body] as Quaternion)
		)
		var current_q := body.global_transform.basis.get_rotation_quaternion()

		# delta in WORLD frame: target = q_err * current, because angular_velocity is global-space
		var q_err := target_q * current_q.inverse()
		if q_err.w < 0.0:
			q_err = -q_err  # take the shortest path around

		var axis := Vector3(q_err.x, q_err.y, q_err.z)
		var angle := q_err.get_angle()
		if angle > 0.001 and axis.length() > 0.001:
			body.angular_velocity = (
				(axis.normalized() * angle * config.rotation_servo_gain)
				. limit_length(config.max_grab_spin)
			)
		else:
			body.angular_velocity = Vector3.ZERO


func _apply_mouse_drag(mouse_delta: Vector2, wheel_delta: float) -> void:
	if mouse_delta == Vector2.ZERO and is_zero_approx(wheel_delta):
		return
	if grabs.is_empty():
		return

	var cam_basis: Basis = player.camera_controller.get_flat_basis()
	var world_delta: Vector3 = (
		cam_basis.x * mouse_delta.x * config.hold_drag_sens_x * player.camera_controller.sensitivity
		+ (
			-Vector3.UP
			* mouse_delta.y
			* config.hold_drag_sens_y
			* player.camera_controller.sensitivity
		)
		+ -cam_basis.z * wheel_delta * config.hold_wheel_sens
	)

	for hold_value in grabs.values():
		var hold := hold_value as GrabHold
		hold.drag_hold(world_delta, config)


## Objects a released throw must not home onto: the thrown body itself and
## anything still gripped by the other arms.
func _homing_exclude(thrown: RigidBody3D) -> Array[Object]:
	var exclude: Array[Object] = [thrown]
	for hold_value in grabs.values():
		exclude.append((hold_value as GrabHold).body)
	return exclude


func _get_mount_for_side(side_dir: int) -> ArmMount:
	for mount in player.arm_mounts:
		if sign(mount.position.x) == side_dir:
			return mount
	return null


## Returns the full ray hit for a held body under the crosshair, or an empty Dictionary.
func _aimed_held_body(max_dist: float) -> Dictionary:
	var from := player.camera_controller.cam.global_position
	var to := from + player.camera_controller.get_camera_direction() * max_dist
	# includes HELD_LAYER, unlike cast_mask
	var params := PhysicsRayQueryParameters3D.create(from, to, ~player.collision_layer)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return {}
	var collider = hit["collider"]
	return hit if _grip_count(collider) > 0 else {}


func _register_grab(mount: ArmMount, body: RigidBody3D, hit_pos: Vector3) -> void:
	if body is ExplosiveBarrel:
		(body as ExplosiveBarrel).armed = false

	var was_empty := grabs.is_empty()
	grabs[mount] = GrabHold.new(mount, body, body.to_local(hit_pos), config)
	# enemy corpse cleanup queue_frees the body without notifying us; drop the grab
	var exit_cb := _on_grabbed_body_exiting.bind(body)
	# two-arm grabs and drop/re-grab hit this with a still-live one-shot connection
	if not body.tree_exiting.is_connected(exit_cb):
		body.tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)
	if not grab_relative_rotations.has(body):
		grab_relative_rotations[body] = (
			player.global_transform.basis.get_rotation_quaternion().inverse()
			* body.global_transform.basis.get_rotation_quaternion()
		)

	mount.set_apply_pole(false)

	if was_empty:
		player.grabbing_changed.emit(true)

	if body.has_meta(EnemyRagdollController.ENEMY_META):
		var enemy: EnemyController = body.get_meta(EnemyRagdollController.ENEMY_META)
		enemy.cancel_get_up()

	# play audio
	AudioUtil.play_with_pitch(_grab_success_player)


func arm_hit_detected(hit: Vector3, _normal: Vector3, collider: Object, mount: ArmMount) -> void:
	if not player.is_in_grab_mode():
		return

	if collider is EnemyController:
		var enemy: EnemyController = collider
		enemy.initiate_ragdoll(false)
		collider = enemy.get_ragdoll()
		enemy.flash(0.2)

	if not collider is RigidBody3D:
		return

	if grabs.has(mount):
		return

	var body = collider as RigidBody3D
	_register_grab(mount, body, hit)
	if not original_layers.has(body):
		original_layers[body] = body.collision_layer
	body.collision_layer = player.HELD_LAYER


func is_mount_grabbing(mount: ArmMount) -> bool:
	return grabs.has(mount)


func frame_update() -> void:
	for hold_value in grabs.values():
		var hold := hold_value as GrabHold
		hold.mount.arm.target_world = hold.grip_world_interpolated()


func _grip_count(body: Object) -> int:
	var count := 0
	for hold_value in grabs.values():
		if (hold_value as GrabHold).body == body:
			count += 1
	return count


func is_grabbing() -> bool:
	return not grabs.is_empty()
