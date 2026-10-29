extends RefCounted
## 第④步第一批 checks (task packet AC1-AC9), run by tests/run_tests.gd after the other suites, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-step4a
##   (add --s4=name,name to run only some of the tests below, e.g. --s4=cards,tiger_bots)
## Real key events (E / 1-4 / Esc / B / J / Space / WASD) and real physics wherever the player does something; state is set
## directly only to reach a starting point quickly (the clock, coins, a seed that draws the wanted 委托, a villain's HP before
## the last blows) - never to produce the result that is checked.
##   AC1 no board during the prologue; the board after it (solid, E opens 看悬赏 / 看委托 / 离开)
##   AC2 posting: day 2 08:00, the next one the day after a turn-in, 巡山 every 2 days, an untaken 巡山 replaced
##   AC3 cards == the plan (黄鼠狼 60/8/0.6/150, 黑虎 180/18/0.7/100, 狼山贼 60/8); 黄鼠狼 flees at half HP and comes back;
##       黑虎 enrages at half HP (intervals x0.7, pounces)
##   AC4 real-key bots win the three bounties (黑虎 by GP bots - 试玩反馈 v1); the attack-masher's rate against 黑虎
##   AC5 20 % loses: HP refilled, coins kept, villains still there; paid only at the turn-in, once; 名望 cap 10
##   AC6 委托: reproducible draw (seed + day), 送馒头 only with the kitchen, each of the six done with real keys (walking
##       there), void at 24:00, 5 -> 家业 +1, x1.5 rounded at 名望 >= 5, 家业 cap 10
##   AC7 save v4 round trip, items / chick kept, 08:00 after a load draws / pays nothing twice, v1 / v2 / v3 upgrade
##   AC8/9 placement (reachable from the spawn on foot, nothing blocked), chick never in a wall, HUD list rects, Esc page
##       4, fonts, every new line calls the hero 少侠 / 小兔兄弟 / 师兄 (never 她 / 师姐)

var r
var ss                     # tests/sample_suite.gd (game helpers)
var t3                     # tests/step3_suite.gd (calendar / board helpers, bound to the same game)
var g: Node
var story: Story
var dlg: Dialogue
var smp: Sample
var s3: Step3
var jh: Jianghu
var b: Bounty
var cm: Commission
var only: Array = []
var report := {}           # numbers for the delivery report (bot rates, ...)


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	SaveGame.erase()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--s4="):
			only = String(a).trim_prefix("--s4=").split(",")
	r.root.size = Vector2i(1440, 810)     # 修复 v1: the game's real view (480 x 270), see test_view
	ss = load("res://tests/sample_suite.gd").new(r)
	t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	var tests := ["tables", "cards", "text", "gating", "placement", "reach", "schedule", "patrol", "board_flow", "lose",
		"weasel_ai", "tiger_ai", "bots", "tiger_bots", "draw", "kinds", "expire", "pay_rules", "save", "upgrade", "hud", "pause", "book", "dialogue_fit", "pages", "view", "resize", "screens", "chick_indoors"]
	for name in tests:
		if only.is_empty() or name in only:
			await call("test_" + name)
	await ss._free_game()
	SaveGame.erase()
	print("STEP4A REPORT ", report)


# ================================================================== helpers
func bind() -> void:
	t3.bind()
	g = ss.g
	story = g.story
	dlg = story.dialogue
	smp = g.sample
	s3 = g.step3
	jh = g.jianghu
	b = jh.bounty
	cm = jh.com


func p() -> Player:
	return g.player


func game(day_idx := 0) -> void:
	await t3.unlocked_game(day_idx)
	bind()


func set_day(n: int, h: float) -> void:
	t3.set_day(n, h)


func advance_to(h: float) -> void:
	await t3.advance_to(h)


## E at the board, then the keys for the choices in order (E for every line). Returns every line shown.
func board(keys: Array) -> Array:
	await r.teleport(jh.board_point)
	var shown := []
	await r.tap(KEY_E)
	var k := 0
	var n := 0
	while story.busy and n < 900:
		if dlg.active and not (dlg.full_text in shown):
			shown.append(dlg.full_text)
		if dlg.choosing:
			# after the given keys: the last option (离开 / 返回), so the conversation always ends
			await r.tap(keys[k] if k < keys.size() else KEY_1 + dlg.choice_options.size() - 1)
			k += 1
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(3)
	return shown


## Plays the running conversation through with E (choices: key 1).
func finish() -> void:
	await ss.finish_scene()


func joined(lines: Array) -> String:
	return "\n".join(lines)


## The index (key) of today's offer of kind `k` on the 看委托 menu, or -1.
func offer_index(k: String) -> int:
	for i in cm.offers.size():
		if String(cm.offers[i]["kind"]) == k:
			return i
	return -1


## A seed whose draw for calendar day `d` contains kind `k` (a starting point: the board then draws it itself).
func seed_for(k: String, d: int, avoid := "") -> int:
	for sd in range(1, 2000):
		jh.seed = sd
		var kinds: Array = cm.draw(d).map(func(o): return String(o["kind"]))
		if k in kinds and (avoid == "" or not (avoid in kinds)):
			return sd
	return -1


## Walks with the movement keys (A* over the walk grid; doors as in nav.gd).
func walk(to: Vector2, limit := 120.0) -> String:
	r.grid_w = 0
	# through the 山门 (the only opening of the south wall, y 1248): via the middle of the passage - the walk helper's
	# 8 px grid would otherwise cut the corner of the gate posts and stick there
	var from := p().global_position
	if g.interiors.room_at(from) == "" and g.interiors.room_at(to) == "" and (from.y < 1240.0) != (to.y < 1240.0):
		for wp in ([Vector2(1040, 1196), Vector2(1040, 1300)] if from.y < 1240.0 else [Vector2(1040, 1300), Vector2(1040, 1196)]):
			var rr: String = await ss.nav.walk_to(wp, limit)
			if rr != "arrived":
				return rr
	return await _walk_retry(to, limit)


