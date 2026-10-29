class_name Interiors
extends Node2D
## 室内图进游戏 v1: the enterable rooms (主角与师兄宿舍、杂物间、旧弟子房、正殿、厨房).
## Every room lives in the SAME world as the outdoor map, placed to the right of it (data/interiors.json "origin"),
## with its own picture (assets/interiors/<id>.png), y-sorted furniture cutouts (<id>_front.png), wall tops drawn
## above the characters (<id>_over.png) and collision boxes (rooms.json, written by pixel2d/interiors/tools/
## generate_interiors.py). Walking into an outdoor door (towards it) fades out, moves the rabbit just inside the room
## door, fades in; walking out of the room door does the reverse. The room the player is in is worked out from him
## position every frame, so the camera limits, the minimap (building position), the indoor light and the doors always
## agree with where he really is (after a door, a respawn or a test teleport alike).
## Also: the opening in bed (asleep -> the drip -> sitting up -> out of bed) and the leaking roof drips of the dorm.
## 打磨 v1: light = unlit room picture + a time-controlled additive daylight layer (<id>_light.png: window / door light,
## shafts) + night light sources per room (rooms.json "lights": oil lamp, candles, 长明灯, stove fire, faint moonlight);
## the minimap star target (minimap_target); the v4 dorm: bucket water level (rises with every drop, overflows in the
## opening), the puddle (shrinks one ring per wipe), the rag in the corner, the wardrobe (open / shut), the second leak
## onto 师兄's pillow.

signal room_changed(id: String)
signal transition_finished(room: String)

const DATA := "res://data/interiors.json"
const ROOMS := "res://assets/interiors/rooms.json"
const BACKDROP := Color(0.118, 0.086, 0.07)     # dark wall-top brown around a room (never an empty void)
const BACKDROP_MARGIN := 720.0
const ENTER_INSET := 18.0                        # px inside the room door where the rabbit appears
const EXIT_OUT := 22.0                           # px below the outdoor wall foot where he appears outside
const TRIGGER_DEPTH := 12.0                      # outdoor trigger strip below the wall foot
const ROOM_GROW := 64.0                          # a point this close to a room still counts as inside it
const SIT_Y := 92.0                              # player node y (room px) while sitting up in bed / lying
const HEAD_X := 247.0

var main: Node
var cfg: Dictionary
var rooms: Dictionary = {}       # id -> {def, origin, rect, door, footprint, sprites, lamp}
var enabled := true              # doors work (off in the story-less sandbox of the older test suites)
var current := ""                # room the player is in ("" = outdoors)
var transitioning := false
var transitions := 0             # statistics for tests
var history: Array = []          # [{from, to, pos}] every door use (tests)
var ground_node: Node2D
var over_node: Node2D
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var drips: InteriorDrips
var npc_homes: Dictionary = {}   # npc id -> [outdoor position, dir] (the sandbox puts them back)
var bed_state := "empty"         # sleeping | sitting | empty (opening)
var bed_sleeping: Sprite2D
var bed_quilt: Sprite2D
var light_node: Node2D
var flames: InteriorFlames
var night_level := 0.0           # last lamp level applied (0 day .. 1 night)
var shaft_strength := 1.0        # last daylight-layer strength applied (tests)
# v4 dorm water
var water_level := 0.55          # bucket 0 empty .. 1 brim
var water_cap := 1.0             # the drops raise the level up to this (after pouring: no second overflow)
var puddle_size := 0.0           # 0 none .. 1 the full overflow puddle
var overflowing := false
var pours := 0
var bucket_drops := 0
var rag_sprite: Sprite2D
var rag_glow: RagGlow            # 试玩反馈 v1: blinking bright edge + gold sparkles on the rag (child of rag_sprite)
var wardrobe_open_sprite: Sprite2D
var wardrobe_is_open := false
var bucket_water: BucketWater
var puddle_draw: PuddleDraw
var leak_stopped: Dictionary = {}   # room id -> true once its roof is mended (两条路小样 v1)
var _cooldown := 0.0
var _armed := true               # a door only works after the player has let go of / stepped out of the last one


func _init() -> void:
	name = "Interiors"


func build(m: Node) -> void:
	main = m
	cfg = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var rd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOMS))
	var defs := {}
	for r in rd["rooms"]:
		defs[r["id"]] = r
	ground_node = Node2D.new()
	ground_node.name = "InteriorGround"
	main.add_child(ground_node)
	main.move_child(ground_node, main.world.get_index())       # drawn below the y-sorted world
	over_node = Node2D.new()
	over_node.name = "InteriorOver"
	main.add_child(over_node)
	main.move_child(over_node, main.world.get_index() + 1)     # drawn above it
	light_node = Node2D.new()
	light_node.name = "InteriorLight"
	main.add_child(light_node)
	main.move_child(light_node, over_node.get_index() + 1)     # daylight layer + flames above the wall tops
	for id in cfg["rooms"]:
		var c: Dictionary = cfg["rooms"][id]
		var d: Dictionary = defs[id]
		var o := Vector2(c["origin"][0], c["origin"][1])
		var size := Vector2(d["size"][0], d["size"][1])
		var fp: Array = c["footprint"]
		var room := {"id": id, "def": d, "origin": o, "rect": Rect2(o, size), "door": c["door"],
			"footprint": Rect2(fp[0], fp[1], fp[2], fp[3]), "furniture": {}}
		rooms[id] = room
		_build_room(room)
	drips = InteriorDrips.new()
	drips.setup(self)
	over_node.add_child(drips)
	flames = InteriorFlames.new()
	flames.setup(self)
	light_node.add_child(flames)
	_build_dorm_water()
	fade_layer = CanvasLayer.new()
	fade_layer.name = "DoorFade"
	fade_layer.layer = 9            # under the HUD (10) and the dialogue (20): only the world goes dark
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.05, 0.04, 0.05, 0.0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)


