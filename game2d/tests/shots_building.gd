extends SceneTree
## 房子整栋实心 v1 screenshots -> screenshots/building_*.png (needs a window, ~40 s):  tools/screenshots_building.sh
##   01 the client's spot: pushed down at the old disciples' house ridge (x 260), she stops outside     02-03 the same at the
##   west eave tip (176) / east spire (344)     04 main hall, from its west side     05 north dorm, pushing at the roof from the
##   north     06 kitchen from the north     07 hut from the west     08 library ruin from the west     09 山门 passage (the
##   gate tower still fades)     10 tree canopy (still fades)
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


func place(pos: Vector2, facing := "down") -> void:
	var p: Player = main.player
	p.global_position = pos
	p.facing = facing
	p.sprite.play("idle_" + facing)
	await frames(6)


## Start at `from`, hold the key for `secs` real physics seconds, then settle.
func push(from: Vector2, code: Key, facing: String, secs := 1.2) -> void:
	await place(from, facing)
	key(code, true)
	await frames(int(secs * 60.0))
	key(code, false)
	await frames(30)


## Start at `from`, hold `code` until her feet pass `stop_y` (or `frames` frames when stop_y = 0), then shoot.
func walk_shot(from: Vector2, code: Key, facing: String, stop_y: float, name: String, nframes := 400) -> void:
	await place(from, facing)
	key(code, true)
	for i in nframes:
		await physics_frame
		var y: float = main.player.global_position.y
		if stop_y > 0.0 and ((code == KEY_W and y <= stop_y) or (code == KEY_S and y >= stop_y)):
			break
	key(code, false)
	await frames(2)
	print(name, " feet ", main.player.global_position)
	await shot(name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	story = main.story
	main.daynight.running = false
	main.daynight.set_hour(11.0)
	await frames(70)
	for i in 60:
		if not story.busy:
			break
		if story.dialogue.active:
			key(KEY_E, true)
			await frames(2)
			key(KEY_E, false)
			await frames(4)
		else:
			await frames(2)
	story.enter_sandbox()
	main.combat.bandits_enabled = false
	await frames(10)
	await push(Vector2(260, 1030), KEY_S, "down")
	print("client spot feet ", main.player.global_position)
	await shot("building_01_client_spot_old_dorm_ridge")
	await push(Vector2(176, 1030), KEY_S, "down")
	print("west tip feet ", main.player.global_position)
	await shot("building_02_old_dorm_west_eave")
	await push(Vector2(344, 1030), KEY_S, "down")
	print("east tip feet ", main.player.global_position)
	await shot("building_03_old_dorm_east_spire")
	await push(Vector2(800, 560), KEY_D, "right")
	await shot("building_04_main_hall_west_side")
	await push(Vector2(300, 740), KEY_S, "down")
	await shot("building_05_north_dorm_from_north")
	await push(Vector2(1550, 740), KEY_S, "down")
	await shot("building_06_kitchen_from_north")
	await push(Vector2(1540, 1862), KEY_D, "right")
	await shot("building_07_hut_from_west")
	await push(Vector2(165, 560), KEY_D, "right")
	await shot("building_08_library_ruin_from_west")
	await place(Vector2(1040, 1215), "up")
	await frames(40)
	await shot("building_09_gate_passage_still_fades")
	var occ: Occlusion = main.occlusion
	for idx in occ.entries.size():
		if String(occ.entries[idx]["type"]) == "tree" and (occ.entries[idx]["rect"] as Rect2).position.x > 600:
			var rect: Rect2 = occ.entries[idx]["rect"]
			await place(Vector2(rect.get_center().x, rect.end.y - 8), "up")
			break
	await frames(40)
	await shot("building_10_tree_canopy_still_fades")
	# 房子整栋实心 v1 fix 2: the north wall moved one tile north - she walks the new walkway, the gap path and the breaches
	await walk_shot(Vector2(312, 416), KEY_W, "up", 370.0, "building_11_breach_V2_walking_through_wall")
	await walk_shot(Vector2(312, 416), KEY_W, "up", 334.0, "building_12_breach_V2_north_side")
	await walk_shot(Vector2(284, 416), KEY_W, "up", 370.0, "building_13_breach_V1_walking_through_wall")
	await walk_shot(Vector2(284, 416), KEY_W, "up", 334.0, "building_14_breach_V1_north_side")
	await walk_shot(Vector2(150, 400), KEY_D, "right", 0.0, "building_15_walkway_behind_ruin_west_pocket_walking_east", 70)
	await walk_shot(Vector2(800, 400), KEY_D, "right", 0.0, "building_16_walkway_behind_hall_walking_east", 90)
	await walk_shot(Vector2(1010, 410), KEY_W, "up", 380.0, "building_17_back_gap_path_going_up")
	await walk_shot(Vector2(1010, 410), KEY_W, "up", 330.0, "building_18_back_gap_path_in_the_grove")
	quit()
