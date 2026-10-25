extends RefCounted
## 启动画面 v1 checks, run by tests/run_tests.gd after every other suite (it takes the test's own game scene out of
## the tree first, so the title and the games it starts are the only things running). Real key / mouse events.
##   AC2 composition: standees (rabbit left facing right, crane right facing left, ~96 px), >= 3 onlookers, logo
##   AC3 effects: leaves (front + back of the swirl), mist, qi motes, ripple, wind - present, moving, looping, restrained
##   AC4 menu: keyboard (↑↓ / W S, E / Enter / Space) and mouse (hover + click); 开始游戏 -> fade -> the same game as
##       a direct launch (spawn, 08:00, full initial-state comparison); 按键与玩法 = the Esc page's content, returns
##   AC5 Esc on the title does nothing; Esc in the game started from the title pauses as before
##   AC6 settings come from data/title.json (moving a value moves the thing)

var r
var title: TitleScreen
var tdata: Dictionary


func _init(runner) -> void:
	r = runner


func run() -> void:
	# the earlier suites' game scene leaves the tree for good (its physics / camera / input must not mix in)
	if r.main != null and r.main.is_inside_tree():
		r.root.remove_child(r.main)
	r.paused = false
	r.release_all()
	tdata = JSON.parse_string(FileAccess.get_file_as_string("res://data/title.json"))
	await test_project_entry()
	await new_title()
	await test_composition()
	await test_effects()
	await test_settings_from_data()
	await test_keyboard_menu()
	await test_mouse_menu()
	await test_help_page()
	await test_esc_on_title()
	await test_start_keyboard_and_identical_state()
	await new_title()
	await test_start_mouse()
	await new_title()
	await test_start_space()
	r.main.queue_free()


# ------------------------------------------------------------------ helpers
## 两条路小样 v1: the menu is 继续游戏 / 新游戏 / 按键与玩法 now (继续游戏 greyed out and skipped without a save, which is
## how these checks run), so the checks below name the buttons by key instead of by position 0 / 1: S() = 新游戏 (the
## former 开始游戏, same key "start"), H() = 按键与玩法. Every check is unchanged otherwise (the ↑↓ wrap now skips the greyed
## 继续游戏, so it still alternates between the two usable buttons).
func S() -> int:
	return title.index_of("start")


func H() -> int:
	return title.index_of("help")


func new_title() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
		await r.process_frame
	title = load("res://scenes/title.tscn").instantiate()
	r.root.add_child(title)
	r.current_scene = title
	await r.frames(3)


func free_game(main: Node) -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
	for n in r.root.get_children():
		if n.name == "TitleFadeIn":
			n.queue_free()
	r.paused = false
	await r.process_frame
	await r.process_frame


## Window position of the centre of a title button (through the camera and the window stretch).
func button_screen_pos(b: Control) -> Vector2:
	return b.get_screen_transform() * (b.size * 0.5)


func mouse_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await r.process_frame
	await r.process_frame


func click(p: Vector2) -> void:
	await mouse_move(p)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await r.process_frame
		await r.process_frame


func style_bg(b: Button) -> Color:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func find_pause_menus(n: Node, out: Array) -> Array:
	if n is PauseMenu:
		out.append(n)
	for c in n.get_children():
		find_pause_menus(c, out)
	return out


func wait_for_game(limit := 240) -> Node:
	for i in limit:
		await r.process_frame
		var cs = r.current_scene
		if cs != null and is_instance_valid(cs) and cs.name == "Main":
			return cs
	return null


## Everything that makes up the opening state of a freshly built game scene.
func game_snapshot(m: Node) -> Dictionary:
	var p: Player = m.player
	var s := {
		"player_pos": p.global_position, "facing": p.facing, "anim": p.sprite.animation, "hp": p.hp,
		"vel": p.velocity, "dash": p.dash_time_left, "cd": p.dash_cooldown_left, "stage": p.attack_stage,
		"input_enabled": p.input_enabled, "focus_guard": p.first_click_guard, "seen_input": p._seen_input,
		"hour": m.daynight.hour, "clock": m.daynight.clock_text(), "clock_running": m.daynight.running,
		"objective": [m.objectives.index, m.objectives.current_text()], "hud_objective": m.hud.objective_label.text,
		"hud_clock": m.hud.clock_label.text, "hint": [m.hud.hint.visible, m.hud.hint_label.text, m.hud.hint_visible],
		"ambience": m.ambience.enabled, "camera": m.camera.global_position, "camera_current": m.camera.is_current(),
		"pause_open": m.pause_menu.is_open, "spar": m.combat.spar_state, "bandits": m.combat.bandits_enabled,
		"bandits_cleared": m.combat.bandits_cleared, "children": m.get_children().map(func(c): return c.get_class() if str(c.name).begins_with("@") else str(c.name)),
		"world_count": m.world.get_child_count(), "colliders": m.solids.get_child_count(),
		"bed_state": m.interiors.bed_state, "room": m.interiors.room_at(p.global_position),
	}
	for n in m.npcs:
		s["npc_" + n.id] = [n.global_position, n.facing if "facing" in n else "", n.visible,
			n.hp if "hp" in n else -1]
	return s


