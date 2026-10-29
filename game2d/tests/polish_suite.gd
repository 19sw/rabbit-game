extends RefCounted
## 打磨 v1 checks (tests/run_tests.gd runs this suite last; quick loop: -- --only-polish). Real key events and real
## physics in games built like a direct launch (story mode, the opening on screen).
##   AC1 round minimap: size / place, centred on him, star in range at its place, out of range on the rim at the right
##       angle (8 directions), indoors the room picture, outdoor target from inside -> rim towards his doorway, target in
##       a room from outside -> its door; nearly transparent over him / an NPC / a thing to press E on; hidden in a
##       conversation; no overlap with the objective line (also with a long text)
##   AC2 indoor light: day / dusk / night per room (brightness floor, warmth, daylight layer on / off, night light
##       sources per room), sampled door transitions (no one-frame jump), the daylight layer is not baked in the base
##   AC3 outdoor occlusion: behind the dorm roof, the hall roof, the compound wall (gate wing), a tree canopy and the
##       kitchen roof the covering picture fades around him (shader on, alpha at his middle low), not when he stands
##       in front; colliders unchanged; an NPC behind a roof / canopy gets the same
##   AC4 opening v4 + wiping: leaks (bucket, 师兄's pillow, none on his bed), wipe without the rag -> hint (UI text),
##       rag -> 3 wipes shrinking the puddle ring by ring -> pour (level 0) -> keeps catching (capped), star order
##       rag -> puddle -> table, leaving before wiping (objective kept, star on the dorm door)
##   AC5 wardrobe: E opens the panel (4 garment icons, 64x64) with S1-衣柜, the door opens; closes with the scene, door
##       shut; no wall clothes; broom + rag in the corner

var r
var g: Node
var it: Interiors
var story: Story
var nav
var sdata: Dictionary
var mm: Minimap

const ROOMS := ["dorm_main", "storage", "dorm_old", "hall", "kitchen"]


func _init(runner) -> void:
	r = runner


func run() -> void:
	r.paused = false
	r.release_all()
	sdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	await new_game()
	await test_opening_art_and_leaks()
	await test_wiping()
	await test_wardrobe()
	await test_minimap()
	await test_minimap_transparency()
	await test_lighting()
	await test_door_transition()
	await test_occlusion()
	await test_occlusion_sweep()
	await _free_game()


# ------------------------------------------------------------------ helpers
func _free_game() -> void:
	if g != null and is_instance_valid(g):
		if g.is_inside_tree():
			g.get_parent().remove_child(g)
		g.queue_free()
	g = null
	await r.process_frame


func new_game() -> void:
	await _free_game()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	g = m
	it = m.interiors
	story = m.story
	mm = m.hud.minimap
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0
	nav = load("res://tests/nav.gd").new(r, m)
	m.daynight.running = false
	await r.frames(3)


func p() -> Player:
	return g.player


func npc(id: String) -> Npc:
	return story._npc(id)


func inter(id: String) -> Dictionary:
	for x in sdata["interactables"]:
		if x["id"] == id:
			return x
	return {}


func thing(id: String) -> Vector2:
	return story._thing_pos(inter(id))


func finish_scene() -> void:
	var n := 0
	while story.busy and n < 400:
		if story.dialogue.choosing:
			await r.tap(KEY_1)
		elif story.dialogue.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(2)


## Plays the running scene to its end and returns every line shown.
func read_scene() -> Array:
	var lines := []
	for i in 300:
		if not story.busy:
			break
		if story.dialogue.active and not story.dialogue.is_typing():
			lines.append(story.dialogue.full_text)
			await r.tap(KEY_E)
		elif story.dialogue.active:
			await r.tap(KEY_E)
		else:
			await r.frames(1)
	await r.frames(2)
	return lines


