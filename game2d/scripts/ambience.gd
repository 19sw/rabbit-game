class_name Ambience
extends Node2D
## Time-of-day mood: tint of the whole map (CanvasModulate), warm glows at lanterns (PointLight2D),
## plus a light screen grade (slight desaturation + warm vignette). Toggle with L.
##
## 颜色、灯笼亮度、时段曲线都在 data/tuning.json（说明.md 第 8 节）；这里只负责把当前时刻的数值应用到画面上。

var enabled := true
var modulate_node: CanvasModulate
var lights: Array[PointLight2D] = []
var grade_layer: CanvasLayer
var grade_mat: ShaderMaterial
var lamp_level := 0.0   # 0 = lanterns off (day) .. 1 = fully lit
var _t := 0.0


func build(light_points: Array) -> void:
	modulate_node = CanvasModulate.new()
	modulate_node.color = Color.WHITE
	add_child(modulate_node)
	var tex := _radial_texture()
	var i := 0
	for lp in light_points:
		var l := PointLight2D.new()
		var stone: bool = lp.get("kind", "") == "stone"
		var cfg: Dictionary = Tuning.data()["stone" if stone else "lantern"]
		l.texture = tex
		l.texture_scale = float(cfg["radius"]) * 2.0 / float(tex.get_width())
		l.color = Tuning.color(cfg["color"])
		l.energy = float(cfg["energy"])
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.global_position = Vector2(lp["x"], lp["y"])
		l.set_meta("base_energy", l.energy)
		l.set_meta("phase", float(i) * 1.7)
		l.name = "Light_%d" % i
		add_child(l)
		lights.append(l)
		i += 1
	grade_layer = CanvasLayer.new()
	grade_layer.layer = 5
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/grade.gdshader")
	rect.material = mat
	grade_mat = mat
	grade_layer.add_child(rect)
	add_child(grade_layer)
	set_enabled(true)


func _radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.55, 0.55, 0.55, 1), Color(0, 0, 0, 1)])
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func set_enabled(on: bool) -> void:
	enabled = on
	modulate_node.visible = on
	for l in lights:
		l.enabled = on
		l.visible = on
	grade_layer.visible = on


func toggle() -> void:
	set_enabled(not enabled)


## Applies the look of the current hour (from DayNight.look() / lamp_level()).
func apply_look(look: Dictionary, lamps: float) -> void:
	modulate_node.color = look["tint"]
	grade_mat.set_shader_parameter("desaturate", look["desaturate"])
	grade_mat.set_shader_parameter("vignette", look["vignette"])
	lamp_level = lamps


func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	for l in lights:
		var ph: float = l.get_meta("phase")
		var flicker := 1.0 + 0.06 * sin(_t * 7.3 + ph) + 0.04 * sin(_t * 12.9 + ph * 2.1)
		l.energy = float(l.get_meta("base_energy")) * flicker * lamp_level
		l.visible = lamp_level > 0.001
