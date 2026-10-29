extends RefCounted
## 试玩反馈 v1 checks (docs/design/试玩反馈-格挡音效-方案-v1.md, part A of the task packet), run by tests/run_tests.gd
## at the end, or alone:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-gp
## Real keys / mouse buttons (K, right button, J, Space, E, Enter, left button), real physics, real AI wherever the player
## does something; state is set directly only for starting points (positions, a calm 师兄, another card on him, a dodge
## that has just ended) - never for the result checked.
##   GP     : K and the right mouse button; caught blow = no damage, 0.6 s stagger (none with super armour), counter
##            12 + 18 = 30 straight to that enemy, gold 反击, blue ring + sparks, 0.1 s hitstop, camera shake; too early
##            = 0.4 s stuck (no moving / dodging, can be hit); 0.3 s cooldown after the stance; invulnerable until the
##            counter ends (困难猴子's second blow, any other enemy, from behind); signals for the sounds
##   chase  : J after a dodge always lands inside 3 tiles (standing, side-stepping, walking away, knocked back)
##   rag    : bright blinking edge + gold sparkles; the gold minimap arrow at the rag, then at the puddle
##   talk   : left click / Space / Enter / E complete and turn the lines; options: hover highlights, click picks,
##            a greyed one ignores the click; right click / K in a conversation never guard

var r
var cs                      # tests/combat_suite.gd bound to this suite's game
var g: Node
var player: Player
var combat: Combat
var fox: Fighter
var wolf: Fighter
var boar: Fighter
var events := []            # every combat / dialogue signal seen: [name, args...]


func _init(runner) -> void:
	r = runner


func run() -> void:
	r.paused = false
	r.release_all()
	SaveGame.erase()           # (after the other suites: start from no save, like the runner does)
	Lang.set_lang("zh")
	await sandbox_game()
	test_input_map()
	await test_gp_success()
	await test_gp_early_and_cooldown()
	await test_gp_invulnerable()
	await test_gp_super_armor()
	await test_gp_mouse()
	await test_no_old_counter()
	await test_signals()
	await test_chase_always_hits()
	await test_spar_choice_mouse()
	await story_game()
	await test_dialogue_mouse()
	await test_rag()
	await _free_game()


# ================================================================== helpers
func _free_game() -> void:
	cs = null
	if g != null and is_instance_valid(g):
		if g.is_inside_tree():
			g.get_parent().remove_child(g)
		g.queue_free()
	g = null
	await r.process_frame


func _bind(m: Node) -> void:
	g = m
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0
	player = m.player
	combat = m.combat
	events = []
	for sig in ["gp_started", "gp_success", "gp_whiffed", "player_hit_enemy", "player_hurt", "dodge_started", "enemy_alert",
			"enemy_down", "player_down", "choice_moved"]:
		combat.connect(sig, _on_event.bind(sig))


func _on_event(a = null, b = null, c = null, d = null) -> void:
	# the bound signal name comes last
	var args := [a, b, c, d].filter(func(x): return x != null)
	var name: String = args.pop_back()
	events.append([name] + args)


func count(name: String) -> int:
	return events.filter(func(e): return e[0] == name).size()


## A fresh game in the old suites' sandbox (no story: 师兄 invites directly, bandits on the road, AI switched off).
func sandbox_game() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.root.size = Vector2i(1440, 810)       # the game's real view (480 x 270), as the runner starts it
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	await r.frames(3)
	m.story.enter_sandbox()
	await r.frames(2)
	m.daynight.running = false
	m.combat.bandits_enabled = false
	_bind(m)
	cs = load("res://tests/combat_suite.gd").new(r)
	fox = cs.fox
	wolf = cs.wolf
	boar = cs.boar


## A fresh game from the very start (the story: the opening in the dorm).
func story_game() -> void:
	await _free_game()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	_bind(m)
	m.daynight.running = false
	await r.frames(3)


func reset() -> void:
	await cs.reset_all()
	for f in combat.fighters:
		f.stats = load("res://cards/%s.tres" % f.card)
		f.reset_home(true)
	combat.bandits_enabled = false
	player.gp_cooldown_left = 0.0
	player.since_dodge_end = 99.0
	events = []
	await r.frames(2)


