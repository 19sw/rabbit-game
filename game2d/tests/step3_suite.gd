extends RefCounted
## 第③步 checks (task packet AC1-AC8, AC10), run by tests/run_tests.gd after the other suites, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-step3
## Real key events (E / 1-4 / Esc / Q / B / J / Space / WASD) and real physics wherever the player does something; state is
## set directly only to reach a starting point quickly (the clock, coins, an opponent's HP before the last blow, flags for
## the 收徒 condition combinations) - never to produce the result that is checked.
##   AC1 calendar: day 1 = the day the prologue ends; open on day 3/6/9 12:00-18:00 only (edges 11:59 / 12:00 / 17:59 /
##       18:00 / midnight); notice board + 门派簿 say the right next date
##   AC2 fee 10 (short: message, nothing taken), one entry per edition (after a loss, a forfeit and a title)
##   AC3 cards == the plan table; 20 % loses / wins a round; +50 between rounds (cap 100); no regen; can't leave the
##       ring; Esc 弃权; refill on leaving; round banners; a real-key bot wins a whole tournament
##   AC4 first title 60 + 名望 2, later 40 + 1, 名望 never over 10, 门派簿 entries
##   AC5 收徒 condition (4 combinations), the next 08:00 at 山门, 老伯's line, 再想想 then again, 收下: 家业 +1, entry
##   AC6 upkeep 5 every 08:00, debt + "伙食钱不够了", paid back, never negative, several days in one jump
##   AC7 jobs from the next 08:00: 帮厨 25 (greyed without the kitchen), 陪练 once a day +3 / 5 wins 名望 +1, 打扫 5 days
##       家业 +1; the 门派簿 shows the job and the progress
##   AC8 save round trip (snapshot equal), a real 第②步 save (tests/fixtures/step2_save_v1.json) upgrades and plays on,
##       crossing 08:00 after loading charges once, invalid step-3 values are refused
##   v1.1 困难: cards (same HP / damage, armour, denser, double strike, 60 % sidestep), the choice at the board, rewards
##        120 / +3 then 80 / +2 (first counted per difficulty), cap, book entry, saved difficulty; bot win rates over
##        10 seeded tournaments each (masher < 30 %, dodge + counter wins)
##   review fixes: a mid-prologue 第②步 save gets day 1 at the real prologue end; 陪练 per calendar day (per_day)
##   AC10 the ring keeps the road / arch / tea stall / villagers clear; new text in the UI font; Esc page 3 fits

var r
var ss                     # tests/sample_suite.gd (game helpers: new_game, reach_unlock, talk, title / continue ...)
var cs                     # tests/combat_suite.gd bound to the current game (bot_step)
var g: Node
var story: Story
var dlg: Dialogue
var smp: Sample
var s3: Step3
var ar: Arena
var dc: Disciple
var bot_log: Variant = []


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	SaveGame.erase()
	ss = load("res://tests/sample_suite.gd").new(r)
	test_tables_and_cards()
	test_font_and_tips_text()
	await test_placement()
	await test_calendar()
	await test_board_and_book_text()
	await test_fee_and_entries()
	await test_round_rules()
	await test_rewards_and_cap()
	await test_bot_tournament()
	await test_disciple_condition()
	await test_disciple_arrival_and_join()
	await test_upkeep_and_debt()
	await test_jobs()
	await test_spar_job()
	await test_save_roundtrip()
	await test_step2_upgrade()
	await test_pause_page3()
	# 补充 v1.1 + review fixes
	test_hard_cards()
	await test_hard_signup_and_rewards()
	await test_hard_bot_rates()
	await test_hard_reaction_bot()
	await test_v2_upgrade()
	await test_midprologue_upgrade()
	await test_spar_per_day()
	await ss._free_game()
	SaveGame.erase()
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_save_bad.json"):
		dir.remove("test_save_bad.json")


# ================================================================== helpers
func bind() -> void:
	g = ss.g
	story = g.story
	dlg = story.dialogue
	smp = g.sample
	s3 = g.step3
	ar = s3.arena
	dc = s3.disciple
	cs = load("res://tests/combat_suite.gd").new(r)


func p() -> Player:
	return g.player


## A new game played to 继续逛逛 (the real ending), the clock first moved to day index `day_idx` 08:00.
func unlocked_game(day_idx := 0) -> void:
	await ss.new_game()
	bind()
	await ss.finish_scene()
	if day_idx > 0:
		g.daynight.restore(8.0, day_idx * 24.0 + 8.0)
	await ss.reach_unlock()
	await r.frames(3)
	bind()


## Puts the clock at day `n` of the 比武大会 calendar, hour `h` (a starting point; only forward in the disciple tests).
func set_day(n: int, h: float) -> void:
	g.daynight.restore(h, float(s3.anchor_day + n - 1) * 24.0 + h)


## The clock forward to the next time it is `h` o'clock (a full day when it is `h` now).
func advance_to(h: float) -> void:
	h += 0.01      # just past the hour (float sums of a running clock may land a hair before it)
	if fposmod(h - g.daynight.hour, 24.0) < 0.02:
		g.daynight.advance_hours(24.0)
	else:
		g.daynight.set_hour(h)
	await r.frames(3)


func set_coins(n: int) -> void:
	ss.set_coins(n)


## Talk / look with E and answer the choices in order with the given keys (E for every line).
func play_keys(keys: Array, limit := 600) -> void:
	var k := 0
	var n := 0
	while story.busy and n < limit:
		if dlg.choosing:
			await r.tap(keys[k] if k < keys.size() else KEY_1)
			k += 1
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(3)


func board_e(keys: Array = [KEY_1]) -> Array:
	await r.teleport(ar.board_point() + Vector2(0, 6))
	var shown := []
	var before := story.played.size()
	await r.tap(KEY_E)
	# collect every line's text as it shows
	var n := 0
	while story.busy and n < 600:
		if dlg.active and not (dlg.full_text in shown):
			shown.append(dlg.full_text)
		if dlg.choosing:
			await r.tap(keys[0] if not keys.is_empty() else KEY_1)
			if not keys.is_empty():
				keys = keys.slice(1)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(3)
	return [story.played.slice(before), shown]


func wait_arena(want: String, limit := 900) -> bool:
	for i in limit:
		if ar.state == want:
			return true
		await r.physics_frame
	return ar.state == want


## Hits with J (bot "masher") until the round is decided; the opponent's HP is put just above the line first.
func win_round_quick(keep_hp := false) -> bool:
	var f := ar.current()
	var line := int(floor(f.stats.max_hp * Economy.arena_float("lose_fraction")))
	f.hp = line + 3
	p().hp = maxi(p().hp, 60)
	for i in 1800:
		if ar.state != "fight":
			break
		if keep_hp:
			p().hp = 100      # (困难 reward checks: the reward is what is checked, not the fight)
		cs.bot_step("counter")
		await r.physics_frame
	cs._release() if cs.has_method("_release") else r.release_all()
	r.release_all()
	return ar.state == "result" and g.combat.bout_last_win


func finish_result() -> void:
	for i in 600:
		if ar.state != "result":
			break
		await r.physics_frame
	await r.frames(2)


## A whole tournament won quickly (opponent HP lowered before each round's last blows; the blows are real keys).
func quick_title(keep_hp := false) -> bool:
	if not await wait_arena("fight"):
		return false
	for i in 3:
		if not await wait_arena("fight"):
			return false
		if not await win_round_quick(keep_hp):
			return false
		await finish_result()
	await r.frames(3)
	return ar.state == "idle" and ar.last_outcome == "champion"


func enter_tournament(day_n: int, coins := 50) -> bool:
	set_day(day_n, 13.0)
	set_coins(coins)
	await r.frames(2)
	await board_e([KEY_1])
	return await wait_arena("intro", 60) or ar.state == "fight"


func book_open_lines() -> Array:
	await r.tap(KEY_B)
	await r.frames(3)
	var lines: Array = story.sect_book.shown_lines()
	var entries: Array = story.sect_book.shown_entries()
	var values: Dictionary = story.sect_book.values.duplicate()
	var rect: Rect2 = story.sect_book.panel.get_global_rect()
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	return [lines, entries, values, rect]


# ================================================================== tables / cards / text
const PLAN_OPP := {
	"monkey": {"max_hp": 70, "damage": 10, "windup": 0.5, "move_speed": 140.0},
	"yak": {"max_hp": 130, "damage": 20, "windup": 0.9, "move_speed": 80.0},
	"snake": {"max_hp": 100, "damage": 14, "windup": 0.6, "move_speed": 120.0},
}


