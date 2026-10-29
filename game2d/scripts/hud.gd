class_name Hud
extends CanvasLayer
## Screen UI: controls hint (fades out, H brings it back), the "按 E …" prompt and the speech bubble that follow an NPC
## or a thing (序章 v1: the walking bubbles of the story), and a short toast (ambience switch, 获得：旧布).

const HINT_TEXT := "WASD / 方向键：移动    J：攻击    空格 / Shift：闪避    E：交谈\nT：时间快进 1 小时    L：氛围灯光开关    H：显示/隐藏本提示\nEsc：查看全部按键和玩法（游戏暂停）"
const OBJECTIVE_PREFIX := "目标："
const PROMPT_TEXT := "按 E 交谈"
const BUBBLE_WRAP := 150.0     # px: longer bubble lines wrap at this width
const HINT_SECONDS := 8.0
const HINT_CLEAR := 14.0       # px around the key hint that must stay clear of the player / things to press E on
const AMBIENCE_ON_TEXT := "氛围灯光：开"
const AMBIENCE_OFF_TEXT := "氛围灯光：关"

var hint: PanelContainer
var hint_label: Label
var prompt: PanelContainer
var prompt_label: Label
var bubble: PanelContainer
var bubble_label: Label
var toast: Label
var minimap: Minimap
var objective: PanelContainer
var objective_label: Label
var clock: PanelContainer
var clock_label: Label
var hint_visible := true
var tasks: Control = null       # 第④步第一批: the "正在做的事" panel under the coins (built by Jianghu)
var _hint_tween: Tween
var _toast_tween: Tween


func _init() -> void:
	layer = 10
	var font: FontFile = load("res://fonts/ui_font.fnt")
	if font:
		font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(root)

	hint = _panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	hint_label = _label(HINT_TEXT, 9, Color(1, 0.96, 0.88))
	hint.add_child(hint_label)
	# bottom-left (the top-left corner belongs to the minimap, top-right to the clock)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 6
	hint.offset_bottom = -6
	root.add_child(hint)

	var margin: float = float(Tuning.data()["minimap"]["margin"])
	minimap = Minimap.new()
	minimap.position = Vector2(margin, margin)
	var mm: Dictionary = Tuning.data()["minimap"]
	var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/map_data.json"))
	minimap.setup(load("res://assets/map/minimap.png"), Vector2(map_data["pixel_width"], map_data["pixel_height"]), mm)
	root.add_child(minimap)

	# 打磨 v1: the objective line sits to the right of the round minimap (never under / over it)
	objective = _panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	objective_label = _label("", 9, Color(1, 0.93, 0.6))
	objective.add_child(objective_label)
	objective.position = Vector2(margin + minimap.size.x + 5, margin + 27)   # under the HP bar (combat_hud.place_hp)
	root.add_child(objective)

	clock = _panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	clock_label = _label("", 10, Color(1, 0.96, 0.85))
	clock.add_child(clock_label)
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	clock.offset_right = -6
	clock.offset_top = 6
	root.add_child(clock)

	prompt = _panel(Color(0.10, 0.08, 0.09, 0.8), Color(0.95, 0.8, 0.45, 1))
	prompt_label = _label(PROMPT_TEXT, 9, Color(1, 0.95, 0.75))
	prompt.add_child(prompt_label)
	prompt.visible = false
	root.add_child(prompt)

	bubble = _panel(Color(1.0, 0.97, 0.9, 0.97), Color(0.47, 0.24, 0.16, 1))
	bubble_label = _label("", 10, Color(0.27, 0.14, 0.1))
	bubble.add_child(bubble_label)
	bubble.visible = false
	root.add_child(bubble)

	toast = _label("", 10, Color(1, 0.95, 0.85))
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.add_theme_constant_override("shadow_offset_y", 1)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.position = Vector2(-60, 8)
	toast.size = Vector2(120, 16)
	toast.modulate.a = 0.0
	root.add_child(toast)


func _ready() -> void:
	_schedule_hint_fade()


func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _schedule_hint_fade() -> void:
	if _hint_tween:
		_hint_tween.kill()
	hint.modulate.a = 1.0
	hint.visible = true
	hint_visible = true
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_SECONDS)
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 1.2)
	_hint_tween.tween_callback(func(): hint.visible = false; hint_visible = false)


## Shows the controls hint again (it fades after HINT_SECONDS) - 序章 v1: after the opening conversation.
func show_hint() -> void:
	_schedule_hint_fade()


## Hides it at once (while a conversation box covers the bottom of the screen).
func hide_hint_now() -> void:
	if _hint_tween:
		_hint_tween.kill()
	hint.visible = false
	hint_visible = false


func toggle_hint() -> void:
	if hint_visible:
		if _hint_tween:
			_hint_tween.kill()
		hint.visible = false
		hint_visible = false
	else:
		_schedule_hint_fade()


func set_clock(text: String) -> void:
	clock_label.text = text


func set_objective(text: String) -> void:
	objective_label.text = text
	objective.visible = text != ""


