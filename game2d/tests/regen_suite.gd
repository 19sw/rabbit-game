extends RefCounted
## 脱战回血 v1.3 checks, run by tests/run_tests.gd after tests/combat_v2_suite.gd. Real physics ticks (the runner
## uses --fixed-fps 60, so N frames = N/60 s of game time), real damage through Player.take_damage, real spar flow,
## real bandit aggro / leash, real Esc key for the pause, a real story scene for the dialogue.

var r
var cs
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
	await reset_regen()
	await test_card_values()
	await test_timing_and_cap()
	await test_no_regen_in_spar_then_after()
	await test_no_regen_with_bandit_then_leash()
	await test_pause()
	await test_dialogue_does_not_block()
	await test_cue()
	await reset_regen()


func seconds(s: float) -> void:
	await r.frames(int(round(s * 60.0)))


## Everything calm: bandits' AI off and at home, no spar, no pause, full HP, regen timers at zero.
func reset_regen() -> void:
	if main.pause_menu.is_open:
		main.pause_menu.close()
	r.paused = false
	await cs.reset_all()
	combat.bandits_enabled = false
	for b in combat.bandits:
		b.stats = load("res://cards/%s.tres" % b.card)
		b.reset_home(true)
	fox.stats = load("res://cards/shixiong.tres")
	fox.reset_home(true)
	player.hp = player.stats.max_hp
	player.regen_calm = 0.0
	player.regen_acc = 0.0
	await r.frames(2)


## Real damage from a hit: 40 -> 60 HP (also resets the protect time so nothing blocks the next hit).
func hurt(amount: int) -> void:
	player.protect_left = 0.0
	player.iframes_left = 0.0
	player.take_damage(amount, player.global_position + Vector2(20, 0))
	await r.frames(2)


func test_card_values() -> void:
	var st: PlayerStats = load("res://cards/player.tres")
	r.check(is_equal_approx(st.regen_delay, 5.0) and is_equal_approx(st.regen_per_sec, 3.0),
		"regen AC4: the player card has regen_delay 5 and regen_per_sec 3", "%s %s" % [st.regen_delay, st.regen_per_sec])


func test_timing_and_cap() -> void:
	await reset_regen()
	await hurt(40)
	var hp0 := player.hp
	await seconds(4.7)
	r.check(hp0 == 60 and player.hp == 60, "regen AC1: no regen within 5 s after damage (60 HP after 4.7 s)", "%d -> %d" % [hp0, player.hp])
	# wait for the first point, then measure 10 s
	var g := 0
	while player.hp == 60 and g < 240:
		await r.physics_frame
		g += 1
	var started_at: float = 4.7 + g / 60.0
	r.check(player.hp > 60 and started_at >= 4.99 and started_at < 5.6, "regen AC1: regen starts at ~5 s after the damage", "first +1 at %.2f s" % started_at)
	var h1 := player.hp
	await seconds(10.0)
	var gained := player.hp - h1
	r.check(absf(gained / 10.0 - 3.0) <= 0.2, "regen AC1: +3 HP/s (+-0.2) measured over 10 s", "%d HP in 10 s" % gained)
	var mid := player.hp
	# sampled once per second: the visible HP only ever goes up, never past max
	var ok := true
	var last := player.hp
	for i in 30:
		await seconds(1.0)
		ok = ok and player.hp >= last and player.hp <= player.stats.max_hp
		last = player.hp
		if player.hp >= player.stats.max_hp:
			break
	await seconds(2.0)
	r.check(mid < 100 and player.hp == 100 and ok and not player.regen_active, "regen AC1: stops at max HP (100) and stays there", "mid %d, now %d" % [mid, player.hp])
	# another hit restarts the 5 s wait
	await hurt(30)
	await seconds(3.0)
	await hurt(10)
	var h2 := player.hp
	await seconds(4.7)
	r.check(player.hp == h2, "regen AC1: a new hit restarts the 5 s wait", "%d -> %d" % [h2, player.hp])
	# a dodged hit (i-frames) is not damage: no reset
	await reset_regen()
	await hurt(40)
	await seconds(3.0)
	player.iframes_left = 1.0
	var took := player.take_damage(20, player.global_position + Vector2(20, 0))
	player.iframes_left = 0.0
	await seconds(2.3)
	r.check(not took and player.hp > 60, "regen: a hit that is dodged (i-frames) does not count as damage / reset the wait", "took %s hp %d" % [took, player.hp])


func test_no_regen_in_spar_then_after() -> void:
	await reset_regen()
	var orig: EnemyStats = cs.calm_fox()
	combat.start_spar()
	await r.frames(3)
	await hurt(30)
	var h := player.hp
	await seconds(9.0)
	r.check(combat.spar_state == "fighting" and h == 70 and player.hp == 70 and not player.regen_active,
		"regen AC2: no regen during a spar (70 HP after 9 s, damage was 9 s ago)", "state %s hp %d" % [combat.spar_state, player.hp])
	fox.stats = orig
	# the spar ends: the existing full heal stays; then lower HP without damage and check the 5 s rule from the spar's end
	combat.end_spar(false)
	combat._timer = 0.0
	combat._finish_spar()
	await r.frames(2)
	r.check(player.hp == player.stats.max_hp, "regen AC5: end of a spar still heals fully", str(player.hp))
	player.hp = 50
	await seconds(4.5)
	var early := player.hp
	await seconds(2.0)
	r.check(early == 50 and player.hp > 50 and player.hp <= 56, "regen AC2: after the spar nothing for 5 s, then regen starts",
		"after 4.5 s: %d, after 6.5 s: %d" % [early, player.hp])
	await reset_regen()


