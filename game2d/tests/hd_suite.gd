extends RefCounted
## 坐姿重画 + 高清头像 + 封面高清小兔 (docs/design/坐姿-高清过场-运镜-方案-v1.md sections 一, 二 and 补充):
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-hd     (also part of the full run)
##   seats     every seat has a pose in data/interiors.json: 厨房长凳 / 小板凳 = "back", 坐垫 / 蒲团 = "cross"; sitting there
##             (real E key) plays the back-view frames facing up / the cross-legged frames facing down, from the new sheets
##   art       the back sheet has no face (no nose / blush / pink inner ears), its seat rows are empty (the room's board
##             shows) and below them his shins + sandals hang; the cross sheet shows the face, the sandals and the paws on
##             the knees; both breathe (2 different frames)
##   no pad    no blue cushion on wooden seats: in the back frames no trouser-blue run wider than 3 px and none at all in
##             the seat rows (the old front picture had a 20 px blue "cushion" - checked too, so the test can fail)
##   portraits every speaker's portrait is the 128x128 HD picture, drawn 64x64 in the unchanged box (HD sampling)
##   title     the title rabbit is the HD texture (160x208 frames from title_hd.json) at scale 0.5 on the same feet: the
##             same 80x104 on-screen box as before
## Every check is on the real game / title scene (tests/schedule_suite.gd helpers for the seats).

var r
var t                      # schedule_suite (game, seat_spot, ...)
var report := {}

const BLUE_KEYS := ["P", "p", "q"]


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	r.root.size = Vector2i(1440, 810)
	SaveGame.erase()
	t = load("res://tests/schedule_suite.gd").new(r)
	t.ss = load("res://tests/sample_suite.gd").new(r)
	t.t3 = load("res://tests/step3_suite.gd").new(r)
	t.t3.ss = t.ss
	t.s4 = load("res://tests/step4a_suite.gd").new(r)
	t.s4.ss = t.ss
	t.s4.t3 = t.t3
	test_seat_data()
	test_sit_art()
	await test_sitting()
	await test_portraits()
	await t.ss._free_game()
	SaveGame.erase()
	await test_title()
	print("HD REPORT ", report)


# ------------------------------------------------------------------ helpers
func rabbit_colors() -> Dictionary:
	## his colours from pixel2d/characters/characters.toml, as the game ships them (CharSheet reads the sheet only), so
	## they are listed here: trouser blues, nose, blush, inner ear, sandal.
	return {"P": Color("#5e6b88"), "p": Color("#48536e"), "q": Color("#363e54"), "N": Color("#e07a86"),
		"b": Color("#f8c4bc"), "n": Color("#f2a3a8"), "K": Color("#7a6656"), "F": Color("#fff6e6"), "f": Color("#f1dfc0")}


func same(a: Color, b: Color) -> bool:
	return a.a > 0.5 and absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004


func count(img: Image, rect: Rect2i, c: Color) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if same(img.get_pixel(x, y), c):
				n += 1
	return n


## Widest horizontal run of trouser-blue pixels in `rect`.
func blue_run(img: Image, rect: Rect2i) -> int:
	var cols := rabbit_colors()
	var best := 0
	for y in range(rect.position.y, rect.end.y):
		var run := 0
		for x in range(rect.position.x, rect.end.x):
			var px := img.get_pixel(x, y)
			var blue := false
			for k in BLUE_KEYS:
				blue = blue or same(px, cols[k])
			run = run + 1 if blue else 0
			best = maxi(best, run)
	return best


# ------------------------------------------------------------------ data
func test_seat_data() -> void:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/interiors.json"))
	var bad := []
	var n := 0
	for s in cfg["seats"]:
		n += 1
		var want := "back" if String(s["type"]) in ["bench", "stool"] else "cross"
		if String(s.get("pose", "")) != want:
			bad.append("%s (%s): pose '%s'" % [s["id"], s["type"], s.get("pose", "")])
	r.check(n == 8 and bad.is_empty(),
		"hd seats: data/interiors.json gives every seat its pose - 厨房长凳 / 小板凳 back (facing the table), 坐垫 / 蒲团 cross-legged", str(bad))