func test_tables_and_cards() -> void:
	Economy.reload()
	var a := Economy.arena()
	var d := Economy.disciple()
	var bad := []
	var want_a := {"interval_days": 3, "open_hour": 12, "close_hour": 18, "fee": 10, "between_heal": 50, "first_win_coins": 60,
		"first_win_fame": 2, "win_coins": 40, "win_fame": 1, "fame_max": 10}
	for k in want_a:
		if int(a.get(k, -1)) != want_a[k]:
			bad.append("%s=%s" % [k, a.get(k)])
	if not is_equal_approx(float(a.get("lose_fraction", 0)), 0.2):
		bad.append("lose_fraction")
	var want_d := {"need_fame": 5, "need_estate": 5, "arrive_hour": 8, "join_estate": 1, "upkeep": 5, "upkeep_hour": 8, "estate_max": 10}
	for k in want_d:
		if int(d.get(k, -1)) != want_d[k]:
			bad.append("%s=%s" % [k, d.get(k)])
	if String(d.get("need_repair", "")) != "dorm_old" or int(Economy.job("cook").get("stall_income", 0)) != 25 \
			or String(Economy.job("cook").get("needs_repair", "")) != "kitchen" or int(Economy.job("spar").get("win_coins", 0)) != 3 \
			or int(Economy.job("spar").get("wins_for_fame", 0)) != 5 or int(Economy.job("spar").get("per_day", 0)) != 1 \
			or int(Economy.job("sweep").get("days_for_estate", 0)) != 5:
		bad.append("jobs")
	var ids: Array = (a.get("rounds", []) as Array).map(func(x): return String(x["id"]))
	if ids != ["monkey", "yak", "snake"]:
		bad.append("rounds " + str(ids))
	r.check(bad.is_empty(), "step3 AC3/AC6/AC7: economy.json arena / disciple = the plan (every 3 days 12-18, fee 10, 20 %, +50, 60/+2 then 40/+1, cap 10; condition 5/5 after the old dorm, 08:00, +1, upkeep 5, 帮厨 25, 陪练 +3 / 5 wins, 打扫 5 days)", str(bad))
	var cbad := []
	for id in PLAN_OPP:
		var c: EnemyStats = load("res://cards/%s.tres" % id)
		for k in PLAN_OPP[id]:
			if not is_equal_approx(float(c.get(k)), float(PLAN_OPP[id][k])):
				cbad.append("%s.%s=%s" % [id, k, c.get(k)])
		if not is_equal_approx(c.end_fraction, Economy.arena_float("lose_fraction")):
			cbad.append(id + ".end_fraction")
	var yak: EnemyStats = load("res://cards/yak.tres")
	var snake: EnemyStats = load("res://cards/snake.tres")
	var monkey: EnemyStats = load("res://cards/monkey.tres")
	var boar: EnemyStats = load("res://cards/boar.tres")
	var feats := yak.attack_kind == "charge" and yak.super_armor and boar.attack_kind == "charge" and is_equal_approx(snake.sidestep_chance, 0.4) \
		and monkey.interval_max < snake.interval_min + 0.5 and monkey.interval_max <= 1.0 and not monkey.super_armor
	r.check(cbad.is_empty() and feats, "step3 AC3: cards monkey / yak / snake = the plan table (HP 70/130/100, damage 10/20/14, wind-up 0.5/0.9/0.6 s, speed 140/80/120); yak charges with super armour like the boar, snake sidesteps 40 %, monkey attacks often", str(cbad))
	var sq: EnemyStats = load("res://cards/squirrel.tres")
	var sx: EnemyStats = load("res://cards/shixiong.tres")
	r.check(sq.max_hp < sx.max_hp and sq.damage < sx.damage and sq.windup >= sx.windup and sq.interval_min >= sx.interval_min
		and sq.sidestep_chance <= sx.sidestep_chance and is_equal_approx(sq.end_fraction, 0.2),
		"step3 AC7: 师弟's 陪练 card is weaker than 师兄 (HP %d < %d, damage %d < %d, slower wind-up, no sidestep), the spar ends at 20 %%" % [sq.max_hp, sx.max_hp, sq.damage, sx.damage])
	r.check(not FileAccess.get_file_as_string("res://scripts/arena.gd").contains("= 10") and FileAccess.get_file_as_string("res://data/economy.json").contains("\"fee\": 10"),
		"step3 AC10: the rule numbers live in the economy table (not in the code)")


func test_font_and_tips_text() -> void:
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := FileAccess.get_file_as_string("res://data/step3.json") + PauseMenu.all_text() \
		+ FileAccess.get_file_as_string("res://scripts/step3.gd") + FileAccess.get_file_as_string("res://scripts/arena.gd") \
		+ FileAccess.get_file_as_string("res://scripts/disciple.gd") + Dialogue.MANY_HINT
	var missing := ""
	for ch in text:
		if ch.unicode_at(0) > 0x7f and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	r.check(missing == "", "step3 AC10: every new character (lines, UI, book, Esc tips) exists in the project UI font", missing)
	var tips := ""
	for t in PauseMenu.TIPS_STEP3:
		tips += Step3.fill(t[1], Step3.numbers())
	r.check(not "{" in tips and "报名费 10 文" in tips and "回 50 点" in tips and "伙食费 5 文" in tips and "每天 25 文" in tips,
		"step3 AC10: the Esc tips page 3 numbers come from economy.json", tips.substr(0, 80))


# ================================================================== placement (AC10 / packet 1)
func test_placement() -> void:
	await unlocked_game()
	await r.frames(3)
	var outer: Rect2 = ar.ring_outer
	var clash := []
	for o in g.data["objects"]:
		var t: Texture2D = load("res://assets/map/" + String(o["tex"]))
		var rr := Rect2(float(o["x"]), float(o["y"]), t.get_width(), t.get_height())
		if String(o["type"]) in ["village_arch", "bench", "building", "fence", "lantern_pole", "signpost"] and rr.intersects(outer.grow(8)):
			clash.append(String(o["type"]))
	for n in g.npcs:
		if outer.grow(24).has_point(n.global_position) and n.visible:
			clash.append(n.id)
	var hidden_rects: Array = ar.hidden_objects.map(func(e): return e["rect"])
	for c in g.data["colliders"]:
		var a: Array = c["rect"]
		if Rect2(a[0], a[1], a[2], a[3]).intersects(outer) and not hidden_rects.has(a):
			clash.append("collider " + String(c["kind"]))
	var hid_ok: bool = ar.hidden_objects.size() == 2 and ar.hidden_objects.all(func(e): return e["sprite"] != null and not e["sprite"].visible and e["shape"] != null and e["shape"].disabled)
	r.check(hid_ok, "step3 AC10 (PM ruling): the pine obj_11 and the bush obj_42 under the ring are hidden and their colliders removed while the ring stands")
	var bp := ar.board_point()
	r.check(clash.is_empty() and ar.board.visible and ar.ring_layer.visible and not ar.ring_shapes[0].disabled
		and not outer.has_point(bp) and outer.position.y > 1660.0,
		"step3 AC10: the ring (+ notice board) stand on the open grass west of the arch, south of the road - no map object, collider or person under it; solid while no tournament runs",
		str(clash))
	# the old ways still work with the ring there: stairs below the gate -> arch -> tea stall -> the village path (real keys)
	r.grid_w = 0
	var res := []
	await r.teleport(Vector2(1040, 1400))
	res.append(await ss.nav.walk_to(Vector2(1455, 1660), 60.0))
	res.append(await ss.nav.walk_to(Vector2(1300, 1880), 60.0))
	res.append(await ss.nav.walk_to(Vector2(1455, 1900), 60.0))
	res.append(await ss.nav.walk_to(Vector2(560, 1610), 90.0))
	r.check(res.all(func(x): return x == "arrived"), "step3 AC10: with the ring standing, the road / arch / tea stall / village path are all still walkable (gate stairs -> arch -> tea stall -> south path -> mountain road)", str(res))
	# before the prologue ends nothing of step 3 exists
	await ss.new_game()
	bind()
	await r.frames(3)
	r.check(not ar.board.visible and not ar.ring_layer.visible and ar.ring_shapes.all(func(cs_): return cs_.disabled) and not dc.npc.visible
		and ar.hidden_objects.all(func(e): return e["sprite"].visible and not e["shape"].disabled)
		and story.interaction_target().get("kind", "") != "step3",
		"step3 AC1: during the prologue the ring, the board and the youngster are not there")


# ================================================================== AC1 calendar
func test_calendar() -> void:
	# the prologue ends on day index 2 of the clock -> that day is day 1
	await unlocked_game(2)
	r.check(s3.anchor_day == 2 and s3.day_number() == 1, "step3 AC1: the day the prologue ends is day 1 (ended on clock day %d)" % s3.anchor_day,
		"anchor %d day %d" % [s3.anchor_day, s3.day_number()])
	var cases := [[1, 10.0, false, 3], [2, 23.99, false, 3], [3, 0.0, false, 3], [3, 11.99, false, 3], [3, 12.0, true, 3],
		[3, 17.99, true, 3], [3, 18.0, false, 6], [4, 12.5, false, 6], [5, 13.0, false, 6], [6, 12.0, true, 6], [6, 18.0, false, 9],
		[9, 15.0, true, 9], [10, 12.0, false, 12]]
	var bad := []
	for c in cases:
		set_day(c[0], c[1])
		if ar.open_now() != c[2] or ar.can_enter() != c[2] or ar.next_day() != c[3]:
			bad.append("day %d %.2f: open %s next %d" % [c[0], c[1], ar.open_now(), ar.next_day()])
	set_day(9, 15.0)
	var ed9 := ar.edition_today()
	r.check(bad.is_empty() and ed9 == 3, "step3 AC1: open on day 3/6/9 12:00-18:00 only (11:59 no, 12:00 yes, 17:59 yes, 18:00 no, day 4/5 no); the next date is right at every edge; day 9 = 第 3 届", str(bad))
	# the clock running over midnight: day 2 23:59 -> day 3 00:00 (still closed until noon), then over 12:00
	set_day(2, 23.9)
	var before := s3.day_number()
	g.daynight.advance_hours(0.2)
	var after := s3.day_number()
	var closed_morning := not ar.open_now() and ar.next_day() == 3
	g.daynight.set_hour(11.95)
	var c1 := ar.open_now()
	g.daynight.advance_hours(0.1)
	var c2 := ar.open_now()
	g.daynight.set_hour(17.95)
	g.daynight.advance_hours(0.1)
	var c3 := ar.open_now()
	r.check(before == 2 and after == 3 and closed_morning and not c1 and c2 and not c3 and ar.next_day() == 6,
		"step3 AC1: running clock: midnight turns day 2 into day 3 (closed in the morning), opens when it passes 12:00, closes when it passes 18:00",
		"%d->%d %s %s %s %s" % [before, after, closed_morning, c1, c2, c3])


