extends SceneTree
## v2 screenshots (time of day, minimap, objective flow) -> screenshots/v2_*.png.  Needs a window:
##   godot --path game2d -s tests/shots_v2.gd        (tools/screenshots_v2.sh)
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
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func place(p: Vector2, dir := "down") -> void:
	player.global_position = p
	player.velocity = Vector2.ZERO
	player.facing = dir
	await frames(8)


func press_e() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(3)


func _run() -> void:
	await frames(10)
	player = main.player
	main.hud.toggle_hint()
	main.daynight.running = false
	var hall := Vector2(30 * T, 21 * T + 20)
	var periods := [["01_dawn_0630", 6.5], ["02_noon_1200", 12.0], ["03_dusk_1800", 18.0], ["04_night_2130", 21.5], ["05_deepnight_0200", 2.0]]
	for p in periods:
		main.daynight.set_hour(p[1])
		await place(hall, "up")
		await shot("v2_time_" + p[0] + "_hall")
	for p in periods:
		main.daynight.set_hour(p[1])
		await place(Vector2(31 * T + 16, 31 * T + 20), "up")
		await shot("v2_time_" + p[0] + "_yard")
	main.daynight.set_hour(21.5)
	await place(Vector2(32 * T + 16, 40 * T + 24), "up")
	await shot("v2_night_gate")
	await place(Vector2(15 * T, 44 * T + 16), "right")
	await shot("v2_night_mountain_road")
	main.daynight.set_hour(8.0)
	# objective flow
	main.objectives.reset()
	await place(Vector2(data_spawn().x, data_spawn().y), "down")
	await shot("v2_flow_1_start_morning")
	var fox: Npc = main.npcs.filter(func(n): return n.id == "fox")[0]
	await place(fox.global_position + Vector2(-6, 26), "up")
	await shot("v2_flow_2_near_shixiong")
	await press_e()
	await shot("v2_flow_3_after_talk_shixiong")
	var crane: Npc = main.npcs.filter(func(n): return n.id == "crane")[0]
	await place(crane.global_position + Vector2(-6, 26), "up")
	await shot("v2_flow_4_near_shifu")
	await press_e()
	await shot("v2_flow_5_done")
	await create_timer(2.0).timeout
	await shot("v2_flow_6_done_after_toast")
	quit()


func data_spawn() -> Vector2:
	return Vector2(main.data["spawn"]["x"], main.data["spawn"]["y"])
