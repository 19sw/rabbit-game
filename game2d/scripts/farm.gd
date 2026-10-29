class_name Farm
extends Node
## 武学与经营 · 第一批 · 经营 (docs/design/武学与经营-第一批-方案-v1.md 第二节). Data: data/farm.json, data/gather.json,
## economy.json more_repairs.farm (开菜园 40 文 家业 +1). Art: assets/farm/ (pixel2d/farm/tools/generate_farm_art.py).
##   菜园      the west strip of the kitchen field (6 plots of 32x32). Before 开菜园 a weed layer covers it (and it stays
##             solid like the whole field); after it the tilled layer, and the field's collider shrinks to the east part
##             (师兄's radishes) so the rabbit can walk between the plots. 开菜园 is a repair asked from 厨娘 (story flag
##             repair_farm -> the 门派簿 entry "开了菜园", 家业 +1 through Economy.points_for).
##   种 / 浇 / 收  E on an empty plot: pick a seed you have; E at the well: a full bucket (bucket_uses = 6 waterings);
##             E on a planted plot not watered since the last 08:00: water it (dark soil); E on a ripe crop: into the 库房.
##   每天      events are settled in time order by the clock (DayNight.total_hours) from the last settled moment to now,
##             whatever size the jumps are (T, 等到天亮, 打坐, a long frame): 00:00 the 萝卜彩蛋 night, 08:00 growth (a
##             watered plot grows one day, an unwatered one neither grows nor dies; the wet marks clear) and the egg's
##             10 文, 09:00 师弟 waters every planted plot that is not watered yet (when his job of that work day is 种地).
##             Gathering spots grow back at 08:00 (picked day < DayNight.day_index(8)); the 药膳 bonus lasts until the next
##             08:00 after eating (total_hours < meal_until). So every way of skipping time ends in the same state.
##   采集      4 bamboo shoots in the grove, 4 herbs by the road, glowing (Commission.Glow with our pictures); E: +1 into the
##             库房. They are separate from the 挖竹笋 委托 (its own spots, its own count).
##   厨娘      her two existing talks get our menu (data/sample.json untouched): 修厨房 gets a 3rd option 菜园和买卖 after 是 / 否;
##             修好之后 ends with the menu. Menu: 开菜园 (before) / 买种子 (after), 卖东西, 做药膳, 没事了.
##   库房      a 门派簿 page (SectBook.add_page "store"): counts; ↑↓ select, E on 药膳 eats it (not in a fight).
##   药膳      2 草药 + 1 青菜 -> 1 药膳 (free). Eaten: main.skills.set_max_hp_bonus("yaoshan", 15) until the next 08:00.
##   萝卜彩蛋  once: the first radish that ripens - that night (steal_hour 00:00) 师兄 eats it (from the plot, else from the
##             库房), a note lies on its plot ("欠你一根萝卜——师兄", E reads it); the next 08:00 he gives 10 文.
##   saving    capture() under "farm" (an optional section: a save without it = nothing opened, an empty 库房).
##   扩建      菜园扩建 v1 (docs/design/菜园扩建-方案-v1.md): the whole fenced field is farmable - 12 plots (plots 0-5 west,
##             opened by 开菜园; 6-11 east, farm.json expand.plots, opened by the repair 扩建菜园 = flag repair_farm_expand,
##             40 文 家业 +1, from 厨娘 once the farm is open). The weed / tilled layers are one 224x160 picture each, cut
##             by region: weeds all over before 开菜园, tilled west + weeds east until 扩建, tilled all over after - the
##             map's striped rows never show. Collider: whole field / open_collider (east) / none. Save key "expanded".

signal opened_now
signal changed

const DATA := "res://data/farm.json"
const GATHER := "res://data/gather.json"
const ART := "res://assets/farm/"
const CROPS := ["greens", "radish", "pumpkin"]
const STORE_KEYS := ["greens", "radish", "pumpkin", "shoots", "herbs", "meal"]
const EPS := 0.000001

var main: Node
var story: Story
var sample: Sample
var s3: Step3
var data: Dictionary
var gdata: Dictionary

# ---- state (saved)
var opened := false
var expanded := false            # 菜园扩建 v1: the east 6 plots (only once opened)
var plots: Array = []            # [{crop: "" | greens | radish | pumpkin, days: int, wet: bool, note: bool}]
var bucket := 0                  # waterings left in the bucket
var seeds := {"greens": 0, "radish": 0, "pumpkin": 0}
var store := {"greens": 0, "radish": 0, "pumpkin": 0, "shoots": 0, "herbs": 0, "meal": 0}
var picked := {}                 # spot id -> DayNight.day_index(respawn_hour) of the day it was picked
var meal_until := -1.0           # total_hours at which the 药膳 bonus ends (-1 = none eaten)
var egg := "none"                # none | ripe | eaten | done
var egg_plot := -1
var mark := -1.0                 # total_hours up to which the daily events are settled (-1 = from the next frame)
var hint_shown := false          # the 师弟 种地 hint (once)
var stats := {"planted": 0, "watered": 0, "harvested": 0, "gathered": 0, "cooked": 0, "eaten": 0, "disciple_waters": 0,
	"sold": 0, "bought": 0}

# ---- runtime
var applied_bonus := 0
var toasts: Array[String] = []   # every toast (tests)
var events: Array = []           # every settled event {at, what} (tests)
var weeds_sprite: Sprite2D
var tilled_sprite: Sprite2D
var wet_sprites: Array[Sprite2D] = []
var crop_sprites: Array[Sprite2D] = []
var note_sprites: Array[Sprite2D] = []
var sparkle_sprites: Array[Sprite2D] = []
var glows: Dictionary = {}       # spot id -> Commission.Glow
var bucket_sprite: Sprite2D
var field_shape: CollisionShape2D
var field_shape_orig: Dictionary = {}
var store_sel := 0
var _t := 0.0

static var _data: Dictionary = {}
static var _gdata: Dictionary = {}


func _init() -> void:
	name = "Farm"
	process_priority = -1     # before Sample: a farm change at 08:00 goes into the same save write as the stall income


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Farm: cannot read " + DATA)
			parsed = {}
		_data = parsed
	return _data


static func load_gather() -> Dictionary:
	if _gdata.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(GATHER))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Farm: cannot read " + GATHER)
			parsed = {}
		_gdata = parsed
	return _gdata