func test_board_and_book_text() -> void:
	await unlocked_game()
	set_day(1, 9.0)
	await r.frames(2)
	var out := await board_e()
	var lines: Array = out[1]
	var joined := "\n".join(lines)
	r.check(out[0] == ["A-告示牌-平时"] and "下届比武大会：第 3 天午时。" in joined and "今天是第 1 天" in joined and not "{" in joined,
		"step3 AC1: the notice board on day 1 says '下届比武大会：第 3 天午时' (and today's day)", joined)
	var bk := await book_open_lines()
	r.check("下届比武大会：第 3 天午时（今天第 1 天）" in bk[0], "step3 AC1: the 门派簿 shows the same next date", str(bk[0]))
	set_day(3, 12.5)
	set_coins(0)
	await r.frames(2)
	var bk2 := await book_open_lines()
	var out2 := await board_e([KEY_2])
	var j2 := "\n".join(out2[1])
	r.check(out2[0] == ["A-告示牌-报名"] and "比武大会 · 第 1 届" in j2 and "报名费 10 文" in j2 and "交 10 文报名比武大会？" in j2
		and "比武大会报名中：今天（第 3 天）午时至酉时" in bk2[0] and ar.state == "idle",
		"step3 AC1: on day 3 at 12:30 the board takes entries (第 1 届, fee 10) and the 门派簿 says it is open today; 算了 = nothing happens", j2.substr(0, 120))
	set_day(3, 18.0)
	await r.frames(2)
	var out3 := await board_e()
	r.check(out3[0] == ["A-告示牌-平时"] and "下届比武大会：第 6 天午时。" in "\n".join(out3[1]),
		"step3 AC1: at 18:00 entries are closed; the board points at day 6")
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	r.check((bk2[3] as Rect2).size.y <= 262.0 and Rect2(Vector2.ZERO, vp).encloses(bk2[3]),
		"step3 AC4: the 门派簿 with the new lines still fits the screen", str(bk2[3]))


# ================================================================== AC2 fee, one entry per edition
func test_fee_and_entries() -> void:
	await unlocked_game()
	set_day(3, 13.0)
	set_coins(7)
	await r.frames(2)
	var out := await board_e([KEY_1])
	var j := "\n".join(out[1])
	r.check(smp.coins == 7 and ar.state == "idle" and ar.entered_edition == 0 and "铜钱不够，还差 3 文。" in j and ar.shortfalls == [3]
		and not g.combat.bout_session, "step3 AC2: 7 coins, fee 10: '还差 3 文', nothing taken, no tournament, still not entered", j.substr(0, 160))
	set_coins(25)
	await board_e([KEY_1])
	await r.frames(2)
	var started: bool = ar.state in ["intro", "fight"] and g.combat.bout_session
	r.check(started and smp.coins == 15 and ar.entered_edition == 1 and "报名费 -10" in smp.toasts,
		"step3 AC2: with 25 coins 报名 takes 10 (15 left) and the tournament starts (第 1 届 entered)")
	# lose round 1 (the monkey's real blows bring the rabbit under 20 %)
	await wait_arena("fight")
	p().hp = 25
	for i in 900:
		if ar.state != "fight":
			break
		await r.physics_frame
	var title: String = g.combat.hud.result_title.text
	await finish_result()
	await r.frames(3)
	r.check(ar.last_outcome == "out" and title == "第 1 轮 · 出局" and p().hp == p().stats.max_hp and ar.state == "idle"
		and not g.combat.bout_session and p().global_position.distance_to(ar.exit_pos) < 2.0 and not ar.ring_shapes[0].disabled,
		"step3 AC3: the monkey's blows take him under 20 % -> '第 1 轮 · 出局', HP refilled, standing outside the ring, the ring solid again",
		"%s hp %d" % [title, p().hp])
	var out2 := await board_e([KEY_1])
	r.check(out2[0] == ["A-告示牌-已参加"] and not ar.can_enter() and smp.coins == 15 and ar.state == "idle",
		"step3 AC2: after going out, the same edition cannot be entered again (board: 本届已参加; nothing taken)")
	# day 6: a new edition can be entered; 弃权 ends it and counts as entered
	set_day(6, 12.0)
	await board_e([KEY_1])
	await wait_arena("fight")
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var btn: bool = g.pause_menu.is_open and g.pause_menu.abandon_button.visible and g.pause_menu.abandon_button.text.begins_with("弃权")
	await r.tap(KEY_Q)
	await r.frames(3)
	r.check(btn and ar.last_outcome == "forfeit" and ar.entered_edition == 2 and not r.paused and not g.combat.bout_session
		and p().hp == p().stats.max_hp and not ar.can_enter() and smp.coins == 5 and "已弃权，本届比武大会结束" in s3.toasts,
		"step3 AC2/AC3: 第 2 届: Esc page offers '弃权（Q）'; Q ends it (refilled, outside, no refund), the edition counts as entered")
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var no_btn: bool = g.pause_menu.is_open and not g.pause_menu.abandon_button.visible
	await r.tap(KEY_ESCAPE)
	r.check(no_btn, "step3 AC3: no '弃权' on the Esc page outside a tournament")
	# day 9: win the title, then the same edition is closed too
	set_day(9, 12.0)
	set_coins(10)
	await board_e([KEY_1])
	var won := await quick_title()
	await r.frames(2)
	r.check(won and smp.coins == 60 and not ar.can_enter() and ar.board_scene() == "A-告示牌-已参加",
		"step3 AC2: with exactly 10 coins entering works (0 left); after the title the same edition is closed as well", "won %s coins %d" % [won, smp.coins])


# ================================================================== AC3 rules inside the ring
func test_round_rules() -> void:
	await unlocked_game()
	await enter_tournament(3)
	# intro: banner + the opponent's line over his head, nobody moves
	await r.frames(10)
	var banner: String = g.combat.hud.banner.text
	var b: Dictionary = story.bubble()
	var still: bool = not p().input_enabled and g.combat.blocks_interaction() and g.combat.in_combat()
	r.check(ar.state == "intro" and banner == "第 1 轮：灵猴门 猴子" and String(b.get("text", "")).begins_with("灵猴门，猴子") and g.hud.bubble.visible and still,
		"step3 AC3: round intro: banner '第 1 轮：灵猴门 猴子', the monkey's line over his head, the rabbit waits", banner)
	await wait_arena("fight")
	var f := ar.current()
	r.check(f.engaged and g.combat.spar_fighter == f and g.combat.yard_closed() and g.combat.fighters.has(f) and g.combat.arena_rect == ar.fight_rect,
		"step3 AC3: the fight: the monkey is engaged inside the ring's walls")
	# no regen during the fight (the monkey held back for this check: a private calm copy of his card)
	var orig: EnemyStats = f.stats
	var calm: EnemyStats = orig.duplicate()
	calm.interval_min = 9999.0
	calm.interval_max = 9999.0
	f.stats = calm
	f.next_attack = 9999.0
	p().hp = 50
	await r.frames(int(6.5 * 60))
	var hp_after := p().hp
	r.check(hp_after == 50 and not p().regen_active, "step3 AC3: no regen in the ring (50 HP stays 50 after 6.5 s without a hit)", str(hp_after))
	# can't leave the ring (real keys), E / doors do nothing
	var fr := ar.fight_rect
	await r.push(Vector2.LEFT, 2.0)
	var x1 := p().global_position.x
	await r.push(Vector2.DOWN, 1.5)
	var y1 := p().global_position.y
	await r.push(Vector2.UP, 1.5)
	var y2 := p().global_position.y
	await r.push(Vector2.RIGHT, 3.0)
	var x2 := p().global_position.x
	await r.tap(KEY_E)
	r.check(x1 >= fr.position.x - 8.0 and y1 <= fr.end.y + 8.0 and y2 >= fr.position.y - 8.0 and x2 <= fr.end.x + 8.0 and not story.busy,
		"step3 AC3: walking into the ropes on every side (real keys) he stays inside the ring; E does nothing", "x %.0f..%.0f y %.0f..%.0f" % [x1, x2, y2, y1])
	f.stats = orig
	# a win by the 20 % line: the monkey just above it, real J blows bring him to <= 14 -> round 2, +50 HP
	p().hp = 40
	f.hp = int(floor(f.stats.max_hp * 0.2)) + 2
	await r.teleport(f.global_position + Vector2(-26, 0))
	for i in 900:
		if ar.state != "fight":
			break
		cs.bot_step("masher")
		await r.physics_frame
	r.release_all()
	var hp_before_heal := p().hp
	var t1: String = g.combat.hud.result_title.text
	var line1: String = g.combat.hud.result_line.text
	await finish_result()
	await r.frames(2)
	r.check(t1 == "第 1 轮 · 胜！" and "猴子：" in line1 and ar.round == 1 and ar.state == "intro" and p().hp == mini(hp_before_heal + 50, 100)
		and g.combat.hud.banner.text == "第 2 轮：铁牛帮 牦牛",
		"step3 AC3: the monkey at 20 %% loses the round; between rounds +50 HP (%d -> %d), then '第 2 轮：铁牛帮 牦牛'" % [hp_before_heal, p().hp], t1)
	# round 2 with 70 HP: a win heals to the cap (100)
	await wait_arena("fight")
	p().hp = 70
	var won2 := await win_round_quick()
	var hp2 := p().hp
	await finish_result()
	await r.frames(2)
	r.check(won2 and ar.round == 2 and p().hp == mini(hp2 + 50, 100) and (hp2 + 50 <= 100 or p().hp == 100),
		"step3 AC3: +50 never goes past 100 (%d -> %d)" % [hp2, p().hp])
	# round 3: the snake's intro, then 弃权 from the Esc page during the fight
	r.check(g.combat.hud.banner.text == "第 3 轮：青蛇派 蛇", "step3 AC3: round 3 banner '第 3 轮：青蛇派 蛇'")
	await wait_arena("fight")
	await r.tap(KEY_ESCAPE)
	await r.tap(KEY_Q)
	await r.frames(3)
	r.check(ar.last_outcome == "forfeit" and p().hp == 100 and ar.opponents.all(func(o): return not o.visible) and not g.combat.fighters.has(ar.opponents[2])
		and g.combat.spar_fighter.id == "fox" and not g.combat.yard_closed() and smp.calm(),
		"step3 AC3: 弃权 in round 3: out of the ring, refilled, opponents gone, 师兄's spar set back, the game calm (saving allowed)")