## A spar with 师兄 wearing `card` (another fighter's numbers), the player `off` from him, facing him.
func spar_with(card: String, off := Vector2(36, 0)) -> void:
	await reset()
	await cs.start_spar_keys()
	# (a private copy of the card, without his 10 % side-step so that the checks are exact)
	var st: EnemyStats = load("res://cards/%s.tres" % (card if card != "" else "shixiong")).duplicate()
	st.sidestep_chance = 0.0
	fox.stats = st
	fox.hp = st.max_hp
	await r.teleport(fox.global_position + off)
	fox.angle = (player.global_position - fox.global_position).angle()
	fox.next_attack = 9999.0
	events = []
	await r.frames(2)


## Waits until `f`'s blow is `lead` s away (its wind-up nearly done; charges: closing in included).
func blow_in(f: Fighter, lead: float, limit := 600) -> bool:
	f.next_attack = minf(f.next_attack, 0.0)
	for i in limit:
		if cs.blow_coming(f) and cs.blow_eta(f) <= lead:
			return true
		await r.physics_frame
	return false


## Key down, held 2 physics frames (the event is taken the frame after it is sent), up.
func press(code: Key) -> void:
	r.key(code, true)
	await r.frames(2)
	r.key(code, false)


func right_click(pressed_only := false) -> void:
	for pressed in ([true] if pressed_only else [true, false]):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = Vector2(720, 405)
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		await r.frames(2)


## Window position of the centre of a control (through the canvas layer and the window stretch).
func screen_pos(c: Control) -> Vector2:
	return r.root.get_final_transform() * c.get_global_rect().get_center()


func mouse_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await r.process_frame
	await r.process_frame


func left_click(p: Vector2) -> void:
	await mouse_move(p)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await r.process_frame
		await r.process_frame


## Frames (physics, not frozen by a hitstop) `f` stays in its stagger from now on.
func stagger_seconds(f: Fighter, limit := 120) -> float:
	var n := 0
	for i in limit:
		if f.state != "stagger":
			break
		if not combat.frozen:
			n += 1
		await r.physics_frame
	return n / 60.0


# ================================================================== the input
func test_input_map() -> void:
	var k := false
	var right := false
	for ev in InputMap.action_get_events("gp"):
		if ev is InputEventKey and (ev.physical_keycode == KEY_K or ev.keycode == KEY_K):
			k = true
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT:
			right = true
	var att_left := InputMap.action_get_events("attack").any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
	r.check(k and right and att_left, "gp AC1: input 'gp' = K and the right mouse button (J / left button stay attack)")


# ================================================================== GP success
func test_gp_success() -> void:
	await spar_with("")
	var hp0 := player.hp
	var fh0 := fox.hp
	var on_hit := {}
	var s0 := player.gp_successes
	var cb := func(_f):
		on_hit["hitstop"] = combat.hitstop_left
		on_hit["hp"] = player.hp
		on_hit["shake"] = combat._shake_left
	combat.gp_success.connect(cb)
	var rings0: int = combat.fx.spawned.get("gp_ring", 0)
	var sparks0: int = combat.fx.spawned.get("gp_spark", 0)
	var ok_wind := await blow_in(fox, 0.14)
	await press(KEY_K)
	var stance: bool = player.in_gp_stance()
	var g0 := 0
	while player.gp_successes == s0 and g0 < 40:
		await r.physics_frame
		g0 += 1
	combat.gp_success.disconnect(cb)
	var caught := player.gp_successes == s0 + 1
	var staggered := fox.state == "stagger"
	var stag := await stagger_seconds(fox)
	# the counter: both blows land on him (12 + 18)
	var g1 := 0
	while player.gp_countering and g1 < 120:
		await r.physics_frame
		g1 += 1
	await r.frames(2)
	var dmg := fh0 - fox.hp
	var gold := combat.hud.number_texts().filter(func(s): return "反击" in s)
	r.check(ok_wind and stance and caught and player.hp == hp0 and on_hit.get("hp", -1) == hp0,
		"gp AC1: K just before 师兄's blow -> guard stance, the blow is caught (GP): no damage", "hp %d -> %d, %s" % [hp0, player.hp, on_hit])
	r.check(staggered and absf(stag - 0.6) <= 2.5 / 60.0 and fox.gp_staggers >= 1,
		"gp AC1: the enemy (no super armour) is knocked back and staggered 0.6 s (%.2f s measured, the counter's blows do not cut it short)" % stag)
	r.check(dmg == 30 and player.gp_counter_split() == [12, 18] and gold.size() >= 1 and not player.gp_countering,
		"gp AC1: the automatic counter (in place) deals 12 + 18 = 30 to him, gold '反击'", "dmg %d %s" % [dmg, gold])
	r.check(absf(float(on_hit.get("hitstop", 0.0)) - 0.1) < 0.001 and float(on_hit.get("shake", 0.0)) > 0.0
		and combat.fx.spawned.get("gp_ring", 0) == rings0 + 1 and combat.fx.spawned.get("gp_spark", 0) == sparks0 + 1,
		"gp AC1: GP feedback - blue ring + blue sparks (drawn in code), 0.1 s hitstop, a small camera shake", str(on_hit))
	await r.frames(20)
	r.check(g.camera.offset == Vector2.ZERO, "gp AC1: the camera shake is over after a moment (offset back to 0)")
	await reset()


