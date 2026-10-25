class_name TitleScreen
extends Node2D
## 启动画面 (title screen, the project's main scene since 启动画面 v1).
## Built in code from data/title.json (外部文件层: title text, menu texts, positions, effect counts / intensity) and
## the generated art in assets/title/ (pixel2d/title/tools/generate_title_art.py -> tools/sync_assets.py).
## Menu (两条路小样 v1 存档): 继续游戏 (greyed out and skipped while there is no save; loads the save, a bad one starts
## fresh with "存档无法读取，已重新开始"), 新游戏 (fade out -> scenes/main.tscn, built exactly as when it is launched
## directly; with a save it first asks "会覆盖存档，确定吗？" 确定 / 取消) and 按键与玩法 (the Esc page's content via
## PauseMenu in help mode). Keyboard ↑↓ / W S + E / Enter / Space, mouse hover + click. Esc on the title does nothing
## (there is no pause here) - except closing the overwrite question.

signal game_started(main: Node)

const DATA := "res://data/title.json"
const ART := "res://assets/title/"
const MAIN_SCENE := "res://scenes/main.tscn"
const MainScript := preload("res://scripts/main.gd")
const VIEW := Vector2(480, 270)

var data: Dictionary
var art: Dictionary
var fx: Dictionary = {}           # kind -> TitleFx
var standees: Dictionary = {}     # "rabbit" / "crane" -> AnimatedSprite2D
var onlookers: Array[AnimatedSprite2D] = []
var logo: Sprite2D
var logo_label: Label             # only when the logo picture is out of date (shows the right text anyway)
var buttons: Array[Button] = []
var markers: Node2D
var selected := 0
var help: PauseMenu
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var camera: Camera2D
var starting := false
var activations: Array[String] = []   # "continue" / "start" / "help" (tests)
var has_save := false
var confirm_box: PanelContainer
var confirm_buttons: Array[Button] = []
var confirm_open := false
var confirm_selected := 1             # 0 = 确定, 1 = 取消 (the safe answer first)
var start_mode := ""                  # "new" | "continue" (tests)


func _ready() -> void:
	MainScript.ensure_input_actions()
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if has_meta("data_override"):     # tests: build from an edited copy of title.json
		data = get_meta("data_override")
	art = JSON.parse_string(FileAccess.get_file_as_string(ART + "title_art.json"))
	name = "Title"
	DisplayServer.window_set_title(str(data["title"]))
	camera = Camera2D.new()
	camera.position = VIEW * 0.5      # keeps the 480x270 picture centred when the window is wider / taller
	add_child(camera)
	camera.make_current()
	_build_backdrop()
	_build_people()
	_build_effects()
	_build_logo()
	has_save = SaveGame.exists()
	_build_menu()
	_build_confirm()
	help = PauseMenu.new()
	help.configure_as_help(str(data["help_title"]), str(data["help_back"]))
	add_child(help)
	help.closed.connect(_on_help_closed)
	fade_layer = CanvasLayer.new()
	fade_layer.name = "Fade"
	fade_layer.layer = 50
	add_child(fade_layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade_rect)
	select(index_of("continue") if has_save else index_of("start"))
	get_viewport().size_changed.connect(_on_view_changed)
	_on_view_changed()
	print("title: ready (%s)" % data["title"])


# ------------------------------------------------------------------ building
func _tex(file: String) -> Texture2D:
	return load(ART + file)