# ================================================================== AC4 rewards
func test_rewards_and_cap() -> void:
	await unlocked_game()
	var fame0 := s3.value("fame")
	await enter_tournament(3, 10)
	var won := await quick_title()
	var res_line: String = g.combat.hud.result_line.text
	r.check(won and smp.coins == 60 and ar.fame_points == 2 and s3.value("fame") == fame0 + 2 and ar.wins == [1] and ar.last_reward.get("first", false),
		"step3 AC4: first title: 60 coins, 名望 +2 (%d -> %d)" % [fame0, s3.value("fame")], "coins %d" % smp.coins)
	var bk := await book_open_lines()
	r.check("比武大会·夺魁（第 1 届）" in bk[1] and int(bk[2]["fame"]) == fame0 + 2, "step3 AC4: 门派簿: '比武大会·夺魁（第 1 届）' and the 名望 bar +2", str(bk[1]))
	await enter_tournament(6, 10)
	won = await quick_title()
	r.check(won and smp.coins == 40 and ar.fame_points == 3 and ar.wins == [1, 2] and not ar.last_reward.get("first", true),
		"step3 AC4: a later title: 40 coins, 名望 +1", "coins %d fame %d" % [smp.coins, ar.fame_points])
	# near the cap: trial tiers (+3) and 陪练 fame put the bar at 9 -> the next title gives 1, the one after 0
	for t in ["trial_bronze", "trial_silver", "trial_gold"]:
		story.flags[t] = true
	dc.spar_fame = 9 - s3.raw_value("fame") + dc.spar_fame
	var v9 := s3.value("fame")
	await enter_tournament(9, 10)
	won = await quick_title()
	var v10 := s3.value("fame")
	await enter_tournament(12, 10)
	var won4 := await quick_title()
	var res4: String = g.combat.hud.result_line.text
	var bk2 := await book_open_lines()
	r.check(won and won4 and v9 == 9 and v10 == 10 and s3.value("fame") == 10 and s3.raw_value("fame") == 10 and ar.last_reward["fame"] == 0
		and ar.last_reward["coins"] == 40 and int(bk2[2]["fame"]) == 10 and "比武大会·夺魁（第 1、2、3、4 届）" in bk2[1],
		"step3 AC4: 名望 never goes past 10 (9 -> 10 -> still 10, the coins are still paid); the book lists every title", "%d %d %s" % [v9, v10, str(bk2[1])])


# ================================================================== AC3 the real-key bot
func test_bot_tournament() -> void:
	await unlocked_game()
	var results := []
	var won := false
	for attempt in 4:
		var day := 3 * (attempt + 1)
		if not await enter_tournament(day, 10):
			results.append("no entry")
			continue
		g.combat.rng.seed = 7 + attempt
		var rounds := []
		var guard := 0
		while ar.state != "idle" and guard < 60 * 400:
			if ar.state == "fight":
				cs.bot_step("counter")
			else:
				r.release_all()
			await r.physics_frame
			guard += 1
			if ar.state == "result" and (rounds.size() == ar.round):
				rounds.append({"round": ar.round + 1, "win": g.combat.bout_last_win, "hp": p().hp, "opp_hp": ar.current().hp})
		r.release_all()
		await r.frames(3)
		results.append({"outcome": ar.last_outcome, "rounds": rounds})
		if ar.last_outcome == "champion":
			won = true
			break
	bot_log = results
	r.check(won, "step3 AC3: a bot pressing the real keys (move, J, Space-dodge on the wind-up, chase-counter) wins a whole tournament (monkey, yak, snake)", str(results))


# ================================================================== AC5 收徒
func test_disciple_condition() -> void:
	await unlocked_game()
	set_day(1, 10.0)
	var combos := {}
	var reset := func():
		for f in ["repair_roof", "repair_dorm_old", "repair_kitchen", "trial_bronze", "trial_silver", "trial_gold"]:
			story.flags.erase(f)
		ar.fame_points = 0
		dc.sweep_estate = 0
		dc.state = "none"
		dc.arrive_day = -1
	# 1) only the old dorm cleaned (家业 2, 名望 1)
	reset.call()
	story.flags["repair_dorm_old"] = true
	await r.frames(3)
	combos["dorm only"] = [dc.condition(), dc.state]
	# 2) only 名望 >= 5 (three trial tiers + one title = 6), no old dorm
	reset.call()
	for t in ["trial_bronze", "trial_silver", "trial_gold"]:
		story.flags[t] = true
	ar.fame_points = 2
	await r.frames(3)
	combos["fame only"] = [dc.condition(), dc.state, s3.value("fame")]
	# 3) only 家业 >= 5 without the old dorm (roof + kitchen = 4, + 1 more)
	reset.call()
	story.flags["repair_roof"] = true
	story.flags["repair_kitchen"] = true
	dc.sweep_estate = 1
	await r.frames(3)
	combos["estate only"] = [dc.condition(), dc.state, s3.value("estate")]
	# 4a) old dorm + 名望 5
	reset.call()
	story.flags["repair_dorm_old"] = true
	for t in ["trial_bronze", "trial_silver", "trial_gold"]:
		story.flags[t] = true
	ar.fame_points = 1
	await r.frames(3)
	combos["dorm + fame"] = [dc.condition(), dc.state]
	# 4b) old dorm + 家业 5 (all three repairs - the step-2 route)
	reset.call()
	for f in ["repair_roof", "repair_dorm_old", "repair_kitchen"]:
		story.flags[f] = true
	await r.frames(3)
	combos["dorm + estate"] = [dc.condition(), dc.state, s3.value("estate")]
	r.check(not combos["dorm only"][0] and combos["dorm only"][1] == "none" and not combos["fame only"][0] and combos["fame only"][2] >= 5
		and not combos["estate only"][0] and combos["estate only"][2] >= 5 and combos["dorm + fame"][0] and combos["dorm + fame"][1] == "coming"
		and combos["dorm + estate"][0] and combos["dorm + estate"][1] == "coming" and combos["dorm + estate"][2] == 5,
		"step3 AC5: condition = old dorm cleaned AND (名望 >= 5 OR 家业 >= 5): dorm only no, 名望 only no, 家业 only no, dorm + 名望 yes, dorm + 家业 (three repairs) yes",
		str(combos))


