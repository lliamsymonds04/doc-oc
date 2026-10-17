shader_type spatial;
render_mode cull_disabled, unshaded;

const int TOTAL_MAX_POINTS = 100;
uniform int MAX_POINTS = 30;
uniform vec3 positions[TOTAL_MAX_POINTS];
uniform float trail_width = 0.2;
uniform sampler2D width_curve : repeat_disable, filter_linear;
uniform bool billboard = true;

void vertex() {
	float index_progress = UV.y * float(MAX_POINTS - 1);
	int index = int(floor(index_progress));
	int next_index = min(index + 1, MAX_POINTS - 1);
	int prev_index = max(0, index - 1);
	float fract_part = fract(index_progress);

	vec3 current_pos = mix(positions[index], positions[next_index], fract_part);

	vec3 forward = normalize(current_pos - positions[prev_index]);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right;
	if (billboard) {
    	vec3 camera_dir = INV_VIEW_MATRIX[3].xyz - current_pos;
        right = normalize(cross(camera_dir, forward));
	} else {
	    right = normalize(cross(forward, up));
	}

	float width_offset = (UV.x - 0.5) * trail_width;
	width_offset  *= texture(width_curve, vec2(UV.y, 0.0)).r;

	vec3 world_pos = current_pos + right * width_offset;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
    ALBEDO = vec3(1.0, 0.3, 0.0);
}
