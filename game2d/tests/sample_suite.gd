extends RefCounted
## 两条路小样 v1 checks (task packet AC1-AC7, AC9), run by tests/run_tests.gd after the other suites, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-sample
## Real key events (E / 1 / 2 / Esc / Q / B / T / Space / WASD) and real physics wherever the player does something;
## the state is set directly only to reach a starting point quickly (e.g. coins for a shortfall, the trial clock near
## its limit). Saves go to user://test_save.json (SaveGame picks it under a test main loop).
##   AC1 nothing of the sample before 继续逛逛 (stages 0..9 + the 序章 · 完 page); everything after it
##   AC2 economy table == the plan's numbers; trial card == the plan's rules; shortfall message, nothing taken
##   AC3 the trial: gating order, dummy hit 8 + stun, dodge passes, medal lines, timeout, 20 % fail + refill, yard
##       closed, abandon from the Esc page, rewards once per tier / repeat 5, 名望, no regen, E blocked, a full real-key
##       bot run to a medal
##   AC4 each repair end to end (confirm 是 / 否, shortfall, pay, fade, outside + room pictures, leak stops, 家业, once
##       only, after-lines, repaired rooms walkable, doors clear)
##   AC5 stall income across 08:00 once per day (fast-forward, the T key), toast
##   AC6 门派簿 coins, 10-segment bars (名望 4 / 家业 5 when all done), entries
##   AC7 a save at every trigger, 继续游戏 restores a snapshot-equal state (after the prologue and mid-prologue),
##       新游戏 asks before overwriting, a corrupt / wrong-version / malformed save starts fresh with the message
## Also: Esc page tips page 2 + the 放弃试炼 button only during the trial; all new text in the UI font.

const PLAN := {"start": 30, "bronze": 10, "silver": 20, "gold": 40, "repeat": 5, "stall": 15, "stall_hour": 8,
	"roof": 30, "dorm_old": 20, "kitchen": 60, "estate_roof": 1, "estate_dorm_old": 1, "estate_kitchen": 2,
	"fame_tier": 1}

var r
var g: Node
var story: Story
var dlg: Dialogue
var smp: Sample
var nav
var tdata: Dictionary


func _init(runner) -> void:
	r = runner


func run() -> void:
	# the earlier suites' game leaves the tree (its input / physics must not mix in)
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	SaveGame.erase()
	tdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/sample.json"))
	test_economy_table()
	test_trial_card_and_route()
	test_font()
	await test_numbers_from_data()
	await test_gating()
	await test_repairs()
	await test_income()
	await test_trial_rules()
	await test_trial_rewards_and_book()
	await test_trial_bot_run()
	await test_pause_page()
	await test_save_triggers()
	await test_continue_restores()
	await test_continue_mid_prologue()
	await test_new_game_confirm()
	await test_broken_saves()
	await _free_game()
	SaveGame.erase()
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_save_bad.json"):
		dir.remove("test_save_bad.json")      # the bad files the broken-save checks set aside


# ================================================================== helpers
func use_game(m: Node) -> void:
	g = m
	story = m.story
	dlg = story.dialogue
	smp = m.sample
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0
	nav = load("res://tests/nav.gd").new(r, m)


func _free_game() -> void:
	for n in r.root.get_children():
		if n.name == "TitleFadeIn" or n is TitleScreen:
			n.queue_free()
	if g != null and is_instance_valid(g):
		if g.is_inside_tree():
			g.get_parent().remove_child(g)
		g.queue_free()
	g = null
	r.paused = false
	await r.process_frame
	await r.process_frame


func new_game() -> void:
	await _free_game()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	r.current_scene = m
	use_game(m)
	m.daynight.running = false
	await r.frames(3)


func p() -> Player:
	return g.player


func npc(id: String) -> Npc:
	return story._npc(id)


## E / 1 (or the given choice key) until the conversation is over.
func finish_scene(choice_key := KEY_1, limit := 500) -> int:
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


## Talks to an NPC with E and answers every choice with `choice_key`. Returns the scenes played.
func talk(id: String, choice_key := KEY_1) -> Array:
	var n := npc(id)
	await stand_near(n.global_position)
	var k := story.played.size()
	await r.tap(KEY_E)
	await finish_scene(choice_key)
	return story.played.slice(k)


## Every line shown in the dialogue box while a scene plays (text as typed at its end).
var seen_lines: Array[String] = []


func _watch_lines() -> void:
	seen_lines.clear()
	if not dlg.is_connected("line_done", _on_line):
		dlg.line_done.connect(_on_line)


func _on_line() -> void:
	seen_lines.append(dlg.full_text)


## The real end of the prologue: stage 8 -> 师父 (E) -> S9-师父-收尾 -> 门派簿 -> 序章 · 完 -> 继续逛逛 (↓ + E).
func reach_unlock() -> void:
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		story.flags[f] = true
	story.set_stage(8)
	await stand_near(npc("crane").global_position)
	await r.tap(KEY_E)
	for i in 900:
		if story.sect_book.is_open:
			await r.tap(KEY_ESCAPE)
		elif story.prologue_end.is_open:
			if story.prologue_end.buttons_shown():
				break
			await r.frames(2)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.tap(KEY_DOWN)
	await r.tap(KEY_E)
	await r.frames(4)


func board_visible() -> bool:
	return smp.trial.board.visible and not smp.trial.board_shape.disabled


func sample_visible() -> Dictionary:
	return {"mouse": smp.mouse.visible, "mouse_solid": smp.mouse.collision_layer != 0, "board": board_visible(),
		"poles": smp.trial.pole_layer.visible, "dummies": smp.trial.dummies.any(func(d): return d.visible),
		"coins": smp.coin_panel.visible, "stall": smp.stall.visible}


func any_true(d: Dictionary) -> bool:
	return d.values().any(func(v): return v)


func all_true(d: Dictionary) -> bool:
	return d.values().all(func(v): return v)


## Puts coins directly (a starting point for a test, not a game action).
func set_coins(n: int) -> void:
	smp.coins = n
	smp._refresh_coins()


