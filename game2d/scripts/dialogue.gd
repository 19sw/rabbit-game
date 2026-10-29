class_name Dialogue
extends CanvasLayer
## 序章 v1 dialogue box (bottom of the screen). Character lines: 64x64 portrait + name tab (称呼) + the line; 旁白 / 提示 /
## 碑文 / 画面 / 字条 (v3) have no portrait and their own look (colour, tab, alignment); 画面 lines can show a picture above the box.
## Text types in letter by letter; E / Enter / Space: show the whole line at once, or go on when it is complete.
## Choices (shown with the line before them): 1 / 2, or ↑↓ then E / Enter / Space - like the spar invitation.
## 第③步: up to MAX_OPTIONS options (keys 1-4); an option can be greyed out (shown, never picked - 帮厨 before the kitchen
## is repaired). Two-option choices look and behave exactly as before.
## 第④步第一批 补充 (client, 2026-10-24): a line never overflows the box. When it needs more lines than the box holds at
## the same font size, it is shown in pages (paginate(): measured with the real label layout; a page ends after 。！？；，、：…
## or a line break where possible); E shows the next page, the choices come with the last one. full_text stays the whole
## line (what the story said); page_text is what is on screen.
## 试玩反馈 v1: the mouse works too - left click = E (complete / go on); with choices showing, the option under the mouse
## is highlighted and a left click on it picks it (a greyed one ignores it; a click elsewhere does nothing). Every mouse
## button is swallowed while a conversation is on screen (never a swing / a guard). Signals for sounds: advanced,
## choice_moved, choice_picked.
## The story (scripts/story.gd) drives it with `await say(entry)` / `await choose(options)`. Pausable: the Esc page
## freezes it with the rest of the game. Input is taken in _input, so the keys never reach the player or the world.

signal line_done
signal advanced                   # 试玩反馈 v1: a line completed at once / next page / next line (E, Enter, Space, click)
signal choice_moved(index: int)   # the selected option changed (↑↓ or the mouse)
signal choice_picked(index: int)

const KIND_STYLE := {
	# kind: [bg, border, tab bg, text colour, centred]
	"speaker": [Color(0.12, 0.09, 0.09, 0.95), Color(0.92, 0.76, 0.45), Color(0.72, 0.24, 0.16), Color(1.0, 0.96, 0.88), false],
	"旁白": [Color(0.05, 0.05, 0.09, 0.9), Color(0.55, 0.6, 0.72), Color(0.32, 0.35, 0.45), Color(0.82, 0.86, 0.95), true],
	"提示": [Color(0.05, 0.15, 0.17, 0.94), Color(0.45, 0.8, 0.78), Color(0.16, 0.48, 0.48), Color(1.0, 0.93, 0.62), false],
	"碑文": [Color(0.46, 0.44, 0.41, 0.97), Color(0.84, 0.81, 0.74), Color(0.3, 0.28, 0.27), Color(0.13, 0.1, 0.1), true],
	"画面": [Color(0.08, 0.06, 0.1, 0.93), Color(0.7, 0.6, 0.8), Color(0.38, 0.28, 0.46), Color(0.93, 0.9, 1.0), true],
	# 剧本 v3: 师兄 left a note on the table - paper, brush ink
	"字条": [Color(0.93, 0.88, 0.74, 0.97), Color(0.55, 0.4, 0.26), Color(0.5, 0.33, 0.2), Color(0.2, 0.13, 0.1), true],
	# 第④步第一批: the 江湖告示榜 - yellowed paper, red tab, left-aligned (lists of 悬赏 / 委托)
	"告示": [Color(0.94, 0.88, 0.72, 0.97), Color(0.6, 0.22, 0.14), Color(0.7, 0.2, 0.12), Color(0.24, 0.12, 0.08), false],
}
const BOX_H := 74.0
const PORTRAIT := 64.0
## 坐姿-高清过场-运镜 方案 v1: the HD portraits (128x128, pixel2d/portraits_hd) drawn into the same 64x64 box - 2x the
## pixels. A speaker without an HD file keeps the old 64x64 one.
const PORTRAIT_HD_DIR := "res://assets/portraits_hd/"
const HD_SHADER := preload("res://scripts/hd_pixel.gdshader")
const NEXT_MARK := "▼"
const START_GUARD := 0.08      # s after a line appears in which a key press is ignored (no accidental double skip)
const MAX_OPTIONS := 5          # 武学与经营第一批 (B): 派活 帮厨 / 陪练 / 打扫 / 种地 / 算了 (keys 1-5)
const MANY_HINT := "1–%d 或 ↑↓ + E"
const GREY := Color(0.55, 0.52, 0.48)

