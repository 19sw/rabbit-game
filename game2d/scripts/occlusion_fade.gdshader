shader_type canvas_item;
// 打磨 v1 (scripts/occlusion.gd): a soft see-through hole in a roof / wall top / canopy around the characters behind it.
// centers: node-local positions of up to 4 covered characters (count of them in use); render-only.

uniform vec2 centers[4];
uniform int count = 0;
uniform float radius = 24.0;
uniform float soft = 8.0;
uniform float min_alpha = 0.3;
uniform float strength = 0.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float hole = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= count) {
			break;
		}
		float d = distance(local_pos, centers[i]);
		hole = max(hole, 1.0 - smoothstep(radius - soft, radius, d));
	}
	c.a *= mix(1.0, min_alpha, hole * strength);
	COLOR = c;
}
