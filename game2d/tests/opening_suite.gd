extends RefCounted
## 开场过场动画 v1 checks (docs/design/开场过场动画-方案-v1.md), run by tests/run_tests.gd, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-opening
## Drives the real title screen with real key / mouse events. The runner keeps Opening.enabled off for the older
## suites (they start the game from the title and expect it at once); this suite turns it on and restores it.
##   data      7 HD pictures (960x540, shown at half size = the whole 480x270 frame), the narration word for word = the plan (Chinese and the plan's 7 English
##             sentences), ~60 s, hold 1 s
##   new game  新游戏 -> the opening -> the existing prologue opening (S1-醒来, first line, nothing leaked), the game
##             state identical to a direct start; 继续游戏 never plays it; 新游戏 over a save (确定) plays it
##   controls  E: whole narration first, then the next picture; Space / Enter / left click the same; an Esc tap does
##             nothing; holding Esc fills the ring and skips after 1 s
##   camera    (坐姿-高清过场-运镜 方案 v1, 三) the data: only pictures 1 and 7 move (one eased move each), the rest are
##             fixed frames; picture 7 ends at zoom 2 (one picture pixel = one game pixel); exactly one shake (picture 4's
##             thunder, 0.3 s), both lightning flashes kept
##   timeline  one whole unattended run: lines fade in one by one, picture 4 flashes and shakes once (0.3 s, dying
##             away), picture 6 lights its three panels in order, only pictures 1 and 7 move - once, then hold - the
##             picture sits on whole pixels in every frame and always fills the frame, it ends by itself after about a
##             minute
##   replay    「重看序幕」 bottom-left: plays only the opening, then the title is back (no game started)
##   layout    every narration line, the hint and the ring inside the 480x270 picture and apart, in both languages

var r
var tt                      # title_suite (title / click / snapshot helpers)
var title: TitleScreen
var data: Dictionary
var was_enabled := false

const PLAN_ZH := [
	"这是一个由走兽飞禽组成的江湖。",
	"门派林立，各怀绝技。胜负，往往只在一招之间。",
	"山上曾有一座门派。身法轻灵，专在危难时护人脱险。山下的人，至今还记得它。",
	"直到那一年，藏经阁塌了半座。弟子们一个接一个，下了山。",
	"如今，山门破旧，只剩三个人守着。",
	"一位不爱提起过去的师父；一个嘴欠却护短的师兄——",
	"还有一只小兔子。他的故事，从一个漏雨的早晨开始。",
]
const PLAN_EN := [
	"This is a jianghu of beasts and birds.",
	"Sects rise everywhere, each with its own art. A duel is often won or lost in a single move.",
	"Once, a sect stood on this mountain. Light of foot, it came to the rescue of those in danger. The folk below still remember it.",
	"Until that year, when half the Scripture Library fell. One by one, the disciples went down the mountain.",
	"Now the gate is old and worn, and only three remain.",
	"A Master who never speaks of the past; a Senior Brother with a sharp tongue and a soft heart—",
	"And a little rabbit. His story begins one rainy morning.",
]


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	r.root.size = Vector2i(1440, 810)
	was_enabled = Opening.enabled
	Opening.enabled = true
	Lang.set_lang("zh")
	SaveGame.erase()
	tt = load("res://tests/title_suite.gd").new(r)
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/opening.json"))
	await test_data()
	test_camera_data()
	await test_new_game()
	await test_continue_skips_opening()
	await test_new_over_save()
	await test_skip_hold()
	await test_other_keys()
	await test_replay()
	await test_layout("zh")
	Lang.set_lang("en")
	await test_layout("en")
	Lang.set_lang("zh")
	await test_timeline()
	if title != null and is_instance_valid(title):
		title.queue_free()
	await r.process_frame
	SaveGame.erase()
	Opening.enabled = was_enabled


# ------------------------------------------------------------------ helpers
func new_title() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
		await r.process_frame
	title = load("res://scenes/title.tscn").instantiate()
	r.root.add_child(title)
	r.current_scene = title
	await r.frames(3)


func find_opening() -> Opening:
	for n in _all(r.root, []):
		if n is Opening and is_instance_valid(n) and n.state != "done":
			return n
	return null


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func wait_opening(limit := 120) -> Opening:
	for i in limit:
		await r.process_frame
		var o := find_opening()
		if o != null:
			return o
	return null


