class_name Opening
extends CanvasLayer
## 开场过场动画 v1 (docs/design/开场过场动画-方案-v1.md): seven full-screen pixel pictures (assets/opening/, drawn by
## pixel2d/opening/tools/generate_opening.py) with narration, slow pans / push-ins, crossfades, a storm flash + shake,
## the three panels of picture 6 lighting up one by one.
## Everything timed / worded comes from data/opening.json (外部文件层); English in data/i18n/en_opening.json (the Labels
## keep the Chinese text and go through the game's translator like every other text).
##
## Entry:  Opening.play(parent, on_done, mode)  - mode "new" (新游戏: on_done enters the game) or "replay" (启动画面
## 「重看序幕」: on_done returns to the title). The overlay covers the whole window, takes every key / mouse event while
## it plays, fades to black at the end (or after a skip), calls on_done, then frees itself.
## Controls: E / Space / Enter / left click = show the whole narration of this picture; again = next picture.
## Hold Esc 1 s (skip_hold_seconds) = skip everything; the ring next to the hint in the bottom-right corner fills while
## Esc is held (a short tap does nothing).
##
## 坐姿-高清过场-运镜 方案 v1 (docs/design/坐姿-高清过场-运镜-方案-v1.md, 二 + 三):
##  - the pictures are the HD set (960x540, pixel2d/opening/tools/generate_opening_hd.py; list in data "art"), each
##    scaled by 480 / its width, so it fills the 480x270 frame at half size (real screen pixels). With "pixel_aa" they
##    are drawn through scripts/opening_pixel.gdshader (even pixels at odd window scales, no crawl while zooming).
##  - calm camera (ideas from the godot-camera-systems skill, written here): most pictures are a fixed frame; only
##    pictures 1 (one pan) and 7 (one push-in) move, once, inside their "move" window, eased in / out (sine), zoom
##    interpolated geometrically, then hold. The picture's position is always a whole game pixel.
##  - one shake (picture 4's thunder): trauma 1 -> 0 over its seconds, amplitude px * trauma^2, direction from a
##    seeded FastNoiseLite sampled by time (no per-frame random numbers), applied as a whole-pixel offset on top of
##    the framing and never moving the framing itself.

signal started(mode: String)
signal scene_changed(index: int)
signal finished(skipped: bool)

const DATA := "res://data/opening.json"
const ART := "res://assets/opening/"
const VIEW := Vector2(480, 270)
const OFF := -1.0e9               # "not started yet" (a revealed line starts in the past, maybe below 0)

## 新游戏 plays the opening only while this is on. tests/run_tests.gd turns it off for the older suites (they start the
## game from the title and expect it at once); tests/opening_suite.gd turns it on for its own checks. 重看序幕 always plays.
static var enabled := true
## Every Sfx.music() call made here (tests).
static var music_log: Array[String] = []

var data: Dictionary
var art: Dictionary
var mode := "new"
var on_done: Callable
var speed := 1.0                 # tests only: plays the timeline faster
var index := -1                  # current picture 0..6
var t := 0.0                     # seconds into the current picture
var state := "play"              # "play" | "ending" | "done"
var skipped := false
var hold := 0.0                  # seconds Esc has been held
var holding := false
var advances := 0                # presses that were used (tests)

var scenes: Array = []
var root: Control
var frame: Control               # the 480x270 picture, centred in the window
var cur: Sprite2D
var prev: Sprite2D
var flash: ColorRect
var black: ColorRect             # fade from / to black over everything
var band: TextureRect
var sub_box: VBoxContainer
var lines: Array[Label] = []
var line_start: Array[float] = []
var hint: Label
var ring: Control
var dimmers: Array[ColorRect] = []
var panel_start: Array[float] = []

var _intro := 0.0
var _cross := 1.0
var _end := 0.0
var _fired := {}
var _flash_at := -100.0
var _flash_len := 0.3
var _flash_alpha := 0.0
var _shake_at := -100.0
var _shake_len := 0.0
var _shake_px := 0.0
var _noise := FastNoiseLite.new()
var _pixel_mat: ShaderMaterial
var tex_scale := 1.0             # picture pixels -> frame pixels (0.5 for the 960x540 pictures)


static func play(parent: Node, done := Callable(), m := "new") -> Opening:
	var o := Opening.new()
	o.mode = m
	o.on_done = done
	parent.add_child(o)
	return o


## The music (B's sound service, scripts/sfx.gd): the opening track while it plays, then Sfx.auto() hands the choice back
## (title -> opening track, game -> day / night). Logged for the tests.
static func music(track: String) -> void:
	music_log.append(track)
	# looked up by name: this script does not depend on the sound service being there (B's scripts/sfx.gd)
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == &"Sfx":
			var s = load(c["path"])
			if s != null:
				if track == "auto":
					s.call("auto")
				else:
					s.call("music", track)
			return


