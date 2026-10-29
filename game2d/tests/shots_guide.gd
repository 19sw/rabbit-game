extends "res://tests/run_tests.gd"
## 新手指引 + 任务面板 screenshots -> screenshots/guide_*.png (the Godot game window only):  tools/screenshots_guide.sh
##   01 the new ending: the 「序章 · 完」 caption over the game     02 师父's guide line
##   03 guide step 1 in the objective line + the gold minimap arrow   04 the 师兄 spar with the key hint
##   05 "指引完成：战斗  +10 文"                                       06-11 the 任务面板, one tab each
##   12 tracking a repair (objective line + arrow at 老周)            13 出师 caption   14 the 门派簿 with 新手指引·出师
## Reuses the guide test helpers (tests/guide_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "guide_" + name + ".png")
	print("saved ", name, " ", img.get_size())


func _run() -> void:
	await frames(3)
	root.remove_child(main)
	root.size = Vector2i(1440, 810)
	SaveGame.erase()
	t = load("res://tests/guide_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(self)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	# 01 / 02 the ending
	await t.ss.new_game()
	t.bind()
	var g: Node = t.g
	await t.finish()
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		t.story.flags[f] = true
	t.story.set_stage(8)
	g.daynight.restore(10.0, 10.0)
	await t.ss.stand_near(t.story._npc("crane").global_position)
	await tap(KEY_E)
	var shot1 := false
	var shot2 := false
	for i in 1500:
		if t.story.sect_book.is_open:
			await tap(KEY_ESCAPE)
		elif g.guide.caption_showing() and g.guide.caption_label.modulate.a > 0.95 and not shot1:
			shot1 = true
			await shot("01_prologue_caption")
		elif t.dlg.active and t.dlg.full_text == "先把门里的事摸熟，有不懂的按 Q 看看。" and not t.dlg.is_typing() and not shot2:
			shot2 = true
			await shot("02_master_line")
			await tap(KEY_E)
		elif t.dlg.active:
			await tap(KEY_E)
		elif t.smp.unlocked and not t.story.busy and not g.guide._intro_pending and shot2:
			break
		else:
			await frames(1)
	g.hud.hide_hint_now()
	await frames(30)
	await shot("03_step1_objective_arrow")
	# 04 / 05 the spar with the hint, then the step's caption
	var c: Combat = g.combat
	var fox: Fighter = t.story._npc("fox")
	await t.walk(fox.global_position + Vector2(0, 30))
	await tap(KEY_E)
	for i in 300:
		if c.spar_state == "choosing":
			break
		if t.dlg.active:
			await tap(KEY_E)
		else:
			await frames(2)
	await tap(KEY_1)
	var hint_shot := false
	for i in 60 * 90:
		if c.spar_state != "fighting":
			break
		t.t3.cs.bot_step("counter")
		if not hint_shot and i > 70:
			hint_shot = true
			await shot("04_spar_key_hint")
		await physics_frame
	t.t3.cs._release()
	release_all()
	for i in 600:
		if g.guide.caption_showing() and g.guide.caption_label.text.begins_with("指引完成") and g.guide.caption_label.modulate.a > 0.95:
			break
		await frames(1)
	await shot("05_step_done_caption")
	await frames(150)
	# 06-11 the board: every tab (some state in each)
	t.t3.set_day(2, 9.0)
	await frames(3)
	await t.s4.accept_bounty()
	await t.s4.accept_commission(String(g.jianghu.com.offers[0]["kind"]))
	await teleport(g.jianghu.board_point + Vector2(-30, 40))
	await frames(5)
	await tap(KEY_Q)
	await process_frame
	var names := ["06_board_guide", "07_board_bounty", "08_board_commission", "09_board_repair", "10_board_arena", "11_board_disciple"]
	for i in 6:
		g.quest_board._set_tab(i)
		await process_frame
		await process_frame
		await shot(names[i])
	# 12 tracking the roof repair
	g.quest_board._set_tab(3)
	await tap(KEY_E)
	await tap(KEY_Q)
	await frames(30)
	await shot("12_tracking_repair")
	# 13 / 14 出师: the remaining steps (a starting point), then the caption and the book
	print("SHOT stage: repair")
	t.ss.set_coins(40)
	await t.ss.talk("mouse", KEY_1)
	print("SHOT stage: repaired ", t.smp.is_repaired("roof"))
	t.story.flags["trial_bronze"] = true
	g.guide.bear_talked = true
	g.guide.arena_seen = true
	g.jianghu.com.total = maxi(1, g.jianghu.com.total)
	for i in 900:
		if g.guide.caption_showing() and g.guide.caption_label.text.begins_with("新手指引·出师") and g.guide.caption_label.modulate.a > 0.95:
			break
		await frames(1)
	print("SHOT stage: grad ", g.guide.paid, " ", g.guide.graduated, " ", g.guide.captions)
	await shot("13_graduate_caption")
	await frames(150)
	await tap(KEY_B)
	await frames(6)
	await shot("14_sect_book_graduate")
	await tap(KEY_ESCAPE)
	await t.ss._free_game()
	SaveGame.erase()
	print("shots done")
	quit(0)
