extends RefCounted
## 序章 v1 checks (tests/run_tests.gd runs this suite last; quick loop: -- --only-story). Real key events and real
## physics in games started the real way (title screen -> 开始游戏) or built like a direct launch (scenes/main.tscn).
##   AC1 full playthrough with the movement keys: title -> steps 1..9 -> 序章 · 完 -> 回到启动画面 -> title; objective
##       text + minimap star checked at every step (fights: the combat suite's dodge-and-counter bot)
##   AC2 gating: 厨娘 before 师父, the "之后" lines, NPC prompts per stage, bandits absent before step 5 is done,
##       knocked out at step 6 -> respawn, still step 6, both bandits back; driven off -> gone for good
##   AC3 spar: win and lose branches (different lines), both go on; rematch offered afterwards
##   AC4 puzzle: S8-进林 once; stele re-readable; wrong order resets; hint once after 3 errors; right order lights the
##       stones + wind towards the next one; the clump blocks before and lets the player through after (collision)
##   AC5 dialogue: portrait + name per speaker, typewriter + skip, choices by 1/2 and by ↓ + E, frozen player
##       (no walking, no attack) and frozen enemies (no damage), Esc page during a conversation, optional lines, bubbles once
##   AC6 门派簿: opened by the ending, entries for both spar results, B re-opens it (and is on the Esc page)
##   AC7 script <-> data verbatim (both directions), no missing glyph, example objectives gone
## 室内图进游戏 v1: the approved script is now v3 (docs/design/区域1-剧情与对话-v3.md): the opening in the dorm room, the
## note (S1-字条, kind 字条), 师父 / 厨娘 inside the hall / kitchen, the room optional lines (S10-*). The playthrough walks
## through the doors (tests/nav.gd) and checks the star on the room door while the target is inside and she is not.

## 打磨 v1: the approved script is v5 (docs/design/区域1-剧情与对话-v5.md): the bucket fills and overflows, she wakes,
## takes the rag in the corner, wipes the puddle (3 x E) and pours the bucket out, then the note; the star aims at the
## target itself / a room's door / her own doorway (Interiors.minimap_target, round player-centred minimap).
const SCRIPT_MD := "docs/design/区域1-剧情与对话-v5.md"
const SPEAKERS := ["旁白", "提示", "碑文", "画面", "字条", "小兔", "师兄", "师父", "厨娘", "老伯", "茶摊老板", "村民", "山贼·狼", "山贼·野猪"]

var r
var g: Node             # the game under test
var story: Story
var dlg: Dialogue
var cs                  # combat suite (bots) bound to the current game
var sdata: Dictionary
var objectives_raw: Dictionary
var nav


func _init(runner) -> void:
	r = runner


func run() -> void:
	r.paused = false
	r.release_all()
	sdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	objectives_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/objectives.json"))
	test_script_vs_data()
	test_glyphs_and_examples()
	await test_full_playthrough()
	await test_dialogue_system()
	await test_gating_and_optional()
	await test_spar_lose_branch_and_book()
	await test_bandits()
	await test_puzzle()
	await test_bubbles_and_book_key()
	_free_game()


# ================================================================== helpers
func use_game(m: Node) -> void:
	g = m
	story = m.story
	dlg = story.dialogue
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0       # rebuild the walk grid for this game when needed
	cs = load("res://tests/combat_suite.gd").new(r)
	nav = load("res://tests/nav.gd").new(r, m)


func _free_game() -> void:
	if g != null and is_instance_valid(g):
		if g.is_inside_tree():
			g.get_parent().remove_child(g)
		g.queue_free()
	g = null
	r.paused = false
	await r.process_frame


## A game built like a direct launch (scenes/main.tscn), the opening conversation on screen.
func new_game() -> void:
	await _free_game()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	use_game(m)
	m.daynight.running = false
	await r.frames(3)


func p() -> Player:
	return g.player


func npc(id: String) -> Npc:
	return story._npc(id)


## Presses E / Enter / Space until the running conversation is over (1 on a choice). Returns the number of presses.
func finish_scene(choice_key := KEY_1, limit := 400) -> int:
	var n := 0
	while story.busy and n < limit:
		if dlg.choosing:
			await r.tap(choice_key)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(2)
	return n


func scenes_since(k: int) -> Array:
	return story.played.slice(k)


## Stands next to `pos` on free ground (teleport) - for the branch tests; the playthrough walks.
func stand_near(pos: Vector2, offs := [Vector2(0, 26), Vector2(-26, 0), Vector2(26, 0), Vector2(0, -26), Vector2(0, 34)]) -> bool:
	for o in offs:
		if r.is_free(pos + o):
			await r.teleport(pos + o)
			return true
	var f: Vector2 = r.find_free_near(pos + Vector2(0, 20), 24)
	if f == Vector2.INF:
		return false
	await r.teleport(f)
	return true


## Walks with the movement keys to `target` (through doors when it is in / out of a room: tests/nav.gd); stops early
## when a conversation starts. Returns "arrived" | "scene" | "stuck".
func walk_to(target: Vector2, limit := 90.0) -> String:
	return await nav.walk_to(target, limit)


## Free spot next to an NPC to walk to (south side first).
func talk_spot(n: Node2D) -> Vector2:
	for o in [Vector2(0, 26), Vector2(-26, 0), Vector2(26, 0), Vector2(0, -26)]:
		if r.is_free(n.global_position + o):
			return n.global_position + o
	return r.find_free_near(n.global_position + Vector2(0, 26), 24)


## What the minimap star must aim at for a target at world point `w` (打磨 v1): the point itself when she is in the same
## place (outdoors / the same room), the room's outdoor door when the target is inside and she is outdoors, her own
## doorway (on the rim) when she is indoors and the target is not in her room.
func star_expect(w: Vector2) -> Vector2:
	var it: Interiors = g.interiors
	var tr := it.room_at(w)
	var pr := it.room_at(p().global_position)
	if pr == "":
		return w if tr == "" else it.door_point(tr)
	if tr == pr:
		return w
	return it.doorway_point(pr)


## The star aims at `expect` (a target given as the real world point; star_expect applies the door rules) and sits on
## the minimap where its geometry says: at its place when in range, else on the rim at the same angle.
func star_ok(expect: Variant) -> bool:
	var mm: Minimap = g.hud.minimap
	if expect == null:
		return not mm.star_active
	var want := star_expect(expect)
	if not mm.star_active or mm.star_target_world.distance_to(want) >= 1.0:
		return false
	var off := (want - p().global_position) * mm.scale_now()
	var c := Vector2(mm.radius, mm.radius)
	if mm.star_on_rim:
		return absf((mm.star_marker - c).length() - (mm.radius - mm.star_inset)) < 0.5 \
			and (off.length() < 0.001 or absf(angle_difference(mm.star_angle(), off.angle())) < 0.02)
	return mm.star_marker.distance_to(c + off) < 0.5


