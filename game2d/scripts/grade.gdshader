shader_type canvas_item;
// Screen colour grade for the dusk mood: a little desaturation and a warm dark vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float desaturate = 0.18;
uniform float vignette = 0.38;
uniform vec3 vignette_color = vec3(0.16, 0.08, 0.05);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.15, 1.0);
	float v = smoothstep(0.30, 0.82, length(d)) * vignette;
	c = mix(c, vignette_color, v);
	COLOR = vec4(c, 1.0);
}
