extends SceneTree
## 开场过场动画 v1 screenshots (needs a window, ~40 s):  godot --path game2d -s tests/shots_opening.gd
## (tools/screenshots_opening.sh). Writes screenshots/opening_<zh|en>_<1..7>.png (each picture mid-move with its whole
## narration) and screenshots/opening_title_replay_<zh|en>.png (the 「重看序幕」 button on the title).
var out_dir := "res://screenshots/"
var title: TitleScreen


func _initialize() -> void:
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
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		title = load("res://scenes/title.tscn").instantiate()
		root.add_child(title)
		current_scene = title
		await frames(40)
		await shot("opening_title_replay_" + lang)
		title.replay()
		var o: Opening = null
		for i in 120:
			await process_frame
			o = title.opening
			if o != null:
				break
		await create_timer(1.2).timeout
		for i in 7:
			# halfway through the picture's camera move, every line shown (picture 4: after both lightning flashes)
			o.t = float(o.scene()["seconds"]) * 0.55
			o.reveal_all()
			if i == 3:
				await create_timer(0.8).timeout
			await frames(2)
			await shot("opening_%s_%d" % [lang, i + 1])
			o.next()
			await create_timer(1.2).timeout      # (real seconds: the crossfade is over whatever the frame rate)
		o.skip()
		await frames(90)
		title.queue_free()
		await frames(5)
	Lang.set_lang("zh")
	quit()