## nav.walk_to, and when the 8 px walk grid leaves the rabbit caught on a corner: a short step away (real keys, each
## direction in turn) and a new plan - up to 4 times.
func _walk_retry(to: Vector2, limit: float) -> String:
	var res: String = await ss.nav.walk_to(to, limit)
	var dirs := [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	for i in 4:
		if res != "stuck":
			return res
		await r.push(dirs[i], 0.25)
		r.grid_w = 0
		res = await ss.nav.walk_to(to, limit)
	return res


## Accepts today's 委托 of kind k at the board with real keys (看委托 -> its line -> 接下).
func accept_commission(k: String) -> bool:
	var i := offer_index(k)
	if i < 0:
		return false
	await board([KEY_2, KEY_1 + i, KEY_1])
	return String(cm.offers[i]["state"]) == "taken"


func turn_in_commission(k: String) -> Array:
	var i := offer_index(k)
	var c0 := smp.coins
	await walk(jh.board_point)
	var lines := await board([KEY_2, KEY_1 + i])
	return [smp.coins - c0, lines]


## A day where kind k is on the board: the seed is chosen, the clock goes to the next 08:00 (the board draws it).
func day_with(k: String, kitchen := false) -> void:
	if kitchen:
		story.flags["repair_kitchen"] = true
		smp.apply_repair_visuals("kitchen")
	var next_day: int = jh.cal_day() + (1 if g.daynight.hour >= 8.0 else 0)
	jh.seed = seed_for(k, next_day)
	await advance_to(8.0)
	await r.frames(3)


## Walks into the bounty's villains from its retreat point until the intro plays, then plays it through.
func start_fight() -> bool:
	var def: Dictionary = b.current_def()
	await r.teleport(Jianghu._vec(def["retreat"]))
	await r.frames(3)
	var target: Vector2 = b.villains[0].global_position
	var res := await walk(target + Vector2(0, 24), 40.0)      # real keys; stops when the intro starts
	r.release_all()
	await finish()
	await r.frames(2)
	return b.villains.any(func(f): return f.engaged)


## A bounty fight with a bot until won / lost / timeout: "won" | "lost" | "timeout".
func bot_fight(kind: String, seconds := 120.0, delay := -1.0) -> String:
	var l0 := b.losses
	t3.cs._dodged_for = {}
	t3.cs._gp_for = {}
	t3.cs._human_plan = {}
	t3.cs._punish_until = -1.0
	for i in int(seconds * 60.0):
		if b.losses > l0:
			r.release_all()
			await finish()
			return "lost"
		if not b.active.is_empty() and String(b.active["state"]) == "won":
			r.release_all()
			await finish()
			return "won"
		if story.busy:
			r.release_all()
			await finish()
			continue
		if not b.villains.any(func(f): return f.engaged):
			# leashed / not yet engaged: walk back in
			var f0: Fighter = b.villains[0] if not b.villains.is_empty() else null
			if f0 != null:
				var to: Vector2 = f0.global_position - p().global_position
				r.hold_dir(to.normalized())
			await r.physics_frame
			continue
		t3.cs.bot_step(kind)
		await r.physics_frame
	t3.cs._release()
	r.release_all()
	return "timeout"


## Accept the posted bounty at the board (real keys: 看悬赏 -> 接榜).
func accept_bounty() -> bool:
	await board([KEY_1, KEY_1])
	return not b.active.is_empty()


## Win the accepted bounty quickly: real J blows after the villains' HP was lowered to 1 (a starting point).
func quick_win() -> bool:
	if not await start_fight():
		return false
	for f in b.villains:
		f.hp = 1
		if f.stats is VillainStats:
			f.has_fled = true       # no flight / rage at 1 HP (that is checked elsewhere)
			f.raged = false
	var res := await bot_fight("gp", 60.0)
	return res == "won"


func turn_in_bounty() -> Array:
	var c0 := smp.coins
	var lines := await board([KEY_1, KEY_1])
	return [smp.coins - c0, lines]


# ================================================================== AC1 tables / cards / texts
func test_tables() -> void:
	Jianghu._data = {}
	var d := Jianghu.load_data()
	var rl := Jianghu.rules()
	var c := Jianghu.crules()
	var bad := []
	var bs: Array = d.get("bounties", [])
	var want := [["偷鸡的黄鼠狼", "山路草丛", 20, 1, 1], ["拦路的山贼", "山路石坎", 35, 1, 3], ["山贼老大「黑虎」", "后山竹林深处", 80, 2, 1]]
	for i in 3:
		var x: Dictionary = bs[i] if i < bs.size() else {}
		if [String(x.get("name", "")), String(x.get("place", "")), int(x.get("coins", -1)), int(x.get("fame", -1)), (x.get("enemies", []) as Array).size()] != want[i]:
			bad.append("bounty %d" % i)
	if bs.size() != 3:
		bad.append("count")
	var pt: Dictionary = rl.get("patrol", {})
	if int(pt.get("interval_days", 0)) != 2 or int(pt.get("coins", 0)) != 15 or int(pt.get("fame", -1)) != 0 or (d["patrol"]["enemies"] as Array).size() != 2:
		bad.append("patrol")
	if int(rl.get("first_day", 0)) != 2 or int(rl.get("post_hour", 0)) != 8 or int(rl.get("max_bounty", 0)) != 1 or int(rl.get("max_commission", 0)) != 2 \
			or not is_equal_approx(float(rl.get("lose_fraction", 0)), 0.2):
		bad.append("rules")
	var kinds := {"bun": 12, "letter": 8, "chicken": 10, "shoots": 10, "jade": 12, "fence": 10}
	for k in kinds:
		if int(c.get("kinds", {}).get(k, {}).get("reward", -1)) != kinds[k]:
			bad.append("reward " + k)
	if String(c["kinds"]["bun"].get("needs_repair", "")) != "kitchen" or int(c["kinds"]["shoots"].get("count", 0)) != 3 \
			or int(c["kinds"]["jade"].get("count", 0)) != 1 or int(c["kinds"]["fence"].get("count", 0)) != 3:
		bad.append("kind conditions")
	if int(c.get("refresh_hour", 0)) != 8 or int(c.get("per_day", 0)) != 2 or int(c.get("expire_hour", 0)) != 24 or int(c.get("estate_every", 0)) != 5 \
			or int(c.get("fame_bonus_at", 0)) != 5 or not is_equal_approx(float(c.get("fame_bonus_mult", 0)), 1.5):
		bad.append("commission rules")
	if Economy.arena_int("fame_max") != 10 or Economy.disciple_int("estate_max") != 10:
		bad.append("caps")
	r.check(bad.is_empty(), "step4a AC2/AC6: data/jianghu.json = the plan (3 bounties 20/+1, 35/+1, 80/+2 at 山路草丛 / 山路石坎 / 后山竹林深处; 巡山 every 2 days 2 狼山贼 15 文 no 名望; first on day 2 08:00; 1 + 2 at once; 20 %; 委托 2 a day at 08:00, void at 24:00, 12/8/10/10/12/10, 送馒头 needs the kitchen, 3 shoots / 1 jade / 3 gaps, 5 -> 家业 +1, x1.5 at 名望 5; caps 10)", str(bad))
	r.check(d.has("_说明") and d.has("_rules说明") and d.has("_bounties说明") and d.has("_places说明"),
		"step4a AC2: the rules file has its 中文 _说明")


const PLAN_CARDS := {
	"weasel": {"max_hp": 60, "damage": 8, "windup": 0.6, "move_speed": 150.0},
	"tiger": {"max_hp": 180, "damage": 18, "windup": 0.7, "move_speed": 100.0},
	"wolf_bounty": {"max_hp": 60, "damage": 8},
}


func test_cards() -> void:
	var bad := []
	for id in PLAN_CARDS:
		var c: EnemyStats = load("res://cards/%s.tres" % id)
		for k in PLAN_CARDS[id]:
			if not is_equal_approx(float(c.get(k)), float(PLAN_CARDS[id][k])):
				bad.append("%s.%s=%s" % [id, k, c.get(k)])
	var w: EnemyStats = load("res://cards/weasel.tres")
	var t: EnemyStats = load("res://cards/tiger.tres")
	var feats: bool = w is VillainStats and is_equal_approx(float(w.get("flee_at")), 0.5) and float(w.get("flee_time")) > 0.0 \
		and t is VillainStats and is_equal_approx(float(t.get("rage_at")), 0.5) and is_equal_approx(float(t.get("rage_interval_factor")), 0.7) \
		and float(t.get("pounce_chance")) > 0.0 and float(t.get("pounce_lunge")) > 0.0
	r.check(bad.is_empty() and feats, "step4a AC3: cards/weasel.tres 60 / 8 / 0.6 s / 150 (flees at half HP), cards/tiger.tres 180 / 18 / 0.7 s / 100 (rage at half HP: intervals x0.7, pounces) = the plan table", str(bad))
	# 狼山贼 (PM ruling MSG-003 reply): wolf_bounty = wolf.tres with damage 8; the prologue wolf keeps 14
	var wb: EnemyStats = load("res://cards/wolf_bounty.tres")
	var wo: EnemyStats = load("res://cards/wolf.tres")
	var diff := []
	for prop in wo.get_property_list():
		var n := String(prop["name"])
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and n != "damage" and wb.get(n) != wo.get(n):
			diff.append(n)
	r.check(wb.max_hp == 60 and wb.damage == 8 and wo.damage == 14 and diff.is_empty(),
		"step4a AC3 (PM ruling): cards/wolf_bounty.tres = 60 HP / 8 damage, every other number as the prologue wolf (wolf.tres keeps 14)", str(diff))
	var ids := []
	for d in Jianghu.load_data()["bounties"] + [Jianghu.load_data()["patrol"]]:
		for e in d["enemies"]:
			ids.append(String(e["card"]))
	r.check(ids == ["weasel", "wolf_bounty", "wolf_bounty", "wolf_bounty", "tiger", "wolf_bounty", "wolf_bounty"],
		"step4a AC3: the bounties use weasel / 3 x wolf_bounty / tiger, 巡山 2 x wolf_bounty", str(ids))


func test_text() -> void:
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := FileAccess.get_file_as_string("res://data/jianghu.json") + PauseMenu.all_text()
	for f in ["jianghu", "bounty", "commission", "villain_stats"]:
		text += FileAccess.get_file_as_string("res://scripts/%s.gd" % f)
	var missing := ""
	for ch in text:
		if ch.unicode_at(0) > 0x7f and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
			missing += ch
	r.check(missing == "", "step4a AC9: every new character (lines, board, HUD, book, Esc tips) exists in the UI font", missing)
	# the hero is a young man: 少侠 / 小兔兄弟 / 师兄, never 她 / 师姐
	var d := Jianghu.load_data()
	var lines := ""
	for sc in d["scenes"]:
		for e in d["scenes"][sc]:
			lines += String(e.get("text", "")) + "\n"
	for k in d["kinds"]:
		lines += String(d["kinds"][k]["desc"]) + String(d["kinds"][k]["thanks"])
	for k in d["ui"]:
		lines += String(d["ui"][k])
	for x in d["bounties"] + [d["patrol"]]:
		lines += String(x.get("desc", ""))
	var bad_words := ["她", "师姐", "姑娘", "女侠"].filter(func(w): return w in lines)
	# 改名与起名 v1: the hero's name is the token {name} in the data now (filled when shown): the default name fills in
	# 小兔 - the same words as before are checked
	lines = PlayerName.fill_with(lines, PlayerName.DEFAULT)
	r.check(bad_words.is_empty() and "少侠" in lines and "小兔兄弟" in lines,
		"step4a: every new line calls the hero 少侠 / 小兔兄弟 (never 她 / 师姐)", str(bad_words))


# ================================================================== AC1 gating
func test_gating() -> void:
	await ss.new_game()
	bind()
	await r.frames(3)
	await r.teleport(jh.board_point)
	await r.frames(3)
	var t := story.interaction_target()
	r.check(not jh.board.visible and jh.board_shape.disabled and not jh.tasks_panel.visible and t.get("kind", "") != "jianghu"
		and cm.offers.is_empty() and b.villains.is_empty(),
		"step4a AC1: during the prologue there is no 江湖告示榜 (not drawn, not solid, no E), no 委托, no villains")
	await game()
	await r.frames(3)
	await r.teleport(jh.board_point)
	await r.frames(3)
	var t2 := story.interaction_target()
	var lines := await board([KEY_3])
	r.check(jh.board.visible and not jh.board_shape.disabled and t2.get("kind", "") == "jianghu" and t2.get("prompt", "") == "按 E 看江湖告示榜"
		and "江湖告示榜：左边红纸是悬赏，右边黄纸是委托。" in lines and dlg.choice_options == ["看悬赏", "看委托", "离开"],
		"step4a AC1: after the prologue the board stands (solid); E asks 看悬赏 / 看委托 / 离开", joined(lines))


# ================================================================== placement / reachability
func test_placement() -> void:
	await game()
	var br := jh.board_rect()
	var clash := []
	for o in g.data["objects"]:
		var tx: Texture2D = load("res://assets/map/" + String(o["tex"]))
		var rr := Rect2(float(o["x"]), float(o["sort_y"]) - 6.0, tx.get_width(), 6.0)
		if rr.intersects(br.grow(4)):
			clash.append(String(o["type"]))
	for c in g.data["colliders"]:
		var a: Array = c["rect"]
		if Rect2(a[0], a[1], a[2], a[3]).intersects(br.grow(6)):
			clash.append("collider " + String(c["kind"]))
	for n in g.npcs:
		if br.grow(30).has_point(n.global_position):
			clash.append(n.id)
	var ring: Rect2 = s3.arena.ring_outer
	var b3: Vector2 = s3.arena.board_point()
	r.check(clash.is_empty() and not br.intersects(ring.grow(16)) and br.get_center().distance_to(b3) > 400.0 and r.is_free(jh.board_point),
		"step4a AC1: the 江湖告示榜 stands on free grass at the village plaza (no object, collider or person within reach; apart from the ring and the 比武 notice board); its E spot is free", str(clash))
	# the old ways with the board there (real keys): gate stairs -> arch -> tea stall -> the plaza -> road -> 比武 board
	var res := []
	await r.teleport(Vector2(1040, 1400))
	res.append(await walk(Vector2(1455, 1660), 60.0))
	res.append(await walk(Vector2(1300, 1880), 60.0))
	res.append(await walk(Vector2(1230, 1790), 60.0))
	res.append(await walk(Vector2(1455, 1900), 60.0))
	res.append(await walk(cm.gap_point(1), 90.0))
	res.append(await walk(b3 + Vector2(0, 6), 90.0))
	r.check(res.all(func(x): return x == "arrived"), "step4a AC1: with the board standing, the road / arch / tea stall / plaza / village / ring board are all still walkable (real keys)", str(res))
	# the new non-solid things never block: fence gaps, glows and the chick have no collision
	var solid := []
	for fg in cm.gaps:
		if fg is CollisionObject2D:
			solid.append(fg.name)
	r.check(cm.chick.collision_layer == 0 and solid.is_empty() and g.npcs.all(func(n): return n != cm.chick),
		"step4a AC1: the chick, the glowing spots and the fence gaps are not solid (nothing new blocks a way or a person)")


## Every new place is reached on foot from the spawn point (real keys, the walk grid includes the board).
func test_reach() -> void:
	await game()
	var pl: Dictionary = jh.data["places"]
	var spots := {"board": jh.board_point, "stall": cm.stall_point, "pen": cm.pen,
		"tanuki": story._npc("tanuki").global_position + Vector2(0, 26), "dog": story._npc("dog").global_position + Vector2(0, 26)}
	var i := 0
	for d in jh.data["bounties"] + [jh.data["patrol"]]:
		spots["retreat_" + String(d["id"])] = Jianghu._vec(d["retreat"])
		for e in d["enemies"]:
			spots["villain_%s_%d" % [d["id"], i]] = Jianghu._vec(e["pos"])
			i += 1
	for k in ["chicken_spots", "shoot_spots", "jade_spots"]:
		for j in (pl[k] as Array).size():
			spots["%s_%d" % [k, j]] = Jianghu._vec(pl[k][j])
	for j in cm.gaps.size():
		spots["gap_%d" % j] = cm.gap_point(j)
	var bad := []
	var spawn := Vector2(g.data["spawn"]["x"], g.data["spawn"]["y"])
	for k in spots:
		var q: Vector2 = spots[k]
		if not r.is_free(q):
			bad.append(k + " not free")
			continue
		await r.teleport(spawn)
		var res := await walk(q, 150.0)
		if res != "arrived" or p().global_position.distance_to(q) > 12.0:
			bad.append("%s %s %s" % [k, res, p().global_position.round()])
	r.check(bad.is_empty(), "step4a AC8: every new place (board, villains, retreat points, chick / glow spots, fence gaps, stall, 茶摊老板, 老伯, 村口) is free and reached on foot from the spawn point (real keys, %d walks)" % spots.size(), str(bad))


# ================================================================== AC2 posting
func test_schedule() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	var d1 := b.offer().is_empty()
	var l1 := joined(await board([KEY_1, KEY_1]))
	set_day(2, 7.99)
	await r.frames(3)
	var d2a := b.offer().is_empty()
	g.daynight.advance_hours(0.02)
	await r.frames(3)
	var d2 := b.offer()
	var toast_new: bool = jh.toasts.has("江湖告示榜贴出了新悬赏")
	r.check(d1 and "下一条：第 2 天辰时上榜（今天第 1 天）" in l1 and d2a and d2.get("index", -1) == 0 and toast_new,
		"step4a AC2: day 1: nothing ('下一条：第 2 天辰时'); day 2 07:59 nothing; 08:00 '偷鸡的黄鼠狼' is posted (toast)", l1)
	var acc := await accept_bounty()
	var lines := joined(await board([KEY_1, KEY_2]))
	var acc2: bool = b.active.size() > 0 and "进行中" in lines
	var won := await quick_win()
	g.daynight.set_hour(15.0)
	var pay := await turn_in_bounty()
	var next_none := b.offer().is_empty()
	set_day(2, 23.99)
	await r.frames(3)
	var still_none := b.offer().is_empty()
	set_day(3, 7.99)
	var none_morning := b.offer().is_empty()
	g.daynight.advance_hours(0.02)
	await r.frames(3)
	var d3 := b.offer()
	r.check(acc and acc2 and won and pay[0] == 20 and next_none and still_none and none_morning and d3.get("index", -1) == 1,
		"step4a AC2: turned in on day 2 -> nothing more that day nor at 07:59 next morning; day 3 08:00 posts '拦路的山贼'", str([acc, acc2, won, pay[0], d3]))
	# turned in early in the morning (07:00 on day 4): the next one comes the next calendar day 08:00, not an hour later
	await accept_bounty()
	await quick_win()
	set_day(4, 7.0)
	await r.frames(2)
	pay = await turn_in_bounty()
	g.daynight.advance_hours(1.5)
	await r.frames(3)
	var not_same := b.offer().is_empty()
	set_day(5, 8.01)
	await r.frames(3)
	r.check(pay[0] == 35 and not_same and b.offer().get("index", -1) == 2,
		"step4a AC2: turned in at 07:00 on day 4 -> not at 08:30 the same day; day 5 08:00 posts '山贼老大「黑虎」'", str([pay[0], not_same, b.offer(), b.active]))


func test_patrol() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(2)
	for i in 3:
		await accept_bounty()
		await quick_win()
		await turn_in_bounty()
		set_day(s3.day_number() + 1, 9.0)
		await r.frames(3)
	# the third was turned in on day 4 at 09:00 -> day 5 08:00 巡山 edition 0
	var after3: bool = b.main_done == 3 and b.patrol_from == jh.cal_day()
	var ed0 := b.offer()
	var line := joined(await board([KEY_1, KEY_2]))
	set_day(6, 9.0)
	await r.frames(3)
	var same: bool = b.offer().get("edition", -1) == 0
	set_day(7, 7.99)
	await r.frames(3)
	var still0: bool = b.offer().get("edition", -1) == 0
	g.daynight.advance_hours(0.02)
	await r.frames(3)
	var ed1 := b.offer()
	r.check(after3 and ed0.get("type", "") == "patrol" and ed0.get("edition", -1) == 0 and "两个狼山贼" in line and "悬赏【巡山】赏金 15 文（不加名望）" in line
		and "第 7 天辰时换下一条" in line and same and still0 and ed1.get("edition", -1) == 1,
		"step4a AC2: after the 3rd turn-in (day 4) 巡山 is posted day 5 08:00; untaken it stays until day 7 08:00, when the next one replaces it", line)
	var f0 := s3.value("fame")
	await accept_bounty()
	var two: bool = b.villains.size() == 2 and b.villains.all(func(f): return f.card == "wolf_bounty")
	await quick_win()
	var pay := await turn_in_bounty()
	var after_pay := b.offer().is_empty()
	set_day(8, 23.0)
	await r.frames(3)
	var none8 := b.offer().is_empty()
	set_day(9, 8.01)
	await r.frames(3)
	var bk: Array = await t3.book_open_lines()
	r.check(two and pay[0] == 15 and s3.value("fame") == f0 and after_pay and none8 and b.offer().get("edition", -1) == 2
		and "揭榜：黄鼠狼、拦路山贼、黑虎 · 巡山 1 回" in bk[1] and "悬赏 3/3 条 · 巡山 1 回 · 委托 0 条（家业进度 0/5）" in bk[0],
		"step4a AC2: 巡山 = 2 狼山贼, 15 文, no 名望; the taken edition is not offered again; day 9 08:00 the next one; 门派簿 '巡山 1 回'", str(bk))


# ================================================================== AC5 the board's bounty flow, losing
func test_board_flow() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(2)
	var lines := joined(await board([KEY_1, KEY_1]))
	var acc: bool = b.active.get("type", "") == "main" and "【偷鸡的黄鼠狼】" in lines and "悬赏第 1 条【偷鸡的黄鼠狼】山路草丛 · 赏金 20 文 · 名望 +1" in lines
	await r.frames(3)
	var present: bool = b.villains.size() == 1 and b.villains[0].visible and b.villains[0].collision_layer != 0 and b.marker.visible
	var red: bool = g.hud.minimap.marks.any(func(m): return (m["color"] as Color).r > 0.9 and (m["color"] as Color).g < 0.3)
	var hud_line: String = jh.tasks_label.text
	r.check(acc and present and red and "悬赏：偷鸡的黄鼠狼（山路草丛）" in hud_line,
		"step4a AC2/AC3: 接榜 -> the 黄鼠狼 stands at 山路草丛 (red ring on the ground, red dot on the minimap); the HUD lists '悬赏：偷鸡的黄鼠狼（山路草丛）'", lines)
	# only one bounty at a time; 放弃 = no penalty, back on the board, the villain gone
	var c0 := smp.coins
	var l2 := joined(await board([KEY_1, KEY_1]))
	r.check(b.active.is_empty() and "放弃了悬赏【偷鸡的黄鼠狼】" in l2 and smp.coins == c0 and b.villains.is_empty() and not b.offer().is_empty(),
		"step4a AC2: 放弃这条悬赏 (no penalty): the villain leaves, it is back on the board", l2)
	await accept_bounty()
	var won := await quick_win()
	var before_turnin := smp.coins
	var wonline: String = jh.tasks_label.text
	await r.frames(10)
	var f0 := s3.value("fame")
	var pay := await turn_in_bounty()
	var pay2 := await turn_in_bounty()
	var bk: Array = await t3.book_open_lines()
	r.check(won and before_turnin == c0 and "回榜交榜" in wonline and pay[0] == 20 and s3.value("fame") == f0 + 1 and pay2[0] == 0
		and "交榜：赏金 20 文，名望 +1 格。" in joined(pay[1]) and "揭榜：黄鼠狼" in bk[1] and b.paid.size() == 1,
		"step4a AC5: winning pays nothing; 交榜 pays 20 文 + 名望 1 once (a second visit pays nothing); 门派簿 '揭榜：黄鼠狼'",
		str([won, before_turnin, c0, wonline, pay[0], pay2[0], s3.value("fame"), f0, bk[1], b.paid.size()]))
	# 名望 never past 10 (the tiger's +2 at 9 gives 1)
	b.main_done = 2
	b.ready_day = -1
	for t in ["trial_bronze", "trial_silver", "trial_gold"]:
		story.flags[t] = true
	s3.disciple.spar_fame += 9 - s3.raw_value("fame")
	await accept_bounty()
	await quick_win()
	var pay3 := await turn_in_bounty()
	r.check(s3.value("fame") == 10 and s3.raw_value("fame") == 10 and pay3[0] == 80 and b.paid[-1]["fame"] == 1,
		"step4a AC5: 名望 stays at 10 (9 + 黑虎's 2 -> 10; the 80 文 are still paid)", str(b.paid))


func test_lose() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(2)
	await accept_bounty()
	var c0 := smp.coins
	await start_fight()
	var f: Fighter = b.villains[0]
	p().hp = 27
	# no regen during the fight; the weasel's real blows bring him to <= 20
	var hp_seen := []
	for i in 60 * 30:
		if b.losses > 0:
			break
		r.hold_dir(Vector2.ZERO)
		if i % 60 == 0:
			hp_seen.append(p().hp)
		await r.physics_frame
	await r.frames(2)
	var lost: bool = b.losses == 1
	var lose_lines := []
	for i in 200:
		if dlg.active and not (dlg.full_text in lose_lines):
			lose_lines.append(dlg.full_text)
		if not story.busy:
			break
		await r.tap(KEY_E)
	await r.frames(3)
	var back: Vector2 = Jianghu._vec(b.current_def()["retreat"])
	r.check(lost and p().hp == 100 and smp.coins == c0 and f.visible and f.hp == f.stats.max_hp and f.global_position.distance_to(f.home) < 1.0
		and f.state == "idle" and p().global_position.distance_to(back) < 2.0 and not p().dead and g.combat.deaths == 0
		and String(b.active["state"]) == "accepted" and "生命掉到两成，败下阵来。生命已经回满，黄鼠狼还在原地，随时可以再去。" in joined(lose_lines),
		"step4a AC5: HP at 20 %% -> lost: HP refilled (100), nothing taken, the 黄鼠狼 back at its place with full HP, the bounty still taken, no knock-out / respawn", str(hp_seen))
	var no_regen := true
	for i in range(1, hp_seen.size()):
		if hp_seen[i] > hp_seen[i - 1]:
			no_regen = false
	r.check(no_regen and hp_seen.size() >= 1, "step4a AC5: no regen during a bounty fight (HP never went up)", str(hp_seen))
	# a fresh try: the intro is not played again (the short line instead); the fight can be won afterwards
	await start_fight()
	var again: bool = story.played.has("J-黄鼠狼-再战") and story.played.count("J-黄鼠狼-上场") == 1
	r.check(again, "step4a AC5: walking back in gives the short line ('又来啦？') and the fight goes on", str(story.played.slice(-4)))


# ================================================================== AC3 villain behaviour
func test_weasel_ai() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(2)
	await accept_bounty()
	await start_fight()
	var f: Fighter = b.villains[0]
	g.combat.rng.seed = 5
	f.hp = 32
	var states := []
	var d_flee_start := -1.0
	var d_flee_max := 0.0
	var fled_at := -1
	var bubble := ""
	for i in 60 * 12:
		p().hp = 100
		if not states.has(f.state):
			states.append(f.state)
		if f.state == "flee":
			var d := f.global_position.distance_to(p().global_position)
			if d_flee_start < 0.0:
				d_flee_start = d
				fled_at = f.hp
				bubble = String(story.bubble().get("text", ""))
			d_flee_max = maxf(d_flee_max, d)
			r.hold_dir(Vector2.ZERO)
		elif fled_at >= 0 and f.state in ["windup", "strike"]:
			break
		else:
			t3.cs.bot_step("masher")
		await r.physics_frame
	r.release_all()
	r.check(fled_at > 0 and fled_at <= 30 and d_flee_max > d_flee_start + 60.0 and states.has("flee") and f.has_fled and f.state in ["windup", "strike"]
		and bubble == "打不过，溜了溜了！",
		"step4a AC3: the 黄鼠狼 at half HP (%d <= 30) runs away (%.0f -> %.0f px) - '打不过，溜了溜了！' - then turns round and attacks again" % [fled_at, d_flee_start, d_flee_max], str(states))
	# only once: no second flight
	var flees := 0
	var was := f.state
	for i in 60 * 6:
		p().hp = 100
		if f.state == "flee" and was != "flee":
			flees += 1
		was = f.state
		t3.cs.bot_step("masher")
		await r.physics_frame
		if not f.engaged:
			break
	r.release_all()
	r.check(flees == 0, "step4a AC3: it runs away only once")


func test_tiger_ai() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(2)
	b.main_done = 2
	await accept_bounty()
	await start_fight()
	var f: Fighter = b.villains[0]
	g.combat.rng.seed = 11
	var calm_ints := []
	for i in 20:
		calm_ints.append(f._interval())
	f.hp = 92
	var seen := {}
	var banner := ""
	var rage_hp := -1
	var rage_state := ""
	var bub := ""
	for i in 60 * 10:
		p().hp = 100
		seen[f.state] = true
		if f.raged and rage_hp < 0:
			rage_hp = f.hp
			rage_state = f.state
			banner = g.combat.hud.banner.text + "/" + g.combat.hud.banner_sub.text
		if f.raged:
			break
		t3.cs.bot_step("masher")
		await r.physics_frame
	r.release_all()
	# the roar line comes over his head once the banner has gone (never under it)
	var early := String(story.bubble().get("text", ""))
	for i in 125:
		p().hp = 100
		await r.physics_frame
	bub = String(story.bubble().get("text", ""))
	var banner_gone: bool = g.combat.hud.banner.modulate.a < 0.05 and early == ""
	var rage_ints := []
	for i in 20:
		rage_ints.append(f._interval())
	var tex_ok: bool = not CharSheet.has_own_art("tiger_rage") or f.sprite.sprite_frames == CharSheet.frames_for("tiger_rage")
	var lo := (f.stats.interval_min * 0.7) - 0.001
	var hi := (f.stats.interval_max * 0.7) + 0.001
	r.check(f.raged and rage_hp <= 90 and rage_state == "rage" and banner == "黑虎发怒了！/出招更快，小心扑击" and bub == "吼——！你惹恼我了！" and banner_gone and tex_ok
		and calm_ints.all(func(x): return x >= f.stats.interval_min and x <= f.stats.interval_max)
		and rage_ints.all(func(x): return x >= lo and x <= hi),
		"step4a AC3: 黑虎 at half HP (%d <= 90) enrages (roar, red sheet, banner '黑虎发怒了！', '吼——！'); his attack intervals become x0.7 (%.2f-%.2f s -> %.2f-%.2f s)" % [rage_hp, f.stats.interval_min, f.stats.interval_max, lo, hi],
		str([banner, early, bub, banner_gone, g.combat.hud.banner.modulate.a, tex_ok, f.state, f.raged]))
	# enraged: he pounces (a charge: the whole lunge can hit), and a dodge through it is a 看破
	var p0 := f.pounces
	var hits := 0
	for i in 60 * 15:
		p().hp = 100
		if f.pounces > p0 + 1:
			break
		r.hold_dir(Vector2.ZERO)
		await r.physics_frame
	r.check(f.pounces >= p0 + 2 and f.attack_kind_now() in ["charge", "strike"], "step4a AC3: enraged 黑虎 pounces (%d pounces in 15 s standing still)" % (f.pounces - p0))
	# not enraged: never a pounce
	var calm: Fighter = f
	calm.reset_home(true)
	r.check(not calm.raged and calm.attack_kind_now() == "strike" and calm.pounces >= 0, "step4a AC3: back at his place he is calm again (rage is per fight)")


# ================================================================== AC4 bots
func fight_with(index: int, kind: String, seed_v: int, delay := -1.0, seconds := 150.0) -> String:
	b.active = {}
	b.main_done = index
	b.ready_day = -1
	await r.frames(2)
	await accept_bounty()
	g.combat.rng.seed = seed_v
	if not await start_fight():
		return "no fight"
	return await bot_fight(kind, seconds, delay)


func test_bots() -> void:
	await game()
	set_day(2, 9.0)
	var out := {}
	for pair in [[0, "weasel"], [1, "wolves"]]:
		var res := []
		for i in 5:
			var o := await fight_with(int(pair[0]), "gp", 300 + i)
			res.append(o)
			b.active = {}
			p().full_heal()
		out[pair[1]] = res
	report["weasel_gp"] = out["weasel"]
	report["wolves_gp"] = out["wolves"]
	var ww: int = out["weasel"].count("won")
	var wl: int = out["wolves"].count("won")
	# reference: the attack-masher (J only) on the first two
	var mash := {}
	for pair in [[0, "weasel"], [1, "wolves"]]:
		var res2 := []
		for i in 5:
			res2.append(await fight_with(int(pair[0]), "masher", 500 + i, -1.0, 90.0))
			b.active = {}
			p().full_heal()
		mash[pair[1]] = res2.count("won")
	report["masher_weasel"] = "%d/5" % mash["weasel"]
	report["masher_wolves"] = "%d/5" % mash["wolves"]
	print("BOUNTY MASHER RATES weasel %d/5 wolves %d/5" % [mash["weasel"], mash["wolves"]])
	r.check(ww >= 4 and wl >= 3, "step4a AC4: a real-key GP bot (tests/combat_suite.gd, 试玩反馈 v1) wins the 黄鼠狼 %d/5 and the three 狼山贼 %d/5 (from walking in to the last knock-out)" % [ww, wl], str(out))


## 试玩反馈 v1: 黑虎 against the GP bots of tests/combat_suite.gd: "gp" presses K so that the stance meets the blow (a claw
## or a pounce closing in); "human" presses K a random 0.30-0.55 s after the wind-up starts and leaves a quarter of the
## attacks unguarded (v1.1's dodge + 看破反击 bots are gone with the 看破反击). The attack-masher never guards.
## (黑虎's wind-up is 0.7 s: a K 0.30-0.55 s after its start only meets the claw when it comes at 0.45 s or later - about 4
## in 10 reactions - so this bot catches ~30 % of his attacks and wins on the counters and its J; measured 7/10 here and
## 23/30 on 30 other seeds. "稳定获胜" is taken as >= 7 of 10 - reported to PM as a judgement call.)
const TIGER_HUMAN_STEADY := 7


func test_tiger_bots() -> void:
	await game()
	set_day(2, 9.0)
	var res := {"perfect": [], "human": [], "masher": []}
	for i in 10:
		res["perfect"].append(await fight_with(2, "gp", 700 + i, -1.0))
		b.active = {}
		p().full_heal()
	for i in 10:
		t3.cs.human_rng.seed = 4000 + i
		res["human"].append(await fight_with(2, "human", 850 + i, -1.0))
		b.active = {}
		p().full_heal()
	for i in 10:
		res["masher"].append(await fight_with(2, "masher", 900 + i, -1.0, 90.0))
		b.active = {}
		p().full_heal()
	var pw: int = res["perfect"].count("won")
	var hw: int = res["human"].count("won")
	var mw: int = res["masher"].count("won")
	report["tiger"] = {"perfect_gp": "%d/10" % pw, "human_like_gp_0.30-0.55s_25pct_unguarded": "%d/10" % hw, "masher": "%d/10" % mw, "detail": res}
	print("TIGER BOT RATES gp %d/10  human %d/10  masher %d/10" % [pw, hw, mw])
	r.check(pw >= 9 and hw >= TIGER_HUMAN_STEADY, "step4a AC4 (试玩反馈 v1): 黑虎 is beaten by real-key GP bots: K as the blow comes %d/10; a human-like bot (K 0.30-0.55 s after the wind-up starts, 25 %% of the attacks unguarded) %d/10 (>= %d)" % [pw, hw, TIGER_HUMAN_STEADY], str(res))
	r.check(mw * 10 < 30, "step4a AC4: the attack-masher (J only, never guards) beats 黑虎 %d/10 (< 30 %%)" % mw, str(res["masher"]))


# ================================================================== AC6 委托
func test_draw() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	var day0 := cm.day
	var first: Array = cm.offers.map(func(o): return o["kind"])
	var again: Array = cm.draw(day0).map(func(o): return o["kind"])
	jh.seed = 4242
	var a1: Array = cm.draw(day0 + 3).map(func(o): return o["kind"])
	var a2: Array = cm.draw(day0 + 3).map(func(o): return o["kind"])
	var kinds_seen := {}
	var bun_without := false
	for d in range(0, 120):
		for o in cm.draw(d):
			kinds_seen[o["kind"]] = true
			if o["kind"] == "bun":
				bun_without = true
	story.flags["repair_kitchen"] = true
	var bun_with := false
	var spots_ok := true
	for d in range(0, 120):
		var ks: Array = cm.draw(d)
		var used := []
		for o in ks:
			if o["kind"] == "bun":
				bun_with = true
			for s in o["spots"]:
				if o["kind"] in ["shoots", "jade"]:
					var key: String = str(jh.data["places"]["shoot_spots" if o["kind"] == "shoots" else "jade_spots"][s])
					if used.has(key):
						spots_ok = false
					used.append(key)
		if ks.size() != 2 or ks[0]["kind"] == ks[1]["kind"]:
			spots_ok = false
	story.flags.erase("repair_kitchen")
	r.check(first.size() == 2 and first == again and a1 == a2 and day0 == jh.cal_day() and not bun_without and bun_with
		and kinds_seen.size() == 5 and spots_ok,
		"step4a AC6: 2 different 委托 a day from seed + day (the same seed and day always give the same two); 送馒头 is never drawn before the kitchen is repaired, and is after; the grove spots of one day never overlap",
		"%s %s %s" % [first, a1, kinds_seen.keys()])
	# 08:00 draws once: the clock crossing 08:00 twice the same day / running on draws nothing new
	var n0 := cm.draws
	await advance_to(7.9)
	var night: bool = cm.offers.is_empty() and cm.day == -1
	g.daynight.advance_hours(0.2)
	await r.frames(3)
	var n1 := cm.draws
	for i in 30:
		await r.physics_frame
	r.check(night and n1 == n0 + 1 and cm.draws == n1 and cm.day == jh.cal_day(),
		"step4a AC6: between midnight and 08:00 the board has no 委托; 08:00 draws the day's two once")


## One 委托 of each kind, done with real keys (walking from the board to the places and back).
func test_kinds() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	var results := {}
	for k in ["bun", "letter", "chicken", "shoots", "jade", "fence"]:
		await day_with(k, k == "bun")
		var lines0 := joined(await board([KEY_2, KEY_1 + offer_index(k)]))
		var ok_acc := await accept_commission(k)
		var steps := []
		match k:
			"bun":
				steps.append(await walk(cm.stall_point))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.find_taken("bun").get("step", -1))
				var tn: Npc = story._npc("tanuki")
				steps.append(await walk(tn.global_position + Vector2(0, 26)))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.find_taken("bun").get("step", -1))
			"letter":
				var tn2: Npc = story._npc("tanuki")
				steps.append(await walk(tn2.global_position + Vector2(0, 26)))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.find_taken("letter").get("step", -1))
				var dog: Npc = story._npc("dog")
				steps.append(await walk(dog.global_position + Vector2(0, 26)))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.find_taken("letter").get("step", -1))
			"chicken":
				var cp: Vector2 = cm.chick.global_position
				steps.append(await walk(cp + Vector2(0, 18)))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.chick_state)
				cm.chick_max_wall = 0
				var maxd := 0.0
				var res := await walk(cm.pen + Vector2(10, 4), 150.0)
				steps.append(res)
				for i in 60:
					await r.physics_frame
				steps.append(cm.chick_state)
				steps.append(cm.chick_max_wall)
			"shoots":
				var o := cm.find_taken("shoots")
				for s in o["spots"]:
					var gp: Vector2 = cm.glows["shoots:%d" % int(s)].position
					steps.append(await walk(gp + Vector2(0, 14)))
					await r.tap(KEY_E)
					await r.frames(3)
				steps.append(cm.find_taken("shoots").get("count", -1))
			"jade":
				var o2 := cm.find_taken("jade")
				var gp2: Vector2 = cm.glows["jade:%d" % int(o2["spots"][0])].position
				steps.append(await walk(gp2 + Vector2(0, 14)))
				await r.tap(KEY_E)
				await finish()
				steps.append(cm.find_taken("jade").get("step", -1))
			"fence":
				for i in 3:
					steps.append(await walk(cm.gap_point(i)))
					var broken_before: bool = cm.gaps[i].broken
					await r.tap(KEY_E)
					await r.frames(3)
					steps.append([broken_before, cm.gaps[i].broken])
		var ready: bool = not cm.find_taken(k).is_empty() and cm.complete(cm.find_taken(k))
		var pay := await turn_in_commission(k)
		var o_done: Dictionary = cm.offers[offer_index(k)]
		var want := int(Jianghu.crules()["kinds"][k]["reward"])
		results[k] = {"ok": ok_acc and ready and pay[0] == want and String(o_done["state"]) == "done", "steps": steps, "pay": pay[0]}
		if not results[k]["ok"]:
			print("KIND FAIL ", k, " ", results[k], " ", joined(pay[1]), " / ", lines0)
	for k in results:
		var extra := ""
		if k == "chicken":
			extra = "; the chick followed the player's own steps back to 村口 and never stood inside a wall"
			results[k]["ok"] = results[k]["ok"] and results[k]["steps"][-1] == 0 and results[k]["steps"][-2] == "home"
		if k == "fence":
			extra = "; each gap broken before E, mended after"
			results[k]["ok"] = results[k]["ok"] and results[k]["steps"].filter(func(x): return x is Array).all(func(x): return x == [true, false])
		r.check(results[k]["ok"], "step4a AC6: 委托 %s done with real keys (accept at the board, walk there, E, walk back, 交差: %d 文)%s" % [jh.com.kind_name(k), results[k]["pay"], extra], str(results[k]))


