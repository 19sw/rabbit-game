extends SceneTree
## 脱战回血 v1.3 screenshots -> screenshots/regen_*.png (needs a window, ~20 s):
##   godot --path game2d -s tests/shots_regen.gd        (tools/screenshots_regen.sh)
## Full frame while regenerating, a 6x close-up of the HP bar (cue bright / dim phase), and full HP (no cue).
var main: Node
var player: Player
var combat: Combat
var out_dir := "res://screenshots/"


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func shot(name: String, crop := Rect2(), zoom := 1) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if crop.has_area():
		img = img.get_region(Rect2i(crop))
		img.resize(img.get_width() * zoom, img.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func _run() -> void:
	await frames(10)
	player = main.player
	combat = main.combat
	main.story.enter_sandbox()
	await frames(3)
	main.hud.toggle_hint()
	main.daynight.running = false
	main.daynight.set_hour(10.0)
	combat.bandits_enabled = false
	player.hp = 45
	player.regen_calm = 0.0
	player.take_damage(5, player.global_position + Vector2(20, 0))
	await frames(60 * 8)           # 5 s wait + a few seconds of regen
	var crop := Rect2(200, 12, 230, 80)     # the HP panel at the 1440x810 window
	print("hp ", player.hp, " regen_active ", player.regen_active)
	# bright / dim phase of the 1.6 s pulse
	await shot("regen_01_scene")
	await shot("regen_02_bar_zoom_a", crop, 4)
	await frames(48)
	await shot("regen_03_bar_zoom_b", crop, 4)
	player.hp = 100
	await frames(5)
	await shot("regen_04_bar_full_zoom", crop, 4)
	quit(0)
