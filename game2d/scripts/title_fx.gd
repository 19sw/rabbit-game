class_name TitleFx
extends Node2D
## 启动画面 "风动气流" effects, one node per kind, every number from data/title.json ("effects"):
##   mist          a seamless mist strip drifting sideways (assets/title/mist_<i>.png)
##   leaves_back / leaves_front   bamboo + ginkgo leaves swirling on ellipses around the two; the half of each orbit
##                 nearer the viewer is drawn in front of the standees, the far half behind them
##   motes         faint qi light points rising around both standees (additive)
##   ripple        a shallow air-wave where their winds meet (thin ")(" rings) + a dust ring on the ground
##   wind          short wind streaks flowing from each of them towards the middle
## Everything is a pure function of the elapsed time `t` (no randomness), drawn with whole-pixel positions so the
## pixels stay crisp at the integer window scale. `intensity` scales counts and opacity together.

var kind := ""
var cfg: Dictionary = {}
var t := 0.0
var intensity := 1.0
var tex: Texture2D
var index := 0
var anchors: Dictionary = {}      # "rabbit" / "crane" -> feet position (motes)
var drawn_items := 0              # how many things were drawn last frame (tests)
## 封面两侧延伸画 v1: the x range the mist strip covers (it wraps every texture width, anchored at x = 0). Default 0..w
## (exactly the picture, as before); the title widens it when the side extensions are there.
var span := Vector2.ZERO


func setup(p_kind: String, p_cfg: Dictionary, p_intensity: float, p_tex: Texture2D = null, p_index := 0) -> TitleFx:
	kind = p_kind
	cfg = p_cfg
	intensity = p_intensity
	tex = p_tex
	index = p_index
	name = {"mist": "Mist%d" % p_index, "leaves_back": "LeavesBack", "leaves_front": "LeavesFront",
		"motes": "Motes", "ripple": "Ripple", "wind": "Wind"}.get(kind, kind)
	if kind == "motes":
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	return self


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


## Deterministic 0..1 hash of an integer (per-leaf / per-mote variation without randomness).
static func h01(n: int, salt := 0) -> float:
	var x := sin(float(n) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return x - floor(x)


static func scaled_count(n: float, k: float) -> int:
	return int(roundf(n * k))


func _draw() -> void:
	drawn_items = 0
	match kind:
		"mist":
			_draw_mist()
		"leaves_back":
			_draw_leaves(false)
		"leaves_front":
			_draw_leaves(true)
		"motes":
			_draw_motes()
		"ripple":
			_draw_ripple()
		"wind":
			_draw_wind()


# ------------------------------------------------------------------ mist
func _draw_mist() -> void:
	if tex == null:
		return
	var w := tex.get_width()
	var off := fposmod(t * float(cfg["speed"]), float(w))
	var k := int(floor(off))
	var h := tex.get_height()
	var y := int(cfg["y"])
	var c := Color(1, 1, 1, clampf(float(cfg["alpha"]) * intensity, 0.0, 1.0))
	# pieces that together cover exactly x span.x..span.y (default 0..w: two pieces, nothing outside the picture);
	# the strip wraps, screen x shows strip column (x + k) mod w
	var x0 := int(span.x)
	var x1 := int(span.y) if span.y > span.x else w
	var x := x0
	while x < x1:
		var src := posmod(x + k, w)
		var n := mini(w - src, x1 - x)
		draw_texture_rect_region(tex, Rect2(x, y, n, h), Rect2(src, 0, n, h), c)
		x += n
	drawn_items = 1


# ------------------------------------------------------------------ leaves
## Positions of every leaf right now: [{pos, front, row, frame, flip}]
func leaf_states() -> Array:
	var out := []
	var swirls: Array = cfg["swirls"]
	var fps := float(cfg["flutter_fps"])
	var n := 0
	for si in swirls.size():
		var s: Dictionary = swirls[si]
		var c := Vector2(s["center"][0], s["center"][1])
		var r := Vector2(s["radius"][0], s["radius"][1])
		var bamboo := scaled_count(float(s["bamboo"]), intensity)
		var total := bamboo + scaled_count(float(s["ginkgo"]), intensity)
		for j in total:
			n += 1
			var phase := TAU * (float(j) / maxf(1.0, float(total))) + h01(n, 1) * 0.6
			var spd := float(s["speed"]) * (0.85 + 0.3 * h01(n, 2))
			var a := phase + spd * t
			var rr := r * (0.82 + 0.3 * h01(n, 3))
			var bob := float(s["bob"]) * sin(t * (0.9 + 0.5 * h01(n, 4)) + TAU * h01(n, 5))
			var p := c + Vector2(cos(a) * rr.x, sin(a) * rr.y + bob)
			# moving direction on screen: derivative of x
			var vx := -sin(a) * spd
			out.append({
				"pos": p, "front": sin(a) > 0.0, "row": 0 if j < bamboo else 1,
				"frame": int(floor(t * fps * (0.8 + 0.4 * h01(n, 6)) + 4.0 * h01(n, 7))) % 4,
				"flip": vx < 0.0,
			})
	return out


func _draw_leaves(front: bool) -> void:
	if tex == null:
		return
	for l in leaf_states():
		if l["front"] != front:
			continue
		var p: Vector2 = l["pos"]
		var src := Rect2(int(l["frame"]) * 8, int(l["row"]) * 8, 8, 8)
		var dst := Rect2(Vector2(roundf(p.x) - 4, roundf(p.y) - 4), Vector2(8, 8))
		if l["flip"]:
			dst = Rect2(dst.position + Vector2(8, 0), Vector2(-8, 8))
		draw_texture_rect_region(tex, dst, src)
		drawn_items += 1


# ------------------------------------------------------------------ qi motes
func mote_states() -> Array:
	var out := []
	var per := scaled_count(float(cfg["per_character"]), intensity)
	var life0 := float(cfg["life"][0])
	var life1 := float(cfg["life"][1])
	var area := Vector2(cfg["area"][0], cfg["area"][1])
	var n := 0
	for who in ["rabbit", "crane"]:
		if not anchors.has(who):
			continue
		var feet: Vector2 = anchors[who]
		var col_a: Array = cfg["colors"][who]
		for k in per:
			n += 1
			var life := lerpf(life0, life1, h01(n, 11))
			var p := fposmod(t + h01(n, 12) * life, life) / life
			var base := feet + Vector2((h01(n, 13) - 0.5) * area.x * 2.0, -10.0 - h01(n, 14) * area.y)
			var pos := base + Vector2(sin(p * TAU + float(k)) * 2.0, -float(cfg["rise"]) * p)
			var alpha := sin(p * PI) * float(cfg["alpha"]) * minf(1.0, intensity)
			out.append({"pos": pos, "alpha": alpha, "color": Color(col_a[0], col_a[1], col_a[2]),
				"big": h01(n, 15) > 0.7})
	return out


func _draw_motes() -> void:
	for m in mote_states():
		var p: Vector2 = m["pos"]
		var c: Color = m["color"]
		c.a = m["alpha"]
		var q := Vector2(roundf(p.x), roundf(p.y))
		draw_rect(Rect2(q, Vector2(1, 1)), c)
		if m["big"]:
			var c2 := c
			c2.a *= 0.45
			for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(q + o, Vector2(1, 1)), c2)
		drawn_items += 1


