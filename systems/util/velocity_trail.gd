class_name VelocityTrail
extends Node

const TRAIL_META := &"velocity_trail"
const GROUP_TRAIL := &"trail_group"
const MIN_SPEED := 3.0
const MIN_TRAIL_WIDTH := 0.2
const MAX_TRAIL_WIDTH := 0.7
const VELOCITY_WIDTH_FACTOR := 0.05
const WIDTH_RATE = 2.0

var trail: Trail

var _body: RigidBody3D


static func attach(body: RigidBody3D) -> VelocityTrail:
	# get_meta's default must not be null: absent and nil are indistinguishable
	if body.has_meta(TRAIL_META):
		var existing := body.get_meta(TRAIL_META) as VelocityTrail
		if is_instance_valid(existing):
			return existing

	return VelocityTrail.new(body)


func _init(body: RigidBody3D) -> void:
	_body = body

	trail = Trail.create()
	trail.extra_cull_margin = 16.0
	trail.target = body
	trail.emitting = false

	body.set_meta(TRAIL_META, self)
	body.add_child(self)
	add_child(trail)
	_try_trail_target()
	_try_color_match()


## Follows the visual child so the ribbon sits at the body's centre, not its origin.
func _try_trail_target() -> void:
	for child in _body.get_children():
		if child is MeshInstance3D or child is CSGShape3D:
			trail.target = child
			return


func _try_color_match() -> void:
	for child in _body.get_children():
		var material: BaseMaterial3D = null
		if child is MeshInstance3D:
			material = child.get_active_material(0) as BaseMaterial3D
		else:
			material = child.get("material") as BaseMaterial3D
		if material == null:
			continue

		trail.color = Color(material.albedo_color, trail.color.a)
		return

	push_warning("%s: no child material to match the trail colour" % _body.name)


func _physics_process(dt: float) -> void:
	if _body.freeze:
		return

	var speed := _body.linear_velocity.length()
	var fast := speed > MIN_SPEED
	var w := clampf(speed * VELOCITY_WIDTH_FACTOR, MIN_TRAIL_WIDTH, MAX_TRAIL_WIDTH)

	# Assign only on change: Trail._set_emitting clears history on every `true`.
	if trail.emitting != fast:
		trail.emitting = fast
		# emitting=true clears history, so the new ribbon must not inherit the
		# width it had when the body last dropped below MIN_SPEED.
		if fast:
			trail.trail_width = w

	if fast:
		trail.trail_width = move_toward(trail.trail_width, w, WIDTH_RATE * dt)