func _build_room(room: Dictionary) -> void:
	var id: String = room["id"]
	var d: Dictionary = room["def"]
	var o: Vector2 = room["origin"]
	# 两条路小样 v1: a repaired room is rebuilt from its own pictures (tex = path prefix without "_front.png" etc.);
	# every node made here is listed in room["nodes"] so apply_variant() can take the old ones away
	var tex_base: String = room.get("tex", "res://assets/interiors/" + id)
	var nodes: Array = []
	room["nodes"] = nodes
	if not room.has("backdrop"):
		var back := ColorRect.new()
		back.name = "Backdrop_" + id
		back.color = BACKDROP
		back.position = o - Vector2(BACKDROP_MARGIN, BACKDROP_MARGIN)
		back.size = room["rect"].size + Vector2(BACKDROP_MARGIN, BACKDROP_MARGIN) * 2.0
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground_node.add_child(back)
		ground_node.move_child(back, 0)        # every backdrop below every room picture (backdrops overlap)
		room["backdrop"] = back
	var base := Sprite2D.new()
	base.name = "Room_" + id
	base.texture = load(tex_base + ".png")
	base.centered = false
	base.position = o
	ground_node.add_child(base)
	if room.has("ground_index"):
		ground_node.move_child(base, int(room["ground_index"]))   # a rebuilt room stays under the puddle / rag layer
	nodes.append(base)
	room["base_tex"] = base.texture
	var front: Texture2D = load(tex_base + "_front.png")
	for f in d["furniture"]:
		var s := _atlas_sprite(front, f["atlas"])
		var r: Array = f["rect"]
		s.position = o + Vector2(r[0], f["sort_y"])
		s.offset = Vector2(0, float(r[1]) - float(f["sort_y"]))
		s.set_meta("type", "interior:" + String(f["type"]))
		s.set_meta("room", id)
		s.name = "Furniture_%s_%s" % [id, f["name"]]
		main.world.add_child(s)
		room["furniture"][f["name"]] = s
		nodes.append(s)
	var over := Sprite2D.new()
	over.name = "Over_" + id
	over.texture = load(tex_base + "_over.png")
	over.centered = false
	over.position = o
	over_node.add_child(over)
	nodes.append(over)
	for c in d["colliders"]:
		var rr: Array = c["rect"]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rr[2], rr[3])
		cs.shape = shape
		cs.position = o + Vector2(rr[0] + rr[2] * 0.5, rr[1] + rr[3] * 0.5)
		cs.set_meta("kind", "interior_wall" if c["kind"] == "wall" else "interior:" + String(c["kind"]))
		cs.set_meta("room", id)
		main.solids.add_child(cs)
		nodes.append(cs)
	# 打磨 v1: the daylight of the room (windows, door, shafts) as an additive layer the hour turns up / down
	var ls := Sprite2D.new()
	ls.name = "Daylight_" + id
	ls.texture = load(tex_base + "_light.png")
	ls.centered = false
	ls.position = o
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ls.material = mat
	light_node.add_child(ls)
	room["daylight"] = ls
	nodes.append(ls)
	# night light sources (rooms.json "lights"): warm glows for lamps / candles / fire, a faint cool one for moonlight
	room["lights"] = []
	var kinds: Dictionary = Tuning.data()["indoor"]["lights"]
	var tex := _radial_texture()
	for spec in d.get("lights", []):
		var kc: Dictionary = kinds[String(spec["kind"])]
		var l := PointLight2D.new()
		l.name = "Light_%s_%d" % [id, room["lights"].size()]
		l.texture = tex
		l.texture_scale = float(spec.get("radius", kc["radius"])) * 2.0 / 128.0
		l.color = Tuning.color(kc["color"])
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.energy = 0.0
		l.visible = false
		l.global_position = o + Vector2(spec["pos"][0], spec["pos"][1])
		l.set_meta("kind", String(spec["kind"]))
		l.set_meta("base_energy", float(spec.get("energy", kc["energy"])))
		add_child(l)
		room["lights"].append(l)
		nodes.append(l)
	# the opening: the player's bed asleep / the quilt alone (sitting up), drawn above the empty bed
	var v: Dictionary = d.get("variants", {})
	if v.has("bed_sleeping") and bed_sleeping == null:
		bed_sleeping = _atlas_sprite(front, v["bed_sleeping"]["atlas"])
		var br: Array = v["bed_sleeping"]["rect"]
		bed_sleeping.position = o + Vector2(br[0], br[1])
		bed_sleeping.z_index = 1
		bed_sleeping.name = "BedSleeping"
		bed_sleeping.visible = false
		main.world.add_child(bed_sleeping)
		bed_quilt = _atlas_sprite(front, v["bed_quilt"]["atlas"])
		var qr: Array = v["bed_quilt"]["rect"]
		bed_quilt.position = o + Vector2(qr[0], qr[1])
		bed_quilt.z_index = 3
		bed_quilt.name = "BedQuilt"
		bed_quilt.visible = false
		main.world.add_child(bed_quilt)


func _atlas_sprite(tex: Texture2D, a: Array) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = Rect2(a[0], a[1], a[2], a[3])
	return s


## 两条路小样 v1: swaps a room for its repaired version (rooms_fixed.json entry `def`, pictures at `tex` + ".png",
## "_front.png", "_over.png", "_light.png"): the old picture, furniture, wall tops, colliders, daylight layer and lights go,
## the new ones are built at the same origin. Anchors / spots the new layout does not list are kept (the room's optional
## lines stay where they were). The dorm's leak (drips, bucket water, puddle) stops with it. Calling it again is a no-op.
func apply_variant(id: String, def: Dictionary, tex: String) -> void:
	if not rooms.has(id) or String(rooms[id].get("tex", "")) == tex:
		return
	var room: Dictionary = rooms[id]
	var old_nodes: Array = room.get("nodes", [])
	room["ground_index"] = (old_nodes[0] as Node).get_index() if not old_nodes.is_empty() else -1
	for n in old_nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	var anchors: Dictionary = (room["def"].get("anchors", {}) as Dictionary).duplicate()
	anchors.merge(def.get("anchors", {}), true)
	var spots: Dictionary = (room["def"].get("spots", {}) as Dictionary).duplicate()
	spots.merge(def.get("spots", {}), true)
	var nd := def.duplicate(true)
	nd["anchors"] = anchors
	nd["spots"] = spots
	room["def"] = nd
	room["tex"] = tex
	room["furniture"] = {}
	if id == opening_room():
		bucket_water = null       # it hung on the old bucket sprite
	_build_room(room)
	if int(room["ground_index"]) < 0:
		room.erase("ground_index")
	stop_leak(id)
	if main.get("hud") != null:
		main.hud.minimap.add_room(id, room["base_tex"], room["origin"])
	if id == opening_room() and wardrobe_open_sprite != null:
		set_wardrobe_open(false)


