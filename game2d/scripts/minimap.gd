class_name Minimap
extends Control
## 打磨 v1: small round minimap in the top-left corner, centred on the player (data/tuning.json "minimap": diameter,
## range outdoors / indoors, transparency). Outdoors it shows the map thumbnail around him, indoors the picture of the
## room he is in. Arrow = his facing. Star = the objective: drawn at its place when it is within range, otherwise on
## the rim in its direction (Interiors.minimap_target decides what it aims at: a room's door from outside, his own
## doorway - always on the rim - when the target is outside the room he is in). The HUD fades it when it would cover
## him, an NPC or something to press E on, and while a conversation is on screen.

const PAD := 96                         # dark border (thumbnail px) around the map so the circle never runs off it
const BACK := Color(0.12, 0.09, 0.08, 1)
const RIM := Color(0.85, 0.72, 0.5, 0.95)

var diameter := 56.0
var radius := 28.0
var blink_hz := 2.0
var range_out := 340.0                   # world px shown from the centre to the rim (outdoors)
var range_in := 210.0
var star_inset := 5.0
var map_tex: Texture2D                   # padded thumbnail of the whole map
var map_scale := 0.125                   # thumbnail px per world px
# 菜园扩建 v1: pictures laid over the thumbnail (the farm's weed / tilled state, so the map's striped crop rows never
# show here either): [{rect: world Rect2, img: Image of rect's size}], each box-averaged down to the thumbnail scale
var overlays: Array = []
var _base_img: Image                     # the padded thumbnail without overlays
var room_tex: Dictionary = {}            # room id -> padded room picture
var room_origin: Dictionary = {}         # room id -> world origin
var room_pad := 160

# state (also read by the tests)
var center_world := Vector2.ZERO         # the player
var room := ""                           # "" = outdoors
var arrow_dir := Vector2.DOWN
var player_marker := Vector2.ZERO        # local position of the arrow (always the centre)
var star_active := false                 # an objective with a star exists
var star_target_world := Vector2.ZERO    # what the star aims at (after the door rules)
var star_on_rim := false
var star_marker := Vector2.ZERO          # local position of the star
var star_shown := false                  # current blink phase
# 第④步第一批: extra dots - red = the accepted 悬赏's villains, yellow = where the accepted 委托 needs you next
# (set by Jianghu each frame: [{point: world Vector2, color: Color}]); out of range they sit on the rim like the star
var marks: Array = []
var mark_markers: Array = []             # [{local: Vector2, color: Color, rim: bool}] (tests)
# 新手指引 v1: the gold arrow of the tracked item (Guide.track_world -> Interiors.minimap_target: {point, rim} or null)
var track_active := false
var track_world := Vector2.ZERO
var track_marker := Vector2.ZERO          # local position of the arrow's tip
var track_on_rim := false
var track_dir := Vector2.DOWN             # where the arrow points
var _t := 0.0


func setup(map_thumb: Texture2D, world_size: Vector2, cfg: Dictionary) -> void:
	diameter = float(cfg["diameter"])
	radius = diameter * 0.5
	blink_hz = float(cfg["blink_per_second"])
	range_out = float(cfg["range"])
	range_in = float(cfg["range_indoor"])
	star_inset = float(cfg["star_inset"])
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_marker = Vector2(radius, radius)
	if map_thumb != null:
		map_scale = float(map_thumb.get_width()) / world_size.x
		map_tex = _padded(map_thumb.get_image(), PAD)
		_base_img = (map_tex as ImageTexture).get_image()
		if not overlays.is_empty():
			_apply_overlays()


## 菜园扩建 v1: replace the overlays (Farm calls this whenever the field changes state).
func set_overlays(list: Array) -> void:
	overlays = list
	_apply_overlays()


## Thumbnail pixel rectangle (padded texture) a world rectangle covers - outward, so it covers every thumbnail pixel
## the rectangle touches.
func thumb_rect(world: Rect2) -> Rect2i:
	var a := (world.position * map_scale).floor()
	var b := (world.end * map_scale).ceil()
	return Rect2i(Vector2i(a) + Vector2i(PAD, PAD), Vector2i(b - a))


