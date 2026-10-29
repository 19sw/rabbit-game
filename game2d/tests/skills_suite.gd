extends RefCounted
## 武学与经营 第一批 · 武学 checks (developer A; docs/design/武学与经营-第一批-方案-v1.md 第一节 + 第五节), run by
## tests/run_tests.gd at the end, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-skills      (add --sk=name,name)
## Real keys (U / I / Space / J / K / E / 1 / 2 / B / Q / ← →) and real physics wherever the player does something; state is
## set directly only for starting points (名望 points, the clock, a skill already learned for a mechanics check, a medal
## flag for the "拿过银" case) - never for the result that is checked.
##   cards     cards/skills/*.tres = the plan table; data/skills.json conditions / trials; U I O registered
##   spin      U: 0.15 s to the blow, 0.5 s in place, every enemy within 48 px (+ its body) takes 15, pushed 24 px x (1 -
##             resist), 0.3 s stagger without super armour, only damage with it (牦牛 / 黑虎 cards); cooldown 4 s (U again
##             at 2 s does nothing, at 4 s it works); I with an empty slot does nothing; the icon's cooldown sweep
##   snow      Space within 0.3 s of a dodge landing = a second dodge 70 % as far, the same i-frames, the cooldown only
##             after it; not before learning / not after 0.3 s; the snow mark where it lands
##   tuna      max HP 120, regen after 3 s at 5 / s; + 药膳 (set_max_hp_bonus "yaoshan" 15) = 135; removed -> 120
##   teach     no lesson below 名望 2; 师父 gives each trial; 3 GP in one 师兄 spar; 打坐 on a 正殿 蒲团 (real keys) to the
##             next 08:00; 银 (an old 银 / 金 counts at once); the ring caption; the slot U; 夜里 "师父 06:00 起"
##   same      打坐 = 等到天亮 = T hour by hour (clock, coins, stall, upkeep, 委托, 悬赏, who is asleep, B's farm when there)
##   book      the 武学 page: silhouettes + how to learn, ↑↓ / E swaps U <-> I, fits the 480x270 screen (中文 / English)
##   board     the 任务面板 tab 武学: locked / go / trial / back / learned, tracking arrow at 师父
##   save      round trip; max HP 120 survives loading; an old save (no "skills") loads with nothing learned
##   bots      困难 (10 seeded tournaments) and 黑虎 (10 seeded fights): the spin bot beats the plain masher; the spin
##             spammer wins < 30 %
##   misc      sounds / events, qi counted but not shown, never 她 / 师姐 / she / her for 小兔

var r
var ss                     # tests/sample_suite.gd (game helpers)
var t3                     # tests/step3_suite.gd
var s4                     # tests/step4a_suite.gd
var sc                     # tests/schedule_suite.gd (observables, nights)
var gp                     # tests/gp_suite.gd (the sandbox game, spar_with)
var g: Node
var story: Story
var dlg: Dialogue
var sk: Skills
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
	Lang.set_lang("zh")
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--sk="):
			only = String(a).trim_prefix("--sk=").split(",")
	ss = load("res://tests/sample_suite.gd").new(r)
	t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	s4 = load("res://tests/step4a_suite.gd").new(r)
	s4.ss = ss
	s4.t3 = t3
	sc = load("res://tests/schedule_suite.gd").new(r)
	sc.ss = ss
	sc.t3 = t3
	sc.s4 = s4
	var tests := ["cards", "texts", "spin", "spin_armor", "snow", "tuna", "teach", "night", "same", "book", "board", "save",
		"audio", "bots_hard", "bots_tiger"]
	for name in tests:
		if only.is_empty() or name in only:
			await call("test_" + name)
	if gp != null:
		await gp._free_game()
	await ss._free_game()
	SaveGame.erase()
	Lang.set_lang("zh")
	print("SKILLS REPORT ", report)


# ================================================================== helpers
func bind() -> void:
	sc.bind()
	g = ss.g
	story = g.story
	dlg = story.dialogue
	sk = g.skills


func p() -> Player:
	return g.player


## A game after the prologue (the real ending), clock stopped.
func game(day_idx := 0) -> void:
	if gp != null:
		await gp._free_game()
		gp = null
	await t3.unlocked_game(day_idx)
	bind()
	g.daynight.running = false
	await r.frames(3)


## 名望 to `n` (a starting point: the 比武大会 points counter).
func set_fame(n: int) -> void:
	var s3: Step3 = g.step3
	s3.arena.fame_points += n - s3.value("fame")
	await r.frames(1)


func tap_u(code := KEY_U) -> void:
	r.key(code, true)
	await r.frames(2)
	r.key(code, false)


## The sandbox game of tests/gp_suite.gd (no story, 师兄 invites at once) with 师兄 wearing `card`, calm.
func sandbox(card := "") -> void:
	if gp == null:
		await ss._free_game()
		gp = load("res://tests/gp_suite.gd").new(r)
		await gp.sandbox_game()
	await gp.spar_with(card)
	g = gp.g
	story = g.story
	dlg = story.dialogue
	sk = g.skills


func all_text(v: Variant) -> String:
	if v is Dictionary:
		var out := ""
		for k in v:
			out += String(k) + " " + all_text(v[k]) + "\n"
		return out
	if v is Array:
		return "\n".join(v.map(func(x): return all_text(x)))
	return str(v)


