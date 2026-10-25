extends SceneTree
## Real-render screenshots of key states -> screenshots/*.png (needs a window / GPU, not --headless):
##   godot --path game2d -s tests/shots.gd          (tools/screenshots.sh)
## Window 1440x810 = 3x the 480x270 base view.

const T := 32.0
var main: Node
var player: Player
var out_dir := "res://screenshots/"


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	# optional: SHOTS_ONLY=02 (only names starting with it), SHOTS_PREFIX=demo_ (file name prefix)
	var only := OS.get_environment("SHOTS_ONLY")
	if only != "" and not name.begins_with(only):
		return
	name = OS.get_environment("SHOTS_PREFIX") + name
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func place(p: Vector2, dir := "down") -> void:
	player.global_position = p
	player.velocity = Vector2.ZERO
	player.facing = dir
	await frames(6)


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await frames(10)
	player = main.player
	await create_timer(0.5).timeout
	await shot("01_spawn_dorm_door")
	main.hud.toggle_hint()   # hide the hint for the other pictures
	await place(Vector2(31 * T + 16, 31 * T + 20), "up")
	await shot("02_training_yard")
	# NPC prompt + bubble (师兄 in the training yard)
	var fox: Npc = main.npcs.filter(func(n): return n.id == "fox")[0]
	await place(fox.global_position + Vector2(-6, 26), "up")
	await shot("03_npc_prompt")
	key(KEY_E, true); await frames(2); key(KEY_E, false)
	await create_timer(0.2).timeout
	await shot("04_npc_bubble")
	# dash afterimage
	await place(Vector2(24 * T, 28 * T), "right")
	await frames(30)
	key(KEY_SPACE, true); await frames(3); key(KEY_SPACE, false)
	await create_timer(0.11).timeout
	await shot("05_dash_afterimage")
	await create_timer(0.8).timeout
	# ambience on / off in front of the main hall (2 red lanterns + stone lantern)
	await place(Vector2(30 * T, 21 * T + 20), "up")
	await frames(10)
	await shot("06_ambience_on_hall")
	main.toggle_ambience()
	await frames(4)
	await shot("07_ambience_off_hall")
	main.toggle_ambience()
	await create_timer(2.2).timeout
	await place(Vector2(32 * T + 16, 40 * T + 24), "up")
	await shot("08_ambience_on_gate")
	main.toggle_ambience()
	await frames(4)
	await shot("09_ambience_off_gate")
	main.toggle_ambience()
	await create_timer(2.2).timeout   # let the on/off toast fade
	# occlusion: behind / in front of the dorm roof
	await place(Vector2(10 * T + 16, 24 * T + 18), "up")
	await shot("10_behind_roof_dorm")
	await place(Vector2(10 * T + 16, 29 * T + 10), "down")
	await shot("11_in_front_of_roof_dorm")
	# occlusion: tree canopy (old tree near the library)
	var tree_x := 0.0
	var tree_y := 0.0
	for s in main.world.get_children():
		if s is Sprite2D and s.get_meta("type", "") == "tree" and (s.position + Vector2(s.texture.get_width() * 0.5, 0)).distance_to(Vector2(19 * T + 48, 19 * T)) < 40:
			tree_x = s.position.x + s.texture.get_width() * 0.5
			tree_y = s.position.y
	await place(Vector2(tree_x + 38, tree_y - 14), "up")
	await shot("12_behind_tree_canopy")
	await place(Vector2(tree_x + 20, tree_y + 12), "down")
	await shot("13_in_front_of_tree")
	# walking under the mountain gate roof
	await place(Vector2(32 * T, 39 * T + 24), "up")
	await shot("14_gate_passage")
	await place(Vector2(15 * T, 44 * T + 16), "right")
	await shot("15_mountain_road_bandits")
	await place(Vector2(45 * T + 16, 55 * T + 16), "down")
	await shot("16_village")
	await place(Vector2(30 * T, 5 * T), "up")
	await shot("17_bamboo_grove")
	quit()