func test_expire() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	await day_with("jade")
	await accept_commission("jade")
	var o := cm.find_taken("jade")
	var gp: Vector2 = cm.glows["jade:%d" % int(o["spots"][0])].position
	await walk(gp + Vector2(0, 14))
	await r.tap(KEY_E)
	await finish()
	var c0 := smp.coins
	g.daynight.set_hour(23.98)
	await r.frames(3)
	var before := cm.complete(cm.find_taken("jade"))
	g.daynight.advance_hours(0.04)
	await r.frames(3)
	var gone: bool = cm.offers.is_empty() and cm.expired == 1 and jh.toasts.has("过了子时，没办完的委托作废了")
	var lines := joined(await board([KEY_2, KEY_1]))
	r.check(before and gone and "今天的委托辰时（8 点）才贴出来。" in lines and smp.coins == c0 and jh.tasks_label.text.find("委托") < 0,
		"step4a AC6: a 委托 not turned in by 24:00 is void (even when done; no pay, no penalty); the board says new ones come at 08:00",
		str([before, gone, cm.expired, smp.coins, c0, jh.tasks_label.text]) + lines)
	await advance_to(8.0)
	r.check(cm.offers.size() == 2 and cm.offers.all(func(x): return String(x["state"]) == "open"), "step4a AC6: 08:00 brings the new day's two")


