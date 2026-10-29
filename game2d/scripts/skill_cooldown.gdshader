shader_type canvas_item;
// 武学 (A): U / I icon cooldown (shader-basics canvas_item recipe). `remaining` 1 -> 0 over the cooldown: the part of the
// icon still cooling, swept clockwise from 12 o'clock, is darkened (and greyed); a thin gold hand marks the sweep.
uniform float remaining : hint_range(0.0, 1.0) = 0.0;
uniform float dark = 0.28;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (remaining > 0.0) {
		vec2 d = UV - vec2(0.5);
		float a = atan(d.x, -d.y);                    // 0 at 12 o'clock, clockwise positive
		float frac = fract(a / 6.2831853 + 1.0);      // 0..1 round the clock
		float edge = 1.0 - remaining;
		if (frac > edge) {
			float g = dot(c.rgb, vec3(0.3, 0.59, 0.11));
			c.rgb = mix(c.rgb, vec3(g), 0.7) * dark;
		}
		if (abs(frac - edge) < 0.025 && length(d) < 0.42 && c.a > 0.5) {
			c.rgb = vec3(1.0, 0.85, 0.4);
		}
	}
	COLOR = c;
}