func test_no_regen_with_bandit_then_leash() -> void:
	await reset_regen()
	# the wolf is on the road, harmless (never attacks, stands at home) but really aggro'd / leashed by Combat
	var st: EnemyStats = wolf.stats.duplicate()
	st.interval_min = 9999.0
	st.interval_max = 9999.0
	st.move_speed = 0.0
	wolf.stats = st
	wolf.next_attack = 9999.0
	var bst: EnemyStats = boar.stats.duplicate()
	bst.aggro_range = 0.0
	boar.stats = bst
	combat.bandits_enabled = true
	var home := wolf.home
	var near: Vector2 = r.find_free_near(home + Vector2(0, 110))
	var far: Vector2 = r.find_free_near(home + Vector2(0, 420), 60)
	var dist_ok: bool = far != Vector2.INF and far.distance_to(home) > st.leash_range
	await r.teleport(near)
	player.hp = 50          # lowered without damage: only the "in combat" rule can hold the regen back
	var g := 0
	while not wolf.engaged and g < 120:
		await r.physics_frame
		g += 1
	r.check(wolf.engaged, "regen AC2: (setup) the wolf noticed the player", "dist %.0f" % near.distance_to(home))
	await seconds(9.0)
	r.check(wolf.engaged and player.hp == 50 and not player.regen_active, "regen AC2: no regen while a bandit is engaged (9 s, no damage taken)", "hp %d" % player.hp)
	# leave: past the leash range the wolf gives up
	await r.teleport(far)
	g = 0
	while wolf.engaged and g < 120:
		await r.physics_frame
		g += 1
	r.check(dist_ok and not wolf.engaged and player.hp == 50, "regen AC2: (setup) the wolf gave up the chase (leash)", "far dist %.0f, leash %.0f" % [far.distance_to(home), st.leash_range])
	await seconds(4.5)
	var early := player.hp
	await seconds(2.0)
	r.check(early == 50 and player.hp > 50, "regen AC2: regen starts only after 5 s out of combat (leash)", "4.5 s: %d, 6.5 s: %d" % [early, player.hp])
	combat.bandits_enabled = false
	await reset_regen()


func test_pause() -> void:
	await reset_regen()
	await hurt(40)
	await seconds(3.0)
	# pause inside the 5 s wait: the wait must not advance while paused
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var paused_ok: bool = r.paused and main.pause_menu.is_open
	var h := player.hp
	await seconds(4.0)
	var held := player.hp
	await r.tap(KEY_ESCAPE)
	await seconds(1.5)
	r.check(paused_ok and h == 60 and held == 60 and player.hp == 60 and not r.paused,
		"regen AC3: paused during the 5 s wait -> the wait does not run (3 s + pause 4 s + 1.5 s = 4.5 s awake: still 60)", "%d %d %d" % [h, held, player.hp])
	await seconds(1.5)
	r.check(player.hp > 60, "regen AC3: after the pause the wait finishes and regen starts", str(player.hp))
	# pause during regen: HP frozen, then it goes on
	await seconds(2.0)
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var before := player.hp
	await seconds(5.0)
	var during := player.hp
	await r.tap(KEY_ESCAPE)
	await seconds(2.0)
	r.check(r.paused == false and before == during and player.hp >= during + 4 and player.hp <= during + 8,
		"regen AC3: HP identical before / after 5 s of Esc pause, and regen goes on after resuming", "before %d during %d after %d" % [before, during, player.hp])
	# the 门派簿 modal also holds it
	await reset_regen()
	await hurt(40)
	await seconds(6.5)
	var s0 := player.hp
	main.story.sect_book.is_open = true
	await seconds(3.0)
	var s1 := player.hp
	main.story.sect_book.is_open = false
	await seconds(1.0)
	r.check(s0 > 60 and s1 == s0 and player.hp > s1, "regen AC3: no regen while the 门派簿 is open", "%d %d %d" % [s0, s1, player.hp])
	await reset_regen()


func test_dialogue_does_not_block() -> void:
	await reset_regen()
	await hurt(40)
	main.story.play("S7-村民")
	await r.frames(10)
	var talking: bool = main.story.busy and main.story.dialogue.active
	await seconds(8.0)
	var still: bool = main.story.busy
	r.check(talking and still and combat.story_hold and player.hp > 60 and player.hp <= 70,
		"regen: regen goes on while a dialogue is on screen (8 s: 60 -> ~66)", "talking %s hp %d" % [talking, player.hp])
	main.story.enter_sandbox()
	await r.frames(3)
	combat.bandits_enabled = false
	await reset_regen()


func test_cue() -> void:
	await reset_regen()
	var bar = combat.hud.hp_bar
	r.check(not bar.regen, "regen AC4: no cue at full HP")
	await hurt(40)
	await seconds(4.0)
	r.check(not bar.regen, "regen AC4: no cue while waiting (5 s)")
	await seconds(2.0)
	r.check(bar.regen and player.regen_active, "regen AC4: cue on while regenerating")
	await seconds(14.0)
	r.check(player.hp == 100 and not bar.regen, "regen AC4: cue off at full HP", "hp %d" % player.hp)
	await reset_regen()