# ================================================================== too early + cooldown
func test_gp_early_and_cooldown() -> void:
	await spar_with("")
	var hp0 := player.hp
	var wh0 := player.gp_whiffs
	var su0 := player.gp_successes
	# K 0.5 s before the blow: the stance (0.25 s) ends 0.25 s before it -> stuck 0.4 s, the blow lands inside that
	await blow_in(fox, 0.5)
	await press(KEY_K)
	var w := 0
	while player.in_gp_stance() and w < 40:
		await r.physics_frame
		w += 1
	var rec := player.gp_recover_left
	var cdw := player.gp_cooldown_left
	var whiffed := player.gp_whiffs == wh0 + 1 and absf(rec - 0.4) < 0.02 and absf(cdw - 0.3) < 0.02
	var p0 := player.global_position
	r.hold_dir(Vector2.LEFT)
	await press(KEY_SPACE)
	await r.frames(4)
	var stuck: bool = player.global_position.distance_to(p0) < 0.5 and not player.is_dashing()
	r.release_all()
	var hit := false
	for i in 30:
		if player.hp < hp0:
			hit = true
			break
		await r.physics_frame
	r.check(whiffed and stuck and hit and player.gp_successes == su0,
		"gp AC1: K too early - the stance ends without a blow: 0.4 s stuck (cannot walk or dodge), and his blow hits",
		"whiff %s (recover %.2f, cooldown %.2f) stuck %s hit %s hp %d" % [whiffed, rec, cdw, stuck, hit, player.hp])
	await reset()
	# cooldown: 0.3 s from the end of the stance K does nothing; after that it works (even while still stuck)
	await spar_with("", Vector2(80, 0))
	await press(KEY_K)
	var w2 := 0
	while player.in_gp_stance() and w2 < 40:                      # the stance runs out (nobody attacks)
		await r.physics_frame
		w2 += 1
	var n0 := player.gp_presses
	var cd := player.gp_cooldown_left
	await r.frames(8)                                              # ~0.13 s after the end (+2 frames in press)
	await press(KEY_K)
	var blocked := player.gp_presses == n0 and not player.in_gp_stance()
	await r.frames(10)                                             # ~0.33 s after the end
	var still_stuck := player.gp_recover_left > 0.0
	await press(KEY_K)
	var again := player.gp_presses == n0 + 1 and player.in_gp_stance()
	r.check(cd > 0.28 and blocked and still_stuck and again,
		"gp AC1: cooldown - K within 0.3 s after the stance ends does nothing; after 0.3 s it guards again (the stuck time does not block K)",
		"cd %.2f blocked %s stuck %s again %s" % [cd, blocked, still_stuck, again])
	# K spam: at most one stance per (stance + cooldown) = 0.55 s
	await reset()
	await spar_with("", Vector2(80, 0))
	var c0 := player.gp_presses
	var f0 := Engine.get_physics_frames()
	for i in 60:
		await press(KEY_K)
	var secs := (Engine.get_physics_frames() - f0) / 60.0
	var most := int(floor(secs / (player.stats.gp_stance + player.stats.gp_cooldown))) + 1
	r.check(player.gp_presses - c0 <= most and player.gp_presses - c0 >= most - 1,
		"gp AC1: mashing K for %.1f s gives only %d stances (one per stance 0.25 + cooldown 0.3 s: at most %d)" % [secs, player.gp_presses - c0, most])
	await reset()


