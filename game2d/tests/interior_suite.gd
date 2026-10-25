extends RefCounted
## 室内图进游戏 v1 checks (tests/run_tests.gd runs this suite after the story suite; quick loop: -- --only-interiors).
## Real key events and real physics in games built like a direct launch (story mode: the opening is on screen).
##   AC2 doors: the 5 doors in and out with the movement keys (arrival spots, facing, fade), repeated in/out without
##       ping-pong or getting stuck, doors blocked during a conversation; 藏经阁 has no door (walking into it stays
##       outside), E at its door plays S5-藏经阁封条; per room: walls hold (walk + dodge into every wall, the doorway
##       plug), every furniture box holds, and from the door every interactable of the room can be reached (grid BFS
##       + a real walk to each), camera limits stay on the room
##   AC3 opening: the leak keeps dripping (bucket drop + ripple, pillow drop once she is up), note gating
##   AC4 师父 / 厨娘 inside at their spots; prompts per stage indoors (steps 3 / 4 / 9 unchanged)
##   AC5 every optional line has exactly one source; the moved ones are gone outdoors; each plays its scene once per E
##   AC7 indoor light readable at night (tint luminance floor), lamp glow at night only indoors; no combat indoors
##       (no fighter inside, no spar invite, J hits nothing, bandits never come in); dodge never passes a wall
##   minimap: indoors the arrow sits in the building; star rules (same room / other room / outdoors)
## 打磨 v1 edits (spec changes only): the opening is v4 (bucket -> overflow; leaks into the bucket and onto 师兄's pillow,
## none on her bed; the note after wiping), 练功服 -> 衣柜, the minimap star rules of the round minimap
## (Interiors.minimap_target), the indoor light rules (darker at night with lamps; eased at the doors). Doors, walls,
## furniture, reachability, NPC gating and no-combat checks are unchanged.

var r
var g: Node
var it: Interiors
var story: Story
var nav
var sdata: Dictionary

const ROOMS := ["dorm_main", "storage", "dorm_old", "hall", "kitchen"]


func _init(runner) -> void:
	r = runner


func run() -> void:
	r.paused = false
	r.release_all()
	sdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	test_single_sources()
	await new_game()
	await test_opening_and_leak()
	await test_doors()
	await test_door_offsets()
	await test_library_locked()
	await test_room_walls_and_dash()
	await test_reachability()
	await test_npcs_and_gating()
	await test_optional_lines_once()
	await test_minimap_and_star()
	await test_light()
	await test_no_combat_indoors()
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
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0
	nav = load("res://tests/nav.gd").new(r, m)
	m.daynight.running = false
	await r.frames(3)


func p() -> Player:
	return g.player


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


func npc(id: String) -> Npc:
	return story._npc(id)


func inter(id: String) -> Dictionary:
	for x in sdata["interactables"]:
		if x["id"] == id:
			return x
	return {}


func room_things(room: String) -> Array:
	return sdata["interactables"].filter(func(x): return x.get("room", "") == room)


## Walks into the door of `room` from outside it with the movement keys; returns the frames the fade took (or -1).
func walk_in(room: String) -> int:
	await r.teleport(it.exit_spot(room))
	r.hold_dir(Vector2.UP)
	var n := 0
	for i in 180:
		await r.physics_frame
		n += 1
		if it.transitioning:
			break
	r.release_all()
	if not it.transitioning:
		return -1
	await nav.settle()
	return n


func walk_out(room: String) -> bool:
	await r.teleport(it.entry_spot(room))
	r.hold_dir(Vector2.DOWN)
	for i in 180:
		await r.physics_frame
		if it.transitioning:
			break
	r.release_all()
	if not it.transitioning:
		return false
	await nav.settle()
	return true


