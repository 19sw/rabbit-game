class_name CombatHud
extends CanvasLayer
## Combat UI: player HP bar (right of the minimap), enemy name plates + HP bars, floating damage numbers,
## banners ("切磋开始！", "山贼被赶跑了！"), the spar result panel, the "来过两招？ 切磋 / 算了" choice,
## the black fade for "你被打倒了" and a short screen flash on a successful dodge.
## v1.2: name plates pick a spot that covers no other fighter's body (above head -> below feet -> sideways ->
## bar only); damage numbers sit under the result panel and are hidden where they would cover it; floating
## text that would overlap the banner ("切磋开始！") is moved below it.

## Damage number colours / float (暴露变量: tweak in the editor on this node)
@export var number_color := Color(1, 1, 1)
@export var counter_color := Color(1.0, 0.82, 0.25)
@export var player_hurt_color := Color(1.0, 0.35, 0.3)
@export var float_rise := 12.0
@export var float_time := 0.6

const HP_BAR_W := 64.0
const BODY_HALF_W := 10.0   # body rect of a 32x32 character around its feet (screen px)
const BODY_H := 30.0
const PLATE_GAP := 3.0
const PLATE_ABOVE := 50.0  # bottom of a plate above the head sits this high over the feet (as in v1): the damage
                           # numbers float in the gap between the head and the plate

var hp_panel: PanelContainer
var hp_label: Label
var hp_bar: _Bar
var plates := {}          # fighter -> {panel, label, bar}
var numbers: Array = []   # {label, world, t}
var numbers_root: Control
var avoid_rects: Array = []   # screen rects plates must avoid (minimap, clock, HP panel ...), set by Combat
var plate_rects := {}     # fighter -> Rect2 (screen) of its plate this frame (tests)
var plate_compact := {}   # plate panel -> true when only the HP bar fits
var banner: Label
var banner_sub: Label
var _banner_tween: Tween
var result_panel: PanelContainer
var result_title: Label
var result_line: Label
var choice: PanelContainer
var choice_title: Label
var choice_opts: Array[Label] = []
var choice_hint: Label
var choice_index := 0
var fade: ColorRect
var fade_label: Label
var flash_rect: ColorRect
var root: Control
var _flash_tween: Tween


func _init() -> void:
	layer = 11
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(root)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 0.95, 0.8, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	hp_panel = _panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	hp_label = _label("生命 100/100", 9, Color(1, 0.96, 0.88))
	vb.add_child(hp_label)
	hp_bar = _Bar.new()
	hp_bar.custom_minimum_size = Vector2(HP_BAR_W, 4)
	hp_bar.fg = Color(0.85, 0.25, 0.22)
	vb.add_child(hp_bar)
	hp_panel.add_child(vb)
	root.add_child(hp_panel)

	numbers_root = Control.new()
	numbers_root.name = "Numbers"
	numbers_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	numbers_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(numbers_root)

	banner = _label("", 14, Color(1, 0.93, 0.6))
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	banner.add_theme_constant_override("shadow_offset_x", 1)
	banner.add_theme_constant_override("shadow_offset_y", 1)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-120, 52)
	banner.size = Vector2(240, 20)
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_sub = _label("", 10, Color(1, 0.96, 0.88))
	banner_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	banner_sub.add_theme_constant_override("shadow_offset_x", 1)
	banner_sub.add_theme_constant_override("shadow_offset_y", 1)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_sub.position = Vector2(-120, 74)
	banner_sub.size = Vector2(240, 16)
	banner_sub.modulate.a = 0.0
	root.add_child(banner_sub)

	result_panel = _panel(Color(0.12, 0.09, 0.08, 0.88), Color(0.95, 0.8, 0.45, 1))
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	result_title = _label("", 16, Color(1, 0.88, 0.45))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_line = _label("", 10, Color(1, 0.96, 0.88))
	result_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_title)
	rv.add_child(result_line)
	result_panel.add_child(rv)
	result_panel.visible = false
	root.add_child(result_panel)

	choice = _panel(Color(1.0, 0.97, 0.9, 0.97), Color(0.47, 0.24, 0.16, 1))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	choice_title = _label("", 10, Color(0.27, 0.14, 0.1))
	cv.add_child(choice_title)
	for i in 2:
		var l := _label("", 10, Color(0.27, 0.14, 0.1))
		cv.add_child(l)
		choice_opts.append(l)
	choice_hint = _label("", 8, Color(0.45, 0.3, 0.22))
	cv.add_child(choice_hint)
	choice.add_child(cv)
	choice.visible = false
	root.add_child(choice)

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	fade_label = _label("", 14, Color(0.95, 0.85, 0.8))
	fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fade_label.set_anchors_preset(Control.PRESET_CENTER)
	fade_label.position = Vector2(-100, -10)
	fade_label.size = Vector2(200, 20)
	fade_label.modulate.a = 0.0
	root.add_child(fade_label)


