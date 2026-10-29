extends SceneTree
## 打磨 v1 screenshots -> screenshots/polish_*.png (needs a window, ~90 s):  tools/screenshots_polish.sh
##   01-04 opening: asleep / bucket filling / overflow + puddle / woken     05 objective 擦干地上的水 (star on the rag)
##   06 hint without the rag   07 rag taken   08-09 wipes 1 and 2   10 pouring (S1-擦水渍)   11 看看桌上的字条
##   12 wardrobe panel   13 dorm corner (broom + rag)   14 the leak onto 师兄's pillow (wet mark)
##   20-24 minimap: outdoors / indoors / star on the rim / transparent over him / rim towards the doorway indoors
##   30-44 indoor light: every room at noon, dusk and night (mean brightness printed)
##   50-55 occlusion: dorm roof, hall roof, compound wall, tree canopy, kitchen roof, an NPC; 56 = the dorm roof with the
##   fade switched off (the old look) for comparison
var main: Node
var story: Story
var it: Interiors
var out_dir := "res://screenshots/"


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


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
	await frames(4)


func finish() -> void:
	var n := 0
	while story.busy and n < 300:
		if story.dialogue.active:
			await tap(KEY_E if not story.dialogue.choosing else KEY_1)
		else:
			await frames(2)
		n += 1


func until_line(text_part: String) -> void:
	for i in 300:
		if story.dialogue.active and text_part in story.dialogue.full_text and not story.dialogue.is_typing():
			return
		if story.dialogue.active:
			await tap(KEY_E)
		else:
			await frames(2)


func place(pos: Vector2, facing := "down") -> void:
	var p: Player = main.player
	p.global_position = pos
	p.facing = facing
	p.sprite.play("idle_" + facing)
	await frames(6)


func thing(id: String) -> Vector2:
	for x in story.data["interactables"]:
		if x["id"] == id:
			return story._thing_pos(x)
	return Vector2.ZERO


func star_visible() -> void:
	for i in 120:
		await frames(1)
		if main.hud.minimap.star_shown:
			return


