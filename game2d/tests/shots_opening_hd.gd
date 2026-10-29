extends SceneTree
## 坐姿-高清过场-运镜 方案 v1 screenshots of the HD opening (needs a window, ~30 s):
##   godot --path game2d -s tests/shots_opening_hd.gd -- [out_dir]
## Writes opening_hd_<zh>_<n>.png at 1440x810 (the default 3x window): every picture with its whole narration -
## picture 1 halfway through its pan, picture 4 just after the thunder flash, picture 7 at the end of its push-in.
## out_dir defaults to res://screenshots/.
var out_dir := "res://screenshots/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0].trim_suffix("/") + "/"
	root.size = Vector2i(1440, 810)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func _run() -> void:
	await frames(5)
	Lang.set_lang("zh")
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await frames(30)
	title.replay()
	var o: Opening = null
	for i in 120:
		await process_frame
		o = title.opening
		if o != null:
			break
	await create_timer(1.2).timeout
	for i in 7:
		var secs := float(o.scene()["seconds"])
		o.t = secs * 0.5
		if i == 6:
			o.t = secs - 0.3                       # push-in finished: the held close-up
		elif i == 3:
			o.t = 1.0                              # let the thunder flash + shake play out first
			await create_timer(0.8).timeout
		o.reveal_all()
		o.speed = 0.0                              # freeze the timeline for the picture
		await frames(3)
		await shot("opening_hd_zh_%d" % (i + 1))
		o.speed = 1.0
		o.next()
		await create_timer(1.2).timeout
	o.skip()
	await frames(90)
	title.queue_free()
	await frames(5)
	quit()