# ================================================================== invulnerable until the counter ends
func test_gp_invulnerable() -> void:
	# 困难猴子: two blows per attack (0.5 s apart) - the second comes during the counter and does nothing
	await spar_with("monkey_hard", Vector2(34, 0))
	var hp0 := player.hp
	var s0 := fox.strikes
	var su0 := player.gp_successes
	var hl0 := fox.hits_landed
	await blow_in(fox, 0.1)
	await press(KEY_K)
	var w := 0
	while fox.strikes < s0 + 2 and w < 120:
		await r.physics_frame
		w += 1
	var second_during := player.gp_countering
	while player.gp_countering and w < 240:
		await r.physics_frame
		w += 1
	fox.next_attack = 9999.0
	r.check(player.gp_successes == su0 + 1 and fox.strikes >= s0 + 2 and second_during and player.hp == hp0 and fox.hits_landed == hl0,
		"gp AC1: 困难猴子's second blow comes during the counter and does not hurt him (invulnerable until the counter ends)",
		"strikes %d second during counter %s hp %d -> %d" % [fox.strikes - s0, second_during, hp0, player.hp])
	await reset()
	# from behind / another enemy: a blow landing in the stance from the far side is caught too; during the counter a
	# second enemy's blow does nothing
	await spar_with("", Vector2(36, 0))
	wolf.global_position = player.global_position + Vector2(30, 0)     # behind him (师兄 is on his left)
	wolf.engage(9999.0)
	wolf.next_attack = 9999.0
	await r.frames(2)
	hp0 = player.hp
	su0 = player.gp_successes
	await press(KEY_K)
	var facing0 := player.facing
	combat.enemy_strike(wolf, wolf.global_position + (player.global_position - wolf.global_position).normalized() * 20.0, 22.0)
	var caught_back := player.gp_successes == su0 + 1 and player.hp == hp0
	await r.frames(10)
	combat.enemy_strike(wolf, player.global_position, 22.0)            # wolf again, mid-counter
	combat.enemy_strike(fox, player.global_position, 22.0)             # and 师兄
	var none := player.hp == hp0 and player.gp_countering
	var w2 := 0
	while player.gp_countering and w2 < 120:
		await r.physics_frame
		w2 += 1
	r.check(caught_back and none, "gp AC1: any direction - a blow from behind (facing %s) is caught; during the counter blows from any enemy do nothing" % facing0,
		"back %s mid-counter %s hp %d" % [caught_back, none, player.hp])
	wolf.reset_home(true)
	await reset()