func test_disciple_arrival_and_join() -> void:
	await unlocked_game()
	set_day(1, 15.0)
	for f in ["repair_roof", "repair_dorm_old", "repair_kitchen"]:
		story.flags[f] = true
	await r.frames(3)
	var due := dc.state == "coming" and not dc.npc.visible
	await advance_to(7.95)
	var not_yet := dc.state == "coming" and not dc.npc.visible and story.talk_scene("dog") != "D-老伯-有人拜师"
	g.daynight.advance_hours(0.1)
	await r.frames(3)
	var at_gate: bool = dc.state == "waiting" and dc.npc.visible and dc.npc.global_position.distance_to(dc._v("gate", [0, 0])) < 1.0 \
		and g.npcs.has(dc.npc) and "山门外好像来了一个少年" in s3.toasts
	r.check(due and not_yet and at_gate, "step3 AC5: condition met at 15:00 -> nobody at 07:57 next morning -> at 08:00 the youngster stands at 山门外",
		"due %s not_yet %s gate %s" % [due, not_yet, at_gate])
	# 老伯's new line (real keys)
	var played: Array = await ss.talk("dog")
	var dog_lines := ""
	for e in story.scene("D-老伯-有人拜师"):
		dog_lines += String(e.get("text", ""))
	r.check(played == ["D-老伯-有人拜师"] and "山门外有人想拜师" in dog_lines, "step3 AC5: 老伯 now says '山门外有人想拜师'", str(played))
	# condition met in the early morning: the next 08:00 is the same morning
	# 再想想 (key 2), he stays; talk again -> asked again; 收下 (key 1)
	var estate0 := s3.value("estate")
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	await play_keys([KEY_2])
	var stayed := dc.state == "waiting" and dc.asked and dc.npc.visible and story.played[-1] == "D-少年-拜师"
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	await play_keys([KEY_1])
	await r.frames(5)
	var bk := await book_open_lines()
	r.check(stayed and story.played[-1] == "D-少年-再问" and dc.state == "joined" and s3.value("estate") == estate0 + 1 and dc.npc.title == "师弟"
		and "收下第一个弟子" in bk[1] and int(bk[2]["estate"]) == estate0 + 1,
		"step3 AC5: 再想想 leaves him at the gate; talking again asks again; 收下 -> 师弟, 家业 +1 (%d -> %d), 门派簿 '收下第一个弟子'" % [estate0, s3.value("estate")], str(bk[1]))
	r.check(dc.place == "yard" and dc.in_yard_rects(dc.npc.global_position) and story.talk_scene(dc.npc.id) == "D-师弟" and story.talk_scene("dog") != "D-老伯-有人拜师",
		"step3 AC5: by day 师弟 is in the dorm yard; talking to him = the 师弟 talk; 老伯 back to his usual lines")
	# he walks about the yard (and stays in it)
	await r.teleport(Vector2(240, 1240))
	var p0: Vector2 = dc.npc.global_position
	var moved := 0.0
	var outside := 0
	for i in 60 * 12:
		await r.physics_frame
		moved = maxf(moved, dc.npc.global_position.distance_to(p0))
		if not dc.in_yard_rects(dc.npc.global_position):
			outside += 1
	r.check(moved > 24.0 and outside == 0, "step3 AC5: he walks about the dorm yard by day (moved %.0f px, never left the yard)" % moved)
	# at night: in the old dorm room
	await advance_to(21.0)
	r.check(dc.place == "night" and g.interiors.room_at(dc.npc.global_position) == "dorm_old", "step3 AC5: at night he is in the old dorm room")
	# the early-morning case: condition met at 06:00 -> the youngster comes at 08:00 of the same morning
	await unlocked_game()
	set_day(1, 6.0)
	for f in ["repair_roof", "repair_dorm_old", "repair_kitchen"]:
		story.flags[f] = true
	await r.frames(3)
	await advance_to(8.0)
	r.check(dc.state == "waiting", "step3 AC5: condition met at 06:00 -> he is there at the next 08:00 (two hours later)")


# ================================================================== AC6 upkeep
## A game with 师弟 taken in (joined at the given hour of day 1; the kitchen repaired when `kitchen`).
func joined_game(kitchen := false, h := 9.0) -> void:
	await unlocked_game()
	set_day(1, 6.0)
	for f in ["repair_roof", "repair_dorm_old"] + (["repair_kitchen"] if kitchen else []):
		story.flags[f] = true
	if not kitchen:
		ar.fame_points = 2       # 名望 1 + 2 + ... the estate route needs the kitchen; here 名望 helps
		for t in ["trial_bronze", "trial_silver"]:
			story.flags[t] = true
	for f in ["roof", "dorm_old"] + (["kitchen"] if kitchen else []):
		smp.apply_repair_visuals(f)
	if kitchen:
		smp.paid_day = g.daynight.day_index(Economy.stall_hour())
	await r.frames(3)
	await advance_to(8.0)
	await advance_to(h)
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	await play_keys([KEY_1])
	await r.frames(3)


func test_upkeep_and_debt() -> void:
	await joined_game(false)
	set_coins(12)
	var seq := []
	for i in 3:
		await advance_to(8.0)
		seq.append([smp.coins, dc.debt])
	var short_toast := "伙食钱不够了（欠 3 文）" in s3.toasts
	r.check(seq == [[7, 0], [2, 0], [0, 3]] and short_toast and smp.coins >= 0 and dc.upkeep_days == 3,
		"step3 AC6: 08:00 each day takes 5 (12 -> 7 -> 2); then 2 pays part, 3 become debt with '伙食钱不够了', coins stay at 0", str(seq))
	await advance_to(8.0)
	var two := [smp.coins, dc.debt]
	smp.add_coins(10)
	await r.frames(3)
	var paid := [smp.coins, dc.debt]
	r.check(two == [0, 8] and paid == [2, 0] and "补上伙食钱 -8" in s3.toasts, "step3 AC6: the debt grows (8) and is paid back as soon as coins come in (10 -> 2 left)", "%s %s" % [two, paid])
	# a jump of several days at once (the clock moved 3 days): 3 days charged, nothing twice
	set_coins(100)
	var d0 := dc.upkeep_days
	g.daynight.advance_hours(72.0)
	await r.frames(3)
	await r.frames(3)
	r.check(dc.upkeep_days == d0 + 3 and smp.coins == 85, "step3 AC6: three days passed in one jump -> three upkeeps (100 -> 85), not more", "%d %d" % [dc.upkeep_days - d0, smp.coins])
	# with the stall: income first, then upkeep (debt 3, coins 0 -> 15 in -> 3 back, 5 upkeep -> 7)
	await joined_game(true)
	set_coins(0)
	dc.debt = 3
	await advance_to(8.0)
	r.check(smp.coins == 7 and dc.debt == 0, "step3 AC6: the stall's 08:00 income pays the old debt and the day's upkeep (0 -> +15 -> 7)", "coins %d debt %d" % [smp.coins, dc.debt])


# ================================================================== AC7 jobs
func talk_disciple(keys: Array) -> Array:
	await ss.stand_near(dc.npc.global_position)
	var opts := []
	await r.tap(KEY_E)
	var k := 0
	var n := 0
	while story.busy and n < 600:
		if dlg.choosing:
			opts.append({"options": dlg.choice_options.duplicate(), "disabled": dlg.choice_disabled.duplicate()})
			var key: int = keys[k] if k < keys.size() else KEY_1
			k += 1
			await r.tap(key)
			if dlg.choosing and dlg.is_disabled(dlg.choice_index) == false and key == KEY_1 and dlg.is_disabled(0):
				opts[-1]["refused"] = true
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(3)
	return opts


func test_jobs() -> void:
	await joined_game(false)
	set_coins(50)
	# 派活 without the kitchen: 帮厨 greyed (key 1 does nothing), 打扫 (key 3)
	var opts := await talk_disciple([KEY_1, KEY_1, KEY_3])
	var menu: Dictionary = opts[1] if opts.size() > 1 else {}
	var grey: bool = menu.get("options", []) == ["帮厨", "陪练", "打扫", "算了"] and menu.get("disabled", [])[0] == true \
		and not menu.get("disabled", [true, true])[1]
	r.check(opts.size() >= 2 and (opts[0]["options"] as Array) == ["派活", "随便聊聊"] and grey and dc.job_next == "sweep" and dc.job_today() == "none",
		"step3 AC7: 派活 offers 帮厨 / 陪练 / 打扫; 帮厨 is greyed (key 1 ignored) while the kitchen is not repaired; 打扫 is chosen but not yet in effect", str(opts))
	var bk := await book_open_lines()
	r.check("师弟：还没派活（明天起：打扫）" in bk[0] and "陪练胜 0/5 · 打扫 0/5 天" in bk[0], "step3 AC7: the 门派簿 shows the job (from tomorrow) and the progress", str(bk[0]))
	# 打扫: in effect from the next 08:00; every 5 full days 家业 +1
	await advance_to(8.0)
	var eff := dc.job_today() == "sweep" and dc.sweep_days == 0
	var est0 := s3.value("estate")
	var days := []
	for i in 5:
		await advance_to(8.0)
		days.append(dc.sweep_days)
	var bk2 := await book_open_lines()
	r.check(eff and days == [1, 2, 3, 4, 5] and s3.value("estate") == est0 + 1 and dc.sweep_estate == 1 and "师弟打扫院子 5 天" in bk2[1]
		and "陪练胜 0/5 · 打扫 0/5 天" in bk2[0] and "师弟：打扫" in bk2[0],
		"step3 AC7: 打扫 in effect from the next 08:00; each finished day counts; 5 days -> 家业 +1 (%d -> %d), book entry" % [est0, s3.value("estate")], str(days))
	# 帮厨: the kitchen repaired -> option enabled; the stall pays 15 on the next 08:00 still (chosen today), 25 from the one after
	story.flags["repair_kitchen"] = true
	smp.apply_repair_visuals("kitchen")
	smp.paid_day = g.daynight.day_index(Economy.stall_hour())
	await advance_to(10.0)
	var opts2 := await talk_disciple([KEY_1, KEY_1])
	var en: bool = opts2.size() >= 2 and not opts2[1]["disabled"][0]
	set_coins(100)
	await advance_to(7.9)
	var inc0 := smp.incomes
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	var first_day: int = smp.coins - 100      # income - upkeep
	var t25 := "小食摊今日收入 +25" in smp.toasts
	r.check(en and dc.job_next == "cook" and smp.incomes == inc0 + 1 and first_day == 25 - 5 and t25 and dc.job_today() == "cook",
		"step3 AC7: 帮厨 (kitchen repaired) chosen at 10:00 -> at the next 08:00 the stall pays 25 instead of 15 ('小食摊今日收入 +25')", "net %d" % first_day)