# ================================================================== AC2 economy table / trial card
func test_economy_table() -> void:
	Economy.reload()
	var e := Economy.data()
	var got := {"start": Economy.start_coins(), "bronze": Economy.trial_reward("bronze"), "silver": Economy.trial_reward("silver"),
		"gold": Economy.trial_reward("gold"), "repeat": Economy.trial_repeat(), "stall": Economy.stall_income(),
		"stall_hour": int(Economy.stall_hour()), "roof": Economy.price("roof"), "dorm_old": Economy.price("dorm_old"),
		"kitchen": Economy.price("kitchen"), "estate_roof": Economy.points_for("estate", "repair_roof"),
		"estate_dorm_old": Economy.points_for("estate", "repair_dorm_old"), "estate_kitchen": Economy.points_for("estate", "repair_kitchen"),
		"fame_tier": Economy.points_for("fame", "trial_gold")}
	var bad := []
	for k in PLAN:
		if int(got[k]) != int(PLAN[k]):
			bad.append("%s %s != %s" % [k, got[k], PLAN[k]])
	r.check(bad.is_empty() and Economy.fame_points("bronze") == 1 and Economy.fame_points("silver") == 1,
		"sample AC2: data/economy.json matches the plan item by item (本钱 30, 铜/银/金 10/20/40, repeat 5, stall 15 at 08:00, roof 30 / old dorm 20 / kitchen 60, 家业 1/1/2, 名望 +1 per tier)", str(bad))
	r.check(FileAccess.get_file_as_string("res://data/economy.json").contains("\"start_coins\": 30") and not FileAccess.get_file_as_string("res://scripts/sample.gd").contains("30)"),
		"sample AC2: the numbers live in the external economy table (not in the code)")
	# the plan's arithmetic: 30 pays the roof; all three tiers (70) + 0 leave 10 short of 20 + 60; two repeats close it
	var all_tiers: int = Economy.trial_reward("bronze") + Economy.trial_reward("silver") + Economy.trial_reward("gold")
	r.check(Economy.start_coins() == Economy.price("roof") and all_tiers == 70
		and Economy.price("dorm_old") + Economy.price("kitchen") - all_tiers == 2 * Economy.trial_repeat(),
		"sample AC2: the plan's budget works out (本钱 = roof; tiers 70 + 2 repeats = old dorm + kitchen)")
	r.check(e.has("repairs") and e["repairs"].size() == 3, "sample AC2: three repairs in the table")


func test_trial_card_and_route() -> void:
	var c: TrialCard = load("res://cards/trial_plum.tres")
	r.check(c.pole_count == 12 and c.pole_points.size() == 12 and is_equal_approx(c.time_limit, 60.0)
		and is_equal_approx(c.gold_seconds, 40.0) and is_equal_approx(c.silver_seconds, 50.0) and is_equal_approx(c.bronze_seconds, 60.0)
		and c.dummy_damage == 8 and c.dummy_points.size() == 2 and is_equal_approx(c.fail_hp_fraction, 0.2),
		"sample AC3: trial card = the plan (12 poles, 60 s, 金 40 / 银 50 / 铜 60, 2 dummies, 8 damage, fail at 20 %)")
	r.check(Economy.best_tier(39.9, c) == "gold" and Economy.best_tier(40.0, c) == "gold" and Economy.best_tier(40.01, c) == "silver"
		and Economy.best_tier(50.0, c) == "silver" and Economy.best_tier(50.01, c) == "bronze" and Economy.best_tier(60.0, c) == "bronze"
		and Economy.best_tier(60.01, c) == "", "sample AC3: medal lines 金 ≤40 s, 银 ≤50 s, 铜 ≤60 s, slower = none")


func test_font() -> void:
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := FileAccess.get_file_as_string("res://data/sample.json") + FileAccess.get_file_as_string("res://data/economy.json") \
		+ FileAccess.get_file_as_string("res://data/title.json") + PauseMenu.all_text() + SaveGame.BROKEN_TEXT
	var missing := ""
	for ch in text:
		if ch.unicode_at(0) > 0x7f and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	r.check(missing == "", "sample AC9: every new character (lines, UI, title, Esc tips) exists in the project UI font", missing)


# ================================================================== review extra 1: numbers in the lines come from the data
func test_numbers_from_data() -> void:
	Economy.reload()
	var keep: Dictionary = Economy.data().duplicate(true)
	# the loaded economy table with the roof at 35 and the stall at 9 o'clock (what editing economy.json does)
	Economy._data["repairs"]["roof"]["price"] = 35
	Economy._data["stall_hour"] = 9
	await new_game()
	var lines := []
	for sc in ["X-老周-修屋顶", "X-厨娘-修好了", "X-试炼木牌"]:
		for e in story.scene(sc):
			lines.append(String(e.get("text", "")))
	var joined := "\n".join(lines)
	var tips := ""
	for l in g.pause_menu.sample_tip_labels:
		tips += l.text + "\n"
	r.check("就收个工钱，35 文" in joined and "花 35 铜钱请老周修屋顶？" in joined and "辰时（9 点）" in joined
		and "限时 60 秒。40 秒内为金，50 秒内为银，60 秒内为铜。" in joined and not "{" in joined + tips and "老周（屋顶 35）" in tips,
		"sample extra: prices / hours / seconds in the lines and Esc tips come from economy.json and the trial card (roof 35 -> '35 文')", joined.substr(0, 200))
	# back to the real table (the repair test below also checks the question as typed in the dialogue box)
	Economy._data = keep
	Economy.reload()
	await new_game()
	var j2 := ""
	for e in story.scene("X-老周-修屋顶"):
		j2 += String(e.get("text", ""))
	r.check("花 30 铜钱请老周修屋顶？" in j2 and "就收个工钱，30 文" in j2, "sample extra: with the real table the lines say 30 again")


# ================================================================== AC1 gating
func test_gating() -> void:
	await new_game()
	var c := sample_visible()
	r.check(not smp.unlocked and not any_true(c) and smp.coins == 0, "sample AC1: at the start nothing of the sample is there (老周, board, poles, dummies, coins, stall)", str(c))
	await finish_scene()      # the opening
	var leaks := []
	for st in [0, 1, 3, 5, 7, 8, 9]:
		story.set_stage(st)
		await r.frames(2)
		if any_true(sample_visible()):
			leaks.append("stage %d visible" % st)
		for id in ["mouse", "dog", "bear", "crane"]:
			var sc := story.talk_scene(id)
			if sc.begins_with("X-"):
				leaks.append("stage %d %s -> %s" % [st, id, sc])
		await r.teleport(smp.trial.board_point() + Vector2(0, 14))
		var t := story.interaction_target()
		if t.get("id", "") == "trial_sign":
			leaks.append("stage %d board E" % st)
	r.check(leaks.is_empty(), "sample AC1: during the prologue (every stage, stage 9 included until 继续逛逛) no sample person, prop, talk, E target or coin counter",
		str(leaks))
	story.set_stage(1)
	await new_game()
	await finish_scene()
	await reach_unlock()
	var v := sample_visible()
	v.erase("stall")
	r.check(smp.unlocked and all_true(v) and smp.coins == 30 and smp.coin_label.text == "铜钱 30"
		and "师父给的本钱：铜钱 +30" in smp.toasts, "sample AC1: '继续逛逛' -> 老周, the trial board / poles / dummies and the coin counter (30) appear, toast for the 本钱",
		"%s coins %d '%s'" % [v, smp.coins, smp.coin_label.text])
	r.check(not smp.stall.visible, "sample AC1: the food stall only after the kitchen repair")
	await _check_toast_clear("师父给的本钱：铜钱 +30")
	var talks := {}
	for id in ["mouse", "dog", "bear", "crane"]:
		talks[id] = story.talk_scene(id)
	r.check(talks == {"mouse": "X-老周-修屋顶", "dog": "X-老伯-旧弟子房", "bear": "X-厨娘-修厨房", "crane": "X-师父-两条路"},
		"sample AC1: after it 老周 / 老伯 / 厨娘 talk about the repairs, 师父 about the two roads", str(talks))
	await r.teleport(smp.trial.board_point() + Vector2(0, 14))
	await r.frames(2)
	r.check(g.prompt_target.get("id", "") == "trial_sign" and g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 看木牌",
		"sample AC1: at the trial board the prompt '按 E 看木牌' shows")
	# the coin counter sits beside the HP bar (right of it, same row, not over the objective / minimap)
	var hp: Rect2 = g.combat.hud.hp_panel.get_global_rect()
	var cr: Rect2 = smp.coin_panel.get_global_rect()
	r.check(cr.position.x >= hp.end.x and absf(cr.position.y - hp.position.y) < 2.0 and not cr.intersects(g.hud.objective.get_global_rect())
		and Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size).encloses(cr),
		"sample AC1: the coin counter is beside the HP bar", "hp %s coins %s" % [hp, cr])
	# 老周 stands on free ground at the dorm door, out of the door path
	var mz := smp.mouse.global_position
	var door_clear: bool = not g.interiors.outdoor_trigger("dorm_main").grow(8).has_point(mz) and not g.interiors.outdoor_trigger("storage").grow(8).has_point(mz)
	r.check(door_clear and mz.distance_to(g.interiors.exit_spot("dorm_main")) < 80.0 and r.find_free_near(mz + Vector2(0, 24), 12) != Vector2.INF,
		"sample: 老周 waits by the dorm door without blocking it", str(mz))
	# 师父's word
	var sc := await talk("crane")
	r.check(sc == ["X-师父-两条路"], "sample AC1: 师父 points to the board and the repairs", str(sc))


