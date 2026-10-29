extends RefCounted
## 新手指引 + 任务面板 v1 checks (task packet AC1-AC8), run by tests/run_tests.gd, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-guide   (--g=name,name for some)
## Real keys (E / 1-4 / Q / Esc / ←→↑↓ / J / Space / WASD) and real physics wherever the player does something; state is set
## directly only for starting points (the clock, coins, earlier steps already paid, a seed) - never for the result checked.

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
var only: Array = []
var report := {}


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
		if String(a).begins_with("--g="):
			only = String(a).trim_prefix("--g=").split(",")
	ss = load("res://tests/sample_suite.gd").new(r)
	t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	s4 = load("res://tests/step4a_suite.gd").new(r)
	s4.ss = ss
	s4.t3 = t3
	var tests := ["tables", "ending", "same_day", "step1", "step2", "step3", "step4", "step5", "order", "hidden", "once",
		"board_keys", "tabs", "tracking", "layout", "save", "upgrade", "esc_keys"]
	for name in tests:
		if only.is_empty() or name in only:
			await call("test_" + name)
	await ss._free_game()
	SaveGame.erase()
	print("GUIDE REPORT ", report)


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


func p() -> Player:
	return g.player


func game(day_idx := 0) -> void:
	await t3.unlocked_game(day_idx)
	bind()
	await r.frames(3)


func finish() -> void:
	await ss.finish_scene()


func walk(to: Vector2, limit := 120.0) -> String:
	return await s4.walk(to, limit)


## Earlier steps already done and paid (a starting point for a later step's own check).
func steps_paid_before(i: int) -> void:
	for k in i:
		gd.done[k] = true
		gd.paid[k] = true


func coins_for(what: String) -> int:
	var n := 0
	for pmt in gd.payments:
		if String(pmt["what"]) == what:
			n += int(pmt["coins"])
	return n


## A spar with 师兄 by real keys (E at him -> 切磋) fought by a bot (试玩反馈 v1: the GP bot) until the result closes.
func senior_spar(kind := "gp") -> Dictionary:
	var c: Combat = g.combat
	var fox: Fighter = story._npc("fox")
	await walk(fox.global_position + Vector2(0, 30))
	await r.tap(KEY_E)
	for i in 300:
		if c.spar_state == "choosing":
			break
		if dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.tap(KEY_1)
	var hint := false
	t3.cs._dodged_for = {}
	t3.cs._gp_for = {}
	for i in 60 * 90:
		if c.spar_state != "fighting":
			break
		if gd.hint_label.visible:
			hint = true
		t3.cs.bot_step(kind)
		await r.physics_frame
	t3.cs._release()
	r.release_all()
	var win := c.last_spar_win
	for i in 400:
		if c.spar_state == "none":
			break
		await r.physics_frame
	await r.frames(3)
	return {"win": win, "hint": hint}


func open_board() -> bool:
	await r.tap(KEY_Q)
	await r.process_frame
	return qb.is_open


func close_board() -> void:
	if qb.is_open:
		await r.tap(KEY_Q)
	await r.process_frame


# ================================================================== AC: data = the plan
func test_tables() -> void:
	Guide._data = {}
	var d := Guide.load_data()
	var rewards: Array = (d["steps"] as Array).map(func(s): return int(s["reward"]))
	var ids: Array = (d["steps"] as Array).map(func(s): return String(s["id"]))
	var total: int = rewards.reduce(func(a, x): return a + x, 0) + int(d["graduate_reward"])
	var line := String(d["scenes"]["G-师父-开始"][0]["text"])
	r.check(rewards == [10, 10, 15, 5, 10] and int(d["graduate_reward"]) == 10 and total == 60 and ids == Guide.STEP_IDS
		and String(d["book"]) == "新手指引·出师" and line == "先把门里的事摸熟，有不懂的按 Q 看看。" and String(d["ui"]["prologue_caption"]) == "序章 · 完"
		and is_equal_approx(float(d["caption_seconds"]), 2.0) and (d["board"]["tabs"] as Array) == ["新手指引", "悬赏", "委托", "修缮", "比武", "收徒"]
		and String(d["spar_hint"]) == "看到师兄发红、头上冒“!” → 按 K（或鼠标右键）格挡 → 自动反击" and d.has("_说明") and not bool(d["hidden_default"])
		and String(d["steps"][0]["todo"]) == "和师兄切磋：格挡（GP）成功一次，再赢下切磋" and String(d["steps"][0]["objective"]).contains("格挡（GP）成功一次"),
		"guide: data/guide.json = the plan (rewards 10/10/15/5/10, 出师 10, 60 in all; 师父's line; caption 序章 · 完 ~2 s; 6 tabs; the spar hint; 门派簿 新手指引·出师; 试玩反馈 v1: step 1 = 格挡（GP）成功一次，再赢下切磋, the GP key hint)",
		str([rewards, total]))
	# every text the guide / board / captions can show is in the data file (ready for another language), none in the code
	var code := FileAccess.get_file_as_string("res://scripts/guide.gd") + FileAccess.get_file_as_string("res://scripts/quest_board.gd")
	var quoted := RegEx.create_from_string("\"[^\"\\n]*[\\x{4e00}-\\x{9fff}][^\"\\n]*\"")
	var hits := []
	for line_ in code.split("\n"):
		if line_.strip_edges().begins_with("#"):
			continue
		for m in quoted.search_all(line_):
			hits.append(m.get_string())
	r.check(hits.is_empty(), "guide: no player-visible Chinese text is written in scripts/guide.gd / quest_board.gd - all of it is in data/guide.json with {placeholders}", str(hits))
	var font: Font = load("res://fonts/ui_font.fnt")
	var missing := ""
	for ch in FileAccess.get_file_as_string("res://data/guide.json") + PauseMenu.all_text():
		if ch.unicode_at(0) > 0x7f and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	r.check(missing == "", "guide: every new character is in the UI font", missing)
	var lines := ""
	for k in d["ui"]:
		lines += String(d["ui"][k])
	for sc in d["scenes"]:
		for e in d["scenes"][sc]:
			lines += String(e.get("text", ""))
	lines += JSON.stringify(d["board"]) + JSON.stringify(d["steps"])
	r.check(not ("她" in lines) and not ("师姐" in lines), "guide: no line calls the hero 她 / 师姐")


