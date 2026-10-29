shader_type canvas_item;
// 武学 (A): 学会新招 - a gold flash round the screen edge (a full-rect ColorRect; post-processing recipe of shader-basics,
// without reading the screen). `amount` 0..1 is tweened by scripts/skills_hud.gd.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float width = 0.18;

void fragment() {
	vec2 e = min(UV, vec2(1.0) - UV);                  // distance to the nearest edge (0 at the edge)
	float d = min(e.x * 1.78, e.y);                     // 16:9: the same thickness on every side
	float k = 1.0 - smoothstep(0.0, width, d);
	COLOR = vec4(glow.rgb, glow.a * k * k * amount);
}
