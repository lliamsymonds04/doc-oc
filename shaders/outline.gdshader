shader_type spatial;
// Full-screen outline pass. Goes on a 2x2 QuadMesh under the Camera3D.
// Writes only the rim, so the depth buffer stays clean for SSAO.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float thickness : hint_range(0.25, 8.0, 0.05) = 0.75;
// Jump relative to the pixel's own distance, so one value works at any range.
uniform float depth_threshold : hint_range(0.001, 0.5, 0.001) = 0.03;
uniform float strength : hint_range(0.0, 1.0, 0.01) = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// INV_PROJECTION_MATRIX only exists in fragment(), so it is passed in.
float linear_depth(mat4 inv_projection, vec2 screen_uv) {
	float raw = texture(depth_texture, screen_uv).r;
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, raw, 1.0);
	// Sky has no depth; the clamp keeps it far away so it still outlines objects.
	return -view.z / max(view.w, 0.000001);
}

float depth_jump(mat4 inv_projection, vec2 screen_uv, float center) {
	return abs(linear_depth(inv_projection, screen_uv) - center) / max(center, 0.001);
}

void fragment() {
	mat4 inv_projection = INV_PROJECTION_MATRIX;
	float center = linear_depth(inv_projection, SCREEN_UV);
	vec2 offset = thickness / VIEWPORT_SIZE;
	vec2 diag = offset * 0.7071;

	float jump = 0.0;
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV + vec2(offset.x, 0.0), center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV - vec2(offset.x, 0.0), center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV + vec2(0.0, offset.y), center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV - vec2(0.0, offset.y), center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV + diag, center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV - diag, center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV + vec2(diag.x, -diag.y), center));
	jump = max(jump, depth_jump(inv_projection, SCREEN_UV + vec2(-diag.x, diag.y), center));

	float mask = smoothstep(depth_threshold, depth_threshold * 2.0, jump) * strength;

	ALBEDO = outline_color.rgb;
	ALPHA = mask * outline_color.a;
}