func _init() -> void:
	name = "Opening"
	layer = 60


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	art = JSON.parse_string(FileAccess.get_file_as_string(ART + str(data.get("art", "opening_art.json"))))
	scenes = data["scenes"]
	_noise.seed = 1027
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	if bool(data.get("pixel_aa", false)):
		_pixel_mat = ShaderMaterial.new()
		_pixel_mat.shader = load("res://scripts/opening_pixel.gdshader")
	_build()
	get_viewport().size_changed.connect(_place)
	_place()
	_show_scene(0, false)
	print("opening: start (%s)" % mode)
	music("opening")
	started.emit(mode)


# ------------------------------------------------------------------ building
func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP       # nothing underneath (title buttons, switch) can be hovered
	add_child(root)
	var bg := ColorRect.new()
	bg.name = "Black"
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	frame = Control.new()
	frame.name = "Frame"
	frame.size = VIEW
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	prev = _picture("Previous")
	cur = _picture("Current")
	flash = ColorRect.new()
	flash.name = "Flash"
	flash.color = Color(1, 1, 1, 0)
	flash.size = VIEW
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(flash)
	# a stepped dark band behind the narration (readable on the bright pictures)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.62)])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	band = TextureRect.new()
	band.name = "Band"
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(band)
	var st: Dictionary = data["subtitle"]
	sub_box = VBoxContainer.new()
	sub_box.name = "Subtitles"
	sub_box.add_theme_constant_override("separation", 1)
	sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(sub_box)
	var most := 0
	for sc in scenes:
		most = maxi(most, (sc["lines"] as Array).size())
	for i in most:
		var l := Label.new()
		l.name = "Line%d" % i
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(float(st["width"]), 0)
		l.add_theme_font_size_override("font_size", int(st["font_size"]))
		l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.84))
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.08))
		l.add_theme_constant_override("outline_size", 4)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_box.add_child(l)
		lines.append(l)
	hint = Label.new()
	hint.name = "Hint"
	hint.text = str(data["hint"])
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.93, 0.88, 0.78, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.07, 0.9))
	hint.add_theme_constant_override("outline_size", 3)
	hint.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(hint)
	ring = Control.new()
	ring.name = "SkipRing"
	ring.size = Vector2(11, 11)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(_draw_ring)
	frame.add_child(ring)
	black = ColorRect.new()
	black.name = "Fade"
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)


func _picture(n: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = n
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _pixel_mat != null:
		s.material = _pixel_mat
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # (the shader picks the sample point itself)
	frame.add_child(s)
	return s


## The picture is centred in the window (a wider / taller window shows black around it, like letterboxing).
func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	frame.position = ((vp - VIEW) * 0.5).round()


func _layout_text() -> void:
	var st: Dictionary = data["subtitle"]
	var w := float(st["width"])
	sub_box.size = Vector2(w, 0)
	sub_box.reset_size()
	var h := sub_box.get_combined_minimum_size().y
	sub_box.size = Vector2(w, h)
	sub_box.position = Vector2(round((VIEW.x - w) * 0.5), round(float(st["bottom"]) - h))
	band.position = Vector2(0, sub_box.position.y - 12)
	band.size = Vector2(VIEW.x, VIEW.y - band.position.y)
	var hs := hint.get_combined_minimum_size()
	hint.size = hs
	hint.position = Vector2(VIEW.x - 6 - ring.size.x - 3 - hs.x, VIEW.y - 3 - hs.y).round()
	ring.position = Vector2(VIEW.x - 6 - ring.size.x, hint.position.y + round((hs.y - ring.size.y) * 0.5))


func _draw_ring() -> void:
	var c := ring.size * 0.5
	var r := ring.size.x * 0.5 - 1.5
	ring.draw_arc(c, r, 0.0, TAU, 24, Color(0.93, 0.88, 0.78, 0.35 if holding else 0.22), 1.5)
	var p := progress()
	if p > 0.0:
		ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * p, 24, Color(1.0, 0.86, 0.42), 2.0)


# ------------------------------------------------------------------ timeline
func scene() -> Dictionary:
	return scenes[index]