func diff(a: Dictionary, b: Dictionary) -> String:
	var out := ""
	for k in a:
		if not b.has(k) or str(a[k]) != str(b[k]):
			out += "%s: %s vs %s; " % [k, a[k], b.get(k)]
	for k in b:
		if not a.has(k):
			out += "%s only in one; " % k
	return out


# ------------------------------------------------------------------ AC: entry
func test_project_entry() -> void:
	r.check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title.tscn",
		"title AC4: the title screen is the main scene (opens first)")
	r.check(ProjectSettings.get_setting("application/boot_splash/show_image") == false,
		"title AC1: Godot boot splash image is off (no Godot logo when the engine starts)")
	r.check(str(ProjectSettings.get_setting("application/config/name")) == str(tdata["title"]),
		"title AC2/AC6: project name (browser tab / window title) = the title text in data/title.json",
		str(ProjectSettings.get_setting("application/config/name")))
	var icon := str(ProjectSettings.get_setting("application/config/icon"))
	r.check(icon == "res://assets/title/icon.png" and ResourceLoader.exists(icon),
		"title AC1: own project icon (favicon is not the Godot logo)", icon)
	r.check(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) == 0
		and str(ProjectSettings.get_setting("display/window/stretch/scale_mode")) == "integer",
		"title: crisp pixels - nearest filter and integer window scaling")


# ------------------------------------------------------------------ AC2
func test_composition() -> void:
	var rb: AnimatedSprite2D = title.standees.get("rabbit")
	var cr: AnimatedSprite2D = title.standees.get("crane")
	r.check(rb != null and cr != null and rb.is_inside_tree() and cr.is_inside_tree(), "title AC2: both standees are in the scene")
	var art: Dictionary = title.art
	var hr := int(art["rabbit"]["height_px"])
	var hc := int(art["crane"]["height_px"])
	r.check(hr >= 88 and hr <= 104 and hc >= 88 and hc <= 104, "title AC2: standees are about 96 px tall", "rabbit %d, crane %d" % [hr, hc])
	r.check(rb.global_position.x < 240 and cr.global_position.x > 240 and art["rabbit"]["faces"] == "right"
		and art["crane"]["faces"] == "left", "title AC2: rabbit on the left facing right, crane on the right facing left",
		"%s / %s" % [rb.global_position, cr.global_position])
	var tex: Texture2D = rb.sprite_frames.get_frame_texture("idle", 0)
	r.check(tex.get_height() == int(art["rabbit"]["frame_size"][1]) and rb.sprite_frames.get_frame_count("idle") >= 2
		and rb.is_playing() and cr.is_playing(), "title AC2: standees play their idle (breathing) frames")
	# standees fully on screen, the logo above them, the menu below their heads
	var view := Rect2(Vector2.ZERO, TitleScreen.VIEW)
	var ok_view := true
	for s in [rb, cr]:
		var fr: Texture2D = s.sprite_frames.get_frame_texture("idle", 0)
		ok_view = ok_view and view.encloses(Rect2(s.global_position + s.offset, fr.get_size()))
	r.check(ok_view, "title AC2: standees are fully inside the 480x270 picture")
	var ids := []
	var scaled_ok := true
	for o in title.onlookers:
		ids.append(o.get_meta("id"))
		scaled_ok = scaled_ok and o.scale.x == float(int(o.scale.x)) and o.scale.x >= 2.0 and o.is_playing() \
			and o.sprite_frames == CharSheet.frames_for(o.get_meta("id"))
	r.check(ids.size() >= 3 and "fox" in ids and "bear" in ids and "dog" in ids,
		"title AC2: at least 3 onlookers - 师兄 fox, 厨娘 bear, 看门老伯 dog", str(ids))
	r.check(scaled_ok, "title AC2: onlookers are the existing 32 px sprites at a whole-number scale, idle animation playing")
	var logo_ok := title.logo != null and title.logo_label == null
	var stamp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/title/title_logo.json"))
	r.check(logo_ok and stamp["text"] == tdata["title"], "title AC2/AC6: pixel title logo shows the text from data/title.json",
		"logo text '%s' vs title.json '%s'" % [stamp.get("text"), tdata["title"]])
	if logo_ok:
		var lr := Rect2(title.logo.position, title.logo.texture.get_size() * title.logo.scale)
		r.check(view.encloses(lr) and lr.end.y < 80 and title.logo.scale.x == float(int(title.logo.scale.x)),
			"title AC2: logo is at the top, fully visible, integer-scaled", str(lr))
	# everything placed on whole pixels
	var off := ""
	for n in [rb, cr, title.logo] + title.onlookers:
		if n.global_position != n.global_position.round():
			off += n.name + " "
	r.check(off == "", "title: all sprites sit on whole pixels (crisp)", off)
	# all title texts exist in the UI font
	var font: Font = load("res://fonts/ui_font.fnt")
	var text: String = tdata["title"] + tdata["menu"]["continue"] + tdata["menu"]["start"] + tdata["menu"]["help"] + tdata["help_title"] \
		+ tdata["help_back"] + tdata["confirm_overwrite"] + tdata["confirm_yes"] + tdata["confirm_no"]
	var missing := ""
	for c in text:
		if c != " " and not font.has_char(c.unicode_at(0)):
			missing += c
	r.check(missing == "", "title: every title / menu character exists in the UI font", missing)