# ================================================================== super armour: no stagger, the damage still lands
func test_gp_super_armor() -> void:
	var out := {}
	for c in [["yak", Vector2(90, 0)], ["tiger", Vector2(40, 0)], ["monkey_hard", Vector2(34, 0)], ["shixiong", Vector2(36, 0)], ["wolf", Vector2(36, 0)]]:
		await spar_with(c[0], c[1])
		var fh0 := fox.hp
		var hp0 := player.hp
		var su0 := player.gp_successes
		events = []
		var ok := await blow_in(fox, 0.14)
		await press(KEY_K)
		var w := 0
		while player.gp_successes == su0 and w < 60:
			await r.physics_frame
			w += 1
		var st := fox.state
		while player.gp_countering and w < 240:
			await r.physics_frame
			w += 1
		fox.next_attack = 9999.0
		out[c[0]] = {"order": events.filter(func(e): return e[0] in ["gp_started", "gp_success", "gp_whiffed", "player_hurt"]).map(func(e): return e[0]),
			"caught": ok and player.gp_successes == su0 + 1, "stagger": st == "stagger", "dmg": fh0 - fox.hp, "hurt": hp0 - player.hp,
			"armour": fox.stats.super_armor}
	var good := true
	for k in out:
		var o: Dictionary = out[k]
		good = good and o["caught"] and o["dmg"] == 30 and o["hurt"] == 0 and o["stagger"] == (not o["armour"])
	r.check(good and out["yak"]["armour"] and out["tiger"]["armour"] and not out["shixiong"]["armour"],
		"gp AC1: super armour (牦牛 charge, 黑虎, 困难猴子) - caught, not staggered, the 30 lands; no armour (师兄, 狼) - staggered", str(out))
	await reset()


# ================================================================== the right mouse button
func test_gp_mouse() -> void:
	await spar_with("")
	var pr0 := player.gp_presses
	var su0 := player.gp_successes
	await blow_in(fox, 0.14)
	await right_click()
	var w := 0
	while player.gp_successes == su0 and w < 40:
		await r.physics_frame
		w += 1
	r.check(player.gp_presses == pr0 + 1 and player.gp_successes == su0 + 1, "gp AC1: the right mouse button guards too (a blow caught)")
	var w2 := 0
	while player.gp_countering and w2 < 120:
		await r.physics_frame
		w2 += 1
	await reset()


# ================================================================== the old 看破反击 is gone
func test_no_old_counter() -> void:
	await spar_with("")
	await cs._fox_windup_until(0.15)
	r.hold_dir(Vector2.DOWN)
	await r.tap(KEY_SPACE)
	r.release_all()
	await r.frames(50)                     # past the 0.6 s chase window: an ordinary attack in place
	fox.next_attack = 9999.0
	var ok_dodge := player.dodge_successes >= 1
	await r.teleport(fox.global_position + Vector2(30, 0))
	var fh := fox.hp
	await r.tap(KEY_J)
	await r.frames(14)
	var d1 := fh - fox.hp
	r.check(ok_dodge and d1 == 8 and not ("counter_window" in player.stats) and not ("counter_left" in player),
		"gp AC1: 看破反击 removed - after a dodge success J is an ordinary 8, the counter window is gone from the card and the player", "dmg %d" % d1)
	await reset()


# ================================================================== signals for the sounds (developer B)
func test_signals() -> void:
	await spar_with("")
	var su0 := player.gp_successes
	await blow_in(fox, 0.14)
	await press(KEY_K)
	var w := 0
	while (player.gp_successes == su0 or player.gp_countering) and w < 160:
		await r.physics_frame
		w += 1
	# a dodge, a plain hit, a too-early K that gets hit
	player.dash_cooldown_left = 0.0
	r.hold_dir(Vector2.UP)
	await r.tap(KEY_SPACE)
	r.release_all()
	await r.frames(30)
	await r.teleport(fox.global_position + Vector2(30, 0))
	await r.tap(KEY_J)
	await r.frames(20)
	await blow_in(fox, 0.5)
	await press(KEY_K)
	for i in 60:
		if count("player_hurt") > 0:
			break
		await r.physics_frame
	fox.next_attack = 9999.0
	var ev := {}
	for e in events:
		ev[e[0]] = ev.get(e[0], 0) + 1
	var hit: Array = events.filter(func(e): return e[0] == "player_hit_enemy")
	var heavy := hit.filter(func(e): return e[3] == true).size()
	var gp_arg: Array = events.filter(func(e): return e[0] == "gp_success")
	r.check(ev.get("gp_started", 0) == 2 and ev.get("gp_success", 0) == 1 and gp_arg[0][1] == fox and ev.get("gp_whiffed", 0) == 1
		and ev.get("enemy_alert", 0) >= 2 and ev.get("dodge_started", 0) == 1 and heavy >= 2 and hit.size() >= 3
		and ev.get("player_hurt", 0) == 1,
		"gp signals: gp_started, gp_success(enemy), gp_whiffed, player_hit_enemy(enemy, dmg, heavy), player_hurt, dodge_started, enemy_alert",
		str(ev))
	await reset()
	# enemy_down / player_down: a bandit knocked out, the player knocked out
	combat.bandits_enabled = true
	wolf.reset_home(true)
	wolf.engage(9999.0)
	wolf.hp = 1
	await r.teleport(r.find_free_near(wolf.global_position + Vector2(-30, 0)))
	wolf.next_attack = 9999.0
	await r.tap(KEY_J)
	await r.frames(20)
	var down_ok := events.any(func(e): return e[0] == "enemy_down" and e[1] == wolf)
	player.hp = 1
	wolf.reset_home(true)
	boar.reset_home(true)
	boar.engage(0.0)
	var t := 0
	while count("player_down") == 0 and t < 600:
		await r.physics_frame
		t += 1
	r.check(down_ok and count("player_down") == 1, "gp signals: enemy_down(enemy) when a bandit goes down, player_down when he is knocked out")
	await r.frames(int(combat.rules.death_seconds * 60) + 10)
	combat.bandits_cleared = false
	await reset()