# ================================================================== AC5 one source per line
func test_single_sources() -> void:
	var count := {}
	for x in sdata["interactables"]:
		count[x["scene"]] = count.get(x["scene"], 0) + 1
	var dup := []
	for k in count:
		if count[k] > 1:
			dup.append(k)
	var want := ["S1-字条", "S1-木桶", "S1-衣柜", "S1-抹布", "S1-擦水渍", "S10-师兄的箱子", "S10-师兄的床", "S10-书架", "S3-祖师像", "S3-香炉", "S10-牌匾",
		"S10-漏光处", "S10-灶台", "S10-米缸", "S10-补过的碗", "S10-空床", "S10-名牌", "S10-旧练功服", "S10-杂物", "S10-破锣", "S5-藏经阁封条"]
	var missing := want.filter(func(sc): return count.get(sc, 0) != 1)
	var where := {}
	for x in sdata["interactables"]:
		where[x["scene"]] = x.get("room", "outdoors")
	var placed_ok: bool = where.get("S1-木桶") == "dorm_main" and where.get("S1-衣柜") == "dorm_main" and where.get("S3-香炉") == "hall" \
		and where.get("S5-藏经阁封条") == "outdoors" and not sdata["scenes"].has("S1-晾衣绳") and not sdata["scenes"].has("S1-练功服")
	r.check(dup.is_empty() and missing.is_empty() and placed_ok,
		"interior AC5: every optional line has exactly one place (木桶 / 衣柜 / 抹布 / 水渍 inside the dorm, 香炉 inside the hall, no outdoor 木桶 / 晾衣绳 / 香炉 spot left, no wall clothes; 封条 at the library door)",
		"dup %s missing %s" % [dup, missing])
	var bad := []
	for x in sdata["interactables"]:
		if x.has("room") and not it_has_anchor(x):
			bad.append(x["id"])
	r.check(bad.is_empty(), "interior AC5: every room interactable points at a thing of the room art (rooms.json anchors)", str(bad))


func it_has_anchor(x: Dictionary) -> bool:
	var rd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/interiors/rooms.json"))
	for room in rd["rooms"]:
		if room["id"] == x["room"]:
			return room["anchors"].has(x.get("item", ""))
	return false


# ================================================================== AC3 opening + leak
func test_opening_and_leak() -> void:
	var d: Interiors.InteriorDrips = it.drips
	var b0: int = d.landed.get("bucket", 0)
	var w0: int = d.landed.get("pillow", 0)
	await r.frames(240)
	var b1: int = d.landed.get("bucket", 0)
	r.check(story.current_scene == "S1-醒来" and it.bed_state == "sleeping" and b1 - b0 >= 2 and d.landed.get("pillow", 0) - w0 >= 1 and not d.landed.has("head"),
		"interior AC3 (v4): while she sleeps the leaks drip into the bucket (%d drops in 4 s) and onto 师兄's pillow; nothing drips on her bed" % (b1 - b0))
	await finish_scene()
	var w1: int = d.landed.get("pillow", 0)
	var b2: int = d.landed.get("bucket", 0)
	await r.frames(300)
	r.check(d.landed.get("pillow", 0) - w1 >= 2 and d.landed.get("bucket", 0) - b2 >= 2,
		"interior AC3: afterwards both leaks drip on (师兄's pillow and the bucket), continuously", "%d / %d" % [d.landed.get("pillow", 0) - w1, d.landed.get("bucket", 0) - b2])
	# gating: walking out and back does not move the story; the note only after wiping; reading moves it on
	var res: String = await nav.walk_to(it.exit_spot("dorm_main") + Vector2(0, 20))
	await r.frames(30)
	r.check(res == "arrived" and story.stage == 0 and g.hud.objective_label.text == "目标：擦干地上的水",
		"interior AC3 (v4): leaving the dorm before wiping keeps 目标：擦干地上的水", res)
	res = await nav.walk_to(story._thing_pos(inter("note")) + Vector2(0, 8))
	await r.frames(2)
	var no_note: bool = g.prompt_target.get("id", "") != "note"
	await wipe_floor()
	res = await nav.walk_to(story._thing_pos(inter("note")) + Vector2(0, 8))
	await r.frames(2)
	var shown: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 查看"
	await r.tap(KEY_E)
	await finish_scene()
	r.check(res == "arrived" and no_note and shown and story.stage == 1 and g.hud.objective_label.text == "目标：去练武场找师兄",
		"interior AC3 (v4): the table has nothing before the floor is wiped; afterwards E reads the note -> 目标：去练武场找师兄", res)
	await r.frames(2)
	r.check(g.prompt_target.is_empty() or g.prompt_target.get("id", "") != "note", "interior AC3: the note is read once (no prompt on the table afterwards)")