# ================================================================== cards / texts
func test_cards() -> void:
	var sp: SkillSpinStats = load("res://cards/skills/swallow_spin.tres")
	var tu: SkillTunaStats = load("res://cards/skills/tuna.tres")
	var sn: SkillSnowStats = load("res://cards/skills/snow_step.tres")
	var pl: PlayerStats = load("res://cards/player.tres")
	var bad := []
	if [sp.damage, sp.radius, sp.impact, sp.length, sp.knockback, sp.stagger, sp.cooldown] != [15, 48.0, 0.15, 0.5, 24.0, 0.3, 4.0]:
		bad.append("swallow_spin")
	if pl.max_hp + tu.max_hp_bonus != 120 or not is_equal_approx(tu.regen_delay, 3.0) or not is_equal_approx(tu.regen_per_sec, 5.0) \
			or pl.max_hp != 100 or not is_equal_approx(pl.regen_delay, 5.0) or not is_equal_approx(pl.regen_per_sec, 3.0):
		bad.append("tuna")
	if not is_equal_approx(sn.window, 0.3) or not is_equal_approx(sn.distance_ratio, 0.7):
		bad.append("snow_step")
	r.check(bad.is_empty(), "skills cards: 燕回旋 15 / 48 px / 0.15 s / 0.5 s / 推开 24 / 硬直 0.3 / 冷却 4 s; 吐纳功 100 -> 120, 回血 5 s -> 3 s, 3 -> 5 / s; 二段闪 0.3 s, 70 %% (= 方案表)", str(bad))
	var d := Skills.load_data()
	var sks: Dictionary = d["skills"]
	var cond := [int(sks["swallow_spin"]["need_fame"]), String(sks["swallow_spin"]["trial"]), int(sks["swallow_spin"]["trial_need"]),
		int(sks["tuna"]["need_fame"]), String(sks["tuna"]["trial"]), int(sks["snow_step"]["need_fame"]), String(sks["snow_step"]["trial"])]
	r.check(cond == [2, "spar_gp", 3, 3, "meditate", 4, "trial_silver"] and d.has("_说明"),
		"skills data: data/skills.json - 燕回旋 名望 2 + 同一场格挡 3 次, 吐纳功 名望 3 + 打坐, 二段闪 名望 4 + 梅花桩银", str(cond))
	load("res://scripts/main.gd").ensure_input_actions()
	var keys := {}
	for a in ["skill_1", "skill_2", "skill_3"]:
		var evs := InputMap.action_get_events(a) if InputMap.has_action(a) else []
		keys[a] = (evs[0] as InputEventKey).physical_keycode if not evs.is_empty() else -1
	r.check(keys["skill_1"] == KEY_U and keys["skill_2"] == KEY_I and keys["skill_3"] == KEY_O,
		"skills keys: U / I are the two move slots, O is registered (no move goes there this batch)", str(keys))


func test_texts() -> void:
	var txt := FileAccess.get_file_as_string("res://data/skills.json") + FileAccess.get_file_as_string("res://data/i18n/en_skills.json")
	var bad := []
	for w in ["她", "师姐", " she ", " her ", "She ", "Her "]:
		if w in txt:
			bad.append(w)
	var addressed: bool = "兔儿" in txt and "徒儿" in txt
	r.check(bad.is_empty() and addressed, "skills texts: 师父 calls 小兔 兔儿 / 徒儿; no 她 / 师姐 / she / her anywhere in the skills' Chinese or English", str(bad))
	# every Chinese text of skills.json shown on screen has English (the scene lines, names, page / board / ui strings)
	var en = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/en_skills.json"))
	var lines: Dictionary = en["lines"]
	var miss := []
	var d := Skills.load_data()
	for id in d["scenes"]:
		for e in d["scenes"][id]:
			if e.has("text") and not lines.has(String(e["text"])):
				miss.append(e["text"])
			for o in e.get("choice", []):
				if not lines.has(String(o["text"])):
					miss.append(o["text"])
	for id in d["skills"]:
		for k in ["name", "desc"]:
			if not lines.has(String(d["skills"][id][k])):
				miss.append(d["skills"][id][k])
	r.check(miss.is_empty(), "skills texts: every line / option / name / description of data/skills.json has its English in data/i18n/en_skills.json", str(miss))