func test_spar_job() -> void:
	await joined_game(false)
	set_coins(20)
	await talk_disciple([KEY_1, KEY_2])     # 派活 -> 陪练
	var no_spar_today: bool = not dc.can_spar_now()
	await advance_to(8.0)
	await advance_to(9.0)
	var spot := dc._v("spar_spot", [0, 0])
	var waiting: bool = dc.place == "spar" and dc.npc.global_position.distance_to(spot) < 1.0
	# 切磋一场 (shown only now), the real blows with him just above 20 %
	var c: Combat = g.combat
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	var offered := false
	var n := 0
	while story.busy and n < 300:
		if dlg.choosing:
			offered = offered or (dlg.choice_options.size() > 0 and dlg.choice_options[0] == "切磋一场")
			await r.tap(KEY_1)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(3)
	var started: bool = c.bout_owner == dc and c.spar_state == "fighting" and p().hp == 100
	dc.npc.hp = int(floor(dc.npc.stats.max_hp * 0.2)) + 2
	for i in 1200:
		if c.spar_state != "fighting":
			break
		cs.bot_step("counter")
		await r.physics_frame
	r.release_all()
	var title: String = c.hud.result_title.text
	for i in 400:
		if c.bout_owner == null:
			break
		await r.physics_frame
	await r.frames(3)
	r.check(no_spar_today and waiting and offered and started and title == "陪练 · 胜！" and smp.coins == 20 - 5 + 3 and dc.spar_wins == 1
		and c.spar_fighter.id == "fox" and not c.yard_closed() and p().hp == 100,
		"step3 AC7: 陪练 from the next day: he waits in the 练武场, '切磋一场' is offered, a win pays +3 (spar ends at 20 %, both refilled)",
		"%s coins %d" % [title, smp.coins])
	var opts := await talk_disciple([KEY_2])
	r.check(not (opts[0]["options"] as Array).has("切磋一场") and not dc.can_spar_now(), "step3 AC7: only one 陪练 a day (no 切磋 offered again today)", str(opts[0]["options"]))
	# the fifth win gives 名望 +1
	dc.spar_wins = 4
	var f0 := s3.value("fame")
	await advance_to(8.0)
	await advance_to(9.0)
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	await play_keys([KEY_1])
	dc.npc.hp = int(floor(dc.npc.stats.max_hp * 0.2)) + 2
	for i in 1200:
		if c.spar_state != "fighting":
			break
		cs.bot_step("counter")
		await r.physics_frame
	r.release_all()
	for i in 400:
		if c.bout_owner == null:
			break
		await r.physics_frame
	var bk := await book_open_lines()
	r.check(dc.spar_wins == 5 and dc.spar_fame == 1 and s3.value("fame") == f0 + 1 and "师弟陪练累计 5 胜" in bk[1] and "陪练胜 0/5 · 打扫 0/5 天" in bk[0],
		"step3 AC7: the 5th 陪练 win: 名望 +1 (%d -> %d), book entry, progress back to 0/5" % [f0, s3.value("fame")], str(bk))
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	r.check(story.sect_book.two_columns and Rect2(Vector2.ZERO, vp).encloses(bk[3]) and (bk[3] as Rect2).size.y <= 262.0 and (bk[3] as Rect2).size.x <= 472.0,
		"step3 AC7: a full 门派簿 (many entries + status lines) puts 名望 / 家业 side by side and fits the 480x270 screen", str(bk[3]))


# ================================================================== AC8 saving
func _s3_observables() -> Dictionary:
	return {"board": ar.board.visible, "ring_solid": not ar.ring_shapes[0].disabled, "npc": dc.npc.visible, "title": dc.npc.title,
		"place": dc.place, "fame": s3.value("fame"), "estate": s3.value("estate"), "next": ar.next_day(), "day": s3.day_number(),
		"talk": story.talk_scene(dc.npc.id), "income": s3.stall_income(g.daynight.day_index(8))}


