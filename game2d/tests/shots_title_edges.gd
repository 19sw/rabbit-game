extends SceneTree
## 封面两侧延伸画 v1 screenshots from the game's own window at several widths (2x scale so even 21:9 fits a laptop
## screen):  godot --path game2d -s tests/shots_title_edges.gd [-- <out dir>]
## 16:9 960x540, ~19.5:9 1170x540, 21:9 1260x540 and 4:3 960x720 (unchanged: no extension in view)
## -> <out dir>/title_edges_<name>.png (default res://screenshots/).
var title: TitleScreen
var out_dir := "res://screenshots/"
const SIZES := [[Vector2i(960, 540), "16x9"], [Vector2i(1170, 540), "19.5x9"], [Vector2i(1260, 540), "21x9"],
	[Vector2i(960, 720), "4x3"]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0].trim_suffix("/") + "/"
	title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for s in SIZES:
		DisplayServer.window_set_size(s[0])
		root.size = s[0]
		await frames(20)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path: String = out_dir + "title_edges_%s.png" % s[1]
		img.save_png(path)
		var vis := title.get_viewport().get_visible_rect().size
		print("saved %s %s (view %dx%d)" % [path, img.get_size(), int(vis.x), int(vis.y)])
	quit()