func ui(key: String, vals: Dictionary = {}) -> String:
	var t := String(data.get("ui", {}).get(key, key))
	return t.format(vals) if not vals.is_empty() else t


func cook_line(key: String, vals: Dictionary = {}) -> String:
	var t := String(data.get("cook", {}).get(key, key))
	return t.format(vals) if not vals.is_empty() else t


static func crop(id: String) -> Dictionary:
	return load_data().get("crops", {}).get(id, {})


static func crop_name(id: String) -> String:
	if crop(id).has("name"):
		return String(crop(id)["name"])
	if load_gather().get("items", {}).has(id):
		return String(load_gather()["items"][id]["name"])
	return String(load_data().get("ui", {}).get("name_" + id, id))


static func days_needed(id: String) -> int:
	return maxi(1, int(crop(id).get("days", 1)))


static func sell_price(id: String) -> int:
	if crop(id).has("sell"):
		return int(crop(id)["sell"])
	return int(load_gather().get("items", {}).get(id, {}).get("sell", 0))


static func seed_price(id: String) -> int:
	return int(crop(id).get("seed_price", 0))


func uses() -> int:
	return int(data.get("bucket_uses", 6))


func grow_hour() -> float:
	return float(data.get("grow_hour", 8))


func water_hour() -> float:
	return float(data.get("disciple_water_hour", 9))


func steal_hour() -> float:
	return float(data.get("radish_egg", {}).get("steal_hour", 0))


func respawn_hour() -> float:
	return float(gdata.get("respawn_hour", 8))


func meal_bonus() -> int:
	return int(data.get("meal", {}).get("hp_bonus", 15))


# ------------------------------------------------------------------ setup
## Called by Story.setup (after the other modules' merges): our scenes, 厨娘's menu, 师弟's 种地 job.
func merge_story_data(sd: Dictionary) -> void:
	data = load_data()
	gdata = load_gather()
	var scenes: Dictionary = sd.get("scenes", {})
	var cook_op := {"do": "fm", "op": "cook"}
	# 修厨房: 是 / 否 / 菜园和买卖 (the first two unchanged)
	for e in scenes.get("X-厨娘-修厨房", []):
		if e is Dictionary and e.has("choice"):
			(e["choice"] as Array).append({"text": ui("opt_farm_menu"), "then": [cook_op.duplicate()]})
			break
	# 修好之后: the lines, then the menu
	if scenes.has("X-厨娘-修好之后"):
		(scenes["X-厨娘-修好之后"] as Array).append(cook_op.duplicate())
	# 师弟: 派活 gets 种地 before 算了, shown only once the farm is open (show_if fm_farm_open) - patched in step3's
	# template too, which Step3 fills again whenever the scene starts
	var host: Node = main if main != null else get_parent()     # (we are a child of main before Story.setup runs)
	var s3 = host.get("step3") if host != null else null
	var holders: Array = [scenes]
	if s3 != null and s3.data.get("scenes") is Dictionary:
		holders.append(s3.data["scenes"])
	for holder in holders:
		for e in holder.get("D-师弟", []):
			if not (e is Dictionary and e.has("choice")):
				continue
			for o in e["choice"]:
				if String(o.get("text", "")) != "派活":
					continue
				for sub in o.get("then", []):
					if sub is Dictionary and sub.has("choice"):
						var ch: Array = sub["choice"]
						if not ch.any(func(x): return String(x.get("show_if", "")) == "fm_farm_open"):
							ch.insert(maxi(0, ch.size() - 1), {"text": ui("job_farm"), "show_if": "fm_farm_open",
								"then": [{"do": "disciple_job", "job": "farm"}]})
	scenes["D-师弟-派活-farm"] = [{"who": "squirrel", "text": ui("farm_assigned")}]


func setup(m: Node) -> void:
	main = m
	story = m.story
	sample = m.sample
	s3 = m.step3
	data = load_data()
	gdata = load_gather()
	plots = []
	for i in plot_positions().size():
		plots.append({"crop": "", "days": 0, "wet": false, "note": false})
	_build_field()
	_build_glows()
	_build_bucket()
	# 门派簿: the 家业 entry "开了菜园" (flag repair_farm; 家业 points from economy.json more_repairs.farm) and the 库房 page
	for tr in story.sect_book.data.get("tracks", []):
		if String(tr["id"]) == "estate":
			tr["entries"].append({"text": ui("book_entry"), "flag": "repair_farm"})
			tr["entries"].append({"text": ui("book_entry_expand"), "flag": "repair_farm_expand"})   # 菜园扩建 v1
	if story.sect_book.has_method("add_page"):
		story.sect_book.add_page("store", ui("store_title"), self)
	_refresh_visuals()


func active() -> bool:
	return sample != null and sample.unlocked and not story.sandbox and story.stage >= 9


# ------------------------------------------------------------------ building the pieces
func _tex(file: String) -> Texture2D:
	return load(ART + file) if ResourceLoader.exists(ART + file) else null


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func field_pos() -> Vector2:
	return _v(data["field"]["pos"])


## All plots' top-left corners: the west 6 (plots), then the east 6 (expand.plots).
static func plot_positions() -> Array:
	var d := load_data()
	return d.get("plots", []) + d.get("expand", {}).get("plots", [])


func west_count() -> int:
	return data.get("plots", []).size()


## A plot the rabbit can use now: west ones once opened, east ones once expanded too.
func plot_open(i: int) -> bool:
	return opened and i >= 0 and i < plots.size() and (i < west_count() or expanded)


func field_rect() -> Rect2:
	return Rect2(field_pos(), _v(data["field"]["size"]))


func west_w() -> float:
	return float(data["field"].get("west_w", 96))


func plot_rect(i: int) -> Rect2:
	return Rect2(_v(plot_positions()[i]), Vector2(32, 32))


func plot_center(i: int) -> Vector2:
	return plot_rect(i).get_center()


