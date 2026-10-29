extends RefCounted
## 坐下与人物作息 v1 checks (docs/design/坐下与人物作息-方案-v1.md section 五, task packet AC1-AC7), run by tests/run_tests.gd,
## or alone:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-schedule   (--sch=name,name)
## Real keys (E / Space / arrows / WASD / Q / Enter / T / Esc), a real mouse click and real physics wherever the player does
## something; the clock (and, for the predicate check, a combat flag) is set directly only as a starting point.

var r
var ss
var t3
var s4
var g: Node
var story: Story
var dlg: Dialogue
var smp: Sample
var s3: Step3
var jh: Jianghu
var gd: Guide
var qb: QuestBoard
var sch: Schedule
var st: Seats
var only: Array = []
var report := {}

const TABLE := {"crane": [21, 6], "fox": [22, 7], "bear": [20, 5], "dog": [22, 6], "tanuki": [19, 7], "duck": [19, 7],
	"mouse": [18, 8]}
const STAND_KEYS := [KEY_E, KEY_SPACE, KEY_LEFT, KEY_W, KEY_DOWN, KEY_D, KEY_UP, KEY_A]


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	r.root.size = Vector2i(1440, 810)
	SaveGame.erase()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--sch="):
			only = String(a).trim_prefix("--sch=").split(",")
	ss = load("res://tests/sample_suite.gd").new(r)
	t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	s4 = load("res://tests/step4a_suite.gd").new(r)
	s4.ss = ss
	s4.t3 = t3
	var tests := ["tables", "art", "seats", "seat_rules", "presence", "fade", "prologue", "busy", "spar", "fox_bed",
		"prompts_minimap", "button_states", "button_night", "button_click", "same_as_t", "save_load", "layout", "commission_grey",
		"fox_prompt_face", "bubble_seen", "detail_late"]
	for name in tests:
		if only.is_empty() or name in only:
			await call("test_" + name)
	await ss._free_game()
	SaveGame.erase()
	print("SCHEDULE REPORT ", report)


# ================================================================== helpers
func bind() -> void:
	s4.bind()
	g = ss.g
	story = g.story
	dlg = story.dialogue
	smp = g.sample
	s3 = g.step3
	jh = g.jianghu
	gd = g.guide
	qb = g.quest_board
	sch = g.schedule
	st = g.seats


func p() -> Player:
	return g.player


## A game after the prologue (the real ending), day index `day_idx`, the clock stopped.
func game(day_idx := 0) -> void:
	await t3.unlocked_game(day_idx)
	bind()
	g.daynight.running = false
	await r.frames(3)


## The clock forward to `h` o'clock (a starting point), then `f` frames.
func clock(h: float, f := 3) -> void:
	g.daynight.set_hour(h)
	await r.frames(f)


## Forward to `h` and past the 0.5 s fades.
func clock_settled(h: float) -> void:
	await clock(h, 3)
	await r.frames(int(sch._fade_secs() * 60.0) + 8)


func npc(id: String) -> Npc:
	return sch.npc_of(id)


func vp() -> Rect2:
	return g.get_viewport().get_visible_rect()


## Window position of the centre of a control (through the canvas layer and the window stretch).
func screen_pos(c: Control) -> Vector2:
	return r.root.get_final_transform() * c.get_global_rect().get_center()


