extends RefCounted
## 武学与经营 · 第一批 · 经营 (B) checks (docs/design/武学与经营-第一批-方案-v1.md 第二、三、三点五、五节), run by
## tests/run_tests.gd, or alone:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-farm
## (add --fm=name,name to run some of its tests only).
## Real keys (E / 1-5 / B / ←→↑↓ / Q / Enter / T / Esc / WASD) and real physics wherever the player does something; state is
## set directly only for starting points (the clock, coins, seeds / a 库房 count, a plot already planted, the disciple's
## job when the job itself is not what is checked) - never for the result that is checked.

var r
var ss
var t3
var s4
var g: Node
var story: Story
var dlg: Dialogue
var smp: Sample
var s3: Step3
var gd: Guide
var fm: Farm
var qb: QuestBoard
var sch: Schedule
var only: Array = []
var report := {}

const PLAN_CROPS := {"greens": [2, 1, 5], "radish": [3, 2, 9], "pumpkin": [6, 4, 22]}


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
		if String(a).begins_with("--fm="):
			only = String(a).trim_prefix("--fm=").split(",")
	ss = load("res://tests/sample_suite.gd").new(r)
	t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	s4 = load("res://tests/step4a_suite.gd").new(r)
	s4.ss = ss
	s4.t3 = t3
	var tests := ["tables", "art", "transition", "open", "seeds", "grow", "sell", "gather", "meal", "egg", "disciple",
		"same_as_t", "advanced", "old_pregrad", "save", "hp135", "layout", "expand", "bucket12", "visual", "save_expand", "minimap", "save_r1"]
	for name in tests:
		if only.is_empty() or name in only:
			await call("test_" + name)
	await ss._free_game()
	SaveGame.erase()
	print("FARM REPORT ", report)


# ================================================================== helpers
func bind() -> void:
	s4.bind()
	g = ss.g
	story = g.story
	dlg = story.dialogue
	smp = g.sample
	s3 = g.step3
	gd = g.guide
	fm = g.farm
	qb = g.quest_board
	sch = g.schedule


func p() -> Player:
	return g.player


## A game after the prologue (the real ending), the clock stopped.
func game(day_idx := 0) -> void:
	await t3.unlocked_game(day_idx)
	bind()
	g.daynight.running = false
	await r.frames(3)


func set_coins(n: int) -> void:
	ss.set_coins(n)


## Plays the running scene to its end; at each choice the next key of `keys` (then KEY_1).
func play_keys(keys: Array, limit := 600) -> Array:
	var seen := []
	var k := 0
	var n := 0
	while story.busy and n < limit:
		if dlg.choosing:
			seen.append({"options": dlg.choice_options.duplicate(), "disabled": dlg.choice_disabled.duplicate()})
			await r.tap(keys[k] if k < keys.size() else KEY_1)
			k += 1
		elif dlg.active and dlg.choice_options.is_empty():
			await r.tap(KEY_E)

		else:
			await r.frames(2)
		n += 1
	await r.frames(3)
	return seen


## E at 厨娘 and the given keys at the menus.
func cook(keys: Array) -> Array:
	await ss.stand_near(ss.npc("bear").global_position)
	await r.tap(KEY_E)
	return await play_keys(keys)


func clock(h: float) -> void:
	g.daynight.set_hour(h)
	await r.frames(3)


## Stand right beside plot i (on the path side) and press E; returns the prompt that was shown.
func at_plot(i: int) -> String:
	var c := fm.plot_center(i)
	# the path side: columns 0 / 2 have their path on the right, 1 / 3 on the left (菜园扩建 v1: 4 columns; the same
	# spots as before for the west 6)
	var col := int(floor((c.x - fm.field_pos().x) / 64.0))
	var side := 1.0 if col % 2 == 0 else -1.0
	await r.teleport(c + Vector2(side * 14.0, 4.0))
	await r.frames(2)
	var t: Dictionary = story.interaction_target()
	return String(t.get("prompt", "")) if String(t.get("kind", "")) == "farm" and int(t.get("plot", -1)) == i else ""


func e_plot(i: int, keys: Array = []) -> String:
	var pr := await at_plot(i)
	await r.tap(KEY_E)
	await r.frames(2)
	if story.busy:
		await play_keys(keys)
	return pr


func open_farm_direct() -> void:
	# a starting point (the opening itself is checked by test_open with real keys)
	fm.opened = true
	story.flags["repair_farm"] = true
	fm._refresh_visuals()
	await r.frames(2)


func expand_farm_direct() -> void:
	# a starting point (the expansion itself is checked by test_expand with real keys)
	fm.opened = true
	fm.expanded = true
	story.flags["repair_farm"] = true
	story.flags["repair_farm_expand"] = true
	fm._refresh_visuals()
	await r.frames(3)


func well_e() -> void:
	await r.teleport(fm._v(fm.data["well"]["pos"]) + Vector2(0, 22))
	await r.frames(2)
	await r.tap(KEY_E)
	await r.frames(2)


func farm_obs() -> Dictionary:
	return {"plots": str(fm.plots), "store": str(fm.store), "seeds": str(fm.seeds), "bucket": fm.bucket, "egg": fm.egg,
		"meal": fm.meal_active(), "bonus": fm.applied_bonus, "maxhp": p().stats.max_hp,
		"ready": fm.gdata["spots"].map(func(sp): return fm.spot_ready(String(sp["id"]))), "coins": smp.coins,
		"dwaters": int(fm.stats["disciple_waters"]), "hour": g.daynight.hour, "total": g.daynight.total_hours,
		"expanded": fm.expanded, "east": range(6, fm.plots.size()).reduce(func(acc, i): return acc + int(fm.plots[i]["days"]), 0)}


# ================================================================== tables
func test_tables() -> void:
	var d := Farm.load_data()
	var bad := []
	for c in PLAN_CROPS:
		var cd: Dictionary = d["crops"][c]
		if [int(cd["seed_price"]), int(cd["days"]), int(cd["sell"])] != PLAN_CROPS[c]:
			bad.append(c)
	var gdat := Farm.load_gather()
	var kinds := {}
	for sp in gdat["spots"]:
		kinds[String(sp["kind"])] = int(kinds.get(String(sp["kind"]), 0)) + 1
	var m: Dictionary = d["meal"]
	var adv: Array = Guide.load_data()["advanced"]["steps"]
	var rewards := adv.map(func(x): return int(x["reward"]))
	var tr: Dictionary = Guide.load_data()["prologue_transition"]
	# 菜园扩建 v1 changed three numbers of this old check (方案 "数字"): plots 6 -> 6 west + 6 east (12), a bucket 6 -> 12
	# waterings, buy at most 6 -> 12; and 扩建菜园 40 文 家业 +1 joins 开菜园. Every other number is checked as before.
	var east: Array = d["expand"]["plots"]
	var pitch_ok: bool = east.size() == 6
	for i in east.size():
		var w: Array = d["plots"][i]
		pitch_ok = pitch_ok and int(east[i][0]) == int(w[0]) + 128 and int(east[i][1]) == int(w[1])     # (same rows, two columns on)
	r.check(bad.is_empty() and Economy.price("farm") == 40 and int(Economy.repair("farm")["estate"]) == 1 and Economy.REPAIRS.size() == 3
		and d["plots"].size() == 6 and pitch_ok and Farm.plot_positions().size() == 12 and int(d["bucket_uses"]) == 12
		and int(d["grow_hour"]) == 8 and int(d["disciple_water_hour"]) == 9 and int(d["seed_max"]) == 12
		and Economy.price("farm_expand") == 40 and int(Economy.repair("farm_expand")["estate"]) == 1,
		"farm 二.1 / 菜园扩建: 开菜园 40 文 家业 +1 (beside the three repairs) opens 6 plots, 扩建菜园 40 文 家业 +1 the east 6 (x 1792 / 1856, same 64 px pitch) = 12; 青菜 2/1 天/5, 萝卜 3/2/9, 南瓜 6/4/22; a bucket waters 12 times; growth 08:00, 师弟 09:00; buy 1-12", str([bad, east]))
	r.check(kinds == {"shoots": 4, "herbs": 4} and int(gdat["items"]["shoots"]["sell"]) == 4 and int(gdat["items"]["herbs"]["sell"]) == 6
		and int(gdat["respawn_hour"]) == 8, "farm 二.4: 竹笋 4 处, 草药 4 处, 卖 4 / 6 文, 每天 08:00 长回来", str(kinds))
	r.check(int(m["herbs"]) == 2 and int(m["greens"]) == 1 and int(m["hp_bonus"]) == 15 and int(d["radish_egg"]["coins"]) == 10,
		"farm 二.5: 药膳 = 2 草药 + 1 青菜, 生命上限 +15; 萝卜彩蛋赔 10 文")
	r.check(rewards == [15, 5, 5, 10] and rewards.reduce(func(a, x): return a + x, 0) == 35 and int(Guide.load_data()["advanced"]["fame_need"]) == 2
		and float(tr["fade_out_seconds"]) == 1.5 and float(tr["caption_seconds"]) == 2.0 and float(tr["fade_in_seconds"]) == 1.5,
		"farm 三 / 三点五: 进阶 rewards 15/5/5/10 (35), 第 4 步 needs 名望 2; the transition 1.5 s / 2 s / 1.5 s", str(rewards))
	# the gathering spots are separate from the 挖竹笋 委托's spots
	var jd = JSON.parse_string(FileAccess.get_file_as_string("res://data/jianghu.json"))
	var near := []
	for sp in gdat["spots"]:
		for q in jd["places"]["shoot_spots"] + jd["places"]["jade_spots"]:
			if Vector2(sp["pos"][0], sp["pos"][1]).distance_to(Vector2(q[0], q[1])) < 60.0:
				near.append(sp["id"])
	r.check(near.is_empty(), "farm 二.4: no gathering spot lies on (or next to) a 委托 spot", str(near))


