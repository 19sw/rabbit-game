extends "res://tests/run_tests.gd"
## 菜园扩建 v1 screenshots (the Godot game window's own picture - no screen capture, no browser):
##   tools/screenshots_farm_expand.sh [output folder]      (default game2d/screenshots/)
##   01 the field before 开菜园 (weeds over the whole fenced field - the map's striped rows never show)
##   02 only the west opened (tilled west 6 plots, weeds east)
##   03 expanded: 12 tilled plots, crops in the east plots too
##   04 close-up (x3 crop of the window picture) of the expanded field where the west / east halves meet: no seam
##   05 close-up of the west-only state at the tilled / weeds edge
## Reuses the farm test helpers (tests/farm_suite.gd); saves go to user://test_save.json, never the player's slot.

var out_dir := "res://screenshots/"
var t


func shot(name: String, crop := Rect2()) -> void:
	print("shooting ", name)
	await process_frame
	RenderingServer.force_draw(false)     # (also when the window is covered: macOS skips drawing occluded windows)
	var img := root.get_texture().get_image()
	if crop.has_area():
		var full := img.get_size()
		img = img.get_region(Rect2i(crop))
		img.resize(full.x, full.y, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("farm_expand_" + name + ".png")
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func settle(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


## The window rectangle (1440x810 shows 480x270 world pixels) of a world rectangle, with the camera on the player.
func screen_rect(world: Rect2) -> Rect2:
	var k: Vector2 = Vector2(root.size) / t.g.get_viewport().get_visible_rect().size
	var xf: Transform2D = t.g.get_viewport().get_canvas_transform()
	var a: Vector2 = xf * world.position
	return Rect2(a * k, world.size * xf.get_scale() * k)


func _run() -> void:
	await frames(3)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	root.remove_child(main)
	root.size = Vector2i(1440, 810)
	SaveGame.erase()
	t = load("res://tests/farm_suite.gd").new(self)
	t.ss = load("res://tests/sample_suite.gd").new(self)
	t.t3 = load("res://tests/step3_suite.gd").new(self)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(self)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	Lang.set_lang("zh")
	await t.game()
	await t.clock(10.0)
	t.g.hud.hide_hint_now()
	# 01 before 开菜园: the rabbit just west of the field
	await teleport(Vector2(1648, 1080))
	await settle(0.5)
	await shot("01_before_open")
	# 02 west opened
	await t.open_farm_direct()
	await teleport(Vector2(1712, 1090))
	await settle(0.5)
	await shot("02_west_opened")
	# 05 (taken here, in the west-only state) the tilled / weeds edge up close
	await shot("05_west_edge_closeup", screen_rect(Rect2(1712, 1000, 96, 54)))
	# 03 expanded, crops west and east (one ripe in the east with its sparkle)
	await t.expand_farm_direct()
	var crops := [["greens", 1], ["radish", 1], ["pumpkin", 2], ["", 0], ["radish", 0], ["greens", 0],
		["pumpkin", 4], ["greens", 1], ["radish", 2], ["pumpkin", 1], ["greens", 0], ["radish", 1]]
	for i in crops.size():
		t.fm.plots[i] = {"crop": crops[i][0], "days": crops[i][1], "wet": i in [5, 9, 10], "note": false}
	t.fm._refresh_visuals()
	await teleport(Vector2(1776, 1094))
	await settle(0.6)
	await shot("03_expanded_crops")
	# 04 where the two halves meet (x 1760), up close: one picture, no seam
	for i in crops.size():
		t.fm.plots[i] = {"crop": "", "days": 0, "wet": false, "note": false}
	t.fm._refresh_visuals()
	await teleport(Vector2(1712, 1090))      # (the same spot and crop as 05: the rabbit just below it, the HUD above it)
	await settle(0.5)
	await shot("04_seam_closeup", screen_rect(Rect2(1712, 1000, 96, 54)))
	await t.ss._free_game()
	SaveGame.erase()
	print("SHOTS DONE")
	quit(0)
