extends "res://tests/run_tests.gd"
## 坐姿重画 + 高清头像 + 封面高清小兔 screenshots (the Godot game window's own picture - no screen capture, no browser):
##   tools/screenshots_hd.sh [output folder]      (default game2d/screenshots/)
##   01 小兔 on the kitchen bench, OLD front picture (the seat's pose cleared for this shot only)
##   02 the same bench, NEW back view facing the table      03 the kitchen stool, new back view
##   04 a hall 蒲团, new cross-legged meditation            05 a dorm cushion, cross-legged
##   06 a dialogue line of 师兄 with his HD portrait          07 the title screen with the HD rabbit
## Reuses the schedule test helpers (tests/schedule_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("hd_" + name + ".png")
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


func sit_shot(st: Seats, id: String, name: String) -> void:
	await t.seat_spot(st.seat(id))
	await tap(KEY_E)
	await settle(0.7)
	await shot(name)
	await tap(KEY_E)
	await settle(0.3)


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
	Lang.set_lang("zh")
	await t.game()
	var g: Node = t.g
	g.hud.hide_hint_now()
	var st: Seats = t.st
	await t.clock_settled(10.0)
	# 01 old picture (pose cleared for this shot only), 02 new
	var bench: Dictionary = st.seat("kitchen_bench")
	var pose: String = bench["pose"]
	bench["pose"] = ""
	await sit_shot(st, "kitchen_bench", "01_bench_old_front")
	bench["pose"] = pose
	await sit_shot(st, "kitchen_bench", "02_bench_new_back")
	await sit_shot(st, "kitchen_stool", "03_stool_new_back")
	await settle(3.3)          # the stool's first-time line bubble fades before the next room
	await sit_shot(st, "hall_futon_1", "04_futon_cross_legged")
	await sit_shot(st, "dorm_cushion_2", "05_cushion_cross_legged")
	# 06 a line of 师兄 with his HD portrait
	await teleport(g.interiors.world_point("dorm_main", Vector2(240, 200)))    # away from the cushions: no 按 E prompt
	await settle(0.3)
	var dlg: Dialogue = g.story.dialogue
	dlg.say({"who": "fox", "text": "哟，醒啦？我还以为你被雨水泡发了，正打算捞起来晒晒。"})
	await settle(2.5)
	await shot("06_dialogue_fox_hd_portrait")
	dlg.close()
	await t.ss._free_game()
	SaveGame.erase()
	# 07 the title screen
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await settle(1.5)
	await shot("07_title_hd_rabbit")
	print("shots done")
	quit(0)