func objective_ok(stage: int) -> bool:
	# v4: stage 0 = 擦干地上的水 (entry 0) then 看看桌上的字条 (entry 1); stage N >= 1 = entry N + 1
	var idx := (1 if story.flags.get("floor_wiped", false) else 0) if stage == 0 else stage + 1
	var st: Dictionary = objectives_raw["steps"][idx]
	var want := String(st["text"]) if st.get("plain", false) else Hud.OBJECTIVE_PREFIX + String(st["text"])
	return g.hud.objective_label.text == want and g.hud.objective.visible


func check_step(stage: int, star: Variant, label: String) -> void:
	await r.frames(2)
	r.check(story.stage == stage and objective_ok(stage) and star_ok(star),
		"story AC1 step %d: objective '%s' and the minimap star (%s)" % [stage, g.hud.objective_label.text, label],
		"stage %d, star %s at %s" % [story.stage, g.hud.minimap.star_active, g.hud.minimap.star_marker])


## Runs the bandit fight with the counter bot until they are driven off (knock-outs: respawn, walk back, again).
func fight_bandits(limit := 240.0) -> bool:
	var c: Combat = g.combat
	var t := 0.0
	cs._dodged_for = {}
	while not c.bandits_cleared and t < limit:
		if story.busy:
			await finish_scene()
			continue
		if c.player_dead:
			await r.frames(5)
			t += 5.0 / 60.0
			continue
		if c.engaged_enemies().is_empty():
			# walk back to them (after a respawn): the zone puts them on the player again
			var target: Vector2 = c.bandits[0].home if c.bandits[0].visible else c.bandits[1].home
			r.hold_dir((target - p().global_position).normalized())
			await r.physics_frame
			t += 1.0 / 60.0
			continue
		cs.bot_step("counter")
		await r.physics_frame
		t += 1.0 / 60.0
	cs._release()
	await r.frames(3)
	return c.bandits_cleared


func _skip_line() -> void:
	for i in 2:
		dlg._guard = 0.0
		dlg.advance()


# ================================================================== AC7 script <-> data
func _script_lines() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../" + SCRIPT_MD).simplify_path()
	var text := FileAccess.get_file_as_string(path)
	var lines := []
	var choices := []
	var quoted := []
	var goals := []
	var started := false
	# "水井——小兔：…" (v2) and "S10-书架：小兔：…" (v3 section 10) carry a label before the speaker
	var rx_line := RegEx.create_from_string("^(?:\\S+?——|S\\d+-[^：]+：)?(" + "|".join(SPEAKERS) + ")：(.+)$")
	var rx_choice := RegEx.create_from_string("→ 选项 [AB]「(.+)」")
	var rx_quoted := RegEx.create_from_string("\"(小兔：[^\"]+)\"")
	for raw in text.split("\n"):
		if raw.begins_with("## 1."):
			started = true
		if raw.begins_with("## 需要你决定") or raw.begins_with("## v3 需要你确认") or raw.begins_with("## v4 需要你确认"):
			break      # the doc's open questions are not game text
		if not started:
			continue
		var s := raw.strip_edges()
		if s.begins_with("- "):
			s = s.substr(2).strip_edges()
		s = s.replace("**", "")
		var mc := rx_choice.search(s)
		if mc:
			choices.append(mc.get_string(1))
			continue
		var mq := rx_quoted.search(s)
		if mq and not rx_line.search(s):
			s = mq.get_string(1)
		var m := rx_line.search(s)
		if m:
			lines.append(m.get_string(1) + "：" + m.get_string(2).strip_edges())
		quoted.append(s)
	# the task table sits above "## 1." - read it separately
	for raw in text.split("\n"):
		if raw.begins_with("## 1."):
			break
		if raw.begins_with("| ") and raw.split("|").size() >= 7 and raw.split("|")[1].strip_edges().is_valid_int():
			for goal in raw.split("|")[5].strip_edges().split(" → "):
				goals.append(goal.strip_edges())
	return {"lines": lines, "choices": choices, "goals": goals, "all": "\n".join(text.split("\n")).replace("**", "")}


func _data_lines(node: Variant, speakers: Dictionary, out: Dictionary) -> void:
	if node is Dictionary:
		if node.has("choice"):
			for o in node["choice"]:
				out["choices"].append(String(o["text"]))
				_data_lines(o.get("then", []), speakers, out)
			return
		if node.has("text") and (node.has("who") or node.has("kind")):
			var who := String(speakers.get(node["who"], {}).get("name", "?")) if node.has("who") else String(node["kind"])
			out["lines"].append(who + "：" + String(node["text"]))
		for k in node:
			if k != "text":
				_data_lines(node[k], speakers, out)
	elif node is Array:
		for x in node:
			_data_lines(x, speakers, out)


func _multiset_diff(a: Array, b: Array) -> Array:
	var left := b.duplicate()
	var out := []
	for x in a:
		var i := left.find(x)
		if i < 0:
			out.append(x)
		else:
			left.remove_at(i)
	return out


func test_script_vs_data() -> void:
	var sc := _script_lines()
	var out := {"lines": [], "choices": []}
	_data_lines({"scenes": sdata["scenes"], "bubbles": sdata["bubbles"]}, sdata["speakers"], out)
	var missing := _multiset_diff(sc["lines"], out["lines"])      # in the script, not in the game data
	var extra := _multiset_diff(out["lines"], sc["lines"])        # in the game data, not in the script
	r.check(sc["lines"].size() >= 100 and missing.is_empty() and extra.is_empty(),
		"story AC7: every line of the approved script is in data/story.json word for word, and nothing else (%d lines, both directions)" % sc["lines"].size(),
		"missing %s; extra %s" % [missing, extra])
	var cm := _multiset_diff(sc["choices"], out["choices"])
	var ce := _multiset_diff(out["choices"], sc["choices"])
	r.check(sc["choices"].size() == 6 and cm.is_empty() and ce.is_empty(), "story AC7: the 6 choices are the script's word for word",
		"missing %s extra %s" % [cm, ce])
	# 门派簿 texts and objective texts come from the script too
	var book: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sect_book.json"))
	var all: String = sc["all"]
	var book_bad := []
	for tr in book["tracks"]:
		if not ("%s：" % tr["name"]) in all:
			book_bad.append(tr["name"])
		for e in tr["entries"]:
			if not ("\"%s\"" % e["text"]) in all:
				book_bad.append(e["text"])
	if not ("下方提示：" + String(book["hint"])) in all:
		book_bad.append(book["hint"])
	r.check(book_bad.is_empty(), "story AC7: 门派簿 names, entries and hint are the script's word for word", str(book_bad))
	# v3: the "左上角目标文字" column of the task table, in order (step 1 has two: 看看桌上的字条 → 去练武场找师兄)
	var texts: Array = objectives_raw["steps"].map(func(st): return String(st["text"]))
	r.check(objectives_raw["steps"].size() == 11 and texts == sc["goals"], "story AC7: the 11 objectives are the script table's '左上角目标文字' in order (v4: step 1 has three)",
		"data %s vs script %s" % [texts, sc["goals"]])


