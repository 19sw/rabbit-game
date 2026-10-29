extends SceneTree
## 试玩反馈 v1 screenshots -> screenshots/gp_*.png (needs a window, ~40 s):
##   godot --path game2d -s tests/shots_gp.gd        (tools/screenshots_gp.sh)
## gp_01 the blue GP ring + sparks the moment 师兄's blow is caught (and gp_02 a 3x close-up), gp_03 the counter's gold
## 反击, gp_04 the rag in the dorm with its bright edge + gold sparkles and the gold minimap arrow on it (gp_05 close-up),
## gp_06 dialogue options with the mouse over one (highlighted; the greyed one stays grey).
var main: Node
var player: Player
var combat: Combat
var fox: Fighter
var out_dir := "res://screenshots/"


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func until(cond: Callable, limit := 600) -> bool:
	for i in limit:
		if cond.call():
			return true
		await physics_frame
	return false


func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())
	return img


## A close-up (x3, nearest) of the window image around a world point.
func zoom(img: Image, world: Vector2, name: String) -> void:
	var ct := main.get_viewport().get_canvas_transform()
	var sp: Vector2 = ct * world                              # in the 480x270 view
	var k := float(img.get_width()) / main.get_viewport().get_visible_rect().size.x
	var c := (sp * k).round()
	var half := Vector2(80, 45) * k
	var rect := Rect2i(Vector2i((c - half).round()), Vector2i((half * 2.0).round()))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sub := img.get_region(rect)
	var up := maxi(1, int(round(3.0 / k)))                      # 3x the game's pixels (the window may already be 3x)
	if up > 1:
		sub.resize(sub.get_width() * up, sub.get_height() * up, Image.INTERPOLATE_NEAREST)
	sub.save_png(out_dir + name + ".png")
	print("saved ", name, " ", sub.get_size())


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
	await process_frame
	await process_frame


func _run() -> void:
	Input.use_accumulated_input = false     # (the synthetic mouse moves below are not merged with the real cursor's)
	await frames(10)
	main.story.enter_sandbox()
	await frames(2)
	player = main.player
	combat = main.combat
	fox = combat.spar_fighter
	main.hud.toggle_hint()
	main.daynight.running = false
	main.daynight.set_hour(10.0)
	combat.bandits_enabled = false
	# 师兄 spar, the GP the moment his blow comes
	player.global_position = fox.global_position + Vector2(0, 26)
	await frames(4)
	await tap(KEY_E)
	await tap(KEY_1)
	await frames(30)
	var st: EnemyStats = fox.stats.duplicate()
	st.sidestep_chance = 0.0
	st.move_speed = 0.0
	fox.stats = st
	player.global_position = fox.global_position + Vector2(36, 0)
	player.facing = "left"
	fox.angle = 0.0
	fox.next_attack = 0.0
	await until(func(): return fox.state == "windup" and fox.stats.windup - fox.t <= 0.12)
	key(KEY_K, true)
	await until(func(): return player.gp_successes > 0, 60)
	key(KEY_K, false)
	await frames(1)
	var img := await shot("gp_01_ring")
	zoom(img, player.global_position + Vector2(-16, -12), "gp_02_ring_zoom")
	await until(func(): return player.gp_counter_hits >= 1, 60)
	await frames(3)
	await shot("gp_03_counter")
	await frames(90)
	# a new game: the opening in the dorm, then the rag
	main.queue_free()
	await frames(2)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.daynight.running = false
	var story: Story = main.story
	for i in 600:
		if not story.busy:
			break
		if story.dialogue.active:
			await tap(KEY_E)
		else:
			await frames(2)
	await frames(30)
	main.hud.toggle_hint()
	var rag: Vector2 = main.interiors.rag_sprite.global_position + main.interiors.rag_sprite.region_rect.size * 0.5
	main.player.global_position = rag + Vector2(40, 16)
	main.player.facing = "left"
	await frames(40)
	img = await shot("gp_04_rag")
	zoom(img, rag, "gp_05_rag_zoom")
	# dialogue options with the mouse over the second one (the third is greyed)
	var dlg: Dialogue = story.dialogue
	main.combat.story_hold = true
	dlg.say({"who": "fox", "text": "来过两招？"}, ["切磋", "算了", "改天再说"], [false, false, true])
	await frames(10)
	await tap(KEY_E)
	await frames(10)
	var l: Label = dlg.choice_labels[1]
	var at: Vector2 = root.get_final_transform() * l.get_global_rect().get_center()     # view -> window pixels
	await mouse_move(at)
	await frames(4)
	print("hover: option %d highlighted" % dlg.choice_index)
	await shot("gp_06_mouse_option")
	quit(0)
