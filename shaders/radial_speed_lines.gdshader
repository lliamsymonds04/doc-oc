shader_type canvas_item;

// Radial speed lines. `intensity` fades them in with player speed; `flow_phase`
// is the accumulated scroll phase (advanced by the script so speed changes
// alter the rate, not the position); `inner_radius` sets how close to screen
// centre they reach (lower = closer in).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_phase = 0.0;
uniform float inner_radius = 0.2;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	COLOR.a = 0.0;

	vec2 pos = UV - vec2(0.5);
	// Snap the angle to one of 64 spokes so dashes stay on rays instead of smearing.
	float theta = round(64.0 * atan(pos.y, pos.x));
	float dist = length(pos);

	// Quantised radial position: flow_phase scrolls it, the per-spoke offset
	// keeps spokes from pulsing in sync.
	float dist_value = round(dist * 4.0 + flow_phase + 8.0 * random(vec2(theta)));
	// Each spoke gets its own random inner edge so the start is ragged, not a circle.
	bool on_spoke = dist > inner_radius + random(vec2(theta)) * 0.3;
	bool on_dash = random(vec2(theta, dist_value)) < 0.02;

	if (on_spoke && on_dash) {
		COLOR = vec4(line_color.rgb, line_color.a * intensity);
	}
}
