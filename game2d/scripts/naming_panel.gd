class_name NamingPanel
extends CanvasLayer
## 改名与起名 v1: the box where the player names the hero (texts: data/naming.json, English in data/i18n).
##   mode "new"     新游戏 on the title screen, before the opening: 「给这只小兔起个名字吧」, [确定] [随机]; Esc goes
##                  back to the title menu (nothing started, an old save untouched).
##   mode "rename"  the Esc page's 改名（R）: 「给他改个名字」, [确定] [随机] [取消]; free, takes effect at once.
## The box is filled with the current name (小兔 at first; in English its English form), all of it selected, so typing
## replaces it and 确定 / Enter right away keeps it. 随机 picks from naming.json "random_names".
## Checks (PlayerName.validate): not empty / not only spaces; at most 5 汉字 or 12 letters in any language (R1; spaces
## not counted, mixed names share the room) -
## a longer text cannot be typed (the box keeps its last good text); a character the game's font cannot draw shows
## 「这个字显示不了，换一个吧」 and 确定 does nothing.
## Typing: a real LineEdit with the keyboard focus - on the web the browser's input method (拼音 etc.) types into it.
## While it is open the title screen, the Esc page and the 任务面板 ignore the keys (their handlers check is_open), so
## E / Q / B / T / Space / arrows typed into the name never act as game keys; Esc is taken here (closes the box only).

signal confirmed(name: String)
signal cancelled

## Tests and the screenshot scripts that start 新游戏 without wanting to type: off = the default name is taken at once
## (tests/run_tests.gd switches it off for the older suites, like Opening.enabled; naming_suite turns it on).
static var enabled := true

var mode := "new"
var is_open := false
var root: Control
var panel: PanelContainer
var title_label: Label
var line: LineEdit
var limit_label: Label
var error_label: Label
var keys_label: Label
var confirm_button: Button
var random_button: Button
var cancel_button: Button
var error := ""                   # error code shown now ("" none) - tests
var _good_text := ""              # the last text within the limit (a longer one is put back to this)
var _random_i := -1


func _init() -> void:
	name = "NamingPanel"
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS          # also works on the paused Esc page
	add_to_group("modal_ui")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing under the box can be clicked
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.03, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.07, 0.08, 0.96), Color(0.92, 0.76, 0.45), 10, 6))
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	title_label = _label("", 11, Color(1.0, 0.88, 0.5))
	col.add_child(title_label)
	line = LineEdit.new()
	line.name = "NameEdit"
	line.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.custom_minimum_size = Vector2(120, 18)
	line.max_length = PlayerName.HARD_MAX
	line.context_menu_enabled = false              # (Godot's own English cut / paste menu)
	line.keep_editing_on_text_submit = true        # a refused name stays in the box, still being typed
	line.caret_blink = true
	line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # the name is shown as typed
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", Color(0.27, 0.12, 0.08))
	line.add_theme_color_override("caret_color", Color(0.6, 0.18, 0.08))
	line.add_theme_color_override("selection_color", Color(0.95, 0.75, 0.45, 0.8))
	line.add_theme_color_override("font_selected_color", Color(0.27, 0.12, 0.08))
	for st in ["normal", "focus", "read_only"]:
		line.add_theme_stylebox_override(st, _box(Color(1.0, 0.95, 0.84), Color(0.6, 0.18, 0.08) if st == "focus"
			else Color(0.47, 0.24, 0.16), 6, 1))
	line.text_changed.connect(_on_text_changed)
	line.text_submitted.connect(func(_t): submit())
	col.add_child(line)
	limit_label = _label("", 9, Color(0.85, 0.78, 0.6))
	col.add_child(limit_label)
	error_label = _label("", 9, Color(1.0, 0.5, 0.4))
	col.add_child(error_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	confirm_button = _button(PlayerName.ui("confirm"), true)
	confirm_button.pressed.connect(submit)
	row.add_child(confirm_button)
	random_button = _button(PlayerName.ui("random"), false)
	random_button.pressed.connect(pick_random)
	row.add_child(random_button)
	cancel_button = _button(PlayerName.ui("cancel"), false)
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)
	keys_label = _label(PlayerName.ui("keys"), 8, Color(0.75, 0.7, 0.62))
	col.add_child(keys_label)


