extends SceneTree
## 两条路小样 v1 screenshots -> screenshots/sample_*.png (the Godot game window only; ~2 min):  tools/screenshots_sample.sh
##   01 继续逛逛 -> 本钱 toast + coin counter   02 老周 at the dorm door   03 the repair question   04 not enough coins
##   05/06 dorm roof outside before / after     07/08 dorm room before / after (leak, bucket, puddle gone)
##   09/10 old dorm before / after              11/12 kitchen outside before / after (+ food stall)   13/14 kitchen room
##   15 the trial board prompt   16 the trial running (clock, lit pole, dummies)   17 a dummy hit   18 the medal screen
##   19 Esc page during the trial (放弃试炼) + 20 tips page 2   21 stall income toast   22 门派簿
##   23 title with 继续游戏   24 新游戏 overwrite question   25 title without a save (greyed)   26 broken save message
## Saves go to user://test_save.json (a SceneTree script), never the player's slot.
var main: Node
var story: Story
var smp: Sample
var out_dir := "res://screenshots/"


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(4)


func use(m: Node) -> void:
	main = m
	story = m.story
	smp = m.sample


func new_game() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	use(m)
	main.daynight.running = false
	await frames(2)


func finish(choice := KEY_1) -> void:
	var n := 0
	while story.busy and n < 400:
		await tap(KEY_E if not story.dialogue.choosing else choice)
		n += 1


## Advances the running conversation until a line containing `part` is fully shown (choices answered with `choice`).
func until_line(part: String, choice := KEY_1) -> void:
	for i in 300:
		var d := story.dialogue
		if d.active and part in d.full_text and not d.is_typing():
			return
		if not story.busy:
			return
		if d.choosing and not part in d.full_text:
			await tap(choice)
		elif d.active and not d.is_typing():
			await tap(KEY_E)
		else:
			await frames(2)


func put(p: Vector2, facing := "down") -> void:
	var pl: Player = main.player
	pl.velocity = Vector2.ZERO
	pl.global_position = p
	pl.facing = facing
	pl.sprite.play("idle_" + facing)
	await frames(3)


func near(n: Node2D) -> void:
	for o in [Vector2(0, 26), Vector2(-26, 0), Vector2(26, 0), Vector2(0, -26)]:
		var q := PhysicsShapeQueryParameters2D.new()
		var r := RectangleShape2D.new()
		r.size = Player.FOOT_SIZE
		q.shape = r
		q.transform = Transform2D(0.0, n.global_position + o + Vector2(0, -2))
		q.collision_mask = 1
		q.exclude = [main.player.get_rid()]
		if main.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty():
			await put(n.global_position + o, "up" if o.y > 0 else ("down" if o.y < 0 else ("right" if o.x < 0 else "left")))
			return


func unlock() -> void:
	for f in ["bandits_defeated", "puzzle_solved", "tiles_found"]:
		story.flags[f] = true
	story.set_stage(8)
	await near(story._npc("crane"))
	await tap(KEY_E)
	# 新手指引 v1: no 序章 · 完 page / 继续逛逛 - the game goes straight on, then 师父's guide line
	for i in 900:
		if story.sect_book.is_open:
			await tap(KEY_ESCAPE)
		elif story.dialogue.active:
			await tap(KEY_E)
		elif main.sample.unlocked and not story.busy and not main.guide._intro_pending:
			break
		else:
			await frames(2)


func repair(who: String, shots: Array) -> void:
	await near(story._npc(who))
	await tap(KEY_E)
	await until_line("铜钱")          # the question line
	if shots.size() > 0:
		await shot(shots[0])
	await finish(KEY_1)