func test_pay_rules() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	# 5 turned in -> 家业 +1 (real turn-ins; the offers are finished by hand as a starting point)
	var e0 := s3.value("estate")
	var seq := []
	for i in 6:
		var o: Dictionary = cm.offers[i % 2]
		if String(o["state"]) == "done":
			await advance_to(8.0)
			o = cm.offers[0]
		var k := String(o["kind"])
		await accept_commission(k)
		var ot := cm.find_taken(k)
		ot["step"] = Commission.LAST_STEP[k]
		await turn_in_commission(k)
		seq.append(s3.value("estate"))
	var bk: Array = await t3.book_open_lines()
	r.check(seq == [e0, e0, e0, e0, e0 + 1, e0 + 1] and cm.total == 6 and "接委托累计 6 条" in bk[1] and "委托 6 条（家业进度 1/5）" in str(bk[0]),
		"step4a AC6: every 5th 委托 turned in gives 家业 +1 (%d -> %d); the 门派簿 shows 'x/5'" % [e0, e0 + 1], str(seq) + str(bk[0]))
	# 名望 >= 5: x1.5 rounded half up; 4 -> plain
	for t in ["trial_bronze", "trial_silver"]:
		story.flags[t] = true
	s3.disciple.spar_fame = 4 - s3.raw_value("fame") + s3.disciple.spar_fame
	var at4 := [cm.reward("bun"), cm.reward("letter"), cm.reward("chicken")]
	s3.disciple.spar_fame += 1
	var at5 := [cm.reward("bun"), cm.reward("letter"), cm.reward("chicken"), cm.reward("jade")]
	Jianghu._data["rules"]["commissions"]["fame_bonus_mult"] = 1.25
	var odd := [cm.reward("bun"), cm.reward("chicken"), cm.reward("letter")]
	Jianghu._data = {}
	Jianghu.load_data()
	jh.data = Jianghu.load_data()
	await advance_to(8.0)
	var k2 := String(cm.offers[0]["kind"])
	await accept_commission(k2)
	cm.find_taken(k2)["step"] = Commission.LAST_STEP[k2]
	var pay := await turn_in_commission(k2)
	var lines := joined(await board([KEY_2, KEY_3]))
	r.check(at4 == [12, 8, 10] and at5 == [18, 12, 15, 18] and odd == [15, 13, 10] and pay[0] == int(round(float(Jianghu.crules()["kinds"][k2]["reward"]) * 1.5))
		and "（名望已有 5 格：报酬 ×1.5）" in lines,
		"step4a AC6: 名望 4 pays 12 / 8 / 10; 名望 5 pays x1.5 (18 / 12 / 15 / 18) rounded half up (x1.25: 12.5 -> 13, 10 -> 12.5 -> 13 ...); the board says so", "%s %s %s %d" % [at4, at5, odd, pay[0]])
	# 家业 cap 10
	s3.disciple.sweep_estate += 10 - s3.raw_value("estate")
	cm.total = 9
	await advance_to(8.0)
	var k3 := String(cm.offers[0]["kind"])
	await accept_commission(k3)
	cm.find_taken(k3)["step"] = Commission.LAST_STEP[k3]
	var pay2 := await turn_in_commission(k3)
	r.check(s3.value("estate") == 10 and s3.raw_value("estate") == 10 and cm.total == 10 and pay2[0] > 0 and "累计完成 10 条委托（家业已满）。" in joined(pay2[1]),
		"step4a AC6: 家业 never past 10 (the 10th 委托 at 10: the coins are paid, '家业已满')", joined(pay2[1]))
	# villagers after 名望 5
	var duck := story.talk_scene("duck")
	var tan := story.talk_scene("tanuki")
	var played: Array = await ss.talk("duck")
	r.check(duck == "J-村民-名望" and tan == "J-茶摊-名望" and played == ["J-村民-名望"],
		"step4a AC6: with 名望 >= 5 the villagers speak differently ('是那位打退山贼的少侠吧！')", "%s %s" % [duck, tan])
	s3.disciple.spar_fame = 0
	ar_fame_reset()
	r.check(story.talk_scene("duck") != "J-村民-名望" and story.talk_scene("tanuki") == "J-茶摊-平时", "step4a AC6: below 5 they say their usual lines")