func test_glyphs_and_examples() -> void:
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := ""
	for fn in ["res://data/story.json", "res://data/objectives.json", "res://data/sect_book.json"]:
		text += FileAccess.get_file_as_string(fn)
	text += SectBook.FULL + SectBook.EMPTY + SectBook.BULLET + Dialogue.NEXT_MARK + "▶" + PauseMenu.all_text()
	var missing := ""
	for ch in text:
		if ch.unicode_at(0) > 32 and ch != "\n" and not font.has_char(ch.unicode_at(0)) and not ch in missing:
			missing += ch
	r.check(missing == "", "story AC7: every character of the story, objectives and 门派簿 exists in the UI font", "missing: " + missing)
	var raw := FileAccess.get_file_as_string("res://data/objectives.json")
	var hud_src := FileAccess.get_file_as_string("res://scripts/hud.gd")
	r.check(not "示例目标完成" in raw and not "done_text" in raw and not "去正殿找师父" in raw and not "对话之后再做" in hud_src,
		"story AC7: the example objectives, '示例目标完成' and the placeholder bubble are gone")


# ================================================================== AC1 full playthrough (title -> 序章 · 完 -> title)
func test_full_playthrough() -> void:
	SaveGame.erase()    # 两条路小样 v1: a first-time player (no save, so 新游戏 starts at once without the overwrite question)
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	r.root.add_child(title)
	r.current_scene = title
	await r.frames(3)
	title.select(title.index_of("start"))     # 新游戏 (was 开始游戏 at position 0; 继续游戏 is above it now)
	await r.tap(KEY_ENTER)
	var m: Node = null
	for i in 240:
		await r.process_frame
		if r.current_scene != null and is_instance_valid(r.current_scene) and r.current_scene.name == "Main":
			m = r.current_scene
			break
	r.check(m != null, "story AC1: 开始游戏 on the title screen enters the game")
	if m == null:
		return
	use_game(m)
	m.daynight.running = false
	await r.frames(3)
	var it: Interiors = g.interiors
	r.check(story.busy and story.current_scene == "S1-醒来" and dlg.active and dlg.kind == "旁白" and not g.hud.objective.visible
		and not g.hud.minimap.star_active and it.room_at(p().global_position) == "dorm_main" and it.bed_state == "sleeping"
		and not p().sprite.visible and it.bed_sleeping.visible,
		"story AC1 (v3): 开始游戏 -> inside the dorm, asleep in bed, S1-醒来 starts, no objective yet")
	# v4: 旁白 -> the bucket fills up drop by drop (the box steps aside) -> 画面 -> ……哗啦 -> it overflows -> 画面 -> wakes
	for i in 40:     # E until the 旁白 line is done (the title's fade-in may still swallow the first press)
		if not (dlg.active and dlg.kind == "旁白"):
			break
		await r.tap(KEY_E)
	var lv0: float = it.water_level
	var box_hidden := false
	var lv_max := 0.0
	var rising := true
	var last := lv0
	for i in 600:
		if dlg.active and dlg.kind == "画面":
			break
		if not dlg.active:
			box_hidden = true
		if it.water_level < last - 0.0001:
			rising = false
		last = it.water_level
		lv_max = maxf(lv_max, it.water_level)
		await r.physics_frame
	r.check(box_hidden and rising and lv0 <= 0.7 and lv_max >= 0.99 and it.puddle_size == 0.0 and it.bed_state == "sleeping"
		and dlg.full_text == "屋顶漏下的雨水，一滴一滴落进床边的木桶。桶里的水越来越满。",
		"story AC3 (v4 opening): asleep, the leak fills the bucket drop by drop up to the brim (%.2f -> %.2f), then the 画面 line" % [lv0, lv_max],
		"hidden %s rising %s '%s'" % [box_hidden, rising, dlg.full_text])
	for i in 60:
		if dlg.active and dlg.full_text == "……哗啦。" and not dlg.is_typing():
			break
		await r.tap(KEY_E)
	var crash_line := dlg.full_text == "……哗啦。"
	await r.tap(KEY_E)
	var saw_overflow := false
	for i in 600:
		if it.overflowing:
			saw_overflow = true
		if dlg.active and dlg.kind == "画面":
			break
		await r.physics_frame
	r.check(crash_line and saw_overflow and it.puddle_size >= 0.99 and it.bed_state == "sleeping" and dlg.full_text == "木桶满了，水漫出来，在地上淌开一大滩。",
		"story AC3 (v4 opening): '……哗啦。' - the full bucket overflows into a puddle on the floor, then the 画面 line", "puddle %.2f" % it.puddle_size)
	for i in 60:
		if dlg.active and dlg.full_text == "……嗯？什么声音……":
			break
		await r.tap(KEY_E)
	r.check(it.bed_state == "sitting" and p().sprite.visible and it.bed_quilt.visible and not it.bed_sleeping.visible,
		"story AC3 (v4 opening): woken by the splash she sits up as she says '……嗯？什么声音……'")
	await finish_scene()
	var getup: Vector2 = it.getup_world()
	r.check(it.bed_state == "empty" and p().global_position.distance_to(getup) < 1.0 and p().z_index == 0 and r.is_free(p().global_position),
		"story AC3 (v3 opening): she gets out of bed onto free floor", str(p().global_position))
	r.check(g.hud.hint.visible, "story AC5: the key hint shows once the opening conversation is over")
	var rag_pos: Vector2 = story._thing_pos(_inter("rag"))
	var puddle_pos: Vector2 = story._thing_pos(_inter("puddle"))
	var note_pos: Vector2 = story._thing_pos(_inter("note"))
	await check_step(0, rag_pos, "擦干地上的水: on the rag in the corner")
	# --- leaving before wiping is allowed: the objective stays, the star points at the dorm door
	var res := await walk_to(it.exit_spot("dorm_main") + Vector2(0, 16))
	await check_step(0, rag_pos, "outside: on the dorm door")
	r.check(res == "arrived" and it.room_at(p().global_position) == "" and story.stage == 0 and (await _prompt_scene_at("fox")) == "",
		"story AC3 (v4): leaving before wiping keeps 擦干地上的水 (师兄 has nothing to say yet)", res)
	# --- the rag, three wipes, the bucket poured out
	res = await walk_to(rag_pos + Vector2(0, 4))
	var k: int = story.played.size()
	await r.tap(KEY_E)
	await finish_scene()
	r.check(res == "arrived" and scenes_since(k) == ["S1-抹布"] and story.flags.get("has_rag", false) and not it.rag_sprite.visible,
		"story AC3 (v4): E at the rag in the corner picks it up (S1-抹布)", "%s %s" % [res, scenes_since(k)])
	await check_step(0, puddle_pos, "on the puddle")
	res = await walk_to(puddle_pos + Vector2(0, 6))
	for n in 3:
		await r.tap(KEY_E)
		await r.frames(30)
	await finish_scene()
	r.check(res == "arrived" and story.flags.get("floor_wiped", false) and it.puddle_size <= 0.001 and it.pours == 1 and "S1-擦水渍" in story.played,
		"story AC3 (v4): three E at the puddle wipe it up (S1-擦水渍) and the bucket is poured out", res)
	await check_step(0, note_pos, "看看桌上的字条: on the note")
	# --- the note
	res = await walk_to(note_pos + Vector2(0, 8))
	k = story.played.size()
	await r.tap(KEY_E)
	var note_kind := dlg.kind
	await finish_scene()
	r.check(res == "arrived" and scenes_since(k) == ["S1-字条"] and note_kind == "字条" and story.stage == 1,
		"story AC3 (v3): E at the little table reads S1-字条 (字条 style) and moves the story on", "%s %s %s" % [res, scenes_since(k), note_kind])
	await check_step(1, npc("fox").global_position, "on 师兄 (outdoors; from inside: on her doorway, on the rim)")
	# --- 厨娘 before 师父: 任务前, no progress (walk there for real: out of the dorm, into the kitchen)
	res = await walk_to(talk_spot(npc("bear")))
	k = story.played.size()
	await r.tap(KEY_E)
	await finish_scene()
	r.check(res == "arrived" and it.room_at(p().global_position) == "kitchen" and scenes_since(k) == ["S4-厨娘-任务前"] and story.stage == 1,
		"story AC2: talking to 厨娘 (inside the kitchen) before 师父 plays S4-厨娘-任务前 and does not move the story on", "%s %s" % [res, scenes_since(k)])
	# --- step 1 -> 2: 师兄, choice A, spar with the counter bot (win)
	res = await walk_to(talk_spot(npc("fox")))
	k = story.played.size()
	await r.tap(KEY_E)
	await finish_scene(KEY_1)
	var c: Combat = g.combat
	r.check(res == "arrived" and scenes_since(k) == ["S2-师兄-初见"] and c.spar_state == "fighting",
		"story AC3: 师兄 -> S2-师兄-初见 (choice) -> the spar starts at once (no 算了 the first time)", "%s %s" % [scenes_since(k), c.spar_state])
	cs._dodged_for = {}
	var t := 0.0
	while c.spar_state == "fighting" and t < 60.0:
		cs.bot_step("counter")
		await r.physics_frame
		t += 1.0 / 60.0
	cs._release()
	for i in 400:
		if story.busy:
			break
		await r.physics_frame
	k = story.played.size() - 1
	await finish_scene()
	r.check(c.last_spar_win and story.played[k] == "S2-师兄-你赢了" and story.flags.get("spar_won", false),
		"story AC3: winning the spar plays S2-师兄-你赢了", str(story.played.slice(k)))
	await check_step(2, it.door_point("hall"), "on the hall door (师父 is inside)")
	# --- 2 -> 3: 师父 inside the hall
	res = await walk_to(talk_spot(npc("crane")))
	r.check(res == "arrived" and it.room_at(p().global_position) == "hall", "story AC4 (v3): walking into the hall through its door to 师父", res)
	await check_step(2, star_expect(npc("crane").global_position), "inside the hall: in the hall's place on the map")
	await r.tap(KEY_E)
	await finish_scene(KEY_2)
	await check_step(3, it.door_point("kitchen"), "on the kitchen door (厨娘 is inside)")
	# --- 3 -> 4: 厨娘 inside the kitchen
	res = await walk_to(talk_spot(npc("bear")))
	await r.tap(KEY_E)
	await finish_scene()
	await check_step(4, npc("dog").global_position, "on 看门老伯")
	r.check(not c.bandits[0].visible and not c.bandits[1].visible, "story AC2: no bandits on the road before step 5 is done")
	# --- 4 -> 5: 老伯 -> bandits appear
	res = await walk_to(talk_spot(npc("dog")))
	await r.tap(KEY_E)
	await finish_scene()
	await check_step(5, Vector2(1456, 1808), "on 村口")
	r.check(c.bandits.all(func(b): return b.visible and b.state == "idle" and b.collision_layer == 1),
		"story AC2: after 老伯 (step 5) both bandits stand on the road")
	# --- step 6: walk down the road -> intro -> fight
	res = await walk_to(r.tile_center(14, 44))
	r.check(res == "scene" and story.current_scene == "S6-山贼-开战", "story AC2: walking down the road, the bandits' opening lines start by themselves",
		"%s %s" % [res, story.current_scene])
	await finish_scene()
	r.check(c.bandits.all(func(b): return b.engaged), "story AC2: after their lines the bandits attack")
	var won := await fight_bandits()
	for i in 400:
		if story.busy or story.stage == 6:
			break
		await r.physics_frame
	await finish_scene()
	r.check(won and story.stage == 6 and "S6-山贼-胜利" in story.played, "story AC1: driving the bandits off plays S6-山贼-胜利", "deaths %d" % c.deaths)
	await check_step(6, npc("tanuki").global_position, "on 茶摊老板")
	# --- 6 -> 7: 茶摊老板, then the villager
	res = await walk_to(talk_spot(npc("tanuki")))
	await r.tap(KEY_E)
	await finish_scene()
	await check_step(7, story.stele_pos, "on the stele")
	res = await walk_to(talk_spot(npc("duck")))
	await r.tap(KEY_E)
	await finish_scene()
	# --- step 7 -> 8: the grove
	res = await walk_to(story.stele_pos + Vector2(0, 24), 120.0)
	r.check(res == "scene" and story.current_scene == "S8-进林", "story AC4: entering the clearing plays S8-进林 by itself", res)
	await finish_scene()
	res = await walk_to(story.stele_pos + Vector2(0, 24))
	await r.tap(KEY_E)
	await finish_scene()
	for id in ["stone_qing", "stone_moss", "stone_crack"]:
		res = await walk_to(story.stones[id]["pos"] + Vector2(0, 16))
		await r.tap(KEY_E)
		await r.frames(10)
	r.check(story.solved, "story AC4: bowing 青石 -> 苔石 -> 裂石 (walking + E) solves the puzzle", str(story.bows))
	await r.frames(100)
	r.grid_w = 0        # the clump has parted: the walk grid changes
	res = await walk_to(story.stash_pos + Vector2(0, 30))
	r.check(res == "scene" and story.current_scene == "S8-找到瓦片", "story AC4: walking through the parted bamboo to the stash plays S8-找到瓦片", res)
	await finish_scene()
	await check_step(8, it.door_point("hall"), "on the hall door (师父 is inside)")
	# --- 8 -> 9: 师父 inside the hall, ending
	res = await walk_to(talk_spot(npc("crane")), 120.0)
	r.check(res == "arrived" and it.room_at(p().global_position) == "hall", "story AC4 (v3): back inside the hall for the ending", res)
	k = story.played.size()
	await r.tap(KEY_E)
	var book_seen := false
	var book_entries := []
	var end_seen := false
	for i in 600:
		if story.sect_book.is_open:
			book_seen = true
			book_entries = story.sect_book.shown_entries()
			await r.frames(5)
			await r.tap(KEY_E)
		elif story.prologue_end.is_open:
			end_seen = true
			break
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	r.check(book_seen and book_entries == ["打跑山路上的山贼", "解开竹林断碑", "赢了师兄一回", "找回了老周的瓦"],
		"story AC6: the ending opens 门派簿 with 名望 (incl. 赢了师兄一回 after a won spar) and 家业 entries", str(book_entries))
	for i in 200:
		if story.prologue_end.buttons_shown():
			break
		await r.physics_frame
	await check_step(9, null, "no star")
	r.check(end_seen and story.prologue_end.title_label.text == "序章 · 完" and story.prologue_end.buttons[0].visible
		and story.prologue_end.buttons[0].text == "回到启动画面" and story.prologue_end.selected == 0,
		"story AC1: 「序章 · 完」 with the 回到启动画面 button (selected)")
	r._log("      playthrough used %d doors" % nav.doors_used)
	await r.tap(KEY_E)
	var back: Node = null
	for i in 60:
		await r.process_frame
		if r.current_scene != null and is_instance_valid(r.current_scene) and r.current_scene is TitleScreen:
			back = r.current_scene
			break
	r.check(back != null and (not is_instance_valid(g) or not g.is_inside_tree()),
		"story AC1: 回到启动画面 returns to the title screen (the game scene is gone)")
	if back != null:
		back.queue_free()
		await r.process_frame
	g = null


