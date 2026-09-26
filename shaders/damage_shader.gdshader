shader_type spatial;
render_mode blend_add, unshaded;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = flash_amount;
}
