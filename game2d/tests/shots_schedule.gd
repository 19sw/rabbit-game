extends "res://tests/run_tests.gd"
## 坐下与人物作息 v1 screenshots (the Godot game window's own picture - no screen capture, no browser):
##   tools/screenshots_schedule.sh [output folder]      (default game2d/screenshots/)
##   01 小兔 on a dorm cushion          02 on a hall 蒲团            03 on the kitchen stool with its line
##   04 the hall at night: empty       05 师兄 asleep in his bed      06 his dream line
##   07 / 08 the 任务面板 button lit / grey (中文)   09 / 10 the same in English
##   11 "一夜过去……"                    12 the morning after: everybody back in the hall
##   13 / 14 (F1) 送馒头 / 送信 grey on the 告示榜 while 茶摊老板 sleeps (中文 / English)
##   15 / 16 (F2) the prompt and the dream line on the bed's lower edge (his face free)
## Reuses the schedule test helpers (tests/schedule_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	print("shooting ", name)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("schedule_" + name + ".png")
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
	t = load("res://tests/schedule_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(self)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	Lang.set_lang("zh")      # a window takes the system language; these shots are Chinese except 09 / 10
	print("SHOT stage: game")
	await t.game()
	print("SHOT stage: game ready")
	var g: Node = t.g
	g.hud.hide_hint_now()
	var st: Seats = t.st
	# 01 cushion (day)
	await t.clock_settled(10.0)
	await t.seat_spot(st.seat("dorm_cushion_2"))
	await tap(KEY_E)
	await settle(0.6)
	await shot("01_sit_cushion")
	await tap(KEY_E)
	# 02 蒲团 (day: 师父 on his own one beside)
	await t.seat_spot(st.seat("hall_futon_1"))
	await tap(KEY_E)
	await settle(0.6)
	await shot("02_sit_futon")
	await tap(KEY_E)
	# 03 the stool and its first-time line
	await t.seat_spot(st.seat("kitchen_stool"))
	await tap(KEY_E)
	await settle(0.4)
	await shot("03_sit_stool_line")
	await tap(KEY_E)
	await settle(3.2)
	# 04 the hall at night: 师父 is gone
	await t.clock_settled(23.0)
	var hall_spot: Vector2 = g.interiors.world_point("hall", Vector2(320, 236))
	await teleport(hall_spot)
	await settle(0.6)
	await shot("04_hall_empty_night")
	# 05 / 06 师兄 asleep in his bed, his dream line
	await t.ss.stand_near(g.schedule.bed_point())
	await settle(0.5)
	await shot("05_fox_asleep")
	await tap(KEY_E)
	await settle(0.4)
	await shot("06_fox_dream")
	await settle(3.2)
	# 07-10 the board: lit at night, grey by day, Chinese and English
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await t.clock_settled(22.5)
		await teleport(g.jianghu.board_point + Vector2(-30, 40))
		await settle(0.3)
		await tap(KEY_Q)
		await settle(0.3)
		await shot("%s_button_lit_%s" % ["07" if lang == "zh" else "09", lang])
		await tap(KEY_Q)
		await t.clock_settled(11.0)
		await tap(KEY_Q)
		await settle(0.3)
		await shot("%s_button_grey_%s" % ["08" if lang == "zh" else "10", lang])
		await tap(KEY_Q)
	Lang.set_lang("zh")
	# 11 一夜过去…… (from the hall at night), 12 the morning after
	await t.clock_settled(23.0)
	await teleport(hall_spot)
	await settle(0.3)
	await tap(KEY_Q)
	await settle(0.2)
	await tap(KEY_ENTER)
	for i in 600:
		if g.schedule.fade_rect.color.a >= 0.999 and g.schedule.fade_label.modulate.a >= 0.999:
			break
		await process_frame
	await settle(0.3)
	await shot("11_night_passes")
	for i in 900:
		if not g.schedule.waiting:
			break
		await process_frame
	await settle(1.0)
	await shot("12_morning_hall")
	# 13 / 14 F1: the 告示榜's 委托 page at 20:00 - 送馒头 / 送信 grey (茶摊老板 asleep), Chinese and English
	t.story.flags["repair_kitchen"] = true
	t.smp.apply_repair_visuals("kitchen")
	g.jianghu.seed = t.seed_both(g.jianghu.cal_day() + 1)
	await t.t3.advance_to(8.0)
	await t.clock(20.0)
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		await t.commission_page()
		await settle(0.5)
		await shot("%s_commission_grey_%s" % ["13" if lang == "zh" else "14", lang])
		await t.leave_page()
	Lang.set_lang("zh")
	# 15 F2: by 师兄's bed at night - the prompt on the bed's lower edge, his face free; 16 with the dream line
	await t.clock_settled(23.0)
	await t.ss.stand_near(g.schedule.bed_point())
	await settle(0.5)
	await shot("15_fox_prompt_edge")
	await tap(KEY_E)
	await settle(0.4)
	await shot("16_fox_dream_edge")
	await t.ss._free_game()
	SaveGame.erase()
	print("shots done")
	quit(0)