func _inter(id: String) -> Dictionary:
	for it in sdata["interactables"]:
		if it["id"] == id:
			return it
	return {}


# ================================================================== AC5 dialogue system
func test_dialogue_system() -> void:
	await new_game()
	# typewriter + skip
	var t0 := dlg.shown_text().length()
	await r.frames(6)
	var t1 := dlg.shown_text().length()
	r.check(dlg.is_typing() and t1 > t0 and t1 < dlg.full_text.length(), "story AC5: the text types in letter by letter", "%d -> %d of %d" % [t0, t1, dlg.full_text.length()])
	await r.tap(KEY_SPACE)
	var full := not dlg.is_typing() and dlg.shown_text() == dlg.full_text and dlg.active
	var n0 := dlg.lines_shown
	await r.tap(KEY_ENTER)
	# v3: after the 旁白 the drop falls onto her forehead (the box steps aside), then the next line comes
	for i in 200:
		if dlg.active:
			break
		await r.physics_frame
	await r.frames(2)
	r.check(full and dlg.lines_shown == n0 + 1 and dlg.kind == "画面" and p().dash_time_left == 0.0, "story AC5: Space shows the whole line, Enter goes on (Space does not dodge)")
	for i in 60:
		if dlg.kind == "speaker":
			break
		await r.tap(KEY_E)
	# speaker style: portrait + name
	r.check(dlg.kind == "speaker" and dlg.name_label.text == "小兔" and dlg.current_portrait() != null
		and dlg.current_portrait().get_size() == Vector2(64, 64) and dlg.portrait_frame.visible,
		"story AC5: a character line shows the 64x64 portrait and the name 小兔")
	# frozen player: walk keys + J do nothing
	var pos := p().global_position
	r.key(KEY_D, true)
	await r.frames(30)
	r.key(KEY_D, false)
	await r.tap(KEY_J)
	await r.frames(3)
	r.check(p().global_position.distance_to(pos) < 0.5 and p().attack_stage == 0 and p().attacks_started == 0,
		"story AC5: during a conversation the player cannot walk or attack")
	# Esc page during the conversation
	await r.tap(KEY_ESCAPE)
	var paused: bool = g.pause_menu.is_open and r.paused
	await r.tap(KEY_ESCAPE)
	r.check(paused and not r.paused and dlg.active, "story AC5: Esc still opens the help page during a conversation, and back")
	await finish_scene()
	# kinds: 提示 has no portrait
	r.check("S1-醒来" in story.played and not story.busy and p().input_enabled, "story AC5: after the conversation the player can move again")
	# portraits and names for every speaker of the script
	var bad := []
	for id in sdata["speakers"]:
		dlg.say({"who": id, "text": "测试"})
		await r.frames(1)
		if dlg.name_label.text != sdata["speakers"][id]["name"] or dlg.current_portrait() == null or dlg.current_portrait().get_size() != Vector2(64, 64):
			bad.append(id)
		_skip_line()
	for kind in ["旁白", "提示", "碑文", "画面", "字条"]:
		dlg.say({"kind": kind, "text": "测试"})
		await r.frames(1)
		if dlg.portrait_frame.visible or dlg.name_label.text != kind or dlg.box_style.bg_color == Dialogue.KIND_STYLE["speaker"][0]:
			bad.append(kind)
		_skip_line()
	dlg.close()
	r.check(bad.is_empty(), "story AC5: all 9 speakers show their own portrait + 称呼; 旁白 / 提示 / 碑文 / 画面 / 字条 have no portrait and their own look", str(bad))
	# choices: key 2, and ↓ + E (师父 at step 2)
	story.set_stage(2)
	await stand_near(npc("crane").global_position)
	await r.tap(KEY_E)
	while not dlg.choosing:
		await r.tap(KEY_E)
	r.check(dlg.choice_panel.visible and dlg.choice_labels[0].text.contains("师父，以前的门派是什么样的？"), "story AC5: the choice appears with the line before it")
	await r.tap(KEY_DOWN)
	var sel := dlg.choice_index
	await r.tap(KEY_E)
	await r.frames(3)
	r.check(sel == 1 and dlg.last_choice == 1 and dlg.full_text == "嗯。路上小心，最近山路不太平。", "story AC5: ↓ + E picks option B and its answer follows", dlg.full_text)
	await finish_scene()
	story.set_stage(4)
	await stand_near(npc("dog").global_position)
	await r.tap(KEY_E)
	while not dlg.choosing:
		await r.tap(KEY_E)
	await r.tap(KEY_2)
	await r.frames(3)
	r.check(dlg.last_choice == 1 and dlg.full_text == "哈哈，好！那你先把今天的菜买回来。", "story AC5: key 2 picks option B", dlg.full_text)
	await finish_scene()