# ================================================================== 燕回旋
func test_spin() -> void:
	await sandbox()
	var fox: Fighter = gp.fox
	sk.learn("swallow_spin", false)
	var slot_u: bool = sk.slots["u"] == "swallow_spin" and sk.slots["i"] == ""
	await r.teleport(fox.global_position + Vector2(40, 0))     # 40 px: inside 48 + body
	var hp0 := fox.hp
	var resist := fox.stats.knock_resist
	var x0 := fox.global_position
	var c0 := p().spins_started
	r.key(KEY_U, true)
	var hit_frame := -1
	var spin_frames := 0
	var start_pos := p().global_position
	var push := 0.0
	var cd_at_start := -1.0
	for i in 60:
		await r.physics_frame
		if i == 1:
			r.key(KEY_U, false)
		if cd_at_start < 0.0 and p().is_spinning():
			cd_at_start = sk.cooldown_fraction("swallow_spin")
		if p().is_spinning():
			r.hold_dir(Vector2.LEFT)          # walking does nothing during the spin
			if not g.combat.frozen:
				spin_frames += 1
		elif spin_frames > 0:
			r.release_all()
		if hit_frame < 0 and fox.hp < hp0:
			hit_frame = spin_frames
		if hit_frame >= 0 and spin_frames - hit_frame <= 12:
			push = maxf(push, fox.global_position.distance_to(x0))
	r.release_all()
	var moved := p().global_position.distance_to(start_pos) > 1.0
	var dmg := hp0 - fox.hp
	var staggered: bool = fox.skill_staggers >= 1
	r.check(slot_u and p().spins_started == c0 + 1 and dmg == 15 and staggered and not moved,
		"skills spin: the first move learned goes into U; U by key spins in place (walking keys ignored), 师兄 (no super armour) within reach takes 15 and is staggered",
		"slot %s dmg %d stagger %s moved %s" % [slot_u, dmg, staggered, moved])
	r.check(abs(hit_frame - 9) <= 1 and abs(spin_frames - 30) <= 1,
		"skills spin: the blow lands 0.15 s after U (frame %d of the move), the move lasts 0.5 s (%d frames, hitstop frames not counted)" % [hit_frame, spin_frames])
	r.check(absf(push - 24.0 * (1.0 - resist)) <= 3.0 and is_equal_approx(fox._stagger_len, 0.3),
		"skills spin: pushed 24 px x (1 - knock resist) = %.1f (moved %.1f), stagger 0.3 s" % [24.0 * (1.0 - resist), push], str(fox._stagger_len))
	# cooldown: U again at 2 s does nothing; at 4 s it works
	var c1 := p().spins_started
	for i in 300:
		if sk.cooldown_left("swallow_spin") <= 2.0:
			break
		await r.physics_frame
	await tap_u()
	await r.frames(3)
	var early_ok := p().spins_started == c1
	var icon_mid: float = sk.hud.icon_remaining("u") if sk.hud.icons_visible() else sk.cooldown_fraction("swallow_spin")
	for i in 300:
		if sk.cooldown_left("swallow_spin") <= 0.0:
			break
		await r.physics_frame
	await tap_u()
	await r.frames(3)
	r.check(early_ok and p().spins_started == c1 + 1 and cd_at_start > 0.98 and icon_mid > 0.35 and icon_mid < 0.55,
		"skills spin: cooldown 4 s - U at 2 s does nothing (%.2f of the cooldown left), after 4 s U spins again" % icon_mid, "%s %d %d %.2f" % [early_ok, c1, p().spins_started, cd_at_start])
	# out of reach: nothing; I with an empty slot: nothing
	await r.frames(40)
	for i in 300:
		if sk.cooldown_left("swallow_spin") <= 0.0:
			break
		await r.physics_frame
	await gp.spar_with("", Vector2(80, 0))
	gp.cs.calm_fox()                 # (he stays where he is: move speed 0)
	await r.frames(2)
	var hp1 := fox.hp
	await tap_u()
	await r.frames(30)
	var far_ok := fox.hp == hp1
	for i in 300:
		if sk.cooldown_left("swallow_spin") <= 0.0:
			break
		await r.physics_frame
	var c2 := p().spins_started
	await tap_u(KEY_I)
	await r.frames(10)
	r.check(far_ok and p().spins_started == c2 and p().last_spin_hits == 0,
		"skills spin: 80 px away nothing is hit (48 px reach); I with an empty slot does nothing")
	# a dodge cuts the spin short; GP / J do not start during it
	await tap_u()
	await r.frames(3)
	var was := p().is_spinning()
	r.hold_dir(Vector2.UP)
	await r.tap(KEY_SPACE)
	r.release_all()
	r.check(was and not p().is_spinning() and (p().is_dashing() or p().dash_cooldown_left > 0.0), "skills spin: a dodge (Space) cuts the spin short")


func test_spin_armor() -> void:
	var res := {}
	for card in ["yak_hard", "tiger", "wolf"]:
		await sandbox(card)
		var fox: Fighter = gp.fox
		sk.learn("swallow_spin", false)
		sk.cooldowns.clear()
		await r.teleport(fox.global_position + Vector2(38, 0))
		var hp0 := fox.hp
		var st0 := fox.skill_staggers
		var x0 := fox.global_position
		await tap_u()
		await r.frames(20)
		res[card] = [hp0 - fox.hp, fox.skill_staggers - st0, snappedf(fox.global_position.distance_to(x0), 0.1)]
	var ok: bool = res["yak_hard"][0] == 15 and res["yak_hard"][1] == 0 and res["tiger"][0] == 15 and res["tiger"][1] == 0 \
		and res["wolf"][0] == 15 and res["wolf"][1] == 1
	r.check(ok, "skills spin: super armour (牦牛 yak_hard, 黑虎 tiger) only loses 15 HP - no stagger, no push; without it (狼) staggered", str(res))
	await gp.spar_with("")


# ================================================================== 踏雪二段闪
## One dodge to the right (+ a second press `second_after` frames after it lands, -1 = none). Returns the result.
func dodge_run(second_after: int) -> Dictionary:
	var pl := p()
	pl.dash_cooldown_left = 0.0
	pl.second_dash_window = 0.0
	await r.frames(2)
	var x0 := pl.global_position.x
	r.hold_dir(Vector2.RIGHT)
	await r.tap(KEY_SPACE)
	var guard := 0
	while pl.is_dashing() and guard < 60:
		await r.physics_frame
		guard += 1
	r.release_all()
	var x1 := pl.global_position.x
	var out := {"first": x1 - x0, "second": 0.0, "started": false, "iframes": 0.0, "cd_after": 0.0, "cd_during": pl.dash_cooldown_left}
	if second_after < 0:
		return out
	await r.frames(second_after)
	var n0 := pl.second_dashes
	r.hold_dir(Vector2.RIGHT)
	r.key(KEY_SPACE, true)
	await r.physics_frame
	await r.physics_frame
	r.key(KEY_SPACE, false)
	out["started"] = pl.second_dashes == n0 + 1
	out["iframes"] = pl.iframes_left
	guard = 0
	while pl.is_dashing() and guard < 60:
		await r.physics_frame
		guard += 1
	r.release_all()
	out["second"] = pl.global_position.x - x1
	out["cd_after"] = pl.dash_cooldown_left
	await r.frames(2)
	return out


