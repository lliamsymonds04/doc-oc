shader_type canvas_item;

uniform float alpha : hint_range(0.0, 1.0) = 0.3;
uniform float inner_radius = 0.45; // clear zone, units of half-screen-width
uniform float outer_radius = 1.45; // 16:9 corner is ~1.41; keep >= this
uniform vec4 tint : source_color = vec4(0.03, 0.035, 0.055, 1.0);

void fragment() {
	vec2 p = abs(UV - 0.5) * 2.0;
	float mask = smoothstep(inner_radius, outer_radius, length(p));
	COLOR = vec4(tint.rgb, mask * alpha);
}
