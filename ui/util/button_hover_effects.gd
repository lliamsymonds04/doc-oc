class_name ButtonHoverEffects
extends Node

## Mouse-only hover effect: while the cursor is over any BaseButton under its
## parent (Button, TextureButton, CheckBox, MenuButton, ...), the pause-menu
## cursor spins counter-clockwise. Button scale/press animations stay on the
## individual button scripts.
##
## Buttons added after _ready are hooked through node_added, so runtime-spawned
## buttons need no extra wiring.

const HOOKED_GROUP := "hover_effects_hooked"

@export var cursor: Control
@export var hover_rotation_deg := -15.0  # negative = counter-clockwise
@export var duration := 0.1

var _hovered := false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep animating while the tree is paused
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons(get_parent())


func _hook_buttons(root: Node) -> void:
	if root is BaseButton:
		_hook(root)

	for child in root.get_children():
		_hook_buttons(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and get_parent().is_ancestor_of(node):
		_hook(node)


func _hook(button: BaseButton) -> void:
	if button.is_in_group(HOOKED_GROUP):
		return

	button.add_to_group(HOOKED_GROUP)
	button.mouse_entered.connect(_on_hover.bind(true))
	button.mouse_exited.connect(_on_hover.bind(false))


## Asks the scene rather than counting, so a button freed while hovered can't
## leave the cursor stuck; enter/exit order between two buttons doesn't matter.
func _on_hover(_entered: bool) -> void:
	# a hovered button still reports mouse_exited while the tree is torn down
	if not is_inside_tree():
		return

	_hovered = get_tree().get_nodes_in_group(HOOKED_GROUP).any(
		func(b: BaseButton): return b.is_hovered()
	)
	_rotate_cursor()


func _rotate_cursor() -> void:
	if cursor == null:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(
		cursor, "rotation", deg_to_rad(hover_rotation_deg if _hovered else 0.0), duration
	)