func _build_field() -> void:
	var g: Node2D = main.ground
	weeds_sprite = Sprite2D.new()
	weeds_sprite.name = "FarmWeeds"
	weeds_sprite.texture = _tex("farm_weeds.png")
	weeds_sprite.centered = false
	weeds_sprite.region_enabled = true      # (菜园扩建 v1: one picture of the whole field, cut by region - no seam)
	weeds_sprite.position = field_pos()
	g.add_child(weeds_sprite)
	tilled_sprite = Sprite2D.new()
	tilled_sprite.name = "FarmTilled"
	tilled_sprite.texture = _tex("farm_tilled.png")
	tilled_sprite.centered = false
	tilled_sprite.region_enabled = true
	tilled_sprite.position = field_pos()
	tilled_sprite.visible = false
	g.add_child(tilled_sprite)
	var wet := _tex("plot_wet.png")
	var crops_tex := _tex("crops.png")
	var note_tex := _tex("note.png")
	var spark := _tex("ripe_sparkle.png")
	for i in plots.size():
		var r := plot_rect(i)
		var w := Sprite2D.new()
		w.texture = wet
		w.centered = false
		w.position = r.position
		w.visible = false
		g.add_child(w)
		wet_sprites.append(w)
		var c := Sprite2D.new()
		c.texture = crops_tex
		c.centered = false
		c.region_enabled = true
		c.region_rect = Rect2(0, 0, 32, 32)
		c.position = Vector2(r.position.x, r.position.y + 26)     # y-sorted by the plant's foot
		c.offset = Vector2(0, -26)
		c.visible = false
		c.set_meta("type", "farm_crop")
		main.world.add_child(c)
		crop_sprites.append(c)
		var n := Sprite2D.new()
		n.texture = note_tex
		n.centered = false
		n.position = Vector2(r.position.x + 8, r.position.y + 24)
		n.offset = Vector2(0, -14)
		n.visible = false
		main.world.add_child(n)
		note_sprites.append(n)
		var s := Sprite2D.new()
		s.texture = spark
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, 16, 16)
		s.position = Vector2(r.position.x + 18, r.position.y + 27)
		s.offset = Vector2(0, -30)
		s.visible = false
		main.world.add_child(s)
		sparkle_sprites.append(s)
	# the field's collider (the whole kitchen field is one "tile" box in map_data.json)
	var fr: Array = data["field"]["collider"]
	var centre := Vector2(float(fr[0]) + float(fr[2]) * 0.5, float(fr[1]) + float(fr[3]) * 0.5)
	for cs in main.solids.get_children():
		if cs is CollisionShape2D and cs.position.distance_to(centre) < 1.0 and cs.shape is RectangleShape2D \
				and (cs.shape as RectangleShape2D).size.is_equal_approx(Vector2(float(fr[2]), float(fr[3]))):
			field_shape = cs
			field_shape_orig = {"pos": cs.position, "size": (cs.shape as RectangleShape2D).size}
			break


func _build_glows() -> void:
	var tex := {"shoots": _tex("gather_shoots.png"), "herbs": _tex("gather_herbs.png")}
	for sp in gdata.get("spots", []):
		var g := Commission.Glow.new()
		g.tex = tex.get(String(sp["kind"]), null)
		g.tint = Color(0.75, 1.0, 0.5) if String(sp["kind"]) == "shoots" else Color(0.85, 0.7, 1.0)
		g.position = _v(sp["pos"])
		g.name = "Gather_" + String(sp["id"])
		g.set_meta("type", "gather_spot")
		g.visible = false
		main.world.add_child(g)
		glows[String(sp["id"])] = g


func _build_bucket() -> void:
	bucket_sprite = Sprite2D.new()
	bucket_sprite.name = "FarmBucket"
	bucket_sprite.texture = _tex("bucket.png")
	bucket_sprite.region_enabled = true
	bucket_sprite.region_rect = Rect2(0, 0, 16, 16)
	bucket_sprite.position = Vector2(10, -9)
	bucket_sprite.visible = false
	main.player.add_child(bucket_sprite)


func _apply_collider() -> void:
	if field_shape == null:
		return
	field_shape.set_deferred("disabled", expanded and opened)     # 菜园扩建 v1: nothing blocks once expanded
	var sh := RectangleShape2D.new()
	if opened:
		var r: Array = data["field"]["open_collider"]
		sh.size = Vector2(float(r[2]), float(r[3]))
		field_shape.shape = sh
		field_shape.position = Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
	else:
		sh.size = field_shape_orig["size"]
		field_shape.shape = sh
		field_shape.position = field_shape_orig["pos"]


## Crop picture stage: 0 seed, 1 sprout, 2 young, 3 ripe.
static func stage_of(id: String, days: int) -> int:
	var need := days_needed(id)
	if days >= need:
		return 3
	if days <= 0:
		return 0
	return 1 if days * 2 < need else 2


func ripe(i: int) -> bool:
	var p: Dictionary = plots[i]
	return String(p["crop"]) != "" and int(p["days"]) >= days_needed(String(p["crop"]))


func _refresh_visuals() -> void:
	_apply_layers()
	for i in plots.size():
		var p: Dictionary = plots[i]
		var has := plot_open(i) and String(p["crop"]) != ""
		wet_sprites[i].visible = plot_open(i) and bool(p["wet"])
		crop_sprites[i].visible = has
		if has:
			var row := CROPS.find(String(p["crop"]))
			crop_sprites[i].region_rect = Rect2(stage_of(String(p["crop"]), int(p["days"])) * 32, row * 32, 32, 32)
		note_sprites[i].visible = plot_open(i) and bool(p["note"])
		sparkle_sprites[i].visible = has and ripe(i)
	var on := active()
	for sp in gdata.get("spots", []):
		glows[String(sp["id"])].visible = on and spot_ready(String(sp["id"]))
	bucket_sprite.visible = on and opened and bucket > 0
	bucket_sprite.region_rect = Rect2(0, 0, 16, 16)
	_apply_collider()
	changed.emit()


## 菜园扩建 v1: the weed / tilled layers by region. Every state covers the whole field (the map's striped rows never show):
## not opened = weeds [0, w); opened = tilled [0, west_w) + weeds [west_w, w); expanded = tilled [0, w). A region at x
## is drawn at field.pos + x, so the same picture pixel always lands on the same world pixel.
func _apply_layers() -> void:
	var size := _v(data["field"]["size"])
	var cut := 0.0 if not opened else (size.x if expanded else west_w())
	tilled_sprite.visible = cut > 0.0
	tilled_sprite.region_rect = Rect2(0, 0, maxf(cut, 1.0), size.y)
	weeds_sprite.visible = cut < size.x
	weeds_sprite.region_rect = Rect2(cut, 0, maxf(size.x - cut, 1.0), size.y)
	weeds_sprite.position = field_pos() + Vector2(cut, 0)
	tilled_sprite.position = field_pos()
	_apply_minimap()