## The roof no longer leaks into this room: no drops, no bucket water, no puddle. Also the stand-in while the repaired
## pictures are missing (then the bucket furniture is hidden here).
func stop_leak(id: String) -> void:
	if drips != null:
		drips.remove_room(id)
	leak_stopped[id] = true
	if id == opening_room():
		puddle_size = 0.0
		overflowing = false
		water_level = 0.0
		if puddle_draw != null:
			puddle_draw.visible = false
		var b: Node = rooms[id]["furniture"].get("bucket", null)
		if b != null:
			b.visible = false


func _radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.5, 0.5, 0.5, 1), Color(0, 0, 0, 1)])
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


# ------------------------------------------------------------------ NPCs in rooms / sandbox
## 序章 v3: 师父 in the hall (before the ancestor portrait), 厨娘 in the kitchen (by the stove).
func place_npcs() -> void:
	for id in cfg.get("npcs", {}):
		var spec: Dictionary = cfg["npcs"][id]
		var n: Npc = _npc(id)
		if n == null:
			continue
		if not npc_homes.has(id):
			npc_homes[id] = [n.global_position, n.home_dir]
		var sp: Dictionary = rooms[spec["room"]]["def"]["spots"][spec["spot"]]
		n.global_position = rooms[spec["room"]]["origin"] + Vector2(sp["pos"][0], sp["pos"][1])
		n.home_dir = String(sp["dir"])
		n.face(n.home_dir)


## The story layer off (older test suites): doors off, everyone at the outdoor spots of characters.toml, the rabbit at
## the outdoor spawn - exactly the v1/v2 layout those suites check.
func enter_sandbox() -> void:
	enabled = false
	for id in npc_homes:
		var n: Npc = _npc(id)
		n.global_position = npc_homes[id][0]
		n.home_dir = npc_homes[id][1]
		n.face(n.home_dir)
	_set_bed("empty")
	var p: Player = main.player
	p.global_position = Vector2(main.data["spawn"]["x"], main.data["spawn"]["y"])
	p.facing = String(main.data["spawn"].get("dir", "down"))
	p.sprite.play("idle_" + p.facing)
	p.velocity = Vector2.ZERO
	current = ""


func _npc(id: String) -> Npc:
	for n in main.npcs:
		if n.id == id:
			return n
	return null


# ------------------------------------------------------------------ geometry
func room_at(p: Vector2) -> String:
	for id in rooms:
		if (rooms[id]["rect"] as Rect2).grow(ROOM_GROW).has_point(p):
			return id
	return ""


func origin(id: String) -> Vector2:
	return rooms[id]["origin"]


func world_point(id: String, local: Vector2) -> Vector2:
	return rooms[id]["origin"] + local


## An interactable's spot (rooms.json "anchors"), world coordinates.
func anchor(id: String, name_: String) -> Vector2:
	var a: Array = rooms[id]["def"]["anchors"][name_]
	return rooms[id]["origin"] + Vector2(a[0], a[1])


## The outdoor door of a room (what the minimap star points at while the target is inside and the player is not).
func door_point(id: String) -> Vector2:
	var d: Dictionary = rooms[id]["door"]
	return Vector2(d["x"], float(d["bottom"]) + 6.0)


## Where the rabbit stands after leaving a room (outside its door, facing away from it).
func exit_spot(id: String) -> Vector2:
	var d: Dictionary = rooms[id]["door"]
	return Vector2(d["x"], float(d["bottom"]) + EXIT_OUT)


## Where he stands after entering (just inside the room door).
func entry_spot(id: String) -> Vector2:
	var dd: Dictionary = rooms[id]["def"]["doors"][0]
	var x := (float(dd["x0"]) + float(dd["x1"])) * 0.5
	return rooms[id]["origin"] + Vector2(roundf(x), float(rooms[id]["def"]["door_y"]) - ENTER_INSET)


## Outdoor trigger strip of a room's door (feet inside it + walking towards the door = go in).
func outdoor_trigger(id: String) -> Rect2:
	var d: Dictionary = rooms[id]["door"]
	var h := float(d["half"]) + 0.5      # inclusive: feet up to `half` px either side of the door centre
	return Rect2(float(d["x"]) - h, float(d["bottom"]) - 2.0, h * 2.0, TRIGGER_DEPTH + 2.0)


## Indoor trigger strip (the doorway at the bottom of the room).
func indoor_trigger(id: String) -> Rect2:
	var dd: Dictionary = rooms[id]["def"]["doors"][0]
	var y := float(rooms[id]["def"]["door_y"])
	var cx := (float(dd["x0"]) + float(dd["x1"])) * 0.5
	# fix round: as forgiving as outside - feet up to `half` px from the doorway centre count (pressed against the
	# wall beside a narrow doorway), never narrower than the doorway itself (the wide hall door)
	var h := maxf((float(dd["x1"]) - float(dd["x0"])) * 0.5 - 2.0, float(rooms[id]["door"]["half"])) + 0.5
	return Rect2(rooms[id]["origin"] + Vector2(cx - h, y - 8.0), Vector2(h * 2.0, 40.0))