func click_at(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await r.process_frame
		await r.process_frame


## Screen (window) rectangle of a Control inside the opening's 480x270 frame, in frame pixels.
func in_frame(o: Opening, c: Control) -> Rect2:
	return Rect2(c.global_position - o.frame.global_position, c.size)


## Window position of the centre of a title button (canvas -> window: the stretch transform of the root).
func btn_pos(b: Control) -> Vector2:
	return r.root.get_final_transform() * (b.get_global_transform_with_canvas() * (b.size * 0.5))


func frame_box() -> Rect2:
	return Rect2(Vector2.ZERO, Opening.VIEW)


func make_save() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	await r.frames(3)
	SaveGame.write(SaveGame.capture(m), "opening test")
	m.queue_free()
	await r.process_frame


# ------------------------------------------------------------------ data
func test_data() -> void:
	var scenes: Array = data["scenes"]
	# (was: 7 pictures of 480x270. 方案 v1 二 redraws them at 960x540 = twice the pixels each way; the old ones stay in
	# assets/opening/ but are no longer listed. Same strength: every listed picture is loaded and its size checked, and
	# now also that the half-size picture covers exactly the 480x270 frame.)
	var sizes_ok := true
	for sc in scenes:
		var tex: Texture2D = load("res://assets/opening/" + str(sc["image"]))
		if tex == null or tex.get_size() != Opening.VIEW * 2:
			sizes_ok = false
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/opening/" + str(data.get("art", ""))))
	var listed := true
	for sc in scenes:
		if not str(sc["image"]) in meta.get("scenes", []):
			listed = false
	r.check(scenes.size() == 7 and sizes_ok and listed and str(meta.get("size", [])) == str([960.0, 540.0]) and bool(data.get("pixel_aa", false)),
		"opening: 7 full-screen HD pictures of 960x540 in assets/opening/ (data/opening.json -> opening_art_hd.json), drawn pixel-aligned")
	var zh_ok := true
	var en_ok := true
	var bad := ""
	var total := 0.0
	for i in scenes.size():
		var ls: Array = scenes[i]["lines"]
		var zh := "".join(ls.map(func(x): return str(x)))
		Lang.set_lang("en")
		var en := " ".join(ls.map(func(x): return Lang.t(str(x))))
		Lang.set_lang("zh")
		if zh != PLAN_ZH[i]:
			zh_ok = false
			bad += "zh %d; " % (i + 1)
		if en != PLAN_EN[i]:
			en_ok = false
			bad += "en %d '%s'; " % [i + 1, en]
		if (scenes[i]["line_times"] as Array).size() != ls.size() or ls.size() > 3:
			zh_ok = false
		total += float(scenes[i]["seconds"])
	total += float(data["fade_in_seconds"]) + float(data["end_fade_seconds"])
	r.check(zh_ok and en_ok, "opening: the narration is the plan's text word for word, in Chinese and in the plan's 7 English sentences", bad)
	r.check(total >= 55.0 and total <= 65.0 and absf(float(data["skip_hold_seconds"]) - 1.0) < 0.001,
		"opening: about one minute long (%.1f s), skip = hold Esc 1 s" % total)
	Lang.set_lang("en")
	var hint_en := Lang.t(str(data["hint"]))
	var replay_en := Lang.t(str(data["replay_button"]["text"]))
	Lang.set_lang("zh")
	r.check(hint_en == "E Continue · Hold Esc to Skip" and replay_en == "Replay Prologue",
		"opening: the hint and the 重看序幕 button have English", "%s / %s" % [hint_en, replay_en])


# ------------------------------------------------------------------ calm camera (data)
func test_camera_data() -> void:
	var scenes: Array = data["scenes"]
	var moving: Array = []
	var static_ok := true
	var moves_ok := true
	var shakes: Array = []
	var flashes := 0
	for i in scenes.size():
		var cam: Dictionary = scenes[i]["camera"]
		if cam.has("move"):
			moving.append(i)
			var m: Array = cam["move"]
			var z0 := float(cam["from"]["zoom"])
			var z1 := float(cam["to"]["zoom"])
			# one move, inside the picture, eased, slow (at least 5 s), never zooming out past the whole picture
			if not (float(m[0]) >= 0.0 and float(m[1]) - float(m[0]) >= 5.0 and float(m[1]) < float(scenes[i]["seconds"])
					and str(cam.get("ease", "")) == "sine" and z0 >= 1.0 and z1 >= 1.0):
				moves_ok = false
		elif not (cam.get("center", []) == [240.0, 135.0] and float(cam.get("zoom", 0.0)) == 1.0):
			static_ok = false
		for e in scenes[i].get("effects", []):
			if e["type"] == "shake":
				shakes.append([i, float(e["seconds"]), float(e["px"])])
			elif e["type"] == "flash":
				flashes += 1
	var c1: Dictionary = scenes[0]["camera"]
	var c7: Dictionary = scenes[6]["camera"]
	var pan_ok: bool = moving == [0, 6] and float(c1["to"]["center"][0]) > float(c1["from"]["center"][0]) \
		and c1["to"]["center"][1] == c1["from"]["center"][1] and float(c1["to"]["zoom"]) == float(c1["from"]["zoom"])
	var push_ok: bool = moving == [0, 6] and float(c7["from"]["zoom"]) == 1.0 and float(c7["to"]["zoom"]) == 2.0
	r.check(moving == [0, 6] and static_ok and moves_ok and pan_ok and push_ok,
		"opening camera data: only picture 1 (one left-to-right pan) and picture 7 (one push-in from the whole picture to zoom 2 = one picture pixel per game pixel) move, each once over >= 5 s with a sine ease; the other 5 are fixed whole-picture frames",
		"moving %s" % str(moving))
	r.check(shakes.size() == 1 and shakes[0][0] == 3 and absf(shakes[0][1] - 0.3) < 0.051 and shakes[0][2] <= 4.0 and flashes == 2,
		"opening camera data: exactly one shake (picture 4's thunder, 0.3 s), both lightning flashes kept", str(shakes))


# ------------------------------------------------------------------ 新游戏 -> opening -> prologue
func test_new_game() -> void:
	SaveGame.erase()
	await new_title()
	Opening.music_log.clear()
	var box := {}
	title.game_started.connect(func(m): box["snap"] = tt.game_snapshot(m), CONNECT_ONE_SHOT)
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var o := await wait_opening()
	r.check(o != null and o.mode == "new" and o.index == 0 and r.current_scene == title and o.hint.visible
		and o.hint.text == str(data["hint"]) and "opening" in Opening.music_log,
		"opening: 新游戏 fades out, then the opening plays (picture 1, hint 'E 继续 · 按住 Esc 跳过' in the corner, the opening music asked for) before the game exists")
	if o == null:
		return
	await r.frames(30)
	var before := o.lines[0].modulate.a
	await r.tap(KEY_E)
	await r.frames(1)
	var revealed: bool = o.index == 0 and o.all_shown() and o.lines[0].modulate.a > 0.99
	await r.tap(KEY_E)
	await r.frames(1)
	r.check(before < 0.99 and revealed and o.index == 1,
		"opening: E first shows the whole narration of the picture, E again goes to the next picture",
		"alpha before %.2f, index %d" % [before, o.index])
	# E through the rest; the press that ends the last picture must not reach the game
	var seen := [0, 1]
	for i in 40:
		if find_opening() == null:
			break
		await r.tap(KEY_E)
		if is_instance_valid(o) and not o.index in seen:
			seen.append(o.index)
	var main: Node = await tt.wait_for_game(200)
	r.check(seen.size() == 7 and main != null, "opening: E steps through all 7 pictures, then the game starts", str(seen))
	if main == null:
		return
	await r.frames(2)
	var story: Story = main.story
	var dlg: Dialogue = story.dialogue
	r.check(story.current_scene == "S1-醒来" and dlg.active and dlg.kind == "旁白" and dlg.page == 0
		and main.interiors.bed_state == "sleeping",
		"opening: after the opening the existing prologue opening runs (S1-醒来, 滴答 narration on its first page, asleep in bed) - the last E did not leak into it",
		"%s %s page %d" % [story.current_scene, dlg.kind, dlg.page])
	var direct: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(direct)
	var dsnap: Dictionary = tt.game_snapshot(direct)
	direct.queue_free()
	await r.process_frame
	var d: String = tt.diff(dsnap, box.get("snap", {}))
	r.check(d == "", "opening: the game after the opening starts in exactly the state of a direct start", d)
	await tt.free_game(main)
	title = null


func test_continue_skips_opening() -> void:
	await make_save()
	await new_title()
	var made := [false]
	var watcher := func(n): if n is Opening: made[0] = true
	r.root.get_tree().node_added.connect(watcher)
	title.select(title.index_of("continue"))
	await r.tap(KEY_ENTER)
	var main: Node = await tt.wait_for_game(200)
	r.root.get_tree().node_added.disconnect(watcher)
	r.check(main != null and not made[0], "opening: 继续游戏 goes straight into the game, the opening never plays")
	await tt.free_game(main)
	title = null


func test_new_over_save() -> void:
	await make_save()
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)              # 会覆盖存档，确定吗？
	title._confirm_select(0)
	await r.tap(KEY_ENTER)              # 确定
	var o := await wait_opening()
	r.check(o != null and o.mode == "new", "opening: 新游戏 over a save (确定) also plays the opening")
	if o != null:
		o.skip()
	var main: Node = await tt.wait_for_game(200)
	r.check(main != null and main.story.current_scene == "S1-醒来", "opening: …and the prologue follows it")
	await tt.free_game(main)
	title = null
	SaveGame.erase()