# ------------------------------------------------------------------ AC3
func test_effects() -> void:
	var need := ["mist0", "mist1", "leaves_back", "leaves_front", "motes", "ripple", "wind"]
	var have := need.filter(func(k): return title.fx.has(k) and title.fx[k].is_inside_tree())
	r.check(have.size() == need.size(), "title AC3: effect nodes present (mist ×2, leaves back/front, qi motes, ripple, wind)", str(have))
	await r.frames(10)
	var drawn := ""
	for k in need:
		if title.fx[k].drawn_items <= 0:
			drawn += k + " "
	r.check(drawn == "", "title AC3: every effect draws something", "nothing drawn: " + drawn)
	# leaves: both bamboo and ginkgo, some in front of and some behind the standees, swirling (positions change)
	var lf: TitleFx = title.fx["leaves_front"]
	var l0: Array = lf.leaf_states()
	var rows := {}
	var front := 0
	for l in l0:
		rows[l["row"]] = true
		front += 1 if l["front"] else 0
	r.check(rows.size() == 2 and front > 0 and front < l0.size(), "title AC3: bamboo + ginkgo leaves swirl around the two (in front and behind)",
		"%d leaves, %d in front" % [l0.size(), front])
	var mist: TitleFx = title.fx["mist0"]
	var m_t0 := mist.t
	var lp0: Vector2 = l0[0]["pos"]
	await r.frames(60)
	var lp1: Vector2 = lf.leaf_states()[0]["pos"]
	r.check(lp0.distance_to(lp1) > 2.0 and mist.t > m_t0 + 0.9, "title AC3: leaves and mist keep moving over time",
		"leaf moved %.1f px in 1 s" % lp0.distance_to(lp1))
	# loops: ripple rings repeat with the period, mist wraps seamlessly at the texture width
	var rp: TitleFx = title.fx["ripple"]
	var period := float(rp.cfg["period"])
	var save_t := rp.t
	rp.t = 1.234
	var a: Array = rp.ripple_rings()
	rp.t = 1.234 + period * 3.0
	var b: Array = rp.ripple_rings()
	rp.t = save_t
	r.check(absf(a[0]["phase"] - b[0]["phase"]) < 0.001 and absf(a[0]["alpha"] - b[0]["alpha"]) < 0.001,
		"title AC3: the ripple loops (same picture every %.1f s)" % period)
	var tex: Texture2D = mist.tex
	var img := tex.get_image()
	var seam := 0
	for y in img.get_height():
		if img.get_pixel(0, y).a8 != img.get_pixel(img.get_width() - 1, y).a8 and absi(img.get_pixel(0, y).a8 - img.get_pixel(img.get_width() - 1, y).a8) > 60:
			seam += 1
	r.check(seam <= 2, "title AC3: the mist strip wraps without a visible seam", "%d rows differ a lot at the seam" % seam)
	var mo: TitleFx = title.fx["motes"]
	var whos := {}
	for m in mo.mote_states():
		var p: Vector2 = m["pos"]
		whos["rabbit" if p.x < 240 else "crane"] = true
	r.check(whos.size() == 2, "title AC3: qi motes around both of them", str(whos.keys()))
	# restrained ("学徒级"): faint motes, a shallow ripple, a moderate number of leaves, no sword-qi / sparks
	var e: Dictionary = tdata["effects"]
	var total_leaves := l0.size()
	var max_mote := 0.0
	for m in mo.mote_states():
		max_mote = maxf(max_mote, m["alpha"])
	var combat_fx := 0
	for n in title.find_children("*", "", true, false):
		if n is CombatFx or n.get_class() in ["GPUParticles2D", "CPUParticles2D"]:
			combat_fx += 1
	r.check(float(e["intensity"]) <= 1.0 and total_leaves <= 30 and max_mote <= 0.8 and float(e["ripple"]["alpha"]) <= 0.5 and combat_fx == 0,
		"title AC3: effects stay restrained (≤30 leaves, motes ≤0.8 opacity, ripple ≤0.5, no slash / spark effects)",
		"leaves %d, mote max %.2f, ripple %.2f, combat fx %d" % [total_leaves, max_mote, float(e["ripple"]["alpha"]), combat_fx])
	# intensity 0 hides the effects, 1 shows them (one knob scales everything)
	lf.intensity = 0.0
	mo.intensity = 0.0
	var none: bool = lf.leaf_states().is_empty() and mo.mote_states().is_empty()
	lf.intensity = float(e["intensity"])
	mo.intensity = float(e["intensity"])
	r.check(none and not lf.leaf_states().is_empty(), "title AC6: effects.intensity scales the effects (0 = off)")


