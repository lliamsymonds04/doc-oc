extends RefCounted
class_name GrabThrowUtil

static func apply_throw(body: RigidBody3D, throw_speed: float, flat_basis: Basis,
		config: PlayerGrabConfig) -> void:
	var throw_dir := -flat_basis.z

	body.linear_velocity.y = 0.0
	body.linear_velocity += throw_dir * throw_speed
	body.linear_velocity.y += maxf(config.THROW_RELEASE_VELOCITY_Y - throw_speed * config.THROW_Y_Z_DROPOFF,
		config.THROW_RELEASE_VELOCITY_Y_MIN)
	apply_spin(body, config)

static func apply_spin(body: RigidBody3D, config: PlayerGrabConfig) -> void:
	var vel := body.linear_velocity
	if vel.length() < 0.1:
		return
	var dir := vel.normalized()
	# looking_at needs an up vector not parallel to the direction;
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	body.angular_velocity = basis.x * (vel.length() * config.RELEASE_SPIN_SENS)