func click(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await r.process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await r.process_frame
		await r.process_frame


func open_board() -> bool:
	await r.tap(KEY_Q)
	await r.process_frame
	return qb.is_open


func close_board() -> void:
	if qb.is_open:
		await r.tap(KEY_Q)
		await r.process_frame


## Runs until the 等到天亮 night is over (or `limit` frames). Returns {black_frames, label_seen, label_text, max_alpha}.
func watch_night(limit := 900) -> Dictionary:
	var out := {"black_frames": 0, "label_seen": false, "label_text": "", "max_alpha": 0.0, "started": false}
	for i in limit:
		if sch.waiting:
			out["started"] = true
		elif out["started"]:
			break
		var a: float = sch.fade_rect.color.a if sch.fade_rect.visible else 0.0
		out["max_alpha"] = maxf(float(out["max_alpha"]), a)
		if a >= 0.999:
			out["black_frames"] = int(out["black_frames"]) + 1
		if sch.fade_label.modulate.a >= 0.999 and sch.fade_rect.visible:
			out["label_seen"] = true
			out["label_text"] = sch.fade_label.text
		await r.physics_frame
	await r.frames(3)
	return out


## A free spot within the seat's reach from which E would sit on it (the other things of the room keep their own reach).
func seat_spot(s: Dictionary) -> Vector2:
	var w: Vector2 = st.seat_world(s)
	for rad in [12.0, 16.0, 20.0, 22.0]:
		for k in 16:
			var a := PI * 0.5 + TAU * float(k) / 16.0
			var c: Vector2 = w + Vector2(cos(a), sin(a)) * rad
			if not r.is_free(c):
				continue
			await r.teleport(c)
			var t: Dictionary = story.interaction_target()
			if String(t.get("seat", "")) == String(s["id"]):
				return c
	return Vector2.INF


func seat_targets_near(s: Dictionary) -> Array:
	var w: Vector2 = st.seat_world(s)
	var hits := []
	for rad in [10.0, 16.0, 22.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var c: Vector2 = w + Vector2(cos(a), sin(a)) * rad
			if not r.is_free(c):
				continue
			await r.teleport(c)
			var t: Dictionary = story.interaction_target()
			if String(t.get("seat", "")) == String(s["id"]):
				hits.append(c)
	return hits


# ================================================================== the data
func test_tables() -> void:
	var d := Schedule.load_data()
	var ok := true
	var bad := []
	for id in TABLE:
		var sp: Dictionary = d["people"].get(id, {})
		if sp.is_empty() or int(sp["sleep"]) != TABLE[id][0] or int(sp["wake"]) != TABLE[id][1]:
			bad.append(id)
	ok = bad.is_empty() and (d["people"] as Dictionary).size() == TABLE.size()
	r.check(ok, "schedule AC2: data/schedule.json people = the plan's table (师父 21-6, 师兄 22-7, 厨娘 20-5, 老伯 22-6, 茶摊老板 19-7, 村民 19-7, 老周 18-8)", str(bad))
	r.check(not (d["people"] as Dictionary).has("squirrel") and not (d["people"] as Dictionary).has("wolf")
		and not (d["people"] as Dictionary).has("boar"), "schedule AC2: 师弟 and the bandits are not in the table (they keep their own day / stay out at night)")
	var w: Dictionary = d["wait"]
	r.check(int(w["to_hour"]) == 8 and is_equal_approx(float(w["fade_seconds"]), 0.5) and is_equal_approx(float(w["text_seconds"]), 1.5)
		and is_equal_approx(float(d["fade_seconds"]), 0.5) and bool(d["prologue_first"]),
		"schedule AC2: 等到天亮 to 08:00, the fade seconds, 0.5 s person fades and 'nobody sleeps before the prologue' are in schedule.json", str(w))
	var fox: Dictionary = d["people"]["fox"]
	var ui: Dictionary = d["ui"]
	r.check(String(fox["night"]) == "bed" and String(fox["dream"]) == "（呼……谁动我萝卜……）"
		and d["people"].keys().filter(func(k): return String(d["people"][k]["night"]) == "bed").size() == 1,
		"schedule AC2: only 师兄 sleeps in sight (his bed); his dream line is the plan's")
	r.check(String(ui["bubble"]) == "呼……" and String(ui["wait_button"]) == "等到天亮（辰时 08:00）" and String(ui["all_awake"]) == "大家都醒着"
		and String(ui["wait_note"]) == "跳过去后，今天没做完的委托会作废。" and String(ui["night_passes"]) == "一夜过去……"
		and ("%02d:00" % int(w["to_hour"])) in String(ui["wait_button"]),
		"schedule AC2/AC3: the bubble, button, grey text, note and night caption are the plan's words (the button names the hour it jumps to)", str(ui))
	var icfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/interiors.json"))
	var seats: Array = icfg["seats"]
	var per := {}
	for s in seats:
		var k := "%s:%s" % [s["room"], s["type"]]
		per[k] = int(per.get(k, 0)) + 1
	var lines := {}
	for s in seats:
		if s.has("line"):
			lines[String(s["id"])] = String(s["line"])
	r.check(seats.size() == 8 and per == {"dorm_main:cushion": 2, "hall:futon": 4, "kitchen:stool": 1, "kitchen:bench": 1}
		and lines == {"hall_futon_master": "（坐上去软塌塌的，师父坐了几十年。）", "kitchen_stool": "（灶火暖烘烘的，有点想睡。）"},
		"schedule AC1: data/interiors.json seats = 8 (宿舍 2 坐垫, 正殿 4 蒲团, 厨房 小板凳 + 长凳), the two lines on 师父's 蒲团 and the stool", str([per, lines]))
	# English: every text a player can see has an English line (no Chinese left)
	var tr := LangTranslation.new()
	var texts: Array = [ui["bubble"], ui["prompt_sit"], ui["prompt_dream"], ui["wait_button"], ui["all_awake"], ui["wait_note"],
		ui["night_passes"], fox["dream"]] + lines.values()
	texts.append(String(ui["commission_asleep"]))
	texts.append(String(ui["opt_c_asleep"]) % "送信")
	var missing := texts.filter(func(x): return tr.has_cjk(tr.translate_text(String(x))))
	r.check(missing.is_empty(), "schedule AC6: every new text has its English (data/i18n/en_schedule.json)", str(missing))
	# 小兔 is male: no 她 / 师姐 / she / her anywhere in the new data
	var raw := FileAccess.get_file_as_string("res://data/schedule.json") + FileAccess.get_file_as_string("res://data/i18n/en_schedule.json") \
		+ FileAccess.get_file_as_string("res://scripts/schedule.gd") + FileAccess.get_file_as_string("res://scripts/seats.gd")
	var re := RegEx.create_from_string("(?i)\\b(she|her|hers|herself)\\b")
	r.check(not ("她" in raw) and not ("师姐" in raw) and re.search(raw) == null,
		"schedule: the new texts / code never call 小兔 她 / 师姐 / she / her")


func test_art() -> void:
	var sit := Image.load_from_file("res://assets/schedule/rabbit_sit.png")
	var bed := Image.load_from_file("res://assets/schedule/fox_asleep_bed.png")
	var rooms = JSON.parse_string(FileAccess.get_file_as_string("res://assets/interiors/rooms.json"))
	var messy := Rect2()
	for rm in rooms["rooms"]:
		if rm["id"] == "dorm_main":
			for f in rm["furniture"]:
				if f["name"] == "senior_bed":
					messy = Rect2(f["rect"][0], f["rect"][1], f["rect"][2], f["rect"][3])
	var f0 := sit.get_region(Rect2i(0, 0, 32, 32))
	var f1 := sit.get_region(Rect2i(32, 0, 32, 32))
	r.check(sit.get_size() == Vector2i(64, 32) and f0.get_data() != f1.get_data(),
		"schedule AC1 art: 小兔坐姿 is 2 frames of 32x32 (breathing: the frames differ)", str(sit.get_size()))
	r.check(bed.get_size() == Vector2i(int(messy.size.x), int(messy.size.y)),
		"schedule AC2 art: 师兄 asleep under his quilt is exactly the size of his bed (bed_messy)", "%s vs %s" % [bed.get_size(), messy.size])
	var sf: SpriteFrames = CharSheet.frames_for("rabbit")
	r.check(sf.has_animation("sit_down") and sf.get_frame_count("sit_down") == 2, "schedule AC1 art: the rabbit's frames have the 2-frame sit_down")


# ================================================================== AC1 sitting
func test_seats() -> void:
	await game()
	await clock(10.0)
	var bad := []
	var done := []
	var i := 0
	var fits := []
	for s in st.seats:
		var id := String(s["id"])
		if id == "hall_futon_master":
			continue      # 师父 stands on it by day: test_seat_rules (night)
		var from := await seat_spot(s)
		if from == Vector2.INF:
			bad.append(id + ": no spot with the prompt")
			continue
		await r.frames(2)
		var prompt_ok: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 坐下"
		var att0 := p().attacks_started
		await r.tap(KEY_E)
		await r.frames(2)
		# 坐姿重画 v1: the picture and facing now depend on the seat's pose (was: always "sit_down" facing down) -
		# bench / stool = the back view facing up (the table), cushion / 蒲团 = cross-legged facing down
		var want_anim := "sit_back" if String(s.get("pose", "")) == "back" else "sit_cross"
		var want_face := "up" if want_anim == "sit_back" else "down"
		var on: bool = st.sitting == id and p().global_position.distance_to(st.seat_world(s)) < 0.01 and p().sprite.animation == want_anim \
			and p().facing == want_face and p().sprite.is_playing() and not g.hud.prompt.visible
		# J while sitting: nothing; a few frames: he does not move
		await r.tap(KEY_J)
		await r.frames(20)
		var still := p().global_position.distance_to(st.seat_world(s)) < 0.01 and p().attacks_started == att0
		var key: Key = STAND_KEYS[i % STAND_KEYS.size()]
		i += 1
		await r.tap(key)
		await r.frames(2)
		var up: bool = st.sitting == "" and st.stood_at.distance_to(from) < 0.01 and r.is_free(st.stood_at) \
			and not p().is_dashing() and p().sprite.offset == Vector2(-16, -31) and p().is_physics_processing()
		# walking off again (away from the seat): he moves, nothing holds him
		var away: Vector2 = (from - st.seat_world(s)).normalized()
		var before := p().global_position
		await r.push(away, 0.4)
		var moved: bool = p().global_position.distance_to(before) > 6.0 and r.is_free(p().global_position)
		if prompt_ok and on and still and up and moved:
			done.append(id)
		else:
			bad.append("%s prompt %s sit %s still %s up %s moved %s (%s)" % [id, prompt_ok, on, still, up, moved, OS.get_keycode_string(key)])
	report["seats_sat"] = done
	r.check(bad.is_empty() and done.size() == 7,
		"schedule AC1: each seat (7 by day + 师父's at night below): 按 E 坐下 -> he sits in the seat's pose (bench / stool: back view facing up; cushion / 蒲团: cross-legged facing down), breathing, no prompt; J does nothing; E / Space / an arrow / WASD stands him up exactly where he stood (free), and he walks off", str(bad))
	# breathing = two different pictures
	var sf: SpriteFrames = p().sprite.sprite_frames
	var breathes := true
	for anim in ["sit_down", "sit_back", "sit_cross"]:
		breathes = breathes and sf.get_frame_count(anim) == 2 and sf.get_frame_texture(anim, 0).region != sf.get_frame_texture(anim, 1).region \
			and sf.get_animation_speed(anim) > 0.0
	r.check(breathes, "schedule AC1: every sitting picture (old front, back view, cross-legged) breathes (2 frames)")


func test_seat_rules() -> void:
	await game()
	await clock_settled(10.0)
	var master: Dictionary = st.seat("hall_futon_master")
	var crane := npc("crane")
	var hits := await seat_targets_near(master)
	r.check(crane.visible and st.occupied(master) and hits.is_empty(),
		"schedule AC1: 师父 stands on his worn 蒲团 by day -> no 按 E 坐下 there", str(hits.size()))
	# night: 师父 is asleep, the seat is free; the line once
	await clock_settled(22.0)
	var from := await seat_spot(master)
	await r.tap(KEY_E)
	await r.frames(3)
	var line := "（坐上去软塌塌的，师父坐了几十年。）"
	var shown: bool = st.sitting == "hall_futon_master" and line in sch.bubble_texts() and g.hud.bubble.visible and g.hud.bubble_label.text == line
	var on_rabbit: bool = String(sch.bubble().get("who", "")) == "rabbit"
	await r.tap(KEY_SPACE)
	await r.frames(200)     # the bubble is over
	await r.teleport(from)
	await r.tap(KEY_E)
	await r.frames(3)
	var again: bool = st.sitting == "hall_futon_master" and not (line in sch.bubble_texts())
	await r.tap(KEY_E)
	await r.frames(2)
	r.check(from != Vector2.INF and shown and on_rabbit and again and st.lines_shown.count(line) == 1,
		"schedule AC1: at night 师父's 蒲团 is free; the first time there his line is a bubble over 小兔 (no dialogue), the second time none",
		str([from, shown, on_rabbit, again]))
	r.check(not story.busy and not dlg.active, "schedule AC1: the seat lines never open the dialogue box")
	# the stool's line, once
	var stool: Dictionary = st.seat("kitchen_stool")
	var sf := await seat_spot(stool)
	await r.tap(KEY_E)
	await r.frames(3)
	var l2 := "（灶火暖烘烘的，有点想睡。）"
	var s1: bool = l2 in sch.bubble_texts() and g.hud.bubble.visible and g.hud.bubble_label.text == l2     # 厨娘's walking line is close by
	await r.tap(KEY_E)
	await r.frames(200)
	await r.teleport(sf)
	await r.tap(KEY_E)
	await r.frames(3)
	var s2: bool = not (l2 in sch.bubble_texts())
	await r.tap(KEY_E)
	await r.frames(2)
	r.check(s1 and s2 and st.lines_shown.count(l2) == 1, "schedule AC1: the stool's line only the first time", str([s1, s2]))
	# a plain seat has no line
	var c1: Dictionary = st.seat("dorm_cushion_1")
	await seat_spot(c1)
	var n0 := sch.bubble_texts().size()
	await r.tap(KEY_E)
	await r.frames(3)
	var plain: bool = st.sitting == "dorm_cushion_1" and sch.bubble_texts().size() == n0
	await r.tap(KEY_E)
	r.check(plain, "schedule AC1: the other seats have no line")
	# the seats never take a prompt away: between the wardrobe and the second cushion the wardrobe wins
	var it: Interiors = g.interiors
	var wpos: Vector2 = it.anchor("dorm_main", "wardrobe")
	var c2: Vector2 = st.seat_world(st.seat("dorm_cushion_2"))
	var both := Vector2.INF
	for k in 40:
		var c := wpos.lerp(c2, float(k) / 39.0)
		if r.is_free(c) and c.distance_to(wpos) <= 29.0 and c.distance_to(c2) <= 23.0:
			both = c
			break
	var wins := ""
	if both != Vector2.INF:
		await r.teleport(both)
		wins = String(story.interaction_target().get("id", ""))
	r.check(both != Vector2.INF and wins == "wardrobe", "schedule AC1: where a thing and a seat are both in reach, the thing keeps its prompt", str([both, wins]))
	# nothing of it is saved
	var keys := SaveGame.capture(g).keys()
	keys.sort()
	# 武学与经营 第一批: the save gained its two documented sections "skills" (A) and "farm" (B); neither holds the seat,
	# the seat lines or who is asleep - checked below by their own keys, so the old meaning of this check stays
	var sk_keys: Array = (SaveGame.capture(g).get("skills", {}) as Dictionary).keys()
	var fm_text := str(SaveGame.capture(g).get("farm", {}))
	r.check(keys == ["combat", "dorm", "farm", "guide", "jianghu", "player", "sample", "skills", "step3", "story", "time"]
		and sk_keys.all(func(k): return k in ["learned", "slots", "inner", "trials"])
		and not ("sitting" in fm_text or "seat" in fm_text or "asleep" in fm_text),
		"schedule AC4: the save has no new field (sitting, the lines, who is asleep are not stored)", str(keys))


# ================================================================== AC2 who is there when
func expected_absent(h: float) -> Dictionary:
	var out := {}
	for id in TABLE:
		out[id] = Schedule.asleep_at({"sleep": TABLE[id][0], "wake": TABLE[id][1]}, h)
	return out


func test_presence() -> void:
	await game()
	await clock_settled(12.0)
	var bandits0: Array = g.combat.bandits.map(func(b): return [b.visible, b.collision_layer])
	var hours := [17.99, 18.0, 18.99, 19.0, 19.99, 20.0, 20.99, 21.0, 21.99, 22.0, 23.99, 0.0, 0.01, 4.99, 5.0, 5.99, 6.0, 6.99,
		7.0, 7.99, 8.0, 12.0]
	var bad := []
	for h in hours:
		await clock_settled(h)
		var want := expected_absent(h)
		for id in TABLE:
			var n := npc(id)
			var gone: bool = sch.absent(id)
			var ok: bool = gone == bool(want[id]) and n.visible == (not gone) and (n.collision_layer == 0) == gone
			if not ok:
				bad.append("%05.2f %s want %s got absent %s visible %s layer %d" % [h, id, want[id], gone, n.visible, n.collision_layer])
	r.check(bad.is_empty(), "schedule AC2: every person is there / gone exactly by the table, just before and after each time, around 00:00 too (solid only when there)",
		str(bad.slice(0, 8)))
	var bandits1: Array = g.combat.bandits.map(func(b): return [b.visible, b.collision_layer])
	var others: bool = sch.changes.all(func(c): return TABLE.has(String(c["id"])))
	r.check(bandits0 == bandits1 and others, "schedule AC2: the bandits are untouched by the night; only the table's people ever change", str([bandits0, bandits1]))


func test_fade() -> void:
	await game()
	await clock_settled(20.5)
	var crane := npc("crane")
	await ss.stand_near(crane.global_position)
	var head := crane.head_position()
	await clock(21.0, 1)
	var gone_now: bool = not crane.visible and crane.collision_layer == 0 and story.interaction_target().get("npc", null) != crane
	var ghost: Node = g.world.get_node_or_null("ScheduleGhost_crane")
	var a0: float = ghost.modulate.a if ghost != null else -1.0
	await r.frames(2)
	var bub: Dictionary = sch.bubble()
	var hud_bub: bool = g.hud.bubble.visible and g.hud.bubble_label.text == "呼……"
	await r.frames(13)
	var a_mid: float = ghost.modulate.a if is_instance_valid(ghost) else -1.0
	await r.frames(25)
	var ghost_gone := not is_instance_valid(ghost) or ghost.is_queued_for_deletion()
	r.check(gone_now and a0 > 0.9 and String(bub.get("text", "")) == "呼……" and (bub.get("pos", Vector2.ZERO) as Vector2).distance_to(head) < 1.0
		and hud_bub and a_mid > 0.2 and a_mid < 0.8 and ghost_gone,
		"schedule AC2: 21:00 -> '呼……' over 师父's head, his picture fades out in 0.5 s, he is gone (no prompt, not solid) at once",
		str([gone_now, a0, bub, hud_bub, a_mid, ghost_gone]))
	await r.frames(60)
	var bub_over: bool = not g.hud.bubble.visible
	# 06:00: fades in on his spot, then he is there
	await clock(6.0, 1)
	var g2: Node = g.world.get_node_or_null("ScheduleGhost_crane")
	var early := not crane.visible and g2 != null and (g2 as Sprite2D).position.distance_to(crane.global_position + crane.sprite.position) < 0.5
	await r.frames(40)
	var crane_bubble: bool = sch._bubbles.any(func(b): return String(b["who"]) == "crane")
	r.check(bub_over and early and crane.visible and crane.collision_layer == 1 and not crane_bubble,
		"schedule AC2: the bubble goes away; at 06:00 he fades in on his own spot (no bubble), then is there and solid",
		str([bub_over, early, crane.visible, crane.collision_layer, crane_bubble]))


func test_prologue() -> void:
	await ss.new_game()
	bind()
	await ss.finish_scene()
	await clock_settled(23.0)
	var all_there := TABLE.keys().filter(func(id): return id != "mouse").all(func(id): return npc(id).visible and not sch.absent(id))
	var opened := await open_board()
	r.check(story.stage < 9 and not sch.active() and all_there and not opened and not sch.wait_shown() and sch.changes.is_empty(),
		"schedule AC2/AC3: before the prologue is done nobody sleeps at 23:00 (and the board with its button does not open)", str([story.stage, all_there, opened]))
	await close_board()
	# the older suites' sandbox: never
	story.enter_sandbox()
	await clock_settled(23.5)
	r.check(not sch.active() and TABLE.keys().filter(func(id): return id != "mouse").all(func(id): return npc(id).visible),
		"schedule AC2: the story-less sandbox of the older suites keeps everybody at every hour")


func test_busy() -> void:
	await game()
	await clock_settled(18.5)
	# a conversation with 村民 runs past 19:00: he waits for its end
	var duck := npc("duck")
	await s4.walk(duck.global_position + Vector2(0, 24))
	await r.tap(KEY_E)
	await r.frames(4)
	var talking := story.busy
	await clock(19.5, 30)
	var stayed := duck.visible and not sch.absent("duck")
	await ss.finish_scene()
	await r.frames(4)
	var left := not duck.visible and sch.absent("duck")
	r.check(talking and stayed and left, "schedule AC2: talking to 村民 past 19:00 -> he stays until the conversation is over, then goes",
		str([talking, stayed, left]))
	# fights / 比武 / 试炼 / bandit fights: nobody vanishes in the middle (the predicate the schedule waits on)
	await clock_settled(20.5)
	var c: Combat = g.combat
	var res := {}
	for flag in ["trial_active", "bout_session"]:
		c.set(flag, true)
		await clock(21.0 if flag == "trial_active" else 22.0, 20)
		var held := not sch.absent("crane" if flag == "trial_active" else "dog")
		c.set(flag, false)
		await r.frames(3)
		res[flag] = held and sch.absent("crane" if flag == "trial_active" else "dog")
	var f: Fighter = c.bandits[0] if not c.bandits.is_empty() else null
	await clock_settled(12.0)
	var engaged_held := false
	if f != null:
		await clock(18.0, 2)
		f.engaged = true
		await clock(19.0, 20)
		engaged_held = not sch.absent("tanuki") and c.in_combat()
		f.engaged = false
		await r.frames(3)
		engaged_held = engaged_held and sch.absent("tanuki")
	r.check(res.get("trial_active", false) and res.get("bout_session", false) and engaged_held,
		"schedule AC2: during a 梅花桩 trial, a 比武 bout or a fight with an engaged bandit nobody disappears; they go when it ends", str([res, engaged_held]))


## 切磋 with 师兄 past 22:00 by real keys, fought by the bot: he stays the whole fight, then goes to bed.
func test_spar() -> void:
	await game()
	await clock_settled(21.5)
	var c: Combat = g.combat
	var fox: Fighter = npc("fox")
	await s4.walk(fox.global_position + Vector2(0, 30))
	await r.tap(KEY_E)
	for i in 300:
		if c.spar_state == "choosing":
			break
		if dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await clock(22.5, 20)
	var choosing_held := c.spar_state == "choosing" and fox.visible
	await r.tap(KEY_1)
	t3.cs._dodged_for = {}
	t3.cs._gp_for = {}
	var always := true
	var frames := 0
	for i in 60 * 90:
		if c.spar_state != "fighting":
			break
		frames += 1
		if not fox.visible or sch.absent("fox"):
			always = false
		t3.cs.bot_step("gp")
		await r.physics_frame
	t3.cs._release()
	r.release_all()
	for i in 600:
		if c.spar_state == "none" and not story.busy:
			break
		if dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.frames(40)
	r.check(choosing_held and frames > 30 and always and sch.absent("fox") and not fox.visible and sch.bed_shown(),
		"schedule AC2: a 切磋 with 师兄 going past 22:00 -> he stays through the choice and the whole fight, then goes to his bed",
		str([choosing_held, frames, always, sch.absent("fox"), sch.bed_shown()]))


func test_fox_bed() -> void:
	await game()
	await clock_settled(12.0)
	var it: Interiors = g.interiors
	var bp: Vector2 = sch.bed_point()
	# by day: the empty bed's own look
	await ss.stand_near(bp)
	var day_t: Dictionary = story.interaction_target()
	r.check(String(day_t.get("id", "")) == "senior_bed" and not sch.bed_shown(), "schedule AC2: by day 师兄's bed is empty (its own 按 E 查看)", str(day_t))
	await clock_settled(22.0)
	var fox := npc("fox")
	var t: Dictionary = story.interaction_target()
	var prompt_ok: bool = String(t.get("kind", "")) == "schedule" and String(t.get("id", "")) == "dream" and g.hud.prompt.visible \
		and g.hud.prompt_label.text == "按 E 查看"
	await r.tap(KEY_E)
	await r.frames(3)
	var line := "（呼……谁动我萝卜……）"
	var said: bool = g.hud.bubble.visible and g.hud.bubble_label.text == line and not dlg.active and not story.busy and sch.dreams == 1
	r.check(not fox.visible and sch.bed_shown() and it.room_at(sch.bed_sprite.global_position) == "dorm_main" and prompt_ok and said,
		"schedule AC2: at night 师兄 is not in the 练武场 but asleep in his own bed (the new picture); E there: '（呼……谁动我萝卜……）' as a bubble",
		str([fox.visible, sch.bed_shown(), prompt_ok, said]))
	# the picture sits exactly on the bed
	var f: Sprite2D = it.rooms["dorm_main"]["furniture"]["senior_bed"]
	var same := (sch.bed_sprite.global_position + sch.bed_sprite.offset).distance_to(f.global_position + f.offset) < 0.2 \
		and sch.bed_sprite.texture.get_size() == f.region_rect.size and sch.bed_sprite.global_position.y > f.global_position.y
	r.check(same, "schedule AC2: the sleeping picture covers the bed exactly and is drawn over it", str([sch.bed_sprite.global_position, f.global_position]))
	await clock_settled(7.0)
	r.check(fox.visible and not sch.bed_shown() and String(story.interaction_target().get("id", "")) == "senior_bed",
		"schedule AC2: 07:00 -> he is back in the 练武场, the bed is empty again")


func test_prompts_minimap() -> void:
	await game()
	await clock_settled(23.0)
	var bad := []
	for id in TABLE:
		var n := npc(id)
		await ss.stand_near(n.global_position)
		await r.frames(2)
		var t: Dictionary = story.interaction_target()
		if t.get("npc", null) == n or g.nearest_npc() == n or story.poi_points().has(n.global_position):
			bad.append(id)
	r.check(bad.is_empty(), "schedule AC2: at night there is no 按 E at anybody's place, and they are not points of interest", str(bad))
	# the gold arrow: tracking 老周's repair (宿舍屋顶) and 老伯's (旧弟子房)
	var res := {}
	for key in ["repair:roof", "repair:dorm_old"]:
		gd.set_track(key)
		await clock_settled(23.5)
		await r.frames(2)
		var night_arrow: bool = g.hud.minimap.track_active
		await clock_settled(10.0)
		await r.frames(2)
		var day_arrow: bool = g.hud.minimap.track_active
		res[key] = [night_arrow, day_arrow]
	r.check(res["repair:roof"] == [false, true] and res["repair:dorm_old"] == [false, true],
		"schedule AC2: the minimap arrow of a tracked repair does not point at 老周 / 老伯 while they are asleep (it does by day)", str(res))
	r.check(sch.filter_target(npc("crane").global_position) != null, "schedule AC2: by day the star / arrow may aim at anybody")


# ================================================================== AC3 the button
func test_button_states() -> void:
	await game()
	await clock_settled(10.0)
	var opened := await open_board()
	var shown: bool = qb.wait_button.visible and qb.wait_note.visible and qb.wait_status.visible
	var grey: bool = qb.wait_button.disabled and qb.wait_status.text == "大家都醒着" and qb.wait_button.text == "等到天亮（辰时 08:00）" \
		and qb.wait_note.text == "跳过去后，今天没做完的委托会作废。"
	var above: bool = qb.wait_note.get_global_rect().end.y <= qb.wait_button.get_global_rect().position.y + 0.5 \
		and qb.wait_button.get_global_rect().end.y <= qb.keys_label.get_global_rect().position.y + 0.5 \
		and qb.list_box.get_global_rect().end.y <= qb.wait_note.get_global_rect().position.y + 0.5
	await r.tap(KEY_ENTER)
	await r.frames(3)
	var no_wait: bool = sch.waits == 0 and qb.is_open
	await close_board()
	r.check(opened and shown and grey and above and no_wait,
		"schedule AC3: by day the 任务面板 shows the note line, the grey '等到天亮（辰时 08:00）' and '大家都醒着' at the bottom (above the keys, under the list); Enter does not skip",
		str([opened, shown, grey, above, no_wait]))
	await clock_settled(18.0)
	await open_board()
	var lit: bool = not qb.wait_button.disabled and qb.wait_status.text == "Enter"
	await close_board()
	await clock_settled(7.5)
	await open_board()
	var lit_early: bool = not qb.wait_button.disabled
	await close_board()
	r.check(lit and lit_early, "schedule AC3: lit as soon as somebody is asleep (18:00 老周; 07:30 still)", str([lit, lit_early]))


func test_button_night() -> void:
	await game(1)
	await clock_settled(22.0)
	var d0: int = g.daynight.day_index(0)
	var pos := p().global_position
	await open_board()
	await r.tap(KEY_ENTER)
	var closed := not qb.is_open and sch.waiting
	# T and Esc in the dark do nothing
	await r.frames(50)
	await r.tap(KEY_T)
	await r.tap(KEY_ESCAPE)
	var esc_closed: bool = not g.pause_menu.is_open
	var night := await watch_night()
	var dn: DayNight = g.daynight
	await r.frames(40)
	var all_back := TABLE.keys().all(func(id): return not sch.absent(id) and npc(id).visible)
	var ok_clock := dn.hour == 8.0 and dn.day_index(0) == d0 + 1 and is_equal_approx(fposmod(dn.total_hours, 24.0), 8.0)
	report["night"] = night
	r.check(closed and esc_closed and float(night["max_alpha"]) >= 0.999 and night["label_seen"] and String(night["label_text"]) == "一夜过去……"
		and sch.night_black_frames >= 88 and sch.night_black_frames <= 92 and ok_clock and all_back and p().global_position == pos and not g.combat.story_hold and p().input_enabled,
		"schedule AC3: 22:00 + Enter -> the board closes, the screen goes black with '一夜过去……' (~1.5 s), the clock is the next day's 08:00 exactly, everybody is back, 小兔 stays where he was; T / Esc in the dark do nothing",
		str([closed, esc_closed, night, sch.night_black_frames, dn.hour, dn.day_index(0) - d0, all_back, p().global_position - pos]))
	var before := p().global_position
	await r.push(Vector2.RIGHT, 0.3)
	r.check(p().global_position.x > before.x + 4.0, "schedule AC3: after the night he walks again")
	# 03:00 -> the same day's 08:00
	await clock_settled(3.0)
	var d1: int = dn.day_index(0)
	await open_board()
	await r.tap(KEY_ENTER)
	await watch_night()
	r.check(dn.hour == 8.0 and dn.day_index(0) == d1, "schedule AC3: from 03:00 it is the same day's 08:00", "%f %d" % [dn.hour, dn.day_index(0) - d1])


func test_button_click() -> void:
	await game()
	await clock_settled(20.0)
	await open_board()
	await click(screen_pos(qb.wait_button))
	var started := sch.waiting and not qb.is_open
	await watch_night()
	r.check(started and sch.waits == 1 and g.daynight.hour == 8.0, "schedule AC3: a mouse click on the lit button does the same", str([started, sch.waits]))
	await clock_settled(11.0)
	await open_board()
	await click(screen_pos(qb.wait_button))
	await r.frames(5)
	r.check(sch.waits == 1 and qb.is_open and not sch.waiting, "schedule AC3: a click on the grey button does nothing")
	await close_board()


## The button's night = pressing T hour by hour: the same coins, stall days, upkeep, debt, bounty, 委托 draws / expiry, toasts.
func observables() -> Dictionary:
	var dc: Disciple = s3.disciple
	var cm: Commission = jh.com
	var b: Bounty = jh.bounty
	return {"hour": g.daynight.hour, "total": g.daynight.total_hours, "coins": smp.coins, "paid_day": smp.paid_day,
		"incomes": smp.incomes, "tick_day": dc.tick_day, "upkeep_days": dc.upkeep_days, "upkeep_paid": dc.upkeep_paid, "debt": dc.debt,
		"job": dc.job, "com_day": cm.day, "offers": str(cm.offers), "expired": cm.expired, "draws": cm.draws, "com_total": cm.total,
		"bounty_offer": str(b.offer()), "ready_day": b.ready_day, "jh_toasts": jh.toasts.duplicate(), "s3_toasts": s3.toasts.duplicate(), "smp_toasts": smp.toasts.duplicate(),
		"day_no": s3.day_number(), "absent": TABLE.keys().filter(func(id): return sch.absent(id)), "fame": s3.value("fame"),
		"estate": s3.value("estate")}


## A game restored from `state` (继续游戏's path: SaveGame.pending -> main._ready).
func restored(state: Dictionary) -> void:
	await ss._free_game()
	SaveGame.pending = state.duplicate(true)
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	r.current_scene = m
	ss.use_game(m)
	m.daynight.running = false
	await r.frames(4)
	bind()


func by_button() -> Dictionary:
	await open_board()
	await r.tap(KEY_ENTER)
	await watch_night()
	await r.frames(10)
	return observables()


func by_t(rest: float) -> Dictionary:
	var dn: DayNight = g.daynight
	var to := sch.hours_to_morning()
	var n := int(floor(to - rest + 0.0001))
	for i in n:
		await r.tap(KEY_T)
		await r.frames(2)
	if rest > 0.0:
		dn.advance_hours(rest)
	await r.frames(10)
	return observables()


## One night from `start` o'clock of the current game, twice from the same saved state: by the button and by T.
func compare_night(start: float, label: String, bad: Array, runs: Dictionary) -> void:
	await clock(start)
	var st0: Dictionary = SaveGame.roundtrip(SaveGame.capture(g))
	await restored(st0)
	var before := observables()
	var a := await by_button()
	await restored(st0)
	var rest := fposmod(sch.wait_hour() - g.daynight.hour, 1.0)
	var b := await by_t(rest)
	runs[label] = [a, b, before]
	for k in a:
		if str(a[k]) != str(b[k]):
			bad.append("%s %s: button %s / T %s" % [label, k, a[k], b[k]])
	# the game goes on from the state before this night (the next start is later on the same game)
	await restored(st0)
	g.daynight.running = false
	await r.frames(2)


func test_same_as_t() -> void:
	# the starting point: 师弟 helping in the kitchen (stall 25 from his job day), day 1
	await t3.joined_game(true, 9.0)
	bind()
	g.daynight.running = false
	smp.coins = 40
	smp._refresh_coins()
	var bad := []
	var runs := {}
	# day 1 21:00 -> day 2 08:00: the first 悬赏 is posted, the day's first 委托 are drawn
	await compare_night(21.0, "day1 21:00", bad, runs)
	# day 2 with a 委托 taken and not done
	await s4.day_with("jade", true)
	var took: bool = await s4.accept_commission("jade")
	for start in [21.0, 3.0, 21.5]:
		await compare_night(start, "day2+ %05.2f" % start, bad, runs)
	var d1: Array = runs["day1 21:00"]
	var posted: bool = String(d1[2]["bounty_offer"]).replace(" ", "") == "{}" and String(d1[0]["bounty_offer"]).replace(" ", "") != "{}" \
		and int(d1[0]["draws"]) >= 1
	var a21: Dictionary = runs["day2+ 21.00"][0]
	var happened: bool = int(a21["incomes"]) >= 1 and int(a21["upkeep_days"]) >= 1 and int(a21["expired"]) == 1 and int(a21["draws"]) >= 1 \
		and float(a21["hour"]) == 8.0 and int(a21["coins"]) != int(runs["day2+ 21.00"][2]["coins"])
	report["same_as_t"] = runs.keys()
	r.check(took and posted and happened, "schedule AC3: these nights really have the daily events (the first 悬赏 posted; stall income, upkeep, the taken 委托 void at 24:00, the new draw at 08:00)",
		str([took, posted, d1[2]["bounty_offer"], d1[0]["bounty_offer"], a21]))
	r.check(bad.is_empty(), "schedule AC3: 等到天亮 (day 1 21:00; day 2 21:00, 03:00, 21:30) ends exactly like pressing T hour by hour: same clock, coins, stall days, upkeep / debt, 悬赏, 委托 (void, drawn, offers), toasts, who is asleep",
		str(bad.slice(0, 6)))


# ================================================================== AC4 saves
func test_save_load() -> void:
	await game()
	await clock_settled(23.0)
	var ok_save: bool = smp.save_now("schedule_test")
	await s4.reload_game()
	bind()
	await r.frames(2)
	var gone := TABLE.keys().all(func(id): return sch.absent(id) and not npc(id).visible)
	var instant: bool = not sch.changes.is_empty() and sch.changes.all(func(c): return bool(c["instant"]))
	var no_ghost := sch._ghosts.is_empty() and sch.bubble_texts().is_empty()
	r.check(ok_save and g.daynight.hour > 22.9 and gone and instant and no_ghost and sch.bed_shown(),
		"schedule AC4: a save made at 23:00 loads with everybody gone at once (no fades, no '呼……'), 师兄 in his bed",
		str([ok_save, g.daynight.hour, gone, instant, no_ghost]))
	await clock_settled(10.0)
	r.check(TABLE.keys().all(func(id): return npc(id).visible), "schedule AC4: and the loaded game's morning brings them back")


# ================================================================== AC6 fits on the screen (zh and en)
func test_layout() -> void:
	var lang0 := Lang.current()
	await game()
	var bad := []
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await clock_settled(22.0)
		var view := vp()
		# the prompt over the stool (the highest seat) and its line
		var stool: Dictionary = st.seat("kitchen_stool")
		await seat_spot(stool)
		await r.frames(2)
		if not view.encloses(g.hud.prompt.get_global_rect()):
			bad.append("%s prompt %s" % [lang, g.hud.prompt.get_global_rect()])
		st.said.clear()
		await r.tap(KEY_E)
		await r.frames(3)
		if not (g.hud.bubble.visible and view.encloses(g.hud.bubble.get_global_rect())):
			bad.append("%s seat line %s" % [lang, g.hud.bubble.get_global_rect()])
		await r.tap(KEY_E)
		await r.frames(200)
		# the dream line by the bed
		await ss.stand_near(sch.bed_point())
		await r.tap(KEY_E)
		await r.frames(3)
		if not (g.hud.bubble.visible and view.encloses(g.hud.bubble.get_global_rect())):
			bad.append("%s dream %s" % [lang, g.hud.bubble.get_global_rect()])
		if not view.encloses(g.hud.prompt.get_global_rect()) and g.hud.prompt.visible:
			bad.append("%s dream prompt" % lang)
		if g.hud.prompt.visible and g.hud.bubble.get_global_rect().intersects(g.hud.prompt.get_global_rect()):
			bad.append("%s dream line over its prompt" % lang)
		await r.frames(200)
		# the board's footer: inside the panel, nothing cut
		for h in [22.0, 10.0]:
			await clock_settled(h)
			await open_board()
			await r.frames(2)
			var pr: Rect2 = qb.panel.get_global_rect()
			for c in [qb.wait_note, qb.wait_button, qb.wait_status]:
				var cr: Rect2 = c.get_global_rect()
				if not pr.grow(0.5).encloses(cr):
					bad.append("%s %02d %s outside %s" % [lang, h, c.text, cr])
				var need: float = c.get_theme_font("font").get_string_size(Lang.t(c.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
					c.get_theme_font_size("font_size")).x
				if need > cr.size.x + 0.5:
					bad.append("%s %02d '%s' cut (%.0f > %.0f)" % [lang, h, Lang.t(c.text), need, cr.size.x])
			if qb.wait_status.get_global_rect().intersects(qb.wait_button.get_global_rect()):
				bad.append("%s status over the button" % lang)
			await close_board()
		# the night caption
		var fl: Label = sch.fade_label
		var w: float = fl.get_theme_font("font").get_string_size(Lang.t(fl.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
			fl.get_theme_font_size("font_size")).x
		if w > view.size.x - 8.0:
			bad.append("%s night caption %.0f" % [lang, w])
	Lang.set_lang(lang0)
	await r.frames(2)
	r.check(bad.is_empty(), "schedule AC6: in Chinese and in English the seat prompt / line, the dream line, the board's button / note / status and '一夜过去……' stay on the screen and nothing is cut",
		str(bad.slice(0, 8)))


# ================================================================== F1: 委托 whose people are asleep (客户 2026-10-27)
## The board's 看委托 page with real keys (E at the board, 2). Returns {text, options, off} of that page; it stays open.
func commission_page() -> Dictionary:
	await r.teleport(jh.board_point)
	await r.tap(KEY_E)
	for i in 300:
		if dlg.choosing:
			break
		if dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.tap(KEY_2)
	for i in 300:
		if dlg.choosing and jh.menus.size() > 0 and jh.menus[-1] == "commission" and not dlg.is_typing():
			break
		await r.frames(2)
	await r.frames(3)
	return {"text": dlg.full_text, "options": dlg.choice_options.duplicate(), "off": dlg.choice_disabled.duplicate()}


func leave_page() -> void:
	for i in 300:
		if not story.busy:
			break
		if dlg.choosing:
			await r.tap(KEY_1 + dlg.choice_options.size() - 1)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.frames(3)


## The option of today's offer of kind k on the page: [index, text, greyed] or [] .
func offer_option(page: Dictionary, k: String) -> Array:
	var i: int = s4.offer_index(k)
	if i < 0:
		return []
	return [i, String(page["options"][i]), bool(page["off"][i])]


## A seed whose draw for calendar day d has both 送馒头 and 送信.
func seed_both(d: int) -> int:
	for sd in range(1, 4000):
		jh.seed = sd
		var kinds: Array = jh.com.draw(d).map(func(o): return String(o["kind"]))
		if "bun" in kinds and "letter" in kinds:
			return sd
	return -1


func test_commission_grey() -> void:
	await game()
	story.flags["repair_kitchen"] = true
	smp.apply_repair_visuals("kitchen")       # 送馒头 needs the kitchen
	var next_day: int = jh.cal_day() + 1
	jh.seed = seed_both(next_day)
	await t3.advance_to(8.0)
	var cm: Commission = jh.com
	var kinds: Array = cm.offers.map(func(o): return String(o["kind"]))
	# 18:30: both can be taken
	await clock(18.5)
	var p1 := await commission_page()
	var open_bun: Array = offer_option(p1, "bun")
	var open_letter: Array = offer_option(p1, "letter")
	await leave_page()
	r.check(kinds.has("bun") and kinds.has("letter") and not open_bun[2] and not open_letter[2] and String(open_bun[1]).ends_with("：接下"),
		"schedule F1: at 18:30 送馒头 and 送信 can be taken as before", str([kinds, open_bun, open_letter]))
	# 19:30: 茶摊老板 is asleep -> both grey with the note; the key and the mouse do nothing
	await clock(19.5)
	var p2 := await commission_page()
	var g_bun: Array = offer_option(p2, "bun")
	var g_letter: Array = offer_option(p2, "letter")
	var note_ok: bool = String(p2["text"]).count("对方已睡，明早再来") == 2
	var opt_ok: bool = String(g_bun[1]) == "送馒头：对方已睡，明早再来" or String(g_bun[1]).ends_with("：对方已睡，明早再来")
	var menus0 := jh.menus.size()
	await r.tap(KEY_1 + int(g_bun[0]))
	await r.frames(4)
	var key_nothing: bool = dlg.choosing and jh.menus.size() == menus0 and String(cm.offers[g_bun[0]]["state"]) == "open"
	await click(screen_pos(dlg.choice_labels[int(g_letter[0])]))
	await r.frames(4)
	var click_nothing: bool = dlg.choosing and jh.menus.size() == menus0 and String(cm.offers[g_letter[0]]["state"]) == "open"
	var direct := cm.accept(int(g_bun[0])) == "" and String(cm.offers[g_bun[0]]["state"]) == "open"
	await leave_page()
	r.check(g_bun[2] and g_letter[2] and note_ok and opt_ok, "schedule F1: after 19:00 (茶摊老板 asleep) 送馒头 and 送信 are grey on the board with '对方已睡，明早再来'",
		str([g_bun, g_letter, note_ok]))
	r.check(key_nothing and click_nothing and direct, "schedule F1: the grey offer cannot be taken - its key and a mouse click do nothing", str([key_nothing, click_nothing, direct]))
	# 22:30: 老伯 is asleep too - 送信 stays grey
	await clock(22.5)
	var p3 := await commission_page()
	var g3: Array = offer_option(p3, "letter")
	await leave_page()
	r.check(g3[2] and sch.commission_asleep("letter") and sch.asleep_at(sch.person("dog"), g.daynight.hour),
		"schedule F1: after 22:00 (老伯 asleep as well) 送信 is still grey", str(g3))
	# a 委托 taken before 19:00 is not touched: next day, take 送信 at 18:00, at 19:30 it is still 进行中 (放弃 only)
	jh.seed = seed_both(jh.cal_day() + 1)
	await t3.advance_to(8.0)
	var woke := await commission_page()
	var w_bun: Array = offer_option(woke, "bun")
	await leave_page()
	r.check(not w_bun.is_empty() and not w_bun[2], "schedule F1: the next morning (茶摊老板 up at 07:00) the day's 送馒头 can be taken again", str(w_bun))
	await clock(18.0)
	var took: bool = await s4.accept_commission("letter")
	await clock(19.5)
	var p4 := await commission_page()
	var t4: Array = offer_option(p4, "letter")
	await leave_page()
	var o4: Dictionary = cm.find_taken("letter")
	r.check(took and not o4.is_empty() and not t4[2] and String(t4[1]).ends_with("：放弃") and not ("对方已睡" in String(t4[1])),
		"schedule F1: a 送信 taken before 19:00 is not changed at 19:30 (still taken, 放弃 offered, not grey)", str([took, t4]))
	# the note fits: Chinese and English, the page's text and every option inside the screen / the options panel
	var lang0 := Lang.current()
	var bad := []
	await t3.advance_to(8.0)
	jh.seed = seed_both(jh.cal_day() + 1)
	await t3.advance_to(8.0)
	await clock(20.0)
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await r.frames(2)
		var pg := await commission_page()
		var view := vp()
		var panel: Rect2 = dlg.choice_panel.get_global_rect()
		if not view.encloses(panel):
			bad.append("%s panel %s" % [lang, panel])
		for i in pg["options"].size():
			var l: Label = dlg.choice_labels[i]
			var need: float = l.get_theme_font("font").get_string_size(Lang.t(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
			if not panel.grow(0.5).encloses(l.get_global_rect()) or need > l.size.x + 0.5:
				bad.append("%s option %d '%s' %.0f/%.0f" % [lang, i, Lang.t(l.text), need, l.size.x])
		var box: Rect2 = dlg.box.get_global_rect() if dlg.get("box") != null else view
		if not view.encloses(box):
			bad.append("%s box %s" % [lang, box])
		if lang == "en" and ("对方已睡" in Lang.t(String(pg["text"])) or Lang.translation().has_cjk(Lang.t(String(pg["options"][0])))):
			bad.append("en untranslated")
		await leave_page()
	Lang.set_lang(lang0)
	await r.frames(2)
	r.check(bad.is_empty(), "schedule F1: in Chinese and English the grey offers' text and the note stay inside the board's page and options", str(bad))


# ================================================================== F2: the prompt and the dream line keep off his face
func test_fox_prompt_face() -> void:
	await game()
	await clock_settled(23.0)
	var bp: Vector2 = sch.bed_point()
	await ss.stand_near(bp)
	await r.frames(3)
	var ct: Transform2D = g.get_viewport().get_canvas_transform()
	var top_left: Vector2 = sch.bed_sprite.global_position + sch.bed_sprite.offset
	var face := Rect2(ct * (top_left + Vector2(14, 2)), (ct * (top_left + Vector2(34, 28))) - (ct * (top_left + Vector2(14, 2))))
	var pr: Rect2 = g.hud.prompt.get_global_rect()
	var prompt_ok: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 查看" and not pr.intersects(face)
	await r.tap(KEY_E)
	await r.frames(3)
	var br: Rect2 = g.hud.bubble.get_global_rect()
	var bubble_ok: bool = g.hud.bubble.visible and not br.intersects(face) and not br.intersects(g.hud.prompt.get_global_rect())
	r.check(prompt_ok and bubble_ok, "schedule F2: by 师兄's bed at night the 按 E 查看 prompt sits on the bed's lower edge and the dream line just above it - neither covers his face",
		str([face, pr, br]))
	await r.frames(200)


# ================================================================== R1: "呼……" only where 小兔 can see the person go
func test_bubble_seen() -> void:
	await game()
	await clock_settled(21.5)
	# indoors (the dorm): 22:00 sends 师兄 and 老伯 (outdoors) to bed - no bubble anywhere
	await ss.stand_near(sch.bed_point())
	await r.frames(3)
	await clock(22.0, 4)
	var gone := sch.absent("fox") and sch.absent("dog")
	var none_in: bool = sch.bubble_texts().is_empty() and not g.hud.bubble.visible
	r.check(gone and none_in, "schedule R1: 小兔 in the dorm when 22:00 comes - 师兄 and 老伯 go to bed outside without any '呼……' (no bubble clamped to the screen edge)",
		str([gone, sch.bubble_texts(), g.hud.bubble.visible]))
	# outdoors, 村民 on screen: 19:00 -> his '呼……' over his head; 老周 (far off screen) has none
	await clock_settled(18.5)
	var duck := npc("duck")
	await ss.stand_near(duck.global_position)
	await r.frames(3)
	await clock(19.0, 3)
	var b: Dictionary = sch.bubble()
	var whos: Array = sch._bubbles.map(func(x): return String(x["who"]))
	var shown: bool = String(b.get("text", "")) == "呼……" and whos.has("duck") and g.hud.bubble.visible and g.hud.bubble_label.text == "呼……"
	r.check(shown, "schedule R1: outdoors with 村民 on screen, 19:00 -> '呼……' over him as before", str([b, whos]))
	await clock_settled(17.5)
	await clock(18.0, 3)
	var mouse_far := not sch._bubbles.any(func(x): return String(x["who"]) == "mouse") and sch.absent("mouse")
	r.check(mouse_far, "schedule R1: outdoors but 老周 off screen (宿舍门口, far away) -> he goes to bed without a bubble", str(sch.bubble_texts()))


## The 委托 detail page opened at 18:59, 接下 pressed after 19:00: it says why nothing happened.
func test_detail_late() -> void:
	await game()
	story.flags["repair_kitchen"] = true
	smp.apply_repair_visuals("kitchen")
	jh.seed = seed_both(jh.cal_day() + 1)
	await t3.advance_to(8.0)
	await clock(18.98)
	await commission_page()
	var i: int = s4.offer_index("bun")
	await r.tap(KEY_1 + i)          # -> the detail page with 接下
	for k in 200:
		if dlg.choosing and jh.menus[-1] == "detail" and not dlg.is_typing():
			break
		await r.frames(2)
	var on_detail: bool = jh.menus[-1] == "detail"
	await clock(19.2, 2)
	await r.tap(KEY_1)              # 接下
	var said := false
	for k in 200:
		if dlg.active and dlg.full_text == "对方已睡，明早再来":
			said = true
			break
		await r.frames(2)
	var still_open: bool = String(jh.com.offers[i]["state"]) == "open"
	await leave_page()
	r.check(on_detail and said and still_open, "schedule R1: the detail page opened at 18:59, 接下 pressed after 19:00 -> '对方已睡，明早再来' (and nothing is taken)",
		str([on_detail, said, still_open]))