var cps := 32.0
var speakers: Dictionary = {}
var portraits: Dictionary = {}     # speaker id -> Texture2D
var pictures: Dictionary = {}      # picture id -> Texture2D
var choice_hint_text := ""

var root: Control
var box: Panel
var box_style: StyleBoxFlat
var portrait_frame: Panel
var portrait: TextureRect
var hd_material: ShaderMaterial    # the HD portraits' sampling (one shared material)
var name_tab: PanelContainer
var name_tab_style: StyleBoxFlat
var name_label: Label
var text_label: Label
var next_mark: Label
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var choice_labels: Array[Label] = []
var choice_hint: Label
var picture_panel: PanelContainer
var picture: TextureRect

var active := false               # a line or a choice is on screen
var entry: Dictionary = {}        # current line
var kind := ""                    # "speaker" or 旁白 / 提示 / 碑文 / 画面
var speaker_name := ""
var full_text := ""            # the whole line
var screen_text := ""          # full_text in the language being played (中英文切换 v1: Lang.t); pages are cut from it
var _lang_for := ""
var pages: PackedStringArray = []   # full_text cut into pages that fit the box
var page := 0
var page_text := ""            # the page on screen
var pages_shown := 0           # statistics for tests
var relayouts := 0             # statistics for tests (修复 v1: window resized while a line is on screen)
var _laid_out_for := Vector2.ZERO
var shown := 0.0               # characters of page_text typed so far
var choosing := false
var choice_options: Array = []
var choice_disabled: Array = []   # bool per option (greyed: shown, never picked)
var choice_index := 0
var last_choice := -1             # index picked for the last line that had options
var lines_shown := 0              # statistics for tests
var _guard := 0.0
var _blink := 0.0


func _init() -> void:
	name = "Dialogue"
	layer = 20
	add_to_group("dialogue")


func setup(story_data: Dictionary) -> void:
	cps = float(story_data.get("typewriter_chars_per_second", 32))
	speakers = story_data.get("speakers", {})
	for id in speakers:
		var pid := String(speakers[id].get("portrait", id))
		var p := "res://assets/portraits/%s.png" % pid
		if ResourceLoader.exists(PORTRAIT_HD_DIR + pid + ".png"):
			portraits[id] = load(PORTRAIT_HD_DIR + pid + ".png")
		elif ResourceLoader.exists(p):
			portraits[id] = load(p)
	var pics: Dictionary = story_data.get("pictures", {})
	for k in pics:
		if ResourceLoader.exists(pics[k]):
			pictures[k] = load(pics[k])
	choice_hint_text = String(story_data.get("ui", {}).get("choice_hint", ""))
	_build()


func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.visible = false
	add_child(root)

	picture_panel = PanelContainer.new()
	picture_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture_panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.1, 0.94), Color(0.92, 0.76, 0.45), 4))
	picture = TextureRect.new()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.stretch_mode = TextureRect.STRETCH_KEEP
	picture_panel.add_child(picture)
	picture_panel.visible = false
	root.add_child(picture_panel)

	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_style = _box(Color.BLACK, Color.WHITE, 0)
	box_style.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", box_style)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = -BOX_H - 6
	box.offset_bottom = -6
	root.add_child(box)

	portrait_frame = Panel.new()
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", _box(Color(0.98, 0.93, 0.82), Color(0.47, 0.24, 0.16), 0))
	portrait_frame.position = Vector2(5, 5)
	portrait_frame.size = Vector2(PORTRAIT, PORTRAIT)
	box.add_child(portrait_frame)
	portrait = TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE     # any texture size is drawn into the 64x64 box
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.size = Vector2(PORTRAIT, PORTRAIT)
	portrait_frame.add_child(portrait)

	name_tab = PanelContainer.new()
	name_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_tab_style = _box(Color.RED, Color(0.47, 0.24, 0.16), 6)
	name_tab.add_theme_stylebox_override("panel", name_tab_style)
	name_label = _label("", 10, Color(1.0, 0.95, 0.85))
	name_tab.add_child(name_label)
	box.add_child(name_tab)

	text_label = _label("", 11, Color.WHITE)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_constant_override("line_spacing", 1)
	text_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # (中英文切换 v1: it shows screen_text, already translated)
	box.add_child(text_label)

	next_mark = _label(NEXT_MARK, 8, Color(1.0, 0.85, 0.45))
	box.add_child(next_mark)

	choice_panel = PanelContainer.new()
	choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_panel.add_theme_stylebox_override("panel", _box(Color(0.12, 0.09, 0.09, 0.96), Color(0.92, 0.76, 0.45), 6))
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 1)
	choice_panel.add_child(choice_box)
	for i in MAX_OPTIONS:
		var l := _label("", 10, Color.WHITE)
		choice_box.add_child(l)
		choice_labels.append(l)
	choice_hint = _label(choice_hint_text, 8, Color(0.85, 0.8, 0.7))
	choice_box.add_child(choice_hint)
	choice_panel.visible = false
	root.add_child(choice_panel)


