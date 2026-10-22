shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float pixel_size : hint_range(1.0, 10.0, 1.0) = 2.0;
uniform float levels : hint_range(1.0, 100.0, 1.0) = 90.0;
uniform float dithering : hint_range(0.0, 1.0, 0.1) = 0.5; // dithering strength (0 = off)

uniform float saturation : hint_range(0.0, 2.0, 0.1) = 1.0;
uniform float contrast : hint_range(0.0, 2.0, 0.1) = 1.0;

uniform vec3 shadow_tint : source_color = vec3(0.05, 0.12, 0.18);     // teal-ish shadows
uniform vec3 highlight_tint : source_color = vec3(0.22, 0.12, 0.03);  // warm orange highlights
uniform float split_strength : hint_range(0.0, 1.0, 0.05) = 0.05;
uniform float split_balance : hint_range(0.0, 1.0, 0.05) = 0.5;       // where dark meets bright

void fragment() {
	vec2 screen_size = vec2(textureSize(SCREEN_TEXTURE, 0));
	vec2 pixel_count = screen_size / (pixel_size * 2.0);
	vec2 pixelated_uv = floor(UV * pixel_count) / pixel_count;
	vec4 color = texture(SCREEN_TEXTURE, pixelated_uv);

	float grayscale = max(color.r, max(color.g, color.b));

	// Spatial dither: hash of the block index, mapped to [-0.5, 0.7]
	vec2 block = floor(UV * pixel_count);
	float d = fract(sin(dot(block, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;

	// Fold the per-block offset into the quantization threshold
	float grayscale_d = grayscale + d * (0.5 / levels) * dithering;
	float lower = floor(grayscale_d * levels) / levels;
	float higher = ceil(grayscale_d * levels) / levels;
	float lower_diff = grayscale_d - lower;
	float higher_diff = higher - grayscale_d;
	float level = lower_diff < higher_diff ? lower : higher;

	float adjustment = grayscale > 0.0 ? level / grayscale : 1.0;
	color.rgb *= adjustment;

	// shadow/highlight tints
	float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	float mix_factor = smoothstep(split_balance - 0.5, split_balance + 0.5, lum);
	color.rgb += mix(shadow_tint, highlight_tint, mix_factor) * split_strength;

	// Saturation and contrast
	color.rgb = mix(vec3(0.5), color.rgb, saturation);
	color.rgb = (color.rgb - 0.5) * contrast + 0.5;

	COLOR = color;
}