# ================================================================== AC2 gating, prompts per stage, optional lines
func _prompt_scene_at(id: String) -> String:
	await stand_near(npc(id).global_position)
	await r.frames(2)
	var tg: Dictionary = g.prompt_target
	if tg.is_empty() or not g.hud.prompt.visible:
		return ""
	return String(tg.get("scene", ""))


func test_gating_and_optional() -> void:
	await new_game()
	await finish_scene()
	g.combat.bandits_enabled = false
	# what each NPC has to say per stage (""= no prompt: no line in the script for that moment)
	var expect := {
		0: {"fox": "", "crane": "", "bear": "S4-厨娘-任务前", "dog": ""},
		1: {"fox": "S2-师兄-初见", "crane": "", "bear": "S4-厨娘-任务前", "dog": "", "tanuki": "", "duck": ""},
		2: {"fox": "S2-师兄-之后", "crane": "S3-师父", "bear": "S4-厨娘-任务前"},
		3: {"crane": "S3-师父-之后", "bear": "S4-厨娘", "dog": ""},
		4: {"bear": "S4-厨娘-之后", "dog": "S5-老伯", "crane": ""},
		6: {"tanuki": "S7-茶摊老板", "duck": "", "dog": ""},
		7: {"duck": "S7-村民", "tanuki": "", "crane": ""},
		8: {"crane": "S9-师父-收尾"},
		9: {"fox": "S9-师兄", "crane": ""},
	}
	var bad := []
	for st in expect:
		story.set_stage(st)
		for id in expect[st]:
			var got := await _prompt_scene_at(id)
			if got != expect[st][id]:
				bad.append("%d %s: %s (want %s)" % [st, id, got, expect[st][id]])
	r.check(bad.is_empty(), "story AC2: '按 E 交谈' and what each NPC says follow the steps (gating, '之后' lines; no prompt where the script has nothing)", str(bad))
	# 村民: S7-村民 once, then the 之后 line
	story.set_stage(7)
	await stand_near(npc("duck").global_position)
	await r.tap(KEY_E)
	await finish_scene()
	var after := await _prompt_scene_at("duck")
	r.check(story.flags.get("villager_met", false) and after == "S7-村民-之后", "story AC2: 村民 says S7-村民 once, then S7-村民-之后")
	# 厨娘's 之后 does not advance; 师父 after 3
	story.set_stage(4)
	await stand_near(npc("bear").global_position)
	await r.tap(KEY_E)
	await finish_scene()
	r.check(story.stage == 4 and story.played[-1] == "S4-厨娘-之后", "story AC2: the '之后' lines do not move the story on")
	# optional things: prompt '按 E 查看', E plays the line, leaving hides the prompt
	story.set_stage(1)
	var obad := []
	for it in sdata["interactables"]:
		if it["id"] == "stele" or it["id"] == "rag" or it["id"] == "puddle":
			continue       # rag / puddle: the wiping task (tests/polish_suite.gd)
		story.set_stage(int(it["stage"][0]) if it.has("stage") else 1)     # the note: only before it is read
		if it.has("if"):
			story.flags[it["if"]] = true                                     # the note: after wiping
		var pos: Vector2 = story._thing_pos(it)
		var st: Vector2 = r.find_free_near(pos, 12)
		if st == Vector2.INF:
			obad.append(it["id"] + " (no free ground)")
			continue
		await r.teleport(st)
		await r.frames(2)
		var want_prompt := "按 E 打开" if it.get("prompt", "") == "open" else "按 E 查看"
		var shown: bool = g.hud.prompt.visible and g.hud.prompt_label.text == want_prompt
		var k: int = story.played.size()
		await r.tap(KEY_E)
		var started: bool = story.busy and story.current_scene == it["scene"]
		await finish_scene()
		var room: String = it.get("room", "")
		await r.teleport(g.interiors.entry_spot(room) if room != "" else r.find_free_near(st + Vector2(0, 90), 40))
		await r.frames(2)
		if not (shown and started and scenes_since(k) == [it["scene"]] and not g.hud.prompt.visible):
			obad.append("%s shown %s started %s %s" % [it["id"], shown, started, scenes_since(k)])
	r.check(obad.is_empty(), "story AC5: optional lines (v4: the room things incl. 字条 / 木桶 / 衣柜 / 香炉 / 祖师像 / S10-*, and 水井, 菜地, 石狮, 藏经阁封条, 茶摊) - '按 E 查看', E plays the script's line", str(obad))