## The v4 wiping task with the keys: the rag in the corner, three E at the puddle (S1-擦水渍 pours the bucket out).
func wipe_floor() -> void:
	await nav.walk_to(story._thing_pos(inter("rag")) + Vector2(0, 4))
	await r.tap(KEY_E)
	await finish_scene()
	await nav.walk_to(story._thing_pos(inter("puddle")) + Vector2(0, 6))
	for n in 3:
		await r.tap(KEY_E)
		await r.frames(30)
	await finish_scene()


# ================================================================== fix round: narrow doors are forgiving
## For each one-tile door: standing off-centre (-16 .. +16 px) and walking into the door goes through, both ways.
func test_door_offsets() -> void:
	var bad := []
	var n := 0
	for room in ["dorm_main", "storage", "dorm_old", "kitchen"]:
		var d: Dictionary = it.rooms[room]["door"]
		for dx in [-16, -12, -8, 0, 8, 12, 16]:
			# enter: from below the door if that spot is free, otherwise already against the wall at that offset
			var st := Vector2(float(d["x"]) + dx, float(d["bottom"]) + 22.0)
			if not r.is_free(st):
				st = Vector2(float(d["x"]) + dx, float(d["bottom"]) + 8.0)
			await r.teleport(st)
			r.hold_dir(Vector2.UP)
			var ok_in := false
			for i in 120:
				await r.physics_frame
				if it.transitioning:
					ok_in = true
					break
			r.release_all()
			await nav.settle()
			ok_in = ok_in and it.room_at(p().global_position) == room
			# exit: inside, at the same offset from the doorway centre
			var e := it.entry_spot(room) + Vector2(dx, 0)
			await r.teleport(e if r.is_free(e) else it.entry_spot(room) + Vector2(dx, 8))
			r.hold_dir(Vector2.DOWN)
			var ok_out := false
			for i in 120:
				await r.physics_frame
				if it.transitioning:
					ok_out = true
					break
			r.release_all()
			await nav.settle()
			ok_out = ok_out and it.room_at(p().global_position) == ""
			n += 2
			if not (ok_in and ok_out):
				bad.append("%s %+d in %s out %s (start %s)" % [room, dx, ok_in, ok_out, st])
	r.check(bad.is_empty() and n == 56, "interior fix: the 4 one-tile doors work from -16 / -12 / -8 / 0 / +8 / +12 / +16 px off centre, in and out (%d walks)" % n, str(bad))
	# still: walking sideways along a front never enters, standing in the strip without pushing never enters
	var t0 := it.transitions
	await r.teleport(Vector2(float(it.rooms["dorm_main"]["door"]["x"]) - 40.0, 931.0))
	await r.push(Vector2.RIGHT, 1.2)
	await r.frames(30)
	r.check(it.transitions == t0 and it.room_at(p().global_position) == "", "interior fix: walking along the dorm front across both wide door strips does not go in")


