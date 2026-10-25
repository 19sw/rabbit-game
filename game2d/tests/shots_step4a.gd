extends "res://tests/run_tests.gd"
## 第④步第一批 screenshots -> screenshots/step4a_*.png (the Godot game window only):  tools/screenshots_step4a.sh
##   01 the 江湖告示榜 at the village plaza        02 the board's menu (看悬赏 / 看委托 / 离开)
##   03 a 悬赏 on the board                       04 the day's 委托 list
##   05 fighting the 黄鼠狼 (山路草丛)              06 the three 狼山贼 (山路石坎)
##   07 fighting 黑虎 (后山竹林深处)                08 黑虎 enraged (banner, red sheet, roar)
##   09 the chick following the rabbit           10 / 11 the fence gaps before / after mending
##   12 the 门派簿 (悬赏 第几条, 委托 x/5)          13 the HUD list under the coins
##   14 Esc page 4 (悬赏 / 委托 tips)            15 the longest spoken line of the data (fits one page)
##   16 / 17 a long speech shown in two pages (补充: a line never overflows the box; E turns the page)
##   18a / 18b 修复 v1: a long line in a wide window (1920x810), then the window shrunk to 1000x560 - laid out again
## Reuses the step-4a test helpers (tests/step4a_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "step4a_" + name + ".png")
	print("saved ", name, " ", img.get_size())


## Waits until the current line is fully typed (and its choices are up).
func settle_dialogue() -> void:
	for i in 300:
		var d: Dialogue = t.dlg
		if not d.active or (not d.is_typing() and (d.choice_options.is_empty() or d.choosing)):
			break
		await frames(2)
	await frames(6)


func through_dialogue() -> void:
	await t.finish()


## E at the board, then keys; stops (without answering) before the choice at index `stop_at` and returns.
func board_until(keys: Array, stop_at: int) -> void:
	await teleport(t.jh.board_point)
	await tap(KEY_E)
	var k := 0
	for i in 400:
		var d: Dialogue = t.dlg
		if d.choosing:
			if k == stop_at:
				return
			await tap(keys[k])
			k += 1
		elif d.active and not d.is_typing():
			await tap(KEY_E)
		await frames(2)


func fight_frames(kind: String, n: int) -> void:
	for i in n:
		if t.story.busy:
			release_all()
			await t.finish()
		if kind == "tiger":
			t.tiger_bot_step(-1.0)
		else:
			t.t3.cs.bot_step(kind)
		t.p().hp = maxi(t.p().hp, 60)
		await physics_frame
	t.t3.cs._release()
	release_all()


