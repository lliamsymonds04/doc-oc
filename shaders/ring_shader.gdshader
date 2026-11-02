shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;
uniform sampler2D CURVE : hint_default_white, filter_linear, repeat_disable;
uniform vec4 RING_COLOR : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float INTENSITY = 1.5;
uniform float MESH_HEIGHT = 2.0;

varying float v_height;

void vertex() {
	// Primitives are centred on the origin, so local Y spans -height / 2 .. height / 2.
	v_height = VERTEX.y / max(MESH_HEIGHT, 0.001) + 0.5;
}

void fragment() {
	float alpha = texture(CURVE, vec2(clamp(v_height, 0.0, 1.0), 0.5)).r;
	ALBEDO = RING_COLOR.rgb * INTENSITY;
	ALPHA = alpha * RING_COLOR.a;
}