## R1 F1: the minimap shows the same state (weeds / tilled west + weeds east / all tilled) - the thumbnail of the map
## would show the original striped rows. The layer pictures are box-averaged down to the thumbnail's scale.
var _layer_imgs := {}
func minimap_overlays() -> Array:
	var out := []
	for sp in [tilled_sprite, weeds_sprite]:
		if sp == null or not sp.visible or sp.texture == null:
			continue
		if not _layer_imgs.has(sp.name):
			var im: Image = sp.texture.get_image()
			if im == null:
				continue
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			_layer_imgs[sp.name] = im
		var r := Rect2i(sp.region_rect)
		out.append({"rect": Rect2(sp.position, Vector2(r.size)), "img": (_layer_imgs[sp.name] as Image).get_region(r)})
	return out


var _minimap_key := ""
func _apply_minimap() -> void:
	var hud = main.get("hud") if main != null else null
	if hud == null or hud.get("minimap") == null or not hud.minimap.has_method("set_overlays"):
		return
	var key := "%s|%s|%s" % [tilled_sprite.region_rect if tilled_sprite.visible else null,
		weeds_sprite.region_rect if weeds_sprite.visible else null, hud.minimap.get("map_tex") != null]
	if key == _minimap_key:
		return                   # (only when the field changes state: open / expand / load)
	_minimap_key = key
	hud.minimap.set_overlays(minimap_overlays())


## The rectangles 师弟 walks about in when his job is 种地 (farm.json disciple; the east paths once expanded).
func walk_rects() -> Array:
	var dd: Dictionary = data.get("disciple", {})
	return dd.get("walk_rects_expanded", dd.get("walk_rects", [])) if expanded else dd.get("walk_rects", [])


## Can 师弟 walk straight from a to b? Inside the field what blocks is the field's collider as it is now (the nav grid
## was built from the map, where the whole field is solid); outside it the nav grid as before.
func walk_clear(a: Vector2, b: Vector2) -> bool:
	var nav: NavGrid = main.combat.nav
	var fr := field_rect().grow(8.0)
	var solid := Rect2()
	if not opened:
		solid = field_rect()
	elif not expanded:
		var r: Array = data["field"]["open_collider"]
		solid = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	solid = solid.grow_individual(7.0, 1.0, 7.0, 6.0) if solid.has_area() else solid     # (his foot box)
	var d := b - a
	var n := maxi(1, int(ceil(d.length() / 4.0)))
	for i in range(1, n + 1):
		var q := a + d * (float(i) / n)
		if fr.has_point(q):
			if solid.has_area() and solid.has_point(q):
				return false
		elif nav != null and not nav.is_free_cell(nav.cell_of(q)):
			return false
	return true


# ------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if main == null:
		return
	_t += delta
	settle()
	_apply_meal()
	var on := active()
	for sp in gdata.get("spots", []):
		var g: Node2D = glows[String(sp["id"])]
		var want := on and spot_ready(String(sp["id"]))
		if g.visible != want:
			g.visible = want
	var f := int(_t * 6.0) % 4
	for s in sparkle_sprites:
		if s.visible:
			s.region_rect = Rect2(f * 16, 0, 16, 16)
	var bw := on and opened and bucket > 0
	if bucket_sprite.visible != bw:
		bucket_sprite.visible = bw
	if bw:
		bucket_sprite.position.x = -10.0 if main.player.facing == "left" else 10.0
		bucket_sprite.z_index = -1 if main.player.facing == "up" else 0


## Settles every daily event between the last settled moment and now, in time order.
func settle() -> void:
	var now: float = main.daynight.total_hours
	if mark < 0.0:
		mark = now
		return
	if now <= mark + EPS:
		return
	var offs := [steal_hour(), grow_hour(), water_hour()]
	var kinds := ["steal", "grow", "water"]
	var k0 := int(floor(mark / 24.0))
	var k1 := int(floor(now / 24.0))
	var before := str(capture_state())
	for k in range(k0, k1 + 1):
		var evs := []
		for j in offs.size():
			var t: float = 24.0 * k + float(offs[j])
			if t > mark + EPS and t <= now + EPS:
				evs.append([t, kinds[j]])
		evs.sort_custom(func(a, b): return a[0] < b[0])
		for ev in evs:
			_event(String(ev[1]), float(ev[0]))
	mark = now
	if str(capture_state()) != before:      # (only a real change asks for a save)
		_refresh_visuals()
		sample.request_save("farm")


func _event(what: String, at: float) -> void:
	if not active():
		return
	events.append({"at": at, "what": what})
	match what:
		"steal":
			_egg_night()
		"grow":
			if egg == "eaten":
				egg = "done"
				var c := int(data.get("radish_egg", {}).get("coins", 10))
				sample.add_coins(c)
				toast(ui("egg_coins", {"coins": c}))
			for i in plots.size():
				var p: Dictionary = plots[i]
				if String(p["crop"]) != "" and bool(p["wet"]) and not ripe(i):
					p["days"] = int(p["days"]) + 1
					if ripe(i) and String(p["crop"]) == "radish" and egg == "none":
						egg = "ripe"
						egg_plot = i
				p["wet"] = false
		"water":
			var dc: Disciple = s3.disciple
			var wd := int(floor((at - float(Economy.disciple_int("upkeep_hour"))) / 24.0))
			if opened and dc.state == "joined" and dc.job_on(wd) == "farm":
				for i in plots.size():
					var p2: Dictionary = plots[i]
					if plot_open(i) and String(p2["crop"]) != "" and not bool(p2["wet"]) and not ripe(i):
						p2["wet"] = true
						stats["disciple_waters"] = int(stats["disciple_waters"]) + 1


## The 萝卜彩蛋 night: 师兄 eats the first ripe radish (in its plot, else one from the 库房) and leaves a note.
func _egg_night() -> void:
	if egg != "ripe":
		return
	var i := egg_plot
	if i >= 0 and i < plots.size() and String(plots[i]["crop"]) == "radish" and ripe(i):
		plots[i]["crop"] = ""
		plots[i]["days"] = 0
		plots[i]["wet"] = false
	elif int(store["radish"]) > 0:
		store["radish"] = int(store["radish"]) - 1
	else:
		egg = "none"          # sold already: the next radish that ripens is the one
		egg_plot = -1
		return
	if i >= 0 and i < plots.size():
		plots[i]["note"] = true
	egg = "eaten"