func test_snow() -> void:
	await sandbox()
	g.combat.end_spar(false)
	g.combat._timer = 0.0
	g.combat._finish_spar()
	await r.frames(3)
	# an open spot (the training yard, no fighter near)
	var spot: Vector2 = r.find_free_near(gp.fox.global_position + Vector2(-150, 60), 30)
	await r.teleport(spot)
	var before := await dodge_run(6)
	await r.teleport(spot)
	sk.learn("snow_step", false)
	var marks0 := int(sk.fx.spawned.get("snow_mark", 0))
	var a := await dodge_run(6)              # 0.1 s after landing
	await r.teleport(spot)
	var late := await dodge_run(22)          # 0.37 s after landing: the window has closed
	r.check(not before["started"], "skills snow: before learning, Space right after a dodge does nothing (the 0.6 s cooldown)", str(before))
	var ratio: float = float(a["second"]) / maxf(1.0, float(a["first"]))
	r.check(a["started"] and absf(ratio - 0.7) <= 0.06 and a["cd_during"] > 0.0,
		"skills snow: learned - Space within 0.3 s of landing dodges again although the cooldown runs, %.0f px after %.0f px (%.2f, plan 70 %%)" % [a["second"], a["first"], ratio], str(a))
	var pl: PlayerStats = p().stats
	r.check(absf(float(a["iframes"]) - (pl.dodge_iframes - 2.0 / 60.0)) <= 0.04 and absf(float(a["cd_after"]) - pl.dodge_cooldown) <= 0.05,
		"skills snow: the second dodge has the same i-frames (%.2f s left 2 frames in); the cooldown (0.6 s) starts only after it" % float(a["iframes"]), str(a))
	r.check(not late["started"], "skills snow: 0.37 s after landing the window (0.3 s) has closed - no second dodge", str(late))
	r.check(int(sk.fx.spawned.get("snow_mark", 0)) == marks0 + 1, "skills snow: the second dodge leaves the snow mark where it lands (one per second dodge)")


# ================================================================== 吐纳功 + 药膳
func test_tuna() -> void:
	await game()
	var pl := p()
	var m0 := pl.stats.max_hp
	var base_card: PlayerStats = load("res://cards/player.tres")
	sk.learn("tuna", false)
	await r.frames(2)
	var m1 := pl.stats.max_hp
	var full1 := pl.hp
	sk.set_max_hp_bonus("yaoshan", 15)
	var m2 := pl.stats.max_hp
	var hp2 := pl.hp
	sk.set_max_hp_bonus("yaoshan", 0)
	var m3 := pl.stats.max_hp
	r.check(m0 == 100 and m1 == 120 and full1 == 120 and m2 == 135 and hp2 == 135 and m3 == 120 and pl.hp == 120 and base_card.max_hp == 100,
		"skills tuna: 吐纳功 -> max HP 120 (full HP follows); + 药膳 set_max_hp_bonus(\"yaoshan\", 15) -> 135; removed -> 120 (cards/player.tres untouched)",
		str([m0, m1, full1, m2, hp2, m3, pl.hp]))
	# regen: 3 s wait, 5 per s
	pl.hp = 60
	pl.regen_calm = 0.0
	pl.regen_acc = 0.0
	await r.frames(int(2.8 * 60))
	var at28 := pl.hp
	await r.frames(int(2.2 * 60))
	var at50 := pl.hp
	r.check(at28 == 60 and absi(at50 - 70) <= 2, "skills tuna: out of combat HP comes back after 3 s (2.8 s: %d) at 5 / s (5.0 s: %d, plan 70)" % [at28, at50])
	# 药膳 (B's farm) when present: eaten from the 库房 -> 135; the next 08:00 it is gone -> 120
	var fm = g.get("farm")
	if fm != null and fm.has_method("eat_meal"):
		await sc.clock(10.0)
		pl.hp = pl.stats.max_hp
		fm.store["meal"] = 1                  # (a starting point: one 药膳 in the 库房)
		var msg: String = fm.eat_meal()
		await r.frames(2)
		var m4 := pl.stats.max_hp
		var hp4 := pl.hp
		g.daynight.advance_hours(fposmod(7.9 - g.daynight.hour, 24.0))
		await r.frames(3)
		var still := pl.stats.max_hp
		g.daynight.advance_hours(0.2)
		await r.frames(4)
		r.check(msg == "" and still == 135 and m4 == 135 and hp4 == 135 and pl.stats.max_hp == 120 and pl.hp == 120,
			"skills tuna + B 药膳: eaten 120 -> 135 (吐纳功 + 药膳 stack), gone at the next 08:00 -> 120", str([msg, m4, hp4, pl.stats.max_hp, pl.hp]))
	else:
		report["tuna_farm"] = "B's farm.eat_meal() not present in this run - stacking checked through the shared entry only"


# ================================================================== 师父传功
func master_talk() -> Array:
	await sc.clock(10.0)
	await r.frames(int(g.schedule._fade_secs() * 60.0) + 8)
	return await ss.talk("crane", KEY_1)