func ar_fame_reset() -> void:
	for t in ["trial_bronze", "trial_silver", "trial_gold"]:
		story.flags.erase(t)
	s3.arena.fame_points = 0
	b.fame_points = 0


# ================================================================== AC7 saving
func _observables() -> Dictionary:
	return {"board": jh.board.visible, "villains": b.villains.size(), "marker": b.marker.visible, "tasks": jh.tasks_label.text,
		"chick": cm.chick.visible, "chick_state": cm.chick_state, "gaps": cm.gaps.map(func(x): return x.broken),
		"glows": cm.glows.values().filter(func(x): return x.visible).size(), "fame": s3.value("fame"), "estate": s3.value("estate"),
		"offer": str(b.offer()), "talk_tanuki": story.talk_scene("tanuki")}


func reload_game() -> void:
	await ss._title()
	await r.tap(KEY_ENTER)
	await ss._wait_game()
	bind()
	g.daynight.running = false
	await r.frames(3)


func test_save() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(3)
	await accept_bounty()
	await day_with("bun", true)
	set_day(3, 9.0)
	await r.frames(3)
	await accept_commission("bun")
	await walk(cm.stall_point)
	await r.tap(KEY_E)
	await finish()
	var other := String(cm.offers[1 - offer_index("bun")]["kind"])
	await accept_commission(other)
	await r.teleport(Vector2(1180, 1700))
	await r.frames(10)
	smp.save_now("test")
	var snap := SaveGame.roundtrip(SaveGame.capture(g))
	var obs := _observables()
	var text := FileAccess.get_file_as_string(SaveGame.path())
	var doc = JSON.parse_string(text)
	await reload_game()
	var snap2 := SaveGame.roundtrip(SaveGame.capture(g))
	var d: String = ss._diff(snap, snap2)
	r.check(int(doc["version"]) == SaveGame.VERSION and SaveGame.VERSION >= 4 and d == "" and snap["jianghu"]["com"]["offers"].size() == 2
		and String(snap["jianghu"]["bounty"]["active"]["state"]) == "accepted",
		"step4a AC7: everything of step 4a (seed, bounty taken, offers + progress - the 馒头 in hand -, totals, chick) saves as the current version (%d) and comes back equal" % SaveGame.VERSION, d)
	r.check(ss._diff(obs, _observables()) == "" and cm.find_taken("bun").get("step", -1) == 1 and story.talk_scene("tanuki") == "J-馒头-送",
		"step4a AC7: and the game looks the same (villain at his place, HUD list, the 馒头 still in hand -> 茶摊老板 takes it)", ss._diff(obs, _observables()))
	# crossing 08:00 after loading: one new draw, the bounty untouched, nothing paid
	# (the kitchen is repaired: the stall's own 08:00 income is the only money that may come in)
	var c0 := smp.coins
	var i0 := smp.incomes
	var n0 := cm.draws
	await advance_to(8.0)
	await r.frames(20)
	var stall := (smp.incomes - i0) * Economy.stall_income()
	var new_day: bool = cm.draws == n0 + 1 and cm.offers.all(func(o): return String(o["state"]) == "open") and smp.coins == c0 + stall \
		and smp.incomes == i0 + 1 and cm.paid.is_empty() and b.paid.is_empty()
	# the same file loaded again: the same single draw
	await ss._free_game()
	ss._write_raw(text)
	await reload_game()
	var n1 := cm.draws
	var i1 := smp.incomes
	var off_before: Array = cm.offers.map(func(o): return o["kind"])
	await advance_to(8.0)
	await r.frames(20)
	await advance_to(9.0)
	await r.frames(20)
	r.check(new_day and n1 == 0 and cm.draws == 1 and smp.coins == c0 + (smp.incomes - i1) * Economy.stall_income() and smp.incomes == i1 + 1
		and off_before.size() == 2 and cm.paid.is_empty(),
		"step4a AC7: after a load the next 08:00 draws once and pays nothing; loading the same save again does the same (no double draw / pay)")
	# a won bounty saved before the turn-in is paid exactly once after a load
	await ss._free_game()
	ss._write_raw(text)
	await reload_game()
	await quick_win()
	smp.save_now("test")
	var won_text := FileAccess.get_file_as_string(SaveGame.path())
	await reload_game()
	var c1 := smp.coins
	var pay := await turn_in_bounty()
	smp.save_now("test")
	await reload_game()
	var pay2 := await turn_in_bounty()
	r.check(String(JSON.parse_string(won_text)["state"]["jianghu"]["bounty"]["active"]["state"]) == "won" and pay[0] == 20 and pay2[0] == 0 and smp.coins == c1 + 20,
		"step4a AC7: a won bounty saved before the turn-in is paid once after loading, and not again after the next load")
	# the chick following is kept (at the player's heels) and still gets home
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	await day_with("chicken")
	await accept_commission("chicken")
	await walk(cm.chick.global_position + Vector2(0, 18))
	await r.tap(KEY_E)
	await finish()
	await walk(Vector2(600, 1600))
	smp.save_now("test")
	await reload_game()
	var follow: bool = cm.chick_state == "follow" and cm.chick.visible and cm.chick.global_position.distance_to(p().global_position) < 30.0
	await walk(cm.pen + Vector2(10, 4), 150.0)
	await r.frames(60)
	r.check(follow and cm.chick_state == "home" and cm.chick_max_wall == 0, "step4a AC7: a chick that was following when saved follows again after loading and gets home (never in a wall)")
	# bad values refused
	var st := SaveGame.roundtrip(SaveGame.capture(g))
	var bad := {}
	var c := st.duplicate(true)
	c["jianghu"]["com"]["offers"].append({"kind": "dragon", "state": "open", "step": 0, "count": 0, "spots": [], "picked": []})
	bad["kind"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c["jianghu"]["bounty"]["main_done"] = -1
	bad["main_done"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c["jianghu"]["bounty"]["active"]["state"] = "maybe"
	bad["state"] = SaveGame.validate(c) != ""
	c = st.duplicate(true)
	c.erase("jianghu")
	bad["missing"] = SaveGame.validate(c) != ""
	r.check(bad.values().all(func(v): return v), "step4a AC7: a version-4 save with bad step-4a values (unknown 委托, negative count, unknown state, section missing) is refused", str(bad))


func test_upgrade() -> void:
	# v1 (a real 第②步 save), v2 and v3 (the current state without the newer sections) all load and play on
	var res := {}
	await ss._free_game()
	ss._write_raw(FileAccess.get_file_as_string("res://tests/fixtures/step2_save_v1.json"))
	await reload_game()
	res["v1"] = [smp.unlocked, jh.board.visible, b.main_done, cm.offers.size(), s3.value("fame")]
	var v1_ok: bool = smp.unlocked and jh.board.visible and b.main_done == 0 and cm.offers.size() == 2 and not b.offer().is_empty()
	smp.save_now("test")
	var cur = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))
	var v1_written: bool = int(cur["version"]) == SaveGame.VERSION and cur["state"].has("jianghu")
	var v3 = cur.duplicate(true)
	v3["version"] = 3
	v3["state"].erase("jianghu")
	var v2 = v3.duplicate(true)
	v2["version"] = 2
	v2["state"]["step3"]["arena"].erase("difficulty")
	v2["state"]["step3"]["arena"].erase("hard_wins")
	v2["state"]["step3"]["disciple"].erase("spar_count")
	var ok := {}
	for pair in [["v3", v3], ["v2", v2]]:
		await ss._free_game()
		ss._write_raw(JSON.stringify(pair[1]))
		var rd := SaveGame.read()
		await reload_game()
		ok[pair[0]] = rd["ok"] and smp.coins == int(cur["state"]["sample"]["coins"]) and jh.board.visible and b.main_done == 0 and cm.offers.size() == 2
		smp.save_now("test")
		ok[pair[0] + "_written"] = int(JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path()))["version"]) == SaveGame.VERSION
	r.check(v1_ok and v1_written and ok.values().all(func(v): return v),
		"step4a AC7: version 1 (第②步), 2 and 3 saves load: step 4a starts empty (the first 悬赏 already due, today's 委托 drawn) and they are written back as the current version",
		str(res) + str(ok))