# ------------------------------------------------------------------ 药膳
func meal_active() -> bool:
	return meal_until > main.daynight.total_hours + EPS


func _apply_meal() -> void:
	var want := meal_bonus() if meal_active() else 0
	if want == applied_bonus:
		return
	var was := applied_bonus
	applied_bonus = want
	var sk = main.get("skills")
	if sk != null and sk.has_method("set_max_hp_bonus"):
		sk.set_max_hp_bonus("yaoshan", want)
	if was > 0 and want == 0 and active():
		toast(ui("meal_gone"))


## The next grow_hour (08:00) strictly after now.
func next_grow_time() -> float:
	var now: float = main.daynight.total_hours
	var k: float = floor((now - grow_hour()) / 24.0) + 1.0
	return 24.0 * k + grow_hour()


## Eat one 药膳 from the 库房. Returns the message shown ("" when eaten).
func eat_meal() -> String:
	var c: Combat = main.combat
	if c.in_combat() or c.blocks_interaction():
		toast(ui("meal_fight"))
		return ui("meal_fight")
	if int(store["meal"]) <= 0:
		toast(ui("meal_none"))
		return ui("meal_none")
	if meal_active():
		toast(ui("meal_active"))
		return ui("meal_active")
	store["meal"] = int(store["meal"]) - 1
	stats["eaten"] = int(stats["eaten"]) + 1
	meal_until = next_grow_time()
	_apply_meal()
	toast(ui("meal_eaten", {"hp": meal_bonus()}))
	sample.request_save("farm")
	return ""


# ------------------------------------------------------------------ gathering
func spot_ready(id: String) -> bool:
	return int(picked.get(id, -1000000)) < main.daynight.day_index(respawn_hour())


func spot(id: String) -> Dictionary:
	for sp in gdata.get("spots", []):
		if String(sp["id"]) == id:
			return sp
	return {}


func gather(id: String) -> void:
	if not spot_ready(id):
		return
	var kind := String(spot(id)["kind"])
	picked[id] = main.daynight.day_index(respawn_hour())
	store[kind] = int(store[kind]) + 1
	stats["gathered"] = int(stats["gathered"]) + 1
	toast(ui("gathered_" + kind))
	_burst(glows[id].position + Vector2(0, -6), Color(0.75, 1.0, 0.5) if kind == "shoots" else Color(0.85, 0.75, 1.0), 8)
	glows[id].visible = false
	sample.request_save("farm")


# ------------------------------------------------------------------ E targets (Story.interaction_target asks)
## Our E target closer than `best_d` ({} = none). The well replaces 小兔's line about it (S4-水井) once the farm is open.
func interaction_target(p: Vector2, best_d: float, best: Dictionary) -> Dictionary:
	if not active():
		return {}
	var out := {}
	if opened:
		var w: Dictionary = data["well"]
		var wp := _v(w["pos"])
		var d := wp.distance_to(p)
		if d <= float(w.get("radius", 34)) and (d < best_d or String(best.get("id", "")) == "well"):
			out = {"kind": "farm", "id": "well", "prompt": ui("prompt_well"), "prompt_pos": wp + Vector2(0, -30), "dist": d}
			best_d = d
		var rad := float(data.get("plot_radius", 26))
		for i in plots.size():
			if not plot_open(i):
				continue
			var c := plot_center(i)
			var dp := c.distance_to(p)
			if dp > rad or dp >= best_d:
				continue
			best_d = dp
			out = {"kind": "farm", "id": "plot", "plot": i, "prompt": plot_prompt(i), "prompt_pos": c + Vector2(0, -22), "dist": dp}
	var gr := float(gdata.get("radius", 26))
	for sp in gdata.get("spots", []):
		var id := String(sp["id"])
		if not spot_ready(id):
			continue
		var pos := _v(sp["pos"])
		var dg := pos.distance_to(p)
		if dg > gr or dg >= best_d:
			continue
		best_d = dg
		out = {"kind": "farm", "id": "gather", "spot": id, "prompt": ui("prompt_gather_" + String(sp["kind"])),
			"prompt_pos": pos + Vector2(0, -30), "dist": dg}
	return out


func plot_prompt(i: int) -> String:
	var p: Dictionary = plots[i]
	if bool(p["note"]):
		return ui("prompt_note")
	if String(p["crop"]) == "":
		return ui("prompt_plant")
	if ripe(i):
		return ui("prompt_harvest")
	if not bool(p["wet"]):
		return ui("prompt_water", {"left": bucket})
	return ui("prompt_look")


func poi_points() -> Array:
	var out := []
	if not active():
		return out
	if opened:
		for i in plots.size():
			if plot_open(i):
				out.append(plot_center(i))
	for sp in gdata.get("spots", []):
		if spot_ready(String(sp["id"])):
			out.append(_v(sp["pos"]))
	return out


func interact(t: Dictionary) -> void:
	match String(t.get("id", "")):
		"well":
			fetch_water()
		"plot":
			use_plot(int(t["plot"]))
		"gather":
			gather(String(t["spot"]))


func fetch_water() -> void:
	if bucket >= uses():
		toast(ui("bucket_already"))
		return
	bucket = uses()
	toast(ui("bucket_full", {"n": uses()}))
	_burst(_v(data["well"]["pos"]) + Vector2(0, -10), Color(0.55, 0.75, 1.0), 6)
	_refresh_visuals()
	sample.request_save("farm")


func use_plot(i: int) -> void:
	var p: Dictionary = plots[i]
	if bool(p["note"]):
		story.data["scenes"]["F-字条"] = [{"kind": "字条", "text": String(data.get("radish_egg", {}).get("note", ""))},
			{"do": "fm", "op": "note_read", "plot": i}]
		story.play("F-字条")
		return
	if String(p["crop"]) == "":
		if seeds.values().all(func(n): return int(n) <= 0):
			toast(ui("no_seeds"))
			return
		story.data["scenes"]["F-种菜"] = plant_menu(i)
		story.play("F-种菜")
		return
	if ripe(i):
		harvest(i)
		return
	if not bool(p["wet"]):
		water(i)
		return
	toast(ui("growing_wet", {"name": crop_name(String(p["crop"])), "days": days_needed(String(p["crop"])) - int(p["days"])}))