func test_teach() -> void:
	await game()
	await sc.clock(10.0, 30)
	var f0: int = g.step3.value("fame")
	var at1 := await master_talk()
	var no_lesson: bool = f0 < 2 and not at1.any(func(s): return String(s).begins_with("K-")) and sk.trial_state("swallow_spin") == "none"
	var items1: Array = sk.board_items()
	r.check(no_lesson and String(items1[0]["state"]) == "locked" and "名望到 2 格后找师父（现在 %d 格）" % f0 in String(items1[0]["text"]),
		"skills teach: below 名望 2 师父 has no lesson; the 武学 tab says '名望到 2 格后找师父（现在 %d 格）'" % f0, str([at1, items1[0]]))
	await set_fame(2)
	var it2: Array = sk.board_items()
	var go_ok: bool = String(it2[0]["state"]) == "current" and "去正殿找师父" in String(it2[0]["text"])
	var sc1 := await master_talk()
	r.check(go_ok and sc1.has("K-师父-燕回旋-考验") and sk.trial_state("swallow_spin") == "assigned",
		"skills teach: at 名望 2 the tab shows '师父传功：燕回旋 · 去正殿找师父'; 师父 gives the trial (同一场格挡 3 次)", str(sc1))
	# the trial: a 师兄 spar by real keys with the GP bot until 3 GP in that spar (win or lose)
	var tries := 0
	while not sk.passed("swallow_spin") and tries < 4:
		tries += 1
		await senior_spar("gp_only")
	var best := sk.trial_best("swallow_spin")
	r.check(sk.passed("swallow_spin") and best >= 3 and not sk.has_learned("swallow_spin"),
		"skills teach: 3 GP in one 师兄 spar (real keys, a bot pressing only K at his blows) passes the trial (%d spars, best %d) - not learned yet" % [tries, best])
	var sc2 := await master_talk()
	await r.frames(10)
	var cap: Array = sk.hud.learn_shown
	r.check(sc2.has("K-师父-燕回旋-传授") and sk.has_learned("swallow_spin") and sk.slots["u"] == "swallow_spin" and cap.has("学会：燕回旋（U）")
		and sk.hud.learning_showing() and sk.hud.icons_visible(),
		"skills teach: back at 师父 he teaches it; slot U; the ring caption '学会：燕回旋（U）' shows after the talk; the U / I icons appear", str([sc2, cap]))
	report["shot_learn"] = true
	await r.frames(200)
	g.hud.hide_hint_now()
	await r.frames(30)
	var ir: Rect2 = sk.hud.icons_rect()
	var vpr: Rect2 = g.get_viewport().get_visible_rect()
	var others := [g.hud.objective.get_global_rect(), g.combat.hud.hp_panel.get_global_rect(), Rect2(g.hud.minimap.position, g.hud.minimap.size)]
	var clash := others.filter(func(o): return o.intersects(ir))
	r.check(vpr.encloses(ir) and ir.position.x < 20.0 and ir.end.y > vpr.size.y - 30.0 and clash.is_empty(),
		"skills icons: the U / I icons sit in the bottom-left corner inside the 480x270 screen, clear of the objective line, HP bar and minimap", str([ir, clash]))
	# tuna: 名望 3 -> trial -> 打坐 on a 蒲团 with real keys -> 08:00 next day -> taught
	await r.frames(160)
	await set_fame(3)
	var sc3 := await master_talk()
	var futon: Dictionary = g.seats.seat("hall_futon_1")
	var spot: Vector2 = await sc.seat_spot(futon)
	await r.tap(KEY_E)
	await r.frames(3)
	var seated: bool = g.seats.sitting == "hall_futon_1"
	var prompt_ok: bool = g.hud.prompt.visible and g.hud.prompt_label.text == "按 E 打坐"
	var total0: float = g.daynight.total_hours
	await r.tap(KEY_E)
	await r.frames(3)
	var asked: bool = story.current_scene == "K-打坐" and dlg.active
	var lines: Array = []
	for i in 40:
		if dlg.choosing:
			break
		lines.append(dlg.full_text)
		await r.tap(KEY_E)
	await r.tap(KEY_1)
	var night: Dictionary = await sc.watch_night(1200)
	await r.frames(10)
	var hours: float = g.daynight.total_hours - total0
	r.check(sc3.has("K-师父-吐纳功-考验") and seated and prompt_ok and asked and "跳过去后，今天没做完的委托会作废" in str(lines),
		"skills teach: 名望 3 -> 吐纳功 trial; sitting on a 正殿 蒲团 shows '按 E 打坐'; E asks first and warns that today's 委托 will be void", str([sc3, seated, prompt_ok, asked, lines]))
	r.check(night["started"] and String(night["label_text"]) == "静坐吐纳……" and night["black_frames"] > 30 and g.daynight.hour == 8.0
		and absf(hours - 22.0) < 0.01 and sk.passed("tuna") and g.seats.sitting == "hall_futon_1",
		"skills teach: 1 = the screen goes dark '静坐吐纳……' and the clock jumps to 08:00 of the next day (10:00 -> +22 h); the trial is passed; he still sits",
		str([night, g.daynight.hour, hours]))
	await r.tap(KEY_DOWN)
	await r.frames(3)
	var sc4 := await master_talk()
	await r.frames(10)
	r.check(sc4.has("K-师父-吐纳功-传授") and sk.has_learned("tuna") and p().stats.max_hp == 120 and sk.hud.learn_shown.has("学会：吐纳功（内功）")
		and sk.fx.qi_flow != null and is_instance_valid(sk.fx.qi_flow),
		"skills teach: 师父 teaches 吐纳功 - max HP 120, '学会：吐纳功（内功）', the faint jade air round the rabbit", str(sc4))
	# snow: 名望 4 with a 银 won before -> taught at once; without it the trial is given and 银 passes it
	await r.frames(160)
	await set_fame(4)
	story.flags.erase("trial_silver")
	story.flags.erase("trial_gold")
	var sc5 := await master_talk()
	var given: bool = sc5.has("K-师父-二段闪-考验") and sk.trial_state("snow_step") == "assigned" and not sk.passed("snow_step")
	await ss._finish_run(40.0)          # the trial by keys (poles in turn), ending at 40 s: 银 or better
	await r.frames(200)
	var got_silver: bool = story.flags.get("trial_silver", false) or story.flags.get("trial_gold", false)
	var sc6 := await master_talk()
	await r.frames(10)
	r.check(given and got_silver and sk.passed("snow_step") and sc6.has("K-师父-二段闪-传授") and sk.has_learned("snow_step")
		and sk.hud.learn_shown.has("学会：踏雪二段闪（身法）"),
		"skills teach: 名望 4 -> 二段闪 trial (梅花桩银); a run at 40 s gives 银 and 师父 teaches it", str([sc5, got_silver, sc6]))


## A 师兄 spar by real keys (E at him -> 切磋) fought by a bot until the result closes.
func senior_spar(kind := "gp") -> bool:
	var c: Combat = g.combat
	var fox: Fighter = story._npc("fox")
	await sc.clock(10.0, 30)
	await ss.stand_near(fox.global_position)
	await r.tap(KEY_E)
	for i in 300:
		if c.spar_state == "choosing":
			break
		if dlg.choosing:
			await r.tap(KEY_1)
		elif dlg.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	if c.spar_state == "choosing":
		await r.tap(KEY_1)
	var cs = load("res://tests/skills_bot.gd").new(r)
	cs._dodged_for = {}
	cs._gp_for = {}
	for i in 60 * 90:
		if c.spar_state != "fighting":
			break
		cs.bot_step(kind)
		await r.physics_frame
	cs._release()
	r.release_all()
	for i in 400:
		if c.spar_state == "none":
			break
		await r.physics_frame
	await r.frames(3)
	return c.last_spar_win