## Review fix F1: the toast's drawn text never meets the coin counter (or the HP bar), and it is drawn above them.
func _check_toast_clear(text: String) -> void:
	await r.process_frame
	var tr: Rect2 = g.hud.toast_text_rect()
	var coin := smp.coin_panel.get_global_rect()
	var hp: Rect2 = g.combat.hud.hp_panel.get_global_rect()
	var on_top: bool = g.hud.toast.get_index() > smp.coin_panel.get_index()
	r.check(g.hud.toast.text == text and tr.size.x > 40.0 and not tr.intersects(coin) and not tr.intersects(hp) and on_top
		and Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size).encloses(tr),
		"sample F1: the toast '%s' is fully readable - clear of the coin counter and the HP bar" % text, "toast %s coins %s hp %s" % [tr, coin, hp])


# ================================================================== AC4 repairs
func test_repairs() -> void:
	# (continues the unlocked game of test_gating)
	var est0 := SectBook.track_value(story.sect_book.data["tracks"][1], story.flags)
	# --- roof: 否 first (nothing happens), then a shortfall, then paid
	set_coins(30)
	var sc := await talk("mouse", KEY_2)
	r.check(sc == ["X-老周-修屋顶"] and smp.coins == 30 and not smp.is_repaired("roof"), "sample AC4 roof: the confirm question 是 / 否 - 否 leaves coins and roof alone")
	set_coins(12)
	_watch_lines()
	sc = await talk("mouse", KEY_1)
	r.check(smp.coins == 12 and not smp.is_repaired("roof") and smp.shortfalls.back() == 18 and "铜钱不够，还差 18 文。" in seen_lines
		and "X-老周-修屋顶" in sc, "sample AC4/AC2: not enough coins -> '还差 18 文', nothing taken, nothing repaired", str(seen_lines.slice(-3)))
	set_coins(30)
	var dorm_tex: Texture2D = smp.exterior_sprites["roof"].texture
	var fade_seen := [false]
	var watch := func(): if g.interiors.fade_rect.color.a > 0.95: fade_seen[0] = true
	g.get_tree().process_frame.connect(watch)
	_watch_lines()
	sc = await talk("mouse", KEY_1)
	g.get_tree().process_frame.disconnect(watch)
	var it: Interiors = g.interiors
	var room: Dictionary = it.rooms["dorm_main"]
	var drips_left: Array = it.drips.list.filter(func(d): return d["room"] == "dorm_main")
	r.check(smp.coins == 0 and smp.is_repaired("roof") and fade_seen[0] and smp.exterior_sprites["roof"].texture != dorm_tex
		and smp.exterior_sprites["roof"].texture.resource_path.ends_with("dorm_roof_fixed.png"),
		"sample AC4 roof: pay 30 -> fade out / in -> the outside roof picture is the mended one", "coins %d fade %s" % [smp.coins, fade_seen[0]])
	r.check(String(room.get("tex", "")).ends_with("dorm_main_fixed") and drips_left.is_empty() and not room["furniture"].has("bucket")
		and it.puddle_size == 0.0 and not it.puddle_draw.visible and it.leak_stopped.get("dorm_main", false),
		"sample AC4 roof: the room is the dry one - no drips (leak animation off), no bucket, no puddle", "tex %s drips %d" % [room.get("tex"), drips_left.size()])
	r.check("补好了！新瓦压旧瓦，往后下多大的雨，屋里都是干的。" in seen_lines and "请老周修好了宿舍屋顶" in _entries("estate")
		and SectBook.track_value(story.sect_book.data["tracks"][1], story.flags) == est0 + 1,
		"sample AC4 roof: after-lines, 门派簿 entry '请老周修好了宿舍屋顶', 家业 +1")
	set_coins(100)
	sc = await talk("mouse", KEY_1)
	r.check(sc == ["X-老周-修好之后"] and smp.coins == 100, "sample AC4 roof: only once - afterwards 老周 says the after lines and takes nothing", str(sc))
	# the bucket is gone from E in the room
	await r.teleport(it.world_point("dorm_main", Vector2(288, 100)))
	await r.frames(2)
	r.check(story.interaction_target().get("id", "") != "dorm_bucket", "sample AC4 roof: the bucket can no longer be looked at")
	await _room_walkable("dorm_main")
	# --- old dorm (老伯 at the gate)
	set_coins(19)
	_watch_lines()
	sc = await talk("dog", KEY_1)
	r.check(smp.coins == 19 and not smp.is_repaired("dorm_old") and "铜钱不够，还差 1 文。" in seen_lines, "sample AC4 old dorm: 19 of 20 -> '还差 1 文', nothing taken")
	set_coins(25)
	_watch_lines()
	sc = await talk("dog", KEY_1)
	var od: Dictionary = it.rooms["dorm_old"]
	var lamp := (od["lights"] as Array).any(func(l): return l.get_meta("kind") == "oil_lamp")
	r.check(smp.coins == 5 and smp.is_repaired("dorm_old") and String(od.get("tex", "")).ends_with("dorm_old_clean") and lamp
		and "整理好了旧弟子房" in _entries("estate") and "瞧瞧，蛛网扫了，被褥铺上了，灯也点上了。" in seen_lines,
		"sample AC4 old dorm: pay 20 -> the clean room (made beds, lamp light), entry '整理好了旧弟子房', after-lines")
	sc = await talk("dog", KEY_1)
	r.check(sc == ["X-老伯-整理之后"] and smp.coins == 5, "sample AC4 old dorm: only once")
	await _room_walkable("dorm_old")
	# the cleaned beds have their own line
	await r.teleport(it.anchor("dorm_old", "empty_beds") + Vector2(0, 24))
	await r.frames(2)
	var t := story.interaction_target()
	r.check(t.get("id", "") != "empty_beds" or t.get("scene", "") == "X-空床-整理后", "sample AC4 old dorm: the empty beds are described as made", str(t.get("scene")))
	# --- kitchen (厨娘 inside the kitchen)
	set_coins(59)
	_watch_lines()
	sc = await talk("bear", KEY_1)
	r.check(smp.coins == 59 and not smp.is_repaired("kitchen") and "铜钱不够，还差 1 文。" in seen_lines and not smp.stall.visible,
		"sample AC4 kitchen: 59 of 60 -> '还差 1 文', nothing taken, no stall")
	set_coins(60)
	var ktex: Texture2D = smp.exterior_sprites["kitchen"].texture
	_watch_lines()
	sc = await talk("bear", KEY_1)
	var kr: Dictionary = it.rooms["kitchen"]
	var fires := (kr["lights"] as Array).filter(func(l): return l.get_meta("kind") == "stove_fire").size()
	r.check(smp.coins == 0 and smp.is_repaired("kitchen") and smp.exterior_sprites["kitchen"].texture != ktex
		and String(kr.get("tex", "")).ends_with("kitchen_fixed") and fires == 2 and smp.stall.visible and not smp.stall_shape.disabled,
		"sample AC4 kitchen: pay 60 -> mended roof outside, rebuilt stove inside (2 fires), the food stall at the door (solid)")
	r.check("厨房小食摊开张" in _entries("estate") and SectBook.track_value(story.sect_book.data["tracks"][1], story.flags) == est0 + 4
		and "灶膛不倒烟了，屋顶也不漏了！" in seen_lines, "sample AC4 kitchen: entry '厨房小食摊开张', 家业 +2 (1 + 1 + 2 = 4 more)")
	sc = await talk("bear", KEY_1)
	r.check(sc == ["X-厨娘-修好之后"] and smp.coins == 0, "sample AC4 kitchen: only once")
	await _room_walkable("kitchen")
	# the stall leaves the kitchen door and the well path free: out of the door and down with the real keys
	await r.teleport(it.exit_spot("kitchen"))
	await r.push(Vector2.DOWN, 0.8)
	var down: float = p().global_position.y - it.exit_spot("kitchen").y
	await r.teleport(it.exit_spot("kitchen"))
	await r.push(Vector2.UP, 0.6)
	await nav.settle()
	r.check(down > 60.0 and it.room_at(p().global_position) == "kitchen", "sample AC4 kitchen: with the stall up the kitchen door still works and the yard below is open",
		"walked %.0f px down; room '%s'" % [down, it.room_at(p().global_position)])


