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
var name_label: Label                # 改名与起名 v1: "弟子：<the hero's name>" at the bottom left of the 门派 page
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
## 武学与经营 第一批 · 翻页 (A): more pages after the 门派 page (0). add_page(id, title, provider): the provider fills its page
## (book_page_fill(book, col)), may take keys on it (book_page_input(book, event) -> true = used) and may hide it
## (book_page_shown() -> false; default shown). ←→ (A D) turn the page; the tab row shows only when there are 2+ pages.
## Every open starts on page 0 (门派), which looks exactly as before apart from that row.
var pages: Array = []                # [{id, title, provider}] after page 0
var page := 0                        # 0 = 门派; i > 0 = pages[i - 1] (among the shown ones, see shown_pages())
var page_ids: Array = []             # ids of the pages shown right now, "sect" first (tests)
var tabs_label: Label                # "← → 翻页" at the end of the tab row
var tab_labels: Array[Label] = []    # the page names of the tab row (the current one in 【】)
var page_labels: Array[Label] = []   # labels of an extra page that wrap like the record lines
var _flags: Dictionary = {}


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


## Registers an extra page (武学与经营 第一批). Pages keep the order they were added in.
func add_page(id: String, title: String, page_provider: Object) -> void:
	for pg in pages:
		if String(pg["id"]) == id:
			pg["title"] = title
			pg["provider"] = page_provider
			return
	pages.append({"id": id, "title": title, "provider": page_provider})


## The pages shown now: [{id, title, provider}] with the 门派 page first (provider null).
func shown_pages() -> Array:
	var out := [{"id": "sect", "title": String(data.get("page_title", "门派")), "provider": null}]
	for pg in pages:
		var pv: Object = pg["provider"]
		if pv != null and (not pv.has_method("book_page_shown") or pv.book_page_shown()):
			out.append(pg)
	return out


## Id of the page shown now ("sect" = the 门派 page).
func page_id() -> String:
	var sp := shown_pages()
	return String(sp[clampi(page, 0, sp.size() - 1)]["id"])


## Turns to page `i` (wraps round) and redraws.
func set_page(i: int) -> void:
	var n := shown_pages().size()
	page = posmod(i, n)
	refresh(_flags)
	if is_open:
		layout()


## Turns to the page with this id (tests, other systems); false when it is not shown.
func show_page(id: String) -> bool:
	var sp := shown_pages()
	for i in sp.size():
		if String(sp[i]["id"]) == id:
			set_page(i)
			return true
	return false


## A label in the book's style for a provider's page (wraps like the record lines when `wrap`).
func page_label(text: String, size: int, color: Color, wrap := true) -> Label:
	var l := _label(text, size, color)
	if wrap:
		page_labels.append(l)
	return l


## Rebuilds the page for the given story flags.
func refresh(flags: Dictionary) -> void:
	_flags = flags
	for c in col.get_children():
		col.remove_child(c)
		c.queue_free()
	bar_labels.clear()
	entry_labels.clear()
	page_labels.clear()
	info_labels.clear()
	title_label = _label(String(data.get("title", "")), 13, Color(0.45, 0.12, 0.08))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sp := shown_pages()
	# (B, 整体收尾): with 2+ pages the tab row stands on the title's line instead of a line of its own - a full 门派簿
	# in English kept scale 1 at 480x270 before the tabs (i18n_suite) and must still
	var title_row: HBoxContainer = null
	if sp.size() > 1:
		title_row = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 12)
		title_row.alignment = BoxContainer.ALIGNMENT_CENTER
		title_row.add_child(title_label)
		col.add_child(title_row)
	else:
		col.add_child(title_label)
	page = clampi(page, 0, sp.size() - 1)
	page_ids = sp.map(func(x): return String(x["id"]))
	tabs_label = null
	tab_labels.clear()
	if sp.size() > 1:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		for i in sp.size():
			var t := String(sp[i]["title"])
			var tl := _label(("【%s】" % t) if i == page else t, 9, Color(0.62, 0.18, 0.08) if i == page else Color(0.45, 0.35, 0.28))
			row.add_child(tl)
			tab_labels.append(tl)
		tabs_label = _label(String(data.get("page_keys", "← → 翻页")), 8, Color(0.45, 0.35, 0.28))
		row.add_child(tabs_label)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(row)
	if page > 0:
		_refresh_extra(sp[page])
		return
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
	# 改名与起名 v1: the hero's name ("弟子：小兔", data "player_line") on the left of the close hint's line - no extra line,
	# a full book must still fit 480x270 at scale 1
	var foot := HBoxContainer.new()
	name_label = _label(PlayerName.fill(String(data.get("player_line", ""))), 8, Color(0.4, 0.2, 0.12))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_label.size_flags_vertical = Control.SIZE_SHRINK_END
	foot.add_child(name_label)
	foot.add_child(close_label)
	col.add_child(foot)