## 打磨 v1 minimap star: where the star aims for a target at world point `target` while the player is in `player_room`:
## same place (outdoors / same room) -> the target itself; target in a room, player outdoors -> that room's outdoor door;
## player indoors, target elsewhere -> his room's doorway, always on the rim ("go out of the door").
func minimap_target(target: Vector2, player_room: String) -> Dictionary:
	var tr := room_at(target)
	if player_room == "":
		return {"point": target if tr == "" else door_point(tr), "rim": false}
	if tr == player_room:
		return {"point": target, "rim": false}
	return {"point": doorway_point(player_room), "rim": true}


## The doorway of a room (inside, at the threshold) in world coordinates.
func doorway_point(id: String) -> Vector2:
	var dd: Dictionary = rooms[id]["def"]["doors"][0]
	return rooms[id]["origin"] + Vector2((float(dd["x0"]) + float(dd["x1"])) * 0.5, float(rooms[id]["def"]["door_y"]))


func footprint_point(id: String, p: Vector2) -> Vector2:
	var rect: Rect2 = rooms[id]["rect"]
	var fp: Rect2 = rooms[id]["footprint"]
	var k := ((p - rect.position) / rect.size).clamp(Vector2.ZERO, Vector2.ONE)
	return fp.position + k * fp.size


# ------------------------------------------------------------------ camera / light
## Camera limits: the map outdoors, the room indoors (centred on it where the room is smaller than the view).
func apply_camera(cam: Camera2D, focus: Vector2) -> void:
	var r := room_at(focus)
	var rect := Rect2(Vector2.ZERO, main.map_size) if r == "" else (rooms[r]["rect"] as Rect2)
	var view: Vector2 = main.get_viewport_rect().size / cam.zoom
	var lim := [rect.position.x, rect.position.y, rect.end.x, rect.end.y]
	if r != "":
		if rect.size.x < view.x:
			lim[0] = rect.get_center().x - view.x * 0.5
			lim[2] = rect.get_center().x + view.x * 0.5
		if rect.size.y < view.y:
			lim[1] = rect.get_center().y - view.y * 0.5
			lim[3] = rect.get_center().y + view.y * 0.5
	cam.limit_left = int(floor(lim[0]))
	cam.limit_top = int(floor(lim[1]))
	cam.limit_right = int(ceil(lim[2]))
	cam.limit_bottom = int(ceil(lim[3]))


## 打磨 v1 indoor look of the hour (tuning.json "indoor"): follows the outdoor tint but softer - pulled towards a warm
## interior white (a lot by day, little at night: `mix_day` .. `mix_night` with the lamp level), so dusk is warmer and
## night darker; never darker than `night_min_luminance` (per-room override in "rooms": the lamp-less old dorm and
## storage get a higher floor) and never brighter than `max_luminance`. The lamps / shafts are separate (apply_light).
static func indoor_look(look: Dictionary, lamps := 0.0, room := "") -> Dictionary:
	var c: Dictionary = Tuning.data()["indoor"]
	var warm := Tuning.color(c["warm"])
	var mix := lerpf(float(c["mix_day"]), float(c["mix_night"]), clampf(lamps, 0.0, 1.0))
	var tint: Color = (look["tint"] as Color).lerp(warm, mix)
	var lum := tint.get_luminance()
	var floor_l := night_floor(room)
	if lum < floor_l and lum > 0.0:
		var k := floor_l / lum
		tint = Color(minf(1.0, tint.r * k), minf(1.0, tint.g * k), minf(1.0, tint.b * k))
	var cap := float(c["max_luminance"])
	if tint.get_luminance() > cap:
		var k2 := cap / tint.get_luminance()
		tint = Color(tint.r * k2, tint.g * k2, tint.b * k2)
	return {"tint": tint, "desaturate": minf(float(look["desaturate"]), float(c["desaturate"])),
		"vignette": minf(float(look["vignette"]), float(c["vignette"])), "name": look["name"]}


static func night_floor(room: String) -> float:
	var c: Dictionary = Tuning.data()["indoor"]
	return float(c.get("rooms", {}).get(room, {}).get("night_min_luminance", c["night_min_luminance"]))


## Daylight layer strength / colour of the hour: full by day, a faint cool moonlight at night (tuning "indoor.shafts").
static func shaft_look(lamps: float) -> Color:
	var sh: Dictionary = Tuning.data()["indoor"]["shafts"]
	var n := clampf(lamps, 0.0, 1.0)
	var col := Tuning.color(sh["day_color"]).lerp(Tuning.color(sh["night_color"]), n)
	col.a = lerpf(float(sh["day_alpha"]), float(sh["night_alpha"]), n)
	return col


## Every frame (main): lamp level of the hour, how far the player is "inside" (0 outdoors .. 1 indoors, eased over the
## door fade so nothing jumps), ambience on/off. Lights of the room he is in glow with the lamp level; the daylight
## layers follow the hour.
func apply_light(level: float, inside_k: float, on: bool) -> void:
	night_level = level
	var sl := shaft_look(level)
	shaft_strength = sl.a if on else 1.0
	for id in rooms:
		var ds: Sprite2D = rooms[id]["daylight"]
		ds.modulate = sl if on else Color(1, 1, 1, 1)
		for l in rooms[id]["lights"]:
			var kind: String = l.get_meta("kind")
			var lv := level if kind != "eternal_lamp" else maxf(level, 0.2)
			var lit: bool = on and lv > 0.001 and id == current and inside_k > 0.001
			l.visible = lit
			l.enabled = lit
			l.energy = float(l.get_meta("base_energy")) * lv * inside_k * flames.flicker(l) if lit else 0.0


## The lights of a room that are glowing right now (tests).
func lit_lights(id: String) -> Array:
	return rooms[id]["lights"].filter(func(l): return l.visible and l.energy > 0.05)


