extends SceneTree
## 序章 v1 screenshots -> screenshots/story_*.png (needs a window, ~40 s):  tools/screenshots_story.sh
##   01 opening conversation   02 a choice   03 bandits' opening lines   04 the wind after a right stone
##   05 the parted bamboo      06 the old cloth   07 门派簿   08 序章 · 完   (+ 09 stele inscription, 10 walking bubble)
var main: Node
var story: Story
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


func new_game() -> void:
	if main != null:
		main.queue_free()
		await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	story = main.story
	main.daynight.running = false
	await frames(2)


func finish() -> void:
	var n := 0
	while story.busy and n < 300:
		await tap(KEY_E if not story.dialogue.choosing else KEY_1)
		n += 1


## Advance until the line with `text_part` is fully shown.
func until_line(text_part: String) -> void:
	for i in 300:
		if story.dialogue.active and text_part in story.dialogue.full_text:
			break
		await tap(KEY_E)
	story.dialogue.advance()     # complete the typing
	await frames(20)


func place(p: Vector2) -> void:
	main.player.global_position = p
	main.player.velocity = Vector2.ZERO
	await frames(3)


func npc(id: String) -> Npc:
	return story._npc(id)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await new_game()
	await until_line("……又漏了。")
	await shot("story_01_opening_dialogue")
	await finish()
	# 02 choice (师兄)
	await place(npc("fox").global_position + Vector2(0, 26))
	await tap(KEY_E)
	for i in 200:
		if story.dialogue.choosing:
			break
		await tap(KEY_E)
	await frames(10)
	await shot("story_02_choice_dialogue")
	await new_game()
	await finish()
	# 03 bandits' opening lines
	story.set_stage(5)
	main.combat.set_bandits_present(true)
	await place(main.combat.bandits[0].home + Vector2(70, -110))
	await frames(5)
	story.dialogue.advance()
	await frames(10)
	await shot("story_03_bandit_intro")
	await finish()
	# 09 stele + 04 wind
	await new_game()
	await finish()
	story.set_stage(7)
	story.flags["grove_entered"] = true
	await place(story.stele_pos + Vector2(0, 18))
	await tap(KEY_E)
	story.dialogue.advance()
	await frames(10)
	await shot("story_09_stele_inscription")
	await finish()
	await place(story.stones["stone_qing"]["pos"] + Vector2(-10, 18))
	await tap(KEY_E)
	await place((story.stones["stone_qing"]["pos"] + story.stones["stone_moss"]["pos"]) * 0.5 + Vector2(-40, 0))
	await frames(40)
	await shot("story_04_puzzle_wind_hint")
	await frames(60)
	await place(story.stones["stone_moss"]["pos"] + Vector2(-10, 18))
	await tap(KEY_E)
	await frames(60)
	await place(story.stones["stone_crack"]["pos"] + Vector2(0, 18))
	await tap(KEY_E)
	await place(story.gate_center() + Vector2(70, 40))
	await frames(150)
	await shot("story_05_bamboo_parted")
	# 06 old cloth
	await place(Vector2(520, 252))
	for i in 60:
		if story.busy:
			break
		await frames(1)
	await until_line("一块褪色的蓝布")
	await shot("story_06_old_cloth")
	await finish()
	# 07 门派簿 + 08 序章 · 完
	story.flags["spar_won"] = true
	story.flags["bandits_defeated"] = true
	await place(npc("crane").global_position + Vector2(0, 26))
	await tap(KEY_E)
	for i in 400:
		if story.sect_book.is_open:
			break
		await tap(KEY_E)
	await frames(10)
	await shot("story_07_sect_book")
	await tap(KEY_E)
	# 新手指引 v1: no 序章 · 完 page any more - the caption 「序章 · 完」 fades in over the game
	for i in 400:
		if main.guide.caption_showing():
			break
		if story.dialogue.active:
			await tap(KEY_E)
		else:
			await frames(1)
	await frames(20)
	await shot("story_08_prologue_end")
	for i in 400:
		if main.sample.unlocked and not story.busy and not main.guide._intro_pending:
			break
		if story.dialogue.active:
			await tap(KEY_E)
		else:
			await frames(2)
	# 10 walking bubble (师兄 nearby at step 9)
	await frames(5)
	await place(npc("fox").global_position + Vector2(30, 40))
	await frames(20)
	await shot("story_10_walking_bubble")
	quit()