# ================================================================== AC1 the new ending (real keys)
func test_ending() -> void:
	await ss.new_game()
	bind()
	await finish()
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		story.flags[f] = true
	story.set_stage(8)
	# the prologue ends before the 委托 refresh hour (08:00). 坐下与人物作息 v1: 07:00, not 06:00 - 师兄 (step 1's arrow) is up at 07:00
	g.daynight.restore(7.0, 7.0)
	var saves0 := smp.saves.size()
	await ss.stand_near(story._npc("crane").global_position)
	await r.tap(KEY_E)
	var page := false
	var cap_at := -1
	var cap_gone := -1
	var frame := 0
	var held_during_caption := []
	for i in 1500:
		if story.prologue_end.is_open:
			page = true
		if gd.caption_showing() and gd.caption_label.text == "序章 · 完" and cap_at < 0:
			cap_at = frame
		elif cap_at >= 0 and cap_gone < 0 and not gd.caption_showing():
			cap_gone = frame
		if story.sect_book.is_open:
			await r.tap(KEY_ESCAPE)
			frame += 4
		elif dlg.active:
			if cap_at >= 0 and dlg.full_text == "先把门里的事摸熟，有不懂的按 Q 看看。":
				held_during_caption.append(gd.caption_showing())
			await r.tap(KEY_E)
			frame += 4
		elif cap_gone >= 0 and not story.busy and not gd._intro_pending:
			break
		else:
			await r.physics_frame
			frame += 1
	await r.frames(3)
	var secs := float(cap_gone - cap_at) / 60.0
	# 坐下与人物作息 v1: 老周 is opened (one of the NPCs) but asleep until 08:00 - test_same_day sees him there at 08:00
	var open_all: bool = smp.unlocked and g.npcs.has(smp.mouse) and (smp.mouse.visible or g.schedule.absent("mouse")) and smp.trial.board.visible and smp.trial.pole_layer.visible and smp.coin_panel.visible \
		and smp.coins == 30 and s3.arena.board.visible and jh.board.visible and story.talk_scene("mouse") == "X-老周-修屋顶" \
		and story.talk_scene("dog") == "X-老伯-旧弟子房" and story.talk_scene("bear") == "X-厨娘-修厨房" and story.talk_scene("crane") == "X-师父-两条路"
	var obj: String = g.hud.objective_label.text
	r.check(not page and cap_at >= 0 and secs > 1.6 and secs < 2.6, "guide AC1: the last line goes straight on - no 序章 · 完 page, no 回到启动画面 / 继续逛逛; the caption 「序章 · 完」 fades in and out by itself (%.2f s)" % secs)
	r.check(open_all, "guide AC1: everything 继续逛逛 used to open is open: 本钱 30, 老周, the trial board + poles, the coin counter, the 比武 board, the 江湖告示榜, the repair / 两条路 talks")
	r.check(story.played.has("G-师父-开始") and obj == "目标：" + String(Guide.load_data()["steps"][0]["objective"]) and not ("序章完成" in obj)
		and g.hud.minimap.track_active and gd.track == "guide" and gd.started,
		"guide AC1: 师父 says '先把门里的事摸熟，有不懂的按 Q 看看。'; the objective line shows guide step 1 (never 序章完成); the gold arrow shows", obj)
	var arrow_ok: bool = absf(angle_difference(g.hud.minimap.track_angle(), (story._npc("fox").global_position - p().global_position).angle())) < 0.05 \
		or not g.hud.minimap.track_on_rim
	r.check(arrow_ok and g.hud.minimap.track_world.distance_to(story._npc("fox").global_position) < 1.0 or g.interiors.room_at(story._npc("fox").global_position) != "",
		"guide AC1: the gold arrow points at 师兄 (step 1 - the 练武场)")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	r.check(smp.saves.size() > saves0 and smp.saves.any(func(x): return "unlock" in String(x).split("+")) and doc is Dictionary and int(doc["version"]) == SaveGame.VERSION
		and bool(doc["state"]["sample"]["unlocked"]) and bool(doc["state"]["guide"]["started"]),
		"guide AC1: the save is written at once (version %d: unlocked, the guide started)" % SaveGame.VERSION)
	report["ending_caption_s"] = secs


