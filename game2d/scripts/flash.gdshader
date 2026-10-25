shader_type canvas_item;
// Hit flash / wind-up glow for fighters: mixes the sprite colour towards flash_color by `amount` (0 = normal).
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, clamp(amount, 0.0, 1.0));
}
