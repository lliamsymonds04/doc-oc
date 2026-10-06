extends CharacterBody3D
class_name EnemyController

@export var damage_flash_duration: float = 0.2
@export var dead_body_cleanup_time: float = 10.0
@export var upright_speed: float = 5.0   # how fast the body stands up

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hitbox: CollisionShape3D = $Hitbox
@export var health_bar: HealthBar

const damage_shader = preload("res://shaders/damage_shader.gdshader")

var _shader_mat: ShaderMaterial
var _tween: Tween
var _death_body: RigidBody3D
var _death_body_collision: CollisionShape3D
var _death_timer: float
var _is_fake_body: bool = false
var _reallign_body: bool = false

func _ready() -> void:
	# create the shader material overlay
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = damage_shader
	mesh.material_overlay = _shader_mat

	health_controller.damage_taken.connect(_on_damage_taken)
	health_controller.healed.connect(_on_healed)
	health_controller.died.connect(_on_death)

	_create_fake_body()

func take_damage(dmg: float) -> void:
	health_controller.apply_damage(dmg)

	if is_dead():
		_swap_to_fake_body()

func is_dead() -> bool:
	return health_controller.is_dead()

func get_death_body() -> RigidBody3D:
	return _death_body

func _physics_process(dt: float) -> void:
	if _reallign_body:
		_make_body_upright(dt)

	velocity += get_gravity() * dt
	move_and_slide()

func _make_body_upright(dt: float) -> void:
	var current_up := global_transform.basis.y.normalized()
	var tilt := current_up.angle_to(Vector3.UP)
	if tilt < 0.02:
		_reallign_body = false
		return

	var fix := Quaternion(current_up, Vector3.UP)
	var step := Quaternion.IDENTITY.slerp(fix, clampf(upright_speed * dt, 0.0, 1.0))
	var rot := step * global_transform.basis.get_rotation_quaternion()
	global_transform.basis = Basis(rot)

func _process(dt: float) -> void:
	if _death_timer > 0.0:
		_death_timer -= dt
		if _death_timer <= 0.0:
			_death_body.queue_free()
			queue_free()

	# temporary toggle
	if Input.is_action_just_pressed("debug"):
		if _is_fake_body:
			_swap_to_real_body()
		else:
			_swap_to_fake_body()

func _on_damage_taken(_dmg: float) -> void:
	if health_bar:
		health_bar.damage_health_bar_tween(health_controller.get_health_float())

	_flash()

func _on_healed(_heal: float) -> void:
	if health_bar:
		health_bar.heal_health_bar_tween(health_controller.get_health_float())

func _on_death() -> void:
	if health_bar:
		health_bar.play_death()

	_death_timer = dead_body_cleanup_time

func _create_fake_body() -> void:
	_death_body = RigidBody3D.new()
	_death_body.visible = false
	_death_body.freeze = true

	var corpse_mesh := MeshInstance3D.new()
	corpse_mesh.mesh = mesh.mesh
	corpse_mesh.position = mesh.position
	_death_body.add_child(corpse_mesh)

	var corpse_shape := CollisionShape3D.new()
	corpse_shape.shape = hitbox.shape
	corpse_shape.position = hitbox.position
	_death_body.add_child(corpse_shape)
	_death_body_collision = corpse_shape

	get_parent().add_child(_death_body)
	_death_body.global_transform = global_transform
	corpse_shape.disabled = true

func _swap_to_fake_body() -> void:
	if not _death_body or _is_fake_body:
		return
	_is_fake_body = true
	visible = false
	_death_body.visible = true
	_death_body.global_transform = global_transform
	_death_body.reset_physics_interpolation()
	_death_body_collision.set_deferred("disabled", false)
	_death_body.add_to_group("enemy_corpse")
	_death_body.set_deferred("freeze", false)
	hitbox.set_deferred("disabled", true)
	set_physics_process(false)

func _swap_to_real_body() -> void:
	if not _death_body or !_is_fake_body:
		return

	_is_fake_body = false
	_death_body.visible = false
	global_transform = _death_body.global_transform
	reset_physics_interpolation()
	visible = true
	_reallign_body = true
	_death_body_collision.set_deferred("disabled", true)
	_death_body.remove_from_group("enemy_corpse")
	_death_body.set_deferred("freeze", true)
	hitbox.set_deferred("disabled", false)
	set_physics_process(true)

func _flash() -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", 1.0)
	_tween = create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, damage_flash_duration)