# ------------------------------------------------------------------ skip / keys
func test_skip_hold() -> void:
	SaveGame.erase()
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var o := await wait_opening()
	if o == null:
		r.check(false, "opening: skip (no opening)")
		return
	# a short tap does nothing
	r.key(KEY_ESCAPE, true)
	await r.frames(12)
	r.key(KEY_ESCAPE, false)
	await r.frames(3)
	r.check(o.state == "play" and o.progress() == 0.0 and not o.skipped and o.index == 0,
		"opening: a short Esc tap (0.2 s) does not skip, the ring empties again")
	# holding: the ring fills, the skip comes at 1 s, not before
	r.key(KEY_ESCAPE, true)
	await r.frames(30)
	var half := o.progress()
	var still := o.state == "play"
	await r.frames(36)
	r.key(KEY_ESCAPE, false)
	r.check(still and half > 0.4 and half < 0.6 and o.skipped and o.state != "play",
		"opening: holding Esc fills the ring in the corner (half after 0.5 s) and skips the whole opening after 1 s",
		"progress at 0.5 s %.2f" % half)
	var main: Node = await tt.wait_for_game(120)
	r.check(main != null and main.story.current_scene == "S1-醒来" and not main.pause_menu.is_open,
		"opening: after the skip the prologue starts (Esc did not open the pause page)")
	await tt.free_game(main)
	title = null