# ------------------------------------------------------------------ doors
func _blocked() -> bool:
	var st = main.story
	if st == null or st.sandbox or st.busy or st._modal_open():
		return true
	var c: Combat = main.combat
	if c.blocks_interaction() or c.story_hold:
		return true
	var p: Player = main.player
	return not p.input_enabled or p.dead


func _physics_process(delta: float) -> void:
	if main == null:
		return
	var p: Player = main.player
	var r := room_at(p.global_position)
	if r != current:
		current = r
		if OS.has_feature("web"):
			print("interior: %s" % (r if r != "" else "outdoors"))
		room_changed.emit(r)
	_cooldown = maxf(0.0, _cooldown - delta)
	if not enabled or transitioning or _blocked():
		return
	var mv := p.move_input()
	var pos := p.global_position
	if current == "":
		var in_any := false
		for id in rooms:
			if outdoor_trigger(id).has_point(pos):
				in_any = true
				if _armed and _cooldown <= 0.0 and mv.y < -0.3:
					enter_room(id)
					return
		if not in_any:
			_armed = true
	else:
		var t := indoor_trigger(current)
		if t.has_point(pos):
			if _armed and _cooldown <= 0.0 and mv.y > 0.3:
				leave_room(current)
				return
		else:
			_armed = true


func enter_room(id: String) -> void:
	await _transition(entry_spot(id), "up", "", id)


func leave_room(id: String) -> void:
	await _transition(exit_spot(id), "down", id, "")


func _transition(to: Vector2, facing: String, from_room: String, to_room: String) -> void:
	transitioning = true
	_armed = false
	var p: Player = main.player
	p.input_enabled = false
	p.velocity = Vector2.ZERO
	var secs := float(cfg.get("fade_seconds", 0.22))
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, secs)
	await tw.finished
	p.dash_time_left = 0.0
	p.global_position = to
	p.facing = facing
	p.sprite.play("idle_" + facing)
	current = room_at(to)
	main._update_camera()
	transitions += 1
	history.append({"from": from_room, "to": to_room, "pos": to})
	if OS.has_feature("web"):
		print("interior: door %s -> %s" % [from_room if from_room != "" else "outdoors", to_room if to_room != "" else "outdoors"])
	var tw2 := create_tween()
	tw2.tween_property(fade_rect, "color:a", 0.0, secs)
	await tw2.finished
	_cooldown = float(cfg.get("cooldown_seconds", 0.35))
	transitioning = false
	var c: Combat = main.combat
	p.input_enabled = not (main.story.busy or c.spar_state == "choosing" or c.spar_state == "result" or c.player_dead)
	transition_finished.emit(current)


## Instantly puts the rabbit outside a room's door (after the ending: he walked out of the hall).
func place_outside(id: String) -> void:
	var p: Player = main.player
	p.global_position = exit_spot(id)
	p.facing = "down"
	p.sprite.play("idle_down")
	current = ""
	_armed = false


# ------------------------------------------------------------------ the opening in bed
func opening_room() -> String:
	return String(cfg.get("opening_room", "dorm_main"))


## Where the rabbit lies (node position: his head on the pillow).
func bed_world() -> Vector2:
	return world_point(opening_room(), Vector2(HEAD_X, SIT_Y))


## Where he stands after getting up ([start] of the dorm layout).
func getup_world() -> Vector2:
	var s: Array = rooms[opening_room()]["def"]["start"]
	return world_point(opening_room(), Vector2(s[0], s[1]))


func head_world() -> Vector2:
	return world_point(opening_room(), Vector2(HEAD_X, 66.0))


func start_opening() -> void:
	var p: Player = main.player
	p.global_position = bed_world()
	p.facing = "down"
	p.sprite.play("idle_down")
	current = ""        # the next physics frame notices the room (and logs it on the web)
	_set_bed("sleeping")
	var w: Dictionary = Tuning.data()["dorm_water"]
	water_level = float(w["start_level"])
	water_cap = 1.0
	puddle_size = 0.0
	overflowing = false


func _set_bed(state: String) -> void:
	bed_state = state
	var p: Player = main.player
	if bed_sleeping != null:
		bed_sleeping.visible = state == "sleeping"
		bed_quilt.visible = state == "sitting"
	p.sprite.visible = state != "sleeping"
	p.z_index = 2 if state == "sitting" else 0


## 画面：屋顶漏下的雨水，一滴一滴落进床边的木桶。桶里的水越来越满。 - the drops come faster, the level climbs to the brim.
func bucket_fill() -> void:
	var w: Dictionary = Tuning.data()["dorm_water"]
	drips.fast = true
	var tw := create_tween()
	tw.tween_property(self, "water_level", 1.0, float(w["fill_seconds"])).set_trans(Tween.TRANS_SINE)
	await tw.finished
	drips.fast = false
	await get_tree().create_timer(0.2, false).timeout


## ……哗啦。 -> 画面：木桶满了，水漫出来，在地上淌开一大滩。 - water spills over the rim and spreads into a puddle.
func bucket_overflow() -> void:
	var w: Dictionary = Tuning.data()["dorm_water"]
	overflowing = true
	if OS.has_feature("web"):
		print("interior: bucket overflow")
	var tw := create_tween()
	tw.tween_property(self, "puddle_size", 1.0, float(w["overflow_seconds"])).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	overflowing = false
	water_cap = 1.0
	await get_tree().create_timer(0.15, false).timeout


## "……嗯？什么声音……": he sits up behind the quilt (startled by the splash).
func sit_up() -> void:
	_set_bed("sitting")
	var p: Player = main.player
	p.facing = "down"
	p.sprite.play("idle_down")
	main.story.fx.float_text("!", head_world() + Vector2(10, 12))
	var tw := create_tween()
	tw.tween_property(p.sprite, "offset", Vector2(-16, -34), 0.08)
	tw.tween_property(p.sprite, "offset", Vector2(-16, -31), 0.12)
	await tw.finished