## Box average of `img` (world pixels of `world`) into the thumbnail rectangle thumb_rect(world).
func overlay_pixels(world: Rect2, img: Image) -> Image:
	var tr := thumb_rect(world)
	var out := Image.create(maxi(1, tr.size.x), maxi(1, tr.size.y), false, Image.FORMAT_RGBA8)
	var inv := 1.0 / map_scale
	for ty in tr.size.y:
		for tx in tr.size.x:
			# the world block of this thumbnail pixel, clipped to the picture
			var wx0 := float(tr.position.x - PAD + tx) * inv - world.position.x
			var wy0 := float(tr.position.y - PAD + ty) * inv - world.position.y
			var x0 := clampi(int(floor(wx0)), 0, img.get_width() - 1)
			var y0 := clampi(int(floor(wy0)), 0, img.get_height() - 1)
			var x1 := clampi(int(ceil(wx0 + inv)), x0 + 1, img.get_width())
			var y1 := clampi(int(ceil(wy0 + inv)), y0 + 1, img.get_height())
			var acc := Color(0, 0, 0, 0)
			var n := 0
			for y in range(y0, y1):
				for x in range(x0, x1):
					acc += img.get_pixel(x, y)
					n += 1
			acc = acc / float(maxi(1, n))
			acc.a = 1.0
			out.set_pixel(tx, ty, acc)
	return out


func _apply_overlays() -> void:
	if _base_img == null or not (map_tex is ImageTexture):
		return
	var img := _base_img.duplicate()
	for o in overlays:
		var src: Image = o["img"]
		if src == null:
			continue
		var tr := thumb_rect(o["rect"])
		img.blit_rect(overlay_pixels(o["rect"], src), Rect2i(Vector2i.ZERO, tr.size), tr.position)
	map_tex = ImageTexture.create_from_image(img)     # (a new texture: rare, and update() keeps no image in headless runs)
	queue_redraw()


func add_room(id: String, picture: Texture2D, origin: Vector2) -> void:
	if picture == null:
		return
	room_tex[id] = _padded(picture.get_image(), room_pad)
	room_origin[id] = origin


static func _padded(img: Image, pad: int) -> ImageTexture:
	var src := img.duplicate()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create(src.get_width() + pad * 2, src.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	out.fill(BACK)
	out.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(pad, pad))
	return ImageTexture.create_from_image(out)


## World px -> minimap px at the current zoom (outdoors / indoors).
func scale_now() -> float:
	return radius / (range_in if room != "" else range_out)


## Local minimap position of a world point (may be outside the circle).
func world_to_local(p: Vector2) -> Vector2:
	return Vector2(radius, radius) + (p - center_world) * scale_now()


## `target` = Interiors.minimap_target(...) result or null (no star).
func update_state(player_pos: Vector2, player_room: String, facing_vec: Vector2, target: Variant) -> void:
	center_world = player_pos
	room = player_room if room_tex.has(player_room) else ""
	arrow_dir = facing_vec.normalized() if facing_vec != Vector2.ZERO else Vector2.DOWN
	star_active = target != null
	if star_active:
		star_target_world = target["point"]
		var off: Vector2 = (star_target_world - center_world) * scale_now()
		var lim := radius - star_inset
		star_on_rim = bool(target.get("rim", false)) or off.length() > lim
		if star_on_rim:
			var dir := off.normalized() if off.length() > 0.001 else Vector2.DOWN
			off = dir * lim
		star_marker = Vector2(radius, radius) + off
	_place_marks()
	queue_redraw()


func set_track(target: Variant) -> void:
	track_active = target != null
	if not track_active:
		return
	track_world = target["point"]
	var off: Vector2 = (track_world - center_world) * scale_now()
	var lim := radius - star_inset
	track_on_rim = bool(target.get("rim", false)) or off.length() > lim
	if track_on_rim:
		track_dir = off.normalized() if off.length() > 0.001 else Vector2.DOWN
		track_marker = Vector2(radius, radius) + track_dir * lim
	else:
		track_dir = Vector2.DOWN          # in range: a small arrow standing over the place, pointing down at it
		track_marker = Vector2(radius, radius) + off