func _ready() -> void:
	Lang.on_changed(func(_l): if is_open: _refresh_texts())
	get_viewport().size_changed.connect(func(): if is_open: _layout())


func _box(bg: Color, border: Color, mx: int, my: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my + 1
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, main: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE           # the keyboard stays in the name box
	b.custom_minimum_size = Vector2(44, 15)
	b.add_theme_font_size_override("font_size", 10)
	var bg := Color(1.0, 0.92, 0.7, 0.97) if main else Color(0.2, 0.15, 0.13, 0.9)
	var fg := Color(0.45, 0.1, 0.06) if main else Color(1.0, 0.93, 0.75)
	var normal := _box(bg, Color(0.62, 0.16, 0.1) if main else Color(0.86, 0.7, 0.4, 0.8), 6, 0)
	var hover := _box(bg.lightened(0.12), Color(1.0, 0.86, 0.5), 6, 0)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(fc, fg)
	return b


# ------------------------------------------------------------------ open / close
## Shows the box ("new" or "rename") filled with the current name, all selected, with the keyboard focus.
func open(how := "new") -> void:
	mode = how
	is_open = true
	root.visible = true
	_random_i = -1
	line.text = PlayerName.shown(PlayerName.value())
	_good_text = line.text if PlayerName.fits(line.text) else ""
	if _good_text == "":
		line.text = ""
	_set_error("")
	_refresh_texts()
	_focus()
	line.select_all()
	if OS.has_feature("web"):
		print("naming: open (%s)" % mode)


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	line.unedit()
	line.release_focus()


func _focus() -> void:
	line.grab_focus()
	line.edit()
	line.caret_column = line.text.length()


func _refresh_texts() -> void:
	title_label.text = PlayerName.ui("rename_title" if mode == "rename" else "title")
	limit_label.text = PlayerName.ui("limit").replace("{0}", str(PlayerName.max_hanzi())).replace("{1}", str(PlayerName.max_letters()))
	cancel_button.visible = mode == "rename"
	keys_label.visible = mode == "new"
	_set_error(error)
	_layout.call_deferred()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	panel.reset_size()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = ((vp - sz) * 0.5 + Vector2(0, -6)).round()


func _set_error(code: String) -> void:
	error = code
	error_label.text = PlayerName.error_text(code) if code != "" else " "


# ------------------------------------------------------------------ typing, buttons
## Over the limit -> the last good text comes back (nothing longer can be typed); a character the font lacks shows the
## message at once.
func _on_text_changed(t: String) -> void:
	if not PlayerName.fits(t):
		var col := mini(line.caret_column, _good_text.length())
		line.text = _good_text
		line.caret_column = col
		_set_error("too_long")
		return
	_good_text = t
	_set_error("missing_char" if PlayerName.missing_char(t.strip_edges()) != "" else "")


## 确定 / Enter: the name is taken if it passes the checks (else the reason is shown and the box stays).
func submit() -> bool:
	if not is_open:
		return false
	var res := PlayerName.validate(line.text)
	if not res["ok"]:
		_set_error(String(res["error"]))
		_focus()
		return false
	var n := PlayerName.canonical(String(res["name"]))
	PlayerName.choose(n)
	close()
	Sfx.play("dialogue_page")
	confirmed.emit(n)
	return true


## 随机: the next random name (never the one in the box now), in the language's form.
func pick_random() -> void:
	var names := PlayerName.random_names()
	if names.is_empty():
		return
	var now := line.text.strip_edges()
	for _k in names.size():
		_random_i = (randi() % names.size()) if _random_i < 0 else (_random_i + 1 + randi() % maxi(1, names.size() - 1)) % names.size()
		if PlayerName.shown(String(names[_random_i])) != now:
			break
	line.text = PlayerName.shown(String(names[_random_i]))
	_good_text = line.text
	_set_error("")
	_focus()
	line.select_all()
	Sfx.play("choice_move")


func cancel() -> void:
	if not is_open:
		return
	close()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed:
		return
	var k: InputEventKey = event
	if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
		if not k.echo:
			cancel()
		get_viewport().set_input_as_handled()
	elif (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not line.has_focus():
		if not k.echo:
			submit()
		get_viewport().set_input_as_handled()
	elif not line.has_focus():
		_focus()                                  # (a click on the dim background took the focus away)