# ================================================================== AC4 art + leaks
func test_opening_art_and_leaks() -> void:
	var d: Dictionary = it.rooms["dorm_main"]["def"]
	var o: Vector2 = it.origin("dorm_main")
	var furn: Dictionary = it.rooms["dorm_main"]["furniture"]
	var bed: Rect2 = Rect2(furn["bed"].position + furn["bed"].offset, furn["bed"].region_rect.size)
	var sbed: Rect2 = Rect2(furn["senior_bed"].position + furn["senior_bed"].offset, furn["senior_bed"].region_rect.size)
	var into := []
	var on_her_bed := false
	var on_pillow := false
	for dr in d["drips"]:
		into.append(dr["into"])
		var land := o + Vector2(dr["x"], dr["y_land"])
		if bed.grow(-2).has_point(land):
			on_her_bed = true
		if dr["into"] == "pillow" and sbed.has_point(land) and land.y < sbed.position.y + 24:
			on_pillow = true
	into.sort()
	r.check(into == ["bucket", "pillow"] and not on_her_bed and on_pillow,
		"polish AC4: the two leaks drip into the bucket and onto 师兄's pillow (head end of his bed); nothing lands on his bed", str(into))
	var types := []
	for f in d["furniture"]:
		types.append(f["type"])
	var corner := Vector2(10, 242)          # south-west floor corner (room px)
	var broom_r: Array = []
	for f in d["furniture"]:
		if f["type"] == "broom":
			broom_r = f["rect"]
	var rag_r: Array = d["variants"]["rag"]["rect"]
	var broom_c := Vector2(broom_r[0] + broom_r[2] * 0.5, broom_r[1] + broom_r[3]) if broom_r.size() == 4 else Vector2.INF
	var rag_c := Vector2(rag_r[0] + rag_r[2] * 0.5, rag_r[1] + rag_r[3])
	r.check(not "wall_clothes" in types and "wardrobe" in types and d["variants"].has("wardrobe_open") and broom_c.distance_to(corner) < 48.0
		and rag_c.distance_to(corner) < 56.0 and rag_c.distance_to(broom_c) < 40.0,
		"polish AC5: no clothes on the wall, a wardrobe instead (with an open look); broom and rag together in the south-west corner",
		"broom %s rag %s" % [broom_c, rag_c])
	# the daylight layer is its own picture (not baked): the base is darker where the layer adds light
	var lit_px := 0
	for id in ROOMS:
		var img: Image = (it.rooms[id]["daylight"].texture as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		if used.size.x > 10 and used.size.y > 10:
			lit_px += 1
	r.check(lit_px == ROOMS.size(), "polish AC2: every room has a separate daylight layer (window / door light, shafts) on top of an unlit picture")


# ================================================================== AC4 wiping
func test_wiping() -> void:
	# the opening: the bucket fills, overflows, he wakes (checked in detail by the story suite) - here: the end state
	var lv0: float = it.water_level
	await finish_scene()
	r.check(story.stage == 0 and g.hud.objective_label.text == "目标：擦干地上的水" and it.puddle_size >= 0.99 and it.water_level >= 0.99
		and lv0 < 0.7 and story.played == ["S1-醒来"], "polish AC4: after the opening: full bucket, the puddle on the floor, 目标：擦干地上的水")
	var rag := thing("rag")
	var puddle := thing("puddle")
	await r.frames(2)
	# fix round: the key hint that comes up after waking never covers the rag corner (nor him)
	var hint_bad := []
	for hk in 3:
		await r.frames(10)
		if not hint_clear():
			hint_bad.append("after waking %d: %s" % [hk, g.hud.hint.get_global_rect()])
	var star_rag: bool = mm.star_target_world.distance_to(rag) < 1.0
	# E at the puddle without the rag: the hint (UI text from data), nothing wiped
	var res: String = await nav.walk_to(puddle + Vector2(0, 6))
	await r.frames(2)
	var prompt_wipe: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 擦水渍"
	var k: int = story.played.size()
	await r.tap(KEY_E)
	await r.frames(10)
	var hint_ok: bool = story.hints_shown == ["先去墙角拿抹布"] and g.hud.toast.text == "先去墙角拿抹布" and g.hud.toast.modulate.a > 0.5 \
		and String(sdata["ui"]["need_rag"]) == "先去墙角拿抹布" and story.played.size() == k and it.puddle_size >= 0.99 and story.wipes == 0
	r.check(res == "arrived" and prompt_wipe and hint_ok and star_rag,
		"polish AC4: star on the rag first; E at the puddle without the rag -> hint '先去墙角拿抹布' (ui.need_rag in story.json), nothing wiped",
		"%s prompt %s hints %s" % [res, prompt_wipe, story.hints_shown])
	# leaving before wiping: allowed, the objective stays, the star points at the dorm door
	res = await nav.walk_to(it.exit_spot("dorm_main") + Vector2(0, 20))
	await r.frames(3)
	r.check(res == "arrived" and it.room_at(p().global_position) == "" and story.stage == 0 and g.hud.objective_label.text == "目标：擦干地上的水"
		and mm.star_target_world.distance_to(it.door_point("dorm_main")) < 1.0,
		"polish AC4: leaving before wiping is allowed - objective unchanged, the star points at the dorm door", res)
	# the rag (the hint again, the first seconds after waking are not over yet when he gets to the corner)
	g.hud.show_hint()
	res = await nav.walk_to(rag + Vector2(0, 4))
	await r.frames(2)
	for hk in 3:
		await r.frames(8)
		if not hint_clear():
			hint_bad.append("at the rag %d: %s" % [hk, g.hud.hint.get_global_rect()])
	r.check(hint_bad.is_empty() and g.hud.hint.visible,
		"polish AC4 fix: the key hint never covers the rag in the corner or the rabbit (it moves to the other bottom corner while one is in use; now: %s)" % g.hud.hint_side, str(hint_bad))
	# the switch itself, independent of the window size: a point inside the left hint area sends it right, and back
	var lr: Rect2 = g.hud.hint_rect_for("left")
	g.hud._place_hint([lr.get_center()])
	var went_right: bool = g.hud.hint_side == "right" and not g.hud.hint.get_global_rect().has_point(lr.get_center())
	g.hud._place_hint([])
	r.check(went_right and g.hud.hint_side == "left" and g.hud.hint.get_global_rect().position.x <= 7.0,
		"polish AC4 fix: the key hint moves to the bottom-right when something is in its bottom-left place, and comes back when it is free")
	var prompt_take: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 拿起"
	await r.tap(KEY_E)
	var lines := await read_scene()
	await r.frames(2)
	r.check(res == "arrived" and prompt_take and lines == ["抹布……拧一拧还能用。", "走到水渍旁边，按 E 擦干。"] and story.flags.get("has_rag", false)
		and not it.rag_sprite.visible and mm.star_target_world.distance_to(puddle) < 1.0 and g.prompt_target.get("id", "") != "rag",
		"polish AC4: E at the rag in the corner: S1-抹布, the rag leaves the floor, the star moves to the puddle", "%s %s" % [res, lines])
	# the note is not readable yet
	await r.teleport(r.find_free_near(thing("note") + Vector2(0, 8), 12))
	await r.frames(2)
	var note_closed: bool = g.prompt_target.get("id", "") != "note"
	# three wipes, the puddle one ring smaller each time
	res = await nav.walk_to(puddle + Vector2(0, 6))
	var sizes := []
	for n in 2:
		await r.tap(KEY_E)
		await r.frames(30)
		sizes.append(snappedf(it.puddle_size, 0.01))
	var busy_before: bool = story.busy
	await r.tap(KEY_E)
	await r.frames(2)
	var scene3: String = story.current_scene
	var poured_during := false
	var lines3 := []
	for i in 400:
		if not story.busy:
			break
		if it.pours == 1 and it.water_level <= 0.001:
			poured_during = true
		if story.dialogue.active and not story.dialogue.is_typing():
			lines3.append(story.dialogue.full_text)
			await r.tap(KEY_E)
		elif story.dialogue.active:
			await r.tap(KEY_E)
		else:
			await r.frames(1)
	await r.frames(3)
	# 改名与起名 v1: the data writes the hero's name as {name}; on screen it is the name (the default 小兔 here)
	var want3: Array = sdata["scenes"]["S1-擦水渍"].filter(func(e): return e.has("text")).map(func(e): return PlayerName.fill(String(e["text"])))
	r.check(res == "arrived" and note_closed and sizes == [0.66, 0.34] and not busy_before and scene3 == "S1-擦水渍" and it.puddle_size <= 0.001
		and story.flags.get("floor_wiped", false) and lines3 == want3,
		"polish AC4: with the rag, E at the puddle 3 times: it shrinks ring by ring (1 -> 0.66 -> 0.34 -> 0), the third plays S1-擦水渍 (the note stays closed until then)",
		"%s sizes %s scene %s lines %s" % [res, sizes, scene3, lines3])
	r.check(poured_during and it.pours == 1 and g.hud.objective_label.text == "目标：看看桌上的字条" and mm.star_target_world.distance_to(thing("note")) < 1.0,
		"polish AC4: S1-擦水渍 pours the bucket out (level 0), then 目标：看看桌上的字条 with the star on the table")
	# the bucket keeps catching drops - and stops below the brim (no second overflow)
	var drops0: int = it.bucket_drops
	var lvl0: float = it.water_level
	await r.frames(600)
	var cap := float(Tuning.data()["dorm_water"]["refill_cap"])
	r.check(it.bucket_drops - drops0 >= 3 and it.water_level > lvl0 + 0.04 and it.water_level <= cap + 0.001 and not it.overflowing,
		"polish AC4: after pouring the bucket goes on catching drops (level %.2f -> %.2f, never above %.2f)" % [lvl0, it.water_level, cap])
	r.check(story.wipes == 3 and story.hints_shown.size() == 1, "polish AC4: wiping counted 3, the hint shown once (only when it was pressed without the rag)")


## The key hint (when shown) covers neither the rag picture nor the rabbit nor any thing to press E on.
func hint_clear() -> bool:
	if not g.hud.hint.visible:
		return true
	var hr: Rect2 = g.hud.hint.get_global_rect()
	var ct: Transform2D = g.get_viewport().get_canvas_transform()
	if it.rag_sprite.visible:
		var rr := Rect2(it.rag_sprite.global_position, it.rag_sprite.region_rect.size)
		if hr.intersects(Rect2(ct * rr.position, rr.size * ct.get_scale())):
			return false
	var body := Occlusion.body_rect(p().global_position)
	if hr.intersects(Rect2(ct * body.position, body.size * ct.get_scale())):
		return false
	for w in story.poi_points():
		if hr.has_point(ct * (w as Vector2)):
			return false
	return true


# ================================================================== AC5 wardrobe
func test_wardrobe() -> void:
	var wp: WardrobePanel = story.wardrobe_panel
	var closed_sprite: Sprite2D = it.rooms["dorm_main"]["furniture"]["wardrobe"]
	var res: String = await nav.walk_to(thing("wardrobe") + Vector2(0, 4))
	await r.frames(2)
	var prompt_open: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 打开" and g.prompt_target.get("id", "") == "wardrobe"
	await r.tap(KEY_E)
	await r.frames(20)
	var opened: bool = wp.is_open and wp.panel.visible and it.wardrobe_is_open and it.wardrobe_open_sprite.visible and not closed_sprite.visible
	var icons_ok: bool = wp.icons.size() == 4
	for ic in wp.icons:
		icons_ok = icons_ok and ic.texture != null and ic.texture.get_width() == 64 and ic.texture.get_height() == 64 and ic.is_visible_in_tree()
	var title_ok: bool = wp.title_label.text == "衣柜"
	var panel_rect: Rect2 = wp.panel.get_global_rect()
	var obj_rect: Rect2 = g.hud.objective.get_global_rect()
	var box_top: float = story.dialogue.box.get_global_rect().position.y
	var lines := await read_scene()
	var want: Array = sdata["scenes"]["S1-衣柜"].filter(func(e): return e.has("text")).map(func(e): return e["text"])
	await r.frames(5)
	var closed: bool = not wp.is_open and not wp.panel.visible and not it.wardrobe_is_open and not it.wardrobe_open_sprite.visible and closed_sprite.visible \
		and p().input_enabled and not story.busy
	r.check(res == "arrived" and prompt_open and opened and icons_ok and title_ok and lines == want,
		"polish AC5: E at the wardrobe opens it - the panel shows the 4 garments (64x64 icons) while S1-衣柜 plays word for word",
		"%s prompt %s open %s icons %s lines %s" % [res, prompt_open, opened, icons_ok, lines])
	r.check(closed and panel_rect.size.x > 256 and panel_rect.position.y >= 0 and panel_rect.end.y < box_top and g.hud.objective.visible
		and not panel_rect.intersects(obj_rect) and not panel_rect.intersects(Rect2(g.hud.minimap.position, g.hud.minimap.size))
		and not panel_rect.intersects(g.combat.hud.hp_panel.get_global_rect()),
		"polish AC5: when the lines end the panel closes and the wardrobe door is shut again; he can walk (panel above the dialogue box, never over the objective line / minimap / HP bar)", "%s obj %s box top %.0f" % [panel_rect, obj_rect, box_top])
	# the garments: drawn in the rabbit's outfit colours (the cream top + blue-grey collar / sash)
	var img: Image = load(WardrobePanel.SHEET).get_image()
	if img.is_compressed():
		img.decompress()
	var cream := 0
	var blue := 0
	for y in range(0, 64, 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.9:
				continue
			if c.r > 0.75 and c.g > 0.7 and c.b > 0.55 and c.r > c.b:
				cream += 1
			if c.b > c.r + 0.08 and c.b > 0.4:
				blue += 1
	r.check(img.get_width() == 256 and img.get_height() == 64 and cream > 200 and blue > 40,
		"polish AC5: the 4 garment icons use the rabbit's outfit palette (cream top, blue-grey collar / sash)", "cream %d blue %d" % [cream, blue])
	# replayable (optional line): a second E opens it again
	await r.frames(10)
	await r.tap(KEY_E)
	await r.frames(10)
	var again: bool = wp.is_open
	await finish_scene()
	r.check(again and wp.opened_count == 2 and not wp.is_open, "polish AC5: the wardrobe can be opened again (optional line) and closes cleanly again")


# ================================================================== AC1 minimap geometry
func test_minimap() -> void:
	var dia := float(Tuning.data()["minimap"]["diameter"])
	r.check(mm.size == Vector2(dia, dia) and absf(dia - 56.0) <= 4.0 and mm.position.x <= 8 and mm.position.y <= 8,
		"polish AC1: round minimap, %d px across at the base resolution, top-left" % int(dia))
	story.set_stage(4)              # 从山门下山: star on 看门老伯 (outdoors)
	var dog := npc("dog").global_position
	var bad := []
	var n_rim := 0
	var n_in := 0
	for a in range(0, 360, 45):
		var dir := Vector2.RIGHT.rotated(deg_to_rad(a))
		for dist in [110.0, 520.0]:
			var st: Vector2 = r.find_free_near(dog + dir * dist, 40)
			if st == Vector2.INF or it.room_at(st) != "" or st.x < 20 or st.y < 20 or st.x > 2028 or st.y > 1900:
				continue
			await r.teleport(st)
			await r.frames(2)
			var off := (dog - p().global_position) * mm.scale_now()
			var c := Vector2(mm.radius, mm.radius)
			var lim := mm.radius - mm.star_inset
			if off.length() > lim:
				n_rim += 1
				var ang_err := absf(angle_difference(mm.star_angle(), off.angle()))
				if not mm.star_on_rim or absf((mm.star_marker - c).length() - lim) > 0.5 or ang_err > 0.02:
					bad.append("rim %d %d err %.3f marker %s" % [a, dist, ang_err, mm.star_marker])
			else:
				n_in += 1
				if mm.star_on_rim or mm.star_marker.distance_to(c + off) > 0.5:
					bad.append("in %d %d marker %s want %s" % [a, dist, mm.star_marker, c + off])
	r.check(bad.is_empty() and n_rim >= 6 and n_in >= 6,
		"polish AC1: star inside the range sits at the target's place; outside it sits on the rim pointing at the target (angle vs atan2, %d far + %d near spots)" % [n_rim, n_in], str(bad))
	# indoors: the room picture; a target in the same room at its place; an outdoor target -> rim towards his doorway
	story.set_stage(0)
	await r.teleport(it.world_point("dorm_main", Vector2(240, 180)))
	await r.frames(3)
	var tgt: Vector2 = story.star_world()
	var off2 := (tgt - p().global_position) * mm.scale_now()
	var in_room: bool = mm.room == "dorm_main" and it.room_at(tgt) == "dorm_main" and mm.star_target_world.distance_to(tgt) < 1.0 \
		and (mm.star_on_rim or mm.star_marker.distance_to(Vector2(mm.radius, mm.radius) + off2) < 0.5)
	story.set_stage(1)
	await r.frames(3)
	var door := it.doorway_point("dorm_main")
	var offd := (door - p().global_position)
	var rim_door: bool = mm.star_on_rim and mm.star_target_world.distance_to(door) < 1.0 and absf(angle_difference(mm.star_angle(), offd.angle())) < 0.02
	# from outside, a target inside a room -> that room's outdoor door
	story.set_stage(2)
	await r.teleport(r.tile_center(31, 29))
	await r.frames(3)
	var out_door: bool = mm.room == "" and mm.star_target_world.distance_to(it.door_point("hall")) < 1.0
	r.check(in_room and rim_door and out_door and off2.length() >= 0.0,
		"polish AC1: indoors the circle shows the room; outdoor target from inside -> star on the rim towards the doorway; target inside from outside -> on that building's door",
		"%s %s %s" % [in_room, rim_door, out_door])
	# objective line never overlaps the circle, even with a long text
	g.hud.set_objective("目标：一段很长很长的目标文字用来检查会不会和小地图重叠")
	await r.frames(2)
	var orect: Rect2 = g.hud.objective.get_global_rect()
	var circ: Array = g.hud.minimap_circle()
	var near := Vector2(clampf(circ[0].x, orect.position.x, orect.end.x), clampf(circ[0].y, orect.position.y, orect.end.y))
	var hp: Rect2 = g.combat.hud.hp_panel.get_global_rect()
	r.check(near.distance_to(circ[0]) > circ[1] and orect.position.x > circ[0].x + circ[1] and not orect.intersects(hp) and not orect.intersects(g.hud.clock.get_global_rect()),
		"polish AC1: the objective line sits beside the minimap - no overlap with the circle, the HP bar or the clock (long text too)", "%s %s" % [orect, circ])


# ================================================================== AC1 transparency
func _alpha_after(frames := 30) -> float:
	await r.frames(frames)
	return mm.modulate.a


func test_minimap_transparency() -> void:
	story.set_stage(2)
	var cfg: Dictionary = Tuning.data()["minimap"]
	var lo := float(cfg["covered_alpha"]) + 0.01
	# nothing under it: opaque
	await r.teleport(r.tile_center(31, 29))
	var a_open: float = await _alpha_after()
	# the player under it (map corner: the camera stops at the edge)
	await r.teleport(r.find_free_near(Vector2(36, 50), 30))
	var a_player: float = await _alpha_after()
	var sp: Vector2 = g.get_viewport().get_canvas_transform() * p().global_position
	var player_under: bool = mm.covers_local(sp - mm.position, 6.0)
	# a thing to press E on under it (the well), the player elsewhere in the view
	var well := story._thing_pos(inter("well"))
	var vs: Vector2 = g.view_rect().size
	var st: Vector2 = r.find_free_near(well - Vector2(30, 40) + vs * 0.5 + Vector2(0, 12), 30)
	await r.teleport(st)
	await r.frames(3)
	var ws: Vector2 = g.get_viewport().get_canvas_transform() * well
	var well_under: bool = mm.covers_local(ws - mm.position, 6.0)
	var a_well: float = await _alpha_after()
	# an NPC under it
	await r.teleport(r.tile_center(31, 29))
	await r.frames(3)
	var duck := npc("duck")
	var home := duck.global_position
	duck.global_position = g.view_rect().position + Vector2(34, 40)
	var a_npc: float = await _alpha_after()
	duck.global_position = home
	var a_back: float = await _alpha_after()
	# in a conversation: hidden (tuning dialogue_alpha)
	story.play("S4-水井")
	var a_talk: float = await _alpha_after(20)
	await finish_scene()
	var a_after: float = await _alpha_after()
	r.check(a_open > 0.99 and player_under and a_player <= lo and well_under and a_well <= lo and a_npc <= lo and a_back > 0.99,
		"polish AC1: the minimap turns almost transparent (%.2f) when the player / a thing to press E on / an NPC is under it, opaque again when nothing is" % float(cfg["covered_alpha"]),
		"open %.2f player %.2f(%s) well %.2f(%s) npc %.2f back %.2f" % [a_open, a_player, player_under, a_well, well_under, a_npc, a_back])
	r.check(a_talk <= float(cfg["dialogue_alpha"]) + 0.01 and a_after > 0.99, "polish AC1: while a conversation is on screen the minimap is put away, back afterwards",
		"%.2f %.2f" % [a_talk, a_after])


# ================================================================== AC2 lighting per room and hour
func _inside(room: String) -> void:
	await r.teleport(it.entry_spot(room) + Vector2(0, -24))
	await r.frames(45)


func test_lighting() -> void:
	var dn: DayNight = g.daynight
	var amb: Ambience = g.ambience
	var bad := []
	var report := []
	var want_lights := {"dorm_main": ["oil_lamp"], "hall": ["candle", "eternal_lamp"], "kitchen": ["stove_fire"], "dorm_old": ["moon"], "storage": ["moon"]}
	for room in ROOMS:
		await _inside(room)
		dn.set_hour(12.0)
		await r.frames(3)
		var day: Color = amb.modulate_node.color
		var day_shaft := it.shaft_strength
		var day_lit := it.lit_lights(room).filter(func(l): return l.get_meta("kind") != "eternal_lamp").size()
		var ds: Sprite2D = it.rooms[room]["daylight"]
		var day_layer: bool = ds.is_visible_in_tree() and ds.modulate.a > 0.99
		dn.set_hour(18.0)
		await r.frames(3)
		var dusk: Color = amb.modulate_node.color
		dn.set_hour(23.0)
		await r.frames(3)
		var night: Color = amb.modulate_node.color
		var night_shaft := it.shaft_strength
		var kinds := {}
		for l in it.lit_lights(room):
			kinds[l.get_meta("kind")] = true
		var floor_l := Interiors.night_floor(room)
		report.append("%s day %.2f dusk %.2f(r-b %.2f) night %.2f lights %s" % [room, day.get_luminance(), dusk.get_luminance(), dusk.r - dusk.b, night.get_luminance(), kinds.keys()])
		if day.get_luminance() < 0.85 or day_shaft < 0.99 or not day_layer or day_lit != 0:
			bad.append("%s day %.2f shaft %.2f lit %d" % [room, day.get_luminance(), day_shaft, day_lit])
		if dusk.r - dusk.b < 0.12 or dusk.r - dusk.b <= day.r - day.b or dusk.get_luminance() >= day.get_luminance() or dusk.get_luminance() <= night.get_luminance():
			bad.append("%s dusk %s" % [room, dusk])
		if night.get_luminance() < floor_l - 0.005 or night.get_luminance() > day.get_luminance() - 0.3 or night_shaft > 0.2:
			bad.append("%s night %.2f shaft %.2f" % [room, night.get_luminance(), night_shaft])
		for k in want_lights[room]:
			if not kinds.has(k):
				bad.append("%s no %s at night" % [room, k])
	dn.set_hour(8.0)
	for line in report:
		r._log("      " + line)
	r.check(bad.is_empty(), "polish AC2: indoors in all 5 rooms - day bright with the window / shaft layer full; dusk warmer; night darker (>= the room's floor) with the shafts off (faint moonlight) and the room's own light sources lit (油灯 / 烛台 + 长明灯 / 灶火 / 窗口月光)", str(bad))
	r.check(Interiors.night_floor("dorm_old") > Interiors.night_floor("dorm_main") and Interiors.night_floor("storage") > Interiors.night_floor("dorm_main"),
		"polish AC2: the lamp-less old dorm and storage keep a higher night floor (readable by the window light)")


# ================================================================== AC2 door transitions
func _sample_door(walk_in_room: String, going_in: bool) -> Array:
	var amb: Ambience = g.ambience
	if going_in:
		await r.teleport(it.exit_spot(walk_in_room))
		await r.frames(40)
		r.hold_dir(Vector2.UP)
	else:
		await r.teleport(it.entry_spot(walk_in_room))
		await r.frames(40)
		r.hold_dir(Vector2.DOWN)
	var lum := []
	var crossed := false
	for i in 150:
		await r.physics_frame
		await r.process_frame
		lum.append(amb.modulate_node.color.get_luminance())
		if it.transitioning:
			crossed = true
			r.release_all()
	r.release_all()
	await nav.settle()
	var max_step := 0.0
	for i in range(1, lum.size()):
		max_step = maxf(max_step, absf(lum[i] - lum[i - 1]))
	return [crossed, max_step, absf(lum[-1] - lum[0])]


func test_door_transition() -> void:
	var dn: DayNight = g.daynight
	var bad := []
	var info := []
	for h in [22.0, 18.5, 12.0]:
		dn.set_hour(h)
		for room in ["dorm_main", "hall"]:
			for going_in in [true, false]:
				var res: Array = await _sample_door(room, going_in)
				info.append("%s %s %.1fh: step %.4f total %.3f" % [room, "in" if going_in else "out", h, res[1], res[2]])
				if not res[0] or res[1] > 0.02:
					bad.append(info[-1])
				if h == 22.0 and res[2] < 0.05:
					bad.append(info[-1] + " (no change?)")
	dn.set_hour(8.0)
	for line in info:
		r._log("      " + line)
	r.check(bad.is_empty(), "polish AC2: walking in / out of a door (night, dusk, noon) the light changes smoothly - sampled every frame, no jump above 0.02 luminance", str(bad))


# ================================================================== AC3 occlusion
func _entry_for(type: String, area: String, x: int) -> int:
	var occ: Occlusion = g.occlusion
	for o in g.data["objects"]:
		if o["type"] != type or (area != "" and o["area"] != area) or (x >= 0 and int(o["x"]) != x):
			continue
		for i in occ.entries.size():
			var rect: Rect2 = occ.entries[i]["rect"]
			if rect.position == Vector2(o["x"], o["y"]):
				return i
	return -1


## The free spot behind entry `idx` where the most of a body is covered (outdoors, drawn over him).
func _behind_spot(idx: int, x_max := INF) -> Vector2:
	var occ: Occlusion = g.occlusion
	var s: Sprite2D = occ.sprite_of(idx)
	var rect: Rect2 = occ.entries[idx]["rect"]
	var best := Vector2.INF
	var best_c := 0.0
	var y := rect.position.y + 2.0
	while y < s.position.y - 1.0:
		var x := rect.position.x + 8.0
		while x < minf(rect.end.x - 8.0, x_max):
			var f := Vector2(x, y)
			if it.room_at(f) == "" and x > 16 and r.is_free(f):
				var cv := occ.coverage(idx, f)
				if cv > best_c + 0.001 or (absf(cv - best_c) <= 0.001 and best != Vector2.INF and absf(x - rect.get_center().x) < absf(best.x - rect.get_center().x)):
					best_c = cv
					best = f
			x += 4.0
		y += 2.0
	return best


func test_occlusion() -> void:
	var occ: Occlusion = g.occlusion
	story.set_stage(2)
	var n_colliders: int = g.solids.get_child_count()
	var bad_roof_entries := 0
	# 房子整栋实心 v1: the roofs (dorm, hall, kitchen) are solid and no longer fade - they are checked in building_suite.gd
	# (no occlusion entry at all, nobody can stand under them); the fade stays for the gate wings / tower and tree canopies
	var spots := {
		"compound wall (gate wing tiles)": _entry_for("gate", "", -1),
		"tree canopy": _entry_for("tree", "trees", 614),
	}
	for roof in [["building", "dorm", 160], ["building", "hall", -1], ["building", "kitchen", -1]]:
		if _entry_for(roof[0], roof[1], roof[2]) != -1:
			bad_roof_entries += 1
	var bad := []
	var done := 0
	var minimum := float(Tuning.data()["occlusion"]["min_alpha"])
	for name in spots:
		var idx: int = spots[name]
		if idx < 0:
			bad.append(name + ": no picture")
			continue
		var s: Sprite2D = occ.sprite_of(idx)
		# the compound wall: behind the west wing of the wall (not in the gate passage)
		var st := _behind_spot(idx, occ.entries[idx]["rect"].position.x + 72.0 if name.begins_with("compound") else INF)
		if st == Vector2.INF:
			bad.append(name + ": no spot behind it")
			continue
		# walk in behind it with the keys: from a little further back, walk down into it (the roof / wall / trunk
		# collider stops him there, tucked behind the picture)
		var back: Vector2 = r.find_free_near(st + Vector2(0, -14), 6)
		await r.teleport(back if back != Vector2.INF else st)
		await r.push(Vector2.DOWN, 0.35)
		await r.frames(30)
		var feet := p().global_position
		var mid := Occlusion.body_rect(feet).get_center()
		var cov := occ.coverage(idx, feet)
		var strength := occ.strength_of(s)
		var alpha := occ.alpha_at(s, mid)
		var shader_on: bool = s.material is ShaderMaterial
		var free_ok: bool = r.is_free(feet)
		# in front of it: no fade
		await r.teleport(r.find_free_near(Vector2(feet.x, s.position.y + 22.0), 40))
		await r.frames(40)
		# (another character may still be behind the same picture - e.g. 老伯 at the gate: only his own hole must be gone)
		var front := p().global_position
		var off_ok: bool = not idx in occ.covering(front) and occ.alpha_at(s, Occlusion.body_rect(front).get_center()) > 0.99 \
			and (s.material == null or occ.active[idx]["centers"].size() < 2)
		r._log("      %s: feet %s covered %.2f, fade %.2f, alpha at his middle %.2f, in front -> off %s" % [name, feet.round(), cov, strength, alpha, off_ok])
		if not (cov >= float(Tuning.data()["occlusion"]["coverage"]) and strength > 0.99 and alpha <= minimum + 0.02 and shader_on and free_ok and off_ok):
			bad.append("%s cov %.2f str %.2f alpha %.2f shader %s free %s off %s" % [name, cov, strength, alpha, shader_on, free_ok, off_ok])
		else:
			done += 1
	r.check(bad.is_empty() and done == 2 and bad_roof_entries == 0 and g.solids.get_child_count() == n_colliders,
		"polish AC3: behind the compound wall tiles (gate wing) and a tree canopy the picture fades around him (alpha %.2f at his middle) - and not when he stands in front; colliders unchanged; roofs have no fade entry (solid since 房子整栋实心 v1)" % minimum,
		str(bad))
	# an NPC behind a canopy / roof gets the same (the player far away)
	var duck := npc("duck")
	var home := duck.global_position
	var tidx: int = spots["tree canopy"]
	var tst := _behind_spot(tidx)
	await r.teleport(r.tile_center(45, 55))
	duck.global_position = tst
	await r.frames(40)
	var ts: Sprite2D = occ.sprite_of(tidx)
	var npc_ok: bool = occ.strength_of(ts) > 0.99 and occ.alpha_at(ts, Occlusion.body_rect(tst).get_center()) <= minimum + 0.02
	duck.global_position = home
	await r.frames(40)
	r.check(npc_ok and occ.strength_of(ts) == 0.0,
		"polish AC3: an NPC behind a tree canopy is seen through the same way (and it clears when they leave)")
	# the map pictures themselves are untouched (render-only): textures are the imported map objects
	var same := true
	for i in occ.entries.size():
		if not String(occ.entries[i]["sprite"].texture.resource_path).begins_with("res://assets/map/obj_"):
			same = false
	r.check(same, "polish AC3: render-only - the outdoor objects still draw the original map pictures (no image changed)")


# ================================================================== AC3 fix round: he stays >= 90 % visible everywhere
## Static sweep: every cell of the 8 px walk grid reachable from the outdoor spawn where any outdoor picture is drawn
## over him, with his real sprite pixels in 4 facings, as the fade settles (Occlusion.visible_fraction steady) - and
## live checks (real fade, after walking there) at the reviewer's spots: the woodpile, pine / bamboo edges, the
## bamboo along the top edge of the map, the eave tips of the old disciples' house.
func test_occlusion_sweep() -> void:
	var occ: Occlusion = g.occlusion
	story.set_stage(2)
	await r.teleport(Vector2(g.data["spawn"]["x"], g.data["spawn"]["y"]))
	r.grid_w = 0
	r._build_grid()
	r._bfs(p().global_position)
	var facings := ["down", "up", "left", "right"]
	var worst := 1.0
	var worst_at := ""
	var cells := 0
	var bad := []
	var types := {}
	for f in facings:
		p().sprite.play("idle_" + f)
		p().sprite.stop()
		p().sprite.frame = 0
		for i in r.reach.size():
			if r.reach[i] == -1:
				continue
			var feet: Vector2 = r._gpos(i % r.grid_w, i / r.grid_w)
			if it.room_at(feet) != "":
				continue
			var pts := occ.pixels_at(p(), feet)
			var ov := occ.over(feet, pts)
			if ov.is_empty():
				continue
			var any := false
			for idx in ov:
				if occ.covered_count(idx, pts) > 0:
					any = true
					types[String(occ.entries[idx]["type"])] = true
			if not any:
				continue
			cells += 1
			var v := occ.visible_fraction(p(), feet, true)
			if v < worst:
				worst = v
				worst_at = "%s %s" % [feet, f]
			if v < 0.9 and bad.size() < 12:
				bad.append("%s %s %.2f" % [feet, f, v])
	p().sprite.play("idle_down")
	r.check(bad.is_empty() and cells > 2000,
		"polish AC3 fix: sweep of %d reachable spots x 4 facings where an outdoor picture covers him (%s) - he is at least 90%% visible everywhere (worst %.2f at %s)" % [cells / 4, ", ".join(types.keys()), worst, worst_at],
		str(bad))
	# live, with the real fade, at the reviewer's spots
	var spots := {"woodpile (1756,876)": Vector2(1756, 876)}
	var found := {"pine edge": "tree", "bamboo edge": "bamboo", "top-edge bamboo": "bamboo", }
	for name in found:
		var want_t: String = found[name]
		var best := Vector2.INF
		var best_n := 0
		for i in r.reach.size():
			if r.reach[i] == -1:
				continue
			var feet: Vector2 = r._gpos(i % r.grid_w, i / r.grid_w)
			if name == "top-edge bamboo" and feet.y > 50:
				continue
			if name.begins_with("eave tip") and (absf(feet.y - 1072) > 8 or absf(feet.x - (164.0 if name.ends_with("west") else 344.0)) > 10):
				continue
			if name == "bamboo edge" and feet.y < 60:
				continue
			var pts := occ.pixels_at(p(), feet)
			for idx in occ.over(feet, pts):
				if String(occ.entries[idx]["type"]) != want_t:
					continue
				var n := occ.covered_count(idx, pts)
				# an edge: only a part of him covered (the hard case for a threshold)
				if n > 0 and n < pts.size() * 0.45 and n > best_n:
					best_n = n
					best = feet
		if best == Vector2.INF and name.begins_with("eave tip"):
			# the strip north of the old disciples' house is narrow: look at every pixel row there
			var tx := 164.0 if name.ends_with("west") else 344.0
			for yy in range(1064, 1082):
				for xx in range(int(tx) - 12, int(tx) + 13, 2):
					var feet := Vector2(xx, yy)
					if not r.is_free(feet):
						continue
					var pts := occ.pixels_at(p(), feet)
					for idx in occ.over(feet, pts):
						var n := occ.covered_count(idx, pts)
						if String(occ.entries[idx]["type"]) == want_t and n > best_n and n < pts.size() * 0.45:
							best_n = n
							best = feet
		if best != Vector2.INF:
			spots[name] = best
	var lbad := []
	var report := []
	for name in spots:
		var st: Vector2 = r.find_free_near(spots[name], 12)
		if st == Vector2.INF:
			lbad.append(name + ": no free ground")
			continue
		# arrive there walking (keys): from 12 px to the side, walk sideways onto the edge spot; else stand on it
		var side: Vector2 = st + Vector2(-12, 0)
		if r.is_free(side) and r.is_free(st + Vector2(-6, 0)):
			await r.teleport(side)
			r.hold_dir(Vector2.RIGHT)
			for k in 30:
				await r.physics_frame
				if p().global_position.x >= st.x:
					break
			r.release_all()
		else:
			await r.teleport(st)
		await r.frames(20)
		var feet := p().global_position
		var v := occ.visible_fraction(p(), feet, false)
		report.append("%s %s %.2f" % [name, feet.round(), v])
		if v < 0.9:
			lbad.append(report[-1])
	for line in report:
		r._log("      " + line)
	r.check(lbad.is_empty() and spots.size() >= 4,
		"polish AC3 fix: arriving (walking sideways onto the spot) at the woodpile, a pine edge, a bamboo edge and the top-edge bamboo (the old dorm eave tips are solid now, 房子整栋实心 v1) - he is at least 90% visible with the real fade (his sprite pixels)", str(lbad) + " spots " + str(spots.keys()))

