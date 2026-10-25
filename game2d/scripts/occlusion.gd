class_name Occlusion
extends Node
## 打磨 v1: outdoor "see through what covers you". When the rabbit (or an NPC / enemy) stands behind a roof, a compound
## wall's tile top, a gate wing or a tree canopy, the outdoor object picture drawn over her gets a soft round
## see-through hole around her (scripts/occlusion_fade.gdshader), faded in / out. Render-only: the colliders, the
## pictures and the y-sort order stay exactly as they are. Numbers in data/tuning.json "occlusion".
##
## How "covers" is decided (fix round): the object is drawn over the character (its base line is below her feet) and
## the opaque pixels of its picture cover at least `coverage` of her REAL sprite pixels (current animation frame) -
## a few pixels at a tree edge, a woodpile, a bamboo edge or an eave tip are enough. The hole is centred on her pixels.

const CELL := 128.0
## 建筑实心 v1: buildings (and the library ruin) are solid over their whole picture - nothing can stand under their
## roof, so they never fade and are not even looked at. Fading is for tree canopies, bamboo, the gate towers' passage...
const SOLID_TYPES := ["building", "library_ruin"]
const MAX_CENTERS := 4

var main: Node
var entries: Array = []          # {sprite, rect (world), image}
var grid: Dictionary = {}        # Vector2i cell -> [entry index]
var active: Dictionary = {}      # entry index -> {strength, mat, centers}
var shader: Shader
var cfg: Dictionary
var _images: Dictionary = {}     # texture path -> Image (alpha lookups)
var _masks: Dictionary = {}      # character frame texture id -> opaque pixel offsets


func _init() -> void:
	name = "Occlusion"


func setup(m: Node) -> void:
	main = m
	cfg = Tuning.data()["occlusion"]
	shader = load("res://scripts/occlusion_fade.gdshader")
	for s in m.world.get_children():
		if not (s is Sprite2D):
			continue
		var t := String(s.get_meta("type", ""))
		if t == "" or t.begins_with("interior:") or s.texture == null or t in SOLID_TYPES:
			continue
		var img := _image(s.texture)
		if img == null:
			continue
		var rect := Rect2(s.position + s.offset, Vector2(s.texture.get_width(), s.texture.get_height()))
		var idx := entries.size()
		entries.append({"sprite": s, "rect": rect, "image": img, "type": t})
		for cy in range(int(floor(rect.position.y / CELL)), int(floor(rect.end.y / CELL)) + 1):
			for cx in range(int(floor(rect.position.x / CELL)), int(floor(rect.end.x / CELL)) + 1):
				var k := Vector2i(cx, cy)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(idx)


func _image(tex: Texture2D) -> Image:
	var key := tex.resource_path
	if key != "" and _images.has(key):
		return _images[key]
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if key != "":
		_images[key] = img
	return img


## Characters that can be covered: the rabbit and every visible NPC / fighter.
func actors() -> Array:
	var out := []
	var p: Player = main.player
	if p.visible and p.sprite.visible:
		out.append(p)
	for n in main.npcs:
		if n.visible:
			out.append(n)
	return out


static func body_rect(feet: Vector2) -> Rect2:
	return Rect2(feet + Vector2(-8, -27), Vector2(16, 26))


## 打磨 v1 fix round: the opaque pixels of the character's CURRENT animation frame (frame-local), cached per frame
## texture - the fade decision and the visibility checks use her real outline, not a box.
func frame_mask(spr: AnimatedSprite2D) -> PackedVector2Array:
	if spr == null or spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
		return PackedVector2Array()
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	if tex == null:
		return PackedVector2Array()
	var key := tex.get_instance_id()
	if _masks.has(key):
		return _masks[key]
	var img := tex.get_image()
	var pts := PackedVector2Array()
	if img != null:
		if img.is_compressed():
			img.decompress()
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					pts.append(Vector2(x, y))
	_masks[key] = pts
	return pts