func _entries(track: String) -> Array:
	story.sect_book.refresh(story.flags)
	return story.sect_book.shown_entries(track)


## A repaired room: from the door every interact anchor is reachable, and walking out through the door works (real keys).
func _room_walkable(id: String) -> void:
	var it: Interiors = g.interiors
	nav.grids.erase(id)
	var reach: PackedByteArray = nav.reachable(id, it.entry_spot(id))
	var gr: Dictionary = nav.room_grid(id)
	var bad := []
	for a in it.rooms[id]["def"].get("anchors", {}):
		if id == "dorm_main" and a in ["bucket", "puddle"]:
			continue
		var ap := it.anchor(id, a)
		var ok := false
		for j in reach.size():
			if reach[j] == 1 and nav.cell_pos(gr, j).distance_to(ap) <= 34.0:
				ok = true
				break
		if not ok:
			bad.append(a)
	await r.teleport(it.entry_spot(id) + Vector2(0, -24))
	var res: String = await nav.go_out(id)
	r.check(bad.is_empty() and res == "door" and it.room_at(p().global_position) == "",
		"sample AC4 %s: the repaired room is walkable (every E spot reachable from the door) and its door leads out" % id, "unreachable %s, out: %s" % [bad, res])


# ================================================================== AC5 daily income
func test_income() -> void:
	# continues: the stall opened at the repair (time frozen at the start hour)
	var dn: DayNight = g.daynight
	dn.running = false
	set_coins(0)
	var n0 := smp.incomes
	dn.set_hour(7.0)          # the clock goes forward to 07:00 the next morning - not yet 08:00
	await r.frames(3)
	var before := smp.coins
	dn.advance_hours(0.9)     # 07:54
	await r.frames(3)
	var still := smp.coins
	await r.tap(KEY_T)        # the real time-skip key: +1 h -> 08:54
	await r.frames(3)
	var after := smp.coins
	r.check(before == 0 and still == 0 and after == 15 and smp.incomes == n0 + 1 and "小食摊今日收入 +15" in smp.toasts
		and g.hud.toast.text == "小食摊今日收入 +15", "sample AC5: crossing 08:00 pays the stall once (+15) with the toast '小食摊今日收入 +15'",
		"%d %d %d" % [before, still, after])
	await _check_toast_clear("小食摊今日收入 +15")
	for i in 6:
		dn.advance_hours(2.0)        # the rest of the day, past midnight up to 08:54 + 12 h
		await r.frames(2)
	r.check(smp.coins == 15 and smp.incomes == n0 + 1, "sample AC5: only once per day (no second payment the same day)", str(smp.coins))
	dn.advance_hours(11.5)           # 08:24 next day
	await r.frames(3)
	r.check(smp.coins == 30 and smp.incomes == n0 + 2, "sample AC5: the next morning pays again (+15)", str(smp.coins))
	# real time: 48 min a day - running the clock over 08:00 pays too
	dn.set_hour(7.99)
	dn.running = true
	await r.frames(90)
	dn.running = false
	r.check(smp.coins == 45, "sample AC5: the running clock crossing 08:00 pays as well", str(smp.coins))


# ================================================================== AC3 trial rules
func _start_trial_by_keys() -> void:
	await r.teleport(smp.trial.board_point() + Vector2(0, 14))
	await r.frames(2)
	await r.tap(KEY_E)
	await finish_scene(KEY_1)
	for i in 120:
		if smp.trial.state == "running":
			break
		await r.physics_frame


func _wait_trial_idle() -> void:
	for i in 400:
		if smp.trial.state == "idle":
			break
		if smp.trial.state == "result":
			await r.tap(KEY_E)
		await r.physics_frame
	await r.frames(2)


