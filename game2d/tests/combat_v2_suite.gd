extends RefCounted
## Combat v1.2 checks (战斗调整 v2), run by tests/run_tests.gd after tests/combat_suite.gd. Real key / mouse events,
## real physics, real AI: 闪身追击 (window, range, counter, walls, arena, swap), Esc pause (state frozen and restored,
## page content and fit), name plates, damage numbers vs result panel / banner, the web focus click.

var r                     # the runner (SceneTree with check(), frames(), key(), tap(), teleport(), hold_dir() ...)
var cs                    # the v1 combat suite (reset_all(), start_spar_keys(), calm_fox(), bot_step() ...)
var main: Node
var player: Player
var combat: Combat
var fox: Fighter
var wolf: Fighter
var boar: Fighter


func _init(runner, combat_suite) -> void:
	r = runner
	cs = combat_suite
	main = r.main
	player = r.player
	combat = main.combat
	fox = cs.fox
	wolf = cs.wolf
	boar = cs.boar


func run() -> void:
	await reset_v2()
	await test_chase_basic()
	await test_chase_window_and_range()
	await test_chase_no_counter()
	await test_chase_after_swap()
	await test_chase_never_through_walls()
	await test_chase_arena()
	await test_pause_freezes_and_restores()
	await test_pause_page()
	await test_hint_mentions_esc()
	await test_plates_do_not_cover_bodies()
	await test_numbers_vs_result_and_banner()
	await test_focus_click()
	await test_bandit_masher_report()
	await reset_v2()


# ================================================================== helpers
## Like the v1 reset, plus: bandits back (even if driven off earlier), their AI off, nothing paused.
func reset_v2() -> void:
	if main.pause_menu.is_open:
		main.pause_menu.close()
	r.paused = false
	await cs.reset_all()
	combat.bandits_enabled = false
	combat.bandits_cleared = false
	for b in combat.bandits:
		b.stats = load("res://cards/%s.tres" % b.card)
		b.reset_home(true)
	fox.stats = load("res://cards/shixiong.tres")
	fox.reset_home(true)
	player.since_dodge_end = 99.0
	await r.frames(2)


## A bandit that stands still and never attacks (private copy of its card), engaged at `p`.
func pin(b: Fighter, p: Vector2) -> void:
	var st: EnemyStats = b.stats.duplicate()
	st.move_speed = 0.0
	st.interval_min = 9999.0
	st.interval_max = 9999.0
	st.turn_time = 99.0
	st.aggro_range = 0.0
	st.leash_range = 0.0
	b.stats = st
	b.global_position = p
	b.engage(9999.0)
	b.next_attack = 9999.0


## Real dodge: hold `d`, tap Space, wait until the dodge is over; returns where it ended.
func dodge(d: Vector2) -> Vector2:
	player.dash_cooldown_left = 0.0
	r.hold_dir(d)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	r.release_all()
	var g := 0
	while player.is_dashing() and g < 30:
		await r.physics_frame
		g += 1
	return player.global_position


## Waits until the current attack (and chase) is over.
func attack_done(limit := 90) -> void:
	var g := 0
	while (player.attack_stage > 0 or player.is_chasing()) and g < limit:
		await r.physics_frame
		g += 1


func spar_calm() -> void:
	await cs.start_spar_keys()
	cs.calm_fox()


func ghosts_max(frames_n: int) -> int:
	var m := 0
	for i in frames_n:
		await r.physics_frame
		m = maxi(m, r.get_nodes_in_group("afterimage").size())
	return m