## World positions of a character's visible pixels if her feet were at `feet` (current frame of `a`).
func pixels_at(a: Node2D, feet: Vector2) -> PackedVector2Array:
	var spr: AnimatedSprite2D = a.sprite
	var m := frame_mask(spr)
	var o := feet + spr.position + spr.offset + Vector2(0.5, 0.5)
	var out := PackedVector2Array()
	out.resize(m.size())
	for i in m.size():
		out[i] = o + (Vector2(m[i].x if not spr.flip_h else 31.0 - m[i].x, m[i].y))
	if out.is_empty():                              # no frame data: fall back to the body box
		var b := body_rect(feet)
		for iy in 7:
			for ix in 5:
				out.append(b.position + Vector2((ix + 0.5) * b.size.x / 5.0, (iy + 0.5) * b.size.y / 7.0))
	return out


static func centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	return c / maxf(1.0, float(pts.size()))


## How many of `pts` the opaque pixels of entry `idx` cover.
func covered_count(idx: int, pts: PackedVector2Array) -> int:
	var e: Dictionary = entries[idx]
	var rect: Rect2 = e["rect"]
	var img: Image = e["image"]
	var n := 0
	for q in pts:
		var lp := (q - rect.position).floor()
		if lp.x < 0 or lp.y < 0 or lp.x >= img.get_width() or lp.y >= img.get_height():
			continue
		if img.get_pixel(int(lp.x), int(lp.y)).a > 0.5:
			n += 1
	return n


## Share (0..1) of a body box at `feet` covered by entry `idx` (used to look for spots behind things).
func coverage(idx: int, feet: Vector2) -> float:
	var b := body_rect(feet)
	if not (entries[idx]["rect"] as Rect2).intersects(b):
		return 0.0
	var pts := PackedVector2Array()
	for iy in 7:
		for ix in 5:
			pts.append(b.position + Vector2((ix + 0.5) * b.size.x / 5.0, (iy + 0.5) * b.size.y / 7.0))
	return float(covered_count(idx, pts)) / float(pts.size())


## Entries drawn over (sorted after) feet `feet` whose rect meets the pixels `pts`.
func over(feet: Vector2, pts: PackedVector2Array) -> Array:
	var out := []
	if pts.is_empty():
		return out
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var seen := {}
	for cy in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
		for cx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
			for idx in grid.get(Vector2i(cx, cy), []):
				if seen.has(idx):
					continue
				seen[idx] = true
				var s: Sprite2D = entries[idx]["sprite"]
				if not s.visible or s.position.y <= feet.y:
					continue           # drawn behind her: nothing to see through
				if (entries[idx]["rect"] as Rect2).intersects(Rect2(lo, hi - lo + Vector2.ONE)):
					out.append(idx)
	return out


## Entries that hide enough of a character at `feet` (pixels `pts`; default: the rabbit's current frame) to fade:
## at least `coverage` of her pixels (tuning; a few pixels are enough).
func covering(feet: Vector2, pts := PackedVector2Array()) -> Array:
	if pts.is_empty():
		pts = pixels_at(main.player, feet)
	var need := maxi(2, int(ceil(float(cfg["coverage"]) * pts.size())))
	var out := []
	for idx in over(feet, pts):
		if covered_count(idx, pts) >= need:
			out.append(idx)
	return out


func _hole_alpha(q: Vector2, centers: Array, strength: float) -> float:
	var r := float(cfg["radius"])
	var soft := float(cfg["soft"])
	var hole := 0.0
	for c in centers:
		hole = maxf(hole, 1.0 - smoothstep(r - soft, r, q.distance_to(c)))
	return lerpf(1.0, float(cfg["min_alpha"]), hole * strength)