# ------------------------------------------------------------------ art
func test_sit_art() -> void:
	var cols := rabbit_colors()
	var back := Image.load_from_file("res://assets/schedule/rabbit_sit_back.png")
	var cross := Image.load_from_file("res://assets/schedule/rabbit_sit_cross.png")
	var old := Image.load_from_file("res://assets/schedule/rabbit_sit.png")
	r.check(back != null and cross != null and back.get_size() == Vector2i(64, 40) and cross.get_size() == Vector2i(64, 32),
		"hd art: the new sitting sheets are there (back view 2 x 32x40, cross-legged 2 x 32x32); the old one stays",
		"%s %s %s" % [back.get_size() if back else null, cross.get_size() if cross else null, old.get_size() if old else null])
	if back == null or cross == null or old == null:
		return
	var b0 := back.get_region(Rect2i(0, 0, 32, 40))
	var b1 := back.get_region(Rect2i(32, 0, 32, 40))
	var c0 := cross.get_region(Rect2i(0, 0, 32, 32))
	var c1 := cross.get_region(Rect2i(32, 0, 32, 32))
	r.check(b0.get_data() != b1.get_data() and c0.get_data() != c1.get_data(), "hd art: both new sitting pictures breathe (2 different frames)")
	# back view: no face, ears seen from behind
	var face := 0
	for fr in [b0, b1]:
		for k in ["N", "b", "n"]:
			face += count(fr, Rect2i(0, 0, 32, 40), cols[k])
	var ears := count(b0, Rect2i(0, 0, 32, 10), cols["F"]) + count(b0, Rect2i(0, 0, 32, 10), cols["f"])
	r.check(face == 0 and ears >= 8, "hd art: the bench / stool picture is his back - no nose, blush or pink inner ears; both ears from behind",
		"face px %d, ear fur px %d" % [face, ears])
	# back view: the seat rows are empty (the room's bench board / stool rim shows there), his legs hang below them
	var gap_px := 0
	for fr in [b0, b1]:
		for y in range(31, 34):
			for x in 32:
				if fr.get_pixel(x, y).a > 0.0:
					gap_px += 1
	var legs := count(b0, Rect2i(0, 34, 32, 6), cols["K"]) + count(b0, Rect2i(0, 34, 32, 6), cols["p"]) + count(b0, Rect2i(0, 34, 32, 6), cols["P"])
	r.check(gap_px == 0 and legs >= 6 and b0.get_region(Rect2i(0, 34, 32, 6)).get_data() == b1.get_region(Rect2i(0, 34, 32, 6)).get_data(),
		"hd art: on a bench / stool he sits on the seat top - rows 31-33 empty for the seat board, shins + sandal heels hang below (still while breathing)",
		"gap px %d, leg px %d" % [gap_px, legs])
	# no blue cushion on wooden seats (and the old picture really had one, so this check can tell)
	var run_back := maxi(blue_run(b0, Rect2i(0, 0, 32, 40)), blue_run(b1, Rect2i(0, 0, 32, 40)))
	var run_old := blue_run(old.get_region(Rect2i(0, 0, 32, 32)), Rect2i(0, 24, 32, 8))
	report["blue_run"] = {"back": run_back, "old_front": run_old}
	r.check(run_back <= 3 and run_old >= 16,
		"hd art: no blue cushion on the wooden seats - the back view has no trouser-blue run wider than 3 px (the old front picture: %d px)" % run_old,
		"back %d" % run_back)
	# cross-legged: facing the camera (nose), sandals and knees out beside the body, paws on the knees
	var nose := count(c0, Rect2i(0, 0, 32, 32), cols["N"])
	var sandals := count(c0, Rect2i(0, 25, 32, 7), cols["K"])
	var knees := count(c0, Rect2i(0, 24, 9, 6), cols["P"]) + count(c0, Rect2i(23, 24, 9, 6), cols["P"])
	var paws := 0
	for k in ["F", "f"]:
		paws += count(c0, Rect2i(4, 24, 6, 3), cols[k]) + count(c0, Rect2i(22, 24, 6, 3), cols[k])
	var run_cross := blue_run(c0, Rect2i(0, 0, 32, 32))
	r.check(nose > 0 and sandals >= 4 and knees >= 6 and paws >= 6 and run_cross <= 12,
		"hd art: on a cushion / 蒲团 he sits cross-legged facing the camera - knees out to both sides, sandals in front, paws on the knees (legs, not a pad)",
		"nose %d sandals %d knees %d paws %d blue run %d" % [nose, sandals, knees, paws, run_cross])