# ================================================================== 闪身追击
func test_chase_basic() -> void:
	await reset_v2()
	await spar_calm()
	var fp := fox.global_position
	# start 86 px above a point 70 px left of 师兄; dodge down -> lands 70 px from him (inside 96, outside the 66 px reach)
	await r.teleport(fp + Vector2(-70, -86))
	var end := await dodge(Vector2.DOWN)
	var d0 := end.distance_to(fp)
	var hp0 := fox.hp
	var c0 := player.chases_started
	await r.frames(4)            # 0.07 s after the dodge ended
	r.key(KEY_J, true)
	var ghosts := await ghosts_max(3)
	r.key(KEY_J, false)
	var g := 0
	while player.is_chasing() and g < 30:
		await r.physics_frame
		ghosts = maxi(ghosts, r.get_nodes_in_group("afterimage").size())
		g += 1
	var arrive := player.global_position.distance_to(fox.global_position)
	await r.frames(14)
	var dmg := hp0 - fox.hp
	r.check(player.chases_started == c0 + 1 and player.last_attack_chased and arrive <= player.stats.hit_offset + 1.5 and dmg == 8
		and ghosts >= 2 and r.is_free(player.global_position),
		"AC4 chase: J 0.07 s after a dodge dashes to 师兄 (%.0f px away) and hits him (attack 1, 8)" % d0,
		"chases %d, arrived at %.1f px, dmg %d, afterimages %d, time %d frames" % [player.chases_started - c0, arrive, dmg, ghosts, g])
	await attack_done()
	# the chase dash is as fast as the dodge (540 px/s): ~38 px take ~4-5 frames
	r.check(g <= 8, "AC4 chase: the dash runs at dodge speed (%d frames for %.0f px)" % [g, d0 - player.stats.hit_offset])
	# combo continues normally after a chase
	await r.teleport(fox.global_position + Vector2(-60, -86))
	await dodge(Vector2.DOWN)
	await r.tap(KEY_J)
	await r.frames(14)
	var hp1 := fox.hp
	await r.tap(KEY_J)
	await r.frames(20)
	r.check(player.last_attack_chased and hp1 - fox.hp == 12, "AC4 chase: attack 2 follows the chase hit as usual (12)", "%d" % (hp1 - fox.hp))
	await attack_done()
	await reset_v2()


func test_chase_window_and_range() -> void:
	await reset_v2()
	await spar_calm()
	var fp := fox.global_position
	var results := {}
	# [label, start offset, wait frames after the dodge ended, expect chase]
	# (80 px: an attack in place - even with its 8 px lunge - cannot reach him; 66 px is the reach)
	for c in [["0.55 s after", Vector2(-80, -86), 33, true], ["0.65 s after", Vector2(-80, -86), 39, false],
			["1.0 s after", Vector2(-80, -86), 60, false], ["out of range (110 px)", Vector2(-110, -86), 3, false],
			["in range (90 px)", Vector2(-90, -86), 3, true]]:
		await r.teleport(fp + c[1])
		fox.global_position = fp
		var end := await dodge(Vector2.DOWN)
		await r.frames(c[2])
		var c0 := player.chases_started
		var hp0 := fox.hp
		var before := player.global_position
		await r.tap(KEY_J)
		await attack_done()
		var moved := player.global_position.distance_to(before)
		var chased := player.chases_started == c0 + 1
		var ok: bool = chased == c[3]
		if not c[3]:
			# no chase: attack in place - only the 8 px lunge, and 师兄 (out of reach) is not hit
			ok = ok and moved <= player.stats.lunge_distance + 1.0 and fox.hp == hp0
		else:
			ok = ok and fox.hp < hp0
		results[c[0]] = ok
		r.check(ok, "AC4 chase: %s -> %s" % [c[0], "chase + hit" if c[3] else "attack in place, no dash"],
			"dodge end %.0f px from 师兄, chased %s, moved %.1f px, 师兄 HP %d -> %d" % [end.distance_to(fp), chased, moved, hp0, fox.hp])
		await r.frames(10)
	# no enemy at all (walking around, no fight): a J after a dodge is a normal attack
	await reset_v2()
	await r.teleport(r.tile_center(31, 29))
	await dodge(Vector2.RIGHT)
	var p0 := player.global_position
	var c1 := player.chases_started
	await r.tap(KEY_J)
	await attack_done()
	r.check(player.chases_started == c1 and player.global_position.distance_to(p0) <= player.stats.lunge_distance + 1.0,
		"AC4 chase: with no enemy in a fight, J after a dodge is an ordinary attack")
	await reset_v2()


