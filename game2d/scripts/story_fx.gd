class_name StoryFx
extends Node2D
## Drawn effects of the bamboo-grove puzzle (序章 v1): the pale cyan glow on a stone that was bowed to in the right
## order, the gust that carries bamboo leaves towards the next stone ("跟着风走"), the chaotic gust when the order is
## wrong, and the floating "沙——" when the clump parts. World-space, drawn above the map.

const LEAF_COLORS := [Color(0.93, 0.97, 0.62), Color(0.78, 0.93, 0.5), Color(1.0, 0.9, 0.55)]   # light, to read on the leaf litter
const GLOW := Color(0.6, 1.0, 0.95)

var glows: Dictionary = {}          # stone id -> world position (lit stones)
var leaves: Array = []              # {from, to, t, dur, phase, amp, col, chaotic, center}
var gusts := 0                      # statistics for tests
var chaotic_gusts := 0
var last_wind_from := Vector2.ZERO
var last_wind_to := Vector2.ZERO
var texts: Array = []               # {text, pos, t}
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "StoryFx"
	z_index = 40
	_rng.seed = 7


func set_glow(id: String, pos: Variant) -> void:
	if pos == null:
		glows.erase(id)
	else:
		glows[id] = pos
	queue_redraw()


func clear_glows() -> void:
	glows.clear()
	queue_redraw()


## A gust from `from` towards `to`: a stream of leaves.
func wind(from: Vector2, to: Vector2) -> void:
	gusts += 1
	last_wind_from = from
	last_wind_to = to
	var n := 26
	for i in n:
		leaves.append({"from": from + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-20, 4)), "to": to + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-16, 4)),
			"t": -i * 0.07, "dur": 1.5 + _rng.randf() * 0.4, "phase": _rng.randf() * TAU, "amp": _rng.randf_range(4, 10),
			"col": LEAF_COLORS[i % LEAF_COLORS.size()], "chaotic": false})


## The wrong-order gust: leaves whirl every which way around `center`.
func chaos(center: Vector2) -> void:
	chaotic_gusts += 1
	for i in 26:
		var a := _rng.randf() * TAU
		leaves.append({"from": center + Vector2.from_angle(a) * _rng.randf_range(10, 60), "to": center, "t": -i * 0.03,
			"dur": 1.3 + _rng.randf() * 0.4, "phase": a, "amp": _rng.randf_range(30, 90), "col": LEAF_COLORS[i % 3], "chaotic": true,
			"center": center})


func float_text(text: String, pos: Vector2) -> void:
	texts.append({"text": text, "pos": pos, "t": 0.0})


func busy() -> bool:
	return not leaves.is_empty()


func _process(delta: float) -> void:
	_t += delta
	for l in leaves:
		l["t"] += delta
	leaves = leaves.filter(func(l): return l["t"] < l["dur"])
	for x in texts:
		x["t"] += delta
	texts = texts.filter(func(x): return x["t"] < 2.2)
	if not glows.is_empty() or not leaves.is_empty() or not texts.is_empty():
		queue_redraw()


func _leaf_pos(l: Dictionary) -> Vector2:
	var k := clampf(l["t"] / l["dur"], 0.0, 1.0)
	if l["chaotic"]:
		var a: float = l["phase"] + k * 9.0 * (1.0 if int(l["amp"]) % 2 == 0 else -1.0)
		return l["center"] + Vector2.from_angle(a) * l["amp"] * (0.4 + 0.6 * sin(k * PI)) + Vector2(0, -10)
	var from: Vector2 = l["from"]
	var to: Vector2 = l["to"]
	var dir := (to - from).normalized()
	var side := dir.orthogonal()
	var eased := k * k * (3.0 - 2.0 * k)
	return from.lerp(to, eased) + side * sin(k * 7.0 + l["phase"]) * l["amp"] + Vector2(0, -12)


func _draw() -> void:
	for id in glows:
		var p: Vector2 = glows[id] + Vector2(0, -8)
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		for i in 4:
			draw_circle(p, 18.0 - i * 4.0, Color(GLOW.r, GLOW.g, GLOW.b, (0.08 + 0.05 * pulse) * (i + 1) * 0.6))
		draw_circle(p + Vector2(-3, -4), 2.0, Color(1, 1, 1, 0.6 + 0.3 * pulse))
	# wind streaks along a right gust (faint curved lines), then the leaves themselves (little lance-shaped bamboo leaves)
	for l in leaves:
		if l["t"] < 0.0 or l["chaotic"] or int(l["phase"] * 10.0) % 2 != 0:
			continue
		var pts := PackedVector2Array()
		for j in 6:
			var tt: float = l["t"] - j * 0.05
			if tt < 0.0:
				break
			pts.append(_leaf_pos({"from": l["from"], "to": l["to"], "t": tt, "dur": l["dur"], "phase": l["phase"], "amp": l["amp"], "chaotic": false}))
		if pts.size() >= 2:
			draw_polyline(pts, Color(1, 1, 1, 0.6), 1.0)
	for l in leaves:
		if l["t"] < 0.0:
			continue
		var p := _leaf_pos(l)
		var k := clampf(l["t"] / l["dur"], 0.0, 1.0)
		var a := minf(1.0, minf(k * 6.0, (1.0 - k) * 5.0))
		var c: Color = l["col"]
		c.a = a
		var ang: float = l["t"] * (9.0 if l["chaotic"] else 3.0) + l["phase"]
		var dir := Vector2.from_angle(ang)
		var side := dir.orthogonal()
		var leaf := PackedVector2Array([p - dir * 5.5, p + side * 1.8, p + dir * 5.5, p - side * 1.8])
		draw_colored_polygon(leaf, c)
		draw_line(p - dir * 5.5, p + dir * 5.5, Color(0.2, 0.4, 0.15, a * 0.8), 1.0)
	var font: Font = ThemeDB.fallback_font
	var f: FontFile = load("res://fonts/ui_font.fnt")
	if f:
		font = f
	for x in texts:
		var k: float = x["t"] / 2.2
		var col := Color(1.0, 0.97, 0.85, 1.0 - k * k)
		var pos: Vector2 = x["pos"] + Vector2(-14, -36 - 14.0 * k)
		draw_string(font, pos + Vector2(1, 1), x["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, col.a * 0.8))
		draw_string(font, pos, x["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