## 夜里 师父 is asleep: the tab and the objective say 师父 06:00 起; the gold arrow has nothing to point at.
func test_night() -> void:
	await game()
	await set_fame(2)
	g.guide.set_track("skill:swallow_spin")
	await sc.clock_settled(22.0)
	var items: Array = sk.board_items()
	var obj: String = g.hud.objective_label.text
	var asleep: bool = g.schedule.absent("crane")
	await sc.open_board()
	var qb: QuestBoard = g.quest_board
	var tab_ok := false
	for i in qb.model.size():
		if String(qb.model[i]["id"]) == "skills":
			qb._set_tab(i)
			tab_ok = String(qb.model[i]["name"]) == "武学"
	var shown := qb.shown_rects().map(func(x): return String(x[0]))
	await sc.close_board()
	r.check(asleep and "师父 06:00 起" in String(items[0]["text"]) and "师父 06:00 起" in obj and tab_ok and str(shown).contains("师父 06:00 起"),
		"skills board: at 22:00 师父 sleeps - the 任务面板 tab 武学 and the objective line say '师父 06:00 起'", str([obj, items[0]]))
	await sc.clock_settled(9.0)
	var tw: Variant = g.guide.track_world()
	var crane: Npc = story._npc("crane")
	r.check(tw is Vector2 and crane != null and (tw as Vector2).distance_to(crane.global_position) < 1.0 and not ("06:00" in g.hud.objective_label.text),
		"skills board: by day the tracked lesson points the gold arrow at 师父 in the 正殿; the line is '去正殿找师父传功：燕回旋'", str([tw, g.hud.objective_label.text]))


# ================================================================== 打坐 = 等到天亮 = T
func test_same() -> void:
	await t3.joined_game(true, 9.0)
	bind()
	g.daynight.running = false
	ss.smp.coins = 40
	ss.smp._refresh_coins()
	await s4.day_with("jade", true)
	await s4.accept_commission("jade")
	await set_fame(3)
	sk.assign("tuna")
	var bad := []
	var runs := {}
	for start in [21.0, 3.0, 13.5]:
		await sc.clock(start)
		var st0: Dictionary = SaveGame.roundtrip(SaveGame.capture(g))
		await sc.restored(st0)
		bind()
		var a := await meditate_run()
		await sc.restored(st0)
		bind()
		var b: Dictionary = {}
		if g.schedule.can_wait():
			b = await sc.by_button()
			var fm = g.get("farm")
			if fm != null and fm.has_method("capture"):
				b["farm"] = str(fm.capture())
			b["max_hp"] = p().stats.max_hp
		await sc.restored(st0)
		bind()
		var rest := fposmod(g.schedule.wait_hour() - g.daynight.hour, 1.0)
		var to: float = g.schedule.hours_to_morning()
		if to < 0.0001:
			to = 24.0
		var c := await t_run(to, rest)
		runs[start] = [a, b, c]
		for k in a:
			if str(a[k]) != str(c.get(k, "-")):
				bad.append("%s %s: 打坐 %s / T %s" % [start, k, a[k], c.get(k, "-")])
			if b.has(k) and str(a[k]) != str(b[k]):
				bad.append("%s %s: 打坐 %s / 等到天亮 %s" % [start, k, a[k], b[k]])
	report["same"] = runs.keys()
	r.check(bad.is_empty(), "skills same: 打坐 (from 21:00, 03:00, 13:30) ends exactly like 等到天亮 and like T hour by hour: clock, coins, stall, upkeep, 委托 void / drawn, 悬赏, toasts, who sleeps%s"
		% (", the farm" if g.get("farm") != null else ""), str(bad.slice(0, 6)))


func observables() -> Dictionary:
	var o: Dictionary = sc.observables()
	var fm = g.get("farm")
	if fm != null and fm.has_method("capture"):
		o["farm"] = str(fm.capture())
	o["max_hp"] = p().stats.max_hp
	return o


## 打坐 with real keys from the current state: sit on a 正殿 蒲团, E, 1, the night.
func meditate_run() -> Dictionary:
	var futon: Dictionary = g.seats.seat("hall_futon_3")
	await sc.seat_spot(futon)
	await r.tap(KEY_E)
	await r.frames(3)
	await r.tap(KEY_E)
	for i in 40:
		if dlg.choosing:
			break
		await r.tap(KEY_E)
	await r.tap(KEY_1)
	await sc.watch_night(2400)
	await r.frames(10)
	return observables()


func t_run(to: float, rest: float) -> Dictionary:
	var n := int(floor(to - rest + 0.0001))
	for i in n:
		await r.tap(KEY_T)
		await r.frames(2)
	if rest > 0.0:
		g.daynight.advance_hours(rest)
	await r.frames(10)
	return observables()


# ================================================================== 门派簿 武学 page
func book_fits() -> Array:
	var book: SectBook = story.sect_book
	var vp := g.get_viewport().get_visible_rect()
	var pr := book.panel.get_global_rect()
	var bad := []
	if not vp.encloses(pr) or book.panel.scale.x < 0.999:
		bad.append("panel %s scale %.2f" % [pr, book.panel.scale.x])
	for l in book.page_labels + book.tab_labels:
		if is_instance_valid(l) and l.is_visible_in_tree() and not pr.grow(1).encloses(l.get_global_rect()):
			bad.append(l.text)
	return bad