func _run() -> void:
	SaveGame.erase()
	await new_game()
	await finish()      # the opening
	main.daynight.set_hour(10.0)
	await unlock()
	await frames(10)
	await shot("sample_01_unlock_coins_toast")
	var it: Interiors = main.interiors
	# 老周 + the roof question + a shortfall
	await put(smp.mouse.global_position + Vector2(-40, 30), "right")
	await frames(20)
	await shot("sample_02_mouse_at_dorm_door")
	await put(Vector2(300, 990), "up")
	await shot("sample_05_roof_outside_before")
	await put(it.world_point("dorm_main", Vector2(300, 140)), "up")
	await frames(40)
	await shot("sample_07_dorm_room_before")
	await put(it.world_point("dorm_old", Vector2(240, 160)), "up")
	await shot("sample_09_old_dorm_before")
	await put(Vector2(1560, 1000), "up")
	await shot("sample_11_kitchen_outside_before")
	await put(it.world_point("kitchen", Vector2(300, 150)), "up")
	await shot("sample_13_kitchen_room_before")
	smp.coins = 12
	smp._refresh_coins()
	await near(smp.mouse)
	await tap(KEY_E)
	await until_line("花 30 铜钱")
	await shot("sample_03_repair_question")
	await tap(KEY_1)
	await until_line("还差")
	await shot("sample_04_not_enough_coins")
	await finish()
	smp.coins = 200
	smp._refresh_coins()
	await repair("mouse", [])
	await repair("dog", [])
	await repair("bear", [])
	await put(Vector2(300, 990), "up")
	await shot("sample_06_roof_outside_after")
	await put(it.world_point("dorm_main", Vector2(300, 140)), "up")
	await frames(40)
	await shot("sample_08_dorm_room_after")
	await put(it.world_point("dorm_old", Vector2(240, 160)), "up")
	await shot("sample_10_old_dorm_after")
	await put(Vector2(1560, 1000), "up")
	await shot("sample_12_kitchen_outside_after_stall")
	await put(it.world_point("kitchen", Vector2(300, 150)), "up")
	await shot("sample_14_kitchen_room_after")
	# the trial
	var tr: PlumTrial = smp.trial
	await put(tr.board_point() + Vector2(0, 14), "up")
	await shot("sample_15_trial_board_prompt")
	await tap(KEY_E)
	await finish(KEY_1)
	await frames(80)
	for i in 4:
		await put(tr.step_point(i), "right")
	await put(tr.step_point(4) + Vector2(-90, 30), "right")
	await frames(30)
	await shot("sample_16_trial_running")
	var foot: Vector2 = tr.card.dummy_points[1]
	main.player.hp = 70
	await put(foot + Vector2(-26, 0), "right")
	tr.angles[1] = PI + deg_to_rad(12.0)
	await frames(12)
	await shot("sample_17_trial_dummy_hit")
	await tap(KEY_ESCAPE)
	await process_frame
	await shot("sample_19_esc_page_abandon")
	await tap(KEY_RIGHT)
	await process_frame
	await shot("sample_20_esc_tips_page2")
	await tap(KEY_LEFT)
	await tap(KEY_ESCAPE)
	for i in range(tr.current, tr.card.pole_points.size()):
		if i == tr.card.pole_points.size() - 1:
			tr.elapsed = 37.6
		await put(tr.step_point(i), "right")
	await frames(20)
	await shot("sample_18_trial_result_gold")
	await tap(KEY_E)
	# stall income
	await put(Vector2(1600, 1060), "up")
	main.daynight.set_hour(7.95)
	await frames(3)
	main.daynight.advance_hours(0.1)        # past 08:00 -> the stall pays, the toast shows
	await frames(12)
	await shot("sample_21_stall_income_toast")
	await frames(120)
	await tap(KEY_B)
	await frames(4)
	await shot("sample_22_sect_book")
	await tap(KEY_E)
	await frames(30)
	smp.save_now("shots")
	# the title with a save
	main.queue_free()
	await process_frame
	var t: TitleScreen = load("res://scenes/title.tscn").instantiate()
	root.add_child(t)
	current_scene = t
	await frames(40)
	await shot("sample_23_title_continue")
	t.select(t.index_of("start"))
	await tap(KEY_ENTER)
	await frames(4)
	await shot("sample_24_new_game_confirm")
	await tap(KEY_ESCAPE)
	# a broken save -> fresh game with the message
	var f := FileAccess.open(SaveGame.path(), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	t.select(t.index_of("continue"))
	await tap(KEY_ENTER)
	for i in 200:
		await process_frame
		if current_scene != null and current_scene.name == "Main":
			break
	await create_timer(0.9).timeout
	await shot("sample_26_broken_save_message")
	current_scene.queue_free()
	for n in root.get_children():
		if n.name == "TitleFadeIn":
			n.queue_free()
	await process_frame
	var t2: TitleScreen = load("res://scenes/title.tscn").instantiate()
	root.add_child(t2)
	current_scene = t2
	await frames(30)
	await shot("sample_25_title_no_save")
	SaveGame.erase()
	quit()