func test_other_keys() -> void:
	SaveGame.erase()
	await new_title()
	await tt.click(btn_pos(title.button("start")))
	var o := await wait_opening()
	if o == null:
		r.check(false, "opening: keys (no opening)")
		return
	await r.frames(10)
	var p: Vector2 = o.frame.get_global_transform_with_canvas() * (Opening.VIEW * 0.5)
	var res := []
	for k in ["click", KEY_SPACE, KEY_ENTER]:
		var idx := o.index
		for n in 2:
			if k is String:
				await click_at(r.root.get_final_transform() * p)
			else:
				await r.tap(k)
		res.append(o.index == idx + 1)
	r.check(res == [true, true, true], "opening: left click, Space and Enter work like E (whole narration, then the next picture)", str(res))
	o.skip()
	var main: Node = await tt.wait_for_game(120)
	await tt.free_game(main)
	title = null


# ------------------------------------------------------------------ replay
func test_replay() -> void:
	SaveGame.erase()
	await new_title()
	var b: Button = title.replay_button
	var rect := Rect2(b.position, b.size)
	var menu_clear := true
	for mb in title.buttons:
		if Rect2(mb.position, mb.size).intersects(rect):
			menu_clear = false
	r.check(b != null and b.visible and b.text == "重看序幕" and rect.position.x < 40 and rect.end.y <= 270 and rect.position.x >= 0
		and rect.end.y > 230 and menu_clear,
		"opening: 「重看序幕」 is a small button in the bottom-left corner of the title, clear of the menu", str(rect))
	await tt.click(btn_pos(b))
	var o := await wait_opening()
	r.check(o != null and o.mode == "replay" and title.replaying, "opening: 重看序幕 plays the opening")
	if o == null:
		return
	for i in 40:
		if find_opening() == null:
			break
		await r.tap(KEY_E)
	await r.frames(60)
	var main_made := false
	for n in r.root.get_children():
		if n.name == "Main":
			main_made = true
	r.check(find_opening() == null and is_instance_valid(title) and r.current_scene == title and not title.replaying
		and not main_made and title.fade_rect.color.a < 0.05 and not title.starting,
		"opening: after the replay the title screen is back (no game started, the picture faded back in)")
	# the title still works: 新游戏 after a replay plays the opening again and starts the game
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var o2 := await wait_opening()
	var played := o2 != null
	if played:
		o2.skip()
	var main: Node = await tt.wait_for_game(200)
	r.check(played and main != null, "opening: 新游戏 after a replay still plays the opening and starts the game")
	await tt.free_game(main)
	title = null


