extends "res://tests/run_tests.gd"
## 武学与经营 第一批 · 武学 (A) screenshots (the Godot game window's own picture - no screen capture, no browser):
##   tools/screenshots_skills.sh [output folder]      (default game2d/screenshots/)
##   01 / 02 the 门派簿 page 武学 (中文 / English), everything learned     03 燕回旋: the dust ring + leg arc mid-move
##   04 踏雪二段闪: the snow mark where the second dodge landed           05 学会吐纳功: the ring caption + edge flash
##   06 the U / I icons under the HP bar, U cooling down (the sweep)      07 the 武学 page before learning (silhouettes)
##   08 the 任务面板 tab 武学 at night (师父 06:00 起)
## Reuses tests/skills_suite.gd helpers; saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("skills_" + name + ".png")
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
	Lang.set_lang("zh")
	t = load("res://tests/skills_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(self)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	t.sc = load("res://tests/schedule_suite.gd").new(self)
	t.sc.ss = t.ss
	t.sc.t3 = t.t3
	t.sc.s4 = t.s4
	await t.game()
	var g: Node = t.g
	var sk: Skills = t.sk
	g.hud.hide_hint_now()
	await t.sc.clock_settled(10.0)
	# 07 the page before learning
	await tap(KEY_B)
	await settle(0.3)
	g.story.sect_book.show_page("skills")
	await settle(0.4)
	await shot("07_book_page_locked")
	await tap(KEY_ESCAPE)
	# 08 the board at night
	await t.set_fame(2)
	await t.sc.clock_settled(22.0)
	await t.sc.open_board()
	var qb: QuestBoard = g.quest_board
	qb._set_tab(qb.model.size() - 1)
	await settle(0.3)
	await shot("08_board_tab_night")
	await t.sc.close_board()
	await t.sc.clock_settled(10.0)
	# 05 learning 吐纳功: the caption
	await t.set_fame(4)
	sk.learn("swallow_spin", false)
	sk.learn("snow_step", false)
	sk.learn("tuna", true)
	await settle(0.55)
	await shot("05_learned_tuna_ring")
	await settle(2.6)
	# 01 / 02 the page, everything learned
	await tap(KEY_B)
	await settle(0.3)
	g.story.sect_book.show_page("skills")
	await settle(0.4)
	await shot("01_book_page_zh")
	await tap(KEY_ESCAPE)
	Lang.set_lang("en")
	await settle(0.2)
	await tap(KEY_B)
	await settle(0.3)
	g.story.sect_book.show_page("skills")
	await settle(0.4)
	await shot("02_book_page_en")
	await tap(KEY_ESCAPE)
	Lang.set_lang("zh")
	await settle(0.2)
	# 03 燕回旋 in the training yard next to 师兄, mid-move
	var fox: Npc = g.story._npc("fox")
	await teleport(fox.global_position + Vector2(-40, 30))
	await settle(0.3)
	key(KEY_U, true)
	await frames(2)
	key(KEY_U, false)
	await settle(0.2)
	await shot("03_swallow_spin")
	await settle(0.5)
	# 06 the icons cooling
	await settle(0.6)
	await shot("06_icons_cooldown")
	await settle(3.5)
	# 04 the snow mark after the second dodge
	await teleport(fox.global_position + Vector2(-140, 60))
	await settle(0.2)
	hold_dir(Vector2.RIGHT)
	await tap(KEY_SPACE)
	await frames(14)
	await tap(KEY_SPACE)
	release_all()
	await frames(16)
	await shot("04_snow_mark")
	await settle(0.5)
	print("SKILLS SHOTS DONE")
	quit(0)