# ================================================================== art
func test_art() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/manifest.json"))
	# 菜园扩建 v1: the weed / tilled layers grew from the west strip (96x160) to the whole fenced field (224x160) - the
	# old check with the new size; every other picture as before.
	var sizes := {"farm_weeds.png": Vector2(224, 160), "farm_tilled.png": Vector2(224, 160), "plot_wet.png": Vector2(32, 32),
		"crops.png": Vector2(128, 96), "ripe_sparkle.png": Vector2(64, 16), "gather_shoots.png": Vector2(96, 32),
		"gather_herbs.png": Vector2(96, 32), "bucket.png": Vector2(32, 16), "note.png": Vector2(16, 16)}
	var bad := []
	for f in sizes:
		var t: Texture2D = load("res://assets/farm/" + f) if ResourceLoader.exists("res://assets/farm/" + f) else null
		if t == null or t.get_size() != sizes[f]:
			bad.append(f)
		var src := ProjectSettings.globalize_path("res://").path_join("../pixel2d/farm/output/" + f)
		if not FileAccess.file_exists(src) or FileAccess.get_md5(src) != FileAccess.get_md5("res://assets/farm/" + f):
			bad.append("sync " + f)
	r.check(man is Dictionary and bad.is_empty(), "farm art: the 9 pictures are in assets/farm (sizes as planned) and byte-equal to pixel2d/farm/output", str(bad))


# ================================================================== 三点五 the prologue transition
func test_transition() -> void:
	await ss.new_game()
	bind()
	await ss.finish_scene()
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		story.flags[f] = true
	story.set_stage(8)
	g.daynight.restore(10.0, 10.0)
	await ss.stand_near(ss.npc("crane").global_position)
	await r.tap(KEY_E)
	var frame := 0
	var black_at := -1
	var light_at := -1
	var start_fade := -1
	var outside_black := false
	var caption_on_black := false
	var unlocked_before_light := false
	var toast_before_light := false
	var choice_seen := false
	var esc_opened := false
	var esc_tried := false
	var moved_during := false
	var obj_during := []
	var coins_toast_at := -1
	for i in 2400:
		var pf: PrologueFade = story.prologue_fade
		var a := pf.alpha() if pf != null else 0.0
		if dlg.choosing or story.prologue_end.is_open:
			choice_seen = true
		if pf != null and pf.is_open:
			if start_fade < 0:
				start_fade = frame
			if g.hud.objective_label.text != "":
				obj_during.append(g.hud.objective_label.text)
			if a >= 0.999 and black_at < 0:
				black_at = frame
			if a >= 0.999:
				outside_black = outside_black or (g.interiors.room_at(p().global_position) == "" and g.camera_target == null)
				caption_on_black = caption_on_black or (gd.caption_showing() and gd.caption_label.text == "序章 · 完")
				if not esc_tried:
					esc_tried = true
					await r.tap(KEY_ESCAPE)
					frame += 4
					esc_opened = g.pause_menu.is_open
					if esc_opened:
						await r.tap(KEY_ESCAPE)
					var pos0 := p().global_position
					await r.push(Vector2.DOWN, 0.2)
					frame += 13
					moved_during = p().global_position.distance_to(pos0) > 1.0
			if smp.unlocked:
				unlocked_before_light = true
			if smp.toasts.any(func(t): return "本钱" in t):
				toast_before_light = true
		elif start_fade >= 0 and light_at < 0:
			light_at = frame
		if coins_toast_at < 0 and smp.toasts.any(func(t): return "本钱" in t):
			coins_toast_at = frame
		if story.sect_book.is_open:
			await r.tap(KEY_ESCAPE)
			frame += 4
		elif dlg.active and not (pf != null and pf.is_open):
			await r.tap(KEY_E)
			frame += 4
		elif light_at >= 0 and not story.busy and not gd._intro_pending and smp.unlocked:
			break
		else:
			await r.physics_frame
			frame += 1
	await r.frames(3)
	var fade_s := float(black_at - start_fade) / 60.0
	var total_s := float(light_at - start_fade) / 60.0
	report["transition"] = [fade_s, total_s]
	r.check(black_at > 0 and fade_s > 1.3 and fade_s < 1.8 and total_s > 4.6 and total_s < 5.6,
		"farm 三点五: after 师父's last line the screen darkens slowly to full black (%.2f s), the whole transition ~5 s (%.2f s)" % [fade_s, total_s])
	r.check(outside_black and caption_on_black and obj_during.is_empty(),
		"farm 三点五: while it is black the rabbit is already outside the hall (camera back on him) and 「序章 · 完」 shows; no objective line meanwhile (never 序章完成)", str(obj_during))
	r.check(not unlocked_before_light and not toast_before_light and coins_toast_at >= light_at and smp.unlocked and smp.coins == 30
		and gd.track == "guide" and g.hud.minimap.track_active and g.hud.objective_label.text.begins_with("目标：指引 1/5"),
		"farm 三点五: only after it is light again: everything opens, 本钱 +30, the guide's step 1 and the gold arrow", str([coins_toast_at, light_at]))
	r.check(not choice_seen and esc_tried and not esc_opened and not moved_during,
		"farm 三点五: no choice box at all; during the transition Esc does not open the page and the rabbit cannot move", str([choice_seen, esc_opened, moved_during]))
	var before2 := p().global_position
	await r.push(Vector2.DOWN, 0.4)
	var it: Interiors = g.interiors
	r.check(p().global_position.distance_to(before2) > 8.0 and it.room_at(p().global_position) == "" and p().facing == "down"
		and before2.distance_to(it.exit_spot("hall")) < 40.0,
		"farm 三点五: lit again he stands at the hall door outside and walks with the real keys", str([before2, it.exit_spot("hall")]))


# ================================================================== 二.1 开菜园
func test_open() -> void:
	await game()
	var fr: Array = fm.data["field"]["collider"]
	var inside := Vector2(1712, 1040)
	var closed_ok: bool = fm.weeds_sprite.visible and not fm.tilled_sprite.visible and not r.is_free(inside)
	await r.teleport(Vector2(1640, 1040))
	var no_prompt: bool = String(story.interaction_target().get("kind", "")) != "farm"
	# 39 coins: 修厨房 -> 3 菜园和买卖 -> 1 开菜园 -> 1 是 -> "还差 1 文"
	set_coins(39)
	ss._watch_lines()
	var m1 := await cook([KEY_3, KEY_1, KEY_1])
	var short: bool = smp.coins == 39 and not fm.opened and "铜钱不够，还差 1 文。" in ss.seen_lines
	var first_menu: Array = m1[0]["options"] if m1.size() > 0 else []
	var cook_menu: Array = m1[1]["options"] if m1.size() > 1 else []
	set_coins(45)
	var est0 := s3.value("estate")
	await cook([KEY_3, KEY_1, KEY_1])
	await r.frames(5)
	var opened_ok: bool = fm.opened and smp.coins == 5 and story.flags.get("repair_farm", false) and s3.value("estate") == est0 + 1
	var bk: Array = await t3.book_open_lines()
	# (菜园扩建 v1: the weed layer no longer goes away - it stays on the east part until 扩建菜园; the old "weeds hidden"
	# becomes "tilled exactly over the west 6 plots, weeds exactly over the rest", the same strength)
	var vis_ok: bool = fm.tilled_sprite.visible and fm.tilled_sprite.region_rect == Rect2(0, 0, 96, 160) and fm.weeds_sprite.visible \
		and fm.weeds_sprite.region_rect == Rect2(96, 0, 128, 160) and r.is_free(inside) and not r.is_free(Vector2(1840, 1040))
	r.check(closed_ok and no_prompt, "farm 二.1: before 开菜园 the 6 plots lie under the weed layer (the field is solid, no prompt)")
	r.check(first_menu == ["是", "否", "菜园和买卖"] and cook_menu == ["开菜园（40 文）", "卖东西", "做药膳", "没事了"] and short,
		"farm 二.1: 厨娘 (real keys): 修厨房's 是 / 否 keep their keys, 3 = 菜园和买卖 -> 开菜园（40 文）/ 卖东西 / 做药膳 / 没事了; with 39 文 '还差 1 文', nothing taken",
		str([first_menu, cook_menu]))
	r.check(opened_ok and vis_ok and "开了菜园" in bk[1], "farm 二.1: 40 文 -> the tilled layer, the plots can be walked between, 家业 +1, 门派簿 '开了菜园'",
		str([fm.opened, smp.coins, s3.value("estate"), est0]))
	await r.teleport(Vector2(1712, 1040))
	await r.push(Vector2.UP, 0.3)
	await r.push(Vector2.DOWN, 0.9)
	var walked: bool = p().global_position.y > 1060.0
	# the 修缮 tab lists 开菜园 (done), 修好之后 she opens the menu at once with 买种子 first
	var tab: Array = gd._tab_repair()
	var farm_item := tab.filter(func(it): return "开菜园" in String(it["text"]))
	story.flags["repair_kitchen"] = true
	smp.apply_repair_visuals("kitchen")
	# (菜园扩建 v1: opened and not yet expanded, her menu has 扩建菜园 before 没事了 - so 没事了 is key 5 now)
	var m3 := await cook([KEY_5])
	r.check(walked and farm_item.size() == 1 and String(farm_item[0]["state"]) == "done" and m3.size() == 1
		and m3[0]["options"] == ["买种子", "卖东西", "做药膳", "扩建菜园（40 文）", "没事了"],
		"farm 二.1 / 三: he walks the farm path (real keys); the 修缮 tab lists 开菜园 (done); after the kitchen repair her talk ends with the menu (买种子 now)",
		str([walked, farm_item, m3]))