# ================================================================== AC3 lose branch, AC6 book without the win
func test_spar_lose_branch_and_book() -> void:
	await new_game()
	await finish_scene()
	story.set_stage(1)      # v3: the note has been read (S1-字条, checked by the playthrough)
	var c: Combat = g.combat
	await stand_near(npc("fox").global_position)
	await r.tap(KEY_E)
	await finish_scene(KEY_2)
	var t := 0.0
	while c.spar_state == "fighting" and t < 90.0:
		cs.bot_step("idle")
		await r.physics_frame
		t += 1.0 / 60.0
	for i in 400:
		if story.busy:
			break
		await r.physics_frame
	var lose_scene := story.current_scene
	await finish_scene()
	r.check(not c.last_spar_win and lose_scene == "S2-师兄-你输了" and story.stage == 2 and not story.flags.get("spar_won", false),
		"story AC3: losing the spar plays S2-师兄-你输了 (different lines) and still goes on to step 2", lose_scene)
	# rematch: 之后 lines, then the usual 切磋 / 算了
	await stand_near(npc("fox").global_position)
	await r.tap(KEY_E)
	var k: int = story.played.size() - 1
	await finish_scene()
	r.check(story.played[k] == "S2-师兄-之后" and c.spar_state == "choosing" and c.hud.choice.visible,
		"story AC3: afterwards 师兄 says S2-师兄-之后 and offers the spar again (切磋 / 算了)")
	await r.tap(KEY_2)
	# straight to the ending (steps 3..8 are covered by the playthrough); the book must not list 赢了师兄一回
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		story.flags[f] = true
	story.set_stage(8)
	await stand_near(npc("crane").global_position)
	await r.tap(KEY_E)
	var entries := []
	for i in 600:
		if story.sect_book.is_open:
			entries = story.sect_book.shown_entries()
			var fame_bar: String = story.sect_book.bar_labels["fame"].text
			var estate_bar: String = story.sect_book.bar_labels["estate"].text
			r.check(fame_bar == "■□□□□□□□□□" and estate_bar == "■□□□□□□□□□" and story.sect_book.hint_label.text == "两条路都能让门派复兴，任意一条走到头，就能接任掌门。",
				"story AC6: 门派簿 shows 名望 / 家业 with one segment each and the hint line", "%s %s" % [fame_bar, estate_bar])
			await r.tap(KEY_ESCAPE)
			r.check(not story.sect_book.is_open and not g.pause_menu.is_open, "story AC6: Esc closes 门派簿 (and does not open the Esc page)")
		elif story.prologue_end.is_open:
			break
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	r.check(entries == ["打跑山路上的山贼", "解开竹林断碑", "找回了老周的瓦"],
		"story AC6: after a lost spar 门派簿 has no '赢了师兄一回'", str(entries))
	r.check(g.camera_target == npc("crane") and p().sprite.modulate.a < 0.05 and "S9-师父-收尾" in story.played,
		"story AC1: the rabbit walks out, the camera rests on 师父 for his last line")
	for i in 200:
		if story.prologue_end.buttons_shown():
			break
		await r.physics_frame
	# 继续逛逛: back in the game, S9-师兄 and B
	await r.tap(KEY_DOWN)
	await r.tap(KEY_E)
	await r.frames(3)
	r.check(not story.prologue_end.is_open and not story.busy and g.camera_target == null and p().sprite.modulate.a == 1.0 and story.stage == 9,
		"story AC1: '继续逛逛' returns to the game after the prologue (step 9, 序章完成)")
	k = story.played.size()
	await stand_near(npc("fox").global_position)
	await r.tap(KEY_E)
	await finish_scene()
	r.check(scenes_since(k) == ["S9-师兄"] and c.spar_state == "choosing", "story AC5: after the ending 师兄 says S9-师兄 (then the usual invitation)")
	await r.tap(KEY_2)


