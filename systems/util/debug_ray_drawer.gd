class_name DebugRayDrawer
extends Node3D
## Drop-in debug drawer for raycasts.
## Add this as a child of Main (or any Node3D at world origin) and it will
## visualize rays queued via [method RaycastUtil.debug_ray] or [method draw_ray].
## If the node is not in the tree, all RaycastUtil debug calls no-op,
## so you can remove it for production with zero code changes.

static var instance: DebugRayDrawer = null

@export var default_thickness: float = 0.015
@export var default_hit_thickness_scale: float = 1.0  # multiplier for hit normal/cross
@export_range(4, 12) var tube_sides: int = 6

# Internal ray record: {from:Vector3, to:Vector3, color:Color, expires:int, thickness:float}
# expires == -1  -> 1 frame (drawn once then culled)
# expires > 0    -> Time.get_ticks_msec() expiry
# thickness < 0  -> use default_thickness, 0 -> use line (1px) if you want, >0 -> tube radius
var _rays: Array[Dictionary] = []
var _mi: MeshInstance3D
var _mesh: ImmediateMesh


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "DebugRayMesh"
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unshaded vertex-color material so lines are visible in any lighting
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = true  # always visible, even through walls
	_mi.material_override = mat
	add_child(_mi)


## Draw a line from [param from] to [param to] with [param color].
## [param duration] == 0.0 -> visible for 1 frame only.
## [param duration] > 0.0  -> lingering for that many seconds (e.g. 0.5).
## [param thickness] < 0 -> use [member default_thickness], 0 -> 1px line,
## > 0 -> tube radius in meters.
func draw_ray(
	from: Vector3,
	to: Vector3,
	color: Color = Color.WHITE,
	duration: float = 0.0,
	thickness: float = -1.0
) -> void:
	var expires: int = -1
	if duration > 0.0:
		expires = Time.get_ticks_msec() + int(duration * 1000.0)
	_rays.append(
		{"from": from, "to": to, "color": color, "expires": expires, "thickness": thickness}
	)


## Convenience: draw a short normal at [param pos] for hit visualization.
func draw_hit(
	pos: Vector3,
	normal: Vector3,
	color: Color = Color.GREEN,
	duration: float = 0.0,
	length: float = 0.4,
	thickness: float = -1.0
) -> void:
	var t := thickness if thickness >= 0.0 else default_thickness * default_hit_thickness_scale
	draw_ray(pos, pos + normal * length, color, duration, t)
	# small cross at hit point so it's visible even at grazing angles
	var s := 0.08
	draw_ray(pos + Vector3(s, 0, 0), pos - Vector3(s, 0, 0), color, duration, t)
	draw_ray(pos + Vector3(0, s, 0), pos - Vector3(0, s, 0), color, duration, t)
	draw_ray(pos + Vector3(0, 0, s), pos - Vector3(0, 0, s), color, duration, t)


## Optional: draw a wire sphere at [param pos] for shape-cast hit volume visualization.
func draw_sphere(
	pos: Vector3,
	radius: float,
	color: Color = Color.GREEN,
	duration: float = 0.0,
	thickness: float = -1.0
) -> void:
	var t := thickness if thickness >= 0.0 else default_thickness
	# 3 axis-aligned circles
	var segs := 12
	for axis in 3:
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p0: Vector3
			var p1: Vector3
			if axis == 0:  # YZ
				p0 = pos + Vector3(0, cos(a0), sin(a0)) * radius
				p1 = pos + Vector3(0, cos(a1), sin(a1)) * radius
			elif axis == 1:  # XZ
				p0 = pos + Vector3(cos(a0), 0, sin(a0)) * radius
				p1 = pos + Vector3(cos(a1), 0, sin(a1)) * radius
			else:  # XY
				p0 = pos + Vector3(cos(a0), sin(a0), 0) * radius
				p1 = pos + Vector3(cos(a1), sin(a1), 0) * radius
			draw_ray(p0, p1, color, duration, t)


func clear() -> void:
	_rays.clear()
	if _mesh:
		_mesh.clear_surfaces()


func _add_tube(a: Vector3, b: Vector3, color: Color, radius: float) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.0001:
		return
	dir /= len
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var s := tube_sides
	for i in s:
		var ang0 := TAU * float(i) / float(s)
		var ang1 := TAU * float(i + 1) / float(s)
		var off0 := (cos(ang0) * right + sin(ang0) * up) * radius
		var off1 := (cos(ang1) * right + sin(ang1) * up) * radius
		var v0 := a + off0
		var v1 := a + off1
		var v2 := b + off0
		var v3 := b + off1
		# tri 1: v0, v1, v2
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v0)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v1)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v2)
		# tri 2: v1, v3, v2
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v1)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v3)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(v2)


func _process(_delta: float) -> void:
	if _mesh == null:
		return

	# Rebuild mesh every frame from current rays (in local space)
	_mesh.clear_surfaces()
	if _rays.is_empty():
		return

	# Use single triangle surface for thick tubes. 1px lines are still tubes with small radius.
	# If you want true 1px lines, pass thickness=0 and we use a separate LINES surface.
	var has_lines := false
	var has_tubes := false
	for r in _rays:
		var th: float = r["thickness"]
		if th == 0.0:
			has_lines = true
		else:
			has_tubes = true

	if has_tubes:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in _rays:
			var th: float = r["thickness"]
			if th == 0.0:
				continue
			var radius: float = th if th > 0.0 else default_thickness
			var col: Color = r["color"]
			var a: Vector3 = to_local(r["from"])
			var b: Vector3 = to_local(r["to"])
			_add_tube(a, b, col, radius)
		_mesh.surface_end()

	if has_lines:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for r in _rays:
			var th: float = r["thickness"]
			if th != 0.0:
				continue
			var col: Color = r["color"]
			var a: Vector3 = to_local(r["from"])
			var b: Vector3 = to_local(r["to"])
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(a)
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(b)
		_mesh.surface_end()

	# Cull after drawing so 1-frame rays were visible for exactly one frame
	var now := Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	kept.resize(0)
	for r in _rays:
		var e: int = r["expires"]
		if e == -1:
			# 1-frame: already drawn, drop it
			continue
		if now < e:
			kept.append(r)
		# else expired -> drop
	_rays = kept
