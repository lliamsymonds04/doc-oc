extends CharacterBody3D
class_name EnemyController

@export var damage_flash_duration: float = 0.2
@export var dead_body_cleanup_time: float = 10.0
@export var upright_speed: float = 5.0
@export var ragdoll_mass: float = 3.0

@onready var health_controller: HealthController = $HealthController
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hitbox: CollisionShape3D = $Hitbox
@export var health_bar: HealthBar

const damage_shader = preload("res://shaders/damage_shader.gdshader")

var _shader_mat: ShaderMaterial
var _tween: Tween
var _ragdoll: EnemyRagdollController
var _death_timer: float

func _ready() -> void:
	# create the shader material overlay
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = damage_shader
	mesh.material_overlay = _shader_mat

	health_controller.damage_taken.connect(_on_damage_taken)
	health_controller.healed.connect(_on_healed)
	health_controller.died.connect(_on_death)

	_ragdoll = EnemyRagdollController.new(self, upright_speed, ragdoll_mass)

func take_damage(dmg: float) -> void:
	health_controller.apply_damage(dmg)

	if is_dead():
		swap_to_ragdoll()

func is_dead() -> bool:
	return health_controller.is_dead()

func get_ragdoll() -> RigidBody3D:
	return _ragdoll.get_body()

func initiate_get_up() -> void:
	if _ragdoll.is_ragdoll():
		_ragdoll.initiate_get_up()

func cancel_get_up() -> void:
	_ragdoll.cancel_get_up()

func _physics_process(dt: float) -> void:
	_ragdoll.make_body_upright(dt)

	velocity += get_gravity() * dt
	move_and_slide()

func _process(dt: float) -> void:
	if _death_timer > 0.0:
		_death_timer -= dt
		if _death_timer <= 0.0:
			_ragdoll.get_body().queue_free()
			queue_free()

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

func swap_to_ragdoll() -> void:
	if _ragdoll.is_ragdoll():
		return
	_ragdoll.activate()

func _flash() -> void:
	if _tween:
		_tween.kill()

	_shader_mat.set_shader_parameter("flash_amount", 1.0)
	_tween = create_tween()
	_tween.tween_property(_shader_mat, "shader_parameter/flash_amount", 0.0, damage_flash_duration)