func test_same_day() -> void:
	# continue from the 06:00 ending above (a fresh game ended at 06:00 the same way)
	if g == null or not is_instance_valid(g) or not smp.unlocked:
		await test_ending()
	var day := jh.cal_day()
	var n0: int = jh.com.offers.size()
	var draws0: int = jh.com.draws
	var hour0: float = g.daynight.hour
	await t3.advance_to(8.0)
	await r.frames(int(g.schedule._fade_secs() * 60.0) + 8)
	var same := jh.cal_day() == day and jh.com.draws == draws0 and jh.com.offers.size() == 2 and smp.mouse.visible
	await t3.advance_to(7.0)
	var next_morning: bool = jh.com.offers.is_empty()
	await t3.advance_to(8.0)
	r.check(hour0 < 8.0 and n0 == 2 and same and next_morning and jh.com.offers.size() == 2,
		"guide AC3: the prologue ended at %02d:00 and the board already has today's 2 委托 (step 5 never waits); 08:00 the same day draws nothing new (and 老周 is up); the next day goes by the normal 08:00 rule" % int(hour0))


# ================================================================== AC2 each step by real keys
func test_step1() -> void:
	await game()
	var c0 := smp.coins
	# 试玩反馈 v1: a win without any GP (dodge + chase only) does not finish step 1
	var res0 := await senior_spar("chase")
	var tries0 := 1
	while not res0["win"] and tries0 < 4:
		res0 = await senior_spar("chase")
		tries0 += 1
	await r.frames(3)
	var not_yet: bool = res0["win"] and not gd.countered and not gd.spar_won and not gd.paid[0] and smp.coins == c0
	var res := await senior_spar("gp")
	var tries := 1
	while not gd.paid[0] and tries < 4:
		res = await senior_spar("gp")
		tries += 1
	await r.frames(3)
	r.check(not_yet, "guide AC2 step 1 (试玩反馈 v1): a spar won without a GP (dodge + chase bot) does not finish step 1", str([res0, tries0, gd.countered]))
	r.check(res["hint"] and gd.countered and gd.spar_won and gd.paid[0] and coins_for("combat") == 10 and smp.coins == c0 + 10
		and "指引完成：战斗  +10 文" in gd.captions and gd.current() == 1,
		"guide AC2 step 1: a 师兄 spar by real keys (E, 切磋, the bot presses K at his blows) shows the key hint '看到师兄发红…按 K', a GP + a win -> '指引完成：战斗  +10 文' (10 文); the guide moves to step 2",
		str([res, tries, gd.countered, gd.spar_won, smp.coins - c0]))
	var obj: String = g.hud.objective_label.text
	r.check(obj == "目标：" + String(Guide.load_data()["steps"][1]["objective"]), "guide AC2: the objective line now shows step 2", obj)


func test_step2() -> void:
	await game()
	steps_paid_before(1)
	var c0 := smp.coins
	var tr: PlumTrial = smp.trial
	await ss._start_trial_by_keys()
	var frames := 0
	while tr.state == "running" and frames < 70 * 60:
		var goal: Vector2 = tr.step_point(tr.current)
		var to := goal - p().global_position
		r.hold_dir(to.normalized() if to.length() > 2.0 else Vector2.ZERO)
		if p().dash_cooldown_left <= 0.0 and not p().is_dashing() and ss._arm_threat(tr):
			r.key(KEY_SPACE, true)
			await r.physics_frame
			r.key(KEY_SPACE, false)
		await r.physics_frame
		frames += 1
	r.release_all()
	var medal := tr.last_result
	await ss._wait_trial_idle()
	await r.frames(5)
	var trial_coins := Economy.trial_reward("bronze") * int(story.flags.get("trial_bronze", false)) + Economy.trial_reward("silver") * int(story.flags.get("trial_silver", false)) \
		+ Economy.trial_reward("gold") * int(story.flags.get("trial_gold", false))
	r.check(medal in ["bronze", "silver", "gold"] and gd.paid[1] and coins_for("trial") == 10 and smp.coins == c0 + trial_coins + 10
		and "指引完成：梅花桩试炼  +10 文" in gd.captions,
		"guide AC2 step 2: a 梅花桩 run by real keys reaches a medal (%s) -> +10 文 on top of the trial's own reward" % medal, "%d -> %d" % [c0, smp.coins])