## Places the HP panel right of the minimap (top-left corner area, never over the minimap/objective/clock).
func place_hp(minimap_rect: Rect2) -> void:
	hp_panel.position = Vector2(minimap_rect.end.x + 6, minimap_rect.position.y - 1)


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


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


# ------------------------------------------------------------------ per frame
func update_player(hp: int, max_hp: int, regen := false) -> void:
	hp_label.text = "生命 %d/%d" % [hp, max_hp]
	hp_bar.ratio = clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	hp_bar.regen = regen
	hp_bar.queue_redraw()


func update_plates(fighters: Array, extra_bodies: Array = []) -> void:
	# bodies on screen: every visible fighter (and the player) - a plate may not cover any body except its owner's
	var bodies := {}
	for f in fighters:
		if f.visible:
			bodies[f] = body_rect(f.global_position)
	var extra: Array = extra_bodies.map(func(p): return body_rect(p))
	var placed: Array = []
	var order := fighters.duplicate()
	order.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	plate_rects.clear()
	for f in order:
		var show: bool = (f.engaged or f.state == "yield") and f.state not in ["down", "gone", "return", "idle"] and f.visible
		if not plates.has(f):
			var p := _panel(Color(0.10, 0.08, 0.09, 0.7), Color(0.6, 0.3, 0.25, 0.9))
			var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
			sb.content_margin_left = 3
			sb.content_margin_right = 3
			sb.content_margin_top = 1
			sb.content_margin_bottom = 2
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			var l := _label(f.full_name, 8, Color(1, 0.92, 0.85))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var b := _Bar.new()
			b.custom_minimum_size = Vector2(36, 3)
			b.fg = Color(0.9, 0.3, 0.25)
			v.add_child(l)
			v.add_child(b)
			p.add_child(v)
			root.add_child(p)
			root.move_child(p, 1)
			plates[f] = {"panel": p, "label": l, "bar": b}
		var e: Dictionary = plates[f]
		e["panel"].visible = show
		if not show:
			continue
		e["bar"].ratio = clampf(float(f.hp) / float(f.stats.max_hp), 0.0, 1.0)
		e["bar"].queue_redraw()
		var blockers: Array = extra.duplicate()
		for o in bodies:
			if o != f:
				blockers.append(bodies[o])
		blockers.append_array(placed)
		blockers.append_array(avoid_rects)
		var rect := _place_plate(e, f.global_position, blockers)
		e["panel"].size = rect.size
		e["panel"].position = rect.position
		placed.append(rect)
		plate_rects[f] = rect


## Screen rect of a 32x32 character's body standing at `feet` (world).
func body_rect(feet: Vector2) -> Rect2:
	var s := _screen(feet)
	return Rect2(s.x - BODY_HALF_W, s.y - BODY_H, BODY_HALF_W * 2.0, BODY_H)