## 试玩反馈 v1: the chase used to count as a 看破反击 (x1.5) after a dodge success; the 看破反击 is gone. Same setup as
## before: the chase after a dodge success is now an ordinary 8 + 12 with no gold 反击 - and (the fix) the chase hit
## lands even when 师兄 side-steps away during the blow's wind-up.
func test_chase_no_counter() -> void:
	await reset_v2()
	await spar_calm()
	var fp := fox.global_position
	await r.teleport(fp + Vector2(36, 0))
	fox.angle = 0.0
	await r.frames(2)
	var succ0 := player.dodge_successes
	await cs._fox_windup_until(0.15)
	# side-step slightly forward (66 deg off "towards him": no swap) at the end of his wind-up -> 看破
	var end := await dodge(Vector2(-0.4, 0.92).normalized())
	fox.next_attack = 9999.0
	var success := player.dodge_successes == succ0 + 1
	var hp0 := fox.hp
	var c0 := player.chases_started
	var gold0: int = combat.hud.number_texts().filter(func(s): return "反击" in s).size()
	var pop0: int = combat.fx.spawned.get("counter_text", 0) + combat.fx.spawned.get("slash_counter", 0)
	await r.frames(3)
	await r.tap(KEY_J)
	var g := 0
	while fox.hp == hp0 and g < 40:
		await r.physics_frame
		g += 1
	var d1 := hp0 - fox.hp
	await r.tap(KEY_J)
	await r.frames(30)
	var d2 := hp0 - fox.hp - d1
	var gold: int = combat.hud.number_texts().filter(func(s): return "反击" in s).size()
	var pop: int = combat.fx.spawned.get("counter_text", 0) + combat.fx.spawned.get("slash_counter", 0)
	r.check(success and player.chases_started == c0 + 1 and d1 == 8 and d2 == 12 and gold == gold0 and pop == pop0,
		"试玩反馈 v1 chase: after a dodge success (看破) the chase hit is an ordinary 8 + 12 - no 看破反击 any more",
		"dodge end %.0f px away, success %s, dmg %d + %d" % [end.distance_to(fp), success, d1, d2])
	await attack_done()
	await r.frames(30)
	# the fix: he side-steps 62 px the moment the chase blow starts - the rabbit keeps sticking to him and the blow lands
	var hits := 0
	var tries := 0
	var detail := []
	for side in [1.0, -1.0, 1.0, -1.0]:
		await r.teleport(fp + Vector2(-70, -86))
		fox.global_position = fp
		player.dash_cooldown_left = 0.0
		await dodge(Vector2.DOWN)
		var h := fox.hp
		await r.tap(KEY_J)
		var w := 0
		while player.is_chasing() and w < 40:
			await r.physics_frame
			w += 1
		# 师兄's own side-step (sidestep_distance in sidestep_time), as when his 10 % chance comes up
		var dir: Vector2 = (fox.global_position - player.global_position).normalized().orthogonal() * float(side)
		fox.velocity = dir * (fox.stats.sidestep_distance / fox.stats.sidestep_time)
		fox.t = 0.0
		fox.state = "sidestep"
		w = 0
		while fox.hp == h and w < 40:
			await r.physics_frame
			w += 1
		tries += 1
		if fox.hp < h:
			hits += 1
		detail.append("%d" % (h - fox.hp))
		await attack_done()
		fox.state = "chase"
		fox.velocity = Vector2.ZERO
		await r.frames(20)
	r.check(hits == tries, "试玩反馈 v1 chase fix: 师兄 side-steps away right as the chase blow starts - it still lands (%d/%d)" % [hits, tries], str(detail))
	await reset_v2()


func test_chase_after_swap() -> void:
	await reset_v2()
	await spar_calm()
	var fp := fox.global_position
	await r.teleport(fp + Vector2(-40, 0))
	await dodge(Vector2.RIGHT)                    # into him, 40 px -> swap behind (28 px)
	var swapped := player.last_dodge_was_swap and player.global_position.x > fp.x
	var hp0 := fox.hp
	await r.frames(2)
	await r.tap(KEY_J)
	await r.frames(14)
	r.check(swapped and player.last_attack_chased and hp0 - fox.hp == 8 and r.is_free(player.global_position),
		"AC4 chase + swap: after a swap, J is the chase attack (already in reach: hits at once)", "swap %s dmg %d" % [swapped, hp0 - fox.hp])
	await attack_done()
	# swap with the buffer: J pressed during the swap -> attack the moment it lands
	await r.teleport(fp + Vector2(40, 0))
	fox.global_position = fp
	player.dash_cooldown_left = 0.0
	r.hold_dir(Vector2.LEFT)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	await r.tap(KEY_J)
	r.release_all()
	var hp1 := fox.hp
	await r.frames(20)
	r.check(player.last_dodge_was_swap and player.last_attack_chased and hp1 - fox.hp == 8, "AC4 chase + swap: J pressed during the swap is buffered and chases on landing",
		"dmg %d" % (hp1 - fox.hp))
	await attack_done()
	await reset_v2()