func test_step3() -> void:
	await game()
	steps_paid_before(2)
	ss.set_coins(40)
	var played: Array = await ss.talk("mouse", KEY_1)
	await r.frames(5)
	r.check(smp.is_repaired("roof") and gd.paid[2] and coins_for("repair") == 15 and smp.coins == 40 - 30 + 15 and "指引完成：修缮  +15 文" in gd.captions,
		"guide AC2 step 3: 老周 by real keys (E, 是): the roof is repaired (-30) -> +15 文 (40 -> 25)", str([played, smp.coins]))


func test_step4() -> void:
	await game()
	steps_paid_before(3)
	var c0 := smp.coins
	var played: Array = await ss.talk("bear", KEY_2)
	await r.frames(5)
	r.check(played.size() > 0 and String(played[0]).begins_with("X-厨娘") and not smp.is_repaired("kitchen") and gd.paid[3] and coins_for("stall") == 5
		and smp.coins == c0 + 5,
		"guide AC2 step 4: talking with 厨娘 (real keys; 否 - nothing repaired) about the stall and its daily income -> +5 文", str(played))


func test_step5() -> void:
	await game()
	steps_paid_before(4)
	# today's two offers with 送信 among them (a starting point: the seed)
	var d: int = jh.cal_day()
	jh.seed = s4.seed_for("letter", d)
	jh.com.offers = jh.com.draw(d)
	var c0 := smp.coins
	var ok_acc: bool = await s4.accept_commission("letter")
	var tn: Npc = story._npc("tanuki")
	await walk(tn.global_position + Vector2(0, 26))
	await r.tap(KEY_E)
	await finish()
	var dog: Npc = story._npc("dog")
	await walk(dog.global_position + Vector2(0, 26))
	await r.tap(KEY_E)
	await finish()
	var pay: Array = await s4.turn_in_commission("letter")
	await r.frames(3)
	var not_yet: bool = not gd.paid[4]
	var target_arena: bool = gd.target_of("guide") == s3.arena.board_point()
	await walk(s3.arena.board_point() + Vector2(0, 6))
	await r.tap(KEY_E)
	await finish()
	await r.frames(5)
	var bk: Array = await t3.book_open_lines()
	r.check(ok_acc and pay[0] == 8 and not_yet and target_arena and gd.arena_seen and gd.paid[4] and coins_for("board") == 10,
		"guide AC2 step 5: a 委托 accepted and turned in by real keys (送信 8 文) - not yet done; the arrow moves to the 比武 board; E there -> +10 文",
		str([ok_acc, pay[0], not_yet, target_arena]))
	r.check(gd.graduated and coins_for("graduate") == 10 and smp.coins == c0 + 8 + 10 + 10 and "新手指引·出师  +10 文" in gd.captions
		and "新手指引·出师" in bk[1] and gd.track == "adv"
		and g.hud.objective_label.text == "目标：" + String(Guide.load_data()["advanced"]["steps"][0]["objective"]) and g.hud.minimap.track_active,
		"guide AC2: all five done -> 出师 +10 文, 门派簿 '新手指引·出师'; (武学与经营 第一批: the guide goes on with 进阶 1/4 - its objective line and the gold arrow, instead of nothing tracked)", str(bk[1]))


## Out of order: step 3 done first (real keys) is not paid while step 1 is the current one; it is paid when its turn comes.
func test_order() -> void:
	await game()
	ss.set_coins(40)
	await ss.talk("mouse", KEY_1)
	await r.frames(5)
	var early: bool = smp.is_repaired("roof") and gd.done[2] and not gd.paid[2] and gd.current() == 0 and smp.coins == 10
	# steps 1 and 2 done (starting point: their conditions)
	gd.dodged = true
	gd.countered = true
	gd.spar_won = true
	story.flags["trial_bronze"] = true
	await r.frames(5)
	r.check(early and gd.paid[0] and gd.paid[1] and gd.paid[2] and smp.coins == 10 + 10 + 10 + 15 and gd.current() == 3
		and gd.payments.map(func(x): return x["what"]) == ["combat", "trial", "repair"],
		"guide AC2: a step done early (the roof first) is not paid out of turn; when steps 1 and 2 are done it is paid right after them (10 + 10 + 15, in order)",
		str(gd.payments))


## The guide switched off in the board (real keys): no objective / arrow; finished steps are still paid (at once).
func test_hidden() -> void:
	await game()
	await open_board()
	var items: Array = gd.tabs()[0]["items"]
	for i in items.size() - 1:
		await r.tap(KEY_DOWN)
	await r.tap(KEY_E)
	await close_board()
	await r.frames(3)
	var off: bool = gd.hidden and gd.track == "" and g.hud.objective_label.text == "" and not g.hud.objective.visible and not g.hud.minimap.track_active
	var c0 := smp.coins
	await ss.talk("bear", KEY_2)
	await r.frames(5)
	r.check(off and gd.paid[3] and smp.coins == c0 + 5 and gd.hint_label.visible == false,
		"guide AC2: 关闭指引 in the 任务面板 (real keys: ↓ to it, E): the objective line and the arrow go; a step finished afterwards (厨娘, step 4, out of order) is still paid at once (+5)",
		str([gd.hidden, gd.track, g.hud.objective_label.text]))
	await open_board()
	for i in items.size() - 1:
		await r.tap(KEY_DOWN)
	await r.tap(KEY_E)
	await close_board()
	await r.frames(3)
	r.check(not gd.hidden and gd.track == "guide" and g.hud.objective.visible, "guide: 打开指引 brings the objective line back")


