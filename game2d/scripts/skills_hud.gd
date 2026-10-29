class_name SkillsHud
extends CanvasLayer
## 武学与经营 第一批 · 武学 (A): what the skills put on the screen.
##   U / I icons   two 16x16 icons (assets/skills/icons.png: 燕回旋 / empty slot) with their key letter in the bottom-left
##                 corner (方案: 屏幕左下角; the HP bar is top-left, right under it is the objective line - so the corner),
##                 above the key hint while that shows on the left. Shown only once a move is learned. Cooling down: the shader
##                 scripts/skill_cooldown.gdshader darkens the part still cooling, sweeping round clockwise.
##   learned       「学会：燕回旋（U）」 in the middle of the screen inside a turning ring of light (assets/skills/tuna_ring.png,
##                 drawn 2x), a gold flash round the screen edge (scripts/skill_edge_glow.gdshader), ~2.4 s, never holds
##                 play. One after the other when several come at once.

const ICON_SIZE := 16.0
const LEARN_SECONDS := 2.4

var skills: Node
var root: Control
var icons_box: Control
var icon_rects := {}               # slot "u" / "i" -> TextureRect
var icon_keys := {}                # slot -> Label
var icon_mats := {}                # slot -> ShaderMaterial
var icon_tex := {}                 # "swallow_spin" / "empty" -> AtlasTexture
var edge: ColorRect
var edge_mat: ShaderMaterial
var learn_box: Control
var learn_ring: AnimatedSprite2D
var learn_label: Label
var learn_shown: Array[String] = []    # every caption shown (tests)
var _queue: Array = []
var _tween: Tween


func setup(sk: Node) -> void:
	skills = sk
	name = "SkillsHud"
	layer = 12
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_icons()
	_build_learn()


func _build_icons() -> void:
	var fx: SkillsFx = skills.fx
	if fx != null and fx.has_art("icons"):
		var sf: SpriteFrames = fx.frames["icons"]
		# own textures (not atlas regions): the cooldown shader works in the icon's UV 0..1
		for pair in [["swallow_spin", 0], ["empty", 1]]:
			var at: Texture2D = sf.get_frame_texture("icons", pair[1])
			icon_tex[pair[0]] = ImageTexture.create_from_image(at.get_image())
	icons_box = Control.new()
	icons_box.name = "SkillIcons"
	icons_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons_box.visible = false
	root.add_child(icons_box)
	var shader: Shader = load("res://scripts/skill_cooldown.gdshader")
	var x := 0.0
	for slot in ["u", "i"]:
		var tr := TextureRect.new()
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		tr.size = Vector2(ICON_SIZE, ICON_SIZE)
		tr.position = Vector2(x, 0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = shader
		tr.material = m
		icons_box.add_child(tr)
		var k := Label.new()
		k.text = slot.to_upper()
		k.add_theme_font_size_override("font_size", 8)
		k.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
		k.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.06, 1.0))
		k.add_theme_constant_override("shadow_offset_x", 1)
		k.add_theme_constant_override("shadow_offset_y", 1)
		k.position = Vector2(x + ICON_SIZE - 4, ICON_SIZE - 9)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons_box.add_child(k)
		icon_rects[slot] = tr
		icon_keys[slot] = k
		icon_mats[slot] = m
		x += ICON_SIZE + 6.0
	icons_box.size = Vector2(x - 6.0 + 4.0, ICON_SIZE + 2.0)


func _build_learn() -> void:
	edge = ColorRect.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_mat = ShaderMaterial.new()
	edge_mat.shader = load("res://scripts/skill_edge_glow.gdshader")
	edge.material = edge_mat
	edge.visible = false
	root.add_child(edge)
	learn_box = Control.new()
	learn_box.name = "LearnCaption"
	learn_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	learn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	learn_box.modulate.a = 0.0
	learn_box.visible = false
	root.add_child(learn_box)
	learn_ring = AnimatedSprite2D.new()
	learn_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	learn_ring.scale = Vector2(2, 2)
	var fx: SkillsFx = skills.fx
	if fx != null and fx.has_art("tuna_ring"):
		learn_ring.sprite_frames = fx.frames["tuna_ring"]
	learn_box.add_child(learn_ring)
	learn_label = Label.new()
	learn_label.add_theme_font_size_override("font_size", 14)
	learn_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.62))
	learn_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	learn_label.add_theme_constant_override("shadow_offset_x", 1)
	learn_label.add_theme_constant_override("shadow_offset_y", 1)
	learn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	learn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	learn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	learn_box.add_child(learn_label)


# ------------------------------------------------------------------ U / I icons
func icons_visible() -> bool:
	return icons_box != null and icons_box.visible


func icons_rect() -> Rect2:
	return icons_box.get_global_rect() if icons_box != null else Rect2()


## Cooldown fraction left (0..1) of the icon of a slot (tests / screenshots).
func icon_remaining(slot: String) -> float:
	var m: ShaderMaterial = icon_mats.get(slot)
	return float(m.get_shader_parameter("remaining")) if m != null else 0.0


func _process(_delta: float) -> void:
	if skills == null or skills.main == null:
		return
	var m: Node = skills.main
	var want: bool = skills.has_any_move() and not m.story.sandbox
	icons_box.visible = want
	if want:
		# the bottom-left corner of the screen (方案: 屏幕左下角); above the key hint while it shows there
		var vp := get_viewport().get_visible_rect().size
		var y := vp.y - 6.0 - ICON_SIZE
		var h: Hud = m.hud
		if h != null and h.hint != null and h.hint.visible and h.hint.modulate.a > 0.05 and h.hint_side == "left":
			y = minf(y, h.hint_rect_for("left").position.y - 4.0 - ICON_SIZE)
		icons_box.position = Vector2(6.0, y).round()
		for slot in ["u", "i"]:
			var id: String = skills.slots.get(slot, "")
			var tr: TextureRect = icon_rects[slot]
			tr.texture = icon_tex.get(id if id != "" else "empty")
			(icon_mats[slot] as ShaderMaterial).set_shader_parameter("remaining", skills.cooldown_fraction(id) if id != "" else 0.0)
			(icon_keys[slot] as Label).modulate.a = 1.0 if id != "" else 0.55


# ------------------------------------------------------------------ 学会新招
func show_learned(text: String) -> void:
	learn_shown.append(text)
	_queue.append(text)
	if _tween == null or not _tween.is_valid() or not _tween.is_running():
		_next()


func learning_showing() -> bool:
	return learn_box.visible and learn_box.modulate.a > 0.01


func _next() -> void:
	if _queue.is_empty():
		learn_box.visible = false
		edge.visible = false
		return
	learn_label.text = _queue.pop_front()
	var vp := get_viewport().get_visible_rect().size
	learn_label.size = Vector2(vp.x, 24)
	learn_label.position = Vector2(0, roundf(vp.y * 0.5 - 12))
	learn_ring.position = (vp * 0.5).round()
	if learn_ring.sprite_frames != null:
		learn_ring.play("tuna_ring")
	learn_box.visible = true
	learn_box.modulate.a = 0.0
	edge.visible = true
	edge_mat.set_shader_parameter("amount", 0.0)
	_tween = create_tween()
	_tween.tween_property(learn_box, "modulate:a", 1.0, 0.3)
	_tween.parallel().tween_method(func(v): edge_mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.2)
	_tween.tween_method(func(v): edge_mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.6)
	_tween.tween_interval(maxf(0.2, LEARN_SECONDS - 1.4))
	_tween.tween_property(learn_box, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(_next)
