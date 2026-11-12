shader_type canvas_item;

// Screen-edge damage feedback: a ring segment pointing at the hit direction, plus
// an all-around glow that creeps inward as health drops.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float angle = -1.5707964; // radians, screen space, 0 = right, +y down
uniform float arc_half_width = 0.7; // radians
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62; // fraction of the way to the border
uniform float buildup : hint_range(0.0, 1.0) = 0.0; // from lost health, widens the edge inward
uniform float buildup_max_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float edge_noise : hint_range(0.0, 1.0) = 0.35; // wobble on the constant outline
uniform vec4 tint : source_color = vec4(0.75, 0.06, 0.06, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	// half extents of the screen in units of half its height, so the angle is true
	vec2 half_extent = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 p = (UV - 0.5) * 2.0 * half_extent;

	// radius normalized by the distance to the border along this ray: the band hugs
	// the screen edge at every angle, not just top and bottom
	float radial = max(abs(p).x / half_extent.x, abs(p).y / half_extent.y);
	float band = smoothstep(inner_radius, 1.0, radial);
	// noise tears the constant outline: it shifts the inner boundary and mottles the
	// alpha, so the border reads as ragged instead of a clean ring
	float n = value_noise(p * 6.0) * 0.6 + value_noise(p * 14.0 + 13.0) * 0.4;
	float inner = mix(0.88, 0.6, buildup) + (n - 0.5) * edge_noise;
	float edge = smoothstep(inner, inner + 0.18, radial) * buildup * buildup_max_alpha;
	edge *= mix(1.0 - edge_noise * 0.8, 1.0, n);

	float delta = abs(mod(atan(p.y, p.x) - angle + PI, TAU) - PI);
	float sector = 1.0 - smoothstep(arc_half_width * 0.5, arc_half_width, delta);

	COLOR = vec4(tint.rgb, clamp(band * sector * intensity + edge, 0.0, 1.0) * tint.a);
}