## Angle from the centre to the arrow (tests: equals the world angle to the target when it sits on the rim).
func track_angle() -> float:
	return (track_marker - Vector2(radius, radius)).angle()


func set_marks(list: Array) -> void:
	marks = list
	_place_marks()


func _place_marks() -> void:
	mark_markers.clear()
	var lim := radius - star_inset
	for m in marks:
		var off: Vector2 = ((m["point"] as Vector2) - center_world) * scale_now()
		var rim := off.length() > lim
		if rim:
			off = (off.normalized() if off.length() > 0.001 else Vector2.DOWN) * lim
		mark_markers.append({"local": Vector2(radius, radius) + off, "color": m["color"], "rim": rim})


## Angle (radians) from the centre to the star on the minimap - equals the world angle to the target (tests).
func star_angle() -> float:
	return (star_marker - Vector2(radius, radius)).angle()


## Is a local point inside the circle (grown by `margin`)?
func covers_local(p: Vector2, margin := 0.0) -> bool:
	return p.distance_to(Vector2(radius, radius)) <= radius + margin


func _process(delta: float) -> void:
	_t += delta
	var shown := star_active and fmod(_t * blink_hz, 1.0) < 0.6
	if shown != star_shown:
		star_shown = shown
		queue_redraw()


func _circle(r: float, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(radius, radius) + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var c := Vector2(radius, radius)
	var pts := _circle(radius)
	draw_colored_polygon(pts, BACK)
	# the picture: UVs of the circle points in the padded texture
	var tex: Texture2D = map_tex
	var px_per_world := map_scale
	var org := Vector2.ZERO
	var pad := float(PAD)
	if room != "":
		tex = room_tex[room]
		px_per_world = 1.0
		org = room_origin[room]
		pad = float(room_pad)
	if tex != null:
		var k := px_per_world / scale_now()          # texture px per minimap px
		var uvs := PackedVector2Array()
		var tsize := Vector2(tex.get_width(), tex.get_height())
		for p in pts:
			var tp := (center_world - org) * px_per_world + Vector2(pad, pad) + (p - c) * k
			uvs.append(tp / tsize)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(Color(1, 1, 1, 1))
		draw_polygon(pts, cols, uvs, tex)
	draw_arc(c, radius - 0.5, 0.0, TAU, 48, Color(0.1, 0.06, 0.05, 0.9), 2.0)
	draw_arc(c, radius - 0.5, 0.0, TAU, 48, RIM, 1.0)
	for mk in mark_markers:
		var mp: Vector2 = (mk["local"] as Vector2).round()
		draw_circle(mp, 3.0, Color(0.1, 0.05, 0.05, 1))
		draw_circle(mp, 2.0, mk["color"])
	if star_shown:
		_draw_star(star_marker.round(), 4.0)
	if track_active:
		_draw_arrow(track_marker.round(), track_dir)
	var tip := c + arrow_dir * 4.5
	var side := arrow_dir.orthogonal()
	var back := c - arrow_dir * 3.0
	var ap := PackedVector2Array([tip, back + side * 3.0, c - arrow_dir * 1.0, back - side * 3.0])
	draw_colored_polygon(ap, Color(1, 1, 1, 1))
	draw_polyline(PackedVector2Array([ap[0], ap[1], ap[2], ap[3], ap[0]]), Color(0.1, 0.05, 0.05, 1), 1.0)


## The gold arrow: tip at `tip`, pointing along `dir`.
func _draw_arrow(tip: Vector2, dir: Vector2) -> void:
	var side := dir.orthogonal()
	var base := tip - dir * 6.0
	var pts := PackedVector2Array([tip, base + side * 3.5, base - side * 3.5])
	draw_colored_polygon(pts, Color(1.0, 0.82, 0.18, 1))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.45, 0.25, 0.02, 1), 1.0)


func _draw_star(cpos: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(cpos + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.86, 0.2, 1))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.45, 0.2, 0.05, 1), 1.0)