# ================================================================== AC2 doors
func test_doors() -> void:
	var bad := []
	for room in ROOMS:
		var n := await walk_in(room)
		var in_pos := p().global_position
		var ok_in: bool = n > 0 and it.room_at(in_pos) == room and in_pos.distance_to(it.entry_spot(room)) < 1.0 and p().facing == "up" \
			and r.is_free(in_pos) and p().input_enabled and it.fade_rect.color.a < 0.01
		# stays inside (no ping-pong): wait, then a little walk around
		await r.frames(40)
		var still: bool = it.room_at(p().global_position) == room and not it.transitioning
		var out_ok := await walk_out(room)
		var out_pos := p().global_position
		var ok_out: bool = out_ok and it.room_at(out_pos) == "" and out_pos.distance_to(it.exit_spot(room)) < 1.0 and p().facing == "down" and r.is_free(out_pos)
		await r.frames(40)
		var still_out: bool = it.room_at(p().global_position) == "" and not it.transitioning
		if not (ok_in and still and ok_out and still_out):
			bad.append("%s in %s(%d) %s still %s out %s %s still %s" % [room, ok_in, n, in_pos, still, ok_out, out_pos, still_out])
	r.check(bad.is_empty(), "interior AC2: all 5 doors - walk in (fade, just inside the door, facing in), walk out (outside the right door, facing out), no bounce back", str(bad))
	# repeated in / out with the keys held through the door: one transition per press, never stuck in the doorway
	var t0 := it.transitions
	var loops_ok := true
	for k in 3:
		if await walk_in("kitchen") < 0 or not await walk_out("kitchen"):
			loops_ok = false
	r.check(loops_ok and it.transitions - t0 == 6, "interior AC2: in / out of the kitchen 3 times in a row: exactly 6 door fades", str(it.transitions - t0))
	# keep holding up after entering: she walks on into the room (no second fade); keep holding down after leaving: same
	await walk_in("dorm_old")
	var t1 := it.transitions
	await r.push(Vector2.UP, 0.8)
	var deeper: bool = it.room_at(p().global_position) == "dorm_old" and it.transitions == t1
	await walk_out("dorm_old")
	var t2 := it.transitions
	await r.push(Vector2.DOWN, 0.6)
	r.check(deeper and it.transitions == t2 and it.room_at(p().global_position) == "", "interior AC2: holding the key on after a door does not bounce back through it")
	# standing in the doorway pressing sideways does nothing; only walking into the door
	await r.teleport(it.exit_spot("hall") + Vector2(0, -14))
	var t3 := it.transitions
	await r.push(Vector2.LEFT, 0.4)
	await r.push(Vector2.RIGHT, 0.4)
	r.check(it.transitions == t3 and it.room_at(p().global_position) == "", "interior AC2: walking along the front of a building does not enter it (only walking into the door)")
	# a conversation blocks the doors
	await r.teleport(it.exit_spot("kitchen"))
	story.play("S4-水井")
	r.hold_dir(Vector2.UP)
	await r.frames(60)
	r.release_all()
	var blocked: bool = it.room_at(p().global_position) == "" and not it.transitioning
	await finish_scene()
	r.check(blocked, "interior AC2: no door while a conversation is on screen")
	# the dorm door from the playthrough side (east door of the front dorm) vs the west door (storage)
	r.check(it.rooms["dorm_main"]["door"]["x"] > it.rooms["storage"]["door"]["x"] and it.exit_spot("dorm_main").distance_to(Vector2(370, 947)) < 1.0
		and it.exit_spot("storage").distance_to(Vector2(242, 947)) < 1.0, "interior AC2: front dorm east door -> 主角与师兄宿舍, west door -> 杂物间")


func test_library_locked() -> void:
	await r.teleport(Vector2(243, 660))
	await r.push(Vector2.UP, 1.0)
	var outside: bool = it.room_at(p().global_position) == "" and p().global_position.y > 630 and not it.transitioning
	await r.frames(2)
	var tg: Dictionary = g.prompt_target
	var k: int = story.played.size()
	await r.tap(KEY_E)
	var sc := story.current_scene
	await finish_scene()
	r.check(outside and tg.get("scene", "") == "S5-藏经阁封条" and sc == "S5-藏经阁封条" and story.played.slice(k) == ["S5-藏经阁封条"]
		and not it.rooms.has("library"), "interior AC2: 藏经阁 stays sealed - walking into its door does nothing, E there plays S5-藏经阁封条",
		"%s %s %s" % [p().global_position, tg.get("scene", ""), sc])