func _show_scene(i: int, crossfade := true) -> void:
	if crossfade and cur.texture != null:
		prev.texture = cur.texture
		prev.scale = cur.scale
		prev.position = cur.position
		prev.visible = true
		prev.modulate.a = 1.0
		_cross = 0.0
	else:
		prev.visible = false
		_cross = 1.0
	index = i
	t = 0.0
	_fired.clear()
	_flash_at = -100.0
	_shake_at = -100.0
	cur.texture = load(ART + str(scene()["image"]))
	tex_scale = VIEW.x / float(cur.texture.get_width())
	cur.modulate.a = 0.0 if crossfade else 1.0
	var ls: Array = scene()["lines"]
	line_start.clear()
	for k in lines.size():
		lines[k].visible = k < ls.size()
		lines[k].text = str(ls[k]) if k < ls.size() else ""
		lines[k].modulate.a = 0.0
		line_start.append(OFF)
	_build_dimmers()
	_apply_camera()
	_layout_text()
	scene_changed.emit(i)


## Picture 6: one dark cover per panel (rects from opening_art.json); each fades away at its time.
func _build_dimmers() -> void:
	for d in dimmers:
		d.queue_free()
	dimmers.clear()
	panel_start.clear()
	if not scene().has("panels"):
		return
	var rects: Array = art["panels_scene6"]
	for k in rects.size():
		var rr: Array = rects[k]
		var d := ColorRect.new()
		d.name = "Panel%dCover" % k
		d.color = Color(0.04, 0.03, 0.05, 0.82)
		d.position = Vector2(float(rr[0]), float(rr[1]))
		d.size = Vector2(float(rr[2]), float(rr[3]))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cur.add_child(d)
		dimmers.append(d)
		panel_start.append(OFF)


func _process(delta: float) -> void:
	if state == "done":
		return
	var dt := delta * speed
	if holding:
		hold += dt
		if hold >= float(data["skip_hold_seconds"]):
			skip()
	ring.queue_redraw()
	if _intro < 1.0:
		_intro = minf(1.0, _intro + dt / float(data["fade_in_seconds"]))
	if _cross < 1.0:
		_cross = minf(1.0, _cross + dt / float(data["crossfade_seconds"]))
		cur.modulate.a = _cross
		if _cross >= 1.0:
			prev.visible = false
	if state == "ending":
		_end = minf(1.0, _end + dt / float(data["end_fade_seconds"] if not skipped else 0.4))
		black.color.a = maxf(_end, 1.0 - _intro)
		if _end >= 1.0:
			_finish()
		return
	black.color.a = 1.0 - _intro
	t += dt
	var sc := scene()
	var times: Array = sc["line_times"]
	for k in times.size():
		if line_start[k] == OFF and t >= float(times[k]):
			line_start[k] = float(times[k])
	if sc.has("panels"):
		var pt: Array = sc["panels"]
		for k in pt.size():
			if panel_start[k] == OFF and t >= float(pt[k]):
				panel_start[k] = float(pt[k])
	for e in sc.get("effects", []):
		var key := "%s@%s" % [e["type"], e["at"]]
		if not _fired.has(key) and t >= float(e["at"]):
			_fired[key] = true
			_fire(e)
	_update_visuals()
	if t >= float(sc["seconds"]):
		next()


func _fire(e: Dictionary) -> void:
	if e["type"] == "flash":
		_flash_at = t
		_flash_len = float(e["seconds"])
		_flash_alpha = float(e["alpha"])
	elif e["type"] == "shake":
		_shake_at = t
		_shake_len = float(e["seconds"])
		_shake_px = float(e["px"])


func _update_visuals() -> void:
	var fade := float(data["line_fade_seconds"])
	for k in lines.size():
		lines[k].modulate.a = 0.0 if line_start[k] == OFF else clampf((t - line_start[k]) / fade, 0.0, 1.0)
	for k in dimmers.size():
		dimmers[k].color.a = 0.82 if panel_start[k] == OFF else 0.82 * (1.0 - clampf((t - panel_start[k]) / 0.6, 0.0, 1.0))
	var fl := t - _flash_at
	flash.color.a = _flash_alpha * (1.0 - fl / _flash_len) if fl >= 0.0 and fl < _flash_len else 0.0
	_apply_camera()
	_layout_text()          # (also follows a language switch: the English lines are longer)


## Shake strength 0..1 right now: 1 at the thunder, falling linearly to 0 over the effect's seconds.
func trauma() -> float:
	var s := t - _shake_at
	if s < 0.0 or s >= _shake_len or _shake_len <= 0.0:
		return 0.0
	return 1.0 - s / _shake_len


## The whole-pixel shake offset (added on top of the framing): amplitude px * trauma^2, direction from smooth noise.
func shake_offset() -> Vector2:
	var tr := trauma()
	if tr <= 0.0:
		return Vector2.ZERO
	var a := _shake_px * tr * tr
	# the direction wanders smoothly (noise -> angle), the size is exactly the trauma amplitude
	var dir := Vector2.from_angle(TAU * _noise.get_noise_1d((t - _shake_at) * 12.0 + 3.7) * 2.0)
	return (dir * a).round()