## An extra page: title row, the provider's content, its close hint.
func _refresh_extra(pg: Dictionary) -> void:
	two_columns = false
	col.add_theme_constant_override("separation", 2)
	values.clear()
	coins_label = null
	hint_label = null
	var pv: Object = pg["provider"]
	pv.book_page_fill(self, col)
	var ch := String(pv.book_page_close_hint()) if pv.has_method("book_page_close_hint") else String(data.get("close_hint", ""))
	close_label = _label(ch, 8, Color(0.45, 0.35, 0.28))
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
	page = 0
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
	_wrap_long_lines(vp.x - 6.0)
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	var k := minf(1.0, minf((vp.x - 6.0) / sz.x, (vp.y - 6.0) / sz.y))
	panel.scale = Vector2(k, k)
	panel.position = ((vp - sz * k) * 0.5).round()
	_laid_for = vp
	_lang_laid = Lang.current()


var _laid_for := Vector2.ZERO
var _lang_laid := ""


## 中英文切换 v1: longer (English) record lines would make the page wider than the screen - such lines wrap inside
## their column (entries in two-column mode: half the page) instead of the whole page being scaled down.
func _wrap_long_lines(room_w: float) -> void:
	var lines: Array = entry_labels + info_labels + page_labels + ([hint_label] if hint_label != null else [])
	for l in lines:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2.ZERO
	panel.reset_size()
	var chrome := panel.get_combined_minimum_size().x - col.get_combined_minimum_size().x
	var full_w := room_w - chrome
	if col.get_combined_minimum_size().x <= full_w:
		return
	var half_w := floorf((full_w - 14.0) * 0.5)
	for l in lines:
		var w := half_w if (two_columns and l in entry_labels) else full_w
		w -= float(l.get_meta("wrap_inset", 0.0))     # (an extra page's label beside an icon: that much narrower)
		if l.get_combined_minimum_size().x > w:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(w, 0)
	panel.reset_size()


func _process(_delta: float) -> void:
	if is_open and (get_viewport().get_visible_rect().size != _laid_for or Lang.current() != _lang_laid
			or not panel.size.is_equal_approx(panel.get_combined_minimum_size())):   # (wrapped lines settle a frame later)
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
	# 武学与经营 第一批: ←→ turn the page; on an extra page its provider sees the keys first (↑↓ / E there)
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		if shown_pages().size() > 1:
			set_page(page + (1 if event.is_action_pressed("move_right") else -1))
			Sfx.play("choice_move")
		get_viewport().set_input_as_handled()
		return
	if page > 0 and not event.is_action_pressed("pause") and not event.is_action_pressed("sect_book"):
		var sp := shown_pages()
		var pv: Object = sp[page]["provider"] if page < sp.size() else null
		if pv != null and pv.has_method("book_page_input") and pv.book_page_input(self, event):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact") or event.is_action_pressed("sect_book") \
			or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.physical_keycode == KEY_ENTER:
		close()
	get_viewport().set_input_as_handled()    # nothing else reacts while the book is open