# ================================================================== per room: walls, furniture, dodge
func test_room_walls_and_dash() -> void:
	var bad := []
	var pushes := 0
	for room in ROOMS:
		var rect: Rect2 = it.rooms[room]["rect"]
		var fl: Array = it.rooms[room]["def"]["floor"]
		var floor_r := Rect2(rect.position + Vector2(fl[0], fl[1]), Vector2(fl[2], fl[3]))
		# walk + dodge into the 4 walls at several places
		for f in [0.2, 0.5, 0.8]:
			var specs := [
				[Vector2(floor_r.position.x + floor_r.size.x * f, floor_r.position.y + 10), Vector2.UP],
				[Vector2(floor_r.position.x + 10, floor_r.position.y + floor_r.size.y * f), Vector2.LEFT],
				[Vector2(floor_r.end.x - 10, floor_r.position.y + floor_r.size.y * f), Vector2.RIGHT],
				[Vector2(floor_r.position.x + floor_r.size.x * f, floor_r.end.y - 6), Vector2.DOWN],
			]
			for sp in specs:
				var st: Vector2 = r.find_free_near(sp[0], 16)
				if st == Vector2.INF or not floor_r.has_point(st):
					continue
				for mode in ["walk", "dash"]:
					await r.teleport(st)
					if mode == "walk":
						await r.push(sp[1], 0.5)
					else:
						p().facing = CharSheet.dir_from_vector(sp[1], p().facing)
						r.hold_dir(sp[1])
						await r.frames(1)
						await r.tap(KEY_SPACE)
						await r.frames(14)
						r.release_all()
						await r.frames(2)
					pushes += 1
					var q := p().global_position
					var door_out: bool = it.room_at(q) == "" and sp[1] == Vector2.DOWN   # the doorway leads out (a door fade)
					await nav.settle()
					if not door_out and not floor_r.grow(2).has_point(q) and it.room_at(p().global_position) == room:
						bad.append("%s %s %s from %s -> %s" % [room, mode, sp[1], st.round(), q.round()])
					if it.room_at(p().global_position) != room:
						await r.teleport(st)
		# the doorway itself: with the doors off (as if the trigger failed) the plug still holds
	r.check(bad.is_empty() and pushes > 100, "interior AC7/AC2: in every room walking and dodging into the walls never leaves the floor (%d pushes)" % pushes, str(bad))
	# the doorway plug: doors off, push down through the doorway
	it.enabled = false
	var plug_bad := []
	for room in ROOMS:
		await r.teleport(it.entry_spot(room))
		await r.push(Vector2.DOWN, 0.8)
		var q := p().global_position
		if q.y > it.rooms[room]["rect"].end.y:
			plug_bad.append(room)
		await r.teleport(it.entry_spot(room))
		r.hold_dir(Vector2.DOWN)
		await r.frames(1)
		await r.tap(KEY_SPACE)
		await r.frames(14)
		r.release_all()
		if p().global_position.y > it.rooms[room]["rect"].end.y:
			plug_bad.append(room + " (dodge)")
	it.enabled = true
	r.check(plug_bad.is_empty(), "interior AC2: even with the door trigger off, nobody walks or dodges out of a room through the doorway (plug)", str(plug_bad))
	# every furniture box: walk into it from below at its centre (it must hold)
	var fbad := []
	var tested := 0
	for room in ROOMS:
		var o: Vector2 = it.rooms[room]["origin"]
		for c in it.rooms[room]["def"]["colliders"]:
			if c["kind"] == "wall":
				continue
			var rr: Array = c["rect"]
			var rect := Rect2(o + Vector2(rr[0], rr[1]), Vector2(rr[2], rr[3]))
			var below := Vector2(rect.get_center().x, rect.end.y + 7)
			if not r.is_free(below):
				continue
			await r.teleport(below)
			await r.push(Vector2.UP, (rect.size.y + 30.0) / p().stats.walk_speed + 0.1)
			tested += 1
			if p().global_position.y < rect.end.y - 4.0:
				fbad.append("%s %s" % [room, c["kind"]])
			await nav.settle()
	r.check(fbad.is_empty() and tested >= 30, "interior AC2: furniture blocks the way (walked into %d pieces from below)" % tested, str(fbad))
	# camera: indoors the view never shows beyond the room picture where the room is bigger than the view
	var cam_bad := []
	for room in ROOMS:
		var rect: Rect2 = it.rooms[room]["rect"]
		for corner in [Vector2(30, 80), Vector2(rect.size.x - 30, 80), Vector2(30, rect.size.y - 30), Vector2(rect.size.x - 30, rect.size.y - 30)]:
			var st: Vector2 = r.find_free_near(rect.position + corner, 30)
			if st == Vector2.INF:
				continue
			await r.teleport(st)
			await r.process_frame
			await r.process_frame
			var vr: Rect2 = g.view_rect()
			var ok_x := vr.size.x > rect.size.x + 0.5 or (vr.position.x >= rect.position.x - 0.5 and vr.end.x <= rect.end.x + 0.5)
			var ok_y := vr.size.y > rect.size.y + 0.5 or (vr.position.y >= rect.position.y - 0.5 and vr.end.y <= rect.end.y + 0.5)
			var centred_x := vr.size.x <= rect.size.x + 0.5 or absf(vr.get_center().x - rect.get_center().x) < 1.0
			var centred_y := vr.size.y <= rect.size.y + 0.5 or absf(vr.get_center().y - rect.get_center().y) < 1.0
			if not (ok_x and ok_y and centred_x and centred_y):
				cam_bad.append("%s %s view %s" % [room, corner, vr])
	r.check(cam_bad.is_empty(), "interior AC2: the camera stays on the room (scrolls inside the big hall, centred where a room is smaller than the view)", str(cam_bad))