func test_once() -> void:
	await game()
	steps_paid_before(3)
	await ss.talk("bear", KEY_2)
	await r.frames(5)
	var c1 := smp.coins
	await ss.talk("bear", KEY_2)
	await r.frames(5)
	smp.save_now("test")
	await s4.reload_game()
	bind()
	await r.frames(10)
	r.check(smp.coins == c1 and gd.paid[3] and coins_for("stall") == 0,
		"guide AC2: each step pays once - talking to 厨娘 again, saving and loading pay nothing more", str(gd.payments))


# ================================================================== AC4 the board
func test_board_keys() -> void:
	await ss.new_game()
	bind()
	await finish()
	await r.tap(KEY_Q)
	await r.process_frame
	var prologue_no: bool = not qb.is_open
	await game()
	var opened := await open_board()
	var paused: bool = r.paused
	await r.tap(KEY_Q)
	await r.process_frame
	var q_closed: bool = not qb.is_open and not r.paused
	await open_board()
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	await r.process_frame
	var esc_closed: bool = not qb.is_open and not g.pause_menu.is_open and not r.paused
	r.check(prologue_no and opened and paused and q_closed and esc_closed,
		"guide AC4: during the prologue Q does nothing; afterwards Q opens the 任务面板 (the game pauses), Q closes it, Esc closes it too (and does not open the Esc page)",
		str([prologue_no, opened, paused, q_closed, esc_closed]))
	# not during a conversation, a spar, the trial; the Esc page keeps its own Q (放弃试炼)
	await ss.stand_near(story._npc("crane").global_position)
	await r.tap(KEY_E)
	await r.frames(3)
	await r.tap(KEY_Q)
	var in_dialogue: bool = not qb.is_open and story.busy
	await finish()
	await ss._start_trial_by_keys()
	await r.tap(KEY_Q)
	var in_trial: bool = not qb.is_open and smp.trial.state == "running"
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var esc_open: bool = g.pause_menu.is_open and g.pause_menu.abandon_button.visible
	await r.tap(KEY_Q)
	await r.frames(3)
	var abandoned: bool = not g.pause_menu.is_open and smp.trial.state != "running" and not qb.is_open
	await ss._wait_trial_idle()
	var fox: Fighter = story._npc("fox")
	await walk(fox.global_position + Vector2(0, 30))
	await r.tap(KEY_E)
	for i in 200:
		if g.combat.spar_state == "choosing":
			break
		if dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.tap(KEY_1)
	await r.frames(10)
	await r.tap(KEY_Q)
	var in_spar: bool = not qb.is_open and g.combat.spar_state == "fighting"
	r.check(in_dialogue and in_trial and esc_open and abandoned and in_spar,
		"guide AC4: Q does not open it during a conversation, the 梅花桩 trial or a spar; with the Esc page open during the trial Q is the page's 放弃 (the trial ends, the board stays shut)",
		str([in_dialogue, in_trial, esc_open, abandoned, in_spar]))
	g.combat.end_spar(false)
	await r.frames(200)