## A pinned bandit stands right behind an obstacle (walls, cliffs, buildings, fences, trees, rocks ...), the player
## dodges sideways so that it ends in front of the obstacle, inside 96 px of the bandit, and presses J. The chase
## must stop at the obstacle: the player ends on free ground on its own side.
func test_chase_never_through_walls() -> void:
	await reset_v2()
	var w := wolf
	var tested := 0
	var chased := 0
	var bad := []
	var by_kind := {}
	var cases := []
	for c in r.data["colliders"]:
		if c["kind"] == "bounds":
			continue
		var k: String = c["kind"]
		if by_kind.get(k, 0) >= (24 if k == "tile" else 6):
			continue
		var rc: Array = c["rect"]
		var rect := Rect2(rc[0], rc[1], rc[2], rc[3])
		if rect.size.y > 70.0:
			continue          # too thick: the bandit behind it would be outside the 96 px chase range
		by_kind[k] = by_kind.get(k, 0) + 1
		var cx := rect.get_center().x
		# [rect, bandit, player dodge end, dodge dir, side check]
		for dd in [Vector2.RIGHT, Vector2.LEFT]:
			cases.append([rect, Vector2(cx, rect.position.y - 4), Vector2(cx, rect.end.y + 9), dd, "below", k])
			cases.append([rect, Vector2(cx, rect.end.y + 9), Vector2(cx, rect.position.y - 3), dd, "above", k])
	for c in cases:
		var rect: Rect2 = c[0]
		var wp: Vector2 = c[1]
		var target_end: Vector2 = c[2]
		var start: Vector2 = target_end - c[3] * 86.4
		if not r.is_free(start) or not r.is_free(target_end) or not cs._free_for_npc(wp, w):
			continue
		await r.teleport(start)
		pin(w, wp)
		await r.frames(1)
		var end := await dodge(c[3])
		if end.distance_to(wp) > player.stats.chase_range or end.distance_to(wp) <= player.stats.hit_offset:
			continue          # the dodge was stopped by something else: no chase possible from here
		var c0 := player.chases_started
		await r.tap(KEY_J)
		await attack_done()
		await r.frames(2)
		tested += 1
		if player.chases_started > c0:
			chased += 1
		var e := player.global_position
		# through = the player's feet box touched the obstacle anywhere on the way, or ended on its far side
		var through := _path_hits(end, e, rect)
		var far_side: bool = (e.y < rect.position.y and end.y > rect.end.y) or (e.y > rect.end.y and end.y < rect.position.y)
		if not r.is_free(e) or through or (far_side and e.x > rect.position.x - 6 and e.x < rect.end.x + 6):
			bad.append("%s %s: from %s -> %s" % [c[5], rect, end.round(), e.round()])
	w.reset_home(true)
	r.check(bad.is_empty() and tested >= 40 and chased >= tested * 0.8,
		"AC4 chase safety: next to %d obstacles (%d kinds) the chase never passes through or into them" % [tested, by_kind.size()],
		"%d chases started; kinds %s; failures %s" % [chased, by_kind.keys(), bad])
	# positive control: same setup with nothing in between -> the chase reaches the bandit
	await r.teleport(Vector2(1000, 1100) - Vector2(86.4, 0))
	pin(w, Vector2(1000, 1030))
	await r.frames(1)
	await dodge(Vector2.RIGHT)
	await r.tap(KEY_J)
	await attack_done()
	var dist_end := player.global_position.distance_to(w.global_position)
	var reached := dist_end <= player.stats.hit_offset + 1.5
	w.reset_home(true)
	r.check(reached and player.last_attack_chased, "AC4 chase: positive control - in the open the same chase reaches the bandit",
		"%.1f px, chased %s, blocked %s, end %s" % [dist_end, player.last_attack_chased, player.chase_blocked, player.chase_end])
	await reset_v2()