# ------------------------------------------------------------------ sitting in the game
func test_sitting() -> void:
	await t.game()
	await t.clock(10.0)
	var st: Seats = t.st
	var bad := []
	var done := []
	for id in ["kitchen_bench", "kitchen_stool", "dorm_cushion_1", "hall_futon_1"]:
		var s: Dictionary = st.seat(id)
		var from: Vector2 = await t.seat_spot(s)
		if from == Vector2.INF:
			bad.append(id + ": no spot with the prompt")
			continue
		await r.tap(KEY_E)
		await r.frames(2)
		var p: Player = t.p()
		var back := String(s["pose"]) == "back"
		var want_anim := "sit_back" if back else "sit_cross"
		var want_file := "rabbit_sit_back.png" if back else "rabbit_sit_cross.png"
		var tex = p.sprite.sprite_frames.get_frame_texture(p.sprite.animation, p.sprite.frame)
		var atlas_ok: bool = tex is AtlasTexture and (tex as AtlasTexture).atlas.resource_path.ends_with(want_file)
		var fh := 40.0 if back else 32.0
		var ok: bool = st.sitting == id and p.sprite.animation == want_anim and p.facing == ("up" if back else "down") and atlas_ok \
			and tex.get_height() == fh and p.sprite.offset == Vector2(-16, -31.0 - float(s.get("lift", 0))) and p.sprite.is_playing()
		# the frame changes while he sits (breathing)
		var f0: int = p.sprite.frame
		var changed := false
		for i in 90:
			await r.frames(1)
			if p.sprite.frame != f0:
				changed = true
				break
		await r.tap(KEY_E)
		await r.frames(2)
		if ok and changed and st.sitting == "":
			done.append(id)
		else:
			bad.append("%s anim %s facing %s atlas %s h %s offset %s breathes %s" % [id, p.sprite.animation, p.facing, atlas_ok,
				tex.get_height() if tex else -1, p.sprite.offset, changed])
	report["sat"] = done
	r.check(bad.is_empty() and done.size() == 4,
		"hd seats: 厨房长凳 and 小板凳 -> the back-view frames facing up (the table / stove); 坐垫 and 蒲团 -> the cross-legged frames facing down; each breathes, E stands him up",
		str(bad))


# ------------------------------------------------------------------ portraits
func test_portraits() -> void:
	var dlg: Dialogue = t.dlg
	var bad := []
	var n := 0
	for id in dlg.speakers:
		dlg.say({"who": id, "text": "测试"})
		await r.frames(1)
		n += 1
		var tex: Texture2D = dlg.current_portrait()
		var pid := String(dlg.speakers[id].get("portrait", id))
		var ok: bool = tex != null and tex.get_size() == Vector2(128, 128) and tex.resource_path == "res://assets/portraits_hd/%s.png" % pid \
			and dlg.portrait.size == Vector2(64, 64) and dlg.portrait_frame.size == Vector2(64, 64) \
			and dlg.portrait.get_global_rect().size == Vector2(64, 64) and dlg.portrait.material != null \
			and dlg.portrait.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR
		if not ok:
			bad.append("%s: %s %s" % [id, tex.get_size() if tex else null, tex.resource_path if tex else ""])

	dlg.close()
	await r.frames(2)
	# every delivered 64 px portrait has its HD one (16), all 128x128
	var hd_bad := []
	var files := 0
	for f in DirAccess.get_files_at("res://assets/portraits"):
		if not f.ends_with(".png"):
			continue
		files += 1
		var img := Image.load_from_file("res://assets/portraits_hd/" + f) if FileAccess.file_exists("res://assets/portraits_hd/" + f) else null
		if img == null or img.get_size() != Vector2i(128, 128):
			hd_bad.append(f)
	report["portraits"] = {"speakers": n, "files": files}
	r.check(n >= 9 and bad.is_empty(), "hd portraits: every speaker's portrait is the 128x128 HD picture, drawn 64x64 in the unchanged box (HD sampling)", str(bad))
	r.check(files == 16 and hd_bad.is_empty(), "hd portraits: all 16 portraits have a 128x128 HD version (the old 64x64 ones stay)", str(hd_bad))


# ------------------------------------------------------------------ title
func test_title() -> void:
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	r.root.add_child(title)
	r.current_scene = title
	await r.frames(3)
	var rb: AnimatedSprite2D = title.standees.get("rabbit")
	var hd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/title/title_hd.json"))["rabbit_hd"]
	var old: Dictionary = title.art["rabbit"]
	var tex: Texture2D = rb.sprite_frames.get_frame_texture("idle", 0)
	var atlas_ok: bool = tex is AtlasTexture and (tex as AtlasTexture).atlas.resource_path == "res://assets/title/rabbit_standee_hd.png"
	var feet := Vector2(int(title.data["standees"]["rabbit"]["feet"][0]), int(title.data["standees"]["rabbit"]["feet"][1]))
	var box := Rect2(rb.global_position + rb.offset * rb.scale, tex.get_size() * rb.scale)
	var old_box := Rect2(feet - Vector2(int(old["feet"][0]), int(old["feet"][1])), Vector2(int(old["frame_size"][0]), int(old["frame_size"][1])))
	r.check(atlas_ok and tex.get_size() == Vector2(int(hd["frame_size"][0]), int(hd["frame_size"][1])) and tex.get_size() == Vector2(160, 208)
		and rb.scale == Vector2(0.5, 0.5) and rb.global_position == feet and box == old_box and rb.material != null
		and rb.sprite_frames.get_frame_count("idle") == int(hd["frames"]) and rb.is_playing(),
		"hd title: the title rabbit is the HD texture (160x208 frames, 2x density) at scale 0.5 on the same feet - the same on-screen box as the old 80x104 standee",
		"%s scale %s box %s old %s" % [tex.get_size(), rb.scale, box, old_box])
	title.queue_free()
	await r.process_frame
