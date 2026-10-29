class_name LangSwitch
extends CanvasLayer
## 中英文切换 v1: the small 「中文 | English」 switch in the top-right corner of the title screen (the loading page has
## the same one in web/shell.html). The chosen language is bright, the other dim; a click switches (Lang.set_lang).

const OPTIONS := [["zh", "中文"], ["en", "English"]]
const ON := Color(1.0, 0.88, 0.5)
const OFF := Color(0.8, 0.76, 0.7, 0.7)

var box: HBoxContainer
var buttons := {}          # lang -> Button


func _init() -> void:
	name = "LangSwitch"
	layer = 40


func _ready() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	box = HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	holder.add_child(box)
	for i in OPTIONS.size():
		if i > 0:
			var bar := Label.new()
			bar.text = "|"
			bar.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			bar.add_theme_font_size_override("font_size", 9)
			bar.add_theme_color_override("font_color", OFF)
			box.add_child(bar)
		var b := Button.new()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # (before the text: "中文" is never sent to the translator)
		b.text = OPTIONS[i][1]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # the names are always written in their own language
		b.add_theme_font_size_override("font_size", 9)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var l: String = OPTIONS[i][0]
		b.pressed.connect(func(): Lang.set_lang(l))
		box.add_child(b)
		buttons[l] = b
	Lang.on_changed(func(_l): _refresh())
	get_viewport().size_changed.connect(_place)
	_refresh()
	_place.call_deferred()


func _refresh() -> void:
	for l in buttons:
		var c := ON if l == Lang.current() else OFF
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			buttons[l].add_theme_color_override(fc, c)


func _place() -> void:
	if box == null:
		return
	var vp := get_viewport().get_visible_rect().size
	box.size = box.get_combined_minimum_size()
	box.position = Vector2(vp.x - box.size.x - 6.0, 3.0).round()


## Screen rectangle of the switch (tests).
func rect() -> Rect2:
	return box.get_global_rect()