func test_book() -> void:
	await game()
	var book: SectBook = story.sect_book
	await r.tap(KEY_B)
	await r.frames(4)
	var first: String = book.page_id()
	await r.tap(KEY_RIGHT)
	await r.frames(4)
	var on_skills := book.page_id() == "skills"
	var rows: Array = sk.book_rows
	var locked: bool = rows.size() == 3 and rows.all(func(x): return x["name"].text == "？？？") \
		and String(rows[0]["detail"].text) == "名望 2 格后，找师父传功"
	var fit0 := book_fits()
	await r.tap(KEY_ESCAPE)
	r.check(first == "sect" and on_skills and locked and fit0.is_empty() and book.page_ids.has("skills"),
		"skills book: B opens the 门派簿 on 门派; → turns to 武学; nothing learned = three grey silhouettes '？？？' with how to learn ('名望 2 格后，找师父传功'); fits the screen",
		str([first, book.page_ids, rows.map(func(x): return x["detail"].text), fit0]))
	sk.learn("swallow_spin", false)
	sk.learn("snow_step", false)
	sk.learn("tuna", false)
	await r.frames(2)
	await r.tap(KEY_B)
	await r.frames(3)
	book.show_page("skills")
	await r.frames(3)
	var names: Array = sk.book_rows.map(func(x): return x["name"].text)
	var st: Array = sk.book_rows.map(func(x): return x["state"].text)
	await r.tap(KEY_E)               # 燕回旋 selected: U -> I
	await r.frames(3)
	var moved: bool = sk.slots["i"] == "swallow_spin" and sk.slots["u"] == ""
	await r.tap(KEY_E)               # I -> U
	await r.frames(3)
	var back: bool = sk.slots["u"] == "swallow_spin"
	var still_open := book.is_open
	await r.tap(KEY_DOWN)
	await r.tap(KEY_DOWN)
	await r.frames(3)
	var sel_tuna := sk.book_sel == 2
	var fit1 := book_fits()
	r.check(names == ["燕回旋", "踏雪二段闪", "吐纳功"] and st == ["装在 U 格", "已生效", "运转中"] and moved and back and still_open and sel_tuna and fit1.is_empty(),
		"skills book: learned = names + '装在 U 格' / '已生效' / '运转中'; E on 燕回旋 moves it U -> I -> U (the book stays open); ↓ selects; fits",
		str([names, st, moved, back, fit1]))
	await r.tap(KEY_ESCAPE)
	# English
	Lang.set_lang("en")
	await r.frames(2)
	await r.tap(KEY_B)
	await r.frames(3)
	book.show_page("skills")
	await r.frames(6)
	var fit2 := book_fits()
	var en_tr: String = Lang.t(sk.book_rows[0]["detail"].text)
	await r.tap(KEY_ESCAPE)
	Lang.set_lang("zh")
	await r.frames(2)
	r.check(fit2.is_empty() and en_tr.begins_with("Spin on the spot"),
		"skills book: in English the 武学 page (long descriptions wrap) stays inside the 480x270 screen, unscaled", str(fit2))


# ================================================================== 任务面板
func test_board() -> void:
	await game()
	await sc.clock(10.0, 30)
	await set_fame(2)
	var qb: QuestBoard = g.quest_board
	await sc.open_board()
	var idx := -1
	for i in qb.model.size():
		if String(qb.model[i]["id"]) == "skills":
			idx = i
	for i in 8:
		if qb.tab == idx:
			break
		await r.tap(KEY_RIGHT)
	var on := qb.tab == idx
	await r.tap(KEY_E)               # 追踪 the first item
	await r.frames(2)
	var tracked: bool = g.guide.track == "skill:swallow_spin"
	var rects: Array = qb.shown_rects()
	var pr: Rect2 = qb.panel.get_global_rect()
	var out := rects.filter(func(x): return not pr.grow(1).encloses(x[1]))
	await sc.close_board()
	await r.frames(3)
	r.check(idx == qb.model.size() - 1 and on and tracked and out.is_empty() and "去正殿找师父传功：燕回旋" in g.hud.objective_label.text,
		"skills board: Q -> the last tab is 武学; E tracks '师父传功：燕回旋' (objective '去正殿找师父传功：燕回旋', gold arrow at 师父); every row inside the panel",
		str([idx, qb.model.size(), tracked, out, g.hud.objective_label.text]))
	sk.learn("swallow_spin", false)
	await r.frames(3)
	r.check(String(sk.board_items()[0]["state"]) == "done" and g.guide.track_done("skill:swallow_spin"),
		"skills board: learned -> '√ 已学会：燕回旋' and the tracking is finished")
	# English: every tab row fits
	Lang.set_lang("en")
	await sc.open_board()
	qb._set_tab(idx)
	await r.frames(3)
	var rects2: Array = qb.shown_rects()
	var pr2: Rect2 = qb.panel.get_global_rect()
	var out2 := rects2.filter(func(x): return not pr2.grow(1).encloses(x[1]))
	await sc.close_board()
	Lang.set_lang("zh")
	r.check(out2.is_empty(), "skills board: in English the 武学 tab's rows stay inside the panel", str(out2))


# ================================================================== saving
func test_save() -> void:
	await game()
	await set_fame(3)
	sk.learn("swallow_spin", false)
	sk.learn("tuna", false)
	sk.assign("snow_step")
	sk.trials["snow_step"]["best"] = 0
	sk.book_activate("swallow_spin")         # into I
	p().hp = 117
	var st0: Dictionary = SaveGame.roundtrip(SaveGame.capture(g))
	var why := SaveGame.validate(st0)
	await sc.restored(st0)
	bind()
	var st1: Dictionary = SaveGame.roundtrip(SaveGame.capture(g))
	r.check(why == "" and str(st0["skills"]) == str(st1["skills"]) and sk.has_learned("tuna") and sk.slots["i"] == "swallow_spin"
		and sk.trial_state("snow_step") == "assigned" and p().stats.max_hp == 120 and p().hp == 117,
		"skills save: learned skills, U / I, trials save and load back equal; max HP 120 and HP 117 (above 100) survive loading", str([st0["skills"], st1["skills"], p().hp]))
	# an old save: no "skills" section
	var old := st0.duplicate(true)
	old.erase("skills")
	old["player"]["hp"] = 100
	var why2 := SaveGame.validate(old)
	await sc.restored(old)
	bind()
	r.check(why2 == "" and sk.learned_ids.is_empty() and sk.slots["u"] == "" and p().stats.max_hp == 100 and not sk.hud.icons_visible(),
		"skills save: an old save without the skills part loads - nothing learned, max HP 100, no U / I icons")
	var broken := st0.duplicate(true)
	broken["skills"] = {"learned": "x"}
	r.check(SaveGame.validate(broken) != "", "skills save: a malformed skills part is refused like any other broken save")