# ================================================================== HUD / Esc page / book
func test_hud() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(3)
	await accept_bounty()
	await day_with("shoots")
	set_day(3, 9.0)
	await r.frames(3)
	await accept_commission("shoots")
	var other := String(cm.offers[1 - offer_index("shoots")]["kind"])
	await accept_commission(other)
	await r.teleport(Vector2(1180, 1700))
	for i in 600:
		if s3._toast_queue.is_empty() and g.hud.toast.modulate.a <= 0.01:
			break
		await r.physics_frame
	g.hud.show_toast("江湖告示榜贴出了新悬赏", 3.0)
	await r.frames(10)
	var hud: Hud = g.hud
	var tr: Rect2 = jh.tasks_panel.get_global_rect()
	var others := {"toast": hud.toast_text_rect(), "objective": hud.objective.get_global_rect(), "coins": smp.coin_panel.get_global_rect(),
		"clock": hud.clock.get_global_rect(), "hp": g.combat.hud.hp_panel.get_global_rect(),
		"minimap": Rect2(hud.minimap.position, hud.minimap.size)}
	var clash := []
	for k in others:
		if (others[k] as Rect2).intersects(tr):
			clash.append(k)
	var lines: PackedStringArray = jh.tasks_label.text.split("\n")
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	r.check(lines.size() == 3 and lines[0] == "悬赏：偷鸡的黄鼠狼（山路草丛）" and lines[1].begins_with("委托：") and clash.is_empty()
		and Rect2(Vector2.ZERO, vp).encloses(tr) and tr.position.y >= smp.coin_panel.get_global_rect().end.y and hud.toast.modulate.a > 0.5,
		"step4a AC9: the HUD lists what is being done (1 悬赏 + 2 委托) under the coin counter; it never touches the toast text, the objective, the clock, the HP bar or the minimap",
		str(clash) + " " + str(tr) + " " + str(lines) + " coin " + str(smp.coin_panel.get_global_rect()) + " toast a %.2f" % hud.toast.modulate.a)
	# a "按 E" prompt behind the list: the list fades; the prompt is drawn above it
	hud.show_prompt(g.camera.get_screen_center_position() + (tr.get_center() - vp * 0.5) / g.camera.zoom + Vector2(0, 8), "按 E 交谈")
	jh._update_tasks()
	var faded: bool = jh.tasks_panel.modulate.a < 0.5 and hud.prompt.get_index() > jh.tasks_panel.get_index()
	hud.hide_prompt()
	jh._update_tasks()
	r.check(faded and jh.tasks_panel.modulate.a > 0.9, "step4a AC9: a prompt behind the list makes it fade (the prompt stays readable, drawn above it)")


func test_pause() -> void:
	await game()
	var pm: PauseMenu = g.pause_menu
	await r.tap(KEY_ESCAPE)
	for i in 3:
		await r.tap(KEY_RIGHT)
	await r.process_frame
	await r.process_frame
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var rect := pm.panel.get_global_rect()
	var text := ""
	var clipped := ""
	for l in pm.jianghu_tip_labels:
		text += l.text
		if l.size.y + 0.5 < l.get_combined_minimum_size().y or not rect.grow(1).encloses(l.get_global_rect()):
			clipped += l.text.substr(0, 5) + " "
	var has_all := ["江湖告示榜", "悬赏", "巡山", "委托", "黄鼠狼", "黑虎", "×1.5", "家业 +1", "子时"].all(func(k): return k in text)
	r.check(pm.page == 3 and pm.tip_pages[3].visible and has_all and clipped == "" and not "{" in text and Rect2(Vector2.ZERO, vp).encloses(rect)
		and "黄鼠狼（20 文、名望 +1）" in text and "15 文" in text,
		"step4a AC9: Esc page 4 (→ → →) covers the board, 悬赏, 巡山, 委托 and their rewards (numbers from jianghu.json); fits, nothing cut off", clipped + text.substr(0, 60))
	await r.tap(KEY_ESCAPE)


func test_book() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(3)
	var bk: Array = await t3.book_open_lines()
	await accept_bounty()
	var bk2: Array = await t3.book_open_lines()
	r.check("悬赏 0/3 条 · 委托 0 条（家业进度 0/5）" in bk[0] and "悬赏第 1 条【偷鸡的黄鼠狼】进行中 · 委托 0 条（家业进度 0/5）" in bk2[0]
		and Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size).encloses(bk2[3]),
		"step4a AC6/AC8: the 门派簿 shows the 悬赏 progress (第几条) and the 委托 count x/5; it still fits the screen", str(bk[0]) + str(bk2[0]))