## The tabs follow the real state.
func test_tabs() -> void:
	await game()
	t3.set_day(1, 9.0)
	await r.frames(3)
	var tx := func(tab: int) -> String:
		return "\n".join((gd.tabs()[tab]["items"] as Array).map(func(it): return String(it["text"]).replace("\n", " / ") + "|" + String(it["state"])))
	# an item line of a tab holding all the given parts
	var has := func(tab: int, parts: Array) -> bool:
		for line in String(tx.call(tab)).split("\n"):
			if parts.all(func(x): return String(x) in line):
				return true
		return false
	var res := {}
	res["bounty_locked"] = "下一条悬赏：第 2 天辰时上榜|locked" in tx.call(1)
	t3.set_day(2, 9.0)
	await r.frames(3)
	res["bounty_offer"] = "悬赏：偷鸡的黄鼠狼 · 山路草丛 · 榜上可接 · 赏 20 文，名望 +1" in tx.call(1)
	await s4.accept_bounty()
	res["bounty_taken"] = "悬赏：偷鸡的黄鼠狼 · 山路草丛 · 已接，未打赢 · 赏 20 文，名望 +1|current" in tx.call(1)
	res["com_open"] = Array(String(tx.call(2)).split("\n")).filter(func(l): return "可接（去村口告示榜）" in l and l.ends_with("|open")).size() == 2 \
		and "累计完成 0 条 · 家业进度 0/5" in tx.call(2)
	var k := String(jh.com.offers[0]["kind"])
	await s4.accept_commission(k)
	res["com_taken"] = "进行中：" in tx.call(2)
	jh.com.find_taken(k)["step"] = Commission.LAST_STEP[k]
	res["com_ready"] = has.call(2, ["办妥了，回告示榜交差", "|current"])
	await s4.turn_in_commission(k)
	res["com_done"] = has.call(2, ["已交差", "|done"]) and "累计完成 1 条 · 家业进度 1/5" in tx.call(2)
	res["repair_open"] = "修缮：宿舍屋顶 · 找老周（宿舍门口） · 30 文 · 家业 +1|open" in tx.call(3)
	ss.set_coins(40)
	await ss.talk("mouse", KEY_1)
	res["repair_done"] = "修缮：宿舍屋顶 · 已修好|done" in tx.call(3)
	res["arena_next"] = "比武大会：第 3 天午时报名 · 村口擂台告示牌 · 报名费 10 文" in tx.call(4)
	t3.set_day(3, 13.0)
	await r.frames(2)
	res["arena_open"] = "比武大会：今天报名中（午时至酉时）" in tx.call(4)
	res["disciple_need"] = "收徒：旧弟子房 未整理（找看门老伯） · 名望 1/5" in tx.call(5)
	story.flags["repair_dorm_old"] = true
	s3.disciple.state = "joined"
	res["disciple_joined"] = "师弟：还没派活 · 每天伙食费 5 文|done" in tx.call(5)
	res["guide_marks"] = tx.call(0).begins_with("▶ 1. 战斗（+10 文）")
	r.check(res.values().all(func(v): return v), "guide AC4: the 6 tabs follow the game: 悬赏 locked -> on the board -> taken; 委托 open / taken / ready / turned in + x/5; 修缮 price + who -> repaired; 比武 next date -> open today; 收徒 what is missing -> 师弟's job; the guide's current step",
		str(res))
	report["tabs_sample"] = tx.call(1) + "\n" + tx.call(2)


func test_tracking() -> void:
	await game()
	ss.set_coins(40)
	# PM fix: every guide step shares the key "guide" - only the current step may wear 【追踪中】 (the 新手指引 tab
	# used to mark all five) - and the toast is drawn under the long guide objective line, never over it
	await open_board()
	var gmarks := []
	for i in qb.item_labels.size():
		if qb.item_labels[i].text.begins_with("【追踪中】"):
			gmarks.append(i)
	await close_board()
	r.check(gd.track == "guide" and gmarks == [gd.current()],
		"guide AC4: on the 新手指引 tab only the current step shows 【追踪中】", str([gd.track, gmarks, gd.current()]))
	g.hud.show_toast("师父给的本钱：铜钱 +30")
	await r.frames(3)
	var tr: Rect2 = g.hud.toast_text_rect()
	var orr: Rect2 = g.hud.objective.get_global_rect()
	r.check(g.hud.objective.visible and not tr.intersects(orr), "guide AC5: a toast never covers the guide's objective line",
		str([tr, orr]))
	await open_board()
	for i in 3:
		await r.tap(KEY_RIGHT)          # 修缮
	await r.tap(KEY_E)               # track the roof
	var tracked: bool = gd.track == "repair:roof"
	await close_board()
	await r.frames(3)
	var obj: String = g.hud.objective_label.text
	var aim: bool = g.hud.minimap.track_active and g.hud.minimap.track_world.distance_to(smp.mouse.global_position) < 1.0
	await ss.talk("mouse", KEY_1)
	await r.frames(5)
	r.check(tracked and obj == "目标：修缮：宿舍屋顶 · 找老周" and aim and gd.track == "guide"
		and g.hud.objective_label.text == "目标：" + String(Guide.load_data()["steps"][0]["objective"]),
		"guide AC4: E on 修缮·宿舍屋顶 tracks it: the objective line says '修缮：宿舍屋顶 · 找老周', the gold arrow points at 老周; once the roof is repaired tracking goes back to the guide",
		str([tracked, obj, aim, gd.track]))
	# one at a time: tracking 比武 replaces it; the board shows 【追踪中】 on that item only
	await open_board()
	await r.tap(KEY_LEFT)
	await r.tap(KEY_LEFT)
	await r.tap(KEY_LEFT)            # 比武 (tab 4) - 武学与经营 第一批: a 7th tab (武学) now sits last, so from tab 0 it
	                                 # takes three ← round the end (7 -> 6 -> 5 -> 4) instead of two; still real keys
	await r.tap(KEY_E)
	var marks := 0
	for l in qb.item_labels:
		if l.text.begins_with("【追踪中】"):
			marks += 1
	await close_board()
	r.check(gd.track == "arena" and marks == 1, "guide AC4: only one item is tracked at a time (【追踪中】 on it only)", gd.track)


# ================================================================== AC5 layout
func fill_everything() -> void:
	t3.set_day(2, 9.0)
	await r.frames(3)
	await s4.accept_bounty()
	for o in jh.com.offers:
		o["state"] = "taken"
	jh.com.offers[0]["step"] = Commission.LAST_STEP[String(jh.com.offers[0]["kind"])]
	jh.com.total = 23
	gd.dodged = true
	await r.frames(3)


