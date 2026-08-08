extends Node3D
class_name BasicArm

## Multi-segment arm solved with FABRIK toward a child Target node.
## Visualizer renders joints as spheres and segments as cylinders.
## All math is in local space: the solver is built from local positions,
## solve() re-anchors the root at the local origin.

@export var num_limbs: int = 3
@export var limb_length: float = 3.0
@export var limb_radius: float = 0.15
@export var joint_radius: float = 0.25
@export var target_speed: float = 8.0

@onready var target: Node3D = $Target

var solver: FabrikSolver
var limb_meshes: Array[MeshInstance3D] = []
var joint_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	if target == null:
		push_error("BasicArm: missing required child node 'Target' — attach basic_arm.tscn or add a Target child.")
		set_process(false)
		set_physics_process(false)
		return
	# Initial straight-line pose toward the target, in local space.
	# joints[0] is the root, followed by one point per limb end.
	var positions := PackedVector3Array([Vector3.ZERO])
	var target_dir := target.position.normalized()
	for i in range(num_limbs):
		positions.append(positions[i] + target_dir * limb_length)

	solver = FabrikSolver.new(positions)
	_build_visualizer()


func _physics_process(_delta: float) -> void:
	var solved := solver.solve(target.position, Vector3.ZERO)
	_update_visualizer(solved)


func _process(delta: float) -> void:
	# Prototype-only input: nudge the target with I/J/K/L (horizontal) and
	# U/O (vertical) so the arm can be exercised without scene edits.
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_I):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_K):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_J):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_L):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_U):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_O):
		move.y -= 1.0
	if move != Vector3.ZERO:
		target.position += move.normalized() * target_speed * delta


func _build_visualizer() -> void:
	var limb_mat := StandardMaterial3D.new()
	limb_mat.albedo_color = Color(0.3, 0.52, 1.0)
	limb_mat.roughness = 0.45

	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(1.0, 0.55, 0.12)
	joint_mat.roughness = 0.45

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = limb_radius
	cylinder.bottom_radius = limb_radius
	cylinder.height = limb_length

	for i in range(num_limbs):
		var seg := MeshInstance3D.new()
		seg.mesh = cylinder
		seg.material_override = limb_mat
		add_child(seg)
		limb_meshes.append(seg)

	var sphere := SphereMesh.new()
	sphere.radius = joint_radius
	sphere.height = joint_radius * 2

	for i in range(num_limbs + 1):
		var joint := MeshInstance3D.new()
		joint.mesh = sphere
		joint.material_override = joint_mat
		add_child(joint)
		joint_meshes.append(joint)


func _update_visualizer(joints: PackedVector3Array) -> void:
	for i in range(limb_meshes.size()):
		var a := joints[i]
		var b := joints[i + 1]
		var len := a.distance_to(b)
		var seg := limb_meshes[i]
		if len < 0.0001:
			seg.scale = Vector3.ZERO
			continue
		seg.position = (a + b) * 0.5
		seg.basis = _basis_aligned_to((b - a) / len)

	for i in range(joint_meshes.size()):
		var joint := joint_meshes[i]
		joint.position = joints[i]


## Returns a right-handed basis whose local Y axis points along `dir`.
func _basis_aligned_to(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(dir)
	return Basis(x, dir, z)