func _box(bg: Color, border: Color, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ API used by the story
## Name shown for a line: the speaker's 称呼, or the kind (旁白 / 提示 / 碑文 / 画面).
## 改名与起名 v1: the hero's name is {name} in the data - the name the player chose is put in here.
func name_for(e: Dictionary) -> String:
	if e.has("who"):
		return PlayerName.fill(String(speakers.get(e["who"], {}).get("name", e["who"])))
	return String(e.get("kind", ""))


## Shows one line and waits until the player has read it (await say(entry)). `options` (optional) are shown with it
## once it is typed; then it returns after a pick, which is left in `last_choice`.
func say(e: Dictionary, options: Array = [], disabled: Array = []) -> void:
	entry = e
	kind = "speaker" if e.has("who") else String(e.get("kind", "旁白"))
	speaker_name = name_for(e)
	full_text = PlayerName.fill(String(e.get("text", "")))     # 改名与起名 v1: {name} -> the hero's name
	screen_text = _screen(full_text)
	shown = 0.0
	_guard = START_GUARD
	choosing = false
	choice_options = options.slice(0, MAX_OPTIONS)
	choice_disabled = []
	for i in choice_options.size():
		choice_disabled.append(i < disabled.size() and bool(disabled[i]))
	choice_index = _first_enabled()
	lines_shown += 1
	_apply_style()
	pages = paginate(screen_text)
	page = 0
	_show_page()
	_laid_out_for = get_viewport().get_visible_rect().size
	active = true
	root.visible = true
	text_label.visible_characters = 0
	choice_panel.visible = false
	next_mark.visible = false
	if OS.has_feature("web"):
		print("story: line %s" % speaker_name)
	await line_done


func close() -> void:
	active = false
	choosing = false
	root.visible = false
	picture_panel.visible = false
	choice_panel.visible = false


func is_typing() -> bool:
	return active and int(shown) < page_text.length()


func shown_text() -> String:
	return page_text.substr(0, int(shown))


func has_more_pages() -> bool:
	return page < pages.size() - 1


func _show_page() -> void:
	page_text = pages[page] if page < pages.size() else ""
	text_label.text = page_text
	shown = 0.0
	text_label.visible_characters = 0
	pages_shown += 1


# ------------------------------------------------------------------ pages (补充: nothing ever overflows the box)
const BREAK_AFTER := "。！？；，、：…—\n!?;,:"
const BREAK_AFTER_EN := ". "        # 中英文切换 v1: English pages may also end after a full stop or between two words
const CLOSERS := "”’）」』】》"


## Height (px) the text may use inside the box.
func text_room() -> float:
	return BOX_H - 22.0


## One line's height in the box (font height + line spacing).
func line_height() -> float:
	var f := text_label.get_theme_font("font")
	var fs := text_label.get_theme_font_size("font_size")
	return f.get_height(fs) + float(text_label.get_theme_constant("line_spacing"))


## How many lines fit in the box.
func line_capacity() -> int:
	var sp := float(text_label.get_theme_constant("line_spacing"))
	return maxi(1, int(floor((text_room() + sp) / line_height())))


## Lines `t` takes in the text label as it is laid out now (width = the box's text width).
func lines_for(t: String) -> int:
	var keep := text_label.text
	var keep_vc := text_label.visible_characters
	text_label.visible_characters = -1       # (the label shapes only the typed characters otherwise)
	text_label.text = t
	var n := text_label.get_line_count()
	text_label.text = keep
	text_label.visible_characters = keep_vc
	return n


## `text` cut into pages that each fit the box (the label's current style / width must be set: _apply_style()).
func paginate(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cap := line_capacity()
	var rest := text
	var guard := 0
	var en := Lang.is_en()
	var breaks := BREAK_AFTER + (BREAK_AFTER_EN if en else "")
	var trim := "\n " if en else "\n"
	while rest != "" and guard < 64:
		guard += 1
		if lines_for(rest) <= cap:
			out.append(rest)
			break
		var lo := 1
		var hi := rest.length()
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if lines_for(rest.substr(0, mid)) <= cap:
				lo = mid
			else:
				hi = mid - 1
		var cut := lo
		# end the page after a punctuation mark (or a line break) when there is one in its second half
		for i in range(cut - 1, int(cut * 0.5) - 1, -1):
			if breaks.contains(rest[i]):
				var c := i + 1
				while c < cut and CLOSERS.contains(rest[c]):
					c += 1
				cut = c
				break
		# never start the next page with a closing mark
		while cut < rest.length() and CLOSERS.contains(rest[cut]) and cut > 1:
			cut -= 1
		out.append(rest.substr(0, cut).rstrip(trim))
		rest = rest.substr(cut).lstrip(trim)
	if out.is_empty():
		out.append(text)
	return out


## HD portrait: coverage sampling (even pixels at the 3x window); a 64 px one: plain nearest, as before.
func _portrait_sampling() -> void:
	var hd := portrait.texture != null and portrait.texture.get_width() > int(PORTRAIT)
	portrait.material = null
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if hd:
		if hd_material == null:
			hd_material = ShaderMaterial.new()
			hd_material.shader = HD_SHADER
		portrait.material = hd_material
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func current_portrait() -> Texture2D:
	return portrait.texture if portrait_frame.visible else null


func _apply_style() -> void:
	var st: Array = KIND_STYLE.get(kind, KIND_STYLE["旁白"])
	box_style.bg_color = st[0]
	box_style.border_color = st[1]
	name_tab_style.bg_color = st[2]
	text_label.add_theme_color_override("font_color", st[3])
	name_label.text = speaker_name
	text_label.text = screen_text
	var has_portrait := kind == "speaker"
	portrait_frame.visible = has_portrait
	portrait.texture = portraits.get(entry.get("who", ""), null) if has_portrait else null
	_portrait_sampling()
	var left := PORTRAIT + 14.0 if has_portrait else 12.0
	name_tab.position = Vector2(left - 4.0, -9.0)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if st[4] else HORIZONTAL_ALIGNMENT_LEFT
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if st[4] else VERTICAL_ALIGNMENT_TOP
	text_label.position = Vector2(left, 13.0)
	# (修复 v1) from the screen, not from box.size: right after a window resize the box has not been re-anchored yet
	var bw := get_viewport().get_visible_rect().size.x - 16.0
	var tw := bw - left - 12.0
	text_label.custom_minimum_size = Vector2(tw, 0)
	text_label.size = Vector2(tw, 0)          # width first: the wrapped height depends on it
	text_label.size = Vector2(tw, BOX_H - 22.0)
	next_mark.position = Vector2(bw - 14.0, BOX_H - 14.0)
	var pic_id := String(entry.get("image", ""))
	picture_panel.visible = pic_id != "" and pictures.has(pic_id)
	if picture_panel.visible:
		picture.texture = pictures[pic_id]
		var vp := get_viewport().get_visible_rect().size
		var sz := picture_panel.get_combined_minimum_size()
		picture_panel.size = sz
		picture_panel.position = (Vector2((vp.x - sz.x) * 0.5, vp.y - BOX_H - 14.0 - sz.y)).round()


## 修复 v1: the window (browser canvas) changed size while a line is on screen - lay the box out again for the new
## width, cut the line into pages again and stay on the page holding the text that was being read; the choices and the
## picture move with the box.
func relayout() -> void:
	_laid_out_for = get_viewport().get_visible_rect().size
	relayouts += 1
	var start := page_start(page)
	var typed_all := not is_typing()
	var typed := int(shown)
	_apply_style()
	pages = paginate(screen_text)
	page = pages.size() - 1
	for i in pages.size():
		if page_start(i) + pages[i].length() > start:
			page = i
			break
	page_text = pages[page]
	text_label.text = page_text
	shown = float(page_text.length()) if typed_all else float(clampi(typed - (page_start(page) - start), 0, page_text.length()))
	text_label.visible_characters = -1 if typed_all else int(shown)
	if choosing and has_more_pages():
		choosing = false          # the choices come back with the last page
		choice_panel.visible = false
	elif choosing:
		_show_choices()


## 中英文切换 v1: the language changed while a line is on screen - the same line in the new language, from its first
## page, shown at once (the player was already reading it).
func relayout_language() -> void:
	screen_text = _screen(full_text)
	_laid_out_for = get_viewport().get_visible_rect().size
	relayouts += 1
	_apply_style()
	pages = paginate(screen_text)
	page = 0
	page_text = pages[0]
	text_label.text = page_text
	shown = float(page_text.length())
	text_label.visible_characters = -1
	if choosing and has_more_pages():
		choosing = false
		choice_panel.visible = false
	elif choosing:
		_show_choices()
	elif not has_more_pages():
		_on_complete()


## 改名与起名 v1: renamed on the Esc page while a line is on screen - the line again with the new name (shown at once,
## like after a language switch).
func refresh_name() -> void:
	if not active:
		return
	speaker_name = name_for(entry)
	full_text = PlayerName.fill(String(entry.get("text", "")))
	relayout_language()


func _screen(t: String) -> String:
	_lang_for = Lang.current()
	return Lang.t(t)


## Index in screen_text where page `i` starts.
func page_start(i: int) -> int:
	var at := 0
	for j in mini(i, pages.size()):
		var f := screen_text.find(pages[j], at)
		at = (f if f >= 0 else at) + pages[j].length()
	if i < pages.size():
		var f2 := screen_text.find(pages[i], at)
		return f2 if f2 >= 0 else at
	return at


func _show_choices() -> void:
	choosing = true
	for i in choice_labels.size():
		choice_labels[i].visible = i < choice_options.size()
	choice_hint.text = choice_hint_text if choice_options.size() <= 2 else MANY_HINT % choice_options.size()
	_refresh_choices()
	choice_panel.visible = true
	var vp := get_viewport().get_visible_rect().size
	var sz := choice_panel.get_combined_minimum_size()
	choice_panel.size = sz
	choice_panel.position = Vector2(vp.x - 8.0 - sz.x, vp.y - BOX_H - 10.0 - sz.y).round()


func _refresh_choices() -> void:
	for i in mini(choice_labels.size(), choice_options.size()):
		var on := i == choice_index
		choice_labels[i].text = "%s %d. %s" % ["▶" if on else "  ", i + 1, String(choice_options[i])]
		var col := Color(1.0, 0.86, 0.42) if on else Color(0.92, 0.88, 0.8)
		if is_disabled(i):
			col = GREY
		choice_labels[i].add_theme_color_override("font_color", col)


func is_disabled(i: int) -> bool:
	return i >= 0 and i < choice_disabled.size() and bool(choice_disabled[i])


func _first_enabled() -> int:
	for i in choice_options.size():
		if not is_disabled(i):
			return i
	return 0


## ↑ / ↓: the previous / next option that can be picked (stays put at the ends, like the two-option choice).
func _step_choice(step: int) -> void:
	var before := choice_index
	var i := choice_index + step
	while i >= 0 and i < choice_options.size():
		if not is_disabled(i):
			choice_index = i
			break
		i += step
	_refresh_choices()
	if choice_index != before:
		choice_moved.emit(choice_index)


## 试玩反馈 v1: index of the option label under `pos` (viewport position of a mouse event), -1 when none.
func choice_at(pos: Vector2) -> int:
	if not choosing or not choice_panel.visible:
		return -1
	for i in mini(choice_labels.size(), choice_options.size()):
		if choice_labels[i].visible and choice_labels[i].get_global_rect().has_point(pos):
			return i
	return -1


## The mouse moved over option i: highlight it (greyed options are never highlighted).
func _hover(i: int) -> void:
	if i < 0 or is_disabled(i) or i == choice_index:
		return
	choice_index = i
	_refresh_choices()
	choice_moved.emit(i)


func _process(delta: float) -> void:
	if not active:
		return
	if Lang.current() != _lang_for:
		relayout_language()
	elif get_viewport().get_visible_rect().size != _laid_out_for:
		relayout()
	if text_label.size.y != BOX_H - 22.0:
		text_label.size = Vector2(text_label.size.x, BOX_H - 22.0)   # (the first layout pass can leave it too tall)
	_guard = maxf(0.0, _guard - delta)
	if int(shown) < page_text.length():
		shown = minf(float(page_text.length()), shown + cps * delta)
		text_label.visible_characters = int(shown)
		if int(shown) >= page_text.length():
			_on_complete()
	_blink += delta
	next_mark.visible = not choosing and not is_typing() and fmod(_blink, 0.8) < 0.5


func _on_complete() -> void:
	text_label.visible_characters = -1
	if not choice_options.is_empty() and not choosing and not has_more_pages():
		_show_choices()


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if active and event is InputEventMouse:
		_mouse_input(event)
		return
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var used := true
	if choosing:
		if event.is_action_pressed("choice_1"):
			_pick(0)
		elif event.is_action_pressed("choice_2") and choice_options.size() > 1:
			_pick(1)
		elif InputMap.has_action("choice_3") and event.is_action_pressed("choice_3") and choice_options.size() > 2:
			_pick(2)
		elif InputMap.has_action("choice_4") and event.is_action_pressed("choice_4") and choice_options.size() > 3:
			_pick(3)
		elif InputMap.has_action("choice_5") and event.is_action_pressed("choice_5") and choice_options.size() > 4:
			_pick(4)
		elif event.is_action_pressed("move_up"):
			_step_choice(-1)
		elif event.is_action_pressed("move_down"):
			_step_choice(1)
		elif _is_advance(event):
			_pick(choice_index)
		elif event.is_action_pressed("pause"):
			used = false
		else:
			used = not (event.is_action_pressed("toggle_ambience") or event.is_action_pressed("time_skip") or event.is_action_pressed("toggle_hint"))
	elif _is_advance(event):
		advance()
	elif event.is_action_pressed("pause") or event.is_action_pressed("toggle_ambience") or event.is_action_pressed("time_skip") \
			or event.is_action_pressed("toggle_hint"):
		used = false    # Esc page, L / T / H keep working during a conversation
	else:
		used = event.is_action_pressed("attack") or event.is_action_pressed("dash") or event.is_action_pressed("choice_1") \
			or event.is_action_pressed("choice_2") or event.is_action_pressed("sect_book") \
			or (InputMap.has_action("gp") and event.is_action_pressed("gp"))     # 试玩反馈 v1: K never guards from a conversation
	if used:
		get_viewport().set_input_as_handled()


## 试玩反馈 v1: mouse during a conversation (see the header). Motion is left to the GUI as well (hover looks); buttons
## are always swallowed.
func _mouse_input(event: InputEventMouse) -> void:
	if event is InputEventMouseMotion:
		if choosing:
			_hover(choice_at(event.position))
		return
	get_viewport().set_input_as_handled()
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if choosing:
		var i := choice_at(mb.position)
		if i >= 0:
			_pick(i)
		return
	advance()


static func _is_advance(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	var k: InputEventKey = event
	for code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if k.keycode == code or k.physical_keycode == code:
			return true
	return false


## E / Enter / Space: complete the line, or go on.
func advance() -> void:
	if not active or _guard > 0.0:
		return
	if is_typing():
		shown = float(page_text.length())
		text_label.visible_characters = -1
		_on_complete()
		advanced.emit()
		return
	if choosing:
		return
	if has_more_pages():
		page += 1
		_show_page()
		_guard = START_GUARD
		advanced.emit()
		return
	active = false
	advanced.emit()
	line_done.emit()


func _pick(i: int) -> void:
	if not choosing or _guard > 0.0 or is_disabled(i):
		return
	choice_index = i
	last_choice = i
	_refresh_choices()
	choosing = false
	choice_panel.visible = false
	active = false
	choice_picked.emit(i)
	line_done.emit()
