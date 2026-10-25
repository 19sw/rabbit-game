class_name SectBook
extends CanvasLayer
## 门派簿 (序章 v1): 名望 and 家业 - a 10-segment bar each (■ filled / □ empty) and their record entries, then the hint
## line. Content: data/sect_book.json (外部文件层); an entry is listed only when its story flag is set (e.g. 赢了师兄一回
## only after a spar win). Opened for the first time at the end of the prologue; afterwards B opens it again.
## 两条路小样 v1: a bar = its "value" (序章结束时各 1 格) + the economy points of the entries whose flag is set
## (data/economy.json: 名望 per trial tier, 家业 per repair) - all done: 名望 4, 家业 5; the coins line (once unlocked).
## E / Esc / Enter (or B) closes it. While it is open the Esc page does not open (group "modal_ui").

signal opened
signal closed

const PATH := "res://data/sect_book.json"
const SAMPLE_PATH := "res://data/sample.json"
const FULL := "■"
const EMPTY := "□"
const BULLET := "· "

var data: Dictionary
var is_open := false
var times_opened := 0
var root: Control
var panel: PanelContainer
var col: VBoxContainer
var title_label: Label
var bar_labels: Dictionary = {}      # track id -> Label with the ■□ bar
var entry_labels: Array[Label] = []  # every entry label currently shown
var hint_label: Label
var close_label: Label
var coins := -1                      # 两条路小样 v1: shown when >= 0 (set by Sample once unlocked)
var coins_text := "%d"
var coins_label: Label
var values: Dictionary = {}          # track id -> bar value shown (tests)
## 第③步: Step3 adds what is not a story flag - points (比武大会 wins, 陪练, 收徒, 打扫), entries and status lines (下届比武
## 大会, 师弟's job and progress): provider.book_extras() -> {points: {track: n}, entries: {track: [text]}, lines: [text]}.
var provider: Object = null
var info_labels: Array[Label] = []   # the status lines shown (tests)
const TWO_COLUMN_LINES := 10         # more bar + entry + status lines than this: the tracks go side by side
var two_columns := false


func _init() -> void:
	name = "SectBook"
	layer = 25
	add_to_group("modal_ui")
	data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SectBook: cannot read " + PATH)
		data = {}
	# 两条路小样 v1: the sample's entries (data/sample.json "book_entries") join the tracks after the prologue's own
	var smp = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH)) if FileAccess.file_exists(SAMPLE_PATH) else null
	if typeof(smp) == TYPE_DICTIONARY:
		var extra: Dictionary = smp.get("book_entries", {})
		for tr in data.get("tracks", []):
			for e in extra.get(String(tr["id"]), []):
				tr["entries"].append(e)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.03, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.87, 0.72, 0.98)      # paper
	sb.border_color = Color(0.42, 0.22, 0.14)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Bar value of a track for these flags: its base value + Economy.points_for(track, flag) of every flag that is set.
static func track_value(tr: Dictionary, flags: Dictionary) -> int:
	var v := int(tr.get("value", 0))
	for e in tr.get("entries", []):
		var f := String(e.get("flag", ""))
		if f != "" and flags.get(f, false):
			v += Economy.points_for(String(tr["id"]), f)
	return v


static func bar_text(value: int, maximum: int) -> String:
	value = clampi(value, 0, maximum)
	return FULL.repeat(value) + EMPTY.repeat(maximum - value)