# ================================================================== 二.1 seeds
func test_seeds() -> void:
	await game()
	await open_farm_direct()
	story.flags["repair_kitchen"] = true
	set_coins(20)
	# 买种子 -> 青菜 -> 3 颗 (6 文)
	var m := await cook([KEY_1, KEY_1, KEY_3])
	var three: bool = int(fm.seeds["greens"]) == 3 and smp.coins == 14
	var counts: Array = m[2]["options"] if m.size() > 2 else []
	# 南瓜 -> 更多…… -> 6 颗 (36 文): 还差 22 文
	ss._watch_lines()
	var m2 := await cook([KEY_1, KEY_3, KEY_4, KEY_3])
	var short: bool = int(fm.seeds["pumpkin"]) == 0 and smp.coins == 14 and "铜钱不够，还差 22 文。" in ss.seen_lines
	var more: Array = m2[3]["options"] if m2.size() > 3 else []
	# 萝卜 -> 更多 -> 4 颗 (12 文)
	await cook([KEY_1, KEY_2, KEY_4, KEY_1])
	# (菜园扩建 v1: seed_max 12 - the 4/5/6 page now ends with one more 更多…… to 8/10/12, checked in test_bucket12)
	r.check(three and counts == ["1 颗 · 2 文", "2 颗 · 4 文", "3 颗 · 6 文", "更多……", "算了"] and more == ["4 颗 · 24 文", "5 颗 · 30 文", "6 颗 · 36 文", "更多……", "算了"]
		and short and int(fm.seeds["radish"]) == 4 and smp.coins == 2,
		"farm 二.1: 买种子 (real keys): pick the seed, then 1-6 颗 (1/2/3, 更多…… 4/5/6, 更多…… on to the third page) at 2 / 3 / 6 文 each; not enough coins -> '还差 N 文', nothing bought",
		str([counts, more, fm.seeds, smp.coins]))


# ================================================================== 二.1 plant / water / grow / harvest
func test_grow() -> void:
	await game()
	await open_farm_direct()
	fm.seeds["greens"] = 2
	fm.seeds["radish"] = 1
	await clock(10.0)
	var pr0 := await at_plot(0)
	await r.tap(KEY_E)
	var menu := await play_keys([KEY_1])
	var planted: bool = String(fm.plots[0]["crop"]) == "greens" and int(fm.seeds["greens"]) == 1
	await e_plot(1, [KEY_2])
	# no water yet: E on the plot -> "桶里没水了"
	var pr1 := await e_plot(0)
	var dry: bool = not bool(fm.plots[0]["wet"]) and "桶里没水了，去井边打水" in fm.toasts
	await well_e()
	# (菜园扩建 v1: a bucket waters 12 times now, was 6 - so full = 12 and 11 left after one)
	var full: bool = fm.bucket == 12
	await e_plot(0)
	var wet: bool = bool(fm.plots[0]["wet"]) and fm.bucket == 11 and fm.wet_sprites[0].visible
	r.check(pr0 == "按 E 种菜" and menu.size() == 1 and menu[0]["options"] == ["青菜（种子 2 颗）", "萝卜（种子 1 颗）", "南瓜（种子 0 颗）", "算了"]
		and menu[0]["disabled"][2] and planted, "farm 二.1: E on an empty plot -> pick a seed you have (南瓜 greyed with none) -> planted", str([pr0, menu, fm.plots[0], fm.seeds]))
	r.check(pr1 == "按 E 浇水（桶里 0 次）" and dry and full and wet,
		"farm 二.1: without water '桶里没水了'; E at the well fills the bucket (12); E on the plot waters it (dark soil, 11 left)", str([pr1, fm.bucket]))
	# 08:00: the watered greens are ripe (1 day); the unwatered radish neither grows nor dies, for days
	await t3.advance_to(8.0)
	var ripe0: bool = fm.ripe(0) and int(fm.plots[1]["days"]) == 0 and String(fm.plots[1]["crop"]) == "radish" and not bool(fm.plots[0]["wet"])
	for i in 3:
		await t3.advance_to(8.0)
	var still: bool = String(fm.plots[1]["crop"]) == "radish" and int(fm.plots[1]["days"]) == 0
	var pr2 := await e_plot(0)
	var got: bool = int(fm.store["greens"]) == 1 and String(fm.plots[0]["crop"]) == "" and not fm.crop_sprites[0].visible
	r.check(ripe0 and still and fm.sparkle_sprites[1].visible == false,
		"farm 二.1: at 08:00 a plot watered the day before grows a day (青菜 ripe); an unwatered one neither grows nor dies (4 days)")
	r.check(pr2 == "按 E 收菜" and got, "farm 二.1: E on the ripe crop -> it goes into the 库房", pr2)
	# watering then the 08:00 boundary: watered after 08:00 counts for the next morning only
	await clock(7.5)
	await e_plot(1)
	await clock(7.9)
	var w_before := bool(fm.plots[1]["wet"])
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	r.check(w_before and int(fm.plots[1]["days"]) == 1 and not bool(fm.plots[1]["wet"]) and fm.crop_sprites[1].region_rect.position.x > 0.0,
		"farm 二.1: watered at 07:30 -> grows at 08:00 the same morning, the wet mark clears, the picture moves on a stage")


# ================================================================== 二.3 sell
func test_sell() -> void:
	await game()
	story.flags["repair_kitchen"] = true
	await open_farm_direct()
	fm.store["greens"] = 2
	fm.store["radish"] = 1
	fm.store["pumpkin"] = 1
	fm.store["shoots"] = 3
	fm.store["herbs"] = 0
	set_coins(0)
	var m := await cook([KEY_2, KEY_1])
	var opts: Array = m[1]["options"] if m.size() > 1 else []
	var dis: Array = m[1]["disabled"] if m.size() > 1 else []
	var veg: bool = smp.coins == 2 * 5 + 9 + 22 and int(fm.store["greens"]) == 0 and int(fm.store["pumpkin"]) == 0
	await cook([KEY_2, KEY_2])
	r.check(opts == ["蔬菜 4 棵 · 41 文", "竹笋 3 份 · 12 文", "草药 0 份 · 0 文", "算了"] and dis[2] and veg and smp.coins == 41 + 12
		and int(fm.store["shoots"]) == 0, "farm 二.3: 卖东西 at 厨娘 (real keys): 青菜 5 / 萝卜 9 / 南瓜 22 / 竹笋 4 / 草药 6 文 (an empty kind greyed)",
		str([opts, smp.coins]))
	set_coins(0)
	ss._watch_lines()
	await cook([KEY_2])
	r.check(smp.coins == 0 and "你手上没什么可卖的呀。" in ss.seen_lines, "farm 二.3: nothing to sell -> her line, nothing changes")


# ================================================================== 二.4 gathering
func test_gather() -> void:
	await game()
	await clock(10.0)
	var bad := []
	for sp in fm.gdata["spots"]:
		var pos := fm._v(sp["pos"])
		var stand: Vector2 = r.find_free_near(pos + Vector2(0, 12), 14)
		if stand == Vector2.INF or not fm.glows[String(sp["id"])].visible:
			bad.append(String(sp["id"]))
	var sp0: Dictionary = fm.gdata["spots"][0]
	var sp4: Dictionary = fm.gdata["spots"][4]
	await r.teleport(r.find_free_near(fm._v(sp0["pos"]) + Vector2(0, 12), 14))
	var pr := String(story.interaction_target().get("prompt", ""))
	var com0: int = g.jianghu.com.offers.size()
	await r.tap(KEY_E)
	await r.teleport(r.find_free_near(fm._v(sp4["pos"]) + Vector2(0, 12), 14))
	var pr4 := String(story.interaction_target().get("prompt", ""))
	await r.tap(KEY_E)
	var got: bool = int(fm.store["shoots"]) == 1 and int(fm.store["herbs"]) == 1 and not fm.glows[String(sp0["id"])].visible
	await r.tap(KEY_E)
	var once: bool = int(fm.store["herbs"]) == 1
	r.check(bad.is_empty(), "farm 二.4: all 8 spots glow after the prologue and can be stood next to", str(bad))
	r.check(pr == "按 E 挖竹笋" and pr4 == "按 E 采草药" and got and once, "farm 二.4: E digs a shoot / picks herbs into the 库房 (the glow goes; once a day)", str([pr, pr4]))
	await clock(7.9)
	var not_yet: bool = not fm.spot_ready(String(sp0["id"]))
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	r.check(not_yet and fm.spot_ready(String(sp0["id"])) and fm.glows[String(sp0["id"])].visible, "farm 二.4: they grow back at 08:00")
	# the 挖竹笋 委托: its shoots are its own - they never reach the 库房, ours never count for it
	await s4.day_with("shoots")
	var took: bool = await s4.accept_commission("shoots")
	var o: Dictionary = g.jianghu.com.find_taken("shoots")
	var c0 := int(o.get("count", 0))
	await r.teleport(r.find_free_near(fm._v(sp0["pos"]) + Vector2(0, 12), 14))
	await r.tap(KEY_E)
	var c1 := int(o.get("count", 0))
	var st0 := int(fm.store["shoots"])
	var spots: Array = g.jianghu.com.targets_of(o)
	if not spots.is_empty():
		await r.teleport(r.find_free_near(spots[0] + Vector2(0, 10), 14))
		await r.tap(KEY_E)
		await r.frames(3)
	r.check(took and c1 == c0 and int(o.get("count", 0)) == c0 + 1 and int(fm.store["shoots"]) == st0,
		"farm 二.4: with 挖竹笋 taken, our shoot does not count for it and its shoot does not go into the 库房", str([took, c0, c1, o.get("count"), st0, fm.store["shoots"]]))