## Does this picture move its camera? (only pictures 1 and 7: they have "move")
func moves(i := -1) -> bool:
	return (scenes[index if i < 0 else i]["camera"] as Dictionary).has("move")


## 0..1 progress of the one camera move (sine ease in / out inside the move window; 0 before it, 1 = hold after it).
func camera_progress() -> float:
	var cam: Dictionary = scene()["camera"]
	if not cam.has("move"):
		return 0.0
	var m: Array = cam["move"]
	var u := clampf((t - float(m[0])) / maxf(0.001, float(m[1]) - float(m[0])), 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * u)


## Framing (centre in 480x270 picture coordinates, zoom) right now.
func framing() -> Array:
	var cam: Dictionary = scene()["camera"]
	if not cam.has("move"):
		return [Vector2(float(cam["center"][0]), float(cam["center"][1])), float(cam["zoom"])]
	var a: Dictionary = cam["from"]
	var b: Dictionary = cam["to"]
	var e := camera_progress()
	var z0 := float(a["zoom"])
	var z1 := float(b["zoom"])
	var z := z0 * pow(z1 / z0, e)                  # geometric: the push-in feels even, not faster at the start
	var c := Vector2(float(a["center"][0]), float(a["center"][1])).lerp(Vector2(float(b["center"][0]), float(b["center"][1])), e)
	return [c, z]


func _apply_camera() -> void:
	var f := framing()
	var c: Vector2 = f[0]
	var z: float = f[1]
	# never show past the picture's edge
	var half := VIEW * 0.5 / z
	c = Vector2(clampf(c.x, half.x, VIEW.x - half.x), clampf(c.y, half.y, VIEW.y - half.y))
	cur.scale = Vector2(z, z) * tex_scale
	var p := (VIEW * 0.5 - c * z).round()
	var lo := (VIEW - VIEW * z).ceil()
	p = Vector2(clampf(p.x, lo.x, 0.0), clampf(p.y, lo.y, 0.0))      # whole pixels, and no sliver of black at an edge
	cur.position = p + shake_offset()


# ------------------------------------------------------------------ player input
func _input(event: InputEvent) -> void:
	if state == "done":
		return
	if event is InputEventMouseMotion:
		return                                   # (the root Control already keeps hover away from the title)
	get_viewport().set_input_as_handled()        # nothing reaches the title / the game while the opening plays
	if event.is_action("pause") or (event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)):
		if event.is_pressed() and not event.is_echo():
			holding = true
		elif not event.is_pressed():
			holding = false
			if state == "play":
				hold = 0.0
		return
	if not event.is_pressed() or event.is_echo():
		return
	var go := false
	if event is InputEventMouseButton:
		go = event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		go = event.is_action("interact") or event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] \
			or event.physical_keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	if go:
		advance()


## E / Space / Enter / click: the whole narration of this picture first, the next picture on the next press.
func advance() -> void:
	if state != "play":
		return
	advances += 1
	if not all_shown():
		reveal_all()
	else:
		next()


func all_shown() -> bool:
	var fade := float(data["line_fade_seconds"])
	for k in scene()["lines"].size():
		if line_start[k] == OFF or t - line_start[k] < fade:
			return false
	for k in panel_start.size():
		if panel_start[k] == OFF or t - panel_start[k] < 0.6:
			return false
	return true


func reveal_all() -> void:
	for k in scene()["lines"].size():
		line_start[k] = t - 10.0
	for k in panel_start.size():
		panel_start[k] = t - 10.0
	_update_visuals()


func next() -> void:
	if state != "play":
		return
	if index + 1 < scenes.size():
		_show_scene(index + 1)
	else:
		state = "ending"
		_end = 0.0


## Hold-Esc result (also callable directly).
func skip() -> void:
	if state == "done":
		return
	skipped = true
	holding = false
	if state == "play":
		state = "ending"
		_end = 0.0


## 0..1 of the Esc hold (the ring).
func progress() -> float:
	return clampf(hold / float(data["skip_hold_seconds"]), 0.0, 1.0)


func _finish() -> void:
	state = "done"
	black.color.a = 1.0
	print("opening: done (%s, %s)" % [mode, "skipped" if skipped else "watched"])
	music("auto")
	finished.emit(skipped)
	if on_done.is_valid():
		on_done.call()
	if is_instance_valid(self):
		queue_free()


## Screen-space rectangles (tests): the picture, each narration line, the hint, the ring.
func frame_rect() -> Rect2:
	return frame.get_global_rect()