## True if the player's feet box (12x6 around p + (0,-2)) overlaps `rect` anywhere on the segment a -> b.
func _path_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var n := int(ceil(a.distance_to(b))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var feet := Rect2(p + Vector2(-6, -5), Player.FOOT_SIZE)
		if feet.grow(-0.6).intersects(rect):
			return true
	return false


func test_chase_arena() -> void:
	await reset_v2()
	await spar_calm()
	var a := combat.arena_rect
	var bad := ""
	var n := 0
	# 师兄 near each edge and corner, the player chasing him along / towards the edge
	var spots := [Vector2(a.position.x + 14, a.get_center().y), Vector2(a.end.x - 14, a.get_center().y),
		Vector2(a.get_center().x, a.position.y + 14), Vector2(a.get_center().x, a.end.y - 10),
		a.position + Vector2(14, 14), Vector2(a.end.x - 14, a.end.y - 10),
		Vector2(a.end.x - 14, a.position.y + 14), Vector2(a.position.x + 14, a.end.y - 10)]
	for sp in spots:
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var start: Vector2 = sp + d * -60.0 - d.orthogonal() * 40.0
			if not a.grow(-8).has_point(start) or not r.is_free(start):
				continue
			fox.global_position = sp
			await r.teleport(start)
			await dodge(d.orthogonal())
			await r.tap(KEY_J)
			await attack_done()
			n += 1
			if not a.grow(1).has_point(player.global_position):
				bad += "%s->%s " % [sp, player.global_position.round()]
	# forced: 师兄 pushed just outside the arena wall (cannot happen in play) - the chase must stop at the edge
	fox.global_position = Vector2(a.position.x - 40, a.get_center().y)
	await r.teleport(Vector2(a.position.x + 40, a.get_center().y - 86))
	await dodge(Vector2.DOWN)
	var c0 := player.chases_started
	await r.tap(KEY_J)
	await attack_done()
	var forced_ok := a.grow(1).has_point(player.global_position) and player.chases_started == c0 + 1
	r.check(bad == "" and n >= 10 and forced_ok, "AC4 chase arena: %d chases at the 练武场 edges and corners never leave it; a target outside the wall stops the chase at the edge" % n,
		"%s forced end %s" % [bad, player.global_position.round()])
	await reset_v2()


# ================================================================== Esc pause
func snapshot() -> Dictionary:
	var s := {
		"hour": main.daynight.hour, "player": player.global_position, "pvel": player.velocity, "stage": player.attack_stage,
		"attack_t": player.attack_t, "dash": player.dash_time_left, "cd": player.dash_cooldown_left, "hp": player.hp,
		"timer": combat._timer, "hitstop": combat.hitstop_left, "banner_a": combat.hud.banner.modulate.a,
		"hint_a": main.hud.hint.modulate.a, "numbers": combat.hud.numbers.map(func(x): return x["t"]),
		"star": main.hud.minimap._t, "lamp_t": main.ambience._t,
	}
	for f in combat.fighters:
		s[f.id] = [f.global_position, f.state, f.t, f.next_attack, f.hp, f.sprite.frame, f.sprite.frame_progress]
	s["psprite"] = [player.sprite.animation, player.sprite.frame, player.sprite.frame_progress]
	return s


func diff(a: Dictionary, b: Dictionary) -> String:
	var out := ""
	for k in a:
		if str(a[k]) != str(b[k]):
			out += "%s: %s -> %s; " % [k, a[k], b[k]]
	return out


func test_pause_freezes_and_restores() -> void:
	await reset_v2()
	# a busy moment: both bandits fighting the player, the clock running, a banner and damage numbers on screen
	combat.bandits_enabled = true
	main.daynight.running = true
	await r.teleport(r.find_free_near(Vector2(512, 1450)))
	var g := 0
	while not (wolf.engaged and boar.engaged) and g < 60:
		await r.physics_frame
		g += 1
	r.hold_dir(Vector2.RIGHT)
	await r.frames(20)
	combat.hud.show_banner("测试", "", 3.0)
	combat.hud.damage_number(player.global_position, 5, "hit")
	await r.frames(3)
	var before := snapshot()
	var box := {}
	main.pause_menu.opened.connect(func(): box["open"] = snapshot(), CONNECT_ONE_SHOT)
	main.pause_menu.closed.connect(func(): box["close"] = snapshot(), CONNECT_ONE_SHOT)
	r.key(KEY_ESCAPE, true)
	await r.frames(1)
	r.key(KEY_ESCAPE, false)
	var opened: bool = main.pause_menu.is_open and r.paused
	var at_pause: Dictionary = box.get("open", {})
	# while paused: wait 1.5 s and hammer the game keys - nothing may change
	for i in 3:
		await r.tap(KEY_J)
		await r.tap(KEY_SPACE)
	r.hold_dir(Vector2.LEFT)
	for i in 80:
		await r.process_frame
	var during := snapshot()
	var still := diff(at_pause, during)
	r.check(opened and not at_pause.is_empty() and still == "", "AC5 Esc: pauses everything - clock, enemies (position / state / timers / animation), player, timers, banner, numbers (1.5 s + J / Space / move keys while paused)",
		"changed while paused: %s" % still)
	r.check(main.pause_menu.root.visible and main.pause_menu.panel.visible, "AC5 Esc: the help page is shown while paused")
	# resume with Esc: continues from exactly the same state, then moves on
	r.hold_dir(Vector2.RIGHT)
	r.key(KEY_ESCAPE, true)
	await r.frames(1)
	r.key(KEY_ESCAPE, false)
	var resumed: bool = not main.pause_menu.is_open and not r.paused
	var after: Dictionary = box.get("close", {})
	await r.frames(30)
	var later := snapshot()
	var moving: bool = later["hour"] > after["hour"] and (later["wolf"][0] != after["wolf"][0] or later["boar"][0] != after["boar"][0] or later["wolf"][2] != after["wolf"][2])
	r.check(resumed and not main.pause_menu.root.visible and not after.is_empty() and diff(at_pause, after) == "" and moving,
		"AC5 Esc again: resumes from exactly the paused state, then time and enemies move on",
		"diff at resume: %s; hour %.4f -> %.4f" % [diff(at_pause, after), after["hour"], later["hour"]])
	r.release_all()
	main.daynight.running = false
	# before the pause vs at the pause: the game was really running (sanity of the snapshot)
	r.check(diff(before, at_pause) != "", "AC5 Esc: (sanity) the snapshot does change while the game runs")
	await reset_v2()
	# spar result timer and death timer stop too
	await spar_calm()
	combat.end_spar(true)
	await r.frames(10)
	var t0 := combat._timer
	await r.tap(KEY_ESCAPE)
	for i in 120:
		await r.process_frame
	var t1 := combat._timer
	await r.tap(KEY_ESCAPE)
	await r.frames(5)
	r.check(absf(t1 - t0) < 0.04 and combat.spar_state == "result" and combat._timer < t1, "AC5 Esc: the spar result timer stops while paused and runs on after", "%.3f %.3f %.3f" % [t0, t1, combat._timer])
	await reset_v2()


func test_pause_page() -> void:
	await reset_v2()
	var pm: PauseMenu = main.pause_menu
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	await r.process_frame
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var rect := pm.panel.get_global_rect()
	var text := ""
	for l in pm.key_labels + pm.tip_labels:
		text += l.text + "\n"
	var keys_ok := true
	for k in ["WASD", "方向键", "J", "鼠标左键", "空格", "Shift", "K", "鼠标右键", "格挡", "E", "交谈", "1 / 2", "↑↓", "选择", "T", "快进", "L", "氛围", "Esc", "暂停"]:
		keys_ok = keys_ok and k in text
	var tips_ok := true
	for k in ["两连击", "闪避无敌", "格挡（GP）", "反击", "自动换位", "闪身追击", "切磋", "20%", "山贼", "复活"]:
		tips_ok = tips_ok and k in text
	var font: Font = load("res://fonts/ui_font.fnt")
	var missing := ""
	for c in PauseMenu.all_text():
		if c != " " and not font.has_char(c.unicode_at(0)):
			missing += c
	r.check(pm.is_open and Rect2(Vector2.ZERO, vp).encloses(rect) and rect.size.x > vp.x * 0.6,
		"AC5 page: the help page fits on the screen (%s inside %s)" % [rect, vp])
	r.check(keys_ok and tips_ok and missing == "", "AC5 page: lists every key with its use (试玩反馈 v1: K / 鼠标右键 格挡) and the play tips (combo, i-frames, 格挡 GP / 反击, swap, chase, spar, bandits)",
		"keys %s tips %s missing glyphs '%s'" % [keys_ok, tips_ok, missing])
	# no label is clipped: each label gets at least its minimum size
	var clipped := ""
	for l in pm.key_labels + pm.tip_labels:
		if l.size.y + 0.5 < l.get_combined_minimum_size().y or not rect.grow(1).encloses(l.get_global_rect()):
			clipped += l.text.substr(0, 6) + " "
	r.check(clipped == "", "AC5 page: no text is cut off", clipped)
	# 继续 button: real mouse click on it resumes; Enter on the focused button too; E too
	var bc := pm.resume_button.get_global_rect().get_center()
	await _click(bc)
	var by_click: bool = not pm.is_open and not r.paused
	await r.frames(3)
	var no_swing := player.attack_stage == 0
	await r.tap(KEY_ESCAPE)
	await r.tap(KEY_ENTER)
	var by_enter := not pm.is_open
	await r.tap(KEY_ESCAPE)
	await r.tap(KEY_E)
	var by_e: bool = not pm.is_open and not r.paused
	r.check(by_click and no_swing and by_enter and by_e, "AC5 page: '继续' resumes by mouse click (without swinging), Enter, or E",
		"click %s (no attack %s) enter %s e %s" % [by_click, no_swing, by_enter, by_e])
	await reset_v2()


func _click(screen: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		Input.parse_input_event(ev)
		await r.process_frame
		await r.process_frame


func test_hint_mentions_esc() -> void:
	r.check("Esc" in main.hud.hint_label.text and "查看全部按键" in main.hud.hint_label.text,
		"AC5 hint: the on-screen key hint says 'Esc：查看全部按键'", main.hud.hint_label.text.replace("\n", " / "))


# ================================================================== small fixes
func test_plates_do_not_cover_bodies() -> void:
	await reset_v2()
	var base := Vector2(520, 1450)
	var bad := ""
	var n := 0
	# wolf / boar arrangements: stacked vertically (close and far), side by side, diagonal; the player close by
	for off in [Vector2(0, 22), Vector2(0, 30), Vector2(0, 40), Vector2(0, -26), Vector2(18, 0), Vector2(26, 12),
			Vector2(-24, 18), Vector2(10, 34), Vector2(40, 0), Vector2(0, 52)]:
		for pp in [Vector2(-40, 0), Vector2(0, 40), Vector2(30, -30)]:
			if not cs._free_for_npc(base, wolf) or not cs._free_for_npc(base + off, boar):
				continue
			pin(wolf, base)
			pin(boar, base + off)
			await r.teleport(base + pp)
			await r.process_frame
			await r.process_frame
			n += 1
			var hud := combat.hud
			var bodies := {wolf: hud.body_rect(wolf.global_position), boar: hud.body_rect(boar.global_position)}
			var pr: Rect2 = hud.body_rect(player.global_position)
			for f in [wolf, boar]:
				if not hud.plate_visible(f):
					bad += "%s hidden; " % f.id
					continue
				var rect: Rect2 = hud.plates[f]["panel"].get_global_rect()
				var other: Fighter = boar if f == wolf else wolf
				if rect.intersects(bodies[other]) or rect.intersects(pr):
					bad += "%s plate %s over %s at off %s player %s; " % [f.id, rect, "other" if rect.intersects(bodies[other]) else "player", off, pp]
			if hud.plates[wolf]["panel"].get_global_rect().intersects(hud.plates[boar]["panel"].get_global_rect()):
				bad += "plates overlap at %s; " % off
	r.check(bad == "" and n >= 20, "AC6 plates: in %d close arrangements neither bandit's name plate covers the other bandit or the player, nor each other" % n, bad)
	# in normal play (real chase) plates stay readable: name shown when there is room
	r.check(combat.hud.plates[wolf]["label"].visible or combat.hud.plates[boar]["label"].visible, "AC6 plates: names still shown when there is room")
	await reset_v2()


func test_numbers_vs_result_and_banner() -> void:
	await reset_v2()
	# finish a spar with a real hit: the last damage number appears right where the result panel opens
	await spar_calm()
	fox.hp = 30
	var g := 0
	while combat.spar_state == "fighting" and g < 30:
		await r.teleport(fox.global_position + Vector2(0, 30))
		await r.tap(KEY_J)
		await r.frames(16)
		g += 1
	var over := ""
	var seen := 0
	for i in 30:
		await r.process_frame
		if not combat.hud.result_panel.visible:
			continue
		var pr: Rect2 = combat.hud.result_panel.get_global_rect()
		for v in combat.hud.visible_numbers():
			if v[1].intersects(pr):
				over += "%s %s; " % v
		seen += 1
	var order_ok: bool = combat.hud.numbers_root.get_index() < combat.hud.result_panel.get_index()
	r.check(combat.spar_state == "result" and seen > 10 and over == "" and order_ok,
		"AC6 result: no damage number is drawn over the spar result panel (and numbers sit under it)", over)
	await reset_v2()
	# "切磋开始！" + "看破！" at the same time: the 看破 text is moved below the banner
	await cs.start_spar_keys()
	cs.calm_fox()
	await r.frames(2)
	var hud := combat.hud
	var bad := ""
	# real dodge success while the start banner is up
	await r.teleport(fox.global_position + Vector2(36, 0))
	fox.angle = 0.0
	hud.show_banner("切磋开始！", "", 1.2)
	await cs._fox_windup_until(0.15)
	hud.show_banner("切磋开始！", "", 1.2)
	await dodge(Vector2.DOWN)
	fox.next_attack = 9999.0
	for i in 20:
		await r.process_frame
		var br := hud.banner_rect()
		for v in hud.visible_numbers():
			if br.has_area() and v[1].intersects(br):
				bad += "%s %s / %s; " % [v[0], v[1], br]
	# forced worst case: the text spawns exactly on the banner
	var br2 := hud.banner_rect()
	var world: Vector2 = main.get_viewport().get_canvas_transform().affine_inverse() * (br2.get_center() + Vector2(0, 12))
	hud.damage_number(world, 0, "text", "看破！")
	for i in 20:
		await r.process_frame
		var br := hud.banner_rect()
		for v in hud.visible_numbers():
			if br.has_area() and v[1].intersects(br):
				bad += "forced %s %s / %s; " % [v[0], v[1], br]
	r.check(bad == "" and "看破！" in hud.number_texts(), "AC6 banner: '看破！' never overlaps '切磋开始！' (real dodge + forced worst case)", bad)
	await reset_v2()


func test_focus_click() -> void:
	await reset_v2()
	await r.teleport(r.tile_center(31, 29))
	var a0 := player.attacks_started
	# the window gets focus (alt-tab back / click into the page) -> that click does not attack
	r.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _click(Vector2(240, 200))
	await r.frames(4)
	var after_focus := player.attacks_started - a0
	await r.frames(30)    # 0.5 s later the mouse attacks again
	await _click(Vector2(240, 200))
	await r.frames(4)
	var later := player.attacks_started - a0
	await attack_done()
	# web build: the very first click on the page only focuses it
	player.first_click_guard = true
	player._seen_input = false
	var a1 := player.attacks_started
	await _click(Vector2(240, 200))
	await r.frames(4)
	var first := player.attacks_started - a1
	await _click(Vector2(240, 200))
	await r.frames(4)
	var second := player.attacks_started - a1
	player.first_click_guard = false
	await attack_done()
	# J is never swallowed
	r.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var a2 := player.attacks_started
	await r.tap(KEY_J)
	await r.frames(2)
	var j_ok := player.attacks_started == a2 + 1
	r.check(after_focus == 0 and later == 1 and first == 0 and second == 1 and j_ok,
		"AC6 focus click: the click that focuses the game (or the page's first click on the web) does not attack; later clicks and J do",
		"after focus %d, later %d, web first %d, second %d, J %s" % [after_focus, later, first, second, j_ok])
	await attack_done()
	await reset_v2()


## Report only (no pass/fail): how an attack-masher does against the two stronger bandits.
func test_bandit_masher_report() -> void:
	var wins := 0
	var deaths_total := 0
	var times := []
	for run in 3:
		await reset_v2()
		combat.bandits_enabled = true
		combat.rng.seed = 500 + run
		await r.teleport(r.find_free_near(Vector2(512, 1440)))
		var t := 0.0
		var d0 := combat.deaths
		while not combat.bandits_cleared and not combat.player_dead and t < 90.0:
			cs.bot_step("masher")
			await r.physics_frame
			t += 1.0 / 60.0
		cs._release()
		if combat.bandits_cleared:
			wins += 1
		deaths_total += combat.deaths - d0
		times.append(snappedf(t, 0.1))
		r._log("      bandits vs masher run %d: %s after %.1f s (狼 %d HP, 野猪 %d HP left)" % [run, "cleared" if combat.bandits_cleared else ("knocked out" if combat.player_dead else "timeout"), t, wolf.hp, boar.hp])
	cs.bot_results["bandit_masher"] = {"runs": 3, "wins": wins, "times": times}
	r._log("      bandits vs masher: %d/3 cleared" % wins)
	await reset_v2()