## Share (0..1) of a character's pixels that stay visible: a pixel is hidden when some picture drawn over her is
## opaque there with an effective alpha above 0.5. steady = true: as it will be once the fade has settled (only this
## character's own holes), false: as drawn right now (current fade strengths / holes of everyone).
func visible_fraction(a: Node2D, feet: Vector2, steady := false) -> float:
	var pts := pixels_at(a, feet)
	var fading := covering(feet, pts) if steady else []
	var c := [centroid(pts)]
	var hidden := 0
	var ov := over(feet, pts)
	for q in pts:
		for idx in ov:
			var e: Dictionary = entries[idx]
			var lp := (q - (e["rect"] as Rect2).position).floor()
			var img: Image = e["image"]
			if lp.x < 0 or lp.y < 0 or lp.x >= img.get_width() or lp.y >= img.get_height() or img.get_pixel(int(lp.x), int(lp.y)).a <= 0.5:
				continue
			var eff := (_hole_alpha(q, c, 1.0) if idx in fading else 1.0) if steady else alpha_at(e["sprite"], q)
			if eff > 0.5:
				hidden += 1
				break
	return 1.0 - float(hidden) / maxf(1.0, float(pts.size()))


func _process(delta: float) -> void:
	if main == null:
		return
	var want := {}
	for a in actors():
		var feet: Vector2 = a.global_position
		if main.interiors.room_at(feet) != "":
			continue
		var pts := pixels_at(a, feet)
		var cov := covering(feet, pts)
		if cov.is_empty():
			continue
		var c := centroid(pts)
		for idx in cov:
			if not want.has(idx):
				want[idx] = []
			if want[idx].size() < MAX_CENTERS:
				want[idx].append(c)
	var rate := float(cfg["fade_per_second"]) * delta
	for idx in want:
		if not active.has(idx):
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("radius", float(cfg["radius"]))
			mat.set_shader_parameter("soft", float(cfg["soft"]))
			mat.set_shader_parameter("min_alpha", float(cfg["min_alpha"]))
			entries[idx]["sprite"].material = mat
			active[idx] = {"strength": 0.0, "mat": mat, "centers": []}
		active[idx]["centers"] = want[idx]
	for idx in active.keys():
		var st: Dictionary = active[idx]
		var on := want.has(idx)
		st["strength"] = move_toward(float(st["strength"]), 1.0 if on else 0.0, rate)
		if not on and st["strength"] <= 0.0:
			entries[idx]["sprite"].material = null
			active.erase(idx)
			continue
		var s: Sprite2D = entries[idx]["sprite"]
		var pts2 := PackedVector2Array()
		for c in st["centers"]:
			pts2.append((c as Vector2) - s.position)
		while pts2.size() < MAX_CENTERS:
			pts2.append(Vector2(-99999, -99999))
		var mat: ShaderMaterial = st["mat"]
		mat.set_shader_parameter("centers", pts2)
		mat.set_shader_parameter("count", st["centers"].size())
		mat.set_shader_parameter("strength", st["strength"])


# ------------------------------------------------------------------ for tests / screenshots
func strength_of(sprite: Sprite2D) -> float:
	for idx in active:
		if entries[idx]["sprite"] == sprite:
			return float(active[idx]["strength"])
	return 0.0


## Alpha the shader gives the sprite's pixel at a world point right now (1 = untouched).
func alpha_at(sprite: Sprite2D, world: Vector2) -> float:
	for idx in active:
		if entries[idx]["sprite"] != sprite:
			continue
		var st: Dictionary = active[idx]
		var hole := 0.0
		var r := float(cfg["radius"])
		var soft := float(cfg["soft"])
		for c in st["centers"]:
			var d := world.distance_to(c)
			hole = maxf(hole, 1.0 - smoothstep(r - soft, r, d))
		return lerpf(1.0, float(cfg["min_alpha"]), hole * float(st["strength"]))
	return 1.0


func sprite_of(idx: int) -> Sprite2D:
	return entries[idx]["sprite"]