## A spot far from both dummies, inside the yard.
func _safe_spot() -> Vector2:
	return Vector2(1300, 1110) if r.is_free(Vector2(1300, 1110)) else r.find_free_near(Vector2(1300, 1100), 24)


func test_trial_rules() -> void:
	var tr: PlumTrial = smp.trial
	var c: Combat = g.combat
	# reach the board with the real keys: E -> board text -> 报名？ 是
	await _start_trial_by_keys()
	r.check(tr.state == "running" and c.trial_active and c.yard_closed() and tr.current == 0 and tr.pole_frame(0) in [1, 2, 3, 4] and tr.pole_frame(1) == 0,
		"sample AC3: E at the board -> 报名 是 -> the trial runs; the yard closes; pole 1 lights, the others are dark")
	g.hud.show_toast("小食摊今日收入 +15")
	await r.process_frame
	var tt: Rect2 = g.hud.toast_text_rect()
	r.check(not tt.intersects(tr.hud_panel.get_global_rect()) and not tt.intersects(smp.coin_panel.get_global_rect()),
		"sample F1: during the trial a toast (e.g. the stall income) stays clear of the trial clock and the coins", "%s / %s" % [tt, tr.hud_panel.get_global_rect()])
	r.check(tr.hud_panel.visible and tr.hud_poles.text == "梅花桩 0 / 12" and tr.hud_time.text.begins_with("用时 ") and tr.hud_lines.text == "金 40 秒内 · 银 50 秒内 · 铜 60 秒内",
		"sample AC3: the clock / pole count / medal lines are on screen", tr.hud_time.text)
	# gating: standing on pole 2 first does nothing, pole 1 then 2 count
	await r.teleport(tr.step_point(1))
	await r.frames(3)
	var skip := tr.current
	await r.teleport(tr.step_point(0))
	await r.frames(3)
	var one := tr.current
	await r.teleport(tr.step_point(1))
	await r.frames(3)
	r.check(skip == 0 and one == 1 and tr.current == 2 and tr.pole_frame(0) == 5 and tr.pole_frame(1) == 5 and tr.pole_frame(2) != 0,
		"sample AC3: only the lit pole counts (pole 2 first: nothing; 1 then 2: both done, 3 lights)", "%d %d %d" % [skip, one, tr.current])
	# E does nothing during the run; no regen (counts as combat)
	await r.teleport(_safe_spot())
	p().hp = 60
	var e_target := story.interaction_target()
	await r.frames(int(6.5 * 60))
	r.check(e_target.is_empty() and c.in_combat() and p().hp == 60 and not p().regen_active,
		"sample AC3: during the trial E does nothing and HP does not regenerate (counts as combat, 6.5 s)", "hp %d" % p().hp)
	# yard closed: walking south out of the yard with the real keys stops at the yard edge
	await r.teleport(Vector2(1040, 1130))
	await r.push(Vector2.DOWN, 1.5)
	var y_out: float = p().global_position.y
	r.check(y_out < c.arena_rect.end.y and g.interiors.room_at(p().global_position) == "", "sample AC3: the yard exits are closed during the trial", str(p().global_position))
	# a dummy arm: 8 damage + stun
	p().hp = 100
	var foot: Vector2 = tr.card.dummy_points[0]
	var spot := foot + Vector2(26, 0)
	if not r.is_free(spot):
		spot = foot + Vector2(-26, 0)
	await r.teleport(spot)
	p().protect_left = 0.0
	tr.angles[0] = (spot - foot).angle() - deg_to_rad(10.0) * signf(tr.card.dummy_turn_degrees[0])
	var hits0 := tr.hits
	var stunned := false
	for i in 30:
		await r.physics_frame
		stunned = stunned or p().stun_left > 0.0
		if tr.hits > hits0:
			break
	r.check(tr.hits == hits0 + 1 and p().hp == 92 and stunned, "sample AC3: a turning arm that sweeps over her: -8 HP and a short stun", "hp %d" % p().hp)
	# a dodge through the arm: no damage
	await r.frames(60)
	await r.teleport(spot)
	p().protect_left = 0.0
	p().dash_cooldown_left = 0.0
	var hp0 := p().hp
	var hits1 := tr.hits
	await r.tap(KEY_SPACE)            # dodge in place (facing) - i-frames start
	tr.angles[0] = (spot - foot).angle()    # the arm is right on her
	await r.frames(6)
	var dodge_ok := tr.hits == hits1 and p().hp == hp0 and p().iframes_left >= 0.0
	r.check(dodge_ok, "sample AC3: dodging through a sweeping arm - the dodge's i-frames, no damage", "hp %d->%d" % [hp0, p().hp])
	await r.teleport(_safe_spot())
	# 20 % rule: HP down to 20 -> this run fails, HP refilled
	p().hp = 26
	await r.teleport(spot)
	p().protect_left = 0.0
	p().iframes_left = 0.0
	tr.angles[0] = (spot - foot).angle() - deg_to_rad(8.0) * signf(tr.card.dummy_turn_degrees[0])
	for i in 40:
		await r.physics_frame
		if tr.state != "running":
			break
	r.check(tr.last_result == "knocked" and tr.state == "result" and p().hp == p().stats.max_hp and not c.trial_active and not c.yard_closed()
		and tr.result_title.text == "被木人桩扫倒 · 这次失败" and tr.result_panel.visible,
		"sample AC3: down to 20 % HP -> '这次失败', HP back to full, the yard opens", "%s hp %d" % [tr.last_result, p().hp])
	await _wait_trial_idle()
	# timeout
	await _start_trial_by_keys()
	await r.teleport(_safe_spot())
	tr.elapsed = 59.8
	await r.frames(20)
	r.check(tr.last_result == "timeout" and tr.result_title.text == "超时 · 这次失败" and not c.trial_active and not c.yard_closed(),
		"sample AC3: past 60 s -> 超时, this run fails, the yard opens")
	var coins_t := smp.coins
	await _wait_trial_idle()
	r.check(smp.coins == coins_t and not story.flags.has("trial_bronze"), "sample AC3: a failed run pays nothing")
	# abandon from the Esc page (real keys: Esc, then Q)
	await _start_trial_by_keys()
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var pm: PauseMenu = g.pause_menu
	var btn_on: bool = pm.is_open and pm.abandon_button.visible and pm.abandon_button.text.begins_with("放弃试炼")
	await r.tap(KEY_Q)
	await r.frames(3)
	r.check(btn_on and not pm.is_open and not r.paused and tr.last_result == "abandoned" and tr.state == "idle" and not c.trial_active
		and not c.yard_closed() and not pm.abandon_button.visible, "sample AC3: Esc page has '放弃试炼' during the trial; it ends the run and resumes the game")
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var no_btn: bool = pm.is_open and not pm.abandon_button.visible
	await r.tap(KEY_ESCAPE)
	r.check(no_btn, "sample AC3: no '放弃试炼' on the Esc page outside the trial")
	# the button by mouse works too
	await _start_trial_by_keys()
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	pm.abandon_button.pressed.emit()
	await r.frames(3)
	r.check(tr.last_result == "abandoned" and not pm.is_open and tr.state == "idle", "sample AC3: clicking '放弃试炼' does the same")