func test_layout() -> void:
	await game()
	await fill_everything()
	var bad := []
	var stats := {}
	for w in [Vector2i(1440, 810), Vector2i(640, 360), Vector2i(1000, 560)]:
		r.root.size = w
		for i in 4:
			await r.process_frame
		var vp: Vector2 = g.get_viewport().get_visible_rect().size
		var scr := Rect2(Vector2.ZERO, vp)
		await open_board()
		for tab in 6:
			qb._set_tab(tab)
			var n: int = qb.items().size()
			for item in n:
				qb._set_sel(item)
				await r.process_frame
				var pr: Rect2 = qb.panel.get_global_rect()
				if not scr.encloses(pr):
					bad.append("%s panel %s" % [w, pr])
				var lr: Rect2 = qb.list_box.get_global_rect()
				for pair in qb.shown_rects():
					var rr: Rect2 = pair[1]
					if not pr.grow(0.5).encloses(rr):
						bad.append("%s tab %d '%s' %s" % [w, tab, String(pair[0]).substr(0, 8), rr])
				for i in qb.item_panels.size():
					var ip: PanelContainer = qb.item_panels[i]
					if ip.visible and (ip.get_global_rect().end.y > lr.end.y + 0.5 or qb.item_labels[i].get_line_count() * 1 < 1):
						bad.append("%s tab %d item %d below the list %s" % [w, tab, i, ip.get_global_rect()])
					if ip.visible and qb.item_labels[i].get_combined_minimum_size().y > ip.size.y + 0.5:
						bad.append("%s tab %d item %d cut" % [w, tab, i])
				if not (qb.pages[qb.page] as Array).has(item):
					bad.append("%s tab %d item %d not on its page" % [w, tab, item])
			stats["%dx%d tab%d" % [w.x, w.y, tab]] = qb.pages.size()
		await close_board()
	# a window change while the board is open: laid out again
	r.root.size = Vector2i(1440, 810)
	for i in 4:
		await r.process_frame
	await open_board()
	var before: Rect2 = qb.panel.get_global_rect()
	r.root.size = Vector2i(1000, 560)
	for i in 4:
		await r.process_frame
	var after: Rect2 = qb.panel.get_global_rect()
	var vp2: Vector2 = g.get_viewport().get_visible_rect().size
	var relaid: bool = after != before and Rect2(Vector2.ZERO, vp2).encloses(after) and qb.shown_rects().all(func(x): return after.grow(0.5).encloses(x[1]))
	await close_board()
	r.root.size = Vector2i(1440, 810)
	for i in 4:
		await r.process_frame
	report["board_pages"] = stats
	r.check(bad.is_empty(), "guide AC5: at 480x270, 640x360 and 500x280, with every tab as full as it gets (bounty taken, both 委托 taken, 23 委托 done, all steps listed), every item of every tab - shown page by page, font unchanged - stays inside the panel and the panel on the screen",
		str(bad.slice(0, 10)))
	r.check(relaid, "guide AC5: the window changes size while the board is open -> laid out again, still inside the screen", str([before, after]))
	# the spar hint and the captions on the real screen
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	gd.hint_label.visible = true
	await r.process_frame
	var hr: Rect2 = gd.hint_label.get_global_rect()
	var hf: Font = gd.hint_label.get_theme_font("font")
	var hw := hf.get_string_size(gd.hint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	gd.hint_label.visible = false
	r.check(Rect2(Vector2.ZERO, vp).encloses(hr) and hw <= vp.x - 8.0, "guide AC5: the step-1 key hint fits the 480x270 screen", str([hr, hw]))


# ================================================================== AC6 saving
func test_save() -> void:
	await game()
	gd.dodged = true
	await ss.talk("bear", KEY_2)
	ss.set_coins(40)
	await ss.talk("mouse", KEY_1)
	gd.set_track("arena")
	gd.set_hidden(false)
	await r.frames(5)
	smp.save_now("test")
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	var c0 := smp.coins
	await s4.reload_game()
	bind()
	await r.frames(5)
	var snap2 := SaveGame.roundtrip(SaveGame.capture(g))
	var d: String = ss._diff(snap["guide"], snap2["guide"])
	r.check(d == "" and snap["guide"]["track"] == "arena" and snap["guide"]["dodged"] and snap["guide"]["bear_talked"] and smp.coins == c0
		and ss._diff(snap, snap2) == "",
		"guide AC6: the guide state (steps done / paid, step-1 marks, 厨娘 talked, tracked item) saves as version %d and comes back equal; no coins move on loading" % SaveGame.VERSION, d)
	var st := snap.duplicate(true)
	st["guide"]["paid"] = [true, false]
	var bad1 := SaveGame.validate(st) != ""
	st = snap.duplicate(true)
	st["guide"]["paid"][4] = true
	var bad2 := SaveGame.validate(st) != ""
	st = snap.duplicate(true)
	st.erase("guide")
	r.check(bad1 and bad2 and SaveGame.validate(st) != "", "guide AC6: a save with a broken guide section (wrong length, paid but not done, missing) is refused")


func test_upgrade() -> void:
	# a version-4 save (the current state without the guide) with the roof repaired, a trial medal and 2 委托 done
	await game()
	ss.set_coins(40)
	await ss.talk("mouse", KEY_1)
	story.flags["trial_silver"] = true
	jh.com.total = 2
	await r.frames(3)
	gd.done = [false, false, false, false, false]
	gd.paid = [false, false, false, false, false]
	gd.payments.clear()
	smp.save_now("test")
	var cur = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	var v4 = cur.duplicate(true)
	v4["version"] = 4
	v4["state"].erase("guide")
	await ss._free_game()
	ss._write_raw(JSON.stringify(v4))
	await s4.reload_game()
	bind()
	var c_loaded := smp.coins
	await r.frames(20)
	var up_ok: bool = gd.started and gd.done == [false, true, true, false, true] and gd.paid == [false, true, true, false, true] \
		and gd.payments.is_empty() and smp.coins == c_loaded and smp.coins == int(v4["state"]["sample"]["coins"]) and gd.current() == 0
	r.check(up_ok, "guide AC6: a version-4 save upgrades: the steps it already meets (trial medal, roof, a 委托 done) count as done - and no coins are paid for them",
		str([gd.done, gd.paid, gd.payments, smp.coins]))
	# then step 1 (+ the 厨娘 talk) are paid normally; 出师 comes when the rest is done, still no coins for the old ones
	gd.dodged = true
	gd.countered = true
	gd.spar_won = true
	gd.arena_seen = true
	await ss.talk("bear", KEY_2)
	await r.frames(5)
	r.check(gd.paid.all(func(x): return x) and gd.graduated and smp.coins == c_loaded + 10 + 5 + 10,
		"guide AC6: after the upgrade only the steps done afterwards pay (战斗 10 + 小食摊 5) and 出师 10", str(gd.payments))
	# v1 (a real 第②步 save), v2 and v3: they load and save as version 5
	var ok := {}
	await ss._free_game()
	ss._write_raw(FileAccess.get_file_as_string("res://tests/fixtures/step2_save_v1.json"))
	await s4.reload_game()
	bind()
	await r.frames(10)
	ok["v1"] = smp.unlocked and gd.started and gd.paid[2] and gd.payments.is_empty() and smp.coins == 30
	smp.save_now("test")
	var cur2 = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	ok["v1_written"] = int(cur2["version"]) == 5
	for ver in [3, 2]:
		var old = cur2.duplicate(true)
		old["version"] = ver
		old["state"].erase("guide")
		old["state"].erase("jianghu")
		if ver == 2:
			old["state"]["step3"]["arena"].erase("difficulty")
			old["state"]["step3"]["arena"].erase("hard_wins")
			old["state"]["step3"]["disciple"].erase("spar_count")
		await ss._free_game()
		ss._write_raw(JSON.stringify(old))
		await s4.reload_game()
		bind()
		await r.frames(10)
		ok["v%d" % ver] = gd.started and gd.paid[2] and gd.payments.is_empty()
	r.check(ok.values().all(func(v): return v), "guide AC6: version 1 (a real 第②步 save with the roof repaired), 2 and 3 saves load: the guide runs, the roof step counts as done without coins; written back as version 5",
		str(ok))
	# a save made during the prologue (version 1): the prologue goes on and ends the new way
	await ss._free_game()
	ss._write_raw(FileAccess.get_file_as_string("res://tests/fixtures/step2_save_v1_midprologue.json"))
	await s4.reload_game()
	bind()
	var mid_ok: bool = not smp.unlocked and not gd.started
	await ss.reach_unlock()
	await r.frames(5)
	r.check(mid_ok and smp.unlocked and gd.started and not story.prologue_end.is_open and gd.captions.has("序章 · 完") and gd.paid == [false, false, false, false, false],
		"guide AC6: a save made during the prologue plays on to the new ending (caption, guide from step 1, nothing pre-paid)")


func test_esc_keys() -> void:
	await game()
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var pm: PauseMenu = g.pause_menu
	var has_q := false
	for i in range(0, pm.key_labels.size(), 2):
		if pm.key_labels[i].text == "Q" and "任务面板" in pm.key_labels[i + 1].text:
			has_q = true
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var fits := true
	var heights := []
	for pg in pm.tip_pages.size():
		pm.show_page(pg)
		await r.process_frame
		await r.process_frame
		heights.append(pm.panel.size.y * pm.panel.scale.y)
		if not Rect2(Vector2.ZERO, vp).encloses(pm.panel.get_global_rect()) or pm.panel.scale.x < 0.999:
			fits = false
	await r.tap(KEY_ESCAPE)
	r.check(has_q and fits, "guide: the Esc page lists Q (任务面板); with the extra row every page still fits 480x270 unscaled", str([has_q, heights]))