# ================================================================== AC2 bandits
func test_bandits() -> void:
	await new_game()
	await finish_scene()
	var c: Combat = g.combat
	var wolf: Fighter = c.bandits[0]
	var boar: Fighter = c.bandits[1]
	# before step 5 is done: nobody on the road, the spot is walkable, nothing engages
	story.set_stage(4)
	await r.teleport(r.find_free_near(wolf.home + Vector2(0, 40)))
	await r.frames(30)
	r.check(not wolf.visible and not boar.visible and wolf.collision_layer == 0 and not wolf.engaged and not story.busy and r.is_free(wolf.home),
		"story AC2: before step 5 is done the bandits are not on the road (invisible, not solid, never attack)")
	# 老伯 -> they appear
	await stand_near(npc("dog").global_position)
	await r.tap(KEY_E)
	await finish_scene()
	r.check(story.stage == 5 and wolf.visible and boar.visible and not story.flags.get("bandits_intro_done", false), "story AC2: S5-老伯 puts the bandits on the road")
	# approach -> intro; during it nothing moves and nobody gets hurt
	await r.teleport(r.find_free_near(wolf.home + Vector2(60, -150)))
	await r.frames(3)
	r.check(story.current_scene == "S6-山贼-开战" and dlg.name_label.text == "山贼·狼", "story AC2: coming near starts S6-山贼-开战 by itself")
	await r.teleport(r.find_free_near(wolf.home + Vector2(0, 30)))   # right next to them, still talking
	var hp := p().hp
	var wp := wolf.global_position
	await r.frames(120)
	r.check(p().hp == hp and wolf.global_position == wp and not wolf.engaged, "story AC5: during the bandits' lines they stand still and do no damage (2 s next to them)")
	await finish_scene()
	r.check(wolf.engaged and boar.engaged, "story AC2: after the lines both attack")
	# lose (with the wolf already knocked out) -> respawn below the stairs, S6-失败, still step 5, both back
	wolf.take_hit(999, p().global_position, 0.0)
	var t := 0.0
	while not c.player_dead and t < 60.0:
		cs.bot_step("idle")
		await r.physics_frame
		t += 1.0 / 60.0
	for i in 300:
		if story.busy:
			break
		await r.physics_frame
	var lose := story.current_scene
	r.check(lose == "S6-山贼-失败" and p().global_position.distance_to(c.respawn_pos) < 1.0 and story.stage == 5 and g.hud.objective_label.text == "目标：沿山路去村口",
		"story AC2: knocked out by the bandits -> wake up below the stairs, S6-山贼-失败, still at step 6 (目标：沿山路去村口)", lose)
	await finish_scene()
	r.check(wolf.visible and boar.visible and wolf.state == "idle" and boar.state == "idle" and wolf.hp == wolf.stats.max_hp
		and boar.hp == boar.stats.max_hp and wolf.global_position == wolf.home, "story AC2: both bandits are back home with full HP (even the one already knocked out)")
	# go back and win
	var won := await fight_bandits()
	for i in 400:
		if story.busy or story.stage == 6:
			break
		await r.physics_frame
	var win_scene := story.current_scene
	await finish_scene()
	r.check(won and story.stage == 6 and (win_scene == "S6-山贼-胜利" or "S6-山贼-胜利" in story.played) and story.played.count("S6-山贼-开战") == 1,
		"story AC2: winning plays S6-山贼-胜利, step 6 done; the opening lines played only once")
	await r.frames(120)
	await r.teleport(r.find_free_near(wolf.home))
	await r.frames(60)
	r.check(not wolf.visible and not boar.visible and not wolf.engaged and not c.blocks_interaction() and not story.busy,
		"story AC2: driven off, the bandits do not come back")


# ================================================================== AC4 puzzle
func _bow(id: String) -> void:
	await r.teleport(r.find_free_near(story.stones[id]["pos"] + Vector2(0, 18), 16))
	await r.frames(2)
	await r.tap(KEY_E)
	await r.frames(2)


func _gate_blocks() -> bool:
	# walk at the clump from the clearing: the player must stay outside the pocket
	await r.teleport(Vector2(600, 250))
	await r.push(Vector2.LEFT, 1.0)
	return p().global_position.x > 560.0