## Rebuilds the page for the given story flags.
func refresh(flags: Dictionary) -> void:
	for c in col.get_children():
		col.remove_child(c)
		c.queue_free()
	bar_labels.clear()
	entry_labels.clear()
	title_label = _label(String(data.get("title", "")), 13, Color(0.45, 0.12, 0.08))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	coins_label = null
	if coins >= 0:
		coins_label = _label(coins_text % coins, 10, Color(0.5, 0.3, 0.05))
		coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(coins_label)
	values.clear()
	info_labels.clear()
	var extras: Dictionary = provider.book_extras() if provider != null else {}
	# 第③步: with many entries the two tracks stand side by side (名望 left, 家业 right) so the page fits the screen;
	# with few entries the page looks as before (one column)
	var n_lines := (extras.get("lines", []) as Array).size()
	for tr in data.get("tracks", []):
		n_lines += 1 + (extras.get("entries", {}).get(tr["id"], []) as Array).size()
		for e in tr.get("entries", []):
			if flags.get(String(e.get("flag", "")), false):
				n_lines += 1
	two_columns = n_lines > TWO_COLUMN_LINES
	# 修复 v1: a full book is set a little tighter (1 px between lines) so it still fits the 480 x 270 screen
	col.add_theme_constant_override("separation", 1 if two_columns else 2)
	var cols_box := HBoxContainer.new()
	cols_box.add_theme_constant_override("separation", 14)
	if two_columns:
		col.add_child(cols_box)
	for tr in data.get("tracks", []):
		var tcol: VBoxContainer = col
		if two_columns:
			tcol = VBoxContainer.new()
			tcol.add_theme_constant_override("separation", 1)
			cols_box.add_child(tcol)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_label(String(tr["name"]), 11, Color(0.3, 0.14, 0.08)))
		var v := track_value(tr, flags) + int(extras.get("points", {}).get(tr["id"], 0))
		v = mini(v, int(tr.get("max", 10)))
		values[tr["id"]] = v
		var bar := _label(bar_text(v, int(tr.get("max", 10))), 11, Color(0.55, 0.2, 0.1))
		row.add_child(bar)
		bar_labels[tr["id"]] = bar
		tcol.add_child(row)
		for e in tr.get("entries", []):
			if flags.get(String(e.get("flag", "")), false):
				var l := _label(BULLET + String(e["text"]), 10, Color(0.22, 0.16, 0.12))
				l.set_meta("track", tr["id"])
				tcol.add_child(l)
				entry_labels.append(l)
		for t in extras.get("entries", {}).get(tr["id"], []):
			var l2 := _label(BULLET + String(t), 10, Color(0.22, 0.16, 0.12))
			l2.set_meta("track", tr["id"])
			tcol.add_child(l2)
			entry_labels.append(l2)
	var rule := ColorRect.new()
	rule.color = Color(0.42, 0.22, 0.14, 0.5)
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)
	for t in extras.get("lines", []):
		var il := _label(String(t), 9, Color(0.45, 0.18, 0.08))
		col.add_child(il)
		info_labels.append(il)
	hint_label = _label(String(data.get("hint", "")), 10, Color(0.35, 0.2, 0.12))
	col.add_child(hint_label)
	close_label = _label(String(data.get("close_hint", "")), 8, Color(0.45, 0.35, 0.28))
	close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(close_label)


## 第③步 status lines shown right now (tests / screenshots).
func shown_lines() -> Array:
	return info_labels.map(func(l): return l.text)


## Entry texts shown right now (tests / screenshots).
func shown_entries(track := "") -> Array:
	var out := []
	for l in entry_labels:
		if track == "" or l.get_meta("track") == track:
			out.append(l.text.trim_prefix(BULLET))
	return out


func open(flags: Dictionary) -> void:
	if is_open:
		return
	refresh(flags)
	is_open = true
	times_opened += 1
	root.visible = true
	await get_tree().process_frame
	layout()
	if OS.has_feature("web"):
		print("story: sect book open")
	opened.emit()


## Centred; never larger than the screen (修复 v1: a very full book on the 480 x 270 view is scaled down a little rather
## than cut off). Laid out again when the window changes size.
func layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	panel.scale = Vector2.ONE
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	var k := minf(1.0, minf((vp.x - 6.0) / sz.x, (vp.y - 6.0) / sz.y))
	panel.scale = Vector2(k, k)
	panel.position = ((vp - sz * k) * 0.5).round()
	_laid_for = vp


var _laid_for := Vector2.ZERO


func _process(_delta: float) -> void:
	if is_open and get_viewport().get_visible_rect().size != _laid_for:
		layout()


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	if event.is_action_pressed("pause") or event.is_action_pressed("interact") or event.is_action_pressed("sect_book") \
			or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.physical_keycode == KEY_ENTER:
		close()
	get_viewport().set_input_as_handled()    # nothing else reacts while the book is open
