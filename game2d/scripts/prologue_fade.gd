class_name PrologueFade
extends CanvasLayer
## 武学与经营 · 第一批 (B) · 序章结尾的转场 (方案 第三点五节): the whole screen (world + HUD) fades to black, stays black
## while the guide's caption "序章 · 完" (layer 15, above us) fades in and out, then fades back in on the rabbit outside
## the hall. Layer 14: above the HUD (10 / 11), under the guide captions (15) and the dialogue (20). While it runs it
## counts as an open page (group modal_ui: the Esc page does not open) and Story is busy (nobody moves).

var is_open := false
var rect: ColorRect
var max_alpha := 0.0          # the darkest it got during the last transition (tests)


func _init() -> void:
	name = "PrologueFade"
	layer = 14
	add_to_group("modal_ui")
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.02, 0.02, 0.04, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)


func alpha() -> float:
	return rect.color.a if rect.visible else 0.0


## Tween the black to `a` in `secs` seconds (awaitable).
func fade_to(a: float, secs: float) -> void:
	rect.visible = true
	var tw := create_tween()
	tw.tween_property(rect, "color:a", a, maxf(0.01, secs)).set_trans(Tween.TRANS_SINE)
	await tw.finished
	max_alpha = maxf(max_alpha, rect.color.a)
	if a <= 0.0:
		rect.visible = false