# ------------------------------------------------------------------ layout
func test_layout(lang: String) -> void:
	await new_title()
	await tt.click(btn_pos(title.replay_button))
	var o := await wait_opening()
	if o == null:
		r.check(false, "opening layout (%s): no opening" % lang)
		return
	await r.frames(5)
	var bad := ""
	var cjk := RegEx.create_from_string(LangTranslation.CJK)
	for i in 7:
		o.reveal_all()
		await r.frames(2)
		var hint_r := in_frame(o, o.hint)
		var ring_r := in_frame(o, o.ring)
		if not frame_box().encloses(hint_r) or not frame_box().encloses(ring_r) or hint_r.intersects(ring_r):
			bad += "hint/ring %d; " % i
		var prev_end := -1.0
		for k in o.lines.size():
			var l: Label = o.lines[k]
			if not l.visible:
				continue
			var lr := in_frame(o, l)
			var shown: String = Lang.t(l.text)
			if not frame_box().encloses(lr) or lr.intersects(hint_r) or lr.position.y < prev_end - 0.5:
				bad += "line %d.%d %s; " % [i, k, lr]
			if lang == "en" and cjk.search(Lang.t(l.text)) != null:
				bad += "cjk %d.%d; " % [i, k]
			prev_end = lr.end.y
			if l.get_line_count() > 2:
				bad += "wrap %d.%d (%d lines: %s); " % [i, k, l.get_line_count(), shown]
		await r.tap(KEY_E)
		await r.frames(2)
	var b: Button = title.replay_button
	var br := Rect2(b.position, b.get_combined_minimum_size().max(b.size))
	if not Rect2(0, 0, 480, 270).encloses(br):
		bad += "replay button %s; " % br
	r.check(bad == "", "opening layout (%s): every narration line, the hint and the skip ring stay inside the 480x270 picture and apart; the 重看序幕 button fits" % lang, bad)
	if find_opening() != null:
		find_opening().skip()
	await r.frames(60)