func plant(i: int, c: String) -> bool:
	if not plot_open(i) or String(plots[i]["crop"]) != "" or int(seeds.get(c, 0)) <= 0:
		return false
	seeds[c] = int(seeds[c]) - 1
	plots[i]["crop"] = c
	plots[i]["days"] = 0
	stats["planted"] = int(stats["planted"]) + 1
	toast(ui("planted", {"name": crop_name(c)}))
	_refresh_visuals()
	sample.request_save("farm")
	return true


func water(i: int) -> bool:
	if bucket <= 0:
		toast(ui("bucket_empty"))
		return false
	var p: Dictionary = plots[i]
	if not plot_open(i) or String(p["crop"]) == "" or bool(p["wet"]) or ripe(i):
		return false
	bucket -= 1
	p["wet"] = true
	stats["watered"] = int(stats["watered"]) + 1
	toast(ui("watered", {"left": bucket}))
	_splash(plot_center(i))
	_refresh_visuals()
	sample.request_save("farm")
	return true


func harvest(i: int) -> bool:
	if not ripe(i):
		return false
	var c := String(plots[i]["crop"])
	store[c] = int(store[c]) + 1
	plots[i] = {"crop": "", "days": 0, "wet": false, "note": bool(plots[i]["note"])}
	stats["harvested"] = int(stats["harvested"]) + 1
	toast(ui("harvested", {"name": crop_name(c)}))
	_burst(plot_center(i) + Vector2(0, -6), Color(0.6, 0.9, 0.4), 10)
	Sfx.play("coin")
	_refresh_visuals()
	sample.request_save("farm")
	return true


# ------------------------------------------------------------------ small particle effects (CPUParticles2D: the web build)
func _particles(pos: Vector2, col: Color, n: int, up: float, grav: float, life: float) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = up * 0.6
	p.initial_velocity_max = up
	p.gravity = Vector2(0, grav)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	p.z_index = 1
	main.world.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.4, false).timeout.connect(p.queue_free)


func _splash(pos: Vector2) -> void:
	_particles(pos + Vector2(0, -2), Color(0.6, 0.8, 1.0), 12, 55.0, 220.0, 0.55)


func _burst(pos: Vector2, col: Color, n: int) -> void:
	_particles(pos, col, n, 45.0, 120.0, 0.6)


# ------------------------------------------------------------------ menus ("do": "fm" entries)
func handles(action: String) -> bool:
	return action == "fm"


func _opt(text: String, then: Array, grey := false) -> Dictionary:
	var o := {"text": text, "then": then}
	if grey:
		o["grey_unless"] = "jh_never"      # (Jianghu.option_ok: never - a greyed option)
	return o


func _op(op: String, extra: Dictionary = {}) -> Array:
	var e := {"do": "fm", "op": op}
	e.merge(extra)
	return [e]


func _bear(text: String) -> Dictionary:
	return {"who": "bear", "text": text}


func _hint(text: String) -> Dictionary:
	return {"kind": "提示", "text": text}


func cook_menu() -> Array:
	var price := Economy.price("farm")
	var first := _opt(ui("opt_seeds"), _op("seeds")) if opened else _opt(ui("opt_open", {"price": price}), _op("open"))
	var opts := [first, _opt(ui("opt_sell"), _op("sell_menu")), _opt(ui("opt_meal"), _op("meal"))]
	if opened and not expanded:          # 菜园扩建 v1: before 没事了, so the first three keep their keys
		opts.append(_opt(ui("opt_expand", {"price": Economy.price("farm_expand")}), _op("expand")))
	opts.append(_opt(ui("opt_bye"), []))
	return [_bear(ui("cook_ask")), {"choice": opts}]


func plant_menu(i: int) -> Array:
	var opts := []
	for c in CROPS:
		opts.append(_opt(ui("opt_plant", {"name": crop_name(c), "count": int(seeds[c])}), _op("plant", {"crop": c, "plot": i}),
			int(seeds[c]) <= 0))
	opts.append(_opt(ui("opt_cancel"), []))
	return [_hint(ui("plant_ask")), {"choice": opts}]


func seeds_menu() -> Array:
	var opts := []
	for c in CROPS:
		opts.append(_opt(ui("opt_seed", {"name": crop_name(c), "price": seed_price(c)}), _op("count", {"crop": c})))
	opts.append(_opt(ui("opt_cancel"), []))
	return [_bear(ui("seeds_ask")), {"choice": opts}]


## Page `page` of the seed counts (farm.json seed_pages; 菜园扩建 v1: 1-3, 4-6, 8/10/12 for seed_max 12).
func count_menu(c: String, page: int) -> Array:
	var pages: Array = data.get("seed_pages", [[1, 2, 3], [4, 5, 6]])
	var mx := int(data.get("seed_max", 6))
	var opts := []
	page = clampi(page, 0, pages.size() - 1)
	for n in pages[page]:
		if int(n) <= mx:
			opts.append(_opt(ui("opt_count", {"n": int(n), "coins": int(n) * seed_price(c)}), _op("buy", {"crop": c, "n": int(n)})))
	if page + 1 < pages.size() and pages[page + 1].any(func(x): return int(x) <= mx):
		opts.append(_opt(ui("opt_more"), _op("count_more", {"crop": c, "page": page + 1})))
	opts.append(_opt(ui("opt_cancel"), []))
	return [_bear(ui("count_ask", {"name": crop_name(c)})), {"choice": opts}]


func sell_value(group: String) -> Array:
	var keys := ["greens", "radish", "pumpkin"] if group == "veg" else [group]
	var n := 0
	var coins := 0
	for k in keys:
		n += int(store[k])
		coins += int(store[k]) * sell_price(k)
	return [n, coins]


func sell_menu() -> Array:
	var opts := []
	for g in ["veg", "shoots", "herbs"]:
		var v := sell_value(g)
		opts.append(_opt(ui("opt_sell_" + g, {"count": v[0], "coins": v[1]}), _op("sell", {"group": g}), int(v[0]) <= 0))
	opts.append(_opt(ui("opt_cancel"), []))
	return [_bear(ui("sell_ask")), {"choice": opts}]


## Story._option_ok for our "fm_" conditions.
func option_ok(key: String) -> bool:
	match key:
		"fm_farm_open":
			return opened
	return false


