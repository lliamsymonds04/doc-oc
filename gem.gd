class_name FloatingGem
extends Node3D

## Bobs the gem on a sine wave around the height it was placed at.

## Emitted once per landing swing, with the contact point and surface normal.
signal hit_landed(position: Vector3, normal: Vector3)

## Seconds the shatter fade takes before the gem leaves the tree.
const SHATTER_TIME: float = 0.12
## Longest emitter lifetime in gem_break.tscn, plus a margin, before the burst frees itself.
const BREAK_VFX_TIME: float = 1.0
## Seconds the hum fades after the break; the gem stays in the tree until it ends.
const HUM_FADE_TIME: float = 1.2
## Effectively silent, so the fade ends inaudible rather than at the last dB.
const SILENT_DB: float = -60.0

@export var bob_height := 0.25
@export var bob_duration := 2.5
@export var break_vfx: PackedScene = preload("res://assets/vfx/gem_break.tscn")

var _base_height := 0.0
var _elapsed := 0.0
var _broken := false

@onready var _hum: AudioStreamPlayer3D = $Hum
@onready var _shape: CollisionShape3D = $Body/CollisionShape3D


## Returns the gem a physics body belongs to, or null when it is not part of one.
static func resolve(collider: Object) -> FloatingGem:
	var node := collider as Node
	while node != null:
		if node is FloatingGem:
			return node
		node = node.get_parent()
	return null


func _ready() -> void:
	_base_height = position.y


func _physics_process(delta: float) -> void:
	_elapsed += delta
	position.y = _base_height + sin(_elapsed * TAU / maxf(bob_duration, 0.01)) * bob_height


## Called when a punch connects; the gem's reaction hangs off [signal hit_landed].
func hit(position: Vector3, normal: Vector3) -> void:
	if _broken:
		return
	_broken = true

	# listeners still get the hit even though the gem is about to go away
	hit_landed.emit(position, normal)
	_shatter()


func _shatter() -> void:
	var vfx := break_vfx.instantiate() as ImpactVFX
	# parked on the parent so the burst outlives the gem it came from
	get_parent().add_child(vfx)
	vfx.play(global_position)
	# nothing pools this burst, so it has to clean up after itself
	get_tree().create_timer(BREAK_VFX_TIME).timeout.connect(vfx.queue_free)

	# stop the gem's own sparkle while it dissolves
	for child in find_children("*", "GPUParticles3D", true, false):
		(child as GPUParticles3D).emitting = false

	# the body collapses with the scale, so take it out before that degenerates
	_shape.set_deferred("disabled", true)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ZERO, SHATTER_TIME)
	# chained below waits for the longest tweener, so the hum is not cut short
	tween.tween_property(_hum, "volume_db", SILENT_DB, HUM_FADE_TIME)

	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var mat := mesh.material_override as BaseMaterial3D
		if mat == null:
			continue
		# duplicated so the fade can't leak into other users of the same material
		var faded := mat.duplicate() as BaseMaterial3D
		mesh.material_override = faded
		tween.tween_property(faded, "albedo_color:a", 0.0, SHATTER_TIME)

	tween.chain().tween_callback(queue_free)
