class_name QuestBoard
extends CanvasLayer
## 任务面板 (新手指引 + 任务看板 v1, plan section 二). Q opens it (the game pauses: SceneTree.paused, like the Esc page);
## Q or Esc closes it. Six tabs (新手指引 / 悬赏 / 委托 / 修缮 / 比武 / 收徒) on the left, the tab's items on the right - built
## from the real game state by Guide.tabs() each time the board opens or changes. ←→ (A D) change the tab, ↑↓ (W S) the
## item, E (Enter) on an item: 追踪 (or, on the guide's last item, 关闭 / 打开指引). Grey = not open yet (with when).
## Fits the screen at any window size: the item list is cut into pages measured with the real labels (font size never
## changes) and laid out again when the window changes size.
## Opens only after the prologue, never during a conversation / fight / trial / tournament / door fade / another page.
## The Esc page's own Q (放弃试炼 / 弃权) is untouched: while the Esc page is open the tree is paused and Q is left to it.

signal opened
signal closed

const MARGIN := 4.0
const TAB_W := 64.0
const BG := Color(0.11, 0.08, 0.08, 0.97)
const BORDER := Color(0.92, 0.76, 0.45)

var main: Node
var guide: Guide
var is_open := false
var root: Control
var panel: Panel
var title_label: Label
var page_label: Label
var keys_label: Label
var tab_labels: Array[Label] = []
var list_box: Control
var item_panels: Array[PanelContainer] = []
var item_labels: Array[Label] = []
var tab := 0
var sel := 0
var page := 0
var pages: Array = []            # [[item indices], ...] of the current tab
var model: Array = []            # Guide.tabs()
var opens := 0                   # statistics (tests)
var refused := 0
var _was_paused := false
var _laid_for := Vector2.ZERO


func _init() -> void:
	name = "QuestBoard"
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("modal_ui")


func setup(m: Node) -> void:
	main = m
	guide = m.guide
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
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(BG, BORDER, 2))
	root.add_child(panel)
	title_label = _label(guide.bt("title"), 11, Color(1.0, 0.88, 0.5))
	panel.add_child(title_label)
	page_label = _label("", 8, Color(0.85, 0.78, 0.6))
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(page_label)
	keys_label = _label(guide.bt("keys"), 8, Color(0.85, 0.8, 0.7))
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(keys_label)
	for i in 6:
		var l := _label("", 10, Color.WHITE)
		panel.add_child(l)
		tab_labels.append(l)
	list_box = Control.new()
	list_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_box.clip_contents = false
	panel.add_child(list_box)


func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ opening / closing
## Q is allowed now (after the prologue, nothing running, no other page).
func can_open() -> bool:
	if main == null or is_open or not guide.active():
		return false
	var story: Story = main.story
	var c: Combat = main.combat
	if story.busy or story._modal_open() or c.blocks_interaction() or c.story_hold or main.interiors.transitioning:
		return false
	if get_tree().paused or main.pause_menu.is_open or main.player.dead:
		return false
	return true


func open() -> void:
	if is_open:
		return
	is_open = true
	opens += 1
	_was_paused = get_tree().paused
	get_tree().paused = true
	root.visible = true
	model = guide.tabs()
	# start on the tab of the tracked item (the guide when nothing is tracked)
	tab = 0
	if guide.track != "" and guide.track != "guide":
		for i in model.size():
			if (model[i]["items"] as Array).any(func(it): return String(it.get("key", "")) == guide.track):
				tab = i
	sel = 0
	_rebuild()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	get_tree().paused = _was_paused
	closed.emit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	var is_q := k.physical_keycode == KEY_Q or k.keycode == KEY_Q
	if not is_open:
		if is_q:
			if can_open():
				open()
				get_viewport().set_input_as_handled()
			else:
				refused += 1
		return
	if is_q or event.is_action_pressed("pause"):
		close()
	elif event.is_action_pressed("move_left"):
		_set_tab(tab - 1)
	elif event.is_action_pressed("move_right"):
		_set_tab(tab + 1)
	elif event.is_action_pressed("move_up"):
		_set_sel(sel - 1)
	elif event.is_action_pressed("move_down"):
		_set_sel(sel + 1)
	elif event.is_action_pressed("interact") or k.keycode == KEY_ENTER or k.physical_keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		activate()
	get_viewport().set_input_as_handled()     # nothing else reacts while the board is open


func _set_tab(i: int) -> void:
	tab = posmod(i, model.size())
	sel = 0
	_rebuild()


func _set_sel(i: int) -> void:
	var n: int = (model[tab]["items"] as Array).size()
	sel = clampi(i, 0, maxi(0, n - 1))
	_paginate_show()


func items() -> Array:
	return model[tab]["items"] if tab < model.size() else []