## Picks the first spot (above the head, below the feet, beside the body ...) where the plate covers nothing in
## `blockers`; if none is clear with the name, tries again with only the HP bar; else the least-covering spot.
func _place_plate(e: Dictionary, feet: Vector2, blockers: Array) -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var s := _screen(feet)
	var best := Rect2()
	var best_cost := INF
	var best_compact := false
	for compact in [false, true]:
		e["label"].visible = not compact
		var sz: Vector2 = e["panel"].get_combined_minimum_size()
		var above := s.y - PLATE_ABOVE - sz.y
		var below := s.y + PLATE_GAP
		var mid := s.y - BODY_H * 0.5 - sz.y * 0.5
		var side := BODY_HALF_W + PLATE_GAP
		var spots := [Vector2(s.x - sz.x * 0.5, above), Vector2(s.x - sz.x * 0.5, below),
			Vector2(s.x - side - sz.x, above), Vector2(s.x + side, above),
			Vector2(s.x - side - sz.x, below), Vector2(s.x + side, below),
			Vector2(s.x - side - sz.x, mid), Vector2(s.x + side, mid)]
		for pos in spots:
			pos.x = clampf(pos.x, 2.0, vp.x - sz.x - 2.0)
			pos.y = clampf(pos.y, 2.0, vp.y - sz.y - 2.0)
			var r := Rect2(pos.round(), sz)
			var cost := 0.0
			for bl in blockers:
				if r.intersects(bl):
					cost += maxf(1.0, r.intersection(bl).get_area())
			if cost < best_cost:
				best_cost = cost
				best = r
				best_compact = compact
			if cost == 0.0:
				break
		if best_cost == 0.0:
			break
	e["label"].visible = not best_compact
	plate_compact[e["panel"]] = best_compact
	return best


func plate_visible(f: Node) -> bool:
	return plates.has(f) and plates[f]["panel"].visible


func _process(delta: float) -> void:
	var ban := banner_rect()
	var res := result_panel.get_global_rect() if result_panel.visible else Rect2()
	for n in numbers:
		n["t"] += delta
		var k: float = n["t"] / float_time
		var l: Label = n["label"]
		var sz := l.get_combined_minimum_size()
		l.size = sz
		var pos := (_screen(n["world"]) - Vector2(sz.x * 0.5, sz.y + float_rise * k)).round()
		if ban.has_area() and Rect2(pos, sz).intersects(ban):
			pos.y = ban.end.y + 1.0      # never on top of "切磋开始！" / other banners
		l.position = pos
		l.modulate.a = 1.0 - maxf(0.0, (k - 0.6) / 0.4)
		if res.has_area() and Rect2(pos, sz).intersects(res):
			l.modulate.a = 0.0           # never drawn over the spar result panel
	for n in numbers.filter(func(x): return x["t"] >= float_time):
		n["label"].queue_free()
	numbers = numbers.filter(func(x): return x["t"] < float_time)


# ------------------------------------------------------------------ events
## kind: "hit" (player hits enemy), "counter" (counter hit, gold + 反击), "hurt" (player hurt)
func damage_number(world: Vector2, amount: int, kind: String, counter_word := "反击") -> void:
	var text := "%d" % amount
	var col := number_color
	if kind == "counter":
		text = "%d %s" % [amount, counter_word]
		col = counter_color
	elif kind == "text":
		text = counter_word
		col = counter_color
	elif kind == "hurt":
		text = "-%d" % amount
		col = player_hurt_color
	var l := _label(text, 10 if kind != "counter" else 11, col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	numbers_root.add_child(l)
	numbers.append({"label": l, "world": world, "t": 0.0, "kind": kind, "text": text})


func number_texts() -> Array:
	return numbers.map(func(n): return n["text"])


## Screen rect of the banner text (and its sub line) while it is showing, else an empty rect.
func banner_rect() -> Rect2:
	var r := Rect2()
	if banner.modulate.a > 0.02 and banner.text != "":
		var sz := banner.get_combined_minimum_size()
		var g := banner.get_global_rect()
		r = Rect2(Vector2(g.get_center().x - sz.x * 0.5, g.position.y), Vector2(sz.x, maxf(sz.y, g.size.y)))
		if banner_sub.modulate.a > 0.02 and banner_sub.text != "":
			var g2 := banner_sub.get_global_rect()
			var sz2 := banner_sub.get_combined_minimum_size()
			r = r.merge(Rect2(Vector2(g2.get_center().x - sz2.x * 0.5, g2.position.y), Vector2(sz2.x, maxf(sz2.y, g2.size.y))))
	return r


## Visible number labels as [text, screen rect] (tests).
func visible_numbers() -> Array:
	var out := []
	for n in numbers:
		var l: Label = n["label"]
		if l.modulate.a > 0.01:
			out.append([n["text"], Rect2(l.position, l.size)])
	return out


func show_banner(text: String, sub := "", seconds := 1.6) -> void:
	banner.text = text
	banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	banner.modulate.a = 1.0
	banner_sub.modulate.a = 1.0 if sub != "" else 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(seconds)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	_banner_tween.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.5)