# ================================================================== AC3 rewards + AC6 book
## Runs the trial to the end by standing on each lit pole in turn (teleport), with the clock set so it ends at `secs`.
func _finish_run(secs: float) -> void:
	var tr: PlumTrial = smp.trial
	await _start_trial_by_keys()
	for i in tr.card.pole_points.size():
		if i == tr.card.pole_points.size() - 1:
			tr.elapsed = secs - 1.0 / 60.0
		await r.teleport(tr.step_point(i))
		await r.frames(1)
		if tr.state != "running":
			break
	for i in 10:
		if tr.state != "running":
			break
		await r.physics_frame


func test_trial_rewards_and_book() -> void:
	var tr: PlumTrial = smp.trial
	for t in Economy.TIERS:
		story.flags.erase("trial_" + t)
	set_coins(0)
	var fame0 := SectBook.track_value(story.sect_book.data["tracks"][0], story.flags)
	# 45 s: 银 (and, within 60 s, 铜): both first time
	await _finish_run(45.0)
	var i1 := tr.last_info.duplicate()
	r.check(tr.last_result == "silver" and smp.coins == 30 and i1.get("fame") == 2 and story.flags.get("trial_silver", false)
		and story.flags.get("trial_bronze", false) and tr.result_title.text == "梅花桩试炼 · 银" and tr.result_reward.text == "铜钱 +30  名望 +2 格",
		"sample AC3: first finish in 45 s -> 银 (and 铜 within 60 s): first-time rewards 20 + 10, 名望 +2", "%s %d %s" % [tr.last_result, smp.coins, tr.result_reward.text])
	await _wait_trial_idle()
	await _finish_run(38.0)
	r.check(tr.last_result == "gold" and smp.coins == 70 and tr.last_info.get("fame") == 1 and story.flags.get("trial_gold", false),
		"sample AC3: then 金 in 38 s -> +40 and 名望 +1 (铜 / 银 not paid again)", str(smp.coins))
	await _wait_trial_idle()
	await _finish_run(55.0)
	r.check(tr.last_result == "bronze" and smp.coins == 75 and tr.last_info.get("fame") == 0 and tr.result_reward.text == "铜钱 +5",
		"sample AC3: a repeat with at least 铜 -> 5 each time, nothing else", str(smp.coins))
	await _wait_trial_idle()
	await _finish_run(39.0)
	r.check(smp.coins == 80, "sample AC3: a repeat 金 -> also only 5", str(smp.coins))
	await _wait_trial_idle()
	var fame := SectBook.track_value(story.sect_book.data["tracks"][0], story.flags)
	r.check(fame == fame0 + 3, "sample AC3: 名望 +1 per tier, first time only (+3 in total)", "%d -> %d" % [fame0, fame])
	# 门派簿 with the real B key
	await r.teleport(_safe_spot())
	await r.tap(KEY_B)
	await r.frames(3)
	var sb := story.sect_book
	var fame_e: Array = sb.shown_entries("fame")
	var est_e: Array = sb.shown_entries("estate")
	r.check(sb.is_open and sb.coins_label != null and sb.coins_label.text == "铜钱：80 文" and sb.bar_labels["fame"].text.length() == 10
		and sb.bar_labels["estate"].text.length() == 10,
		"sample AC6: 门派簿 shows the coins ('铜钱：80 文') and two 10-segment bars", sb.coins_label.text if sb.coins_label else "-")
	r.check(sb.bar_labels["fame"].text == "■■■■□□□□□□" and sb.bar_labels["estate"].text == "■■■■■□□□□□" and sb.values == {"fame": 4, "estate": 5},
		"sample AC6: everything done -> 名望 4 / 家业 5 (序章 1 + 3 tiers; 序章 1 + 1 + 1 + 2)", "%s %s" % [sb.bar_labels["fame"].text, sb.bar_labels["estate"].text])
	r.check(fame_e.slice(-3) == ["梅花桩试炼·铜", "梅花桩试炼·银", "梅花桩试炼·金"] and est_e.slice(-3) == ["请老周修好了宿舍屋顶", "整理好了旧弟子房", "厨房小食摊开张"],
		"sample AC6: the new entries are listed", "%s / %s" % [fame_e, est_e])
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	r.check(Rect2(Vector2.ZERO, vp).encloses(sb.panel.get_global_rect()), "sample AC6: the longer 门派簿 still fits on the screen", str(sb.panel.get_global_rect()))
	await r.tap(KEY_E)


# ================================================================== AC3 the real-key bot run
## From the board with the real keys: E, 是, then steer with the movement keys towards the lit pole each frame; when an
## arm is about to cross her path, dodge (Space) through it. Must reach a medal within the limit.
func test_trial_bot_run() -> void:
	var tr: PlumTrial = smp.trial
	await _start_trial_by_keys()
	var started_ok := tr.state == "running"
	var frames := 0
	var stuck := 0.0
	var last := p().global_position
	var dodges := 0
	while tr.state == "running" and frames < 70 * 60:
		var goal: Vector2 = tr.step_point(tr.current)
		var to := goal - p().global_position
		r.hold_dir(to.normalized() if to.length() > 2.0 else Vector2.ZERO)
		# an arm tip close ahead and coming: dodge towards the pole
		if p().dash_cooldown_left <= 0.0 and not p().is_dashing() and _arm_threat(tr):
			r.key(KEY_SPACE, true)
			await r.physics_frame
			r.key(KEY_SPACE, false)
			dodges += 1
		await r.physics_frame
		frames += 1
		stuck = stuck + 1.0 / 60.0 if p().global_position.distance_to(last) < 0.2 and not p().is_stunned() else 0.0
		last = p().global_position
		if stuck > 2.0:
			break
	r.release_all()
	var res := tr.last_result
	var secs := tr.last_seconds
	await _wait_trial_idle()
	r.check(started_ok and res in ["gold", "silver", "bronze"], "sample AC3: a full trial run with the real keys (walk + dodge bot) reaches a medal",
		"%s in %.1f s, %d hits, %d dodges" % [res, secs, tr.hits, dodges])
	r._log("      bot run: %s in %.1f s, %d hits, %d dodges" % [res, secs, tr.hits, dodges])


func _arm_threat(tr: PlumTrial) -> bool:
	var pos := p().global_position
	for i in tr.card.dummy_points.size():
		var foot: Vector2 = tr.card.dummy_points[i]
		var d := pos.distance_to(foot)
		if d > tr.card.arm_length + 10.0 or d < 6.0:
			continue
		var a := (pos - foot).angle()
		var w := deg_to_rad(tr.card.dummy_turn_degrees[i])
		for k in 2:
			var arm := tr.angles[i] + PI * k
			var diff := wrapf(a - arm, -PI, PI)
			if signf(diff) == signf(w) and absf(diff) < deg_to_rad(28.0):
				return true      # the arm reaches her within ~0.3 s
	return false