## Out of bed: he hops to the floor beside the bed; the quilt stays thrown back.
func get_up() -> void:
	var p: Player = main.player
	_set_bed("empty")
	p.z_index = 2
	var to := getup_world()
	p.facing = "left"
	p.sprite.play("walk_left")
	var tw := create_tween()
	tw.tween_property(p, "global_position", to, 0.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-16, -37), 0.25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-16, -31), 0.25).set_delay(0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	p.z_index = 0
	p.facing = "down"
	p.sprite.play("idle_down")


# ------------------------------------------------------------------ v4 dorm: bucket, puddle, rag, wardrobe
func _build_dorm_water() -> void:
	var id := opening_room()
	if not rooms.has(id):
		return
	var room: Dictionary = rooms[id]
	var d: Dictionary = room["def"]
	var o: Vector2 = room["origin"]
	var front: Texture2D = load("res://assets/interiors/%s_front.png" % id)
	var v: Dictionary = d.get("variants", {})
	var wd: Dictionary = d.get("water", {})
	if wd.has("bucket") and room["furniture"].has("bucket"):
		bucket_water = BucketWater.new()
		bucket_water.setup(self, o + Vector2(wd["bucket"]["center"][0], wd["bucket"]["center"][1]), float(wd["bucket"]["r"]))
		room["furniture"]["bucket"].add_child(bucket_water)      # sorts with the bucket
	if wd.has("puddle"):
		puddle_draw = PuddleDraw.new()
		puddle_draw.setup(self, o, wd["puddle"]["blobs"])
		ground_node.add_child(puddle_draw)                        # on the floor, under everyone
	if v.has("rag"):
		rag_sprite = _atlas_sprite(front, v["rag"]["atlas"])
		var rr: Array = v["rag"]["rect"]
		rag_sprite.position = o + Vector2(rr[0], rr[1])
		rag_sprite.name = "Rag"
		ground_node.add_child(rag_sprite)
		rag_glow = RagGlow.new()
		rag_glow.setup(front, Rect2(v["rag"]["atlas"][0], v["rag"]["atlas"][1], v["rag"]["atlas"][2], v["rag"]["atlas"][3]))
		rag_sprite.add_child(rag_glow)        # hidden with the rag once it is taken
	if v.has("wardrobe_open") and room["furniture"].has("wardrobe"):
		var ws: Sprite2D = room["furniture"]["wardrobe"]
		wardrobe_open_sprite = _atlas_sprite(front, v["wardrobe_open"]["atlas"])
		var wr: Array = v["wardrobe_open"]["rect"]
		wardrobe_open_sprite.position = ws.position
		wardrobe_open_sprite.offset = Vector2(float(wr[0]), float(wr[1])) + o - ws.position
		wardrobe_open_sprite.name = "WardrobeOpen"
		wardrobe_open_sprite.visible = false
		main.world.add_child(wardrobe_open_sprite)


## A drop landed in the bucket: the level rises a little (up to the cap).
func _bucket_drop() -> void:
	bucket_drops += 1
	if overflowing:
		return
	var w: Dictionary = Tuning.data()["dorm_water"]
	water_level = minf(water_cap, water_level + float(w["per_drop"]))


func take_rag() -> void:
	if rag_sprite != null:
		rag_sprite.visible = false
	if OS.has_feature("web"):
		print("interior: rag taken")


## Wipe number n (1..3): the puddle shrinks one ring (tuning dorm_water.wipe_sizes), with a little scrub of the rabbit.
func wipe_to(n: int) -> void:
	var sizes: Array = Tuning.data()["dorm_water"]["wipe_sizes"]
	var target := float(sizes[clampi(n, 0, sizes.size() - 1)])
	var p: Player = main.player
	var tw := create_tween()
	tw.tween_property(self, "puddle_size", target, 0.35)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-14, -31), 0.09)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-18, -31), 0.09).set_delay(0.09)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-16, -31), 0.09).set_delay(0.18)
	await tw.finished


## 画面：小兔把木桶里的水倒掉，放回原处。 - he steps to the bucket, it empties; it goes on catching drops (to the cap).
func pour_bucket() -> void:
	var w: Dictionary = Tuning.data()["dorm_water"]
	var p: Player = main.player
	var tw := create_tween()
	tw.tween_property(self, "water_level", 0.0, 0.6).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-16, -35), 0.15)
	tw.parallel().tween_property(p.sprite, "offset", Vector2(-16, -31), 0.15).set_delay(0.15)
	await tw.finished
	water_level = 0.0
	water_cap = float(w["refill_cap"])
	pours += 1
	if OS.has_feature("web"):
		print("interior: bucket poured")
	await get_tree().create_timer(0.2, false).timeout


func set_wardrobe_open(on: bool) -> void:
	wardrobe_is_open = on
	if wardrobe_open_sprite == null:
		return
	wardrobe_open_sprite.visible = on
	rooms[opening_room()]["furniture"]["wardrobe"].visible = not on


# ================================================================== water drawing
const WA := [Color("2f5f8f"), Color("3f7fb5"), Color("62a6d6"), Color("a6d8f0")]


static func _ellipse(c: Vector2, rx: float, ry: float, n := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var q := (c + Vector2(cos(a) * rx, sin(a) * ry)).round()
		if pts.is_empty() or (q != pts[pts.size() - 1] and q != pts[0]):
			pts.append(q)
	return pts


## Draws a pixel-snapped filled ellipse (nothing when it is too small to be a polygon).
static func _fill_ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx < 1.5 or ry < 1.0:
		return
	var pts := _ellipse(c, rx, ry)
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, col)


