class_name CrackDecal
extends Decal

## Surface crack left behind when the player's arm hits static geometry.
## Spawn via [method spawn]; fades out and frees itself after LIFETIME.

const TEXTURE: Texture2D = preload("res://assets/textures/ground_crack.png")

const SIZE: Vector3 = Vector3(1.5, 0.01, 1.5)
const LIFETIME: float = 10.0
const FADE_TIME: float = 2.0
const MAX_LIVE: int = 24

static var _live: Array[CrackDecal] = []


static func spawn(
	parent: Node, pos: Vector3, normal: Vector3, size_factor: float = 1.0
) -> CrackDecal:
	if _live.size() >= MAX_LIVE:
		var oldest: CrackDecal = _live.pop_front()
		oldest.queue_free()
	var decal := CrackDecal.new()
	_live.append(decal)
	decal.size = size_factor * SIZE
	parent.add_child(decal)
	decal.place(pos, normal)
	return decal


func _init() -> void:
	texture_albedo = TEXTURE
	size = SIZE
	modulate = Color(1, 1, 1, 0.9)


func place(pos: Vector3, normal: Vector3) -> void:
	global_position = pos + normal * size.y * 0.05

	var x := normal.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		# Normal is (anti)parallel to UP; pick a fallback axis.
		x = normal.cross(Vector3.RIGHT)
	x = x.normalized()

	var y := normal
	var z := x.cross(y)
	transform.basis = Basis(x, y, z)

	# Random spin around the surface normal so repeated hits don't overlap identically.
	rotate_object_local(Vector3.UP, randf() * TAU)

	var tween := create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(
		func() -> void:
			_live.erase(self)
			queue_free()
	)