## Mean luminance of the middle of the screen (the floor / people), 0..1.
func mean_lum(img: Image) -> float:
	var s := 0.0
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int(h * 0.3), int(h * 0.85), 4):
		for x in range(int(w * 0.15), int(w * 0.85), 4):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return s / maxf(1.0, float(n))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	story = main.story
	it = main.interiors
	main.daynight.running = false
	await frames(70)
	await shot("polish_01_opening_asleep_bucket")
	for i in 40:
		if not (story.dialogue.active and story.dialogue.kind == "旁白"):
			break
		await tap(KEY_E)
	for i in 400:
		if it.water_level >= 0.85:
			break
		await physics_frame
	await shot("polish_02_bucket_filling")
	await until_line("哗啦")
	await tap(KEY_E)
	for i in 400:
		if it.puddle_size >= 0.7:
			break
		await physics_frame
	await shot("polish_03_bucket_overflow_puddle")
	await until_line("什么声音")
	await shot("polish_04_woken_sitting_up")
	await finish()
	await frames(20)
	await star_visible()
	await shot("polish_05_objective_wipe_star_on_rag")
	# without the rag
	await place(thing("puddle") + Vector2(0, 6), "up")
	await tap(KEY_E)
	await frames(6)
	await shot("polish_06_hint_need_rag")
	await place(thing("rag") + Vector2(0, 4), "left")
	await frames(4)
	await shot("polish_13_dorm_corner_broom_rag")
	await tap(KEY_E)
	await until_line("拧一拧")
	await shot("polish_07_rag_taken")
	await finish()
	await place(thing("puddle") + Vector2(0, 8), "up")
	await tap(KEY_E)
	await frames(30)
	await shot("polish_08_wipe_1")
	await tap(KEY_E)
	await frames(30)
	await shot("polish_09_wipe_2")
	await tap(KEY_E)
	await until_line("放回原处")
	await shot("polish_10_poured_bucket")
	await finish()
	await frames(10)
	await star_visible()
	await shot("polish_11_objective_note")
	await place(it.world_point("dorm_main", Vector2(340, 150)), "up")
	await frames(90)
	await shot("polish_14_leak_on_senior_pillow")
	# wardrobe
	await place(thing("wardrobe") + Vector2(0, 4), "up")
	await tap(KEY_E)
	await until_line("一件比一件旧")
	await shot("polish_12_wardrobe_panel")
	await finish()
	# minimap
	story.flags["floor_wiped"] = true
	story.set_stage(2)
	await place(Vector2(1010, 980), "up")
	await star_visible()
	await shot("polish_20_minimap_outdoors")
	await place(it.world_point("hall", Vector2(470, 250)), "left")
	await star_visible()
	await shot("polish_21_minimap_indoors_hall")
	story.set_stage(5)       # 沿山路去村口: far away
	await place(Vector2(1010, 980), "up")
	await star_visible()
	await shot("polish_22_minimap_star_on_rim")
	await place(Vector2(40, 60), "up")
	await frames(30)
	await shot("polish_23_minimap_transparent_over_player")
	story.set_stage(1)
	await place(it.world_point("kitchen", Vector2(330, 170)), "up")
	await star_visible()
	await shot("polish_24_minimap_indoor_rim_towards_door")
	# indoor light
	var n := 30
	var spots := {"dorm_main": Vector2(240, 170), "hall": Vector2(330, 220), "kitchen": Vector2(250, 170),
		"dorm_old": Vector2(272, 200), "storage": Vector2(150, 190)}
	for room in spots:
		for pair in [["noon", 12.0], ["dusk", 18.0], ["night", 23.0]]:
			main.daynight.set_hour(pair[1])
			await place(it.world_point(room, spots[room]), "up")
			await frames(40)
			var img := await shot("polish_%d_light_%s_%s" % [n, room, pair[0]])
			print("  brightness %s %s: %.3f" % [room, pair[0], mean_lum(img)])
			n += 1
	main.daynight.set_hour(10.0)
	# occlusion
	var occ: Occlusion = main.occlusion
	# (房子整栋实心 v1: the roofs are solid and no longer fade - see shots_building.gd; only the compound wall and the tree)
	var picks := [["compound wall", "gate", "", -1, 72.0], ["tree canopy", "tree", "trees", 614, INF]]
	n = 50
	var first_spot := Vector2.INF
	var tree_idx := -1
	for pk in picks:
		var idx := _entry_for(pk[1], pk[2], pk[3])
		var st := _behind(idx, occ.entries[idx]["rect"].position.x + pk[4] if pk[4] != INF else INF)
		await place(st, "up")
		await frames(30)
		await shot("polish_%d_occlusion_%s" % [n, String(pk[0]).replace(" ", "_")])
		if first_spot == Vector2.INF:
			first_spot = st
		if pk[0] == "tree canopy":
			tree_idx = idx
		n += 1
	var duck: Npc = story._npc("duck")
	var home := duck.global_position
	var tst := _behind(tree_idx)
	duck.global_position = tst + Vector2(18, 0)
	await place(tst + Vector2(-30, 60), "up")
	await frames(30)
	await shot("polish_55_occlusion_npc_behind_tree")
	duck.global_position = home
	# the old look for comparison: fade switched off
	await place(first_spot, "up")
	await frames(30)
	occ.set_process(false)
	for idx in occ.active.keys():
		occ.entries[idx]["sprite"].material = null
	await frames(4)
	await shot("polish_56_occlusion_off_old_look_compound_wall")
	occ.set_process(true)
	quit()


func _entry_for(type: String, area: String, x: int) -> int:
	var occ: Occlusion = main.occlusion
	for o in main.data["objects"]:
		if o["type"] != type or (area != "" and o["area"] != area) or (x >= 0 and int(o["x"]) != x):
			continue
		for i in occ.entries.size():
			if (occ.entries[i]["rect"] as Rect2).position == Vector2(o["x"], o["y"]):
				return i
	return -1


func _free(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var r := RectangleShape2D.new()
	r.size = Player.FOOT_SIZE
	q.shape = r
	q.transform = Transform2D(0.0, p + Vector2(0, -2))
	q.collision_mask = 1
	q.exclude = [main.player.get_rid()]
	return main.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _behind(idx: int, x_max := INF) -> Vector2:
	var occ: Occlusion = main.occlusion
	var s: Sprite2D = occ.sprite_of(idx)
	var rect: Rect2 = occ.entries[idx]["rect"]
	var best := Vector2.INF
	var best_c := 0.0
	var y := rect.position.y + 2.0
	while y < s.position.y - 1.0:
		var x := rect.position.x + 8.0
		while x < minf(rect.end.x - 8.0, x_max):
			var f := Vector2(x, y)
			if it.room_at(f) == "" and x > 16 and _free(f):
				var cv := occ.coverage(idx, f)
				if cv > best_c + 0.001 or (absf(cv - best_c) <= 0.001 and best != Vector2.INF and absf(x - rect.get_center().x) < absf(best.x - rect.get_center().x)):
					best_c = cv
					best = f
			x += 4.0
		y += 2.0
	return best