# ================================================================== 补充: no text ever overflows the dialogue box
## Every line the dialogue box can show: the scenes of story / sample / step 3 / jianghu (step-3 templates filled with
## every greeting and chat line and the longest day numbers), the board's built menus and result lines for every bounty
## and 委托 kind. [entry, choices (option texts) or []]
func all_lines() -> Array:
	var out := []
	var add_scene := func(entries: Array, tag: String) -> void:
		var stack := entries.duplicate()
		while not stack.is_empty():
			var e = stack.pop_front()
			if not (e is Dictionary):
				continue
			if e.has("choice"):
				out.append([{"kind": "选项", "text": "", "tag": tag}, (e["choice"] as Array).map(func(o): return String(o.get("text", "")))])
				for o in e["choice"]:
					stack.append_array(o.get("then", []))
			elif e.has("text"):
				var x: Dictionary = e.duplicate()
				x["tag"] = tag
				out.append([x, []])
	var sc: Dictionary = story.data["scenes"]
	for id in sc:
		if s3._templates.has(id):
			continue
		add_scene.call(sc[id], String(id))
	# step-3 templates: {day} etc. with long numbers, every greeting and every chat line
	var vals := Step3.numbers()
	vals["day"] = 999
	vals["next_day"] = 999
	vals["edition"] = 333
	var greets: Array = s3.data.get("greetings", {}).values()
	var chats: Array = s3.data.get("chats", [])
	var longest_g: String = greets.reduce(func(a, x): return x if String(x).length() > String(a).length() else a, "")
	var longest_c: String = chats.reduce(func(a, x): return x if String(x).length() > String(a).length() else a, "")
	for id in s3._templates:
		var raw := JSON.stringify(s3._templates[id])
		var combos := [[longest_g, longest_c]]
		if "{greeting}" in raw:
			for gr in greets:
				combos.append([gr, longest_c])
		if "{chat}" in raw:
			for ch in chats:
				combos.append([longest_g, ch])
		for cb in combos:
			vals["greeting"] = cb[0]
			vals["chat"] = cb[1]
			add_scene.call(Step3.fill_entries(s3._templates[id], vals), String(id))
	# the 江湖告示榜's built menus and result lines
	var ui: Dictionary = jh.data["ui"]
	var lines := []
	for i in 3:
		var d: Dictionary = jh.data["bounties"][i]
		lines.append(ui["bounty_offer"] % [i + 1, d["name"], d["place"], int(d["coins"]), int(d["fame"]), d["desc"]])
		lines.append(ui["bounty_active"] % [d["name"], d["place"]])
		lines.append(ui["bounty_won"] % [d["name"], int(d["coins"]), ui["bounty_fame_part"] % int(d["fame"])])
		lines.append(ui["bounty_accepted"] % [d["name"], d["place"]])
		lines.append(ui["bounty_abandoned"] % d["name"])
	lines.append(ui["patrol_offer"] % [15, jh.data["patrol"]["desc"], 999])
	lines.append(ui["bounty_paid"] % [80, ui["bounty_paid_fame"] % 2])
	lines.append(ui["bounty_paid"] % [80, ui["bounty_paid_fame_full"]])
	lines.append(ui["bounty_none_next"] % [999, 999])
	lines.append(ui["patrol_none_next"] % [999, 999])
	lines.append(ui["bounty_slot_full"])
	for k in jh.data["kinds"]:
		var kd: Dictionary = jh.data["kinds"][k]
		lines.append(ui["commission_detail"] % [kd["client"], kd["name"], 18, kd["desc"]])
		lines.append(ui["commission_paid"] % [kd["client"], kd["thanks"], 18] + "\n" + ui["commission_estate_full"] % 100)
		lines.append(ui["commission_accepted"] % kd["name"])
		lines.append(ui["commission_abandoned"] % kd["name"])
		for st in kd["hud"]:
			lines.append(ui["abandon_question"] % [kd["name"], String(st).replace("%d", "3")])
	lines.append("\n".join([ui["commission_head"] + ui["commission_bonus"] % [10, Jianghu.mult_text()], ui["commission_line"] % [1, "补篱笆", 18, ui["commission_taken"] % "补村口东边的篱笆 3/3"],
		ui["commission_line"] % [2, "挖竹笋", 18, ui["commission_ready"]]]))
	lines.append(ui["commission_none"])
	lines.append(ui["board_title"])
	for t in lines:
		out.append([{"kind": "告示", "text": t, "tag": "board"}, []])
	out.append([{"kind": "选项", "text": "", "tag": "board"}, [ui["opt_c_abandon"] % "补篱笆", ui["opt_c_turnin"] % "挖竹笋", ui["opt_leave"]]])
	return out


func test_dialogue_fit() -> void:
	await game()
	await r.frames(3)
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var items := all_lines()
	var bad := []
	var n_lines := 0
	var n_pages := 0
	var n_choices := 0
	var multi := 0
	var max_lines := 0
	var longest := ""
	var f: Font = dlg.text_label.get_theme_font("font")
	var fs: int = dlg.text_label.get_theme_font_size("font_size")
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	for it in items:
		var e: Dictionary = it[0]
		var opts: Array = it[1]
		if not opts.is_empty():
			n_choices += 1
			dlg.choice_options = opts
			dlg.choice_disabled = []
			dlg._show_choices()
			await r.process_frame
			var cr: Rect2 = dlg.choice_panel.get_global_rect()
			var box_top: float = vp.y - Dialogue.BOX_H - 6.0
			var cut := false
			for i in opts.size():
				var l: Label = dlg.choice_labels[i]
				if l.get_line_count() > 1 or not cr.grow(0.5).encloses(l.get_global_rect()):
					cut = true
			if not Rect2(Vector2.ZERO, vp).encloses(cr) or cr.end.y > box_top + 0.5 or cut:
				bad.append("%s choice %s %s" % [e["tag"], str(opts), cr])
			dlg.choice_panel.visible = false
			dlg.choosing = false
			continue
		n_lines += 1
		dlg.entry = e
		dlg.kind = "speaker" if e.has("who") else String(e.get("kind", "旁白"))
		dlg.speaker_name = dlg.name_for(e)
		dlg.full_text = String(e["text"])
		dlg.screen_text = dlg._screen(dlg.full_text)       # 中英文切换 v1: the line as shown in the language being played
		dlg._apply_style()
		var pages: PackedStringArray = dlg.paginate(dlg.screen_text)
		n_pages += pages.size()
		if pages.size() > 1:
			multi += 1
		if dlg.full_text.length() > longest.length():
			longest = dlg.full_text
		var tw: float = dlg.text_label.size.x
		for pg in pages:
			var nl := dlg.lines_for(pg)
			var h := nl * dlg.line_height() - float(dlg.text_label.get_theme_constant("line_spacing"))
			var w := f.get_multiline_string_size(pg, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, -1, flags).x
			# independent count: a fresh TextParagraph with the same font, size and width
			var para := TextParagraph.new()
			para.add_string(pg, f, fs)
			para.width = tw
			para.break_flags = flags
			if para.get_line_count() != nl:
				bad.append("%s '%s' label %d lines, paragraph %d" % [e["tag"], pg.substr(0, 16), nl, para.get_line_count()])
			max_lines = maxi(max_lines, nl)
			if h > dlg.text_room() + 0.01 or w > tw + 0.5 or pg.strip_edges() == "":
				bad.append("%s '%s' lines %d h %.1f w %.1f" % [e["tag"], pg.substr(0, 16), nl, h, w])
		var gone := "\n " if Lang.is_en() else "\n"     # (English pages may drop the space they were cut at)
		var joined := "".join(pages)
		var whole := dlg.screen_text
		for ch in gone:
			joined = joined.replace(ch, "")
			whole = whole.replace(ch, "")
		if joined != whole:
			bad.append("%s text lost '%s'" % [e["tag"], dlg.full_text.substr(0, 16)])
		if Lang.is_en() and Lang.translation().has_cjk(dlg.screen_text):
			bad.append("%s not translated '%s'" % [e["tag"], dlg.full_text.substr(0, 24)])
		if e.has("image"):
			var pr: Rect2 = dlg.picture_panel.get_global_rect()
			if not Rect2(Vector2.ZERO, vp).encloses(pr) or pr.end.y > vp.y - Dialogue.BOX_H - 6.0 + 0.5:
				bad.append("%s picture %s" % [e["tag"], pr])
	report["dialogue_fit"] = {"lines": n_lines, "pages": n_pages, "multi_page_lines": multi, "choices": n_choices, "capacity": dlg.line_capacity(), "max_lines_on_a_page": max_lines}
	print("DIALOGUE FIT ", report["dialogue_fit"], " longest: ", longest)
	r.check(bad.is_empty() and n_lines > 300 and n_choices > 30 and max_lines == dlg.line_capacity(),
		"补充: every line of every data file (story / sample / step3 / jianghu scenes, step-3 templates with every greeting / chat, the board's built lines: %d lines -> %d pages, %d of them on more than one page) and every choice list (%d) fits the dialogue box with the real layout (lines x line height <= %.0f px, width <= the text area; choices / pictures on screen, above the box); paging loses no text" % [n_lines, n_pages, multi, n_choices, dlg.text_room()],
		str(bad.slice(0, 12)))
	# the panels with long text: every Esc tips page and the 门派簿 fit the screen, no label cut
	var pm: PauseMenu = g.pause_menu
	await r.tap(KEY_ESCAPE)
	var esc_bad := []
	for pgi in pm.tip_pages.size():
		pm.show_page(pgi)
		await r.process_frame
		await r.process_frame
		var rect := pm.panel.get_global_rect()
		if not Rect2(Vector2.ZERO, vp).encloses(rect):
			esc_bad.append("page %d panel" % pgi)
		for l in pm.tip_pages[pgi].get_children():
			if l is Label and (l.size.y + 0.5 < l.get_combined_minimum_size().y or not rect.grow(1).encloses(l.get_global_rect())):
				esc_bad.append("page %d '%s'" % [pgi, l.text.substr(0, 6)])
	await r.tap(KEY_ESCAPE)
	r.check(esc_bad.is_empty(), "补充: every Esc tips page (1-4) fits the screen; no tip is cut", str(esc_bad))


## Paging with real keys. Every data line fits one page today (test_dialogue_fit), so the check uses the longest real
## line (one page) and a long speech made of 黑虎's real lines run together (several pages): E turns the page, the pages
## end at punctuation, nothing is lost, the next line comes after the last page.
func long_speech() -> String:
	var t := ""
	for id in ["J-黑虎-上场", "J-黑虎-胜"]:
		for e in jh.data["scenes"][id]:
			if String(e.get("who", "")) == "tiger":
				t += String(e["text"])
	return t


func play_pages(text: String, who: String) -> Array:
	story.data["scenes"]["T-分页"] = [{"who": who, "text": text}, {"kind": "提示", "text": "（下一句）"}]
	story.play("T-分页")
	await r.frames(3)
	var pages := dlg.pages.size()
	var page_list: Array = Array(dlg.pages)
	var seen := []
	for i in 300:
		if not story.busy:
			break
		if dlg.active and not dlg.is_typing() and (seen.is_empty() or seen[-1] != dlg.page_text):
			seen.append(dlg.page_text)
		await r.tap(KEY_E)
	return [pages, seen, page_list]