func _sprite(file: String, node_name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = _tex(file)
	s.centered = false
	return s


func _effects_cfg() -> Dictionary:
	return data["effects"]


func _build_backdrop() -> void:
	# when the window is not 16:9 (or larger than a whole-number multiple of 480x270) the picture's edges are
	# continued outwards instead of leaving dark bars
	var surround := Node2D.new()
	surround.name = "Surround"
	surround.draw.connect(_draw_surround.bind(surround))
	add_child(surround)
	# wall + yard continue as a tiled plain strip (separate sprites: tiling needs texture_repeat)
	var edge := _tex("bg_sect_edge.png")
	var span := float(edge.get_width()) * 128.0
	for x in [-span, VIEW.x]:
		var tile := Sprite2D.new()
		tile.name = "EdgeLeft" if x < 0 else "EdgeRight"
		tile.texture = edge
		tile.centered = false
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.region_enabled = true
		tile.region_rect = Rect2(0, 0, span, VIEW.y)
		tile.position = Vector2(x, 0)
		surround.add_child(tile)
	var bg := Node2D.new()
	bg.name = "Backdrop"
	add_child(bg)
	var eff := _effects_cfg()
	var k := float(eff["intensity"])
	bg.add_child(_sprite("bg_sky.png", "Sky"))
	var mists: Array = eff["mist"]
	var m0: TitleFx = TitleFx.new().setup("mist", mists[0], k, _tex("mist_0.png"), 0)
	bg.add_child(m0)
	bg.add_child(_sprite("bg_hills.png", "Hills"))
	var m1: TitleFx = TitleFx.new().setup("mist", mists[1], k, _tex("mist_1.png"), 1)
	bg.add_child(m1)
	bg.add_child(_sprite("bg_sect.png", "Sect"))
	fx["mist0"] = m0
	fx["mist1"] = m1


## Continues the picture outwards when the view is wider / taller than 480x270 (see ViewFit): sky and hills by
## stretching their outermost pixel columns (flat bands; the wall and yard are the tiled Edge sprites on top);
## above / below by the top sky row and the bottom yard row. Everything stays on whole pixels.
func _draw_surround(n: Node2D) -> void:
	const FAR := 4000.0
	var W := VIEW.x
	var H := VIEW.y
	for file in ["bg_sky.png", "bg_hills.png"]:
		var t := _tex(file)
		n.draw_texture_rect_region(t, Rect2(-FAR, 0, FAR, H), Rect2(0, 0, 1, H))
		n.draw_texture_rect_region(t, Rect2(W, 0, FAR, H), Rect2(W - 1, 0, 1, H))
	var sky := _tex("bg_sky.png")
	n.draw_texture_rect_region(sky, Rect2(-FAR, -FAR, W + 2.0 * FAR, FAR), Rect2(0, 0, 1, 1))
	n.draw_texture_rect_region(_tex("bg_sect.png"), Rect2(-FAR, H, W + 2.0 * FAR, FAR), Rect2(0, H - 1, 1, 1))


func _on_view_changed() -> void:
	var vp := get_viewport()
	var win := DisplayServer.window_get_size()
	print("title: view %dx%d in window %dx%d (scale %.2f)" % [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y,
		win.x, win.y, vp.get_final_transform().get_scale().x])


func _build_people() -> void:
	var crowd := Node2D.new()
	crowd.name = "Onlookers"
	add_child(crowd)
	for o in data["onlookers"]:
		var s := AnimatedSprite2D.new()
		s.name = str(o["id"]).capitalize()
		s.sprite_frames = CharSheet.frames_for(o["id"])
		s.centered = false
		s.offset = Vector2(-16, -31)      # feet of a 32 px frame (pixel2d: feet on row 29, outline row 30)
		s.scale = Vector2.ONE * int(o["scale"])
		s.position = Vector2(int(o["feet"][0]), int(o["feet"][1]))
		s.play("idle_" + str(o["dir"]))
		s.set_meta("id", o["id"])
		crowd.add_child(s)
		onlookers.append(s)


func _standee_frames(info: Dictionary) -> SpriteFrames:
	var tex := _tex(info["file"])
	var fw := int(info["frame_size"][0])
	var fh := int(info["frame_size"][1])
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_speed("idle", float(info["fps"]))
	sf.set_animation_loop("idle", true)
	for i in int(info["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("idle", at)
	return sf


func _build_effects() -> void:
	var eff := _effects_cfg()
	var k := float(eff["intensity"])
	var leaves_tex := _tex("leaves.png")
	var back: TitleFx = TitleFx.new().setup("leaves_back", eff["leaves"], k, leaves_tex)
	add_child(back)
	var wind: TitleFx = TitleFx.new().setup("wind", eff["wind"], k)
	add_child(wind)
	var ripple: TitleFx = TitleFx.new().setup("ripple", eff["ripple"], k)
	add_child(ripple)
	# standees (+ a small stepped shadow under each) between the far and near halves of the leaf swirl
	var shadows := Node2D.new()
	shadows.name = "Shadows"
	add_child(shadows)
	var stand := Node2D.new()
	stand.name = "Standees"
	add_child(stand)
	var anchors := {}
	for who in ["rabbit", "crane"]:
		var info: Dictionary = art[who]
		var s := AnimatedSprite2D.new()
		s.name = who.capitalize()
		s.sprite_frames = _standee_frames(info)
		s.centered = false
		s.offset = -Vector2(int(info["feet"][0]), int(info["feet"][1]))
		var feet := Vector2(int(data["standees"][who]["feet"][0]), int(data["standees"][who]["feet"][1]))
		s.position = feet
		s.play("idle")
		if who == "crane":
			s.frame = 2     # the two breathe out of step
		stand.add_child(s)
		standees[who] = s
		anchors[who] = feet
		var sh := Polygon2D.new()
		sh.color = Color(0.1, 0.06, 0.08, 0.28)
		var w := 22.0 if who == "rabbit" else 18.0
		sh.polygon = PackedVector2Array([feet + Vector2(-w, -1), feet + Vector2(w, -1), feet + Vector2(w - 4, 2),
			feet + Vector2(-w + 4, 2)])
		shadows.add_child(sh)
	var motes: TitleFx = TitleFx.new().setup("motes", eff["motes"], k)
	motes.anchors = anchors
	add_child(motes)
	wind.anchors = anchors
	var front: TitleFx = TitleFx.new().setup("leaves_front", eff["leaves"], k, leaves_tex)
	add_child(front)
	fx["leaves_back"] = back
	fx["leaves_front"] = front
	fx["motes"] = motes
	fx["ripple"] = ripple
	fx["wind"] = wind


func _build_logo() -> void:
	var lg: Dictionary = data["logo"]
	var stamp_path := ART + "title_logo.json"
	var stamp = JSON.parse_string(FileAccess.get_file_as_string(stamp_path)) if FileAccess.file_exists(stamp_path) else null
	var center := Vector2(int(lg["center"][0]), int(lg["center"][1]))
	if typeof(stamp) == TYPE_DICTIONARY and str(stamp.get("text", "")) == str(data["title"]) and ResourceLoader.exists(ART + "title_logo.png"):
		logo = _sprite("title_logo.png", "Logo")
		var sc := int(lg["scale"])
		logo.scale = Vector2(sc, sc)
		var size := logo.texture.get_size() * sc
		logo.position = (center - size * 0.5).round()
		add_child(logo)
	else:
		# the title text was changed but the pixel logo was not regenerated yet: still show the right name
		push_warning("Title: assets/title/title_logo.png is out of date - run tools/sync_assets.py (update.sh)")
		logo_label = Label.new()
		logo_label.name = "LogoText"
		logo_label.text = str(data["title"])
		logo_label.add_theme_font_size_override("font_size", 28)
		logo_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
		logo_label.add_theme_color_override("font_outline_color", Color(0.16, 0.1, 0.12))
		logo_label.add_theme_constant_override("outline_size", 6)
		logo_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(logo_label)
		logo_label.position = (center - logo_label.get_combined_minimum_size() * 0.5).round()


func _menu_box(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(0)
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	return sb


func _build_menu() -> void:
	var ml: Dictionary = data["menu_layout"]
	var menu := Node2D.new()
	menu.name = "Menu"
	add_child(menu)
	var size := Vector2(int(ml["button_size"][0]), int(ml["button_size"][1]))
	var y := int(ml["top"])
	var i := 0
	for key in ["continue", "start", "help"]:
		var b := Button.new()
		b.name = {"continue": "Continue", "start": "Start", "help": "Help"}[key]
		b.text = str(data["menu"][key])
		b.focus_mode = Control.FOCUS_NONE     # keyboard is handled here (Space / Enter / E), never by Button focus
		b.size = size
		b.custom_minimum_size = size
		b.position = Vector2(int(ml["center_x"]) - int(size.x / 2), y)
		b.add_theme_font_size_override("font_size", 10)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		b.set_meta("key", key)
		var idx := i
		b.mouse_entered.connect(func(): if usable(idx): select(idx))
		b.pressed.connect(func(): activate(idx))
		if key == "continue" and not has_save:
			b.disabled = true
		_style_button(b, false)
		menu.add_child(b)
		b.size = size        # exact size (the theme would otherwise grow it before the overrides apply)
		buttons.append(b)
		y += int(size.y) + int(ml["gap"])
		i += 1
	markers = Node2D.new()
	markers.name = "Markers"
	markers.draw.connect(_draw_markers)
	menu.add_child(markers)


func _style_button(b: Button, on: bool) -> void:
	var normal: StyleBoxFlat
	var text: Color
	if b.disabled:
		normal = _menu_box(Color(0.12, 0.09, 0.1, 0.55), Color(0.55, 0.5, 0.45, 0.6), 1)
		text = Color(0.7, 0.66, 0.62, 0.85)       # greyed but still readable
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, normal)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color",
				"font_disabled_color"]:
			b.add_theme_color_override(fc, text)
		return
	if on:
		normal = _menu_box(Color(1.0, 0.92, 0.7, 0.97), Color(0.62, 0.16, 0.1), 1)
		text = Color(0.45, 0.1, 0.06)
	else:
		normal = _menu_box(Color(0.12, 0.09, 0.1, 0.72), Color(0.86, 0.7, 0.4, 0.75), 1)
		text = Color(0.96, 0.9, 0.78)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, normal)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(fc, text)


## Little pixel arrows pointing at the selected button from both sides.
func _draw_markers() -> void:
	if buttons.is_empty():
		return
	var r := Rect2(buttons[selected].position, buttons[selected].size)
	var col := Color(1.0, 0.86, 0.42)
	var dark := Color(0.35, 0.12, 0.08)
	var cy := int(r.position.y + r.size.y * 0.5)
	for side in [-1, 1]:
		var tip_x := int(r.position.x) - 3 if side < 0 else int(r.position.x + r.size.x) + 2
		for k in 4:   # 4 px tall arrow column by column
			var x := tip_x - k if side < 0 else tip_x + k
			markers.draw_rect(Rect2(x, cy - k - 1, 1, 2 * k + 2), dark)
			if k > 0:
				markers.draw_rect(Rect2(x, cy - k, 1, 2 * k), col)


func _build_confirm() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Confirm"
	layer.layer = 40
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(root)
	confirm_box = PanelContainer.new()
	confirm_box.add_theme_stylebox_override("panel", _menu_box(Color(0.1, 0.07, 0.08, 0.95), Color(0.92, 0.76, 0.45), 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var q := Label.new()
	q.text = "  " + str(data.get("confirm_overwrite", "会覆盖存档，确定吗？")) + "  "
	q.add_theme_font_size_override("font_size", 10)
	q.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for i in 2:
		var b := Button.new()
		b.text = str(data.get("confirm_yes" if i == 0 else "confirm_no", "确定" if i == 0 else "取消"))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 14)
		b.add_theme_font_size_override("font_size", 10)
		var idx := i
		b.mouse_entered.connect(func(): _confirm_select(idx))
		b.pressed.connect(func(): _confirm_answer(idx == 0))
		row.add_child(b)
		confirm_buttons.append(b)
	col.add_child(row)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_child(col)
	confirm_box.add_child(pad)
	confirm_box.visible = false
	root.add_child(confirm_box)


func _confirm_select(i: int) -> void:
	confirm_selected = clampi(i, 0, 1)
	for j in confirm_buttons.size():
		_style_button(confirm_buttons[j], j == confirm_selected)


func open_confirm() -> void:
	confirm_open = true
	confirm_box.visible = true
	_confirm_select(1)
	var sz := confirm_box.get_combined_minimum_size()
	confirm_box.size = sz
	var vp := get_viewport().get_visible_rect().size
	confirm_box.position = ((vp - sz) * 0.5 + Vector2(0, 30)).round()


func _confirm_answer(yes: bool) -> void:
	if not confirm_open:
		return
	confirm_open = false
	confirm_box.visible = false
	if yes:
		start_game("new")
	else:
		select(selected)


# ------------------------------------------------------------------ menu logic
func index_of(key: String) -> int:
	for i in buttons.size():
		if buttons[i].get_meta("key") == key:
			return i
	return -1


func button(key: String) -> Button:
	return buttons[index_of(key)]


## A button that can be chosen (继续游戏 only with a save).
func usable(i: int) -> bool:
	return i >= 0 and i < buttons.size() and not buttons[i].disabled


func _step(dir: int) -> int:
	var i := selected
	for _k in buttons.size():
		i = (i + dir + buttons.size()) % buttons.size()
		if usable(i):
			return i
	return selected


func select(i: int) -> void:
	if starting:
		return
	selected = clampi(i, 0, buttons.size() - 1)
	for j in buttons.size():
		_style_button(buttons[j], j == selected)
	markers.queue_redraw()


func activate(i: int) -> void:
	if starting or help.is_open or confirm_open or not usable(i):
		return
	select(i)
	var key: String = buttons[i].get_meta("key")
	activations.append(key)
	if key == "continue":
		start_game("continue")
	elif key == "start":
		if has_save:
			open_confirm()
		else:
			start_game("new")
	else:
		help.open()


func _on_help_closed() -> void:
	select(selected)


func _unhandled_input(event: InputEvent) -> void:
	if starting or help.is_open:
		return
	if confirm_open:
		if event.is_action_pressed("move_left", true) or event.is_action_pressed("move_right", true) \
				or event.is_action_pressed("move_up", true) or event.is_action_pressed("move_down", true):
			_confirm_select(1 - confirm_selected)
		elif event.is_action_pressed("pause", false):
			_confirm_answer(false)
		elif event.is_action_pressed("interact", false) or _is_confirm_key(event):
			_confirm_answer(confirm_selected == 0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_up", true):
		select(_step(-1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down", true):
		select(_step(1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact", false) or _is_confirm_key(event):
		activate(selected)
		get_viewport().set_input_as_handled()
	# Esc ("pause") is deliberately ignored here: there is nothing to pause on the title screen.


static func _is_confirm_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var k: InputEventKey = event
	for code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if k.keycode == code or k.physical_keycode == code:
			return true
	return false


# ------------------------------------------------------------------ start
## mode "new": a fresh game (an old save is removed - the player confirmed); "continue": the save is read and checked
## here (SaveGame.read, never waits); a bad one is moved aside and the new game shows SaveGame.BROKEN_TEXT.
func start_game(mode := "new") -> void:
	if starting:
		return
	starting = true
	start_mode = mode
	SaveGame.pending = null
	SaveGame.pending_broken = false
	if mode == "continue":
		var res := SaveGame.read()
		if res["ok"]:
			SaveGame.pending = res["state"]
		else:
			print("title: save unreadable (%s)" % res["error"])
			SaveGame.quarantine()
			SaveGame.pending_broken = true
	else:
		SaveGame.erase()
	print("title: start (%s)" % mode)
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, float(data["fade_out_seconds"]))
	tw.tween_callback(_enter_game)


## Swap this scene for a fresh scenes/main.tscn (the same way the engine would launch it directly), then fade in
## from black on a separate overlay that is not part of the game scene and frees itself.
func _enter_game() -> void:
	var tree := get_tree()
	var root := tree.root
	var overlay := CanvasLayer.new()
	overlay.name = "TitleFadeIn"
	overlay.layer = 50
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(black)
	var main: Node = load(MAIN_SCENE).instantiate()
	root.remove_child(self)
	root.add_child(main)
	tree.current_scene = main
	root.add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_property(black, "color:a", 0.0, float(data["fade_in_seconds"]))
	tw.tween_callback(overlay.queue_free)
	var sp: Vector2 = main.player.global_position
	print("title: game started (spawn %d,%d, %s)" % [sp.x, sp.y, main.daynight.clock_text()])
	game_started.emit(main)
	queue_free()