## E on the selected item: 追踪 it, or switch the guide off / on.
func activate() -> void:
	var its := items()
	if sel >= its.size():
		return
	var it: Dictionary = its[sel]
	match String(it.get("action", "")):
		"track":
			guide.set_track(String(it["key"]))
		"toggle":
			guide.set_hidden(not guide.hidden)
	model = guide.tabs()
	_rebuild()


# ------------------------------------------------------------------ layout
func _rebuild() -> void:
	for p in item_panels:
		p.queue_free()
	item_panels.clear()
	item_labels.clear()
	for it in items():
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tracked := String(it.get("key", "")) != "" and String(it["key"]) == guide.track
		var l := _label((guide.bt("tracking") if tracked else "") + String(it["text"]), 9, _color(String(it["state"])))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pc.add_child(l)
		list_box.add_child(pc)
		item_panels.append(pc)
		item_labels.append(l)
	_layout()


func _color(state: String) -> Color:
	match state:
		"done":
			return Color(0.62, 0.78, 0.55)
		"current":
			return Color(1.0, 0.9, 0.55)
		"locked":
			return Color(0.55, 0.52, 0.48)
		"info":
			return Color(0.85, 0.82, 0.75)
	return Color(0.95, 0.92, 0.86)


## Panel = the screen minus a margin (never larger); tabs left; items right in pages that fit.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_laid_for = vp
	var sz := Vector2(minf(vp.x - MARGIN * 2.0, 472.0), vp.y - MARGIN * 2.0)
	panel.size = sz
	panel.position = ((vp - sz) * 0.5).round()
	title_label.position = Vector2(8, 3)
	title_label.size = Vector2(sz.x * 0.6, 14)
	page_label.position = Vector2(sz.x * 0.6, 5)
	page_label.size = Vector2(sz.x * 0.4 - 8, 12)
	var keys_h := 13.0
	keys_label.position = Vector2(4, sz.y - keys_h - 3)
	keys_label.size = Vector2(sz.x - 8, keys_h)
	var top := 20.0
	for i in tab_labels.size():
		var l := tab_labels[i]
		var on := i == tab
		l.text = ("▶ " if on else "  ") + String(model[i]["name"]) if i < model.size() else ""
		l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42) if on else Color(0.9, 0.86, 0.78))
		l.position = Vector2(6, top + i * 17.0)
		l.size = Vector2(TAB_W, 15)
	list_box.position = Vector2(TAB_W + 12, top)
	list_box.size = Vector2(sz.x - TAB_W - 20, sz.y - top - keys_h - 8)
	var w := list_box.size.x
	for i in item_panels.size():
		var l := item_labels[i]
		l.custom_minimum_size = Vector2(w - 10, 0)
		l.size = Vector2(w - 10, 0)          # the wrapped height depends on the width: set it before measuring
		item_panels[i].custom_minimum_size = Vector2(w, 0)
		item_panels[i].size = Vector2(w, 0)
	_paginate_show()


func _paginate_show() -> void:
	var h := list_box.size.y
	pages = []
	var cur: Array = []
	var used := 0.0
	for i in item_panels.size():
		var ih := item_panels[i].get_combined_minimum_size().y
		if not cur.is_empty() and used + ih > h:
			pages.append(cur)
			cur = []
			used = 0.0
		cur.append(i)
		used += ih + 2.0
	if not cur.is_empty():
		pages.append(cur)
	if pages.is_empty():
		pages = [[]]
	page = 0
	for p in pages.size():
		if (pages[p] as Array).has(sel):
			page = p
	var y := 0.0
	for i in item_panels.size():
		var pc := item_panels[i]
		var on: bool = (pages[page] as Array).has(i)
		pc.visible = on
		if on:
			pc.position = Vector2(0, y)
			pc.size = Vector2(list_box.size.x, pc.get_combined_minimum_size().y)
			y += pc.size.y + 2.0
			var it: Dictionary = items()[i]
			var tracked := String(it.get("key", "")) != "" and String(it["key"]) == guide.track
			pc.add_theme_stylebox_override("panel", _box(Color(0.35, 0.22, 0.1, 0.95) if i == sel else Color(0.16, 0.12, 0.1, 0.9),
				Color(1.0, 0.85, 0.4) if i == sel else (Color(0.95, 0.75, 0.3) if tracked else Color(0.4, 0.3, 0.2)), 2))
	page_label.text = guide.bt("page") % [page + 1, pages.size()]


func _process(_delta: float) -> void:
	if is_open and get_viewport().get_visible_rect().size != _laid_for:
		_layout()


## Every text node of the board with its rect (tests).
func shown_rects() -> Array:
	var out := []
	for c in [title_label, page_label, keys_label] + tab_labels:
		out.append([c.text, c.get_global_rect()])
	for i in item_panels.size():
		if item_panels[i].visible:
			out.append([item_labels[i].text, item_panels[i].get_global_rect()])
	return out