func _run() -> void:
	await frames(3)
	root.remove_child(main)
	SaveGame.erase()
	t = load("res://tests/step4a_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	root.size = Vector2i(1440, 810)      # the game's view: 480 x 270
	await t.game()
	var g: Node = t.g
	g.hud.hide_hint_now()
	t.set_day(2, 10.0)
	await frames(5)
	# 01 the board
	await teleport(t.jh.board_point + Vector2(-30, 36))
	await frames(30)
	await shot("01_board")
	# 02 menu, 03 bounty, 04 commissions
	await board_until([KEY_1], 0)
	await settle_dialogue()
	await shot("02_board_menu")
	await tap(KEY_1)
	await settle_dialogue()
	await shot("03_bounty_offer")
	await tap(KEY_1)          # 接榜
	await through_dialogue()
	await board_until([KEY_2], 1)
	await settle_dialogue()
	await shot("04_commissions")
	await tap(KEY_3)
	await through_dialogue()
	# 05 the weasel
	g.combat.rng.seed = 3
	await t.start_fight()
	await fight_frames("counter", 90)
	await shot("05_fight_weasel")
	for f in t.b.villains:
		f.hp = 1
	await t.bot_fight("counter", 40.0)
	await t.turn_in_bounty()
	# 06 the wolves
	t.set_day(3, 10.0)
	await frames(3)
	await t.accept_bounty()
	g.combat.rng.seed = 4
	await t.start_fight()
	await fight_frames("counter", 80)
	await shot("06_fight_wolves")
	for f in t.b.villains:
		f.hp = 1
	await t.bot_fight("counter", 40.0)
	await t.turn_in_bounty()
	# 07 / 08 黑虎, then enraged
	t.set_day(4, 10.0)
	await frames(3)
	await t.accept_bounty()
	g.combat.rng.seed = 5
	await t.start_fight()
	await fight_frames("tiger", 100)
	await shot("07_fight_tiger")
	var tg: Fighter = t.b.villains[0]
	tg.hp = 92
	for i in 600:
		if tg.raged:
			break
		t.t3.cs.bot_step("masher")
		t.p().hp = 100
		await physics_frame
	release_all()
	await frames(14)
	await shot("08_tiger_rage")
	tg.hp = 1
	await t.bot_fight("tiger", 40.0)
	# 09 the chick following
	await t.day_with("chicken")
	await t.accept_commission("chicken")
	await t.walk(t.cm.chick.global_position + Vector2(0, 18))
	await tap(KEY_E)
	await t.finish()
	await t.walk(Vector2(560, 1440))
	await t.walk(Vector2(760, 1430))
	await frames(4)
	await shot("09_chick_follows")
	await t.walk(t.cm.pen + Vector2(10, 4), 150.0)
	await frames(30)
	await t.turn_in_commission("chicken")
	# 10 / 11 the fence
	await t.day_with("fence")
	await t.accept_commission("fence")
	await t.walk(t.cm.gap_point(1) + Vector2(0, -20))
	await frames(20)
	await shot("10_fence_before")
	for i in 3:
		await t.walk(t.cm.gap_point(i))
		await tap(KEY_E)
		await frames(3)
	await t.walk(t.cm.gap_point(1) + Vector2(0, -20))
	await frames(40)
	await shot("11_fence_after")
	await t.turn_in_commission("fence")
	# 13 the HUD list (a 委托 taken) and 12 the 门派簿
	var k := String(t.cm.offers[0]["kind"]) if String(t.cm.offers[0]["state"]) == "open" else String(t.cm.offers[1]["kind"])
	await t.accept_commission(k)
	await t.board([KEY_1, KEY_2])
	await teleport(Vector2(1180, 1700))
	await frames(60)
	await shot("13_hud_tasks")
	await tap(KEY_B)
	await frames(6)
	await shot("12_sect_book")
	await tap(KEY_ESCAPE)
	await frames(3)
	# 14 Esc page 4
	await tap(KEY_ESCAPE)
	for i in 3:
		await tap(KEY_RIGHT)
	await process_frame
	await process_frame
	await shot("14_esc_tips4")
	await tap(KEY_ESCAPE)
	# 15 the longest spoken line of the data (one page), 16 / 17 a long speech in two pages (补充: paging)
	await teleport(t.jh.board_point + Vector2(-30, 36))
	var best: Dictionary = {}
	for it in t.all_lines():
		if (it[1] as Array).is_empty() and it[0].has("who") and String(it[0]["text"]).length() > String(best.get("text", "")).length():
			best = it[0]
	t.story.data["scenes"]["T-最长"] = [{"who": best["who"], "text": best["text"]}]
	t.story.play("T-最长")
	await frames(3)
	await settle_dialogue()
	await shot("15_longest_line")
	await t.finish()
	t.story.data["scenes"]["T-分页"] = [{"who": "tiger", "text": t.long_speech()}]
	t.story.play("T-分页")
	await frames(3)
	await settle_dialogue()
	await frames(30)
	await shot("16_paging_page1")
	await tap(KEY_E)
	await settle_dialogue()
	await frames(30)
	await shot("17_paging_page2")
	await t.finish()
	# 18 修复 v1: the window shrinks while a long line is on screen - the box lays the text out again
	root.size = Vector2i(1920, 810)
	await frames(6)
	t.story.data["scenes"]["T-缩放"] = [{"who": "tiger", "text": t.long_speech()}]
	t.story.play("T-缩放")
	await frames(3)
	await settle_dialogue()
	await shot("18a_dialogue_wide_window")
	root.size = Vector2i(1000, 560)
	await frames(8)
	await settle_dialogue()
	await shot("18b_dialogue_after_shrinking")
	await t.finish()
	root.size = Vector2i(1440, 810)
	await frames(6)
	await t.ss._free_game()
	SaveGame.erase()
	print("shots done")
	quit(0)
