class_name CombatFx
extends Node2D
## World-space combat effects: attack arcs (刀光/掌风), hit sparks, the red "!" over enemies whose wind-up has
## locked, and the gold "反击!" popup. Uses the effect sheets from pixel2d (assets/fx/fx.json + PNGs, copied by
## tools/sync_assets.py) when they exist; otherwise draws simple placeholder shapes, so the game never depends on art.

const FX_JSON := "res://assets/fx/fx.json"
const DIRS := ["down", "left", "right", "up"]

var effects := {}              # name -> {frames: SpriteFrames, anchor, directions}
var art := false               # true when the effect art was loaded
var spawned := {}              # name -> count (for tests / screenshots)
var _drawn: Array = []         # placeholder shapes: {kind, pos, dir, t, life, color, r}
var _alerts := {}              # fighter -> Node2D


func _ready() -> void:
	z_index = 20
	_load_art()


func _load_art() -> void:
	if not FileAccess.file_exists(FX_JSON):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(FX_JSON))
	if typeof(meta) != TYPE_DICTIONARY or not meta.has("effects"):
		push_warning("CombatFx: cannot read " + FX_JSON)
		return
	for name in meta["effects"]:
		var e: Dictionary = meta["effects"][name]
		var png := "res://assets/fx/" + String(e["file"])
		if not ResourceLoader.exists(png):
			continue
		var tex: Texture2D = load(png)
		var fs: Array = e.get("frame_size", [32, 32])
		var dirs = e.get("directions", null)
		var rows: Array = dirs if typeof(dirs) == TYPE_ARRAY else [""]
		var sf := SpriteFrames.new()
		sf.remove_animation("default")
		for r in rows.size():
			var key: String = "fx" if rows[r] == "" else String(rows[r])
			sf.add_animation(key)
			sf.set_animation_speed(key, float(e.get("fps", 20)))
			sf.set_animation_loop(key, bool(e.get("loop", false)))
			for i in int(e.get("count", 1)):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * int(fs[0]), r * int(fs[1]), int(fs[0]), int(fs[1]))
				sf.add_frame(key, at)
		effects[name] = {"frames": sf, "anchor": e.get("anchor", [0, 0]), "directions": typeof(dirs) == TYPE_ARRAY,
			"loop": bool(e.get("loop", false)), "count": int(e.get("count", 1)), "fps": float(e.get("fps", 20))}
	art = not effects.is_empty()


func _note(name: String) -> void:
	spawned[name] = spawned.get(name, 0) + 1


func _sprite(name: String, dir: String, ref: Vector2) -> AnimatedSprite2D:
	var e: Dictionary = effects[name]
	var s := AnimatedSprite2D.new()
	s.centered = false
	s.sprite_frames = e["frames"]
	var anim: String = dir if e["directions"] else "fx"
	var anchor: Array = e["anchor"][dir] if e["directions"] else e["anchor"]
	s.position = (ref - Vector2(anchor[0], anchor[1])).round()
	add_child(s)
	s.play(anim)
	if not e["loop"]:
		s.animation_finished.connect(s.queue_free)
	return s


## Attack arc. `body` = feet of the attacker; the art anchors on the body centre (centre of the 32x32 frame).
func slash(feet: Vector2, aim: Vector2, stage: int, counter: bool) -> void:
	var dir := CharSheet.dir_from_vector(aim, "down")
	var name := ("slash" if stage == 1 else "slash2") + ("_counter" if counter else "")
	_note(name)
	if effects.has(name):
		_sprite(name, dir, feet + Vector2(0, -15))
		return
	_drawn.append({"kind": "arc", "pos": feet + Vector2(0, -12), "dir": aim, "t": 0.0, "life": 0.14,
		"color": Color(1.0, 0.85, 0.3) if counter else Color(0.85, 0.95, 1.0), "r": 26.0 if stage == 1 else 32.0})


func spark(at: Vector2) -> void:
	_note("hit_spark")
	if effects.has("hit_spark"):
		_sprite("hit_spark", "", at)
		return
	_drawn.append({"kind": "spark", "pos": at, "dir": Vector2.ZERO, "t": 0.0, "life": 0.12, "color": Color(1, 0.95, 0.6), "r": 7.0})


## Gold "反击!" floating up from `at` (art) - returns false when there is no art (the HUD shows text instead).
func counter_popup(at: Vector2) -> bool:
	_note("counter_text")
	if not effects.has("counter_text"):
		return false
	var s := _sprite("counter_text", "", at)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", s.position.y - 12.0, 0.6)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.25).set_delay(0.35)
	tw.tween_callback(s.queue_free)
	return true


## Shows / hides the red "!" over a fighter (called every frame by Combat).
func set_alert(f: Node2D, on: bool) -> void:
	var has := _alerts.has(f) and is_instance_valid(_alerts[f])
	if on and not has:
		_note("alert")
		var n: Node2D
		if effects.has("alert"):
			n = _sprite("alert", "", Vector2.ZERO)
		else:
			n = _DrawnAlert.new()
			add_child(n)
		_alerts[f] = n
	if on:
		var n: Node2D = _alerts[f]
		var head: Vector2 = f.global_position + Vector2(0, -33)
		if n is AnimatedSprite2D:
			var a: Array = effects["alert"]["anchor"]
			n.position = (head - Vector2(a[0], a[1])).round()
		else:
			n.position = head.round()
	elif has:
		_alerts[f].queue_free()
		_alerts.erase(f)


func alert_visible(f: Node2D) -> bool:
	return _alerts.has(f) and is_instance_valid(_alerts[f])


func _process(delta: float) -> void:
	if _drawn.is_empty():
		return
	for d in _drawn:
		d["t"] += delta
	_drawn = _drawn.filter(func(d): return d["t"] < d["life"])
	queue_redraw()


func _draw() -> void:
	for d in _drawn:
		var k: float = d["t"] / d["life"]
		var c: Color = d["color"]
		c.a = 1.0 - k
		if d["kind"] == "arc":
			var base: float = (d["dir"] as Vector2).angle()
			draw_arc(d["pos"], d["r"] * (0.8 + 0.2 * k), base - 1.0, base + 1.0, 10, c, 3.0)
			draw_arc(d["pos"], d["r"] * (0.6 + 0.2 * k), base - 0.7, base + 0.7, 8, Color(1, 1, 1, c.a * 0.6), 1.0)
		else:
			var r: float = d["r"] * (0.6 + 0.6 * k)
			var p: Vector2 = d["pos"]
			draw_line(p - Vector2(r, 0), p + Vector2(r, 0), c, 2.0)
			draw_line(p - Vector2(0, r), p + Vector2(0, r), c, 2.0)
			draw_line(p - Vector2(r, r) * 0.6, p + Vector2(r, r) * 0.6, c, 1.0)
			draw_line(p - Vector2(r, -r) * 0.6, p + Vector2(r, -r) * 0.6, c, 1.0)


class _DrawnAlert:
	extends Node2D

	func _draw() -> void:
		draw_rect(Rect2(-2, -14, 4, 9), Color(0.95, 0.15, 0.1))
		draw_rect(Rect2(-2, -3, 4, 3), Color(0.95, 0.15, 0.1))
		draw_rect(Rect2(-3, -15, 6, 16), Color(0.2, 0.02, 0.02), false, 1.0)
