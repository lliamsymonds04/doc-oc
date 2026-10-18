shader_type spatial;
render_mode cull_disabled, unshaded;

const int TOTAL_MAX_POINTS = 100;
uniform int MAX_POINTS = 30;
uniform int POINT_COUNT = 30;
uniform vec4 TRAIL_COLOR = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool BILLBOARD = true;
uniform sampler2D WIDTH_CURVE : repeat_disable, filter_linear;
uniform float TRAIL_WIDTH = 0.2;
uniform vec3 positions[TOTAL_MAX_POINTS];

void vertex() {
	int count = clamp(POINT_COUNT, 2, MAX_POINTS);
	float index_progress = UV.y * float(count - 1);
	int index = int(floor(index_progress));
	int next_index = min(index + 1, count - 1);
	int prev_index = max(0, index - 1);
	float fract_part = fract(index_progress);

	vec3 current_pos = mix(positions[index], positions[next_index], fract_part);

	vec3 dir = current_pos - positions[prev_index];
	vec3 forward = length(dir) > 0.0001 ? normalize(dir) : vec3(0.0, 0.0, 1.0);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right;
	if (BILLBOARD) {
    	vec3 camera_dir = INV_VIEW_MATRIX[3].xyz - current_pos;
        right = normalize(cross(camera_dir, forward));
	} else {
	    right = normalize(cross(forward, up));
	}

	float width_offset = (UV.x - 0.5) * TRAIL_WIDTH;
	width_offset  *= texture(WIDTH_CURVE, vec2(UV.y, 0.0)).r;

	vec3 world_pos = current_pos + right * width_offset;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
    ALBEDO = TRAIL_COLOR.rgb;
    ALPHA = TRAIL_COLOR.a * (1.0 - UV.y);
}