# ================================================================== 二.5 药膳
func test_meal() -> void:
	await game()
	story.flags["repair_kitchen"] = true
	await open_farm_direct()
	await clock(10.0)
	fm.store["herbs"] = 3
	fm.store["greens"] = 0
	ss._watch_lines()
	await cook([KEY_3])
	var short: bool = int(fm.store["meal"]) == 0 and "药膳要 2 份草药加 1 棵青菜。你现在有草药 3 份、青菜 0 棵。" in ss.seen_lines
	fm.store["greens"] = 1
	var c0 := smp.coins
	await cook([KEY_3])
	var made: bool = int(fm.store["meal"]) == 1 and int(fm.store["herbs"]) == 1 and int(fm.store["greens"]) == 0 and smp.coins == c0
	r.check(short and made, "farm 二.5: 做药膳 (real keys): 2 草药 + 1 青菜 -> 1 药膳, free; without enough her line says what is missing")
	# eat it in the 库房 page: B, → to 库房 (past 武学), ↓ to 药膳, E
	var base: int = p().stats.max_hp
	await r.tap(KEY_B)
	await r.frames(3)
	var book: SectBook = story.sect_book
	var to_store := 0
	while book.page_id() != "store" and to_store < 4:
		await r.tap(KEY_RIGHT)
		to_store += 1
	var rows := fm.store_rows().size()
	for i in rows:
		if String(fm.store_rows()[fm.store_sel]["key"]) == "meal":
			break
		await r.tap(KEY_DOWN)
	var hp0: int = p().hp
	await r.tap(KEY_E)
	await r.frames(3)
	var still_open: bool = book.is_open and book.page_id() == "store"
	var eaten: bool = int(fm.store["meal"]) == 0 and fm.meal_active() and p().stats.max_hp == base + 15 and p().hp == hp0 + 15
	var page_text: Array = book.page_labels.map(func(l): return l.text)
	await r.tap(KEY_ESCAPE)
	r.check(still_open and eaten and page_text.any(func(t): return "药膳在身：生命上限 +15" in String(t)),
		"farm 二.2 / 二.5: 库房 page (real keys B, →, ↓, E): eating 药膳 -> 生命上限 +15 (%d -> %d), the page stays open and says so" % [base, p().stats.max_hp],
		str(page_text))
	# 吐纳功 stacks: 100 + 20 + 15 = 135
	var sk = g.get("skills")
	var stack: bool = true
	if sk != null and sk.has_method("learn"):
		sk.learn("tuna", false)
		await r.frames(2)
		stack = p().stats.max_hp == 135
	r.check(stack, "farm 二.5: with 吐纳功 learned the two add up: 生命上限 135", str(p().stats.max_hp))
	# in a fight it cannot be eaten
	fm.store["meal"] = 1
	fm.meal_until = -1.0
	await r.frames(2)
	g.combat.spar_state = "fighting"
	var msg := fm.eat_meal()
	g.combat.spar_state = "none"
	r.check(msg == "正在战斗，不能吃东西" and int(fm.store["meal"]) == 1, "farm 二.5: not during a fight", msg)
	fm.eat_meal()
	await clock(7.9)
	var on := fm.meal_active()
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	r.check(on and not fm.meal_active() and fm.applied_bonus == 0 and p().stats.max_hp == (120 if sk != null and sk.has_learned("tuna") else 100)
		and "药膳的劲儿过去了" in fm.toasts, "farm 二.5: at the next 08:00 the bonus is gone (back to the 吐纳功 value)", str(p().stats.max_hp))


# ================================================================== 二.1 萝卜彩蛋
func test_egg() -> void:
	await game()
	await open_farm_direct()
	await clock(10.0)
	fm.seeds["radish"] = 2
	await e_plot(2, [KEY_2])
	fm.bucket = 6
	await e_plot(2)
	await t3.advance_to(8.0)
	await clock(10.0)
	await e_plot(2)
	await t3.advance_to(8.0)
	var ripe: bool = fm.ripe(2) and fm.egg == "ripe"
	var c0 := smp.coins
	await clock(23.5)
	await clock(0.5)
	var eaten: bool = String(fm.plots[2]["crop"]) == "" and bool(fm.plots[2]["note"]) and fm.note_sprites[2].visible and fm.egg == "eaten" and smp.coins == c0
	await clock(8.1)
	var paid: bool = smp.coins == c0 + 10 and fm.egg == "done" and fm.toasts.any(func(t): return "萝卜钱" in String(t))
	ss._watch_lines()
	var pr := await e_plot(2)
	var read: bool = "欠你一根萝卜——师兄" in ss.seen_lines and not bool(fm.plots[2]["note"])
	r.check(ripe and eaten and paid, "farm 二.1 萝卜彩蛋: the first radish ripens; that night 师兄 eats it and leaves a note; the next morning +10 文")
	r.check(pr == "按 E 看字条" and read, "farm 二.1 萝卜彩蛋: E on the note: '欠你一根萝卜——师兄'", pr)
	# only once: a second radish ripens and stays
	await e_plot(3, [KEY_2])
	for d in 2:
		await clock(10.0)
		await e_plot(3)
		await t3.advance_to(8.0)
	var c1 := smp.coins
	await clock(23.0)
	await clock(9.0)
	r.check(fm.ripe(3) and String(fm.plots[3]["crop"]) == "radish" and smp.coins == c1 and fm.egg == "done", "farm 二.1 萝卜彩蛋: only once - the next radish is left alone")


# ================================================================== 1.5 师弟种地
func test_disciple() -> void:
	await t3.joined_game(false, 9.0)
	bind()
	g.daynight.running = false
	var hint: bool = fm.toasts.filter(func(t): return String(t) == "师弟可以派去种地，每天帮你浇水。（派活：找师弟按 E）").size() == 1
	fm.on_disciple_joined()
	var once: bool = fm.toasts.filter(func(t): return "师弟可以派去种地" in String(t)).size() == 1
	var dc: Disciple = s3.disciple
	set_coins(100)
	# farm not open: 派活 has no 种地
	var o1: Array = await t3.talk_disciple([KEY_1, KEY_4])
	var closed_menu: Array = o1[1]["options"] if o1.size() > 1 else []
	await open_farm_direct()
	var o2: Array = await t3.talk_disciple([KEY_1, KEY_4])
	var menu: Array = o2[1]["options"] if o2.size() > 1 else []
	r.check(hint and once and closed_menu == ["帮厨", "陪练", "打扫", "算了"] and menu == ["帮厨", "陪练", "打扫", "种地", "算了"]
		and dc.job_next == "farm", "farm 1.5: the one-time hint when he joins; 派活 offers 种地 only once the farm is open (5th key set: 种地 picked with 4)",
		str([closed_menu, menu, dc.job_next]))
	# plots: 0-2 planted (2 already watered by the rabbit), 3 ripe, 4-5 empty
	for i in 3:
		fm.plots[i] = {"crop": "pumpkin", "days": 0, "wet": false, "note": false}
	fm.plots[3] = {"crop": "greens", "days": 1, "wet": false, "note": false}
	fm._refresh_visuals()
	await t3.advance_to(8.0)      # day 1 of the job
	await clock(8.5)
	fm.bucket = 6
	await e_plot(2)               # the rabbit waters plot 2 himself before 09:00 (real E)
	var w0 := int(fm.stats["disciple_waters"])
	var pw0 := int(fm.stats["watered"])
	await clock(8.9)
	var before9: bool = not bool(fm.plots[0]["wet"]) and bool(fm.plots[2]["wet"])
	await clock(9.1)
	var watered: bool = bool(fm.plots[0]["wet"]) and bool(fm.plots[1]["wet"]) and int(fm.stats["disciple_waters"]) == w0 + 2 \
		and int(fm.stats["watered"]) == pw0 and not bool(fm.plots[3]["wet"])
	var no_sow: bool = String(fm.plots[4]["crop"]) == "" and String(fm.plots[3]["crop"]) == "greens"
	await clock(12.0)
	var place_ok: bool = dc.place == "farm" and dc.bucket_sprite.visible and dc.npc.visible
	await clock(22.0)
	var night_ok: bool = dc.place == "night"
	await t3.advance_to(8.0)
	var grew: bool = int(fm.plots[0]["days"]) == 1 and int(fm.plots[1]["days"]) == 1
	r.check(before9 and watered and no_sow, "farm 1.5: at 09:00 he waters every planted plot not watered yet (not the one already wet, not the ripe one), never sows or harvests")
	r.check(place_ok and night_ok and grew, "farm 1.5: by day he walks the farm with a bucket, at night the old dorm; the plots he watered grow at the next 08:00",
		str([dc.place, place_ok, night_ok, grew]))
	# another job: from the next day on no watering
	await clock(10.0)
	await t3.talk_disciple([KEY_1, KEY_3])
	await clock(11.0)
	for i in 3:
		fm.plots[i]["wet"] = false
	await t3.advance_to(8.0)
	await clock(9.5)
	var stopped: bool = not bool(fm.plots[0]["wet"]) and dc.job_today() == "sweep"
	r.check(stopped and dc.upkeep_paid > 0, "farm 1.5: changed to 打扫 -> from the next day he does not water any more (upkeep unchanged)", str([stopped, dc.job_today()]))
	# board 收徒 tab says 师弟：种地 when that is his job
	dc.job = "farm"
	dc.job_from = -1
	var tab: Array = gd._tab_disciple()
	r.check(String(tab[0]["text"]).begins_with("师弟：种地"), "farm 1.5: the 任务看板 收徒 tab shows '师弟：种地'", str(tab[0]["text"]))


# ================================================================== 等到天亮 / 打坐 / T: the same farm
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