## Called every frame: minimap centre / arrow / star (target = Interiors.minimap_target result or null). It eases to
## almost transparent while any of `cover_screen` (screen points of the player, NPCs and things to press E on) is
## under it, and to `dialogue_alpha` while a conversation is on screen (tuning.json "minimap").
var minimap_covering := false        # last frame: something was under the minimap (tests)


func update_minimap(player_pos: Vector2, room: String, facing_vec: Vector2, target: Variant, cover_screen: Array,
		in_dialogue: bool, delta: float) -> void:
	minimap.update_state(player_pos, room, facing_vec, target)
	var mm: Dictionary = Tuning.data()["minimap"]
	var margin := float(mm["cover_margin"])
	minimap_covering = false
	for sp in cover_screen:
		if minimap.covers_local((sp as Vector2) - minimap.position, margin):
			minimap_covering = true
			break
	var want := 1.0
	if in_dialogue:
		want = float(mm["dialogue_alpha"])
	elif minimap_covering:
		want = float(mm["covered_alpha"])
	minimap.modulate.a = move_toward(minimap.modulate.a, want, float(mm["fade_per_second"]) * delta)
	_place_hint(cover_screen)


## 打磨 v1 fix round: the key hint never sits on the player or on something to press E on (e.g. the rag in the dorm
## corner right after waking): it goes to the bottom-right corner when the bottom-left one is taken, and back.
var hint_side := "left"


func hint_rect_for(side: String) -> Rect2:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 270)
	var sz := hint.size
	var x := 6.0 if side == "left" else vp.x - 6.0 - sz.x
	return Rect2(Vector2(x, vp.y - 6.0 - sz.y), sz)


func _place_hint(points: Array) -> void:
	var blocked := {}
	for side in ["left", "right"]:
		var r := hint_rect_for(side).grow(HINT_CLEAR)
		blocked[side] = points.any(func(q): return r.has_point(q))
	var side := hint_side
	if blocked[hint_side] and not blocked["right" if hint_side == "left" else "left"]:
		side = "right" if hint_side == "left" else "left"
	elif hint_side == "right" and not blocked["left"]:
		side = "left"
	if side == hint_side:
		return
	hint_side = side
	if side == "left":
		hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		hint.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sz := hint.size
	var r2 := hint_rect_for(side)
	hint.position = r2.position
	hint.size = sz


## The minimap's circle on screen (centre, radius) - layout checks.
func minimap_circle() -> Array:
	return [minimap.position + Vector2(minimap.radius, minimap.radius), minimap.radius]


## 两条路小样 v1: once the coin counter sits in the top row, the toast moves down under it (Sample sets the top).
func set_toast_top(y: float) -> void:
	toast.position.y = y


## Where the toast's text is actually drawn on screen (it is centred and may be wider than the label box).
func toast_text_rect() -> Rect2:
	var f := toast.get_theme_font("font")
	var w := f.get_string_size(Lang.t(toast.text), HORIZONTAL_ALIGNMENT_LEFT, -1, toast.get_theme_font_size("font_size")).x
	var r := toast.get_global_rect()
	return Rect2(Vector2(r.get_center().x - w * 0.5, r.position.y), Vector2(w, r.size.y))


func show_toast(text: String, seconds := 1.2) -> void:
	toast.text = text
	toast.get_parent().move_child(toast, -1)      # drawn above every other HUD panel
	if _toast_tween:
		_toast_tween.kill()
	toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.5)


## Places `panel` centred above a world point (bottom edge at the point).
func place_above(panel: Control, world_pos: Vector2) -> void:
	var screen := get_viewport().get_canvas_transform() * world_pos
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	var pos := screen - Vector2(sz.x * 0.5, sz.y)
	# 修复 v1: never off the screen (a character at the edge of the view keeps his bubble / prompt inside it)
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 2.0, maxf(2.0, vp.x - sz.x - 2.0))
	pos.y = clampf(pos.y, 2.0, maxf(2.0, vp.y - sz.y - 2.0))
	panel.position = pos.round()


func show_prompt(world_pos: Vector2, text := PROMPT_TEXT) -> void:
	prompt_label.text = text
	prompt.visible = true
	place_above(prompt, world_pos)


func hide_prompt() -> void:
	prompt.visible = false


var _bubble_lang := ""


func show_bubble(text: String, world_pos: Vector2) -> void:
	if bubble_label.text != text or _bubble_lang != Lang.current():   # (中英文切换 v1: the wrap is decided per language)
		_bubble_lang = Lang.current()
		bubble_label.text = text
		var w := bubble_label.get_theme_font("font").get_string_size(Lang.t(text), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if w > BUBBLE_WRAP else TextServer.AUTOWRAP_OFF
		bubble_label.custom_minimum_size = Vector2(BUBBLE_WRAP if w > BUBBLE_WRAP else 0.0, 0)
		bubble.size = Vector2.ZERO
	bubble.visible = true
	place_above(bubble, world_pos)


func hide_bubble() -> void:
	bubble.visible = false
