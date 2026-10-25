extends "res://tests/run_tests.gd"
## 第③步 screenshots -> screenshots/step3_*.png (the Godot game window only, ~3 min):  tools/screenshots_step3.sh
##   01 the ring + notice board at the village (entries open: 报名 banner)   02 the board's entry question
##   03 round 1 intro (monkey)   04 round 2 intro (yak)   05 round 3 intro (snake)   06 a fight in the ring (snake)
##   07 the title result (夺魁)   08 the youngster at 山门外   09 收下 / 再想想   10 师弟 in the dorm yard
##   11 派活 (帮厨 greyed)   12 陪练 in the 练武场   13 门派簿 (titles, 收徒, job + progress, next date)
##   14 Esc page 3 (擂台 / 收徒 tips)   15 伙食钱不够了 toast   16 普通 / 困难 at sign-up   17 a 困难 round (monkey)
##   18 the 困难 title result
## Reuses the step-3 test helpers (tests/step3_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "step3_" + name + ".png")
	print("saved ", name, " ", img.get_size())


func _run() -> void:
	await frames(3)
	root.remove_child(main)
	SaveGame.erase()
	t = load("res://tests/step3_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	await t.unlocked_game()
	var g: Node = t.g
	g.hud.hide_hint_now()
	# 01 / 02 the ring and the board on day 3, 13:00
	t.set_day(3, 13.0)
	t.set_coins(40)
	await teleport(t.ar.board_point() + Vector2(40, 30))
	await frames(20)
	await shot("01_ring_board")
	await teleport(t.ar.board_point() + Vector2(0, 6))
	await tap(KEY_E)
	for i in 200:
		var d: Dialogue = t.dlg
		if d.choosing:
			break
		if d.active and not d.is_typing():
			await tap(KEY_E)
		await frames(2)
	await frames(10)
	await shot("02_board_question")
	await tap(KEY_1)
	await t.play_keys([KEY_1])
	# 03-07 the three rounds (the bot fights; the opponent's HP is lowered near the end of each round for speed)
	for rnd in 3:
		await t.wait_arena("intro", 300)
		await frames(40)
		await shot("%02d_round%d_intro" % [3 + rnd, rnd + 1])
		await t.wait_arena("fight", 300)
		if rnd == 2:
			for i in 70:
				t.cs.bot_step("counter")
				await physics_frame
			await shot("06_fight_snake")
		await t.win_round_quick()
		if rnd == 2:
			await frames(30)
			await shot("07_champion")
		await t.finish_result()
	# 08 / 09 the youngster at the gate (three repairs -> next 08:00)
	for f in ["repair_roof", "repair_dorm_old", "repair_kitchen"]:
		t.story.flags[f] = true
		t.smp.apply_repair_visuals(f)
	await frames(3)
	await t.advance_to(8.0)
	await t.advance_to(9.0)
	await teleport(t.dc.npc.global_position + Vector2(0, 30))
	await frames(20)
	await shot("08_youngster_gate")
	await tap(KEY_E)
	for i in 200:
		if t.dlg.choosing:
			break
		if t.dlg.active and not t.dlg.is_typing():
			await tap(KEY_E)
		await frames(2)
	await frames(10)
	await shot("09_accept_question")
	await tap(KEY_1)
	await t.play_keys([KEY_1])
	await frames(10)
	# 10 师弟 in the dorm yard
	await teleport(Vector2(300, 1040))
	await frames(120)
	await shot("10_disciple_yard")
	# 11 派活 (kitchen not repaired -> 帮厨 greyed): a game state with the kitchen flag off for this picture
	t.story.flags.erase("repair_kitchen")
	await t.ss.stand_near(t.dc.npc.global_position)
	await tap(KEY_E)
	var picked := 0
	for i in 300:
		if t.dlg.choosing:
			if picked == 0:
				await tap(KEY_1)
				picked = 1
				await frames(4)
				continue
			break
		if t.dlg.active and not t.dlg.is_typing():
			await tap(KEY_E)
		await frames(2)
	await frames(10)
	await shot("11_jobs_menu")
	await tap(KEY_2)        # 陪练
	await t.play_keys([])
	t.story.flags["repair_kitchen"] = true
	# 12 陪练 in the 练武场 the next day
	await t.advance_to(8.0)
	await t.advance_to(9.0)
	await t.ss.stand_near(t.dc.npc.global_position)
	await tap(KEY_E)
	await t.play_keys([KEY_1])
	for i in 90:
		t.cs.bot_step("counter")
		await physics_frame
	await shot("12_spar_disciple")
	t.dc.npc.hp = 10
	for i in 900:
		if g.combat.bout_owner == null:
			break
		t.cs.bot_step("counter")
		await physics_frame
	release_all()
	await frames(10)
	# 13 门派簿
	await tap(KEY_B)
	await frames(10)
	await shot("13_sect_book")
	await tap(KEY_ESCAPE)
	# 14 Esc page 3
	await tap(KEY_ESCAPE)
	await tap(KEY_RIGHT)
	await tap(KEY_RIGHT)
	await frames(4)
	await shot("14_esc_tips3")
	await tap(KEY_ESCAPE)
	# 15 伙食钱不够了
	t.story.flags.erase("repair_kitchen")     # no stall income this morning: the upkeep cannot be paid in full
	t.set_coins(2)
	await t.advance_to(8.0)
	for i in 900:
		if g.hud.toast.text.begins_with("伙食钱不够了") and g.hud.toast.modulate.a > 0.9:
			break
		await frames(1)
	await shot("15_upkeep_short")
	# 16-18 补充 v1.1: the difficulty choice, a 困难 round, the 困难 title
	t.story.flags["repair_kitchen"] = true
	t.set_day(t.ar.next_day() + (3 if t.ar.next_day() <= t.s3.day_number() else 0), 13.0)
	t.set_coins(40)
	await frames(3)
	await teleport(t.ar.board_point() + Vector2(0, 6))
	await tap(KEY_E)
	var asked := 0
	for i in 300:
		var d: Dialogue = t.dlg
		if d.choosing:
			if asked == 0:
				await tap(KEY_1)
				asked = 1
				await frames(4)
				continue
			break
		if d.active and not d.is_typing():
			await tap(KEY_E)
		await frames(2)
	await frames(10)
	await shot("16_difficulty_choice")
	await tap(KEY_2)
	await t.play_keys([])
	for rnd in 3:
		await t.wait_arena("fight", 400)
		if rnd == 0:
			for i in 50:
				t.cs.bot_step("counter")
				await physics_frame
			await shot("17_hard_round")
		await t.win_round_quick(true)
		if rnd == 2:
			await frames(30)
			await shot("18_hard_champion")
		await t.finish_result()
	SaveGame.erase()
	quit(0)