## n nights from `start` with method: "wait" (the 等到天亮 button), "sit" (打坐, A's meditate), "t" (T hour by hour). Between
## nights the day goes on with T to 21:00.
func nights(method: String, n: int) -> void:
	for k in n:
		if method == "t":
			var to := fposmod(8.0 - g.daynight.hour, 24.0)
			for i in int(round(to)):
				await r.tap(KEY_T)
				await r.frames(2)
		elif method == "wait":
			await sch_open_wait()
		else:
			g.schedule.meditate("静坐吐纳……")
			await g.schedule.wait_finished
		await r.frames(6)
		if k < n - 1:
			for i in 13:
				await r.tap(KEY_T)
				await r.frames(2)


func sch_open_wait() -> void:
	await r.tap(KEY_Q)
	await r.process_frame
	await r.tap(KEY_ENTER)
	for i in 600:
		await r.physics_frame
		if not g.schedule.waiting and i > 5:
			break


func test_same_as_t() -> void:
	await t3.joined_game(true, 9.0)
	bind()
	g.daynight.running = false
	# (菜园扩建 v1: was 6 plots on an opened farm; now the expanded farm with all 12 planted - the same checks over twice
	# the plots, plus that an east plot really grew and was watered by 师弟)
	await expand_farm_direct()
	var dc: Disciple = s3.disciple
	dc.job_next = "farm"
	dc.job_from = dc.work_day()        # (starting point: his job is 种地 from today)
	set_coins(60)
	for i in 12:
		fm.plots[i] = {"crop": ["greens", "radish", "pumpkin"][i % 3], "days": 0, "wet": i < 3 or i == 6, "note": false}
	fm.store["meal"] = 1
	fm.store["herbs"] = 2
	await clock(19.0)
	fm.eat_meal()
	fm.picked[String(fm.gdata["spots"][0]["id"])] = g.daynight.day_index(8)
	fm.picked[String(fm.gdata["spots"][5]["id"])] = g.daynight.day_index(8)
	fm._refresh_visuals()
	await clock(21.0)
	var st0: Dictionary = SaveGame.roundtrip(SaveGame.capture(g))
	var runs := {}
	for method in ["wait", "sit", "t"]:
		await restored(st0)
		await nights(method, 3)
		runs[method] = farm_obs()
	var bad := []
	for k in runs["t"]:
		for mth in ["wait", "sit"]:
			if str(runs[mth][k]) != str(runs["t"][k]):
				bad.append("%s %s: %s / T %s" % [mth, k, runs[mth][k], runs["t"][k]])
	report["same_as_t"] = runs["t"]
	var a: Dictionary = runs["t"]
	var happened: bool = int(a["dwaters"]) > 0 and "\"days\": 2" in String(a["plots"]) and not bool(a["meal"]) and a["ready"].all(func(x): return x)
	var east_grew: bool = runs["t"].has("east") and int(runs["t"]["east"]) >= 8 and bool(runs["t"]["expanded"])     # (only plot 6 starts wet: >= 8 days in the east needs 师弟's east waterings)
	r.check(happened and east_grew, "farm 五 / 菜园扩建: these 3 nights really have farm events on all 12 plots (growth east too, 师弟's 09:00 watering, spots back, the 药膳 gone)", str(a))
	r.check(bad.is_empty(), "farm 五: 3 nights by 等到天亮, by 打坐 and by T hour by hour end in the same farm: plots, 库房, spots, 药膳 / 生命上限, coins, clock",
		str(bad.slice(0, 6)))


# ================================================================== 三 进阶指引
func test_advanced() -> void:
	await game()
	await clock(10.0)
	var before: bool = gd.track == "guide" and not gd.graduated and gd._tab_guide().size() == 7
	# 出师 (starting point: the five steps paid) -> 进阶 1/4
	for i in 5:
		gd.done[i] = true
		gd.paid[i] = true
	await r.frames(4)
	var adv_on: bool = gd.graduated and gd.track == "adv" and g.hud.objective_label.text == "目标：进阶 1/4：开菜园，种下第一颗种子" and g.hud.minimap.track_active
	await r.tap(KEY_Q)
	await r.process_frame
	var marks := 0
	var adv_items := 0
	for l in qb.item_labels:
		if l.text.begins_with("【追踪中】"):
			marks += 1
		if "进阶" in l.text:
			adv_items += 1
	await r.tap(KEY_Q)
	await r.process_frame
	r.check(marks == 1 and adv_items >= 4, "farm 三: the 任务看板 新手指引 tab lists the 进阶 steps after 出师, 【追踪中】 on the current one only", str([marks, adv_items]))
	r.check(before and adv_on, "farm 三: 进阶 appears only after 出师: then 'Advanced 进阶 1/4' on the objective line and the gold arrow (厨娘)", g.hud.objective_label.text)
	# out of order: 燕回旋 learned first (名望 enough) -> step 4 paid at once (10)
	var sk = g.get("skills")
	var c0 := smp.coins
	var low_text := ""
	if sk != null:
		# 名望 1: step 4 says how to get more
		for i in 3:
			gd.adv_paid[i] = true
			gd.adv_done[i] = true
		await r.frames(3)
		low_text = g.hud.objective_label.text
		var tab: Array = gd._tab_guide()
		var hint_ok := tab.any(func(it): return "去梅花桩试炼或接悬赏可以涨名望" in String(it["text"]))
		var arrow_trial: bool = gd.target_of("adv") == smp.trial.board_point()
		gd.adv_paid = [false, false, false, false]
		gd.adv_done = [false, false, false, false]
		r.check(low_text == "目标：进阶 4/4：名望到 2 格后找师父（现在 1 格）" and hint_ok and arrow_trial,
			"farm 三: 名望 below 2 -> step 4 says '名望到 2 格后找师父（现在 1 格）', the board adds how to raise it, the arrow points at the trial", low_text)
		sk.learn("swallow_spin", false)
		await r.frames(4)
	var s4_ok: bool = gd.adv_paid[3] and smp.coins == c0 + 10 and not gd.adv_paid[0]
	# step 1 / 2 / 3 with the real things
	await open_farm_direct()
	fm.seeds["greens"] = 2
	await e_plot(0, [KEY_1])
	await r.frames(3)
	var s1: bool = gd.adv_paid[0] and smp.coins == c0 + 25
	await well_e()
	await e_plot(0)
	await t3.advance_to(8.0)
	await e_plot(0)
	await r.frames(3)
	var s2: bool = gd.adv_paid[1] and smp.coins == c0 + 30
	var sp: Dictionary = fm.gdata["spots"][4]
	await r.teleport(r.find_free_near(fm._v(sp["pos"]) + Vector2(0, 12), 14))
	await r.tap(KEY_E)
	fm.store["herbs"] = 2
	await cook([KEY_3, KEY_3])
	await r.frames(4)
	var s3ok: bool = gd.adv_paid[2] and gd.adv_finished and smp.coins == c0 + 35
	var cap: bool = gd.captions.has("进阶 · 完")
	r.check(s4_ok and s1 and s2 and s3ok, "farm 三: done in any order, each paid when done: 燕回旋 +10, 开菜园 + 种下 +15, 浇水 + 收菜 +5, 采集 + 药膳 +5 (35 in all)",
		str([gd.payments.slice(-4), smp.coins - c0]))
	var seen_fin := false
	for i in 900:
		seen_fin = seen_fin or (gd.caption_showing() and gd.caption_label.text == "进阶 · 完")
		if seen_fin and not gd.caption_showing():
			break
		await r.frames(1)
	await r.frames(3)
	r.check(cap and seen_fin and gd.track == "" and g.hud.objective_label.text == "" and not gd.caption_showing(),
		"farm 三: all four -> '进阶 · 完' fades in and out (~2 s), nothing tracked afterwards", str([gd.captions.slice(-3), gd.track, g.hud.objective_label.text, gd.caption_showing()]))
	# an older save (no 'adv' in the guide section, a farm already opened and planted): counts as done, no coins
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	doc["state"]["guide"].erase("adv")
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(5)
	var c2 := smp.coins
	await r.frames(5)
	r.check(gd.adv_done[0] and gd.adv_paid[0] and smp.coins == c2 and not gd.payments.any(func(x): return String(x["what"]).begins_with("adv_")),
		"farm 三: an older save - steps it already meets count as done, no coins paid", str([gd.adv_done, gd.adv_paid, gd.payments]))


# ================================================================== saving
func test_save() -> void:
	await game()
	await open_farm_direct()
	await clock(10.0)
	fm.seeds = {"greens": 1, "radish": 2, "pumpkin": 3}
	fm.plots[0] = {"crop": "radish", "days": 1, "wet": true, "note": false}
	fm.plots[5] = {"crop": "", "days": 0, "wet": false, "note": true}
	fm.bucket = 4
	fm.store = {"greens": 1, "radish": 0, "pumpkin": 2, "shoots": 3, "herbs": 4, "meal": 1}
	fm.picked[String(fm.gdata["spots"][1]["id"])] = g.daynight.day_index(8)
	fm.egg = "eaten"
	fm.egg_plot = 5
	fm.hint_shown = true
	fm.eat_meal()
	await r.frames(3)
	var hp_before: int = p().hp
	var cap0: Dictionary = SaveGame.roundtrip(fm.capture())
	cap0.erase("mark")      # (the settled-up-to clock: the reload runs a few frames before the test stops the clock)
	smp.save_now("test")
	await s4.reload_game()
	bind()
	await r.frames(3)
	var cap1: Dictionary = SaveGame.roundtrip(fm.capture())
	cap1.erase("mark")
	r.check(str(cap0) == str(cap1) and fm.tilled_sprite.visible and fm.wet_sprites[0].visible and fm.note_sprites[5].visible,
		"farm 四: everything of the farm saves and loads (plots, wet, note, bucket, seeds, 库房, picked spots, 药膳 end, egg, hint)", str([cap0, cap1]))
	r.check(fm.meal_active() and p().stats.max_hp == 115 + (20 if g.get("skills") != null and g.skills.has_learned("tuna") else 0) and p().hp == hp_before,
		"farm 四: a save with the 药膳 on loads with 生命上限 +15 and the same HP (not cut at 100)", str([p().stats.max_hp, p().hp, hp_before]))
	# an old save (no farm section): nothing opened, an empty 库房
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	doc["state"].erase("farm")
	doc["state"]["story"]["flags"].erase("repair_farm")
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(3)
	r.check(not fm.opened and fm.weeds_sprite.visible and fm.store.values().all(func(v): return int(v) == 0) and not fm.meal_active()
		and p().stats.max_hp == 100 + (20 if g.get("skills") != null and g.skills.has_learned("tuna") else 0),
		"farm 四: a save without the farm section loads: the farm not opened, the 库房 empty")
	# a broken farm section is refused
	doc["state"]["farm"] = Farm.defaults()
	doc["state"]["farm"]["bucket"] = -3
	r.check(SaveGame.validate(doc["state"]) != "" and Farm.validate(Farm.defaults()) == "", "farm 四: a broken farm section is refused")


