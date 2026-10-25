extends SceneTree
## Automated checks for the 2D pixel version. Drives the real game (real input actions / key events, real physics).
## Run (from the project root):  tools/run_tests.sh      or
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd
## Exit code 0 = all passed. Writes screenshots/debug_reachability.png (walkable area from the spawn).

const T := 32.0
var main: Node
var player: Player
var data: Dictionary
var fails := 0
var passes := 0
var log_lines: PackedStringArray = []
var grid_step := 8
var grid_w := 0
var grid_h := 0
var free_grid := PackedByteArray()
var reach := PackedInt32Array()   # BFS parent index (-1 = unreached)


func _initialize() -> void:
	SaveGame.erase()    # 两条路小样 v1: start from no save (tests use user://test_save.json, never the player's slot)
	# 第④步第一批 修复 v1: the game's real view - a 1440x810 window shows the 480x270 picture (ViewFit). Headless runs
	# used to start with a 64x64 window, which ViewFit turned into a 480x480 view: every "fits on the screen" check was
	# measured on a screen 210 px taller than the game's.
	root.size = Vector2i(1440, 810)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


# ------------------------------------------------------------------ helpers
func check(cond: bool, name: String, detail := "") -> bool:
	if cond:
		passes += 1
		_log("PASS  " + name + ("" if detail == "" else "  (" + detail + ")"))
	else:
		fails += 1
		_log("FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
	return cond


func _log(s: String) -> void:
	print(s)
	log_lines.append(s)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "dash", "interact"]:
		Input.action_release(a)


func hold_dir(d: Vector2) -> void:
	Input.action_release("move_left"); Input.action_release("move_right")
	Input.action_release("move_up"); Input.action_release("move_down")
	if d.x > 0.001: Input.action_press("move_right", clampf(d.x, 0.0, 1.0))
	if d.x < -0.001: Input.action_press("move_left", clampf(-d.x, 0.0, 1.0))
	if d.y > 0.001: Input.action_press("move_down", clampf(d.y, 0.0, 1.0))
	if d.y < -0.001: Input.action_press("move_up", clampf(-d.y, 0.0, 1.0))


func push(d: Vector2, seconds: float) -> void:
	hold_dir(d)
	await frames(int(seconds * 60.0))
	release_all()
	await frames(1)


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


func teleport(p: Vector2) -> void:
	release_all()
	player.velocity = Vector2.ZERO
	player.dash_time_left = 0.0
	player.dash_cooldown_left = 0.0
	player.global_position = p
	await frames(2)


