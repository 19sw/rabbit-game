extends SceneTree
## 室内图进游戏 v1 screenshots -> screenshots/interior_*.png (needs a window, ~60 s):  tools/screenshots_interiors.sh
##   01 asleep in bed (the leak drips)   02 (v4) the bucket full   03 sitting up ("……嗯？什么声音……")
##   04 out of bed, objective 看看桌上的字条   05 the note (S1-字条)   06 the door fade (going out)   07 outside the dorm door
##   08 正殿 inside: 师父 before the blurred portrait   09 the portrait line (S3-祖师像)   10 厨房: 厨娘 by the stove
##   11 旧弟子房   12 杂物间   13 藏经阁 door (S5-藏经阁封条)   14 indoor at noon   15 indoor at night   16 outdoor at night
##   17 minimap while indoors (star on the hall door)
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


func finish() -> void:
	var n := 0
	while story.busy and n < 300:
		if story.dialogue.active:
			await tap(KEY_E if not story.dialogue.choosing else KEY_1)
		else:
			await frames(2)
		n += 1


## Advance until the line with `text_part` is fully shown.
func until_line(text_part: String) -> void:
	for i in 200:
		if story.dialogue.active and text_part in story.dialogue.full_text and not story.dialogue.is_typing():
			return
		if story.dialogue.active:
			await tap(KEY_E)
		else:
			await frames(2)


func goto(room: String, local: Vector2, facing := "down") -> void:
	var p: Player = main.player
	p.global_position = main.interiors.world_point(room, local)
	p.facing = facing
	p.sprite.play("idle_" + facing)
	await frames(4)


func near_thing(id: String) -> void:
	for it in story.data["interactables"]:
		if it["id"] == id:
			var pos: Vector2 = story._thing_pos(it)
			main.player.global_position = pos + Vector2(0, 14)
			main.player.facing = "up"
			main.player.sprite.play("idle_up")
	await frames(4)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	story = main.story
	main.daynight.running = false
	await frames(2)
	# 01 asleep, 旁白 滴答——滴答—— while the bucket drip falls
	await frames(70)
	await shot("interior_01_asleep_in_bed")
	for i in 40:          # E through the 旁白 line -> the drop
		if not (story.dialogue.active and story.dialogue.kind == "旁白"):
			break
		await tap(KEY_E)
	# 打磨 v1 (script v4): no drop on his forehead any more - 02 is the bucket filled to the brim (see shots_polish.gd)
	for i in 400:
		if main.interiors.water_level >= 0.99:
			break
		await physics_frame
	await shot("interior_02_bucket_full")
	await until_line("什么声音")
	await shot("interior_03_sitting_up")
	await finish()
	await frames(20)
	await shot("interior_04_out_of_bed_objective")
	# 05 the note (v4: readable once the floor is wiped - the wiping itself is in shots_polish.gd)
	story.flags["has_rag"] = true
	story.flags["floor_wiped"] = true
	await near_thing("note")
	await tap(KEY_E)
	await until_line("醒了来练武场")
	await shot("interior_05_note")
	await finish()
	# 06 the door fade, 07 outside
	var it: Interiors = main.interiors
	await goto("dorm_main", it.entry_spot("dorm_main") - it.origin("dorm_main") + Vector2(0, 8))
	key(KEY_S, true)
	for i in 40:
		await physics_frame
		if main.interiors.fade_rect.color.a > 0.55:
			break
	await shot("interior_06_door_fade")
	key(KEY_S, false)
	await frames(40)
	await shot("interior_07_outside_dorm_door")
	# 08 / 09 hall
	story.set_stage(2)
	await goto("hall", Vector2(400, 150), "left")
	await frames(10)
	await shot("interior_08_hall_master_portrait")
	await near_thing("portrait")
	await tap(KEY_E)
	await until_line("背影")
	await shot("interior_09_portrait_line")
	await finish()
	# 10 kitchen
	await goto("kitchen", Vector2(250, 170), "up")
	await shot("interior_10_kitchen_cook")
	await goto("dorm_old", Vector2(272, 200), "up")
	await shot("interior_11_old_dorm")
	await goto("storage", Vector2(150, 190), "up")
	await shot("interior_12_storage")
	# 13 library door
	main.player.global_position = Vector2(243, 660)
	main.player.facing = "up"
	await frames(4)
	await tap(KEY_E)
	await until_line("封条")
	await shot("interior_13_library_door_sealed")
	await finish()
	# 14 / 15 / 16 light
	main.daynight.set_hour(12.0)
	await goto("dorm_main", Vector2(240, 180), "up")
	await frames(6)
	await shot("interior_14_indoor_noon")
	main.daynight.set_hour(22.0)
	await frames(6)
	await shot("interior_15_indoor_night")
	await goto("hall", Vector2(330, 220), "up")
	await frames(6)
	await shot("interior_15b_hall_night")
	main.player.global_position = Vector2(370, 960)
	await frames(6)
	await shot("interior_16_outdoor_night")
	main.daynight.set_hour(8.0)
	# 17 minimap while indoors: step 3 (去厨房找厨娘), the star on the kitchen door
	story.set_stage(3)
	await goto("hall", Vector2(470, 250), "down")      # right side: the minimap is not faded over him
	for i in 120:         # the star blinks: take the picture while it is shown
		await frames(1)
		if main.hud.minimap.star_shown:
			break
	await shot("interior_17_minimap_indoor_star_on_kitchen_door")
	quit()