# ------------------------------------------------------------------ AC6
func test_settings_from_data() -> void:
	# moving a value in title.json moves the thing: build a title from an edited copy of the data
	var edited := tdata.duplicate(true)
	edited["standees"]["rabbit"]["feet"] = [120, 230]
	edited["onlookers"][0]["feet"] = [60, 200]
	edited["effects"]["leaves"]["swirls"][0]["bamboo"] = 1
	var t2: TitleScreen = load("res://scenes/title.tscn").instantiate()
	t2.set_meta("data_override", edited)
	r.root.add_child(t2)
	await r.frames(2)
	var moved: bool = t2.standees["rabbit"].position == Vector2(120, 230) and t2.onlookers[0].position == Vector2(60, 200)
	var fewer: bool = t2.fx["leaves_front"].leaf_states().size() == title.fx["leaves_front"].leaf_states().size() - int(tdata["effects"]["leaves"]["swirls"][0]["bamboo"]) + 1
	t2.queue_free()
	await r.process_frame
	# renaming the game: a title text that the pixel logo was not regenerated for is still shown correctly (as text)
	var renamed := tdata.duplicate(true)
	renamed["title"] = "动物武侠"
	var t3: TitleScreen = load("res://scenes/title.tscn").instantiate()
	t3.set_meta("data_override", renamed)
	r.root.add_child(t3)
	await r.frames(2)
	var renamed_ok: bool = t3.logo == null and t3.logo_label != null and t3.logo_label.text == "动物武侠"
	t3.queue_free()
	await r.process_frame
	r.check(renamed_ok, "title AC6: a new title text is never shown with the old logo (falls back to text until the logo is regenerated)")
	title.camera.make_current()
	r.check(moved and fewer, "title AC6: positions and effect counts come from data/title.json (edited copy moves / changes them)")
	r.current_scene = title