# ================================================================== reachability: door -> every interactable
func test_reachability() -> void:
	var bad := []
	var walked := 0
	for room in ROOMS:
		var seen: PackedByteArray = nav.reachable(room, it.entry_spot(room))
		var gr: Dictionary = nav.room_grid(room)
		var targets := []
		for x in room_things(room):
			targets.append([x["id"], story._thing_pos(x), float(x.get("radius", 30))])
		for spec in it.rooms[room]["def"]["spots"].values():
			targets.append(["npc spot", it.rooms[room]["origin"] + Vector2(spec["pos"][0], spec["pos"][1]), 40.0])
		for tg in targets:
			# some reachable free cell within the interact radius
			var ok := false
			for i in seen.size():
				if seen[i] == 1 and nav.cell_pos(gr, i).distance_to(tg[1]) <= tg[2] - 4.0:
					ok = true
					break
			if not ok:
				bad.append("%s %s (grid)" % [room, tg[0]])
		# and a real walk from the door to each thing, E prompt shows there
		for x in room_things(room):
			if x.has("stage"):
				story.set_stage(int(x["stage"][0]))
			var saved := story.flags.duplicate()
			if x.has("if"):
				story.flags[x["if"]] = true
			if x.has("unless"):
				story.flags.erase(x["unless"])
			await r.teleport(it.entry_spot(room))
			var pos: Vector2 = story._thing_pos(x)
			var res: String = await nav.walk_to(pos + Vector2(0, 6), 40.0)
			await r.frames(2)
			walked += 1
			if res != "arrived" or g.prompt_target.get("id", "") != x["id"]:
				bad.append("%s %s walk %s prompt %s at %s" % [room, x["id"], res, g.prompt_target.get("id", ""), p().global_position.round()])
			story.flags = saved
			story.set_stage(1)
	r.check(bad.is_empty(), "interior AC2: in every room each interactable (and the NPC spot) is reachable from the door - grid search + a real walk to all %d things with the prompt showing" % walked, str(bad))


