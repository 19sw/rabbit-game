extends SceneTree
## 启动画面 screenshots -> screenshots/title_*.png and screenshots/title_anim/ (needs a window, ~25 s):
##   godot --path game2d -s tests/shots_title.gd        (tools/screenshots_title.sh also builds the GIF)
## title (several frames for the GIF), the selected-button highlight (keyboard and mouse), the help page,
## the fade, and the spawn right after 开始游戏.
var title: TitleScreen
var out_dir := "res://screenshots/"


func _initialize() -> void:
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())
	return img


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
	await frames(2)


func mouse_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await frames(3)


## Screen position (window pixels) of a point in the title's 480x270 picture.
func to_screen(p: Vector2) -> Vector2:
	return title.get_viewport().get_canvas_transform() * p * (Vector2(root.size) / title.get_viewport().get_visible_rect().size)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir + "title_anim"))
	await frames(30)
	await shot("title_01_screen")
	# animation frames (0.25 s apart) for the GIF: leaves, mist, motes, ripple all move
	for i in 24:
		var img := root.get_texture().get_image()
		await RenderingServer.frame_post_draw
		img = root.get_texture().get_image()
		img.save_png(out_dir + "title_anim/frame_%02d.png" % i)
		await create_timer(0.25).timeout
	print("saved 24 animation frames")
	await shot("title_02_screen_later")
	# keyboard: Down selects 按键与玩法
	await tap(KEY_DOWN)
	await frames(4)
	await shot("title_03_highlight_help_keyboard")
	# mouse: hover 开始游戏
	var b := title.button("start")
	await mouse_move(to_screen(b.position + b.size * 0.5))
	await frames(4)
	await shot("title_04_highlight_start_mouse")
	# help page (same content as the Esc page)
	title.select(title.index_of("help"))
	await tap(KEY_ENTER)
	await frames(6)
	await shot("title_05_help_page")
	await tap(KEY_ESCAPE)
	await frames(4)
	await shot("title_06_back_from_help")
	# Esc on the title: nothing happens
	await tap(KEY_ESCAPE)
	await frames(6)
	await shot("title_07_esc_on_title_nothing")
	# 开始游戏 -> fade -> spawn
	title.select(title.index_of("start"))
	await tap(KEY_ENTER)
	await create_timer(0.35).timeout
	await shot("title_08_fading_out")
	var main: Node = null
	for i in 240:
		await process_frame
		if current_scene != null and current_scene.name == "Main":
			main = current_scene
			break
	await create_timer(0.25).timeout
	await shot("title_09_fading_in_game")
	await create_timer(1.0).timeout
	await shot("title_10_after_start_spawn")
	print("after start: scene=%s spawn=%s clock=%s" % [current_scene.name, main.player.global_position if main else null,
		main.daynight.clock_text() if main else ""])
	quit()