func do_action(e: Dictionary, token: int) -> void:
	match String(e.get("op", "")):
		"cook":
			await story._run_entries(cook_menu(), token)
		"open":
			var price := Economy.price("farm")
			await story._run_entries([_hint(ui("open_confirm", {"price": price, "estate": int(Economy.repair("farm").get("estate", 1))})),
				{"choice": [_opt(ui("opt_yes"), _op("open_do")), _opt(ui("opt_no"), [])]}], token)
		"open_do":
			await _open_farm(token)
		"expand":
			var xp := Economy.price("farm_expand")
			await story._run_entries([_hint(ui("expand_confirm", {"price": xp, "estate": int(Economy.repair("farm_expand").get("estate", 1))})),
				{"choice": [_opt(ui("opt_yes"), _op("expand_do")), _opt(ui("opt_no"), [])]}], token)
		"expand_do":
			await _expand_farm(token)
		"seeds":
			await story._run_entries(seeds_menu(), token)
		"count":
			await story._run_entries(count_menu(String(e["crop"]), 0), token)
		"count_more":
			await story._run_entries(count_menu(String(e["crop"]), int(e.get("page", 1))), token)
		"buy":
			await _buy(String(e["crop"]), int(e["n"]), token)
		"sell_menu":
			if sell_value("veg")[0] + sell_value("shoots")[0] + sell_value("herbs")[0] <= 0:
				await story.dialogue.say(_bear(cook_line("nothing_to_sell")))
			else:
				await story._run_entries(sell_menu(), token)
		"sell":
			await _sell(String(e["group"]), token)
		"meal":
			await _cook_meal(token)
		"plant":
			plant(int(e["plot"]), String(e["crop"]))
		"note_read":
			var i := int(e["plot"])
			if i >= 0 and i < plots.size():
				plots[i]["note"] = false
				_refresh_visuals()
				sample.request_save("farm")


func _open_farm(token: int) -> void:
	if opened:
		return
	var price := Economy.price("farm")
	if sample.coins < price:
		sample.shortfalls.append(price - sample.coins)
		await story.dialogue.say(_hint(ui("not_enough", {"n": price - sample.coins})))
		return
	sample.add_coins(-price)
	toast(ui("paid", {"n": price}))
	story.dialogue.close()
	var fade: ColorRect = main.interiors.fade_rect
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_interval(0.5)
	await tw.finished
	opened = true
	story.flags["repair_farm"] = true
	_refresh_visuals()
	if OS.has_feature("web"):
		print("farm: opened")
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.45)
	await tw2.finished
	opened_now.emit()
	sample.request_save("repair")
	if token != story._run_id:
		return
	await story.dialogue.say(_bear(cook_line("opened")))


## 菜园扩建 v1: 扩建菜园 - the east 6 plots (40 文, 家业 +1 through the flag repair_farm_expand).
func _expand_farm(token: int) -> void:
	if not opened or expanded:
		return
	var price := Economy.price("farm_expand")
	if sample.coins < price:
		sample.shortfalls.append(price - sample.coins)
		await story.dialogue.say(_hint(ui("not_enough", {"n": price - sample.coins})))
		return
	sample.add_coins(-price)
	toast(ui("paid", {"n": price}))
	story.dialogue.close()
	var fade: ColorRect = main.interiors.fade_rect
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_interval(0.5)
	await tw.finished
	expanded = true
	story.flags["repair_farm_expand"] = true
	_refresh_visuals()
	if OS.has_feature("web"):
		print("farm: expanded")
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.45)
	await tw2.finished
	sample.request_save("repair")
	if token != story._run_id:
		return
	await story.dialogue.say(_bear(cook_line("expanded")))


func _buy(c: String, n: int, token: int) -> void:
	var cost := n * seed_price(c)
	if sample.coins < cost:
		sample.shortfalls.append(cost - sample.coins)
		await story.dialogue.say(_hint(ui("not_enough", {"n": cost - sample.coins})))
		return
	sample.add_coins(-cost)
	seeds[c] = int(seeds[c]) + n
	stats["bought"] = int(stats["bought"]) + n
	toast(ui("bought", {"n": n, "name": crop_name(c)}))
	Sfx.play("coin")
	sample.request_save("farm")
	if token == story._run_id:
		await story.dialogue.say(_bear(cook_line("bought")))


func _sell(g: String, token: int) -> void:
	var v := sell_value(g)
	if int(v[0]) <= 0:
		return
	var keys := ["greens", "radish", "pumpkin"] if g == "veg" else [g]
	for k in keys:
		store[k] = 0
	stats["sold"] = int(stats["sold"]) + int(v[0])
	sample.add_coins(int(v[1]))
	toast(ui("sold", {"coins": int(v[1])}))
	Sfx.play("coin")
	sample.request_save("farm")
	if token == story._run_id:
		await story.dialogue.say(_bear(cook_line("sold")))


func _cook_meal(token: int) -> void:
	var m: Dictionary = data.get("meal", {})
	var nh := int(m.get("herbs", 2))
	var ng := int(m.get("greens", 1))
	if int(store["herbs"]) < nh or int(store["greens"]) < ng:
		await story.dialogue.say(_bear(cook_line("meal_short", {"herbs": nh, "greens": ng, "have_h": int(store["herbs"]),
			"have_g": int(store["greens"])})))
		return
	store["herbs"] = int(store["herbs"]) - nh
	store["greens"] = int(store["greens"]) - ng
	store["meal"] = int(store["meal"]) + 1
	stats["cooked"] = int(stats["cooked"]) + 1
	sample.request_save("farm")
	if token == story._run_id:
		await story.dialogue.say(_bear(cook_line("meal_done")))


# ------------------------------------------------------------------ 师弟
## Disciple.accept: the one-time hint.
func on_disciple_joined() -> void:
	if hint_shown:
		return
	hint_shown = true
	toast(ui("disciple_hint"))
	sample.request_save("farm")


func toast(t: String) -> void:
	toasts.append(t)
	s3.toast(t)


# ------------------------------------------------------------------ 门派簿 库房 page (SectBook.add_page provider)
func book_page_shown() -> bool:
	return active()


func store_rows() -> Array:
	var out := []
	out.append({"key": "seeds", "text": ui("store_seeds", {"greens": int(seeds["greens"]), "radish": int(seeds["radish"]),
		"pumpkin": int(seeds["pumpkin"])})})
	for k in STORE_KEYS:
		out.append({"key": k, "text": ui("store_row", {"name": crop_name(k), "count": int(store[k])})})
	return out