# ================================================================== AC4 NPCs inside, gating unchanged
func test_npcs_and_gating() -> void:
	var crane := npc("crane")
	var bear := npc("bear")
	var cs: Dictionary = it.rooms["hall"]["def"]["spots"]["crane"]
	var bs: Dictionary = it.rooms["kitchen"]["def"]["spots"]["bear"]
	var crane_ok: bool = it.room_at(crane.global_position) == "hall" and crane.global_position == it.origin("hall") + Vector2(cs["pos"][0], cs["pos"][1]) and crane.facing == "up"
	var anchor_portrait := it.anchor("hall", "portrait")
	var bear_ok: bool = it.room_at(bear.global_position) == "kitchen" and bear.global_position == it.origin("kitchen") + Vector2(bs["pos"][0], bs["pos"][1]) \
		and bear.global_position.distance_to(it.anchor("kitchen", "stove")) < 90.0
	r.check(crane_ok and bear_ok and crane.global_position.distance_to(anchor_portrait) < 60.0,
		"interior AC4: 师父 stands inside the hall before the ancestor portrait (facing it), 厨娘 inside the kitchen by the stove",
		"%s %s %s" % [crane.global_position, crane.facing, bear.global_position])
	var expect := {2: {"crane": "S3-师父", "bear": "S4-厨娘-任务前"}, 3: {"crane": "S3-师父-之后", "bear": "S4-厨娘"},
		4: {"crane": "", "bear": "S4-厨娘-之后"}, 8: {"crane": "S9-师父-收尾"}, 9: {"crane": ""}}
	var bad := []
	for st in expect:
		story.set_stage(st)
		for id in expect[st]:
			var n := npc(id)
			await r.teleport(r.find_free_near(n.global_position + Vector2(0, 26), 16))
			await r.frames(2)
			var got := String(g.prompt_target.get("scene", "")) if g.hud.prompt.visible else ""
			if got != expect[st][id]:
				bad.append("%d %s: %s" % [st, id, got])
	r.check(bad.is_empty(), "interior AC4: inside, 师父 / 厨娘 say what each step allows (steps 3, 4, 9 gating unchanged)", str(bad))
	# talking turns them to the rabbit, afterwards 师父 faces the portrait again
	story.set_stage(3)
	await r.teleport(r.find_free_near(crane.global_position + Vector2(0, 26), 16))
	await r.tap(KEY_E)
	var faced := crane.facing
	await finish_scene()
	r.check(faced == "down" and crane.facing == "up" and story.stage == 3, "interior AC4: 师父 turns to her to talk, then back to the portrait; '之后' does not move on")


# ================================================================== AC5 optional lines once each
func test_optional_lines_once() -> void:
	story.set_stage(1)
	var bad := []
	for x in sdata["interactables"]:
		if not x.has("room"):
			continue
		if x.has("stage"):
			continue        # the note (moves the story on; checked above)
		var pos: Vector2 = story._thing_pos(x)
		await r.teleport(r.find_free_near(pos, 12))
		await r.frames(2)
		var k: int = story.played.size()
		await r.tap(KEY_E)
		var lines := []
		for i in 100:
			if not story.busy:
				break
			if story.dialogue.active and not story.dialogue.is_typing():
				lines.append(story.dialogue.full_text)
				await r.tap(KEY_E)
			elif story.dialogue.active:
				await r.tap(KEY_E)
			else:
				await r.frames(1)
		var want: Array = sdata["scenes"][x["scene"]].filter(func(e): return e.has("text")).map(func(e): return e["text"])
		if story.played.slice(k) != [x["scene"]] or lines != want:
			bad.append("%s %s %s" % [x["id"], story.played.slice(k), lines])
	r.check(bad.is_empty(), "interior AC5: every room's optional lines play from their thing, each line once per E, word for word", str(bad))


# ================================================================== minimap (打磨 v1: round, player-centred)
func test_minimap_and_star() -> void:
	var mm: Minimap = g.hud.minimap
	story.set_stage(2)      # 去正殿见师父 (师父 inside the hall)
	await r.teleport(r.tile_center(31, 29))
	await r.frames(3)
	var a: bool = mm.star_target_world.distance_to(it.door_point("hall")) < 1.0 and mm.room == ""
	await r.teleport(it.world_point("kitchen", Vector2(240, 180)))
	await r.frames(3)
	var in_kitchen: bool = mm.room == "kitchen" and mm.center_world == p().global_position
	var b: bool = mm.star_target_world.distance_to(it.doorway_point("kitchen")) < 1.0 and mm.star_on_rim
	await r.teleport(it.world_point("hall", Vector2(320, 230)))
	await r.frames(3)
	var c: bool = mm.star_target_world.distance_to(npc("crane").global_position) < 1.0 and mm.room == "hall"
	story.set_stage(1)      # 去练武场找师兄 from inside: her doorway, on the rim
	await r.frames(3)
	var d: bool = mm.star_target_world.distance_to(it.doorway_point("hall")) < 1.0 and mm.star_on_rim
	r.check(a and b and c and d and in_kitchen,
		"interior minimap: target inside -> star on that building's door (from outside); from another room / target outdoors -> on the rim towards her doorway; in the same room -> its place; indoors the circle shows the room",
		"%s %s %s %s %s" % [a, b, c, d, in_kitchen])