# ------------------------------------------------------------------ timeline (one whole unattended run)
func test_timeline() -> void:
	await new_title()
	await tt.click(btn_pos(title.replay_button))
	var o := await wait_opening()
	if o == null:
		r.check(false, "opening timeline: no opening")
		return
	var frames := 0
	var line_ok := true
	var order := ""
	var flash_max := 0.0
	var shake_seen := false
	var panels_order: Array = []
	var framings := {}          # picture -> distinct (position without shake, scale) seen
	var whole_px := true
	var covers := true
	var held := true
	var shake_frames: Array = []        # [picture, t, |offset|] of every frame with a shake offset
	var last_index := -1
	var started_lines := {}
	while find_opening() != null and frames < 60 * 75:
		await r.process_frame
		frames += 1
		if not is_instance_valid(o) or o.state != "play":
			continue
		if o.index != last_index:
			last_index = o.index
			order += str(o.index)
		var sc: Dictionary = o.scene()
		var times: Array = sc["line_times"]
		for k in times.size():
			var key := "%d.%d" % [o.index, k]
			if o.lines[k].modulate.a > 0.0 and not started_lines.has(key):
				started_lines[key] = o.t
				if absf(o.t - float(times[k])) > 0.1:
					line_ok = false
		if o.index == 3:
			flash_max = maxf(flash_max, o.flash.color.a)
			if o.shake_offset() != Vector2.ZERO:
				shake_seen = true
		var off := o.shake_offset()
		if off != Vector2.ZERO:
			shake_frames.append([o.index, o.t, maxf(absf(off.x), absf(off.y))])
		var pos := o.cur.position
		if pos != pos.round():
			whole_px = false
		var base := pos - off
		var key := "%s|%.5f" % [base, o.cur.scale.x]
		if not framings.has(o.index):
			framings[o.index] = {}
		framings[o.index][key] = true
		# the picture always covers the whole 480x270 frame (no black edge), except the few shake pixels
		var size := o.cur.texture.get_size() * o.cur.scale
		if not Rect2(base, size).grow(0.01).encloses(Rect2(Vector2.ZERO, Opening.VIEW)):
			covers = false
		# hold: after its one move the framing does not change any more (checked against the end framing)
		if o.moves() and o.t > float(sc["camera"]["move"][1]) + 0.05:
			var end := Vector2(float(sc["camera"]["to"]["center"][0]), float(sc["camera"]["to"]["center"][1]))
			var z := float(sc["camera"]["to"]["zoom"])
			var want := (Opening.VIEW * 0.5 - end * z).round()
			if base != want or absf(o.cur.scale.x - z * o.tex_scale) > 0.0001:
				held = false
		if o.index == 5:
			for k in o.dimmers.size():
				if o.dimmers[k].color.a < 0.4 and not k in panels_order:
					panels_order.append(k)
	var secs := frames / 60.0
	var n_lines := 0
	for sc in data["scenes"]:
		n_lines += (sc["lines"] as Array).size()
	r.check(order == "0123456" and line_ok and started_lines.size() == n_lines and n_lines == 13,
		"opening timeline: unattended, the 7 pictures follow each other and all 13 narration lines fade in one by one at their times",
		"order %s, lines %d" % [order, started_lines.size()])
	r.check(flash_max > 0.6 and shake_seen, "opening timeline: picture 4 flashes white and shakes", "flash %.2f" % flash_max)
	r.check(panels_order == [0, 1, 2], "opening timeline: picture 6 lights its three panels one after another (师父, 师兄, 小兔)", str(panels_order))
	# (was: "the camera moves on at least 6 pictures". 方案 v1 三 makes 5 of the 7 fixed frames, so this now checks
	# the opposite, with the same per-frame measurement: pictures 1 and 7 move a lot, every other picture never moves.)
	var moved: Array = []
	for i in framings:
		if framings[i].size() > 1:
			moved.append(i)
	moved.sort()
	r.check(moved == [0, 6] and framings.get(0, {}).size() > 20 and framings.get(6, {}).size() > 20 and held,
		"opening timeline: only picture 1 (pan) and picture 7 (push-in) move - once, then they hold their end framing; the other five never move",
		"moved %s, framings %s, held %s" % [str(moved), str(framings.keys().map(func(k): return framings[k].size())), held])
	r.check(whole_px and covers, "opening timeline: in every frame the picture sits on whole game pixels and fills the whole 480x270 frame",
		"whole px %s, covers %s" % [whole_px, covers])
	var sh_ok := not shake_frames.is_empty()
	var first_half := 0.0
	var second_half := 0.0
	for f in shake_frames:
		if f[0] != 3 or f[1] < 0.9 - 0.001 or f[1] > 0.9 + 0.3:
			sh_ok = false
		if f[1] < 1.05:
			first_half = maxf(first_half, f[2])
		else:
			second_half = maxf(second_half, f[2])
	r.check(sh_ok and first_half >= 2.0 and second_half < first_half,
		"opening timeline: the screen shakes exactly once - picture 4 at the thunder, within 0.3 s, dying away (strongest first)",
		"%d shaking frames, max %.0f then %.0f" % [shake_frames.size(), first_half, second_half])
	r.check(secs > 55.0 and secs < 65.0 and is_instance_valid(title) and r.current_scene == title,
		"opening timeline: it ends by itself after about a minute (%.1f s) and the title is back" % secs)
