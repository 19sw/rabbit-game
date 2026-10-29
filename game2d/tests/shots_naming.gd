extends SceneTree
## 改名与起名 v1 screenshots -> screenshots/naming_*.png (needs a window, ~30 s):
##   godot --path game2d -s tests/shots_naming.gd          (tools/screenshots_naming.sh)
##   01 title (中文)   02 title (English)   03 the naming box after 新游戏 with 阿糯 typed   04 a line with the name
##   05 the Esc page's 改名 box   06 the 门派簿 with the name
## Uses the test save slot (user://test_save.json), never the player's.

var out_dir := "res://screenshots/"
var title: TitleScreen


func _initialize() -> void:
	# a window behind other windows gets almost no vsync ticks on macOS (about 1 frame a second): no vsync, 60 fps cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	# (and a covered window is not drawn at all: kept on top for the ~40 s of the run)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	root.size = Vector2i(1440, 810)
	SaveGame.erase()
	Opening.enabled = false
	Lang.set_lang("zh")
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(2)


func type_char(ch: String) -> void:
	var ev := InputEventKey.new()
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	ev = ev.duplicate()
	ev.pressed = false
	ev.unicode = 0
	Input.parse_input_event(ev)
	await frames(1)


func new_title() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
		await process_frame
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await frames(40)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await new_title()
	await shot("naming_01_title_zh")
	Lang.set_lang("en")
	await frames(10)
	await shot("naming_02_title_en")
	Lang.set_lang("zh")
	await frames(10)
	title.select(title.index_of("start"))
	await tap(KEY_ENTER)
	await frames(10)
	title.naming.line.select_all()
	for ch in "阿糯":
		await type_char(ch)
	await frames(20)
	await shot("naming_03_box_new_game")
	await tap(KEY_ENTER)
	print("shots: confirmed name=", PlayerName.value(), " starting=", title.starting)
	var main: Node = null
	for i in 240:
		await process_frame
		if current_scene != null and current_scene.name == "Main":
			main = current_scene
			break
	if main == null:
		print("no game")
		quit(1)
		return
	print("shots: game")
	await frames(30)
	var story: Story = main.story
	var dlg: Dialogue = story.dialogue
	for i in 1500:
		if dlg.active and dlg.kind == "speaker" and String(dlg.entry.get("who", "")) == "rabbit" and not dlg.is_typing():
			break
		if dlg.active and not dlg.is_typing() and i % 10 == 0:
			await tap(KEY_E)
		else:
			await frames(1)
	print("shots: line ", dlg.kind, " ", dlg.speaker_name)
	await frames(30)
	await shot("naming_04_line_with_name")
	while story.busy:
		await tap(KEY_E)
	await frames(10)
	# 厨娘 says his name
	story.play("S4-厨娘-任务前")
	await frames(90)
	await shot("naming_04b_npc_line_with_name")
	while story.busy:
		await tap(KEY_E)
	await frames(10)
	# Esc -> 改名（R）
	await tap(KEY_ESCAPE)
	await frames(10)
	await tap(KEY_R)
	await frames(6)
	main.pause_menu.rename_panel.line.select_all()
	for ch in "白小楼":
		await type_char(ch)
	await frames(20)
	await shot("naming_05_esc_rename")
	await tap(KEY_ENTER)
	await frames(10)
	await shot("naming_05b_esc_page_renamed")
	await tap(KEY_ESCAPE)
	await frames(10)
	story.book_unlocked = true
	story.open_book()
	await frames(20)
	await shot("naming_06_sect_book")
	SaveGame.erase()
	quit(0)