# ------------------------------------------------------------------ ripple (air wave where the winds meet)
func ripple_rings() -> Array:
	var out := []
	var rings := int(cfg["rings"])
	var period := float(cfg["period"])
	for i in rings:
		var ph := fposmod(t / period + float(i) / float(rings), 1.0)
		out.append({"phase": ph, "alpha": float(cfg["alpha"]) * minf(1.0, intensity) * (1.0 - ph) * minf(1.0, ph * 5.0)})
	return out


func _ellipse_pixels(c: Vector2, r: Vector2, col: Color, arcs_only: bool) -> void:
	var seen := {}
	var steps := int(maxf(12.0, (r.x + r.y) * 3.0))
	for s in steps:
		var a := TAU * float(s) / float(steps)
		if arcs_only and absf(cos(a)) < 0.35:
			continue   # only the left and right arcs: ")(" - the two winds pressing against each other
		var p := Vector2(roundf(c.x + cos(a) * r.x), roundf(c.y + sin(a) * r.y))
		if seen.has(p):
			continue
		seen[p] = true
		draw_rect(Rect2(p, Vector2(1, 1)), col)


func _draw_ripple() -> void:
	var c := Vector2(cfg["center"][0], cfg["center"][1])
	var r0 := Vector2(cfg["radius_from"][0], cfg["radius_from"][1])
	var r1 := Vector2(cfg["radius_to"][0], cfg["radius_to"][1])
	var col_a: Array = cfg["color"]
	var g: Dictionary = cfg["ground"]
	var g0 := Vector2(g["radius_from"][0], g["radius_from"][1])
	var g1 := Vector2(g["radius_to"][0], g["radius_to"][1])
	for ring in ripple_rings():
		var ph: float = ring["phase"]
		var col := Color(col_a[0], col_a[1], col_a[2], ring["alpha"])
		_ellipse_pixels(c, r0.lerp(r1, ph), col, true)
		var gc := Color(col_a[0], col_a[1], col_a[2], float(g["alpha"]) * minf(1.0, intensity) * (1.0 - ph) * minf(1.0, ph * 5.0))
		_ellipse_pixels(Vector2(c.x, float(g["y"])), g0.lerp(g1, ph), gc, false)
		drawn_items += 1


# ------------------------------------------------------------------ wind streaks
func _draw_wind() -> void:
	if anchors.size() < 2:
		return
	var n := scaled_count(float(cfg["streaks_per_side"]), intensity)
	var mid_x := (float(anchors["rabbit"].x) + float(anchors["crane"].x)) * 0.5
	var length := int(cfg["length"])
	for side in [-1, 1]:
		var from_x: float = float(anchors["rabbit"].x) + 34.0 if side < 0 else float(anchors["crane"].x) - 30.0
		for k in n:
			var ph := fposmod(t * float(cfg["speed"]) + float(k) / float(maxi(1, n)) + (0.5 if side > 0 else 0.0), 1.0)
			var y := float(anchors["rabbit"].y) - 40.0 - float(k) * 14.0 + sin(ph * PI) * -4.0
			var x := lerpf(from_x, mid_x - float(side) * 6.0, ph)
			var a := float(cfg["alpha"]) * minf(1.0, intensity) * sin(ph * PI)
			var col := Color(1, 1, 1, a)
			for i in length:
				var px := roundf(x - float(side) * float(-i))
				var py := roundf(y + sin((float(i) / float(length)) * PI) * -1.5)
				draw_rect(Rect2(Vector2(px, py), Vector2(1, 1)), col)
			drawn_items += 1