# ================================================================== Esc page
func test_pause_page() -> void:
	var pm: PauseMenu = g.pause_menu
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var p1: bool = pm.page == 0 and pm.tip_pages[0].visible and not pm.tip_pages[1].visible
	await r.tap(KEY_RIGHT)
	await r.process_frame
	await r.process_frame
	var rect := pm.panel.get_global_rect()
	var text := ""
	var clipped := ""
	for l in pm.sample_tip_labels:
		text += l.text
		if l.size.y + 0.5 < l.get_combined_minimum_size().y or not rect.grow(1).encloses(l.get_global_rect()):
			clipped += l.text.substr(0, 5) + " "
	var has_all := ["梅花桩试炼", "修缮", "铜钱", "存档", "放弃", "小食摊"].all(func(k): return k in text)
	r.check(p1 and pm.page == 1 and pm.tip_pages[1].visible and has_all and clipped == "" and Rect2(Vector2.ZERO, vp).encloses(rect),
		"sample AC9: Esc page tips page 2 (→) covers the trial, repairs, coins, the stall and saving; fits, nothing cut off", clipped)
	await r.tap(KEY_LEFT)
	var back: bool = pm.page == 0
	await r.tap(KEY_ESCAPE)
	r.check(back and not pm.is_open, "sample AC9: ← goes back to page 1; Esc closes")


# ================================================================== AC7 saving
func _reason(r_: String) -> bool:
	return r_ in SaveGame.last_reason.split("+")


func _saved_reasons() -> Array:
	var out := []
	for x in smp.saves:
		out.append_array(x.split("+"))
	return out


func _write_count() -> int:
	return SaveGame.writes


func test_save_triggers() -> void:
	var it: Interiors = g.interiors
	var got := {}
	# door: walk into the dorm and out again with the real keys
	var w0 := _write_count()
	await r.teleport(it.exit_spot("dorm_main") + Vector2(0, 4))
	var res: String = await nav.go_in("dorm_main")
	await r.frames(3)
	got["door in"] = _write_count() > w0 and _reason("door")
	w0 = _write_count()
	res = await nav.go_out("dorm_main")
	await r.frames(3)
	got["door out"] = _write_count() > w0 and _reason("door")
	# story progress (a conversation finishing)
	w0 = _write_count()
	await talk("crane")
	await r.frames(3)
	got["story"] = _write_count() > w0 and _reason("story")
	# trial end
	w0 = _write_count()
	await _start_trial_by_keys()
	var during := _write_count() == w0          # nothing is written while it runs
	smp.trial.abandon()
	await r.frames(3)
	got["trial"] = during and _write_count() > w0 and _reason("trial")
	# daily income
	w0 = _write_count()
	g.daynight.set_hour(7.9)
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	got["income"] = _write_count() > w0 and _reason("income")
	# repair: a fresh game where the roof is repaired
	r.check(got.values().all(func(v): return v), "sample AC7: a save is written at doors (in / out), story progress, the end of a trial and the daily income", str(got))
	r.check(SaveGame.path() == SaveGame.TEST_SLOT and SaveGame.exists(), "sample AC7: tests write only user://test_save.json (the player's slot is untouched)")
	r.check("repair" in _saved_reasons() and "unlock" in _saved_reasons(), "sample AC7: the repairs (and the unlock) were saved too", str(smp.saves))


## Deep compare of two captured states (floats within `tol`); "" when equal.
func _diff(a: Variant, b: Variant, path := "", tol := 0.02) -> String:
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) <= tol else "%s: %s != %s" % [path, a, b]
	if typeof(a) != typeof(b):
		return "%s: type %s != %s" % [path, typeof(a), typeof(b)]
	if a is Dictionary:
		var out := ""
		for k in a:
			if not b.has(k):
				out += "%s.%s missing; " % [path, k]
			else:
				out += _diff(a[k], b[k], "%s.%s" % [path, k], tol)
		for k in b:
			if not a.has(k):
				out += "%s.%s extra; " % [path, k]
		return out
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d != %d; " % [path, a.size(), b.size()]
		var out2 := ""
		for i in a.size():
			out2 += _diff(a[i], b[i], "%s[%d]" % [path, i], tol)
		return out2
	return "" if a == b else "%s: %s != %s; " % [path, a, b]


## The title screen (as the project's main scene) -> the selected / given button by key -> the game it starts.
func _title() -> TitleScreen:
	await _free_game()
	var t: TitleScreen = load("res://scenes/title.tscn").instantiate()
	r.root.add_child(t)
	r.current_scene = t
	await r.frames(3)
	return t


func _wait_game() -> Node:
	for i in 300:
		await r.process_frame
		if r.current_scene != null and is_instance_valid(r.current_scene) and r.current_scene.name == "Main":
			var m: Node = r.current_scene
			use_game(m)
			await r.frames(2)
			return m
	return null


func _observables() -> Dictionary:
	var it: Interiors = g.interiors
	return {"coins_label": smp.coin_label.text, "mouse": smp.mouse.visible, "board": board_visible(), "stall": smp.stall.visible,
		"roof_tex": smp.exterior_sprites["roof"].texture.resource_path, "kitchen_tex": smp.exterior_sprites["kitchen"].texture.resource_path,
		"dorm_tex": String(it.rooms["dorm_main"].get("tex", "")), "old_tex": String(it.rooms["dorm_old"].get("tex", "")),
		"kitchen_room": String(it.rooms["kitchen"].get("tex", "")), "drips": it.drips.list.size(), "room": it.room_at(p().global_position),
		"objective": g.hud.objective_label.text, "clock": g.daynight.clock_text(), "talk_mouse": story.talk_scene("mouse"),
		"book": SectBook.track_value(story.sect_book.data["tracks"][1], story.flags)}