func book_page_fill(book: SectBook, col: VBoxContainer) -> void:
	var rows := store_rows()
	store_sel = clampi(store_sel, 0, rows.size() - 1)
	for i in rows.size():
		var on := i == store_sel
		var meal := String(rows[i]["key"]) == "meal"
		var c := Color(0.62, 0.18, 0.08) if on else (Color(0.3, 0.14, 0.08) if meal else Color(0.22, 0.16, 0.12))
		col.add_child(book.page_label(("▶ " if on else "  ") + String(rows[i]["text"]), 10, c))
	if meal_active():
		col.add_child(book.page_label(ui("store_meal_on", {"hp": meal_bonus()}), 9, Color(0.2, 0.45, 0.2)))
	col.add_child(book.page_label(ui("store_hint"), 9, Color(0.45, 0.18, 0.08)))


func book_page_close_hint() -> String:
	return ui("store_close")


func book_page_input(book: SectBook, event: InputEvent) -> bool:
	var n := store_rows().size()
	if event.is_action_pressed("move_up"):
		store_sel = posmod(store_sel - 1, n)
		book.set_page(book.page)
		return true
	if event.is_action_pressed("move_down"):
		store_sel = posmod(store_sel + 1, n)
		book.set_page(book.page)
		return true
	if event.is_action_pressed("interact") or (event is InputEventKey and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		if String(store_rows()[store_sel]["key"]) == "meal":
			eat_meal()
			book.set_page(book.page)
		return true
	return false


# ------------------------------------------------------------------ saving (optional section "farm")
static func defaults() -> Dictionary:
	var ps := []
	for i in plot_positions().size():
		ps.append({"crop": "", "days": 0, "wet": false, "note": false})
	return {"opened": false, "expanded": false, "plots": ps, "bucket": 0, "seeds": {"greens": 0, "radish": 0, "pumpkin": 0},
		"store": {"greens": 0, "radish": 0, "pumpkin": 0, "shoots": 0, "herbs": 0, "meal": 0}, "picked": {}, "meal_until": -1.0,
		"egg": "none", "egg_plot": -1, "mark": -1.0, "hint_shown": false,
		"stats": {"planted": 0, "watered": 0, "harvested": 0, "gathered": 0, "cooked": 0, "eaten": 0, "disciple_waters": 0,
			"sold": 0, "bought": 0}}


## What the daily events can change (settle() saves only when it did change).
func capture_state() -> Array:
	return [plots, store, egg, egg_plot, stats["disciple_waters"]]


func capture() -> Dictionary:
	return {"opened": opened, "expanded": expanded, "plots": plots.duplicate(true), "bucket": bucket, "seeds": seeds.duplicate(), "store": store.duplicate(),
		"picked": picked.duplicate(), "meal_until": meal_until, "egg": egg, "egg_plot": egg_plot, "mark": mark,
		"hint_shown": hint_shown, "stats": stats.duplicate()}


func restore(d: Dictionary) -> void:
	var df := defaults()
	opened = bool(d.get("opened", false))
	# (菜园扩建 v1: an older save has no key = not expanded. R1 F2: the story flag repair_farm_expand - restored before
	# us - counts too, so the flag and the land never disagree: no 家业 without the land, no second 40 文)
	expanded = opened and (bool(d.get("expanded", false)) or bool(story.flags.get("repair_farm_expand", false)))
	plots = []
	for p in d.get("plots", df["plots"]):
		if plots.size() >= plot_positions().size():
			break
		plots.append({"crop": String(p["crop"]), "days": int(p["days"]), "wet": bool(p["wet"]), "note": bool(p["note"])})
	while plots.size() < plot_positions().size():
		plots.append({"crop": "", "days": 0, "wet": false, "note": false})
	bucket = int(d.get("bucket", 0))
	for k in seeds:
		seeds[k] = int(d.get("seeds", {}).get(k, 0))
	for k in store:
		store[k] = int(d.get("store", {}).get(k, 0))
	picked = {}
	for k in d.get("picked", {}):
		picked[String(k)] = int(d["picked"][k])
	meal_until = float(d.get("meal_until", -1.0))
	egg = String(d.get("egg", "none"))
	egg_plot = int(d.get("egg_plot", -1))
	mark = float(d.get("mark", -1.0))
	hint_shown = bool(d.get("hint_shown", false))
	for k in stats:
		stats[k] = int(d.get("stats", {}).get(k, 0))
	if opened:
		story.flags["repair_farm"] = true
	if expanded:
		story.flags["repair_farm_expand"] = true
	else:
		story.flags.erase("repair_farm_expand")     # (R1 F2: a flag left without the land - e.g. farm not opened - adds no 家业)
	_refresh_visuals()
	_apply_meal()


## "" when the farm section of a save is well formed (absent = an older save: fine).
static func validate(d: Variant) -> String:
	if d == null:
		return ""
	if typeof(d) != TYPE_DICTIONARY:
		return "bad farm"
	if not (d.get("opened") is bool) or not (d.get("hint_shown") is bool):
		return "bad farm.opened"
	if d.has("expanded") and not (d["expanded"] is bool):       # 菜园扩建 v1 (optional)
		return "bad farm.expanded"
	for k in ["bucket", "meal_until", "egg_plot", "mark"]:
		if not SaveGame._type_ok(d.get(k), "num"):
			return "bad farm." + k
	if float(d["bucket"]) < 0.0:
		return "bad farm.bucket"
	if not (String(d.get("egg", "")) in ["none", "ripe", "eaten", "done"]):
		return "bad farm.egg"
	if not (d.get("plots") is Array) or (d["plots"] as Array).size() > plot_positions().size():
		return "bad farm.plots"
	for p in d["plots"]:
		if typeof(p) != TYPE_DICTIONARY or not (String(p.get("crop", "?")) in ["", "greens", "radish", "pumpkin"]) \
				or not SaveGame._type_ok(p.get("days"), "num") or float(p["days"]) < 0.0 or not (p.get("wet") is bool) or not (p.get("note") is bool):
			return "bad farm.plot"
	for sec in ["seeds", "store", "picked", "stats"]:
		if not (d.get(sec) is Dictionary):
			return "bad farm." + sec
		for k in d[sec]:
			if not SaveGame._type_ok(d[sec][k], "num"):
				return "bad farm.%s.%s" % [sec, k]
			if sec != "picked" and float(d[sec][k]) < 0.0:
				return "bad farm.%s.%s" % [sec, k]
	return ""
