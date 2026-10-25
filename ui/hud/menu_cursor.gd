class_name MenuCursor
extends TextureRect

## Software cursor for the pause menu. While shown, the native pointer image is
## swapped for a transparent one (see [method set_native_hidden]) so this graphic
## is the only cursor on screen and can be rotated on hover.
##
## Position comes from the native pointer, which stays in MOUSE_MODE_CONFINED:
## MOUSE_MODE_CONFINED_HIDDEN leaves it frozen under Wayland in 4.7.
## Pivot stays at the texture's top-left, matching the OS hotspot, so the tip
## stays under the pointer while it spins.

var _blank: ImageTexture


func _ready() -> void:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_blank = ImageTexture.create_from_image(image)


func _process(_dt: float) -> void:
	position = get_global_mouse_position()


func set_native_hidden(hidden: bool) -> void:
	Input.set_custom_mouse_cursor(_blank if hidden else texture, Input.CURSOR_ARROW)