# ================================================================== layout zh / en
func test_layout() -> void:
	var lang0 := Lang.current()
	await game()
	story.flags["repair_kitchen"] = true
	await open_farm_direct()
	fm.store["meal"] = 2
	var bad := []
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await r.frames(3)
		var view: Rect2 = g.get_viewport().get_visible_rect()
		await r.tap(KEY_B)
		await r.frames(3)
		var book: SectBook = story.sect_book
		var n := 0
		while book.page_id() != "store" and n < 4:
			await r.tap(KEY_RIGHT)
			n += 1
		await r.frames(4)
		var pr: Rect2 = book.panel.get_global_rect()
		if not view.grow(0.5).encloses(pr) or book.page_id() != "store":
			bad.append("%s store page %s" % [lang, pr])
		await r.tap(KEY_ESCAPE)
		# 厨娘's menu and 卖东西
		await ss.stand_near(ss.npc("bear").global_position)
		await r.tap(KEY_E)
		var k := 0
		while story.busy and k < 200:
			if dlg.choosing:
				var cr: Rect2 = dlg.choice_panel.get_global_rect()
				if not view.grow(0.5).encloses(cr):
					bad.append("%s choice %s" % [lang, cr])
				await r.tap(KEY_4 if dlg.choice_options.size() == 4 else KEY_2)
			elif dlg.active:
				await r.tap(KEY_E)
			else:
				await r.frames(2)
			k += 1
		await r.frames(3)
	Lang.set_lang(lang0)
	r.check(bad.is_empty(), "farm 五: the 库房 page and 厨娘's menus fit the 480x270 screen in Chinese and in English", str(bad))


# ================================================================== R1 F1: an older save loaded before 出师
func test_old_pregrad() -> void:
	await game()
	await clock(10.0)
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	doc["state"]["guide"].erase("adv")        # a save from before 进阶 existed, not graduated yet
	doc["state"].erase("farm")
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(5)
	var not_grad: bool = not gd.graduated and not gd._adv_old_save and gd.adv_done == [false, false, false, false]
	# this session: open the farm, plant a seed (real E), then 出师
	await open_farm_direct()
	fm.seeds["greens"] = 1
	await e_plot(0, [KEY_1])
	var c0 := smp.coins
	for i in 5:
		gd.done[i] = true
		gd.paid[i] = true
	await r.frames(6)
	var grad_coins := int(gd.data.get("graduate_reward", 10))
	r.check(not_grad and gd.graduated and gd.adv_paid[0] and smp.coins == c0 + grad_coins + 15
		and gd.payments.any(func(x): return String(x["what"]) == "adv_farm" and int(x["coins"]) == 15),
		"farm 三 (R1 F1): an older save loaded before 出师 - a 进阶 step done in this session (plant a seed) pays 15 文 once 出师 comes",
		str([not_grad, gd.adv_done, gd.adv_paid, smp.coins - c0, gd.payments]))


# ================================================================== R1: 135 survives a save / load
func test_hp135() -> void:
	await game()
	await clock(10.0)
	var sk = g.get("skills")
	if sk == null or not sk.has_method("learn"):
		r.check(false, "farm 四 (R1): 吐纳功 + 药膳 135 after save / load (no skills node)")
		return
	sk.learn("tuna", false)
	fm.store["meal"] = 1
	fm.eat_meal()
	await r.frames(3)
	p().hp = p().stats.max_hp
	var before: int = p().stats.max_hp
	smp.save_now("test")
	await s4.reload_game()
	bind()
	await r.frames(3)
	r.check(before == 135 and p().stats.max_hp == 135 and p().hp == 135 and fm.meal_active(),
		"farm 四 (R1): with 吐纳功 learned and a 药膳 on, a save loads with 生命上限 135 and HP 135 (not cut)",
		str([before, p().stats.max_hp, p().hp]))


# ================================================================== 菜园扩建 v1 (docs/design/菜园扩建-方案-v1.md)
## 扩建菜园 bought with the real keys: not there before 开菜园; 39 文 short; 40 文 -> east 6 plots, 家业 +1, 门派簿, 修缮栏;
## the east part blocks until then and can be walked into after; an east plot planted / watered / grown / harvested.
func test_expand() -> void:
	await game()
	story.flags["repair_kitchen"] = true          # (her talk then ends with the menu at once)
	var m0 := await cook([KEY_4])
	var menu0: Array = m0[0]["options"] if m0.size() > 0 else []
	var tab0: Array = gd._tab_repair().filter(func(it): return "扩建菜园" in String(it["text"]))
	r.check(menu0 == ["开菜园（40 文）", "卖东西", "做药膳", "没事了"] and tab0.is_empty(),
		"菜园扩建: before 开菜园 there is no 扩建菜园 - not in 厨娘's menu, not in the 修缮 tab", str([menu0, tab0]))
	# 开菜园 (real keys), then the menu offers 扩建菜园 before 没事了
	set_coins(40)
	await cook([KEY_1, KEY_1])
	await r.frames(5)
	var tab1: Array = gd._tab_repair().filter(func(it): return "扩建菜园" in String(it["text"]))
	var tracked: bool = tab1.size() == 1 and String(tab1[0]["state"]) == "open" and String(tab1[0]["text"]) == "修缮：扩建菜园 · 找厨娘（厨房） · 40 文 · 家业 +1" \
		and gd.target_of("repair:farm_expand") == ss.npc("bear").global_position
	# before 扩建: the east part blocks (real walk), its plots are no E target, no map mark
	var east_pt := Vector2(1840, 1040)
	await r.teleport(Vector2(1776, 1040))
	var blocked_tp: bool = p().global_position.x < 1770.0 or not r.is_free(east_pt)
	await r.teleport(Vector2(1745, 1040))
	await r.push(Vector2.RIGHT, 0.6)
	var stopped_x: float = p().global_position.x
	var t_east: Dictionary = fm.interaction_target(fm.plot_center(8), 1e9, {})
	var field_marks: int = fm.poi_points().filter(func(q): return fm.field_rect().has_point(q)).size()
	r.check(fm.opened and not fm.expanded and tracked and not r.is_free(east_pt) and stopped_x < 1762.0 and int(t_east.get("plot", -1)) < 6
		and field_marks == 6 and blocked_tp,
		"菜园扩建: after 开菜园 the 修缮 tab lists 扩建菜园 (找厨娘 · 40 文 · 家业 +1, the arrow to 厨娘); the east part still blocks (real keys: stopped at x %.0f), its plots are no E target, 6 marks" % stopped_x,
		str([tab1, t_east, field_marks]))
	# 39 文: short, nothing changes
	set_coins(39)
	ss._watch_lines()
	var m1 := await cook([KEY_4, KEY_1])
	var menu1: Array = m1[0]["options"] if m1.size() > 0 else []
	var short: bool = not fm.expanded and smp.coins == 39 and "铜钱不够，还差 1 文。" in ss.seen_lines \
		and "花 40 文扩建菜园？东边再开 6 块地。（家业 +1）" in ss.seen_lines
	# 45 文: 扩建
	set_coins(45)
	var est0 := s3.value("estate")
	ss._watch_lines()
	await cook([KEY_4, KEY_1])
	await r.frames(5)
	var done: bool = fm.expanded and smp.coins == 5 and story.flags.get("repair_farm_expand", false) and s3.value("estate") == est0 + 1 \
		and "东边那六块也翻好了，现在一共十二块地。种子我这儿管够。" in ss.seen_lines
	var bk: Array = await t3.book_open_lines()
	var tab2: Array = gd._tab_repair().filter(func(it): return "扩建菜园" in String(it["text"]))
	var m2 := await cook([KEY_4])
	var menu2: Array = m2[0]["options"] if m2.size() > 0 else []
	r.check(menu1 == ["买种子", "卖东西", "做药膳", "扩建菜园（40 文）", "没事了"] and short,
		"菜园扩建: 厨娘 (real keys): 买种子 / 卖东西 / 做药膳 / 扩建菜园（40 文）/ 没事了; she asks first (家业 +1); with 39 文 '还差 1 文', nothing taken", str([menu1, smp.coins]))
	r.check(done and "扩建了菜园" in bk[1] and tab2.size() == 1 and String(tab2[0]["state"]) == "done" and menu2 == ["买种子", "卖东西", "做药膳", "没事了"],
		"菜园扩建: 40 文 -> 扩建 (铜钱 -40, 家业 +1, 门派簿 '扩建了菜园', 修缮 tab 已修好, her line), and her menu is back to 4 items",
		str([fm.expanded, smp.coins, s3.value("estate"), est0, tab2, menu2]))
	# after 扩建: walk into the east part (real keys), 12 marks, 师弟's walk covers the field
	await r.teleport(Vector2(1745, 1040))
	await r.push(Vector2.RIGHT, 0.9)
	var walked_x: float = p().global_position.x
	var marks2: int = fm.poi_points().filter(func(q): return fm.field_rect().has_point(q)).size()
	var wr: Array = fm.walk_rects()
	var reach_east: bool = fm.walk_clear(Vector2(1712, 1040), Vector2(1840, 1060))
	fm.expanded = false
	var reach_before: bool = fm.walk_clear(Vector2(1712, 1040), Vector2(1840, 1060))
	var wr_before: int = fm.walk_rects().size()
	fm.expanded = true
	r.check(r.is_free(east_pt) and walked_x > 1800.0 and marks2 == 12 and wr.size() == 4 and wr_before == 2 and reach_east and not reach_before,
		"菜园扩建: after 扩建 the east part can be walked into (real keys: x %.0f), 12 plot marks; 师弟's farm walk covers the east paths too (blocked before)" % walked_x,
		str([walked_x, marks2, wr, reach_east, reach_before]))
	# an east plot: plant / water / grow / harvest with the real E
	fm.seeds["greens"] = 2
	await clock(10.0)
	var pr6 := await e_plot(6, [KEY_1])
	var pr11 := await e_plot(11, [KEY_1])
	await well_e()
	await e_plot(6)
	await e_plot(11)
	var wet_ok: bool = bool(fm.plots[6]["wet"]) and bool(fm.plots[11]["wet"]) and fm.wet_sprites[11].visible and fm.bucket == 10
	await t3.advance_to(8.0)
	var ripe_ok: bool = fm.ripe(6) and fm.ripe(11) and fm.sparkle_sprites[11].visible
	var prh := await e_plot(11)
	await e_plot(6)
	r.check(pr6 == "按 E 种菜" and pr11 == "按 E 种菜" and wet_ok and ripe_ok and prh == "按 E 收菜" and int(fm.store["greens"]) == 2
		and String(fm.plots[6]["crop"]) == "" and String(fm.plots[11]["crop"]) == "",
		"菜园扩建: the east plots (real E): plant, water from the bucket, grow at 08:00, harvest into the 库房", str([pr6, pr11, prh, fm.plots.slice(6), fm.store]))