# ------------------------------------------------------------------ AC4 keyboard
func test_keyboard_menu() -> void:
	title.select(S())
	await r.frames(2)
	var hi := style_bg(title.button("start"))
	var lo := style_bg(title.button("help"))
	r.check(title.selected == S() and hi != lo and hi.get_luminance() > lo.get_luminance() + 0.3,
		"title AC4: 开始游戏 is selected first and clearly highlighted", "selected %s / other %s" % [hi, lo])
	var seq := []
	for k in [KEY_DOWN, KEY_DOWN, KEY_UP, KEY_S, KEY_W, KEY_S]:
		await r.tap(k)
		seq.append(title.selected)
	r.check(seq == [H(), S(), H(), S(), H(), S()], "title AC4: ↑↓ and W / S move the selection (wrapping)", str(seq))
	await r.tap(KEY_DOWN)
	r.check(title.selected == H() and style_bg(title.button("help")) == hi and style_bg(title.button("start")) == lo,
		"title AC4: the highlight follows the selection")
	var opened := []
	for k in [KEY_ENTER, KEY_SPACE, KEY_E]:
		title.select(H())
		await r.tap(k)
		opened.append(title.help.is_open)
		await r.tap(KEY_ESCAPE)
	r.check(opened == [true, true, true] and not title.help.is_open,
		"title AC4: Enter, Space and E each confirm the selected item (opened 按键与玩法 each time)", str(opened))
	title.select(S())


# ------------------------------------------------------------------ AC4 mouse
func test_mouse_menu() -> void:
	title.select(S())
	await mouse_move(button_screen_pos(title.button("help")))
	var hover1 := title.selected
	await mouse_move(button_screen_pos(title.button("start")))
	var hover0 := title.selected
	r.check(hover1 == H() and hover0 == S(), "title AC4: mouse hover selects (and highlights) the button under it",
		"hover help -> %d, hover start -> %d" % [hover1, hover0])
	await click(button_screen_pos(title.button("help")))
	var by_click := title.help.is_open
	await click(title.help.resume_button.get_screen_transform() * (title.help.resume_button.size * 0.5))
	r.check(by_click and not title.help.is_open, "title AC4: clicking 按键与玩法 opens the page, clicking 返回 closes it")
	await mouse_move(Vector2(5, 5))


# ------------------------------------------------------------------ AC4 help page
func test_help_page() -> void:
	title.select(H())
	await r.tap(KEY_ENTER)
	await r.process_frame
	var h: PauseMenu = title.help
	var text := ""
	for l in h.key_labels + h.tip_labels:
		text += l.text + "\n"
	var expect := ""
	for k in PauseMenu.KEYS:
		expect += k[0] + "\n" + k[1] + "\n"
	for t in PauseMenu.TIPS:
		expect += "%s：%s\n" % [t[0], t[1]]
	r.check(h.is_open and h.root.visible and text == expect and h.key_labels.size() == PauseMenu.KEYS.size() * 2
		and h.tip_labels.size() == PauseMenu.TIPS.size(),
		"title AC4: 按键与玩法 shows exactly the Esc page's keys and tips (same PauseMenu.KEYS / TIPS, one source)")
	r.check(h.title_label.text == tdata["help_title"] and h.resume_button.text == tdata["help_back"] and not r.paused,
		"title AC4: help page heading / back button from title.json, and the title is not paused",
		"%s / %s / paused %s" % [h.title_label.text, h.resume_button.text, r.paused])
	var vp: Vector2 = title.get_viewport().get_visible_rect().size
	r.check(Rect2(Vector2.ZERO, vp).encloses(h.panel.get_global_rect()), "title AC4: help page fits on the screen")
	await r.tap(KEY_ESCAPE)
	var back_esc: bool = not h.is_open and r.current_scene == title and title.selected == H()
	await r.tap(KEY_ENTER)
	await r.tap(KEY_E)
	var back_e: bool = not h.is_open
	await r.tap(KEY_ENTER)
	await r.tap(KEY_ENTER)
	var back_enter: bool = not h.is_open
	r.check(back_esc and back_e and back_enter and title.activations.count("start") == 0,
		"title AC4: Esc / E / Enter return from the help page to the title (selection kept, nothing started)",
		"esc %s e %s enter %s" % [back_esc, back_e, back_enter])


# ------------------------------------------------------------------ AC5 Esc on the title
func test_esc_on_title() -> void:
	var before := title.activations.size()
	title.select(S())
	await r.tap(KEY_ESCAPE)
	await r.frames(5)
	await r.tap(KEY_ESCAPE)
	await r.frames(5)
	var pms := find_pause_menus(r.root, [])
	var only_help: bool = pms.size() == 1 and pms[0] == title.help and not pms[0].is_open
	r.check(not r.paused and only_help and title.activations.size() == before and r.current_scene == title
		and title.selected == S(), "title AC5: Esc on the title does nothing (no pause page, nothing paused, nothing chosen)",
		"paused %s, pause menus %d, help open %s" % [r.paused, pms.size(), title.help.is_open])