# ================================================================== 闪身追击: inside 3 tiles it always lands
func test_chase_always_hits() -> void:
	await reset()
	await cs.start_spar_keys()
	cs.calm_fox()
	var fp: Vector2 = fox.global_position
	var a := combat.arena_rect.grow(-14)
	var cases := 0
	var hits := 0
	var bad := []
	var moves := ["still", "sidestep", "away", "knocked", "towards"]
	for dist in [40.0, 56.0, 72.0, 88.0, 95.0]:
		for ang in [0.0, 1.2, 2.4, 3.6, 4.8]:
			var mv: String = moves[(cases) % moves.size()]
			fox.global_position = fp
			fox.state = "chase"
			fox.velocity = Vector2.ZERO
			var start: Vector2 = fp + Vector2.from_angle(ang) * dist
			if not a.has_point(start) or not r.is_free(start):
				continue
			await r.teleport(start)
			player.since_dodge_end = 0.05      # a dodge has just ended here
			fox.hp = fox.stats.max_hp           # (the spar would end at 20 %)
			var h := fox.hp
			await r.tap(KEY_J)
			# the target moves while the rabbit dashes / winds up
			var away := (fox.global_position - player.global_position).normalized()
			match mv:
				"sidestep":
					fox.velocity = away.orthogonal() * (fox.stats.sidestep_distance / 0.3)
					fox.state = "sidestep"
					fox.t = 0.0
				"away":
					fox.velocity = away * 140.0
					fox.state = "sidestep"
					fox.t = -0.2
				"knocked":
					fox.knock_vel = away * 120.0
					fox.knock_left = 0.12
					fox.state = "stagger"
					fox.t = 0.0
				"towards":
					fox.velocity = -away * 100.0
					fox.state = "sidestep"
					fox.t = 0.0
			var w := 0
			while fox.hp == h and w < 50:
				await r.physics_frame
				w += 1
			cases += 1
			if fox.hp < h and player.last_attack_chased:
				hits += 1
			else:
				bad.append("%s %.0f px @%.1f (chased %s blocked %s now %.0f px, end %s)" % [mv, dist, ang, player.last_attack_chased,
					player.chase_blocked, player.global_position.distance_to(fox.global_position), player.chase_end.round()])
			var w2 := 0
			while (player.attack_stage > 0 or player.is_chasing()) and w2 < 60:
				await r.physics_frame
				w2 += 1
			fox.state = "chase"
			fox.velocity = Vector2.ZERO
			await r.frames(4)
	r.check(cases >= 20 and hits == cases, "gp AC1 chase: J after a dodge with 师兄 inside 3 tiles (96 px) always lands - %d/%d (standing, side-stepping, walking away / towards, knocked back)" % [hits, cases],
		str(bad))
	await reset()