func is_free(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var r := RectangleShape2D.new()
	r.size = Player.FOOT_SIZE
	q.shape = r
	q.transform = Transform2D(0.0, p + Vector2(0, -2))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	return main.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func tile_center(tx: float, ty: float) -> Vector2:
	return Vector2(tx * T + 16.0, ty * T + 16.0)


func find_free_near(p: Vector2, radius := 24) -> Vector2:
	if is_free(p):
		return p
	for r in range(2, radius + 1, 2):
		for off in [Vector2(0, r), Vector2(0, -r), Vector2(r, 0), Vector2(-r, 0), Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
			if is_free(p + off):
				return p + off
	return Vector2.INF


# ------------------------------------------------------------------ run
func _run() -> void:
	await frames(3)
	player = main.player
	data = main.data
	# 序章 v1: the game now opens with a conversation and drives E / bandits / objectives through the story. The
	# walking, collision, NPC-position and combat checks below are about mechanics, so they run with the story layer
	# switched off (Story.enter_sandbox: no conversation, bandits on the road, 师兄 invites directly) - the same way
	# they already switched the bandit AI off. The story itself is checked by tests/story_suite.gd (real keys, from the
	# title screen).
	main.story.enter_sandbox()
	await frames(2)
	main.daynight.running = false   # the clock is frozen so older tests are not affected by time of day; test_daynight turns it on
	# the walking / collision / NPC tests below teleport the player onto the mountain road; the bandits would now
	# (correctly) attack. Their AI is switched off for these tests only and back on for the combat tests.
	main.combat.bandits_enabled = false
	if "--only-v2" in OS.get_cmdline_user_args():
		# quick loop while working on combat v1.2:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-v2
		var only = load("res://tests/combat_v2_suite.gd").new(self, load("res://tests/combat_suite.gd").new(self))
		await only.run()
		_log("")
		_log("RESULT (only v2): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-regen" in OS.get_cmdline_user_args():
		# quick loop for 脱战回血 v1.3:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-regen
		await load("res://tests/regen_suite.gd").new(self, load("res://tests/combat_suite.gd").new(self)).run()
		_log("RESULT (only regen): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-story" in OS.get_cmdline_user_args():
		# quick loop for the prologue:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-story
		root.remove_child(main)
		await load("res://tests/story_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only story): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-interiors" in OS.get_cmdline_user_args():
		# quick loop for the rooms:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-interiors
		root.remove_child(main)
		await load("res://tests/interior_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only interiors): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-polish" in OS.get_cmdline_user_args():
		# quick loop for 打磨 v1:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-polish
		await load("res://tests/polish_suite.gd").new(self).run()
		_log("RESULT (only polish): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-building" in OS.get_cmdline_user_args():
		# quick loop for 房子整栋实心 v1:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-building
		root.remove_child(main)
		await load("res://tests/building_suite.gd").new(self).run()
		_log("RESULT (only building): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-sample" in OS.get_cmdline_user_args():
		# quick loop for 两条路小样 v1:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-sample
		root.remove_child(main)
		await load("res://tests/sample_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only sample): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-step3" in OS.get_cmdline_user_args():
		# quick loop for 第③步:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-step3
		root.remove_child(main)
		await load("res://tests/step3_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only step3): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-step4a" in OS.get_cmdline_user_args():
		# quick loop for 第④步第一批:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-step4a
		#   (add --s4=name,name to run some of its tests only)
		root.remove_child(main)
		await load("res://tests/step4a_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only step4a): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	if "--only-title" in OS.get_cmdline_user_args():
		# quick loop for the title screen:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-title
		await load("res://tests/title_suite.gd").new(self).run()
		_log("")
		_log("RESULT (only title): %d passed, %d failed" % [passes, fails])
		quit(1 if fails > 0 else 0)
		return
	await test_spawn()
	await test_font()
	await test_movement_and_animation()
	await test_walls()
	await test_object_colliders()
	await test_map_bounds()
	await test_reachability()
	await test_npcs()
	await test_dash()
	await test_ambience()
	await test_camera()
	await test_v2_speed_dash()
	await test_daynight()
	await test_clock_and_keys()
	await test_minimap()
	await test_occlusion_order()
	# combat v1 (tests/combat_suite.gd)
	var cs = load("res://tests/combat_suite.gd").new(self)
	await cs.run()
	# combat tuning v2 / v1.2 (tests/combat_v2_suite.gd): 闪身追击, Esc pause, plates / numbers / banner, focus click
	var cs2 = load("res://tests/combat_v2_suite.gd").new(self, cs)
	await cs2.run()
	# 脱战回血 v1.3 (tests/regen_suite.gd): wait / rate / cap, not in a spar or with an engaged bandit, pause, dialogue
	await load("res://tests/regen_suite.gd").new(self, cs).run()
	# 启动画面 v1 (tests/title_suite.gd): runs last - it takes the game scene above out of the tree and drives the
	# title screen (the project's main scene) and the games it starts
	SaveGame.erase()    # the title screen opens without a save (继续游戏 greyed out), as for a first-time player
	var ts = load("res://tests/title_suite.gd").new(self)
	await ts.run()
	# 序章 v1 (tests/story_suite.gd): the whole prologue from the title screen, branches, puzzle, 门派簿, script check
	await load("res://tests/story_suite.gd").new(self).run()
	# 室内图进游戏 v1 (tests/interior_suite.gd): doors, rooms (walls, furniture, reachability), opening leak, NPCs inside,
	# optional lines, minimap star, indoor light, no combat indoors
	await load("res://tests/interior_suite.gd").new(self).run()
	# 打磨 v1 (tests/polish_suite.gd): round minimap, indoor light rules, outdoor occlusion fade, v4 opening + wiping,
	# wardrobe
	await load("res://tests/polish_suite.gd").new(self).run()
	# 房子整栋实心 v1 (tests/building_suite.gd): every building solid over its whole picture, no roof fade, doors, reachability
	await load("res://tests/building_suite.gd").new(self).run()
	# 两条路小样 v1 (tests/sample_suite.gd): unlock gating, economy table, the trial, repairs, stall income, 门派簿, saving
	await load("res://tests/sample_suite.gd").new(self).run()
	# 第③步 (tests/step3_suite.gd): 比武大会 calendar / fee / rounds / rewards / bot, 收徒, upkeep, jobs, saving + step-2 upgrade
	await load("res://tests/step3_suite.gd").new(self).run()
	# 第④步第一批 (tests/step4a_suite.gd): 江湖告示榜, 悬赏 posting / fights / bots, 委托 draw / six kinds / 24:00, saving v4
	await load("res://tests/step4a_suite.gd").new(self).run()
	_log("")
	_log("RESULT: %d passed, %d failed" % [passes, fails])
	var f := FileAccess.open("res://tests/last_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ tests
func test_spawn() -> void:
	var sp: Dictionary = data["spawn"]
	var p := player.global_position
	check(p.distance_to(Vector2(sp["x"], sp["y"])) < 0.5, "spawn: player starts at the spawn point", str(p))
	# characters.toml puts the rabbit on the dorm door cell (7, 28); the door is the bottom row of the dorm
	check(p.x >= 7 * T and p.x <= 8 * T and p.y >= 29 * T and p.y <= 29 * T + 12,
		"spawn: in front of the dorm door (tile 7,28)", str(p))
	check(is_free(p), "spawn: spawn point is not inside anything")
	check(player.facing == "down" and player.sprite.animation == "idle_down", "spawn: idle facing down")
	check(main.hud.hint.visible and "WASD" in main.hud.hint_label.text, "spawn: controls hint shown")


func test_font() -> void:
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := Hud.HINT_TEXT + Hud.PROMPT_TEXT + Hud.AMBIENCE_ON_TEXT + Hud.AMBIENCE_OFF_TEXT + Hud.OBJECTIVE_PREFIX
	# 序章 v1: the story files too (every line, choice, prompt, objective, 门派簿 text; the ■□ bar glyphs)
	for fn in ["res://data/tuning.json", "res://data/objectives.json", "res://data/story.json", "res://data/sect_book.json"]:
		text += FileAccess.get_file_as_string(fn)
	for h in range(24):
		main.daynight.set_hour(h)
		text += main.daynight.clock_text()
	main.daynight.set_hour(Tuning.data()["start_hour"])
	for n in data["npcs"]:
		text += n["title"]
	text += SectBook.FULL + SectBook.EMPTY + SectBook.BULLET + Dialogue.NEXT_MARK + "▶" + PauseMenu.all_text()
	var missing := ""
	for c in text:
		if c != "\n" and not font.has_char(c.unicode_at(0)):
			missing += c
	check(missing == "", "font: every UI character exists in the CJK font", "missing: " + missing)


func test_movement_and_animation() -> void:
	var start := tile_center(31, 29)   # training yard
	await teleport(start)
	# real key events: WASD and the arrow keys
	var cases := [[KEY_D, Vector2.RIGHT, "right"], [KEY_A, Vector2.LEFT, "left"], [KEY_W, Vector2.UP, "up"],
		[KEY_S, Vector2.DOWN, "down"], [KEY_RIGHT, Vector2.RIGHT, "right"], [KEY_LEFT, Vector2.LEFT, "left"],
		[KEY_UP, Vector2.UP, "up"], [KEY_DOWN, Vector2.DOWN, "down"]]
	for c in cases:
		await teleport(start)
		key(c[0], true)
		await frames(20)
		var moved: Vector2 = player.global_position - start
		var anim_walk: String = player.sprite.animation
		key(c[0], false)
		await frames(3)
		var ok: bool = moved.normalized().dot(c[1]) > 0.99 and moved.length() > 35.0
		check(ok and anim_walk == "walk_" + c[2] and player.sprite.animation == "idle_" + c[2],
			"move: key %s moves %s, plays walk_%s then idle_%s" % [OS.get_keycode_string(c[0]), c[2], c[2], c[2]],
			"moved %s, walk anim %s, idle anim %s" % [moved.round(), anim_walk, player.sprite.animation])
	# diagonal
	await teleport(start)
	key(KEY_D, true); key(KEY_S, true)
	await frames(30)
	var dm := player.global_position - start
	key(KEY_D, false); key(KEY_S, false)
	await frames(2)
	check(dm.x > 40 and dm.y > 40 and absf(dm.x - dm.y) < 3.0 and absf(dm.length() / 0.5 - player.stats.walk_speed) < 12.0,
		"move: diagonal D+S moves down-right at normal speed", str(dm.round()))
	await teleport(start)
	key(KEY_UP, true); key(KEY_A, true)
	await frames(20)
	var dm2 := player.global_position - start
	var a2: String = player.sprite.animation
	key(KEY_UP, false); key(KEY_A, false)
	await frames(2)
	check(dm2.x < -20 and dm2.y < -20 and (a2 == "walk_up" or a2 == "walk_left"),
		"move: diagonal Up+A moves up-left with a 4-direction walk animation", "%s %s" % [dm2.round(), a2])
	# timed walk: dorm door -> training-yard centre (v2: client asked for ~30% slower than v1's 4.08 s => about 6 s)
	await teleport(Vector2(data["spawn"]["x"], data["spawn"]["y"]))
	var goal := tile_center(31, 29)
	var path := []
	_build_grid()
	path = _astar(player.global_position, goal)
	var t := await _drive(path, 10.0)
	check(t > 0.0 and t >= 5.5 and t <= 6.5, "A1 move: dorm door -> training-yard centre takes 5.5-6.5 s (v1: ~4.08 s)", "%.2f s" % t)


func _wall_push(start: Vector2, d: Vector2, limit_ok: Callable, label: String, seconds := 0.45) -> int:
	## returns 1 if checked, 0 if start blocked
	if not is_free(start):
		return 0
	await teleport(start)
	await push(d, seconds)
	if not limit_ok.call(player.global_position):
		check(false, label, "start %s -> ended %s" % [start, player.global_position.round()])
		return -1
	return 1


func test_walls() -> void:
	var results := {}
	# north wall y=11 (moved one tile north in 房子整栋实心 v1 fix 2; gap 30..32 is the back gate; tiles 8..9 = the two breaches)
	for tx in range(4, 60):
		if tx >= 30 and tx <= 32:
			continue
		if tx == 8 or tx == 9:
			continue   # the two V-shaped breaches beside 藏经阁 (x 256..322) are walkable since 房子整栋实心 v1 fix; tested in building_suite.gd
		var r1 := await _wall_push(Vector2(tx * T + 16, 12 * T + 14), Vector2.UP, func(p): return p.y > 11 * T + 16, "north wall from inside at x=%d" % tx)
		var r2 := await _wall_push(Vector2(tx * T + 16, 10 * T + 20), Vector2.DOWN, func(p): return p.y < 11 * T + 16, "north wall from outside at x=%d" % tx)
		results["north"] = results.get("north", []) + [r1, r2]
	# south wall y=39 (gap 29..35 is the mountain gate)
	for tx in range(4, 60):
		if tx >= 29 and tx <= 35:
			continue
		var r1 := await _wall_push(Vector2(tx * T + 16, 38 * T + 20), Vector2.DOWN, func(p): return p.y < 39 * T + 16, "south wall from inside at x=%d" % tx)
		var r2 := await _wall_push(Vector2(tx * T + 16, 40 * T + 20), Vector2.UP, func(p): return p.y > 39 * T + 16, "south wall from outside at x=%d" % tx)
		results["south"] = results.get("south", []) + [r1, r2]
	# west wall x=3 and east wall x=60
	for ty in range(13, 39):
		var r1 := await _wall_push(Vector2(4 * T + 16, ty * T + 20), Vector2.LEFT, func(p): return p.x > 3 * T + 8, "west wall from inside at y=%d" % ty)
		var r2 := await _wall_push(Vector2(2 * T + 16, ty * T + 20), Vector2.RIGHT, func(p): return p.x < 3 * T + 8, "west wall from outside at y=%d" % ty)
		var r3 := await _wall_push(Vector2(59 * T + 16, ty * T + 20), Vector2.RIGHT, func(p): return p.x < 60 * T + 24, "east wall from inside at y=%d" % ty)
		var r4 := await _wall_push(Vector2(61 * T + 16, ty * T + 20), Vector2.LEFT, func(p): return p.x > 60 * T + 24, "east wall from outside at y=%d" % ty)
		results["west"] = results.get("west", []) + [r1, r2]
		results["east"] = results.get("east", []) + [r3, r4]
	# upper cliff rows 41-42 (stairs at 31..33)
	for tx in range(0, 64):
		if tx >= 31 and tx <= 33:
			continue
		var r1 := await _wall_push(Vector2(tx * T + 16, 40 * T + 24), Vector2.DOWN, func(p): return p.y < 41 * T + 16, "upper cliff from above at x=%d" % tx, 0.6)
		var r2 := await _wall_push(Vector2(tx * T + 16, 43 * T + 20), Vector2.UP, func(p): return p.y > 42 * T + 16, "upper cliff from below at x=%d" % tx, 0.6)
		results["cliff1"] = results.get("cliff1", []) + [r1, r2]
	# lower stone bank rows 47-48, x 18..63
	for tx in range(18, 64):
		var r1 := await _wall_push(Vector2(tx * T + 16, 46 * T + 24), Vector2.DOWN, func(p): return p.y < 47 * T + 16, "lower stone bank from above at x=%d" % tx, 0.6)
		var r2 := await _wall_push(Vector2(tx * T + 16, 49 * T + 20), Vector2.UP, func(p): return p.y > 48 * T + 16, "lower stone bank from below at x=%d" % tx, 0.6)
		results["cliff2"] = results.get("cliff2", []) + [r1, r2]
	for k in results:
		var arr: Array = results[k]
		var tested := arr.count(1) + arr.count(-1)
		check(arr.count(-1) == 0 and tested > 0, "walls/cliffs: %s - no pass-through" % k,
			"%d pushes tested, %d skipped (start blocked by something else)" % [tested, arr.count(0)])
	# gaps that must stay open
	# the paved walkway behind the hall (the north wall moved one tile north in 房子整栋实心 v1 fix 2): start on it at tile 31,12
	# and walk up through the back-wall gap (building_suite.gd walks the whole way there from the spawn)
	await teleport(tile_center(31, 12))
	await push(Vector2.UP, 1.2)
	check(player.global_position.y < 11 * T, "walls: back-wall gap (to the bamboo grove) is passable", str(player.global_position.round()))
	await teleport(tile_center(32, 34))
	await push(Vector2.DOWN, 1.6)
	check(player.global_position.y > 40 * T + 16, "walls: mountain gate passage is passable", str(player.global_position.round()))
	await teleport(tile_center(32, 40))
	await push(Vector2.DOWN, 1.2)
	check(player.global_position.y > 43 * T, "cliff: stone stairs are passable", str(player.global_position.round()))


func test_object_colliders() -> void:
	## Every object footprint: walk straight into it from below and from above at its centre - must not pass.
	var tested := 0
	var skipped := 0
	var bad: PackedStringArray = []
	var by_kind := {}
	for c in data["colliders"]:
		if c["kind"] in ["tile", "bounds"]:
			continue
		var r: Array = c["rect"]
		var rect := Rect2(r[0], r[1], r[2], r[3])
		var cx := rect.position.x + rect.size.x * 0.5
		var travel := (rect.size.y + 30.0) / player.stats.walk_speed + 0.1
		var below := Vector2(cx, rect.end.y + 7)
		var above := Vector2(cx, rect.position.y - 3)
		var any := false
		if is_free(below):
			await teleport(below)
			await push(Vector2.UP, travel)
			tested += 1
			any = true
			if player.global_position.y < rect.end.y - 4.0:
				bad.append("%s %s from below -> %s" % [c["kind"], rect, player.global_position.round()])
		if is_free(above):
			await teleport(above)
			await push(Vector2.DOWN, travel)
			tested += 1
			any = true
			if player.global_position.y > rect.position.y + 4.0:
				bad.append("%s %s from above -> %s" % [c["kind"], rect, player.global_position.round()])
		if not any:
			skipped += 1
		by_kind[c["kind"]] = by_kind.get(c["kind"], 0) + 1
	check(bad.is_empty(), "objects: no object can be walked through (buildings, trees, bamboo, rocks, well, fence, racks...)",
		"%d pushes on %d footprints, %d footprints boxed in by neighbours; kinds: %s; failures: %s" % [tested, by_kind.values().reduce(func(a, b): return a + b, 0), skipped, by_kind.keys(), bad])
	# NPCs are solid
	var npc_bad := []
	for n in main.npcs:
		var st := find_free_near(n.global_position + Vector2(0, 14), 8)
		if st == Vector2.INF:
			continue
		await teleport(st)
		await push(Vector2.UP, 0.5)
		if player.global_position.y < n.global_position.y:
			npc_bad.append(n.id)
	check(npc_bad.is_empty(), "objects: NPCs cannot be walked through", str(npc_bad))


func test_map_bounds() -> void:
	var W: float = data["pixel_width"]
	var H: float = data["pixel_height"]
	var bad := []
	var n := 0
	for i in range(1, 63, 3):
		for spec in [[Vector2(i * T + 16, 12), Vector2.UP], [Vector2(i * T + 16, H - 6), Vector2.DOWN]]:
			var st := find_free_near(spec[0], 16)
			if st == Vector2.INF:
				continue
			await teleport(st)
			await push(spec[1], 0.4)
			n += 1
			var p := player.global_position
			if p.y - 5 < 0 or p.y + 1 > H:
				bad.append(p)
	for j in range(1, 59, 3):
		for spec in [[Vector2(10, j * T + 16), Vector2.LEFT], [Vector2(W - 10, j * T + 16), Vector2.RIGHT]]:
			var st := find_free_near(spec[0], 16)
			if st == Vector2.INF:
				continue
			await teleport(st)
			await push(spec[1], 0.4)
			n += 1
			var p := player.global_position
			if p.x - 6 < 0 or p.x + 6 > W:
				bad.append(p)
	check(bad.is_empty() and n > 40, "bounds: cannot walk off the map edge", "%d edge pushes, out: %s" % [n, bad])


# ---------------------------------------------------------------- reachability (grid BFS + driven walks)
func _build_grid() -> void:
	if grid_w > 0:
		return
	grid_w = int(data["pixel_width"]) / grid_step
	grid_h = int(data["pixel_height"]) / grid_step
	free_grid.resize(grid_w * grid_h)
	for gy in grid_h:
		for gx in grid_w:
			free_grid[gy * grid_w + gx] = 1 if is_free(_gpos(gx, gy)) else 0


func _gpos(gx: int, gy: int) -> Vector2:
	return Vector2(gx * grid_step + grid_step * 0.5, gy * grid_step + grid_step * 0.5)


func _gidx(p: Vector2) -> int:
	var gx := clampi(int(p.x / grid_step), 0, grid_w - 1)
	var gy := clampi(int(p.y / grid_step), 0, grid_h - 1)
	return gy * grid_w + gx


func _neighbors(i: int) -> Array:
	var gx := i % grid_w
	var gy := i / grid_w
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var nx: int = gx + d.x
		var ny: int = gy + d.y
		if nx < 0 or ny < 0 or nx >= grid_w or ny >= grid_h:
			continue
		if free_grid[ny * grid_w + nx] == 0:
			continue
		if d.x != 0 and d.y != 0:
			if free_grid[gy * grid_w + nx] == 0 or free_grid[ny * grid_w + gx] == 0:
				continue
		out.append(ny * grid_w + nx)
	return out


func _bfs(from: Vector2) -> void:
	reach.resize(grid_w * grid_h)
	reach.fill(-1)
	var s := _gidx(from)
	reach[s] = s
	var q := [s]
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		for nb in _neighbors(i):
			if reach[nb] == -1:
				reach[nb] = i
				q.append(nb)


func _nearest_free_cell(p: Vector2) -> int:
	var i := _gidx(p)
	if free_grid[i] == 1:
		return i
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var j := _gidx(p + Vector2(dx, dy) * grid_step)
				if free_grid[j] == 1:
					return j
	return i


func _astar(from: Vector2, to: Vector2) -> Array:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid_w, grid_h)
	astar.cell_size = Vector2(grid_step, grid_step)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for gy in grid_h:
		for gx in grid_w:
			if free_grid[gy * grid_w + gx] == 0:
				astar.set_point_solid(Vector2i(gx, gy))
	var a := _nearest_free_cell(from)
	var b := _nearest_free_cell(to)
	var ids := astar.get_id_path(Vector2i(a % grid_w, a / grid_w), Vector2i(b % grid_w, b / grid_w))
	var pts := []
	for id in ids:
		pts.append(_gpos(id.x, id.y))
	# keep only the turning points
	var simple := []
	for k in pts.size():
		if k == 0 or k == pts.size() - 1:
			simple.append(pts[k])
			continue
		var d1: Vector2 = (pts[k] - pts[k - 1]).sign()
		var d2: Vector2 = (pts[k + 1] - pts[k]).sign()
		if d1 != d2:
			simple.append(pts[k])
	return simple


func _drive(path: Array, limit: float) -> float:
	## Walks the player along `path` with the movement actions. Returns seconds taken, or -1 if stuck/timeout.
	var t := 0.0
	var wp := 0
	var last := player.global_position
	var stuck := 0.0
	while wp < path.size():
		var target: Vector2 = path[wp]
		var to: Vector2 = target - player.global_position
		if to.length() < 3.5:
			wp += 1
			continue
		hold_dir(to.normalized())
		await physics_frame
		t += 1.0 / 60.0
		if player.global_position.distance_to(last) < 0.3:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
		last = player.global_position
		if stuck > 1.0 or t > limit:
			release_all()
			_log("      drive stopped at %s (waypoint %d/%d %s)" % [player.global_position.round(), wp, path.size(), target])
			return -1.0
	release_all()
	await frames(1)
	return t


func test_reachability() -> void:
	_build_grid()
	var spawn := Vector2(data["spawn"]["x"], data["spawn"]["y"])
	_bfs(spawn)
	var targets := {
		"村口 (village square)": tile_center(45, 56), "竹林 (bamboo clearing)": tile_center(30, 4),
		"练武场 (training yard)": tile_center(31, 29), "正殿前 (main hall front)": tile_center(32, 21),
		"厨房门口 (kitchen door)": tile_center(46, 30), "藏经阁 (library ruins)": tile_center(14, 20),
		"东园 (east garden)": tile_center(50, 20), "山门外 (outside the gate)": tile_center(32, 40),
		"山路 (mountain road)": tile_center(14, 45), "村口茶摊 (tea stall)": tile_center(40, 58),
	}
	for name in targets:
		var i := _nearest_free_cell(targets[name])
		check(reach[i] != -1, "reach: %s reachable from the spawn (grid search)" % name, str(targets[name]))
	var free_n := 0
	var reach_n := 0
	for i in free_grid.size():
		if free_grid[i] == 1:
			free_n += 1
			if reach[i] != -1:
				reach_n += 1
	_log("      walkable cells %d, reachable from spawn %d (%.1f%%)" % [free_n, reach_n, 100.0 * reach_n / maxf(1, free_n)])
	_save_reach_image()
	# actually walk there with the movement keys
	for name in ["村口 (village square)", "竹林 (bamboo clearing)"]:
		await teleport(spawn)
		var path := _astar(spawn, targets[name])
		var t := await _drive(path, 120.0)
		check(t > 0.0 and player.global_position.distance_to(path[-1]) < 6.0,
			"reach: walked from the spawn to %s with the movement keys" % name, "%.1f s, %d turns, end %s" % [t, path.size(), player.global_position.round()])


func _save_reach_image() -> void:
	var img: Image = (load("res://assets/map/ground.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	for o in data["objects"]:
		var oi: Image = (load("res://assets/map/" + o["tex"]) as Texture2D).get_image()
		oi.convert(Image.FORMAT_RGBA8)
		img.blend_rect(oi, Rect2i(0, 0, oi.get_width(), oi.get_height()), Vector2i(o["x"], o["y"]))
	var over := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for gy in grid_h:
		for gx in grid_w:
			var i := gy * grid_w + gx
			var col := Color(0, 0, 0, 0)
			if free_grid[i] == 0:
				col = Color(1, 0, 0, 0.35)
			elif reach[i] == -1:
				col = Color(1, 0, 1, 0.55)   # free but unreachable pocket
			else:
				col = Color(0.2, 0.6, 1.0, 0.18)
			over.fill_rect(Rect2i(gx * grid_step, gy * grid_step, grid_step, grid_step), col)
	img.blend_rect(over, Rect2i(0, 0, over.get_width(), over.get_height()), Vector2i.ZERO)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	img.save_png("res://screenshots/debug_reachability.png")


# ---------------------------------------------------------------- NPCs
func test_npcs() -> void:
	check(main.npcs.size() == 8, "npc: 8 NPCs placed", str(main.npcs.size()))
	for n in main.npcs:
		var d: Dictionary = {}
		for nd in data["npcs"]:
			if nd["id"] == n.id:
				d = nd
		check(n.global_position == Vector2(d["x"], d["y"]) and n.sprite.animation == "idle_" + d["dir"] and n.sprite.is_playing(),
			"npc: %s at characters.toml tile %s, idle facing %s" % [n.full_name, [int(d["x"]) / 32, int(d["y"]) / 32], d["dir"]])
	await teleport(tile_center(31, 26))
	check(not main.hud.prompt.visible, "npc: no prompt when nobody is near")
	for n in main.npcs:
		var st := Vector2.INF
		for off in [Vector2(0, 26), Vector2(-26, 0), Vector2(26, 0), Vector2(0, -26), Vector2(0, 34), Vector2(20, 20), Vector2(-20, 20)]:
			if is_free(n.global_position + off):
				st = n.global_position + off
				break
		if st == Vector2.INF:
			check(false, "npc: %s has free ground around it" % n.title)
			continue
		await teleport(st)
		await frames(2)
		if n != main.combat.spar_fighter:
			# 序章 v1: the "（对话之后再做）" placeholder bubble is gone - what each NPC says (and when "按 E 交谈" shows)
			# is the story's, checked per stage by tests/story_suite.gd. Here (story layer off) only free ground
			# around every NPC is checked, which that suite relies on.
			check(is_free(st), "npc: %s has free ground next to it to talk from" % n.title, str(st))
			continue
		var prompt_ok: bool = main.hud.prompt.visible and main.prompt_npc == n and main.hud.prompt_label.text == "按 E 交谈"
		await tap(KEY_E)
		await frames(2)
		# combat v1: E next to 师兄 opens the spar invitation (来过两招？ 切磋 / 算了)
		var bubble_text: String = main.combat.hud.choice_title.text
		var bubble_ok: bool = main.combat.hud.choice.visible and bubble_text == "来过两招？" and not main.hud.prompt.visible and not main.hud.bubble.visible
		# walk away
		var away := find_free_near(st + (st - n.global_position).normalized() * 90.0, 40)
		await teleport(away)
		await frames(2)
		var gone: bool = not main.hud.bubble.visible and not main.hud.prompt.visible and not main.combat.hud.choice.visible
		check(prompt_ok and bubble_ok and gone,
			"npc: %s - near shows 按 E 交谈, E opens '%s', leaving hides it" % [n.title, bubble_text],
			"prompt %s, invite %s, hidden after leaving %s" % [prompt_ok, bubble_ok, gone])


# ---------------------------------------------------------------- dash
func _dash_from(start: Vector2, d: Vector2) -> Vector2:
	await teleport(start)
	player.facing = CharSheet.dir_from_vector(d, player.facing)
	hold_dir(d)
	await frames(1)
	await tap(KEY_SPACE)
	await frames(14)
	release_all()
	await frames(2)
	return player.global_position


func test_dash() -> void:
	var start := tile_center(28, 29)
	await teleport(start)
	player.facing = "right"
	await tap(KEY_SPACE)
	var ghosts := 0
	for i in 8:
		await physics_frame
		ghosts = maxi(ghosts, get_nodes_in_group("afterimage").size())
	await frames(6)
	var dist := player.global_position.x - start.x
	check(dist > 70 and dist < 100 and absf(player.global_position.y - start.y) < 0.5,
		"dash: Space dashes ~85 px in the facing direction", "%.1f px" % dist)
	check(ghosts >= 3, "dash: leaves fading afterimages", "%d afterimages at once" % ghosts)
	await frames(30)
	check(get_nodes_in_group("afterimage").size() == 0, "dash: afterimages fade out and are removed")
	# cooldown
	await teleport(start)
	player.facing = "right"
	await tap(KEY_SPACE)
	await frames(12)
	var p1 := player.global_position
	await tap(KEY_SHIFT)
	await frames(12)
	check(player.global_position.distance_to(p1) < 1.0, "dash: cooldown blocks an immediate second dash")
	await frames(40)
	await tap(KEY_SHIFT)
	await frames(14)
	check(player.global_position.distance_to(p1) > 70, "dash: Shift dashes again after the cooldown", "%.1f px" % player.global_position.distance_to(p1))
	# dash into walls / solid things: must stay on the same side
	var cases := [
		["north wall", Vector2(20 * T + 16, 12 * T + 10), Vector2.UP, func(p): return p.y > 11 * T + 16],
		["north wall from the bamboo side", Vector2(20 * T + 16, 10 * T + 20), Vector2.DOWN, func(p): return p.y < 11 * T + 16],
		["south wall", Vector2(10 * T + 16, 38 * T + 24), Vector2.DOWN, func(p): return p.y < 39 * T + 16],
		["west wall", Vector2(4 * T + 10, 30 * T), Vector2.LEFT, func(p): return p.x > 3 * T + 8],
		["east wall", Vector2(59 * T + 20, 22 * T), Vector2.RIGHT, func(p): return p.x < 60 * T + 24],
		["cliff edge", Vector2(10 * T + 16, 40 * T + 26), Vector2.DOWN, func(p): return p.y < 41 * T + 16],
		["lower stone bank", Vector2(40 * T + 16, 49 * T + 20), Vector2.UP, func(p): return p.y > 48 * T + 16],
		["dorm wall (from the front)", Vector2(10 * T + 16, 29 * T + 8), Vector2.UP, func(p): return p.y > 29 * T - 4],
		["dorm roof (from behind)", Vector2(10 * T + 16, 23 * T + 20), Vector2.DOWN, func(p): return p.y < 24 * T + 9],   # solid from the ridge (y 776): feet stop above it
		["main hall", Vector2(28 * T + 16, 20 * T + 12), Vector2.UP, func(p): return p.y > 20 * T - 4],
		["kitchen fence", Vector2(54 * T + 16, 30 * T - 2), Vector2.DOWN, func(p): return p.y < 30 * T + 30],
		["NPC 师兄", Vector2(976, 959 + 30), Vector2.UP, func(p): return p.y > 959],
	]
	for c in cases:
		var st := find_free_near(c[1], 10)
		if st == Vector2.INF:
			check(false, "dash: %s - test start blocked" % c[0], str(c[1]))
			continue
		var end := await _dash_from(st, c[2])
		check(c[3].call(end), "dash: cannot dash through the %s" % c[0], "%s -> %s" % [st.round(), end.round()])
	# systematic: dash at the walls every 2 tiles
	var bad := []
	for tx in range(4, 60, 2):
		if tx >= 29 and tx <= 35:
			continue
		if tx == 8 or tx == 9:
			continue   # the wall breaches (walkable, see building_suite.gd)
		for spec in [[Vector2(tx * T + 16, 12 * T + 8), Vector2.UP, func(p): return p.y > 11 * T + 16],
				[Vector2(tx * T + 16, 38 * T + 26), Vector2.DOWN, func(p): return p.y < 39 * T + 16],
				[Vector2(tx * T + 16, 40 * T + 26), Vector2.DOWN, func(p): return p.y < 41 * T + 16]]:
			if tx >= 30 and tx <= 33 and spec[1] == Vector2.UP:
				continue
			if not is_free(spec[0]):
				continue
			var end := await _dash_from(spec[0], spec[1])
			if not spec[2].call(end):
				bad.append([spec[0], end])
	check(bad.is_empty(), "dash: dash sweep along north wall, south wall and cliff edge never passes", str(bad))


# ---------------------------------------------------------------- ambience / camera / occlusion
func test_ambience() -> void:
	var amb: Ambience = main.ambience
	main.daynight.set_hour(8.0)
	await frames(3)
	check(amb.enabled and amb.modulate_node.visible and amb.lights.size() == 8 and amb.lights.all(func(l): return l.enabled),
		"ambience: on by default with 8 lantern lights", "%d lights" % amb.lights.size())
	check(amb.modulate_node.color.r > amb.modulate_node.color.b and amb.modulate_node.color.v < 0.95,
		"ambience: tint is warm and dimmer than the original", str(amb.modulate_node.color))
	await tap(KEY_L)
	check(not amb.enabled and not amb.modulate_node.visible and not amb.grade_layer.visible and amb.lights.all(func(l): return not l.enabled),
		"ambience: L turns it off")
	await tap(KEY_L)
	check(amb.enabled and amb.modulate_node.visible, "ambience: L turns it back on")


func test_camera() -> void:
	var W: float = data["pixel_width"]
	var H: float = data["pixel_height"]
	var map_rect := Rect2(0, 0, W, H)
	for p in [Vector2(40, 40), Vector2(W - 40, 40), Vector2(40, H - 20), Vector2(W - 40, H - 20), tile_center(31, 29)]:
		await teleport(find_free_near(p, 40))
		await process_frame
		await process_frame
		var vr: Rect2 = main.view_rect()
		check(map_rect.encloses(vr.grow(-0.5)), "camera: view stays inside the map near %s" % p, "view %s" % vr)
	await teleport(tile_center(31, 29))
	await process_frame
	var c: Vector2 = main.camera.get_screen_center_position()
	check(c.distance_to(player.global_position) < 20 and c == c.round(), "camera: follows the player on whole pixels", str(c))


func _sprite_by_type(t: String, near: Vector2) -> Sprite2D:
	var best: Sprite2D = null
	var bd := INF
	for s in main.world.get_children():
		if s is Sprite2D and s.get_meta("type", "") == t:
			var d := (s.position as Vector2).distance_to(near)
			if d < bd:
				bd = d
				best = s
	return best


func test_occlusion_order() -> void:
	# north of the dorm roof (stopped at the ridge, 房子整栋实心 v1: she can no longer tuck behind it) -> the dorm draws over the player
	var dorm := _sprite_by_type("building", Vector2(5 * T + 144, 29 * T))
	await teleport(Vector2(10 * T + 16, 24 * T + 12))
	await push(Vector2.DOWN, 0.4)
	var behind := player.global_position
	check(behind.y < dorm.position.y and behind.y > 24 * T, "occlusion: player stopped at the dorm ridge is sorted behind the dorm (and not inside the roof)",
		"feet %s, dorm base %s" % [behind.round(), dorm.position.y])
	await teleport(Vector2(10 * T + 16, 29 * T + 8))
	check(player.global_position.y > dorm.position.y, "occlusion: in front of the dorm the player is sorted in front")
	var tree := _sprite_by_type("tree", Vector2(19 * T + 48, 19 * T))
	var trunk_x: float = tree.position.x + tree.texture.get_width() * 0.5
	await teleport(Vector2(trunk_x, tree.position.y - 18))
	await push(Vector2.DOWN, 0.3)
	check(player.global_position.y < tree.position.y and is_free(player.global_position) and absf(player.global_position.x - trunk_x) < 1,
		"occlusion: under a tree canopy (behind the trunk) the tree draws over the player", str(player.global_position.round()))


# ================================================================ v2 additions
func test_v2_speed_dash() -> void:
	# walking is ~30% slower than v1 (190 px/s). Combat v1.1 moved it from data/tuning.json into the player's
	# stat card (cards/player.tres) - same value, new home; tuning.json must no longer carry it.
	var v: float = player.stats.walk_speed
	check(v >= 190.0 * 0.62 and v <= 190.0 * 0.78 and not Tuning.data().has("walk_speed") and player.stats.resource_path == "res://cards/player.tres",
		"A1 speed: walk speed is ~30% below v1's 190 px/s and lives in the player card (moved from tuning.json)", "%.0f px/s" % v)
	# dash is unchanged from v1: 540 px/s for 0.16 s (~86 px), cooldown 0.6 s (v1.1: values now in the player card)
	check(player.stats.dodge_speed == 540.0 and player.stats.dodge_time == 0.16 and player.stats.dodge_cooldown == 0.6,
		"A1 dash: speed / time / cooldown identical to v1")
	var start := tile_center(31, 29)
	await teleport(start)
	await frames(2)
	player.facing = "right"
	await tap(KEY_SPACE)
	await frames(14)
	var dist := player.global_position.x - start.x
	check(dist > 70 and dist < 100, "A1 dash: distance still ~85 px (same as v1)", "%.1f px" % dist)


func test_daynight() -> void:
	var dn: DayNight = main.daynight
	var day_s := Tuning.day_seconds()
	check(is_equal_approx(day_s, 48.0 * 60.0) and is_equal_approx(day_s / 24.0, 120.0),
		"A2 time: one game day = 48 real minutes (1 game hour = 2 real minutes)", "%.0f s/day" % day_s)
	check(absf(float(Tuning.data()["start_hour"]) - 8.0) < 0.01, "A2 time: tuning start hour is 8:00")
	# the live node progresses with real (here: fixed 60 fps) time
	dn.set_hour(8.0)
	var h0 := dn.hour
	dn.running = true
	await frames(360)   # 6 s
	dn.running = false
	var dh := dn.hour - h0
	check(absf(dh - 6.0 / 120.0) < 0.004, "A2 time: running node advances 1 h per 120 s (6 s -> 0.05 h)", "%.4f h" % dh)
	dn.set_hour(8.0)
	dn.advance_seconds(120.0)
	check(absf(dn.hour - 9.0) < 1e-6, "A2 time: 120 s -> 8:00 becomes 9:00", str(dn.hour))
	dn.set_hour(23.5)
	dn.advance_seconds(120.0)
	check(absf(dn.hour - 0.5) < 1e-6, "A2 time: wraps past midnight", str(dn.hour))
	# the main scene starts at 8:00
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	await frames(2)
	check(absf(fresh.daynight.hour - 8.0) < 0.05 and fresh.hud.clock_label.text.begins_with("辰时 08:0"),
		"A2 time: a new game starts at 辰时 08:00", "%.3f %s" % [fresh.daynight.hour, fresh.hud.clock_label.text])
	fresh.queue_free()
	await frames(2)
	dn.set_hour(8.0)
	# distinct moods: brightness / colour per period, lamps off by day and on at night
	var lum := {}
	for pair in [["dawn", 6.5], ["noon", 12.0], ["dusk", 18.0], ["night", 21.5], ["deep", 2.0]]:
		dn.set_hour(pair[1])
		var t: Color = dn.look()["tint"]
		lum[pair[0]] = t.get_luminance()
		_log("      %s %.1f: tint %s lamps %.2f" % [pair[0], pair[1], t, dn.lamp_level()])
	check(lum["noon"] > lum["dawn"] and lum["dawn"] > lum["night"] and lum["night"] > lum["deep"] and lum["noon"] - lum["deep"] > 0.4,
		"A3 look: noon > dawn > night > deep night brightness, clearly different", str(lum))
	dn.set_hour(12.0)
	check(dn.lamp_level() == 0.0, "A3 lamps: off at noon")
	dn.set_hour(8.0)
	check(dn.lamp_level() == 0.0, "A3 lamps: off at 8:00")
	dn.set_hour(21.0)
	check(dn.lamp_level() == 1.0, "A3 lamps: fully on at night")
	dn.set_hour(2.0)
	check(dn.lamp_level() == 1.0, "A3 lamps: still on in deep night")
	dn.set_hour(7.0)
	check(dn.lamp_level() == 0.0, "A3 lamps: off after dawn (7:00)")
	# smoothness: no jump between neighbouring minutes anywhere in the day
	var worst := 0.0
	var prev: Color = Color.BLACK
	for m in range(0, 1441):
		dn.set_hour(float(m) / 60.0)
		var c: Color = dn.look()["tint"]
		if m > 0:
			worst = maxf(worst, maxf(absf(c.r - prev.r), maxf(absf(c.g - prev.g), absf(c.b - prev.b))))
		prev = c
	check(worst < 0.01, "A3 look: tint changes smoothly (max step per game minute %.4f)" % worst)
	check(absf(_tint_at(0.0).r - _tint_at(24.0 - 1e-4).r) < 0.01, "A3 look: 23:59 joins 0:00 without a jump")
	# readable at night: the darkest tint is not near black, and the ambience node applies it with lamps lit
	var darkest := 1.0
	for m in range(0, 1440, 10):
		dn.set_hour(float(m) / 60.0)
		darkest = minf(darkest, dn.look()["tint"].get_luminance())
	check(darkest > 0.3, "A3 look: darkest moment is still bright enough to see (tint luminance %.2f)" % darkest)
	dn.set_hour(21.5)
	await frames(3)
	var amb: Ambience = main.ambience
	check(amb.lamp_level == 1.0 and amb.lights.all(func(l): return l.enabled and l.visible and l.energy > 0.5),
		"A3 lamps: ambience lights lit at night")
	dn.set_hour(12.0)
	await frames(3)
	check(amb.lights.all(func(l): return l.energy == 0.0 and not l.visible), "A3 lamps: ambience lights dark at noon")
	dn.set_hour(8.0)


func _tint_at(h: float) -> Color:
	main.daynight.set_hour(h)
	return main.daynight.look()["tint"]


func test_clock_and_keys() -> void:
	var dn: DayNight = main.daynight
	dn.running = false
	dn.set_hour(18.0)
	await frames(2)
	check(main.hud.clock_label.text == "酉时 18:00", "A4 clock: 18:00 shows 酉时 18:00", main.hud.clock_label.text)
	var expect := {0.0: "子时 00:00", 1.0: "丑时 01:00", 3.5: "寅时 03:30", 6.0: "卯时 06:00", 8.0: "辰时 08:00", 9.0: "巳时 09:00", 10.25: "巳时 10:15",
		12.0: "午时 12:00", 14.0: "未时 14:00", 16.5: "申时 16:30", 20.0: "戌时 20:00", 22.0: "亥时 22:00", 23.0: "子时 23:00", 17.0: "酉时 17:00"}
	var bad := ""
	for h in expect:
		dn.set_hour(h)
		if dn.clock_text() != expect[h]:
			bad += "%s->%s " % [h, dn.clock_text()]
	check(bad == "", "A4 clock: 时辰 + HH:MM text for 14 sample times", bad)
	dn.set_hour(8.0)
	await frames(2)
	await tap(KEY_T)
	check(absf(dn.hour - 9.0) < 0.001 and main.hud.clock_label.text == "巳时 09:00", "A2 key: T fast-forwards 1 hour (8:00 -> 9:00) and the clock follows", "%.3f %s" % [dn.hour, main.hud.clock_label.text])
	for i in 9:
		await tap(KEY_T)
	check(absf(dn.hour - 18.0) < 0.001 and main.hud.clock_label.text == "酉时 18:00", "A2 key: 9 more T presses -> 酉时 18:00", "%.3f" % dn.hour)
	# L still toggles the ambience, clock stays visible
	var amb: Ambience = main.ambience
	await tap(KEY_L)
	check(not amb.enabled and not amb.modulate_node.visible and main.hud.clock.visible, "A4 key: L still turns ambience off (clock stays)")
	await tap(KEY_L)
	check(amb.enabled and amb.modulate_node.visible and amb.modulate_node.color.is_equal_approx(dn.look()["tint"]),
		"A4 key: L turns it back on with the current time's tint")
	dn.set_hour(8.0)


## 打磨 v1: the minimap is a small circle centred on the player (spec change: was a whole-map thumbnail). Same checks,
## for the new shape: top-left + size, follows position / facing / real walking, star at the objective, blinking,
## never over the player in normal places, no overlap with the other HUD pieces, fades over the player in a corner.
func test_minimap() -> void:
	main.objectives.reset()
	var mm: Minimap = main.hud.minimap
	var dia: float = float(Tuning.data()["minimap"]["diameter"])
	var vp := Vector2(480, 270)
	check(mm.position.x < 12 and mm.position.y < 12 and mm.size.x == dia and mm.size.y == dia and absf(dia - 56.0) <= 4.0 and mm.size.x < vp.x * 0.15,
		"A5 minimap: top-left, round, about 56 px across (half the old 104 px)", "%s at %s" % [mm.size, mm.position])
	check(mm.map_tex != null and mm.map_tex.get_width() >= 200, "A5 minimap: built from the map thumbnail (padded, so the circle never runs off the map)")
	# centred on the player + facing
	var spots := [tile_center(31, 29), tile_center(8, 29), tile_center(32, 21), tile_center(45, 55), tile_center(30, 5), Vector2(240, 932)]
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	var bad := ""
	for sp in spots:
		await teleport(find_free_near(sp))
		for dn_ in dirs:
			player.facing = dn_
			await frames(2)
			if mm.center_world.distance_to(player.global_position) > 0.5 or mm.player_marker != Vector2(mm.radius, mm.radius) or mm.arrow_dir.distance_to(dirs[dn_]) > 0.01:
				bad += "[%s %s: %s dir %s] " % [sp, dn_, mm.center_world, mm.arrow_dir]
	check(bad == "", "A5 minimap: centred on the player, the arrow shows her facing (6 places x 4 facings)", bad)
	# real walking: the map moves under the centred arrow
	await teleport(tile_center(31, 29))
	var m0 := mm.center_world
	var s0 := mm.world_to_local(tile_center(31, 29))
	key(KEY_D, true); await frames(60); key(KEY_D, false); await frames(3)
	var s1 := mm.world_to_local(tile_center(31, 29))
	check(mm.center_world.x > m0.x + 20.0 and s1.x < s0.x - 1.0 and absf(s1.y - s0.y) < 0.5 and mm.arrow_dir == Vector2.RIGHT,
		"A5 minimap: walking right scrolls the map left under the arrow, pointing right", "%s -> %s" % [m0, mm.center_world])
	# star at the current objective
	var obj_pos: Vector2 = main.story.star_world()
	var off: Vector2 = (obj_pos - player.global_position) * mm.scale_now()
	var star_ok: bool = mm.star_active and mm.star_target_world.distance_to(obj_pos) < 0.5
	if off.length() <= mm.radius - mm.star_inset:
		star_ok = star_ok and mm.star_marker.distance_to(Vector2(mm.radius, mm.radius) + off) < 0.5
	else:
		star_ok = star_ok and mm.star_on_rim and absf(angle_difference(mm.star_angle(), off.angle())) < 0.02
	check(star_ok, "A5 star: sits at the current objective (or on the rim towards it)", "%s" % mm.star_marker)
	var seen := {}
	for i in 90:
		await physics_frame
		seen[mm.star_shown] = true
	check(seen.has(true) and seen.has(false), "A5 star: blinks (visible and hidden within 1.5 s)")
	# does not cover the player in normal play: screen position of the player vs the circle
	var covered := ""
	for sp in [tile_center(31, 29), Vector2(240, 932), tile_center(32, 21), tile_center(32, 40), tile_center(45, 55)]:
		await teleport(find_free_near(sp))
		await frames(3)
		var sc: Vector2 = main.get_viewport().get_canvas_transform() * player.global_position
		if mm.covers_local(sc - mm.position, 2.0):
			covered += str(sp) + " "
	check(covered == "", "A5 minimap: never covers the player at normal places", covered)
	# HUD pieces do not overlap each other
	await frames(2)
	var rects := {"minimap": Rect2(mm.global_position, mm.size), "objective": main.hud.objective.get_global_rect(), "clock": main.hud.clock.get_global_rect(), "hint": main.hud.hint.get_global_rect()}
	var ov := ""
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if rects[keys[i]].intersects(rects[keys[j]]):
				ov += "%s/%s " % [keys[i], keys[j]]
	check(ov == "", "A5 layout: minimap, objective line, clock and key hint do not overlap", ov + str(rects))
	# if the player is ever under the minimap (map corner), it fades
	await teleport(find_free_near(Vector2(40, 60)))
	await frames(30)
	var sc2: Vector2 = main.get_viewport().get_canvas_transform() * player.global_position
	_log("      corner: player at screen %s, minimap alpha %.2f" % [sc2.round(), mm.modulate.a])
	check(not mm.covers_local(sc2 - mm.position) or mm.modulate.a < 0.5, "A5 minimap: fades if the player would be hidden behind it (map corner)")