func test_puzzle() -> void:
	await new_game()
	await finish_scene()
	story.set_stage(7)
	# S8-进林 on the first entry only. 房子整栋实心 v1 fix: WALK there from the spawn with the keys (no teleport into the wall
	# strip): across the courtyard, through the breach in the north wall beside 藏经阁, along the meadow into the grove
	await r.teleport(Vector2(g.data["spawn"]["x"], g.data["spawn"]["y"]))
	var walk1: String = await nav.walk_to(Vector2(560, 330), 150.0)
	var entered := story.current_scene
	await finish_scene()
	await r.teleport(Vector2(330, 440))
	await r.frames(5)
	var walk2: String = await nav.walk_to(Vector2(560, 330), 150.0)
	r._log("      grove walks: %s / %s, now at %s" % [walk1, walk2, p().global_position.round()])
	r.check(entered == "S8-进林" and story.played.count("S8-进林") == 1 and not story.busy, "story AC4: S8-进林 plays on the first entry into the clearing only")
	# blocked before
	var blocked := await _gate_blocks()
	r.check(blocked and not story.gate_open() and r.is_free(story.stash_pos + Vector2(0, 30)), "story AC4: before the puzzle the bamboo clump blocks the way to the stash (collision)",
		str(p().global_position.round()))
	# the stele, twice
	for i in 2:
		await r.teleport(r.find_free_near(story.stele_pos + Vector2(0, 18), 12))
		await r.frames(2)
		var pr: String = g.hud.prompt_label.text if g.hud.prompt.visible else ""
		await r.tap(KEY_E)
		var first_kind := dlg.kind
		var first_text := dlg.full_text
		await finish_scene()
		r.check(pr == "按 E 读碑文" and first_kind == "碑文" and first_text == "「风自东来，先拜青石，再拜苔石，后拜裂石。」",
			"story AC4: E at the stele reads the inscription (%s time)" % ("first" if i == 0 else "again"), "%s %s" % [pr, first_kind])
	# stones look different
	var texs := []
	for id in ["stone_qing", "stone_moss", "stone_crack"]:
		texs.append(story.stones[id]["sprite"].texture.get_image().get_data())
	r.check(texs[0] != texs[1] and texs[1] != texs[2] and texs[0] != texs[2], "story AC4: 青石 / 苔石 / 裂石 are three different pictures")
	# wrong first stone
	await _bow("stone_moss")
	var w1 := story.current_scene
	var chaos := story.fx.chaotic_gusts
	await finish_scene()
	r.check(w1 == "S8-拜错" and chaos == 1 and story.progress == 0 and story.fx.glows.is_empty(), "story AC4: a wrong stone -> chaotic gust, '……不对。风不是往这边吹的。'")
	# right, then wrong -> everything off
	await _bow("stone_qing")
	var lit: bool = story.fx.glows.has("stone_qing") and story.fx.last_wind_to.distance_to(story.stones["stone_moss"]["pos"]) < 1.0
	await _bow("stone_crack")
	var w2 := story.current_scene
	await finish_scene()
	r.check(lit and w2 == "S8-拜错" and story.fx.glows.is_empty() and story.progress == 0,
		"story AC4: 青石 lights up and the wind blows towards 苔石; then a wrong stone puts every light out (start again)")
	# third error -> the hint, once
	await _bow("stone_crack")
	var k: int = story.played.size()
	await finish_scene()
	var hint_after3 := scenes_since(k - 1)
	await _bow("stone_moss")
	k = story.played.size()
	await finish_scene()
	var after4 := scenes_since(k - 1)
	r.check(hint_after3 == ["S8-拜错", "S8-卡住提示"] and after4 == ["S8-拜错"] and story.errors == 4,
		"story AC4: after the 3rd mistake the hint '村民说，跟着风走……' comes once (not after the 4th)", "%s / %s" % [hint_after3, after4])
	# the right order
	await _bow("stone_qing")
	await _bow("stone_moss")
	var to_crack: bool = story.fx.last_wind_to.distance_to(story.stones["stone_crack"]["pos"]) < 1.0
	await _bow("stone_crack")
	r.check(to_crack and story.solved and story.fx.glows.size() == 3 and not story.busy, "story AC4: 青石 -> 苔石 -> 裂石 lights all three (wind 苔石 -> 裂石) and solves it")
	r.check(star_ok(story.stash_pos), "story AC1: once solved the star moves to the stash")
	await r.frames(100)
	r.check(story.gate_open() and story.gate_halves.size() == 2 and not story.gate_sprite.visible, "story AC4: '沙——' the clump parts (two halves slide aside)")
	await r.teleport(Vector2(600, 250))
	await r.push(Vector2.LEFT, 1.2)
	var inside := p().global_position.x < 545.0
	var sc := story.current_scene
	r.check(inside, "story AC4: after the puzzle the player walks through the opening into the pocket (collision)", str(p().global_position.round()))
	for i in 60:
		if story.busy:
			break
		await r.physics_frame
	await r.frames(2)
	var pic := false
	var k2: int = story.played.size()
	for i in 40:
		if dlg.active and dlg.kind == "画面":
			pic = dlg.picture_panel.visible and dlg.picture.texture != null
			break
		await r.tap(KEY_E)
	await finish_scene()
	r.check(story.played[-1] == "S8-找到瓦片" and pic and story.stage == 8 and story.flags.get("item_旧布", false),
		"story AC4: S8-找到瓦片 shows the old cloth picture, 获得：旧布, step 8", "%s pic %s" % [story.played.slice(k2 - 1), pic])


# ================================================================== AC5 bubbles, AC6 book key
func test_bubbles_and_book_key() -> void:
	await new_game()
	await finish_scene()
	story.set_stage(6)
	await r.teleport(npc("dog").global_position + Vector2(0, 40))
	await r.frames(10)
	r.check(story.bubble().is_empty(), "story AC5: no walking bubbles before step 7")
	story.set_stage(7)
	await r.frames(3)
	var b: Dictionary = story.bubble()
	var shown_b: bool = g.hud.bubble.visible and g.hud.bubble_label.text == "瓦被山贼藏进后山了？……竹林那条小路，好多年没人走了。"
	var pos := p().global_position
	var dir := Vector2.RIGHT
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if r.is_free(pos + d * 20) and r.is_free(pos + d * 40):
			dir = d
			break
	await r.push(dir, 0.3)
	r.check(not b.is_empty() and shown_b and p().global_position.distance_to(pos) > 30 and not story.busy, "story AC5: 老伯's bubble line appears while walking past (walking goes on)",
		"%s shown %s label '%s' moved %s" % [b, g.hud.bubble.visible, g.hud.bubble_label.text, p().global_position - pos])
	await r.frames(int(4.2 * 60))
	await r.teleport(npc("dog").global_position + Vector2(0, 40))
	await r.frames(30)
	r.check(story.bubble().is_empty() and story.bubbles_shown.count("瓦被山贼藏进后山了？……竹林那条小路，好多年没人走了。") == 1, "story AC5: each bubble line appears once")
	# 师兄: two lines, one after the other
	await r.teleport(npc("fox").global_position + Vector2(0, 40))
	await r.frames(int(4.2 * 60) * 2 + 20)
	var fox_lines := story.bubbles_shown.filter(func(s): return s.begins_with("听说") or s.begins_with("（小声）下次"))
	r.check(fox_lines == ["听说你一个人把山贼打跑了？……行啊你。哼，我才不羡慕。", "（小声）下次带上我。"], "story AC5: 师兄's two bubble lines come one after the other", str(fox_lines))
	await r.teleport(npc("bear").global_position + Vector2(0, 40))
	await r.frames(10)
	r.check(story.bubbles_shown.size() == 4, "story AC5: 厨娘's bubble too - all 4 '回门派途中' lines", str(story.bubbles_shown))
	# B before the ending does nothing
	await r.frames(int(4.2 * 60))
	await r.tap(KEY_B)
	r.check(not story.sect_book.is_open, "story AC6: B does nothing before 门派簿 has been opened at the end")
	story.flags["bandits_defeated"] = true
	story.flags["spar_won"] = true
	story.book_unlocked = true
	await r.tap(KEY_B)
	await r.frames(2)
	var opened := story.sect_book.is_open and story.sect_book.shown_entries("fame").has("赢了师兄一回")
	var pos2 := p().global_position
	r.key(KEY_D, true)
	await r.frames(20)
	r.key(KEY_D, false)
	var still := p().global_position.distance_to(pos2) < 0.5
	await r.tap(KEY_B)
	r.check(opened and still and not story.sect_book.is_open, "story AC6: afterwards B opens 门派簿 again (game holds), B / E / Esc closes it")
	var on_page := false
	for k in PauseMenu.KEYS:
		if k[0] == "B" and "门派簿" in k[1]:
			on_page = true
	r.check(on_page, "story AC6: the B key is listed on the Esc page (PauseMenu.KEYS)")
