shader_type canvas_item;
// 坐姿-高清过场-运镜 方案 v1: pixel-art sampling for the HD opening pictures (scripts/opening.gd).
// The 960x540 pictures are shown at half size; with the default 3x window one picture pixel covers 1.5 screen pixels
// and, during the push-in of picture 7, any fraction. Plain nearest sampling then makes columns alternately 1 and 2
// screen pixels wide and edges crawl while the scale changes. Here each screen pixel takes its picture pixel's colour
// and only the one screen pixel that straddles a boundary between two picture pixels is blended by how much of it
// each side covers (the sprite uses linear filtering, the sample point is pushed to the texel centre elsewhere).
// At whole-number scales this gives exactly the nearest-neighbour picture.

varying vec4 tint;

void vertex() {
	tint = COLOR;      // modulate (the crossfade alpha)
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 p = UV * size;
	vec2 seam = floor(p + 0.5);
	vec2 span = max(fwidth(p), vec2(1.0e-4));
	p = seam + clamp((p - seam) / span, -0.5, 0.5);
	COLOR = texture(TEXTURE, p / size) * tint;
}