## The water inside the bucket (child of the bucket sprite: y-sorted with it). Rises with the level; ripples on drops;
## a lip of water over the rim and streams down the front while it overflows.
class BucketWater extends Node2D:
	var o: Interiors
	var center := Vector2.ZERO      # world
	var r := 9.0

	func setup(owner_: Interiors, c: Vector2, radius: float) -> void:
		o = owner_
		center = c
		r = radius
		name = "BucketWater"

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := center - global_position
		var lv := clampf(o.water_level, 0.0, 1.0)
		if lv > 0.02:
			var k := 0.45 + 0.55 * lv                       # the surface widens as it climbs the tapered staves
			var cc := c + Vector2(0, roundf((1.0 - lv) * 3.0))
			Interiors._fill_ellipse(self, cc, r * k, r * k * 0.92, Interiors.WA[0])
			Interiors._fill_ellipse(self, cc + Vector2(-0.5, -0.5), r * k - 1.0, r * k * 0.92 - 1.0, Interiors.WA[1])
			draw_rect(Rect2((cc + Vector2(-r * k * 0.5, -r * k * 0.5)).round(), Vector2(2, 1)), Interiors.WA[3])
			if lv >= 0.98:
				draw_arc(c, r + 1.5, 0.0, TAU, 20, Interiors.WA[2], 1.0)    # brim-full: water at the rim
		if o.overflowing:
			var t := float(Time.get_ticks_msec()) / 1000.0
			for k in 4:
				var x := c.x - 6.0 + k * 4.0
				var y0 := c.y + r + 2.0
				var len_ := 4.0 + fmod(t * 20.0 + k * 3.0, 6.0)
				draw_rect(Rect2(Vector2(x, y0).round(), Vector2(1, len_)), Interiors.WA[2])
				draw_rect(Rect2(Vector2(x, y0 + len_).round(), Vector2(1, 1)), Interiors.WA[3])


## The puddle on the floor (in the floor layer: under every character / furniture). Size 0..1 scales every blob towards
## the puddle's middle - each wipe takes one ring off.
class PuddleDraw extends Node2D:
	var o: Interiors
	var blobs: Array = []
	var mid := Vector2.ZERO

	func setup(owner_: Interiors, origin_: Vector2, b: Array) -> void:
		o = owner_
		name = "Puddle"
		for x in b:
			blobs.append([origin_ + Vector2(x[0], x[1]), float(x[2]), float(x[3])])
		mid = blobs[0][0]

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var s := clampf(o.puddle_size, 0.0, 1.0)
		if s <= 0.02:
			return
		var outer := Interiors.WA[0]
		outer.a = 0.45
		var inner := Interiors.WA[1]
		inner.a = 0.5
		for b in blobs:
			var c: Vector2 = mid + (b[0] - mid) * s
			Interiors._fill_ellipse(self, c, b[1] * s, b[2] * s, outer)
		for b in blobs:
			var c: Vector2 = mid + (b[0] - mid) * s
			if b[1] * s > 3.0:
				Interiors._fill_ellipse(self, c + Vector2(0, -0.5), b[1] * s - 2.0, maxf(1.0, b[2] * s - 1.5), inner)
		for b in blobs.slice(0, 2):
			var c: Vector2 = mid + (b[0] - mid) * s
			if b[1] * s > 4.0:
				draw_rect(Rect2((c + Vector2(-b[1] * s * 0.5, -b[2] * s * 0.5)).round(), Vector2(maxf(1.0, 4.0 * s), 1)), Interiors.WA[3])


# ================================================================== 试玩反馈 v1: the rag stands out
## A bright 1-px edge around the rag's opaque pixels that pulses (PULSE s), and gold sparkles rising above it and fading.
## Drawn in code over the rag (local coordinates = the rag sprite's, top-left of its picture).
class RagGlow extends Node2D:
	const PULSE := 1.2
	const EDGE := Color(1.0, 0.95, 0.62)
	const GOLD := Color(1.0, 0.84, 0.25)
	const SPARKS := 5
	const SPARK_LIFE := 1.1
	var edge: PackedVector2Array = []     # pixels just outside the rag
	var halo: PackedVector2Array = []     # one pixel further out (a soft second ring)
	var size := Vector2.ZERO
	var t := 0.0

	func setup(tex: Texture2D, region: Rect2) -> void:
		name = "RagGlow"
		size = region.size
		var img := tex.get_image()
		if img == null:
			return
		if img.is_compressed():
			img.decompress()
		var w := int(region.size.x)
		var h := int(region.size.y)
		var solid := {}
		for y in h:
			for x in w:
				var px := Vector2i(int(region.position.x) + x, int(region.position.y) + y)
				if px.x < img.get_width() and px.y < img.get_height() and img.get_pixelv(px).a > 0.5:
					solid[Vector2i(x, y)] = true
		var ring1 := _ring(solid)
		for p in ring1:
			edge.append(Vector2(p))
		var inner := solid.duplicate()
		for p in ring1:
			inner[p] = true
		for p in _ring(inner):
			halo.append(Vector2(p))

	## Pixels next to (4-neighbours of) the set that are not in it.
	func _ring(set_: Dictionary) -> Array:
		var out := {}
		for p in set_:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if not set_.has(q):
					out[q] = true
		return out.keys()

	## 0..1 brightness of the edge now.
	func pulse() -> float:
		return 0.5 + 0.5 * sin(t * TAU / PULSE)

	## Sparkle i: [position (local), alpha].
	func spark(i: int) -> Array:
		var ph := fmod(t / SPARK_LIFE + float(i) / float(SPARKS), 1.0)
		var x := size.x * (0.1 + 0.8 * fmod(float(i) * 0.618 + floor(t / SPARK_LIFE + float(i) / float(SPARKS)) * 0.37, 1.0))
		return [Vector2(round(x), round(-1.0 - 12.0 * ph)), sin(ph * PI)]

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var k := pulse()
		var c := EDGE
		c.a = 0.45 + 0.55 * k
		for p in edge:
			draw_rect(Rect2(p, Vector2.ONE), c)
		var hc := EDGE
		hc.a = 0.12 + 0.3 * k
		for p in halo:
			draw_rect(Rect2(p, Vector2.ONE), hc)
		for i in SPARKS:
			var sp: Array = spark(i)
			var a := float(sp[1])
			var at: Vector2 = sp[0]
			var g := GOLD
			g.a = a
			draw_rect(Rect2(at, Vector2.ONE), Color(1.0, 0.98, 0.85, a))      # white-hot centre
			var g2 := g
			g2.a = a * 0.85
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_rect(Rect2(at + d, Vector2.ONE), g2)
			if a > 0.7:                  # a longer twinkle at its brightest
				var g3 := g
				g3.a = (a - 0.7) * 2.0
				for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
					draw_rect(Rect2(at + d, Vector2.ONE), g3)