## A bucket waters 12 times; the 13th try says to fetch water. 12 seeds bought on the third page (8 / 10 / 12).
func test_bucket12() -> void:
	await game()
	story.flags["repair_kitchen"] = true
	await expand_farm_direct()
	await clock(10.0)
	set_coins(100)
	# 买种子 -> 南瓜 -> 更多…… -> 更多…… -> 12 颗 (72 文)
	var m := await cook([KEY_1, KEY_3, KEY_4, KEY_4, KEY_3])
	var page3: Array = m[4]["options"] if m.size() > 4 else []
	r.check(page3 == ["8 颗 · 48 文", "10 颗 · 60 文", "12 颗 · 72 文", "算了"] and int(fm.seeds["pumpkin"]) == 12 and smp.coins == 28,
		"菜园扩建: 买种子 (real keys) goes up to 12 颗 - the third page 8 / 10 / 12 颗; 12 南瓜 seeds = 72 文", str([page3, fm.seeds, smp.coins]))
	for i in 12:
		await e_plot(i, [KEY_3])
	var planted: bool = fm.plots.all(func(q): return String(q["crop"]) == "pumpkin")
	await well_e()
	var full := fm.bucket
	var w0 := int(fm.stats["watered"])
	var prompts := []
	for i in 12:
		prompts.append(await e_plot(i))
	var all_wet: bool = fm.plots.all(func(q): return bool(q["wet"]))
	r.check(planted and full == 12 and all_wet and fm.bucket == 0 and int(fm.stats["watered"]) == w0 + 12 and prompts[0] == "按 E 浇水（桶里 12 次）"
		and prompts[11] == "按 E 浇水（桶里 1 次）" and "浇好了（桶里还剩 0 次）" in fm.toasts,
		"菜园扩建: one bucket (12) waters all 12 plots with the real E, down to 0", str([full, fm.bucket, prompts]))
	await t3.advance_to(8.0)
	var empties0: int = fm.toasts.filter(func(t): return String(t) == "桶里没水了，去井边打水").size()
	var pr13 := await e_plot(0)
	var empties1: int = fm.toasts.filter(func(t): return String(t) == "桶里没水了，去井边打水").size()
	r.check(pr13 == "按 E 浇水（桶里 0 次）" and empties1 == empties0 + 1 and not bool(fm.plots[0]["wet"]) and int(fm.stats["watered"]) == w0 + 12,
		"菜园扩建: the 13th watering: '桶里没水了，去井边打水', the plot stays dry", str([pr13, empties0, empties1]))


## The map's striped crop rows never show: in all three states every point of the field is under an opaque layer pixel,
## the layers draw above the ground, and each layer's picture pixel sits on the same world pixel (no seam, no shift).
func layer_report() -> Dictionary:
	var fr: Rect2 = fm.field_rect()
	var layers: Array = [fm.weeds_sprite, fm.tilled_sprite]
	var imgs := {}
	for l in layers:
		imgs[l] = (l as Sprite2D).texture.get_image() if (l as Sprite2D).texture != null else null
	var xs := range(int(fr.position.x), int(fr.end.x), 4)
	xs.append(int(fr.end.x) - 1)
	var ys := range(int(fr.position.y), int(fr.end.y), 4)
	ys.append(int(fr.end.y) - 1)
	var holes := []
	var who := {}
	for y in ys:
		for x in xs:
			var pt := Vector2(x + 0.5, y + 0.5)
			var hit := ""
			for l in layers:
				var sp: Sprite2D = l
				if not sp.is_visible_in_tree() or imgs[l] == null:
					continue
				if Rect2(sp.position, sp.region_rect.size).has_point(pt):
					var tp: Vector2 = pt - sp.position + sp.region_rect.position
					if (imgs[l] as Image).get_pixel(int(tp.x), int(tp.y)).a > 0.99:
						hit = String(sp.name)
			if hit == "":
				holes.append(Vector2(x, y))
			else:
				who[hit] = int(who.get(hit, 0)) + 1
	var aligned := true
	var width := 0.0
	for l in layers:
		var sp2: Sprite2D = l
		if sp2.is_visible_in_tree():
			aligned = aligned and sp2.position == fm.field_pos() + Vector2(sp2.region_rect.position.x, 0) and sp2.region_rect.position.y == 0.0 \
				and sp2.region_rect.size.y == fr.size.y
			width += sp2.region_rect.size.x
	var top := true
	var ground: Node2D = g.ground
	for c in ground.get_children():
		if c is Sprite2D and c != fm.weeds_sprite and c != fm.tilled_sprite and (c as Sprite2D).texture == ground.get_child(0).texture:
			top = top and c.get_index() < fm.weeds_sprite.get_index() and c.get_index() < fm.tilled_sprite.get_index()
	return {"holes": holes.size(), "who": who, "aligned": aligned, "width": width, "top": top}


func test_visual() -> void:
	await game()
	await clock(10.0)
	var rep := {}
	rep["closed"] = layer_report()
	await open_farm_direct()
	rep["west"] = layer_report()
	await expand_farm_direct()
	rep["expanded"] = layer_report()
	report["visual"] = rep
	var fw: float = fm.field_rect().size.x
	var ok := true
	for k in rep:
		ok = ok and int(rep[k]["holes"]) == 0 and bool(rep[k]["aligned"]) and is_equal_approx(float(rep[k]["width"]), fw) and bool(rep[k]["top"])
	var c: Dictionary = rep["closed"]["who"]
	var w: Dictionary = rep["west"]["who"]
	var e: Dictionary = rep["expanded"]["who"]
	r.check(fm.field_rect() == Rect2(1664, 992, 224, 160) and ok and c.keys() == ["FarmWeeds"] and w.has("FarmWeeds") and w.has("FarmTilled")
		and e.keys() == ["FarmTilled"],
		"菜园扩建 画面: the original striped rows never show - before 开菜园 all weeds, west opened = tilled west + weeds east, expanded = all tilled; every point of the field under an opaque pixel, above the ground, one picture per layer cut at the same place (no seam)",
		str(rep))


