class_name WardrobePanel
extends CanvasLayer
## 打磨 v1: the dorm wardrobe opened (S1-衣柜). A panel above the dialogue box shows the clothes inside as 64x64 pixel
## icons (assets/interiors/wardrobe_clothes.png, drawn by pixel2d/interiors/tools/interior_art.py garment_icon() in the
## rabbit's outfit colours): two spare training outfits (the newer one, the older one), the one 师父 patched, the
## childhood short-sleeve top. The story opens it with the scene and closes it when the scene ends.

const SHEET := "res://assets/interiors/wardrobe_clothes.png"
const ICON := 64
const TOP_Y := 64.0         # fix round: under the objective line (it ends at y ~52) and the minimap (y 62)

var is_open := false
var icons: Array[TextureRect] = []
var panel: PanelContainer
var title_label: Label
var opened_count := 0       # statistics for tests
var _tween: Tween


func _init() -> void:
	name = "WardrobePanel"
	layer = 15                  # above the HUD (10), under the dialogue box (20)


func setup(title: String) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.13, 0.09, 0.96)
	sb.border_color = Color(0.85, 0.66, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	vb.add_child(title_label)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	var tex: Texture2D = load(SHEET)
	var n := int(tex.get_width() / ICON) if tex else 0
	for i in n:
		var cell := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.3, 0.2, 0.14, 1)          # the inside of the wardrobe (dark wood)
		cs.border_color = Color(0.48, 0.33, 0.22)
		cs.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", cs)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * ICON, 0, ICON, ICON)
		var tr := TextureRect.new()
		tr.texture = at
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.custom_minimum_size = Vector2(ICON, ICON)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(tr)
		hb.add_child(cell)
		icons.append(tr)
	root.add_child(panel)
	panel.visible = false


func open() -> void:
	is_open = true
	opened_count += 1
	panel.reset_size()
	var vp := Vector2(480, 270)
	if is_inside_tree():
		vp = get_viewport().get_visible_rect().size
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	# below the top-left HUD (minimap / HP / objective line end at y 62) and above the dialogue box
	panel.position = Vector2(roundf((vp.x - sz.x) * 0.5), TOP_Y)
	panel.visible = true
	panel.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	if OS.has_feature("web"):
		print("story: wardrobe open")


func close() -> void:
	if not is_open:
		return
	is_open = false
	if _tween:
		_tween.kill()
	panel.visible = false
	panel.modulate.a = 0.0
	if OS.has_feature("web"):
		print("story: wardrobe closed")