func test_save_roundtrip() -> void:
	await joined_game(true)
	await talk_disciple([KEY_1, KEY_1])      # 帮厨 from tomorrow (pending in the save)
	await enter_tournament(3, 30)
	await quick_title()
	set_day(4, 7.5)
	await r.frames(2)
	dc.debt = 4
	dc.spar_wins = 3
	dc.sweep_days = 2
	set_coins(0)
	await r.frames(2)
	smp.save_now("test")
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	var obs := _s3_observables()
	var saved_text := FileAccess.get_file_as_string(SaveGame.path())
	var doc = JSON.parse_string(saved_text)
	await ss._title()
	await r.tap(KEY_ENTER)
	var m: Node = await ss._wait_game()
	if m == null:
		r.check(false, "step3 AC8: 继续游戏 enters the game")
		return
	bind()
	g.daynight.running = false
	var snap2 := SaveGame.roundtrip(SaveGame.capture(g))
	var d: String = ss._diff(snap, snap2)
	r.check(int(doc["version"]) == SaveGame.VERSION and d == "" and snap["step3"]["arena"]["wins"] == [1] and snap["step3"]["disciple"]["job_next"] == "cook",
		"step3 AC8: every step-3 state (calendar anchor, entries, titles, 名望 given, disciple, job + pending job, debt, progress) saves as the current version (%d) and comes back equal" % SaveGame.VERSION, d)
	r.check(ss._diff(obs, _s3_observables()) == "", "step3 AC8: and the game looks the same (ring, board, 师弟 where he should be, bars, next date, talk, income)", ss._diff(obs, _s3_observables()))
	# crossing 08:00 after loading: one upkeep + the 帮厨 income, once
	set_coins(0)
	await advance_to(8.0)
	await r.frames(3)
	var c1 := smp.coins
	await r.frames(30)
	r.check(c1 == 25 - 4 - 5 and smp.coins == c1 and dc.debt == 0 and dc.job_today() == "cook",
		"step3 AC8: after loading, the next 08:00 pays 帮厨 25, takes the old debt 4 and the upkeep 5 - once (16)", "coins %d" % c1)
	# the same save loaded again (the 08:00 above saved over it - put the 07:30 file back): charged again exactly once
	var autosaved = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	var resaved: bool = int(autosaved["state"]["step3"]["disciple"]["debt"]) == 0 and int(autosaved["state"]["step3"]["disciple"]["tick_day"]) > int(snap["step3"]["disciple"]["tick_day"])
	r.check(resaved, "step3 AC8: the 08:00 charge is saved at once (the slot holds the paid state: no debt, the day ticked)")
	await ss._free_game()
	ss._write_raw(saved_text)
	await ss._title()
	await r.tap(KEY_ENTER)
	await ss._wait_game()
	bind()
	g.daynight.running = false
	set_coins(0)
	await advance_to(8.0)
	await r.frames(10)
	r.check(smp.coins == 16 and dc.upkeep_days == 1, "step3 AC8: loading the save again and crossing 08:00 gives the same single charge (no double charge, none lost)", "coins %d" % smp.coins)
	# invalid step-3 values are refused
	var st := SaveGame.roundtrip(SaveGame.capture(g))
	var bad := {}
	var c := st.duplicate(true)
	c["step3"]["disciple"]["debt"] = -2
	bad["debt"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c["step3"]["disciple"]["state"] = "boss"
	bad["state"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c["step3"]["arena"]["wins"] = "many"
	bad["wins"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c.erase("step3")
	bad["missing"] = SaveGame.validate(c) != ""
	r.check(bad.values().all(func(v): return v), "step3 AC8: a version-2 save with bad step-3 values (negative debt, unknown state, wins not a list, section missing) is refused", str(bad))


func test_step2_upgrade() -> void:
	await ss._free_game()
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/step2_save_v1.json")
	var old = JSON.parse_string(fixture)
	ss._write_raw(fixture)
	var rd := SaveGame.read()
	var t: TitleScreen = await ss._title()
	var offered: bool = not t.button("continue").disabled
	await r.tap(KEY_ENTER)
	var m: Node = await ss._wait_game()
	if m == null:
		r.check(false, "step3 AC8: a 第②步 save enters the game")
		return
	bind()
	g.daynight.running = false
	r.check(int(old["version"]) == 1 and not old["state"].has("step3") and rd["ok"] and offered and g.hud.toast.text != SaveGame.BROKEN_TEXT
		and smp.unlocked and smp.coins == 30 and smp.is_repaired("roof") and smp.is_repaired("dorm_old") and story.stage == 9,
		"step3 AC8: a real 第②步 save (version 1, written by the step-2 code) is offered by 继续游戏 and loads (coins 30, roof + old dorm, after the prologue) - not thrown away")
	var up_ok: bool = s3.anchor_day == 0 and s3.day_number() == 2 and ar.next_day() == 3 and ar.entered_edition == 0 and ar.wins.is_empty() \
		and dc.state == "none" and s3.value("fame") == 3 and s3.value("estate") == 3 and ar.board.visible
	r.check(up_ok, "step3 AC8: upgraded: step 3 starts empty, day 1 = the game's first day (the save is on clock day 1 -> day 2, next tournament day 3), bars unchanged (3 / 3)",
		"anchor %d day %d next %d fame %d estate %d" % [s3.anchor_day, s3.day_number(), ar.next_day(), s3.value("fame"), s3.value("estate")])
	# it plays on: repair the kitchen with 老伯 -> 厨娘 (60): 家业 5 -> the youngster comes at the next 08:00
	set_coins(60)
	var played: Array = await ss.talk("bear")
	await r.frames(5)
	var coming := dc.state == "coming"
	await advance_to(8.0)
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	r.check(smp.is_repaired("kitchen") and coming and dc.state == "waiting" and int(doc["version"]) == SaveGame.VERSION and doc["state"].has("step3"),
		"step3 AC8: the upgraded game plays on into step 3 (kitchen -> 家业 5 -> the youngster at the next 08:00) and saves as the current version (%d)" % SaveGame.VERSION, str(played))


# ================================================================== Esc page 3
func test_pause_page3() -> void:
	await unlocked_game()
	var pm: PauseMenu = g.pause_menu
	await r.tap(KEY_ESCAPE)
	await r.tap(KEY_RIGHT)
	await r.tap(KEY_RIGHT)
	await r.process_frame
	await r.process_frame
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var rect := pm.panel.get_global_rect()
	var text := ""
	var clipped := ""
	for l in pm.step3_tip_labels:
		text += l.text
		if l.size.y + 0.5 < l.get_combined_minimum_size().y or not rect.grow(1).encloses(l.get_global_rect()):
			clipped += l.text.substr(0, 5) + " "
	var has_all := ["比武大会", "擂台规则", "夺魁奖励", "收徒", "师弟的活", "弃权", "伙食费"].all(func(k): return k in text)
	r.check(pm.page == 2 and pm.tip_pages[2].visible and has_all and clipped == "" and Rect2(Vector2.ZERO, vp).encloses(rect),
		"step3 AC10: Esc page tips page 3 (→ →) covers the 比武大会, its rules and rewards, 收徒 and the jobs; fits, nothing cut off", clipped)
	await r.tap(KEY_ESCAPE)


# ================================================================== 补充 v1.1: 困难
const HARD_IDS := ["monkey", "yak", "snake"]


func test_hard_cards() -> void:
	var bad := []
	for id in HARD_IDS:
		var n: EnemyStats = load("res://cards/%s.tres" % id)
		var h: EnemyStats = load("res://cards/%s_hard.tres" % id)
		for k in ["max_hp", "damage", "move_speed", "attack_kind", "end_fraction"]:
			if h.get(k) != n.get(k):
				bad.append("%s.%s" % [id, k])
		if not h.super_armor:
			bad.append(id + " armour")
		var avg_n := (n.interval_min + n.interval_max) * 0.5
		var avg_h := (h.interval_min + h.interval_max) * 0.5
		if avg_h > avg_n * 0.75 + 0.001:
			bad.append("%s interval %.2f vs %.2f" % [id, avg_h, avg_n])
		if h.windup > n.windup or h.stagger > n.stagger:
			bad.append(id + " windup / stagger")
	var mh: EnemyStats = load("res://cards/monkey_hard.tres")
	var yn: EnemyStats = load("res://cards/yak.tres")
	var yh: EnemyStats = load("res://cards/yak_hard.tres")
	var sh: EnemyStats = load("res://cards/snake_hard.tres")
	var specials := mh is ComboStats and int(mh.get("strikes_per_attack")) == 2 and not (load("res://cards/monkey.tres") is ComboStats) \
		and yh.attack_kind == "charge" and yh.interval_max < yn.interval_min and is_equal_approx(sh.sidestep_chance, 0.6)
	var rounds: Array = Economy.arena().get("rounds", [])
	var cards_ok := rounds.map(func(x): return String(x.get("card_hard", ""))) == ["monkey_hard", "yak_hard", "snake_hard"]
	var rw := [Economy.arena_hard("first_win_coins"), Economy.arena_hard("first_win_fame"), Economy.arena_hard("win_coins"), Economy.arena_hard("win_fame")]
	r.check(bad.is_empty() and specials and cards_ok and rw == [120, 3, 80, 2],
		"step3 v1.1: 困难 cards keep the plan's HP / damage / speed; all three have super armour, no stagger, shorter wind-ups and intervals (>= 30 %% shorter); the monkey strikes twice, the yak charges more often, the snake sidesteps 60 %; rewards 120/+3 then 80/+2 in economy.json",
		str(bad) + " " + str(rw))


func test_hard_signup_and_rewards() -> void:
	await unlocked_game()
	set_day(3, 13.0)
	set_coins(10)
	await r.frames(2)
	var out := await board_e([KEY_1, KEY_2])
	var shown: String = "\n".join(out[1])
	await wait_arena("intro", 60)
	var f := ar.current()
	r.check(ar.difficulty == "hard" and smp.coins == 0 and "选哪种难度？（只算这一届，报名费都是 10 文）" in shown
		and f.stats.resource_path.ends_with("monkey_hard.tres") and g.combat.hud.banner_sub.text == "困难",
		"step3 v1.1: at the board 报名 asks 普通 / 困难 (key 2 = 困难), fee 10 as well; the monkey uses his 困难 card, the banner says 困难", shown.substr(0, 120))
	# super armour + the double strike, with real J blows during his wind-up
	await wait_arena("fight")
	var hp0 := f.hp
	var seen := {}
	var hit_in_windup := false
	for i in 60 * 8:
		if ar.state != "fight":
			break
		seen[f.state] = true
		if f.state == "windup" and f.t < 0.15 and not hit_in_windup:
			await r.teleport(f.global_position + f.facing_vec() * 26.0)
			p().facing = CharSheet.dir_from_vector(f.global_position - p().global_position, p().facing)
			r.key(KEY_J, true)
			await r.frames(2)
			r.key(KEY_J, false)
			for k in 20:
				seen[f.state] = true
				p().hp = 100
				await r.physics_frame
			hit_in_windup = f.hp < hp0
			continue
		p().hp = 100
		if hit_in_windup and seen.has("gap"):
			break
		await r.physics_frame
	r.check(hit_in_windup and not seen.has("stagger") and seen.has("gap"),
		"step3 v1.1: 困难 monkey: a real J blow in his wind-up hurts but does not interrupt (no stagger); his attacks come in two strikes", str(seen.keys()))
	var won := await quick_title(true)
	var title: String = g.combat.hud.result_title.text
	var bk := await book_open_lines()
	r.check(won and title == "比武大会 · 夺魁！（困难）" and smp.coins == 120 and ar.fame_points == 3 and ar.hard_wins == [1] and ar.wins.is_empty()
		and "比武大会·夺魁·困难（第 1 届）" in bk[1], "step3 v1.1: first 困难 title: 120 coins, 名望 +3, book '比武大会·夺魁·困难（第 1 届）'", "%s coins %d" % [title, smp.coins])
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	r.check(snap["step3"]["arena"]["difficulty"] == "hard" and snap["step3"]["arena"]["hard_wins"] == [1] and SaveGame.validate(snap) == "",
		"step3 v1.1: the edition's difficulty and the 困难 titles are saved (version %d)" % SaveGame.VERSION)
	set_day(6, 13.0)
	set_coins(10)
	await board_e([KEY_1, KEY_2])
	won = await quick_title(true)
	r.check(won and smp.coins == 80 and ar.fame_points == 5 and ar.hard_wins == [1, 2], "step3 v1.1: a later 困难 title: 80 coins, 名望 +2")
	set_day(9, 13.0)
	set_coins(10)
	await board_e([KEY_1, KEY_1])
	var normal_cards: bool = ar.current().stats.resource_path.ends_with("monkey.tres")
	won = await quick_title(true)
	var bk2 := await book_open_lines()
	r.check(won and normal_cards and ar.difficulty == "normal" and smp.coins == 60 and ar.wins == [3]
		and "比武大会·夺魁（第 3 届）" in bk2[1] and "比武大会·夺魁·困难（第 1、2 届）" in bk2[1],
		"step3 v1.1: 普通 the next edition uses the normal cards again; its first title still pays 60 / +2 (firsts are counted per difficulty); both book lines", str(bk2[1]))
	# the cap: 9 -> a 困难 title gives 1, not 2
	dc.spar_fame = 9 - s3.raw_value("fame") + dc.spar_fame
	set_day(12, 13.0)
	set_coins(10)
	await board_e([KEY_1, KEY_2])
	won = await quick_title(true)
	r.check(won and s3.value("fame") == 10 and ar.last_reward["fame"] == 1 and ar.last_reward["coins"] == 80,
		"step3 v1.1: 名望 stays capped at 10 with 困难 titles (9 -> 10, the coins are still paid)")


## One tournament with a bot (real keys) from the board; returns {outcome, rounds}.
func bot_tournament(day: int, diff_key: int, kind: String, seed_v: int) -> Dictionary:
	set_day(day, 13.0)
	set_coins(10)
	await r.frames(2)
	await board_e([KEY_1, diff_key])
	g.combat.rng.seed = seed_v
	cs._dodged_for = {}
	cs._punish_until = -1.0
	var rounds := []
	var guard := 0
	while ar.state != "idle" and guard < 60 * 300:
		if ar.state == "fight":
			cs.bot_step(kind)
		else:
			r.release_all()
		await r.physics_frame
		guard += 1
		if ar.state == "result" and rounds.size() == ar.round:
			rounds.append(int(g.combat.bout_last_win))
	r.release_all()
	await r.frames(3)
	return {"outcome": ar.last_outcome, "rounds": rounds.size(), "won": ar.last_outcome == "champion"}


func test_hard_bot_rates() -> void:
	await unlocked_game()
	var res := {"masher": [], "counter": []}
	var day := 3
	for kind in ["masher", "counter"]:
		for i in 10:
			var o := await bot_tournament(day, KEY_2, kind, 1000 + i)
			res[kind].append(o)
			day += 3
	var mw: int = res["masher"].filter(func(o): return o["won"]).size()
	var cw: int = res["counter"].filter(func(o): return o["won"]).size()
	var m_r3: int = res["masher"].filter(func(o): return o["rounds"] >= 3).size()
	bot_log = res
	print("HARD BOT RATES masher %d/10 (reached round 3: %d) counter %d/10" % [mw, m_r3, cw])
	print("HARD BOT DETAIL ", res)
	r.check(mw * 10 < 30 and cw >= 6, "step3 v1.1: 困难, 10 seeded tournaments each with real keys: attack-masher wins %d/10 (< 30 %%), dodge + counter wins %d/10" % [mw, cw],
		"masher reached round 3 in %d" % m_r3)


# ================================================================== review fixes
func test_midprologue_upgrade() -> void:
	await ss._free_game()
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/step2_save_v1_midprologue.json")
	var old = JSON.parse_string(fixture)
	ss._write_raw(fixture)
	var rd := SaveGame.read()
	await ss._title()
	await r.tap(KEY_ENTER)
	var m: Node = await ss._wait_game()
	if m == null:
		r.check(false, "step3 fix: a mid-prologue 第②步 save enters the game")
		return
	bind()
	g.daynight.running = false
	var before_ok: bool = int(old["version"]) == 1 and not bool(old["state"]["sample"]["unlocked"]) and rd["ok"] \
		and int(rd["state"]["step3"]["anchor_day"]) == -1 and s3.anchor_day == -1 and not smp.unlocked
	# the prologue ends two days later on the clock: that day is day 1
	g.daynight.restore(8.0, 2 * 24.0 + 8.0)
	await ss.reach_unlock()
	await r.frames(3)
	r.check(before_ok and smp.unlocked and s3.anchor_day == 2 and s3.day_number() == 1 and ar.next_day() == 3,
		"step3 fix: a 第②步 save made during the prologue upgrades with no day 1 yet; the real prologue end (clock day 2) becomes day 1",
		"anchor %d day %d" % [s3.anchor_day, s3.day_number()])


func test_spar_per_day() -> void:
	await joined_game(false)
	await talk_disciple([KEY_1, KEY_2])     # 陪练 from tomorrow
	await advance_to(8.0)                   # day 2: 陪练 in effect
	await advance_to(7.5)                   # day 3 07:30 - still yesterday's (陪练) work day, he is in the yard
	var c: Combat = g.combat
	var early: bool = dc.place == "spar" and dc.can_spar_now()
	await ss.stand_near(dc.npc.global_position)
	await r.tap(KEY_E)
	await play_keys([KEY_1])
	dc.npc.hp = int(floor(dc.npc.stats.max_hp * 0.2)) + 2
	for i in 1200:
		if c.spar_state != "fighting":
			break
		cs.bot_step("counter")
		await r.physics_frame
	r.release_all()
	for i in 400:
		if c.bout_owner == null:
			break
		await r.physics_frame
	var used: bool = dc.spar_count == 1 and not dc.can_spar_now()
	await advance_to(8.5)                   # same calendar day, the new work day
	var opts := await talk_disciple([KEY_2])
	var no_second: bool = not dc.can_spar_now() and not (opts[0]["options"] as Array).has("切磋一场")
	await advance_to(7.5)                   # next calendar day
	var next_day: bool = dc.can_spar_now()
	# per_day comes from economy.json: 2 allows a second bout the same day
	Economy._data["disciple"]["jobs"]["spar"]["per_day"] = 2
	dc.spar_day = dc.today()
	dc.spar_count = 1
	var two: bool = dc.can_spar_now()
	Economy.reload()
	r.check(early and used and no_second and next_day and two,
		"step3 fix: 陪练 is once per calendar day (a bout at 07:30 means none at 08:30 the same day, one again the next morning); the count comes from economy.json jobs.spar.per_day (2 -> a second bout)",
		"%s %s %s %s %s" % [early, used, no_second, next_day, two])



# ================================================================== 困难 with a human-like reaction delay
## The counter bot of tests/combat_suite.gd, but it does not know when the strike will land: it reacts a FIXED delay after
## the wind-up starts (the red glow), like a person. Dodge sideways (into him at close range = swap behind), then the
## chase-counter with J inside the chase window; otherwise walks in and attacks.
func delay_bot_step(delay: float) -> void:
	if cs._j_down:
		r.key(KEY_J, false)
		cs._j_down = false
	if cs._space_down:
		r.key(KEY_SPACE, false)
		cs._space_down = false
	cs._atk_cd -= 1.0 / 60.0
	var pl := p()
	var enemies: Array = g.combat.engaged_enemies()
	if enemies.is_empty() or pl.dead:
		r.hold_dir(Vector2.ZERO)
		return
	var f: Fighter = enemies[0]
	var to: Vector2 = f.global_position - pl.global_position
	var d := to.length()
	var reach: float = f.stats.attack_range + 40.0 if f.stats.attack_kind != "charge" else f.stats.strike_lunge + 50.0
	if f.state == "windup" and f.t >= delay and d < reach and cs._dodged_for.get(f, -1) != f.strikes \
			and not pl.is_dashing() and pl.dash_cooldown_left <= 0.0:
		var dir := to.normalized().orthogonal()
		if d <= 60.0 and f.stats.attack_kind != "charge":
			dir = to.normalized()
		r.hold_dir(dir)
		cs.press_space()
		cs._dodged_for[f] = f.strikes
		return
	if not pl.is_dashing() and pl.since_dodge_end <= pl.stats.chase_window and d <= pl.stats.chase_range and cs._atk_cd <= 0.0:
		r.hold_dir(Vector2.ZERO)
		cs.press_j()
		cs._atk_cd = 0.1
		return
	r.hold_dir(to.normalized() if d > 34.0 else Vector2.ZERO)
	if d < 62.0 and cs._atk_cd <= 0.0:
		cs.press_j()
		cs._atk_cd = 0.1


func delay_tournament(day: int, delay: float, seed_v: int) -> Dictionary:
	set_day(day, 13.0)
	set_coins(10)
	await r.frames(2)
	await board_e([KEY_1, KEY_2])
	g.combat.rng.seed = seed_v
	cs._dodged_for = {}
	var lost_to := -1
	var guard := 0
	while ar.state != "idle" and guard < 60 * 300:
		if ar.state == "fight":
			delay_bot_step(delay)
		else:
			r.release_all()
		if ar.state == "result" and not g.combat.bout_last_win:
			lost_to = ar.round
		await r.physics_frame
		guard += 1
	r.release_all()
	await r.frames(3)
	return {"won": ar.last_outcome == "champion", "lost_round": lost_to + 1}


func test_hard_reaction_bot() -> void:
	await unlocked_game()
	var day := 3
	var out := {}
	for delay in [0.30, 0.35]:
		var res := []
		for i in 10:
			res.append(await delay_tournament(day, delay, 2000 + i))
			day += 3
		out[delay] = res
	var w30: int = out[0.30].filter(func(o): return o["won"]).size()
	var w35: int = out[0.35].filter(func(o): return o["won"]).size()
	var lost := {}
	for k in out:
		lost[k] = out[k].filter(func(o): return not o["won"]).map(func(o): return o["lost_round"])
	print("HARD REACTION BOT 0.30 s: %d/10  0.35 s: %d/10  lost in rounds %s" % [w30, w35, lost])
	r.check(w30 >= 7 and w35 >= 4, "step3 v1.1 (loosened): 困难 with a human reaction delay (dodges a fixed time after the wind-up starts, real keys, 10 seeded tournaments each): 0.30 s wins %d/10 (>= 7), 0.35 s wins %d/10 (>= 4)" % [w30, w35],
		"losses by round " + str(lost))


# ================================================================== a version-2 save upgrades to version 3
func test_v2_upgrade() -> void:
	await joined_game(false)
	await enter_tournament(3, 30)
	await quick_title()
	dc.spar_day = s3.day_number()       # a 陪练 was recorded
	await r.frames(2)
	smp.save_now("test")
	var cur = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	# the version-2 layout (before 补充 v1.1): no difficulty / 困难 titles, no 陪练 count
	var v2 = cur.duplicate(true)
	v2["version"] = 2
	v2["state"]["step3"]["arena"].erase("difficulty")
	v2["state"]["step3"]["arena"].erase("hard_wins")
	v2["state"]["step3"]["disciple"].erase("spar_count")
	var strict := SaveGame.validate(SaveGame.normalize(v2["state"]))     # v2 state as-is does not pass the v3 check
	await ss._free_game()
	ss._write_raw(JSON.stringify(v2))
	var rd := SaveGame.read()
	await ss._title()
	await r.tap(KEY_ENTER)
	var m: Node = await ss._wait_game()
	if m == null:
		r.check(false, "step3 v1.1: a version-2 save enters the game")
		return
	bind()
	g.daynight.running = false
	var up: Dictionary = rd.get("state", {}).get("step3", {})
	r.check(strict != "" and rd["ok"] and String(up["arena"]["difficulty"]) == "normal" and (up["arena"]["hard_wins"] as Array).is_empty()
		and int(up["disciple"]["spar_count"]) == 1 and ar.wins == [1] and dc.state == "joined" and ar.difficulty == "normal" and dc.spar_count == 1
		and smp.coins == int(cur["state"]["sample"]["coins"]),
		"step3 v1.1: a version-2 save (no difficulty / 困难 titles / 陪练 count) upgrades to version %d on 继续游戏: 普通, no 困难 titles, the recorded 陪练 counts once; everything else as saved" % SaveGame.VERSION, strict)
	smp.save_now("test")
	var after = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	r.check(int(after["version"]) == SaveGame.VERSION and after["state"]["step3"]["arena"].has("hard_wins"), "step3 v1.1: and it is written back as version %d" % SaveGame.VERSION)
