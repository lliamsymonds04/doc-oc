class_name AirState
extends PlayerState

const HAND_VELOCITY_OFFSET_SCALE: float = 0.05
const HAND_VELOCITY_OFFSET_MAX: float = 1.0

const TILT_PIVOT_ROTATION_SPEED: float = 60.0
const TILT_PIVOT_ROTATION_SCALE : float = 0.02
const TILT_FORWARD_LIMIT: float = deg_to_rad(30.0)
const TILT_BACKWARD_LIMIT: float = deg_to_rad(30.0)

func enter() -> void:
	var p := player

	for mount in p.all_mounts():
		var idle_pos = mount.compute_idle_target()

		mount.arm.target = idle_pos
		mount.set_apply_floor(false)

func calculate_hand_velocity_offset(velocity: Vector3) -> Vector3:
	var mag = velocity.length()
	var new_mag = min(mag * HAND_VELOCITY_OFFSET_SCALE, HAND_VELOCITY_OFFSET_MAX)
	return velocity.normalized() * new_mag

func physics_update(dt: float) -> void:
	var p := player

	p.velocity += p.get_gravity() * dt

	var velocityRotation := p.velocity.y * TILT_PIVOT_ROTATION_SCALE

	if velocityRotation < -TILT_FORWARD_LIMIT:
		velocityRotation = -TILT_FORWARD_LIMIT
	if velocityRotation > TILT_BACKWARD_LIMIT:
		velocityRotation = TILT_BACKWARD_LIMIT

	p.rotation.y = p.camera_controller.global_rotation.y
	p.camera_controller.rotation.y = 0

	var current_rot_x := p.tilt_pivot.rotation.x
	var new_rot_x = lerp(current_rot_x, velocityRotation, dt * TILT_PIVOT_ROTATION_SPEED)
	p.tilt_pivot.rotation.x = new_rot_x

	var hand_velocity_offset = calculate_hand_velocity_offset(p.velocity)
	for mount in p.all_mounts():
		mount.arm.target = mount.compute_idle_target() + hand_velocity_offset

	var probe_hits := p.mount_prober.get_leg_probe_hits()
	if probe_hits.size() >= 1 and p.velocity.y <= 0.0:
		for mount in p.leg_mounts:
			if probe_hits.has(mount):
				var hit_pos: Vector3 = probe_hits[mount]["position"]
				if hit_pos:
					mount.set_target(hit_pos)

			else:
				mount.sync_from_arm()

		for mount in p.arm_mounts:
			mount.set_target(mount.compute_idle_target())

		p.set_state(p.StateID.GROUNDED)
