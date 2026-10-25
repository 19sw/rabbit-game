class_name PrologueEnd
extends CanvasLayer
## 「序章 · 完」 screen (序章 v1): fades to black, shows the title, then the "回到启动画面" button (selected) and
## "继续逛逛" (keeps playing in region 1, so S9-师兄 and the 门派簿 key B can still be used).
## ↑↓ / W S select, E / Enter / Space confirm, mouse hover + click. Texts: data/story.json -> ui.

signal chosen(key: String)     # "title" | "continue"

var is_open := false
var root: Control
var black: ColorRect
var title_label: Label
var buttons: Array[Button] = []
var selected := 0
var _ready_for_input := false


func _init() -> void:
	name = "PrologueEnd"
	layer = 26
	add_to_group("modal_ui")


func setup(ui: Dictionary) -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.visible = false
	add_child(root)
	black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0.04, 0.03, 0.05, 0.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	title_label = Label.new()
	title_label.text = String(ui.get("prologue_end_title", ""))
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	title_label.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.08))
	title_label.add_theme_constant_override("outline_size", 4)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_CENTER)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.modulate.a = 0.0
	root.add_child(title_label)
	var i := 0
	for key in ["title", "continue"]:
		var b := Button.new()
		b.text = String(ui.get("back_to_title" if key == "title" else "keep_playing", key))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.set_meta("key", key)
		b.custom_minimum_size = Vector2(96, 18)
		b.visible = false
		var idx := i
		b.mouse_entered.connect(func(): select(idx))
		b.pressed.connect(func(): confirm(idx))
		root.add_child(b)
		buttons.append(b)
		i += 1


func _style(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.92, 0.7, 0.97) if on else Color(0.12, 0.09, 0.1, 0.8)
	sb.border_color = Color(0.62, 0.16, 0.1) if on else Color(0.86, 0.7, 0.4, 0.75)
	sb.set_border_width_all(1)
	var text := Color(0.45, 0.1, 0.06) if on else Color(0.96, 0.9, 0.78)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb)
	for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(fc, text)


func select(i: int) -> void:
	selected = clampi(i, 0, buttons.size() - 1)
	for j in buttons.size():
		_style(buttons[j], j == selected)


## Fade to black, title, then the buttons (the title button first).
func open() -> void:
	if is_open:
		return
	is_open = true
	_ready_for_input = false
	root.visible = true
	var vp := get_viewport().get_visible_rect().size
	title_label.size = Vector2(vp.x, 36)
	title_label.position = Vector2(0, vp.y * 0.38 - 18).round()
	var y := vp.y * 0.38 + 30
	for b in buttons:
		b.size = b.custom_minimum_size
		b.position = Vector2((vp.x - b.size.x) * 0.5, y).round()
		y += 24
	select(0)
	if OS.has_feature("web"):
		print("story: prologue end")
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.8)
	tw.tween_property(title_label, "modulate:a", 1.0, 0.6)
	tw.tween_callback(func():
		for b in buttons:
			b.visible = true
		_ready_for_input = true)


func buttons_shown() -> bool:
	return _ready_for_input


func confirm(i: int) -> void:
	if not is_open or not _ready_for_input:
		return
	select(i)
	var key: String = buttons[i].get_meta("key")
	if key == "continue":
		is_open = false
		root.visible = false
		black.color.a = 0.0
		title_label.modulate.a = 0.0
		for b in buttons:
			b.visible = false
	chosen.emit(key)


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var vp := get_viewport()
	vp.set_input_as_handled()      # (taken first: 回到启动画面 leaves the tree while handling it)
	if _ready_for_input:
		if event.is_action_pressed("move_up"):
			select((selected - 1 + buttons.size()) % buttons.size())
		elif event.is_action_pressed("move_down"):
			select((selected + 1) % buttons.size())
		elif Dialogue._is_advance(event):
			confirm(selected)