# ================================================================== the spar invitation by mouse
func test_spar_choice_mouse() -> void:
	await reset()
	await r.teleport(cs.spot_near(fox))
	await r.tap(KEY_E)
	await r.frames(2)
	var hud: CombatHud = combat.hud
	var shown := hud.choice.visible and combat.spar_state == "choosing"
	var moved := count("choice_moved")
	await mouse_move(screen_pos(hud.choice_opts[1]))
	var hover := hud.choice_index == 1 and hud.choice_opts[1].text.begins_with("▶") and count("choice_moved") == moved + 1
	var a0 := player.attacks_started
	await left_click(Vector2(40, 40))                         # not on an option: nothing (and no swing)
	var nothing: bool = combat.spar_state == "choosing" and player.attacks_started == a0
	await left_click(screen_pos(hud.choice_opts[0]))
	await r.frames(3)
	var started: bool = combat.spar_state == "fighting" and player.attacks_started == a0
	r.check(shown and hover and nothing and started,
		"gp AC3: the spar invitation by mouse - hovering an option selects it, a click elsewhere does nothing, a click on '切磋' starts the spar (never a swing)",
		"%s %s %s %s" % [shown, hover, nothing, started])
	await reset()


# ================================================================== dialogue by mouse
func test_dialogue_mouse() -> void:
	var dlg: Dialogue = g.story.dialogue
	# the opening conversation: left clicks only (complete the line, then the next one)
	var n0 := dlg.lines_shown
	var clicks := 0
	var turned := 0
	for i in 400:
		if not g.story.busy:
			break
		if dlg.active and dlg.choosing:
			await left_click(screen_pos(dlg.choice_labels[dlg.choice_index]))
			await r.frames(6)
		elif dlg.active and dlg._guard > 0.0:
			await r.frames(1)
		elif dlg.active:
			var before := dlg.lines_shown
			var page0 := dlg.page
			var typing := dlg.is_typing()
			await left_click(Vector2(720, 300))
			clicks += 1
			if dlg.lines_shown > before or dlg.page != page0 or (typing and not dlg.is_typing()) or not dlg.active:
				turned += 1
			await r.frames(6)
		else:
			await r.frames(2)
	var swings := player.attacks_started
	r.check(not g.story.busy and dlg.lines_shown > n0 and turned == clicks and swings == 0 and player.gp_presses == 0,
		"gp AC3: the opening conversation is read with the left mouse button alone (complete -> next line), never a swing",
		"lines %d clicks %d turned %d" % [dlg.lines_shown - n0, clicks, turned])
	await r.frames(10)
	# Space / Enter / E: each completes a typing line and turns a complete one
	var keys_ok := {}
	for code in [KEY_SPACE, KEY_ENTER, KEY_E]:
		var done := [false]
		_say_async(dlg, {"kind": "旁白", "text": "测试：一句很长的话，用来看打字的时候按键能不能一下显示完整。"}, done)
		await r.frames(6)
		var typing0 := dlg.is_typing()
		await r.tap(code)
		var completed := not dlg.is_typing() and dlg.active
		await r.frames(8)
		await r.tap(code)
		await r.frames(2)
		keys_ok[code] = typing0 and completed and done[0]
	r.check(keys_ok.values().all(func(x): return x), "gp AC3: Space, Enter and E each complete a typing line and then turn it", str(keys_ok))
	# options: hover highlights, a click picks, a greyed one ignores the click, a click elsewhere does nothing
	var res := [false]
	_say_async(dlg, {"kind": "旁白", "text": "测试：选一个"}, res, ["切磋", "再想想", "算了"], [false, true, false])
	await r.frames(6)
	await r.tap(KEY_E)                       # complete -> the options show
	await r.frames(10)
	var moved := []
	dlg.choice_moved.connect(func(i): moved.append(i))
	await mouse_move(screen_pos(dlg.choice_labels[2]))
	var hover2 := dlg.choice_index == 2 and dlg.choice_labels[2].text.begins_with("▶")
	await mouse_move(screen_pos(dlg.choice_labels[1]))      # greyed: never highlighted
	var grey_hover := dlg.choice_index == 2
	await left_click(screen_pos(dlg.choice_labels[1]))      # greyed: the click does nothing
	var grey_click: bool = dlg.choosing and not res[0]
	await left_click(Vector2(40, 40))                        # outside the options: nothing
	var outside: bool = dlg.choosing and not res[0]
	await left_click(screen_pos(dlg.choice_labels[0]))
	await r.frames(2)
	var picked: bool = res[0] and dlg.last_choice == 0
	r.check(hover2 and grey_hover and grey_click and outside and picked and moved.has(2),
		"gp AC3: options - the mouse over one highlights it, a click picks it; a greyed one is never highlighted and ignores clicks; a click elsewhere does nothing",
		"%s %s %s %s %s moved %s" % [hover2, grey_hover, grey_click, outside, picked, moved])
	# right click / K during a conversation never guards (and does not wait to guard after it)
	var done2 := [false]
	_say_async(dlg, {"kind": "旁白", "text": "测试：右键"}, done2)
	await r.frames(6)
	await right_click()
	await press(KEY_K)
	await r.frames(3)
	await r.tap(KEY_E)
	await r.tap(KEY_E)
	await r.frames(10)
	r.check(done2[0] and player.gp_presses == 0 and not player.in_gp_stance(), "gp AC3: right click and K during a conversation never start a guard (not even after it)")


