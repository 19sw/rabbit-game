extends Node
## Autoload "ViewFit" (启动画面 v1 fix): makes the 480x270 pixel view always cover the whole window/canvas.
## With stretch mode canvas_items + scale_mode integer, a window that is not an exact multiple of 480x270 (e.g. a
## 1280x720 browser window on a Retina screen = 2560x1440 canvas pixels -> 5x = 2400x1350) was left with dark bars.
## Here the base size is widened/heightened to window / scale, so the picture still uses the same whole-number scale
## (crisp pixels) but fills the window; at most (scale - 1) pixels of remainder can stay uncovered.

const BASE := Vector2i(480, 270)


func _ready() -> void:
	get_tree().root.size_changed.connect(fit)
	fit()


func fit() -> void:
	var root := get_tree().root
	var win := root.size
	if win.x <= 0 or win.y <= 0:
		return
	var s := maxi(1, mini(win.x / BASE.x, win.y / BASE.y))
	var want := Vector2i(maxi(BASE.x, win.x / s), maxi(BASE.y, win.y / s))
	if root.content_scale_size != want:
		root.content_scale_size = want
