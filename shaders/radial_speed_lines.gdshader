shader_type canvas_item;

// Radial speed lines. `intensity` fades them in with player speed. `flow_phase`
// is advanced by the script so a speed change alters the rate, not the position.
// `inner_radius` is how close to screen centre they reach (lower = closer in).

uniform sampler2D dash_texture : filter_linear, repeat_disable;

// The trace's ink spans only ~8% of its canvas width, so the sampled cell is
// squeezed into that sliver. Lower = wider dashes; at ~0.08 the ink core fills
// the cell and the sides harden.
uniform float trace_scale : hint_range(0.04, 0.25) = 0.15;

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
	float angle = atan(pos.y, pos.x);
	// Quantise the angle to 1/64 rad steps so dashes stay on rays instead of smearing.
	float theta = round(64.0 * angle);
	float dist = length(pos);

	// Quantised radial position: flow_phase scrolls it, the per-spoke offset
	// keeps spokes from pulsing in sync.
	float cell = dist * 4.0 + flow_phase + 8.0 * random(vec2(theta));
	float dist_value = round(cell);
	// Each spoke gets its own random inner edge so the start is ragged, not a circle.
	bool on_spoke = dist > inner_radius + random(vec2(theta)) * 0.3;
	bool on_dash = random(vec2(theta, dist_value)) < 0.02;

	if (on_spoke && on_dash) {
		// Spoke-local UV: x across the ray, y along it, so the texture's long
		// axis (vertical) runs outward from the centre.
		vec2 dash_uv = vec2((64.0 * angle - theta) * trace_scale, cell - dist_value) + 0.5;
		COLOR = vec4(
			line_color.rgb, line_color.a * intensity * texture(dash_texture, dash_uv).a
		);
	}
}