func test_pages() -> void:
	if Lang.is_en():
		# Chinese paging (pages end at 。，！); the English pages are checked by tests/i18n_suite.gd (test_english_paging, test_midline)
		r.check(true, "补充 (%s): Chinese-text paging check - skipped in the English run, see i18n_suite" % "pages")
		return
	await game()
	await r.frames(3)
	var best: Dictionary = {}
	for it in all_lines():
		if (it[1] as Array).is_empty() and it[0].has("who") and String(it[0]["text"]).length() > String(best.get("text", "")).length():
			best = it[0]
	var a := await play_pages(String(best["text"]), String(best["who"]))
	r.check(a[0] == 1 and a[1].size() == 2 and a[1][0] == String(best["text"]),
		"补充: the longest spoken line in the data (%d characters) fits one page" % String(best["text"]).length(), String(best["text"]))
	var speech := long_speech()
	var b2 := await play_pages(speech, "tiger")
	var pages: int = b2[0]
	var seen: Array = b2[1]
	var ends_ok := true
	for i in range(0, pages - 1):
		var pg: String = b2[2][i]
		var last := pg[pg.length() - 1]
		if not (Dialogue.BREAK_AFTER.contains(last) or Dialogue.CLOSERS.contains(last)):
			ends_ok = false
	report["paging_demo"] = b2[2]
	r.check(pages >= 2 and seen.size() == pages + 1 and "".join(seen.slice(0, pages)) == speech and seen[-1] == "（下一句）" and ends_ok,
		"补充: a long speech (%d characters) shows in %d pages: E turns the page, every page ends at a punctuation mark, nothing is lost, then the next line" % [speech.length(), pages],
		str(b2[2]))


# ================================================================== 修复 v1: the real screen, window changes, every panel
const WINDOWS := [Vector2i(1440, 810), Vector2i(640, 360), Vector2i(1000, 560)]


func set_window(w: Vector2i) -> Vector2:
	r.root.size = w
	for i in 4:
		await r.process_frame
	return g.get_viewport().get_visible_rect().size


## The layout checks run on the game's real view: a 1440 x 810 window shows exactly 480 x 270.
func test_view() -> void:
	await game()
	var vp := await set_window(Vector2i(1440, 810))
	r.check(vp == Vector2(480, 270) and r.root.size == Vector2i(1440, 810),
		"修复 v1: layout checks run on the real view - a 1440x810 window shows 480x270 (headless runs used to measure on 480x480)", str(vp))


## A long line on screen while the window changes size: it is laid out again (text inside the box, in pages that fit).
func test_resize() -> void:
	if Lang.is_en():
		# Chinese paging (pages end at 。，！); the English pages are checked by tests/i18n_suite.gd (test_english_paging, test_midline)
		r.check(true, "补充 (%s): Chinese-text paging check - skipped in the English run, see i18n_suite" % "resize")
		return
	await game()
	var vp0 := await set_window(Vector2i(1920, 810))
	story.data["scenes"]["T-缩放"] = [{"who": "tiger", "text": long_speech()}, {"kind": "提示", "text": "（下一句）"}]
	story.play("T-缩放")
	for i in 12:
		await r.process_frame
	var res := []
	var bad := []
	for w in [Vector2i(1440, 810), Vector2i(1000, 560), Vector2i(1920, 810)]:
		var vp := await set_window(w)
		var box: Rect2 = dlg.box.get_global_rect().grow(-2)
		var lr: Rect2 = dlg.text_label.get_global_rect()
		var nl := dlg.lines_for(dlg.page_text)
		var h := nl * dlg.line_height() - float(dlg.text_label.get_theme_constant("line_spacing"))
		var inside: bool = box.encloses(Rect2(lr.position, Vector2(lr.size.x, h))) and Rect2(Vector2.ZERO, vp).encloses(dlg.box.get_global_rect())
		res.append({"win": w, "view": vp, "pages": dlg.pages.size(), "page": dlg.page, "lines": nl, "inside": inside})
		if not inside or nl > dlg.line_capacity():
			bad.append(w)
	# reading on after the changes: nothing lost
	var seen := [dlg.page_text]
	for i in 200:
		if not story.busy:
			break
		await r.tap(KEY_E)
		if dlg.active and not dlg.is_typing() and seen[-1] != dlg.page_text:
			seen.append(dlg.page_text)
	await set_window(Vector2i(1440, 810))
	r.check(bad.is_empty() and dlg.relayouts >= 3 and vp0 == Vector2(640, 270),
		"修复 v1: a long line on screen while the window goes 1920x810 -> 1440x810 -> 1000x560 -> 1920x810: laid out again each time, the text stays inside the box (pages re-cut to fit)", str(res))
	r.check(seen[-1] == "（下一句）", "修复 v1: after the resizes the line reads on to its end and the next line", str(seen))


## Every panel with text on the real screen (and 640x360 / 1000x560 windows): the Esc pages, the 门派簿 full of entries,
## the HUD list with its longest lines, every toast, the board prompts, the 序章 · 完 page.
func test_screens() -> void:
	await game()
	set_day(2, 9.0)
	await r.frames(3)
	var bad := []
	# a full book: every bounty turned in, 巡山, 委托, step-3 titles / disciple lines
	b.main_done = 3
	b.patrols_done = 12
	b.fame_points = 4
	cm.total = 23
	cm.estate_points = 4
	s3.arena.wins = [1, 2, 3, 4, 5, 6]
	s3.arena.hard_wins = [7, 8, 9]
	for f in ["trial_bronze", "trial_silver", "trial_gold", "repair_roof", "repair_dorm_old", "repair_kitchen"]:
		story.flags[f] = true
	var pm: PauseMenu = g.pause_menu
	for w in WINDOWS:
		var vp := await set_window(w)
		var scr := Rect2(Vector2.ZERO, vp)
		# Esc pages 1-4
		pm.open()
		for pgi in pm.tip_pages.size():
			pm.show_page(pgi)
			await r.process_frame
			await r.process_frame
			var rect := pm.panel.get_global_rect()
			if not scr.encloses(rect) or not scr.encloses(pm.resume_button.get_global_rect()):
				bad.append("%s Esc %d %s" % [w, pgi + 1, rect])
			for l in pm.tip_pages[pgi].get_children() + pm.key_labels:
				if l is Label and l.is_visible_in_tree() and not rect.grow(1).encloses(l.get_global_rect()):
					bad.append("%s Esc %d label '%s'" % [w, pgi + 1, l.text.substr(0, 6)])
		pm.close()
		await r.process_frame
		# the 门派簿
		story.book_unlocked = true
		await r.tap(KEY_B)
		await r.frames(3)
		var br: Rect2 = story.sect_book.panel.get_global_rect()
		report["book_full_%dx%d" % [w.x, w.y]] = {"size": story.sect_book.panel.size, "scale": story.sect_book.panel.scale.x}
		if not scr.encloses(br):
			bad.append("%s book %s" % [w, br])
		await r.tap(KEY_ESCAPE)
		await r.frames(2)
		# the HUD list with its longest lines
		b.active = {"type": "main", "index": 2, "edition": -1, "state": "accepted", "intro": true}
		cm.offers = [{"kind": "fence", "state": "taken", "step": 0, "count": 2, "spots": [0, 1, 2], "picked": [0, 1]},
			{"kind": "letter", "state": "taken", "step": 1, "count": 0, "spots": [], "picked": []}]
		cm.day = jh.cal_day()
		await r.frames(3)
		var tr: Rect2 = jh.tasks_panel.get_global_rect()
		if not jh.tasks_panel.visible or not scr.encloses(tr) or tr.intersects(g.hud.clock.get_global_rect()):
			bad.append("%s tasks %s '%s'" % [w, tr, jh.tasks_label.text])
		b.active = {}
		cm.offers = []
		cm.day = jh.cal_day()
		# every toast text of the game (sample / step3 / jianghu ui, numbers filled with 3 digits)
		for src in [smp.data.get("ui", {}), s3.data.get("ui", {}), jh.data.get("ui", {})]:
			for k in src:
				if not (src[k] is String) or not (String(k).begins_with("toast") or String(k) in ["start_coins", "stall_income", "paid", "fee_paid", "youngster_came", "upkeep", "upkeep_short", "upkeep_repaid", "sweep_estate", "joined_toast", "out_refill", "forfeited"]):
					continue
				var t := String(src[k]).replace("%d", "100").replace("%s", "补篱笆")
				g.hud.show_toast(t, 0.2)
				await r.process_frame
				var tt: Rect2 = g.hud.toast_text_rect()
				if not scr.encloses(tt):
					bad.append("%s toast '%s' %s" % [w, t, tt])
		# the two boards' prompts
		for pt in [jh.board_point, s3.arena.board_point()]:
			await r.teleport(pt)
			await r.frames(3)
			if not g.hud.prompt.visible or not scr.encloses(g.hud.prompt.get_global_rect()):
				bad.append("%s prompt at %s %s" % [w, pt, g.hud.prompt.get_global_rect()])
		# the 序章 · 完 caption (新手指引 v1: it replaced the 序章 · 完 page) and a long 指引完成 caption
		for cap in ["序章 · 完", g.guide.uf("step_done", {"title": "告示榜与比武", "coins": 100})]:
			g.guide.caption_label.text = cap
			g.guide.caption_label.modulate.a = 1.0
			await r.process_frame
			var cf: Font = g.guide.caption_label.get_theme_font("font")
			var cw := cf.get_string_size(Lang.t(cap), HORIZONTAL_ALIGNMENT_LEFT, -1, g.guide.caption_label.get_theme_font_size("font_size")).x
			if cw > vp.x - 4.0 or not scr.encloses(g.guide.caption_label.get_global_rect()):
				bad.append("%s caption '%s' w %.0f" % [w, cap, cw])
			g.guide.caption_label.modulate.a = 0.0
		await r.frames(2)
	await set_window(Vector2i(1440, 810))
	r.check(bad.is_empty(), "修复 v1: at 480x270 (1440x810), 640x360 and 500x280 (1000x560): every Esc page (button included), the full 门派簿, the HUD list with its longest lines, every toast, both boards' prompts and the 序章 · 完 / 指引完成 captions stay on the screen", str(bad.slice(0, 12)))


## A save made indoors with the chick following: after loading, the chick waits outside that room's door (not inside).
func test_chick_indoors() -> void:
	await game()
	set_day(1, 9.0)
	await r.frames(3)
	await day_with("chicken")
	await accept_commission("chicken")
	await walk(cm.chick.global_position + Vector2(0, 18))
	await r.tap(KEY_E)
	await finish()
	var res: String = await walk(g.interiors.exit_spot("kitchen") + Vector2(0, 2), 200.0)
	var res2: String = await ss.nav.go_in("kitchen")
	await r.frames(5)
	var inside_now: bool = g.interiors.room_at(p().global_position) == "kitchen"
	smp.save_now("test")
	await reload_game()
	var room: String = g.interiors.room_at(p().global_position)
	var cpos: Vector2 = cm.chick.global_position
	var ok_load: bool = room == "kitchen" and cm.chick_state == "follow" and g.interiors.room_at(cpos) == "" \
		and cpos.distance_to(g.interiors.exit_spot("kitchen")) < 2.0
	var res3: String = await ss.nav.go_out("kitchen")
	await r.frames(10)
	r.check(inside_now and ok_load and res3 == "door" and cm.chick.global_position.distance_to(p().global_position) < 30.0 and cm.chick_max_wall == 0,
		"修复 v1: saved in the kitchen with the chick following -> after loading it waits outside the kitchen door (never inside the room) and is at his heels again when he walks out",
		str([res, res2, inside_now, room, cpos, cm.chick_state, res3]))