func _say_async(dlg: Dialogue, e: Dictionary, flag: Array, opts: Array = [], disabled: Array = []) -> void:
	g.story.busy = true
	g.combat.story_hold = true
	await dlg.say(e, opts, disabled)
	dlg.close()
	g.combat.story_hold = false
	g.story.busy = false
	flag[0] = true


# ================================================================== the rag
func test_rag() -> void:
	# (the opening was read by test_dialogue_mouse: 目标：擦干地上的水)
	var it: Interiors = g.interiors
	var mm: Minimap = g.hud.minimap
	var story: Story = g.story
	await r.frames(5)
	var glow := it.rag_glow
	var has_glow: bool = glow != null and glow.is_inside_tree() and glow.edge.size() >= 8 and it.rag_sprite.visible
	var lo := 1.0
	var hi := 0.0
	for i in 80:                     # over more than one 1.2 s pulse
		if glow:
			lo = minf(lo, glow.pulse())
			hi = maxf(hi, glow.pulse())
		await r.physics_frame
	var p0 := lo
	var p1 := hi
	var sp: Array = glow.spark(0) if glow else [Vector2.ZERO, 0.0]
	var rag := story._thing_pos(_inter(story, "rag"))
	var puddle := story._thing_pos(_inter(story, "puddle"))
	var arrow_rag: bool = mm.track_active and mm.track_world.distance_to(rag) < 1.0 and mm.star_target_world.distance_to(rag) < 1.0
	r.check(has_glow and p1 - p0 > 0.8 and (sp[0] as Vector2).y < 0.0 and String(story.main.objectives.current().get("id", "")) == "wipe_floor",
		"gp AC2: the rag has a blinking bright edge (%d px) and gold sparkles rising above it" % (glow.edge.size() if glow else 0), "pulse %.2f -> %.2f" % [p0, p1])
	r.check(arrow_rag, "gp AC2: 擦干地上的水 without the rag - the gold minimap arrow (and the star) point at the rag", "%s %s" % [mm.track_world, rag])
	# take it (real walk + E)
	var nav = load("res://tests/nav.gd").new(r, g)
	var res: String = await nav.walk_to(rag + Vector2(0, 4))
	await r.frames(2)
	await r.tap(KEY_E)
	for i in 200:
		if not story.busy:
			break
		if story.dialogue.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
	await r.frames(4)
	var arrow_puddle: bool = mm.track_active and mm.track_world.distance_to(puddle) < 1.0
	r.check(res == "arrived" and story.flags.get("has_rag", false) and not it.rag_sprite.visible and not glow.is_visible_in_tree() and arrow_puddle,
		"gp AC2: once the rag is taken it (and its glow) is gone and the gold arrow points at the puddle", "%s %s" % [res, mm.track_world])


func _inter(story: Story, id: String) -> Dictionary:
	for x in story.data["interactables"]:
		if x["id"] == id:
			return x
	return {}