# ================================================================== night light flames
## Small flickering flames for the room lights (oil lamp, candles, 长明灯; the stove's fire mouth is painted - it gets a
## flicker of its glow only). Shown in the dark hours; the 长明灯 always burns.
class InteriorFlames extends Node2D:
	var o: Interiors
	var t := 0.0

	func setup(owner_: Interiors) -> void:
		o = owner_
		name = "Flames"

	func flicker(l: PointLight2D) -> float:
		var ph := float(l.global_position.x) * 0.37
		return 1.0 + 0.07 * sin(t * 7.1 + ph) + 0.04 * sin(t * 13.3 + ph * 1.7)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for id in o.rooms:
			if id != o.current:
				continue
			for l in o.rooms[id]["lights"]:
				var kind: String = l.get_meta("kind")
				var lv := o.night_level if kind != "eternal_lamp" else 1.0
				if lv < 0.05 or kind == "moon" or kind == "stove_fire":
					continue
				var p: Vector2 = l.global_position.round()
				var f := flicker(l)
				var a := clampf(lv * 1.5, 0.0, 1.0)
				if kind == "eternal_lamp":
					draw_rect(Rect2(p + Vector2(-3, 1), Vector2(7, 2)), Color("9a8040"))
					draw_rect(Rect2(p + Vector2(-2, 3), Vector2(5, 1)), Color("4a3a22"))
				var h := 3.0 if f > 1.02 else 2.0
				draw_rect(Rect2(p + Vector2(-1, -h), Vector2(2, h + 1)), Color(1.0, 0.53, 0.3, a))
				draw_rect(Rect2(p + Vector2(0, -h - 1), Vector2(1, h)), Color(1.0, 0.82, 0.48, a))
				draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color(1.0, 0.96, 0.75, a))


# ================================================================== drips
## The leaking roof of the dorm (v4): drops fall from the two holes all the time - one into the bucket (ripples, the
## level rises), one onto 师兄's pillow (it is wet). `fast` = the opening's "一滴一滴…越来越满" (drops come quicker).
class InteriorDrips extends Node2D:
	const FALL := 0.5
	var owner_: Interiors
	var list: Array = []          # {top, land, into, period, t}
	var landed := {}              # into -> number of landings (tests)
	var splashes: Array = []      # {pos, t, ring}
	var fast := false

	func setup(o: Interiors) -> void:
		owner_ = o
		name = "Drips"
		z_index = 5
		var k := 0
		for id in o.rooms:
			for d in o.rooms[id]["def"].get("drips", []):
				var org: Vector2 = o.rooms[id]["origin"]
				list.append({"top": org + Vector2(d["x"], d["y_top"]), "land": org + Vector2(d["x"], d["y_land"]),
					"into": String(d["into"]), "period": 1.35 + 0.4 * k, "t": 0.45 * k, "room": id})
				landed[String(d["into"])] = 0
				k += 1

	## 两条路小样 v1: the roof of this room is mended - its drops stop.
	func remove_room(id: String) -> void:
		list = list.filter(func(d): return d["room"] != id)
		splashes.clear()

	func _process(delta: float) -> void:
		for d in list:
			var sp := 3.0 if fast and d["into"] == "bucket" else 1.0
			d["t"] += delta * sp
			if d["t"] >= d["period"]:
				d["t"] -= d["period"]
				landed[d["into"]] += 1
				splashes.append({"pos": d["land"], "t": 0.0, "ring": d["into"] == "bucket"})
				if d["into"] == "bucket":
					owner_._bucket_drop()
		for s in splashes:
			s["t"] += delta
		splashes = splashes.filter(func(s): return s["t"] < 0.35)
		queue_redraw()

	func _drop(p: Vector2) -> void:
		var w := 2.0
		var h := 4.0
		var q := p.round()
		draw_rect(Rect2(q + Vector2(-0.5, -h - 5.0), Vector2(1, 4.0)), Color(0.8, 0.9, 1.0, 0.45))   # trail
		draw_rect(Rect2(q + Vector2(-w * 0.5 - 1.0, -h - 1.0), Vector2(w + 2.0, h + 2.0)), Color(0.24, 0.36, 0.52, 0.9))
		draw_rect(Rect2(q + Vector2(-w * 0.5, -h), Vector2(w, h)), Color(0.66, 0.84, 1.0, 1.0))
		draw_rect(Rect2(q + Vector2(-w * 0.5, -h), Vector2(1, 1)), Color(1, 1, 1, 1))

	func _draw() -> void:
		for d in list:
			var k: float = d["t"] / FALL
			if k <= 1.0:
				_drop((d["top"] as Vector2).lerp(d["land"], k * k))
		for s in splashes:
			var k: float = s["t"] / 0.35
			var a := 1.0 - k
			var p: Vector2 = s["pos"]
			var col := Color(0.86, 0.94, 1.0, a)
			if s["ring"]:
				draw_arc(p, 2.0 + 6.0 * k, 0.0, TAU, 14, Color(0.3, 0.45, 0.6, a), 1.0)
				draw_arc(p, 1.0 + 4.0 * k, 0.0, TAU, 12, col, 1.0)
			else:
				var spread := 4.0 * (0.4 + k)
				for dx in [-1.0, 1.0]:
					draw_rect(Rect2(p + Vector2(dx * spread - 0.5, -2.0 - 4.0 * sin(k * PI)), Vector2(1, 1)), col)
					draw_rect(Rect2(p + Vector2(dx * spread * 0.5 - 0.5, -3.0 - 5.0 * sin(k * PI)), Vector2(1, 1)), col)