# ================================================================== sounds / qi
func test_audio() -> void:
	var au := Sfx.service()
	var ok: bool = au != null and au.sound_for("skill_spin") == "skill_spin" and au.sound_for("skill_snow_step") == "skill_snow" \
		and au.sound_for("skill_tuna_learned") == "skill_tuna"
	var files := []
	for id in ["skill_spin", "skill_snow", "skill_tuna"]:
		if ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % id):
			files.append(id)
	r.check(ok and files.size() == 3, "skills audio: 3 new sounds (燕回旋 呼——, 二段闪 嚓, 吐纳功 嗡) are files in assets/audio/sfx with their events in data/audio.json", str(files))
	await sandbox()
	sk.learn("swallow_spin", false)
	sk.cooldowns.clear()
	var m0: int = au.sfx_count
	await r.teleport(gp.fox.global_position + Vector2(36, 0))
	var q0 := sk.qi
	await tap_u()
	await r.frames(20)
	var n: int = au.sfx_count - m0
	var played: Array = au.sfx_log.slice(maxi(0, au.sfx_log.size() - n)).map(func(e): return String(e["id"]))
	r.check(sk.qi > q0 and g.combat.hud.root.find_children("*Qi*", "", true, false).is_empty() and sk.hud.root.find_children("*Qi*", "", true, false).is_empty(),
		"skills qi: the 气槽 fills on hits (%d -> %d) but nothing shows it this batch" % [q0, sk.qi])
	r.check(played.has("skill_spin"), "skills audio: U plays the 呼—— (skill_spin)", str(played))


# ================================================================== bots
func _bot_cs() -> Object:
	var cs = load("res://tests/skills_bot.gd").new(r)
	t3.cs = cs
	return cs


func test_bots_hard() -> void:
	await t3.unlocked_game()
	bind()
	sk.learn("swallow_spin", false)
	var res := {}
	var day := 3
	for kind in ["masher", "masher_u", "spin_spam", "gp_u"]:
		var cs = _bot_cs()
		res[kind] = {"wins": 0, "rounds": 0, "dmg": 0}
		var dmg := [0]
		var cb := func(_e, d, _h): dmg[0] += int(d)
		g.combat.player_hit_enemy.connect(cb)
		for i in 10:
			sk.cooldowns.clear()
			var o: Dictionary = await t3.bot_tournament(day, KEY_2, kind, 1000 + i)
			day += 3
			res[kind]["wins"] += int(o["won"])
			res[kind]["rounds"] += int(o["rounds"])
		g.combat.player_hit_enemy.disconnect(cb)
		res[kind]["dmg"] = dmg[0]
		print("SKILL HARD BOT %s %s" % [kind, res[kind]])
	report["bots_hard"] = res
	var mu: Dictionary = res["masher_u"]
	var m: Dictionary = res["masher"]
	# "强": both J bots lose most 困难 tournaments (the cards have super armour - the spin only adds its 15), so the win count
	# alone is 0-2 of 10 for both and pure noise; the measure is the damage dealt to the opponents over the same 10 seeds,
	# with the wins not lower by more than that noise (one tournament). Judgement call - reported to PM.
	var stronger: bool = int(mu["dmg"]) > int(m["dmg"]) and int(mu["wins"]) + 1 >= int(m["wins"])
	r.check(stronger, "skills bots 困难 (10 seeded tournaments each, real keys): the masher using 燕回旋 (U when in reach) is stronger than the plain J masher - damage dealt %d vs %d, wins %d vs %d (the GP bot with U: %d/10)"
		% [mu["dmg"], m["dmg"], mu["wins"], m["wins"], res["gp_u"]["wins"]], str(res))
	r.check(int(res["spin_spam"]["wins"]) * 10 < 30, "skills bots 困难: the U-only spammer (never looks at the enemy) wins %d/10 (< 30 %%)" % int(res["spin_spam"]["wins"]), str(res["spin_spam"]))


func test_bots_tiger() -> void:
	await s4.game()
	bind()
	s4.set_day(2, 9.0)
	sk.learn("swallow_spin", false)
	var res := {}
	for kind in ["masher", "masher_u", "spin_spam", "gp_u"]:
		var cs = _bot_cs()
		res[kind] = {"wins": 0, "dmg": 0}
		var dmg := [0]
		var cb := func(_e, d, _h): dmg[0] += int(d)
		g.combat.player_hit_enemy.connect(cb)
		for i in 10:
			sk.cooldowns.clear()
			var o: String = await s4.fight_with(2, kind, 900 + i, -1.0, 90.0)
			res[kind]["wins"] += int(o == "won")
			s4.b.active = {}
			p().full_heal()
		g.combat.player_hit_enemy.disconnect(cb)
		res[kind]["dmg"] = dmg[0]
		print("SKILL TIGER BOT %s %s" % [kind, res[kind]])
	report["bots_tiger"] = res
	var mu: Dictionary = res["masher_u"]
	var m: Dictionary = res["masher"]
	r.check(int(mu["dmg"]) > int(m["dmg"]) and int(mu["wins"]) + 1 >= int(m["wins"]),
		"skills bots 黑虎 (10 seeded fights each, real keys): the masher using 燕回旋 is stronger than the plain J masher - damage dealt %d vs %d, wins %d vs %d (the GP bot with U: %d/10)"
		% [mu["dmg"], m["dmg"], mu["wins"], m["wins"], res["gp_u"]["wins"]], str(res))
	r.check(int(res["spin_spam"]["wins"]) * 10 < 30, "skills bots 黑虎: the U-only spammer wins %d/10 (< 30 %%)" % int(res["spin_spam"]["wins"]), str(res["spin_spam"]))