## Saving: 12 plots after 扩建 save and load; an older save (6 plots, no "expanded") loads as not expanded with its 6 plots.
func test_save_expand() -> void:
	await game()
	await expand_farm_direct()
	await clock(10.0)
	fm.plots[0] = {"crop": "greens", "days": 0, "wet": true, "note": false}
	fm.plots[7] = {"crop": "radish", "days": 1, "wet": true, "note": false}
	fm.plots[11] = {"crop": "pumpkin", "days": 3, "wet": false, "note": false}
	fm._refresh_visuals()
	var est0 := s3.value("estate")
	var cap0: Dictionary = SaveGame.roundtrip(fm.capture())
	cap0.erase("mark")
	smp.save_now("test")
	await s4.reload_game()
	bind()
	await r.frames(3)
	var cap1: Dictionary = SaveGame.roundtrip(fm.capture())
	cap1.erase("mark")
	r.check(str(cap0) == str(cap1) and fm.expanded and fm.plots.size() == 12 and fm.crop_sprites[11].visible and fm.wet_sprites[7].visible
		and fm.tilled_sprite.region_rect.size.x == 224.0 and not fm.weeds_sprite.visible and r.is_free(Vector2(1840, 1040))
		and story.flags.get("repair_farm_expand", false) and s3.value("estate") == est0,
		"菜园扩建 存档: after 扩建 all 12 plots save and load (crops, wet), still expanded, the east part walkable, 家业 the same", str([cap0, cap1]))
	# an older save: the farm section of 6 plots, no "expanded" key
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	var f: Dictionary = doc["state"]["farm"]
	f.erase("expanded")
	f["plots"] = (f["plots"] as Array).slice(0, 6)
	f["plots"][2] = {"crop": "radish", "days": 1, "wet": true, "note": false}
	doc["state"]["story"]["flags"].erase("repair_farm_expand")
	var valid_old: String = SaveGame.validate(doc["state"])
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(3)
	var east_empty: bool = range(6, 12).all(func(i): return String(fm.plots[i]["crop"]) == "" and not bool(fm.plots[i]["wet"]))
	r.check(valid_old == "" and fm.opened and not fm.expanded and fm.plots.size() == 12 and String(fm.plots[0]["crop"]) == "greens" and bool(fm.plots[0]["wet"])
		and String(fm.plots[2]["crop"]) == "radish" and int(fm.plots[2]["days"]) == 1 and bool(fm.plots[2]["wet"]) and east_empty
		and fm.weeds_sprite.visible and fm.weeds_sprite.region_rect == Rect2(96, 0, 128, 160) and not r.is_free(Vector2(1840, 1040))
		and not story.flags.get("repair_farm_expand", false) and s3.value("estate") == est0 - 1 and (fm.cook_menu()[1]["choice"] as Array).size() == 5,
		"菜园扩建 存档: an older save (6 plots, no 扩建) loads: not expanded, its 6 plots' crops and watering kept, the east 6 empty under weeds and blocking, 扩建菜园 on offer",
		str([valid_old, fm.opened, fm.expanded, fm.plots]))
	var bad1 := Farm.defaults()
	bad1["expanded"] = "yes"
	var bad2 := Farm.defaults()
	(bad2["plots"] as Array).append({"crop": "", "days": 0, "wet": false, "note": false})
	var old := Farm.defaults()
	old.erase("expanded")
	old["plots"] = (old["plots"] as Array).slice(0, 6)
	r.check(Farm.validate(bad1) != "" and Farm.validate(bad2) != "" and Farm.validate(old) == "" and Farm.validate(Farm.defaults()) == "",
		"菜园扩建 存档: a non-bool 'expanded' or more than 12 plots is refused; the old 6-plot shape is fine", str([Farm.validate(bad1), Farm.validate(bad2), Farm.validate(old)]))


# ================================================================== 菜园扩建 R1 (review.md F1 / F2 / F6)
## The minimap's field pixels in the current state: {bad: pixels off the expected layer average, outside: pixels just
## outside the field changed, n: pixels checked}. Expected = the plain average of the world block (8x8 at the minimap's
## scale) of whichever layer covers it, computed here from the delivered pictures (not from Farm's / Minimap's code).
func minimap_report(state: String) -> Dictionary:
	var mm: Minimap = g.hud.minimap
	var img: Image = (mm.map_tex as ImageTexture).get_image()
	var base: Image = mm._base_img
	var weeds: Image = load("res://assets/farm/farm_weeds.png").get_image()
	var tilled: Image = load("res://assets/farm/farm_tilled.png").get_image()
	weeds.convert(Image.FORMAT_RGBA8)
	tilled.convert(Image.FORMAT_RGBA8)
	var fr: Rect2 = fm.field_rect()
	var cut := 0.0 if state == "closed" else (fr.size.x if state == "expanded" else fm.west_w())
	var k := 1.0 / mm.map_scale
	var tr: Rect2i = mm.thumb_rect(fr)
	var bad := []
	var stripes_left := 0
	for ty in tr.size.y:
		for tx in tr.size.x:
			var w0 := Vector2(float(tr.position.x - Minimap.PAD + tx), float(tr.position.y - Minimap.PAD + ty)) * k - fr.position
			var src: Image = tilled if w0.x < cut else weeds
			var acc := Color(0, 0, 0, 0)
			var n := 0
			for y in range(int(w0.y), int(w0.y + k)):
				for x in range(int(w0.x), int(w0.x + k)):
					acc += src.get_pixel(clampi(x, 0, src.get_width() - 1), clampi(y, 0, src.get_height() - 1))
					n += 1
			acc /= float(n)
			var got := img.get_pixel(tr.position.x + tx, tr.position.y + ty)
			if absf(got.r - acc.r) > 0.02 or absf(got.g - acc.g) > 0.02 or absf(got.b - acc.b) > 0.02:
				bad.append(Vector2i(tx, ty))
			if got.is_equal_approx(base.get_pixel(tr.position.x + tx, tr.position.y + ty)):
				stripes_left += 1
	var outside := 0
	for tx in range(-1, tr.size.x + 1):
		for ty in [-1, tr.size.y]:
			var q := Vector2i(tr.position.x + tx, tr.position.y + ty)
			if not img.get_pixel(q.x, q.y).is_equal_approx(base.get_pixel(q.x, q.y)):
				outside += 1
	return {"bad": bad.size(), "same_as_thumb": stripes_left, "outside": outside, "n": tr.size.x * tr.size.y, "rect": tr}


func test_minimap() -> void:
	await game()
	await clock(10.0)
	var rep := {}
	rep["closed"] = minimap_report("closed")
	# 开菜园 with the real keys (the minimap follows at once)
	story.flags["repair_kitchen"] = true
	set_coins(80)
	await cook([KEY_1, KEY_1])
	await r.frames(5)
	rep["west"] = minimap_report("west")
	await cook([KEY_4, KEY_1])
	await r.frames(5)
	rep["expanded"] = minimap_report("expanded")
	smp.save_now("test")
	await s4.reload_game()
	bind()
	await r.frames(3)
	rep["expanded_loaded"] = minimap_report("expanded")
	report["minimap"] = rep
	var ok := fm.expanded
	for st in rep:
		# (a few block averages may happen to equal the old thumbnail pixel; the striped rows would be most of them)
		ok = ok and int(rep[st]["n"]) == 28 * 20 and int(rep[st]["bad"]) == 0 and int(rep[st]["outside"]) == 0 \
			and int(rep[st]["same_as_thumb"]) < int(rep[st]["n"]) / 20
	r.check(ok, "菜园扩建 R1 F1: the minimap shows the farm's state, never the map's striped rows - weeds / tilled west + weeds east / all tilled (bought with real keys, and after a reload), each of the 28x20 field pixels the average of its 8x8 world block, nothing outside the field touched",
		str(rep))


## R1 F2: the expansion flag and the farm section are reconciled on load; F6: an old 6-slot save that never opened the farm.
func test_save_r1() -> void:
	await game()
	await clock(10.0)
	var est_none := s3.value("estate")
	# F6: an older save, farm section with 6 slots, opened = false, no "expanded"
	smp.save_now("test")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	var f: Dictionary = doc["state"]["farm"]
	f["opened"] = false
	f.erase("expanded")
	f["plots"] = (f["plots"] as Array).slice(0, 6)
	doc["state"]["story"]["flags"].erase("repair_farm")
	doc["state"]["story"]["flags"].erase("repair_farm_expand")
	var v6: String = SaveGame.validate(doc["state"])
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(3)
	var menu6: Array = fm.cook_menu()[1]["choice"].map(func(o): return String(o["text"]))
	r.check(v6 == "" and not fm.opened and not fm.expanded and fm.plots.size() == 12 and fm.plots.all(func(q): return String(q["crop"]) == "")
		and fm.weeds_sprite.visible and fm.weeds_sprite.region_rect == Rect2(0, 0, 224, 160) and not fm.tilled_sprite.visible
		and not r.is_free(Vector2(1712, 1040)) and menu6 == ["开菜园（40 文）", "卖东西", "做药膳", "没事了"] and s3.value("estate") == est_none,
		"菜园扩建 R1 F6: an older save with a 6-slot farm section, never opened: loads unopened - 12 empty plots under weeds, the field solid, 开菜园 on offer, 家业 unchanged",
		str([v6, fm.opened, fm.expanded, menu6]))
	# F2 a: flag repair_farm_expand set, farm opened but without "expanded" -> expanded (no second 40 文, 家业 once)
	await open_farm_direct()
	smp.save_now("test")
	doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	doc["state"]["farm"].erase("expanded")
	doc["state"]["story"]["flags"]["repair_farm_expand"] = true
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(3)
	var menu_a: Array = fm.cook_menu()[1]["choice"].map(func(o): return String(o["text"]))
	r.check(fm.expanded and menu_a == ["买种子", "卖东西", "做药膳", "没事了"] and s3.value("estate") == est_none + 2 and r.is_free(Vector2(1840, 1040))
		and fm.tilled_sprite.region_rect.size.x == 224.0,
		"菜园扩建 R1 F2: flag 扩建 set but the farm section without it -> loads expanded (east open, no 扩建 to pay again, 家业 +1 counted once)",
		str([fm.expanded, menu_a, s3.value("estate"), est_none]))
	# F2 b: flag set but the farm not even opened -> the flag is dropped (no 家业 without land)
	smp.save_now("test")
	doc = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	doc["state"]["farm"] = Farm.defaults()
	doc["state"]["story"]["flags"].erase("repair_farm")
	doc["state"]["story"]["flags"]["repair_farm_expand"] = true
	ss._write_raw(JSON.stringify(doc))
	await s4.reload_game()
	bind()
	await r.frames(3)
	r.check(not fm.opened and not fm.expanded and not story.flags.get("repair_farm_expand", false) and s3.value("estate") == est_none,
		"菜园扩建 R1 F2: flag 扩建 set but the farm not opened -> the flag is dropped, 家业 not counted", str([story.flags.get("repair_farm_expand"), s3.value("estate"), est_none]))