func test_continue_restores() -> void:
	# the unlocked game: everything repaired, tiers, coins; now: indoors (old dorm), HP 73, 15:30, coins 42
	var it: Interiors = g.interiors
	g.daynight.running = false
	await r.teleport(it.exit_spot("dorm_old") + Vector2(0, 4))
	await nav.go_in("dorm_old")
	p().hp = 73
	g.daynight.set_hour(15.5)
	set_coins(42)
	await r.frames(2)
	smp.save_now("test")
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	var obs := _observables()
	# the title: 继续游戏 is enabled and selected first; Enter
	var t := await _title()
	var cont_ok: bool = not t.button("continue").disabled and t.selected == t.index_of("continue")
	await r.tap(KEY_ENTER)
	var mode := t.start_mode
	var m := await _wait_game()
	if m == null:
		r.check(false, "sample AC7: 继续游戏 enters the game")
		return
	g.daynight.running = false
	var snap2 := SaveGame.roundtrip(SaveGame.capture(g))
	var d := _diff(snap, snap2)
	r.check(cont_ok and mode == "continue", "sample AC7: with a save the title offers 继续游戏 (enabled, selected first)")
	r.check(d == "", "sample AC7: 继续游戏 restores a state equal to the saved snapshot (story, flags, coins, repairs, trial tiers, book, time, place, HP)", d)
	var obs2 := _observables()
	r.check(_diff(obs, obs2) == "", "sample AC7: and it looks the same (coin counter, 老周, board, stall, mended pictures, rooms, no drips, indoors, clock, talk, book)",
		_diff(obs, obs2))
	r.check(not story.busy and story.stage == 9 and p().hp == 73 and g.interiors.room_at(p().global_position) == "dorm_old" and smp.coins == 42,
		"sample AC7: no opening scene replays; she is in the old dorm with 73 HP and 42 coins")
	# the restored game plays on: walk out of the room (door), the trial board works
	var res: String = await nav.go_out("dorm_old")
	r.check(res == "door", "sample AC7: the restored game is playable (walks out through the door)")


func test_continue_mid_prologue() -> void:
	# a fresh game in the opening: take the rag, wipe once -> saved at a calm moment
	await _free_game()
	SaveGame.erase()
	await new_game()
	await finish_scene()
	var it: Interiors = g.interiors
	await stand_near(it.anchor("dorm_main", "rag"), [Vector2(0, 18), Vector2(18, 0), Vector2(-18, 0), Vector2(0, -18)])
	await r.tap(KEY_E)
	await finish_scene()
	await stand_near(it.anchor("dorm_main", "puddle"), [Vector2(0, 26), Vector2(26, 0), Vector2(-26, 0), Vector2(0, -26)])
	await r.tap(KEY_E)
	await r.frames(30)
	smp.save_now("test")
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	snap["dorm"]["water_level"] = 0.0      # the drips keep filling the bucket in real time
	var t := await _title()
	await r.tap(KEY_ENTER)
	var m := await _wait_game()
	if m == null:
		r.check(false, "sample AC7: 继续游戏 (mid-prologue) enters the game")
		return
	g.daynight.running = false
	var snap2 := SaveGame.roundtrip(SaveGame.capture(g))
	snap2["dorm"]["water_level"] = 0.0
	var d := _diff(snap, snap2)
	r.check(d == "" and story.flags.get("has_rag", false) and story.wipes == 1 and not g.interiors.rag_sprite.visible
		and g.interiors.bed_state == "empty" and not smp.unlocked and not any_true(sample_visible()) and not story.busy,
		"sample AC7: a mid-prologue save (rag taken, one wipe) restores the same gating state; nothing of the sample shows", d)
	# and the prologue goes on from there: two more wipes play S1-擦水渍
	await stand_near(g.interiors.anchor("dorm_main", "puddle"), [Vector2(0, 26), Vector2(26, 0), Vector2(-26, 0), Vector2(0, -26)])
	await r.tap(KEY_E)
	await r.frames(30)
	await r.tap(KEY_E)
	await r.frames(5)
	await finish_scene()
	r.check(story.flags.get("floor_wiped", false), "sample AC7: the restored prologue goes on (the third wipe finishes the floor)")


func test_new_game_confirm() -> void:
	var had := SaveGame.exists()
	var t := await _title()
	t.select(t.index_of("start"))
	await r.tap(KEY_ENTER)
	await r.frames(2)
	var asked: bool = t.confirm_open and t.confirm_box.visible and not t.starting
	await r.tap(KEY_ESCAPE)        # 取消
	await r.frames(2)
	var kept: bool = not t.confirm_open and SaveGame.exists() and not t.starting
	await r.tap(KEY_ENTER)
	await r.frames(2)
	var default_no: bool = t.confirm_selected == 1
	await r.tap(KEY_E)             # E on 取消 (the default)
	await r.frames(2)
	var kept2: bool = not t.confirm_open and SaveGame.exists() and not t.starting
	r.check(had and asked and kept and default_no and kept2, "sample AC7: 新游戏 with a save asks '会覆盖存档，确定吗？' (取消 first; Esc / 取消 keep the save)",
		"asked %s kept %s default %s kept2 %s" % [asked, kept, default_no, kept2])
	await r.tap(KEY_ENTER)
	await r.frames(2)
	await r.tap(KEY_LEFT)          # -> 确定
	await r.tap(KEY_E)
	var mode := t.start_mode
	var m := await _wait_game()
	r.check(m != null and mode == "new" and story.stage == 0 and story.current_scene == "S1-醒来" and not smp.unlocked and smp.coins == 0,
		"sample AC7: 确定 starts a new game from the opening (the old save is replaced)")
	r.check(not SaveGame.exists(), "sample AC7: the old save is gone once a new game is confirmed")
	var t2 := await _title()
	r.check(t2.button("continue").disabled and t2.selected == t2.index_of("start"), "sample AC7: without a save 继续游戏 is greyed out and skipped")
	await r.tap(KEY_UP)
	r.check(t2.selected != t2.index_of("continue"), "sample AC7: ↑ skips the greyed 继续游戏")


func _write_raw(text: String) -> void:
	var f := FileAccess.open(SaveGame.path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_broken_saves() -> void:
	var good := {}
	var cases := {"garbage": "{this is not json", "empty": "", "version": JSON.stringify({"game": SaveGame.GAME_ID, "version": 99, "state": {}}),
		"malformed": JSON.stringify({"game": SaveGame.GAME_ID, "version": SaveGame.VERSION, "state": {"story": {"stage": "nine"}}}),
		"bad values": JSON.stringify({"game": SaveGame.GAME_ID, "version": SaveGame.VERSION, "state": {"story": {}}})}
	for k in cases:
		_write_raw(cases[k])
		var t := await _title()
		var offered: bool = not t.button("continue").disabled
		await r.tap(KEY_ENTER)
		var m := await _wait_game()
		var ok: bool = m != null and offered and story.stage == 0 and story.busy and g.hud.toast.text == SaveGame.BROKEN_TEXT \
			and g.hud.toast.modulate.a > 0.5 and not SaveGame.exists()
		good[k] = ok
	r.check(good.values().all(func(v): return v), "sample AC7: a corrupt / empty / wrong-version / malformed save -> '存档无法读取，已重新开始', a fresh game, no hang; the bad file is set aside",
		str(good))
	var t3 := await _title()
	r.check(t3.button("continue").disabled, "sample AC7: after a bad save 继续游戏 is greyed out again")
	# a hand-made invalid value inside an otherwise good state is refused before anything is applied
	var st := SaveGame.capture(g) if g != null else {}
	await _free_game()
	if not st.is_empty():
		st["player"]["hp"] = -5
		r.check(SaveGame.validate(SaveGame.roundtrip(st)) != "", "sample AC7: invalid values (HP -5) are refused by the check")