func show_result(title: String, line: String) -> void:
	result_title.text = title
	result_line.text = line
	result_panel.visible = true
	var vp := get_viewport().get_visible_rect().size
	var sz := result_panel.get_combined_minimum_size()
	result_panel.size = sz
	result_panel.position = ((vp - sz) * 0.5 + Vector2(0, -50)).round()


func hide_result() -> void:
	result_panel.visible = false


func screen_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	flash_rect.color.a = 0.35
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_rect, "color:a", 0.0, 0.18)


func show_choice(title: String, opts: Array, hint: String, world_pos: Vector2, index := 0) -> void:
	choice_title.text = title
	choice_hint.text = hint
	choice_index = index
	for i in choice_opts.size():
		choice_opts[i].set_meta("text", "%d %s" % [i + 1, opts[i]])
	_refresh_choice()
	choice.visible = true
	var sz := choice.get_combined_minimum_size()
	choice.size = sz
	choice.position = (_screen(world_pos) - Vector2(sz.x * 0.5, sz.y)).round()


func move_choice(index: int) -> void:
	choice_index = index
	_refresh_choice()


func _refresh_choice() -> void:
	for i in choice_opts.size():
		var sel := i == choice_index
		choice_opts[i].text = ("▶ " if sel else "    ") + String(choice_opts[i].get_meta("text", ""))
		choice_opts[i].add_theme_color_override("font_color", Color(0.75, 0.2, 0.1) if sel else Color(0.27, 0.14, 0.1))


## 试玩反馈 v1: index of the option under `pos` (viewport position of a mouse event), -1 when none.
func choice_at(pos: Vector2) -> int:
	if not choice.visible:
		return -1
	for i in choice_opts.size():
		if choice_opts[i].get_global_rect().has_point(pos):
			return i
	return -1


func hide_choice() -> void:
	choice.visible = false


func fade_out(text: String, seconds: float) -> void:
	fade_label.text = text
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.85, seconds)
	tw.parallel().tween_property(fade_label, "modulate:a", 1.0, seconds)


func fade_in(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, seconds)
	tw.parallel().tween_property(fade_label, "modulate:a", 0.0, seconds)


class _Bar:
	extends Control
	var ratio := 1.0
	var fg := Color(0.85, 0.25, 0.22)
	var regen := false      # 脱战回血 v1.3: soft slow pulse on the filled part (never when full / in combat)
	var _t := 0.0

	func _process(delta: float) -> void:
		if regen:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.12, 0.11, 1))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), fg)
		if regen:
			var k := 0.5 + 0.5 * sin(_t * TAU / 1.6)
			var w := size.x * ratio
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, size.y)), Color(1.0, 0.75, 0.6, 0.10 + 0.14 * k))
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, 1)), Color(1.0, 0.9, 0.8, 0.25 + 0.3 * k))
			# a soft glint sweeping over the filled part
			var gx := fmod(_t * 28.0, w + 12.0) - 6.0
			draw_rect(Rect2(clampf(gx, 0.0, w), 0, clampf(gx + 6.0, 0.0, w) - clampf(gx, 0.0, w), size.y), Color(1, 1, 1, 0.18))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 1.0)
