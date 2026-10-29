extends "res://tests/run_tests.gd"
## 武学与经营 第一批 · 经营 (B) screenshots (the Godot game window's own picture - no screen capture, no browser):
##   tools/screenshots_farm.sh [output folder]      (default game2d/screenshots/)
##   01 序章转场: black with 「序章 · 完」     02 lit again: the rabbit outside the hall
##   03 the field before 开菜园 (weeds)      04 after 开菜园 (tilled plots)
##   05 three crops growing (青菜 / 萝卜 / 南瓜, one ripe with its sparkle)   06 watered plots (dark soil), the bucket
##   07 a glowing gathering spot (bamboo shoot)   08 the 库房 page (中文)   09 the 库房 page (English)
##   10 the 进阶 objective line + the 任务看板 新手指引 tab with the 进阶 steps
## Reuses the farm test helpers (tests/farm_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	print("shooting ", name)
	await process_frame
	RenderingServer.force_draw(false)     # (also when the window is covered: macOS skips drawing occluded windows)
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("farm_" + name + ".png")
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


func _run() -> void:
	await frames(3)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	root.remove_child(main)
	root.size = Vector2i(1440, 810)
	SaveGame.erase()
	t = load("res://tests/farm_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(self)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	Lang.set_lang("zh")
	# 01 / 02 the prologue transition
	await t.ss.new_game()
	t.bind()
	await t.ss.finish_scene()
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		t.story.flags[f] = true
	t.story.set_stage(8)
	t.g.daynight.restore(10.0, 10.0)
	await t.ss.stand_near(t.ss.npc("crane").global_position)
	await tap(KEY_E)
	var shot1 := false
	for i in 3000:
		var pf: PrologueFade = t.story.prologue_fade
		if pf != null and pf.is_open and pf.alpha() >= 0.999 and t.gd.caption_showing() and t.gd.caption_label.modulate.a > 0.95 and not shot1:
			shot1 = true
			await shot("01_transition_black_caption")
		if t.story.sect_book.is_open:
			await tap(KEY_ESCAPE)
		elif t.dlg.active and not (pf != null and pf.is_open):
			if t.smp.unlocked:
				break
			await tap(KEY_E)
		elif t.smp.unlocked and not t.story.busy and not (pf != null and pf.is_open):
			break
		else:
			await physics_frame
	await settle(0.3)
	t.g.hud.hide_hint_now()
	await shot("02_transition_lit_outside_hall")
	await t.ss.finish_scene()
	# 03 / 04 the field before / after
	t.g.daynight.running = false
	await t.clock(10.0)
	await teleport(Vector2(1640, 1080))
	await settle(0.5)
	await shot("03_field_before")
	await t.open_farm_direct()
	await settle(0.4)
	await shot("04_field_opened")
	# 05 three crops (one ripe), 06 watered plots + the bucket
	t.fm.plots[0] = {"crop": "greens", "days": 1, "wet": false, "note": false}
	t.fm.plots[1] = {"crop": "radish", "days": 1, "wet": false, "note": false}
	t.fm.plots[2] = {"crop": "pumpkin", "days": 2, "wet": false, "note": false}
	t.fm.plots[3] = {"crop": "pumpkin", "days": 4, "wet": false, "note": false}
	t.fm.plots[4] = {"crop": "radish", "days": 0, "wet": false, "note": false}
	t.fm._refresh_visuals()
	await teleport(Vector2(1712, 1150))
	await settle(0.5)
	await shot("05_three_crops")
	t.fm.bucket = 6
	await t.e_plot(1)
	await t.e_plot(2)
	await t.e_plot(4)
	await teleport(Vector2(1712, 1094))
	await settle(0.4)
	await shot("06_watered_plots_bucket")
	# 07 a gathering spot glowing
	var sp: Dictionary = t.fm.gdata["spots"][1]
	await teleport(find_free_near(t.fm._v(sp["pos"]) + Vector2(-30, 20), 14))
	await settle(0.5)
	await shot("07_gather_glow")
	# 08 / 09 the 库房 page
	t.fm.seeds = {"greens": 3, "radish": 2, "pumpkin": 1}
	t.fm.store = {"greens": 2, "radish": 1, "pumpkin": 1, "shoots": 3, "herbs": 2, "meal": 1}
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await frames(3)
		await tap(KEY_B)
		await frames(3)
		var n := 0
		while t.story.sect_book.page_id() != "store" and n < 4:
			await tap(KEY_RIGHT)
			n += 1
		for i in 6:
			await tap(KEY_DOWN)
		await settle(0.3)
		await shot("08_store_page_zh" if lang == "zh" else "09_store_page_en")
		await tap(KEY_ESCAPE)
	Lang.set_lang("zh")
	# 10 进阶: after 出师
	for i in 5:
		t.gd.done[i] = true
		t.gd.paid[i] = true
	t.fm.opened = false
	t.story.flags["repair_farm"] = false
	t.fm._refresh_visuals()
	await settle(3.0)
	await teleport(Vector2(1500, 1100))
	await tap(KEY_Q)
	await settle(0.3)
	await shot("10_advanced_guide")
	await tap(KEY_Q)
	await t.ss._free_game()
	SaveGame.erase()
	print("SHOTS DONE")
	quit(0)
