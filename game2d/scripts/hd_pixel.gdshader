shader_type canvas_item;
// 坐姿-高清过场-运镜 方案 v1 (B): pixel-art sampling for the HD dialogue portraits (128x128 in the 64x64 box,
// scripts/dialogue.gd) and the HD title rabbit (scale 0.5, scripts/title_screen.gd). With the default 3x window one HD
// pixel covers 1.5 screen pixels; plain nearest sampling would make columns alternately 1 and 2 screen pixels wide.
// Each screen pixel takes its texel's colour; only a screen pixel straddling a texel boundary is blended by coverage
// (the node uses linear filtering). At whole-number scales (2x / 4x windows) this is exactly nearest-neighbour.
// Works on AtlasTexture frames too (UV and TEXTURE_PIXEL_SIZE are both in atlas space).

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 p = UV * size;
	vec2 seam = floor(p + 0.5);
	vec2 span = max(fwidth(p), vec2(1.0e-4));
	p = seam + clamp((p - seam) / span, -0.5, 0.5);
	COLOR = texture(TEXTURE, p / size) * tint;
}