# ================================================================== AC7 light (打磨 v1 rules)
func test_light() -> void:
	var dn: DayNight = g.daynight
	var worst := 1.0
	for m in range(0, 1440, 15):
		dn.set_hour(float(m) / 60.0)
		worst = minf(worst, Interiors.indoor_look(dn.look(), dn.lamp_level(), "dorm_main")["tint"].get_luminance())
	dn.set_hour(2.0)
	var night_out: float = dn.look()["tint"].get_luminance()
	await r.teleport(it.world_point("dorm_main", Vector2(240, 180)))
	await r.frames(45)
	var amb: Ambience = g.ambience
	var night_in: float = amb.modulate_node.color.get_luminance()
	var lamp_on: bool = it.lit_lights("dorm_main").size() >= 1
	dn.set_hour(12.0)
	await r.frames(3)
	var noon_in: float = amb.modulate_node.color.get_luminance()
	var lamp_off: bool = it.lit_lights("dorm_main").is_empty()
	await r.teleport(r.tile_center(31, 29))
	await r.frames(45)
	var noon_out: float = amb.modulate_node.color.get_luminance()
	var floor_l := Interiors.night_floor("dorm_main")
	r.check(worst >= floor_l - 0.005 and night_in >= floor_l - 0.005 and night_in > night_out + 0.05 and noon_in > 0.85 and night_in < noon_in - 0.3
		and lamp_on and lamp_off and absf(noon_out - dn.look()["tint"].get_luminance()) < 0.01,
		"interior AC7: indoor light - never darker than luminance %.2f (deep night outside %.2f, inside %.2f; noon inside %.2f), the oil lamp glows indoors at night only" % [worst, night_out, night_in, noon_in])
	dn.set_hour(8.0)


# ================================================================== AC7 no combat indoors
func test_no_combat_indoors() -> void:
	var c: Combat = g.combat
	var inside := []
	for f in c.fighters:
		if it.room_at(f.global_position) != "" or it.room_at(f.home) != "":
			inside.append(f.id)
	# J indoors: the swing hits nothing, no fight starts
	await r.teleport(it.world_point("hall", Vector2(320, 230)))
	var hits_before := 0
	await r.tap(KEY_J)
	await r.frames(40)
	var no_hit: bool = p().last_hits == 0 and c.engaged_enemies().is_empty() and c.spar_state == "none"
	# 师兄 never offers the spar indoors (he is outside); the spar blocks the doors
	await r.teleport(r.find_free_near(npc("fox").global_position + Vector2(0, 26), 16))
	story.set_stage(2)
	c.open_choice()
	await r.tap(KEY_1)
	await r.frames(10)
	var fighting: bool = c.spar_state == "fighting"
	await r.teleport(it.exit_spot("hall"))
	r.hold_dir(Vector2.UP)
	await r.frames(60)
	r.release_all()
	var stayed_out: bool = it.room_at(p().global_position) == "" and not it.transitioning
	c.end_spar(true)
	for i in 400:
		if c.spar_state == "none":
			break
		await r.physics_frame
	await finish_scene()
	r.check(inside.is_empty() and no_hit and fighting and stayed_out and hits_before == 0,
		"interior AC7: no combat indoors - no fighter is ever inside, J indoors hits nothing and starts nothing, a running spar keeps the doors shut",
		"inside %s hit %s fighting %s stayed %s" % [inside, no_hit, fighting, stayed_out])