# ------------------------------------------------------------------ AC4 start (keyboard) + identical state + AC5 in game
func test_start_keyboard_and_identical_state() -> void:
	var box := {}
	title.game_started.connect(func(m): box["snap"] = game_snapshot(m), CONNECT_ONE_SHOT)
	title.select(S())
	var fade: ColorRect = title.fade_rect
	await r.tap(KEY_ENTER)
	await r.frames(12)
	var mid := fade.color.a if is_instance_valid(fade) else -1.0
	var main := await wait_for_game()
	r.check(mid > 0.05 and mid < 0.95, "title AC4: 开始游戏 fades out first", "fade alpha after 0.2 s: %.2f" % mid)
	r.check(main != null and (not is_instance_valid(title) or not title.is_inside_tree()),
		"title AC4: after the fade the game scene replaces the title")
	if main == null:
		return
	var data: Dictionary = main.data
	# 室内图进游戏 v1 (script v3): the game starts inside the dorm, the rabbit asleep in her bed (no longer at the
	# outdoor spawn in front of the dorm door) - same check, the start spot moved
	var sp: Vector2 = main.interiors.bed_world()
	var snap: Dictionary = box.get("snap", {})
	r.check(snap.get("player_pos", Vector2.INF).distance_to(sp) < 0.5 and snap.get("facing") == "down" and main.interiors.room_at(sp) == "dorm_main",
		"title AC4: the game starts at the opening spot (in bed in the dorm room) facing down", str(snap.get("player_pos")))
	r.check(absf(float(snap.get("hour", -1.0)) - float(Tuning.data()["start_hour"])) < 0.001 and snap.get("clock") == "辰时 08:00",
		"title AC4: the game starts at 08:00", str(snap.get("clock")))
	var overlay: Node = null
	for n in r.root.get_children():
		if n.name == "TitleFadeIn":
			overlay = n
	r.check(overlay != null and not main.is_ancestor_of(overlay), "title AC4: the fade-in overlay is separate from the game scene")
	# a direct launch of scenes/main.tscn, snapshot at the same moment (right after it is built)
	var direct: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(direct)
	var dsnap := game_snapshot(direct)
	direct.queue_free()
	await r.process_frame
	var d := diff(dsnap, snap)
	r.check(d == "" and snap.size() > 30, "title AC4: game state after 开始游戏 is identical to a direct launch (%d values: player, clock, objective, HUD, NPCs, combat, camera, scene tree)" % snap.size(), d)
	# the confirm key did not leak into the game, the overlay fades away
	await r.frames(int(float(tdata["fade_in_seconds"]) * 60.0) + 20)
	var p: Player = main.player
	var gone := true
	for n in r.root.get_children():
		if n.name == "TitleFadeIn":
			gone = false
	r.check(p.attack_stage == 0 and p.dash_time_left == 0.0 and p.global_position.distance_to(sp) < 0.5 and gone,
		"title AC4: the key that started the game does not act in it (no attack / dodge / step); the fade-in overlay is gone",
		"pos %s stage %d dash %.2f overlay gone %s" % [p.global_position, p.attack_stage, p.dash_time_left, gone])
	# AC5: in the game Esc pauses and opens the page, Esc again resumes
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var paused_ok: bool = main.pause_menu.is_open and r.paused and not main.pause_menu.help_only
	await r.tap(KEY_ESCAPE)
	await r.process_frame
	var resumed_ok: bool = not main.pause_menu.is_open and not r.paused
	r.check(paused_ok and resumed_ok, "title AC5: in the game started from the title, Esc pauses (help page) and Esc again resumes")
	await free_game(main)


func test_start_mouse() -> void:
	await click(button_screen_pos(title.button("start")))
	var main := await wait_for_game()
	r.check(main != null and main.player.global_position.distance_to(main.interiors.bed_world()) < 0.5
		and main.player.attack_stage == 0, "title AC4: clicking 开始游戏 starts the game at the opening spot (the click does not attack)")
	await free_game(main)


func test_start_space() -> void:
	title.select(S())
	await r.tap(KEY_SPACE)
	var main := await wait_for_game()
	await r.frames(10)
	r.check(main != null and main.player.dash_time_left == 0.0 and main.player.global_position.distance_to(main.interiors.bed_world()) < 0.5,
		"title AC4: Space starts the game too (and does not make the rabbit dodge)")
	await free_game(main)
