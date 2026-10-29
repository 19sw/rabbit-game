class_name PlumTrial
extends Node
## 两条路小样 v1 · 梅花桩试炼 (plan section 3). All numbers: cards/trial_plum.tres (TrialCard, 配置资产).
## States: idle -> intro (the yard closes, "开始！", the clock waits) -> running -> result -> idle.
##   - 12 poles light one at a time; standing on the lit one (foot inside step_radius of its step point) marks it done
##     and lights the next; the last one finishes the run.
##   - 2 wooden dummies turn (two opposite arms, arm_length from the foot); an arm over the rabbit's feet is a hit through
##     Player.take_damage (8, stun) - so the dodge's i-frames (and the short protection after a hit) let him through.
##   - the clock: time_limit -> 超时 (fail). HP down to fail_hp_fraction -> 这次失败, HP refilled. Esc page: 放弃试炼.
##   - finished: medal by time (gold / silver / bronze lines), rewards via Sample.reward_trial (first time per tier coins
##     + 名望, afterwards the repeat reward).
##   - while it runs Combat.trial_active is on: counts as combat (no regen), E does nothing, the yard is closed with the
##     spar arena walls, doors are blocked.
## Art: assets/sample/trial/ (plum_pole.png, dummy_spin.png, trial_sign.png) and ui/medals.png; drawn stand-ins otherwise.

signal started
signal finished(result: String, seconds: float, info: Dictionary)   # result: gold|silver|bronze|timeout|knocked|abandoned
signal pole_stepped(index: int)

const CARD := "res://cards/trial_plum.tres"
const POLE_FRAME := Vector2(32, 32)
const POLE_STEP_IN_FRAME := Vector2(16, 20)     # the step point inside a pole frame
const DUMMY_FRAME := Vector2(96, 128)
const DUMMY_FOOT_IN_FRAME := Vector2(48, 82)
const DUMMY_POST := Rect2(-5, -8, 10, 8)        # post collider around the foot
const SIGN_FOOT_IN_FRAME := Vector2(24, 45)
const SIGN_RECT := Rect2(-16, -5, 32, 6)

var main: Node
var sample: Sample
var card: TrialCard
var enabled := false
var state := "idle"
var current := 0                 # index of the lit pole
var elapsed := 0.0
var intro_left := 0.0
var result_left := 0.0
var last_result := ""
var last_seconds := 0.0
var last_info: Dictionary = {}
var hits := 0                    # dummy hits this run
var runs := 0                    # finished runs with a medal (saved)
var best_time := 0.0             # best finishing time (0 = none; saved)
var results: Array[String] = []  # every run's result (tests)
var angles: PackedFloat32Array = PackedFloat32Array()

var pole_layer: Node2D
var poles: Array[Sprite2D] = []
var pole_tex: Texture2D
var dummies: Array[Node2D] = []
var dummy_tex: Texture2D
var dummy_shapes: Array[CollisionShape2D] = []
var board: Node2D
var board_shape: CollisionShape2D
var board_pos := Vector2.ZERO
var ui_layer: CanvasLayer
var hud_panel: PanelContainer
var hud_poles: Label
var hud_time: Label
var hud_lines: Label
var result_panel: PanelContainer
var result_title: Label
var result_sub: Label
var result_reward: Label
var result_medal: TextureRect
var medal_tex: Texture2D
var _lit_t := 0.0


func _init() -> void:
	name = "PlumTrial"


func setup(m: Node, s: Sample) -> void:
	main = m
	sample = s
	card = load(CARD)
	angles.resize(card.dummy_points.size())
	for i in angles.size():
		angles[i] = deg_to_rad(card.dummy_start_degrees[i] if i < card.dummy_start_degrees.size() else 0.0)
	var sd: Dictionary = s.data.get("trial_sign", {})
	board_pos = Vector2(sd.get("pos", [1110, 1120])[0], sd.get("pos", [1110, 1120])[1])
	pole_tex = Sample.art("trial/plum_pole.png")
	dummy_tex = Sample.art("trial/dummy_spin.png")
	medal_tex = Sample.art("ui/medals.png")
	_build_poles()
	_build_dummies()
	_build_board()
	_build_ui()
	set_enabled(false)


# ------------------------------------------------------------------ building
func _build_poles() -> void:
	pole_layer = Node2D.new()
	pole_layer.name = "TrialPoles"
	main.add_child(pole_layer)
	main.move_child(pole_layer, main.world.get_index())    # on the ground: under every character
	for i in card.pole_points.size():
		var s := Sprite2D.new()
		s.name = "Pole%d" % i
		s.centered = false
		s.position = (card.pole_points[i] - POLE_STEP_IN_FRAME).round()
		if pole_tex != null:
			s.texture = pole_tex
			s.region_enabled = true
		else:
			s.texture = _stand_in_pole()
		pole_layer.add_child(s)
		poles.append(s)
	_paint_poles()


func _stand_in_pole() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(8, 30):
		for x in range(10, 23):
			if Vector2(x, y).distance_to(Vector2(16, 20)) <= 7.0:
				img.set_pixel(x, y, Color("8a5a34"))
	return ImageTexture.create_from_image(img)


func _build_dummies() -> void:
	for i in card.dummy_points.size():
		var foot := card.dummy_points[i]
		var d: Node2D
		if dummy_tex != null:
			var s := Sprite2D.new()
			s.texture = dummy_tex
			s.centered = false
			s.region_enabled = true
			s.offset = -DUMMY_FOOT_IN_FRAME
			d = s
		else:
			d = DummyStandIn.new()
			(d as DummyStandIn).trial = self
			(d as DummyStandIn).index = i
		d.name = "TrialDummy%d" % i
		d.position = foot
		d.set_meta("type", "trial_dummy")
		main.world.add_child(d)
		dummies.append(d)
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = DUMMY_POST.size
		cs.shape = sh
		cs.position = foot + DUMMY_POST.get_center()
		cs.set_meta("kind", "trial_dummy")
		main.solids.add_child(cs)
		dummy_shapes.append(cs)
	_paint_dummies()


func _build_board() -> void:
	var t := Sample.art("trial/trial_sign.png")
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.offset = -SIGN_FOOT_IN_FRAME
		board = s
	else:
		board = BoardStandIn.new()
	board.name = "TrialSign"
	board.position = board_pos
	board.set_meta("type", "trial_sign")
	main.world.add_child(board)
	board_shape = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = SIGN_RECT.size
	board_shape.shape = sh
	board_shape.position = board_pos + SIGN_RECT.get_center()
	board_shape.set_meta("kind", "trial_sign")
	main.solids.add_child(board_shape)


func _ui_panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	return p


func _ui_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.05))
	l.add_theme_constant_override("outline_size", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "TrialUI"
	ui_layer.layer = 12
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ui_layer.add_child(root)
	# running: big clock + pole count at the top centre, the medal lines under it
	hud_panel = _ui_panel(Color(0.10, 0.07, 0.07, 0.82), Color(0.95, 0.78, 0.42))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_poles = _ui_label("", 11, Color(1.0, 0.9, 0.6))
	hud_time = _ui_label("", 13, Color(1.0, 1.0, 0.92))
	row.add_child(hud_poles)
	row.add_child(hud_time)
	col.add_child(row)
	hud_lines = _ui_label("", 8, Color(0.92, 0.84, 0.66))
	col.add_child(hud_lines)
	hud_panel.add_child(col)
	hud_panel.visible = false
	root.add_child(hud_panel)
	# result: medal + title + time + rewards, in the middle
	result_panel = _ui_panel(Color(0.12, 0.08, 0.08, 0.94), Color(0.95, 0.78, 0.42))
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 2)
	rc.alignment = BoxContainer.ALIGNMENT_CENTER
	rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_medal = TextureRect.new()
	result_medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result_medal.custom_minimum_size = Vector2(32, 32)
	result_medal.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	result_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc.add_child(result_medal)
	result_title = _ui_label("", 14, Color(1.0, 0.86, 0.45))
	result_sub = _ui_label("", 10, Color(1.0, 0.96, 0.88))
	result_reward = _ui_label("", 10, Color(1.0, 0.85, 0.5))
	rc.add_child(result_title)
	rc.add_child(result_sub)
	rc.add_child(result_reward)
	rc.add_child(_ui_label(sample.ui("trial_close"), 8, Color(0.8, 0.72, 0.6)))
	result_panel.add_child(rc)
	result_panel.visible = false
	root.add_child(result_panel)


# ------------------------------------------------------------------ enabling (after the prologue)
func set_enabled(on: bool) -> void:
	enabled = on
	pole_layer.visible = on
	board.visible = on
	board_shape.set_deferred("disabled", not on)
	for d in dummies:
		d.visible = on
	for cs in dummy_shapes:
		cs.set_deferred("disabled", not on)


func board_point() -> Vector2:
	return board_pos


## E at the board is offered (not while a run is on, not before the prologue ends).
func board_usable() -> bool:
	return enabled and state == "idle"


func step_point(i: int) -> Vector2:
	return card.pole_points[i]


func arm_segments(i: int) -> Array:
	var foot := card.dummy_points[i]
	var dir := Vector2.from_angle(angles[i]) * card.arm_length
	return [[foot, foot + dir], [foot, foot - dir]]


# ------------------------------------------------------------------ the run
func begin() -> void:
	if not enabled or state != "idle":
		return
	var p: Player = main.player
	var c: Combat = main.combat
	state = "intro"
	current = 0
	elapsed = 0.0
	hits = 0
	intro_left = card.intro_seconds
	c.trial_active = true
	p.full_heal()
	p.reset_combat_state()
	p.velocity = Vector2.ZERO
	c.close_yard()
	if not c.arena_rect.grow(-8).has_point(p.global_position):
		p.global_position = board_pos + Vector2(0, -16)
	main.pause_menu.set_abandon_action(sample.ui("abandon"), abandon)
	_paint_poles()
	_show_hud(true)
	c.hud.show_banner(sample.ui("trial_go"), "", card.intro_seconds)
	if OS.has_feature("web"):
		print("trial: start")
	started.emit()


func _physics_process(delta: float) -> void:
	if main == null or not enabled:
		return
	var c: Combat = main.combat
	if c.story_hold:
		return
	_lit_t += delta
	if state == "intro" or state == "running":
		for i in angles.size():
			var w := deg_to_rad(card.dummy_turn_degrees[i] if i < card.dummy_turn_degrees.size() else 90.0)
			angles[i] = fposmod(angles[i] + w * delta, TAU)
	_paint_dummies()
	_paint_poles()
	match state:
		"intro":
			main.player.input_enabled = false
			intro_left -= delta
			if intro_left <= 0.0:
				state = "running"
				main.player.input_enabled = true
		"running":
			if c.frozen:
				return
			elapsed += delta
			_check_dummies()
			if state != "running":
				return
			var p: Player = main.player
			if p.global_position.distance_to(card.pole_points[current]) <= card.step_radius:
				current += 1
				pole_stepped.emit(current - 1)
				if OS.has_feature("web"):
					print("trial: pole %d" % current)
				if current >= card.pole_points.size():
					_finish(_medal_result(elapsed))
					return
			if elapsed >= card.time_limit:
				elapsed = card.time_limit
				_finish("timeout")
		"result":
			result_left -= delta
			if result_left <= 0.0:
				close_result()
	_update_hud()


func _check_dummies() -> void:
	var p: Player = main.player
	var foot := p.global_position
	for i in card.dummy_points.size():
		for seg in arm_segments(i):
			var q := Geometry2D.get_closest_point_to_segment(foot, seg[0], seg[1])
			if q.distance_to(foot) > card.arm_half_width + card.player_hit_radius:
				continue
			if q.distance_to(card.dummy_points[i]) < 4.0:
				continue      # the post itself is solid; only the arms hit
			if p.take_damage(card.dummy_damage, card.dummy_points[i]):
				hits += 1
				p.stun_left = card.dummy_stun
				var ch: CombatHud = main.combat.hud
				ch.damage_number(foot + Vector2(0, -30), card.dummy_damage, "hurt")
				main.combat.fx.spark(foot + Vector2(0, -12))
				main.combat.hitstop(main.combat.rules.hitstop)
				if p.hp <= int(floor(p.stats.max_hp * card.fail_hp_fraction)):
					_finish("knocked")
				return


func _medal_result(seconds: float) -> String:
	var t := Economy.best_tier(seconds, card)
	return t if t != "" else "timeout"


## Ends the run (result = gold|silver|bronze|timeout|knocked|abandoned): rewards, the result panel, the yard opens.
func _finish(result: String) -> void:
	if state != "running" and state != "intro":
		return
	var c: Combat = main.combat
	var p: Player = main.player
	last_result = result
	last_seconds = elapsed
	results.append(result)
	c.trial_active = false
	c.open_yard()
	main.pause_menu.set_abandon_action("", Callable())
	p.input_enabled = true
	var info := {}
	if result in Economy.TIERS:
		runs += 1
		best_time = elapsed if best_time <= 0.0 else minf(best_time, elapsed)
		info = sample.reward_trial(elapsed)
	if result == "knocked":
		p.full_heal()
		p.reset_combat_state()
	last_info = info
	_show_hud(false)
	if result == "abandoned":
		state = "idle"
		sample.toast_text(sample.ui("trial_abandoned"))
	else:
		state = "result"
		result_left = card.result_seconds
		_show_result(result, info)
	if OS.has_feature("web"):
		print("trial: %s %.1f" % [result, elapsed])
	sample.request_save("trial")
	finished.emit(result, elapsed, info)


func abandon() -> void:
	if state == "running" or state == "intro":
		_finish("abandoned")


func close_result() -> void:
	if state != "result":
		return
	result_panel.visible = false
	state = "idle"


func _input(event: InputEvent) -> void:
	if state == "result" and event.is_action_pressed("interact", false):
		close_result()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ drawing
func _paint_poles() -> void:
	var frame := 1 + int(_lit_t * 8.0) % 4
	for i in poles.size():
		var s := poles[i]
		var f := 0
		if state == "running" or state == "intro":
			f = 5 if i < current else (frame if i == current else 0)
		if s.region_enabled:
			s.region_rect = Rect2(Vector2(f * POLE_FRAME.x, 0), POLE_FRAME)
		else:
			s.modulate = Color(0.6, 0.6, 0.6) if f == 5 else (Color(1.6, 1.4, 0.7) if f > 0 else Color.WHITE)
		s.set_meta("frame", f)


func pole_frame(i: int) -> int:
	return int(poles[i].get_meta("frame", 0))


func _paint_dummies() -> void:
	for i in dummies.size():
		var d := dummies[i]
		if d is Sprite2D:
			var k := int(round(rad_to_deg(angles[i]) / 22.5)) % 16
			(d as Sprite2D).region_rect = Rect2(Vector2(posmod(k, 16) * DUMMY_FRAME.x, 0), DUMMY_FRAME)
		else:
			d.queue_redraw()


func _show_hud(on: bool) -> void:
	hud_panel.visible = on
	if on:
		hud_lines.text = sample.ui("trial_lines") % [int(card.gold_seconds), int(card.silver_seconds), int(card.bronze_seconds)]
		_update_hud()


func _update_hud() -> void:
	if not hud_panel.visible:
		return
	hud_poles.text = sample.ui("trial_poles") % [current, card.pole_points.size()]
	hud_time.text = sample.ui("trial_time") % elapsed
	var left := card.time_limit - elapsed
	hud_time.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if left <= 10.0 else Color(1.0, 1.0, 0.92))
	var vp := hud_panel.get_viewport_rect().size
	var sz := hud_panel.get_combined_minimum_size()
	hud_panel.size = sz
	# under the toast line (which sits under the HP / coin row): toasts during a run stay readable
	var hud: Hud = main.hud
	hud_panel.position = Vector2(roundf((vp.x - sz.x) * 0.5), hud.toast.position.y + hud.toast.size.y + 2.0)


func _show_result(result: String, info: Dictionary) -> void:
	var medal_frame: int = {"gold": 0, "silver": 1, "bronze": 2}.get(result, 3)
	if medal_tex != null:
		var at := AtlasTexture.new()
		at.atlas = medal_tex
		at.region = Rect2(medal_frame * 32, 0, 32, 32)
		result_medal.texture = at
	if result in Economy.TIERS:
		result_title.text = sample.ui("trial_medal") % sample.ui("tier_" + result)
		result_sub.text = sample.ui("trial_time") % last_seconds
		var parts := []
		if int(info.get("coins", 0)) > 0:
			parts.append(sample.ui("trial_reward_coins") % int(info["coins"]))
		if int(info.get("fame", 0)) > 0:
			parts.append(sample.ui("trial_reward_fame") % int(info["fame"]))
		result_reward.text = "  ".join(parts) if not parts.is_empty() else sample.ui("trial_no_reward")
	else:
		result_title.text = sample.ui("trial_timeout") if result == "timeout" else sample.ui("trial_knocked")
		result_sub.text = sample.ui("trial_fail_sub")
		result_reward.text = sample.ui("trial_time") % last_seconds
	result_panel.visible = true
	await get_tree().process_frame
	var vp := result_panel.get_viewport_rect().size
	var sz := result_panel.get_combined_minimum_size()
	result_panel.size = sz
	result_panel.position = ((vp - sz) * 0.5 + Vector2(0, -20)).round()


## Stand-ins while the art is missing.
class DummyStandIn extends Node2D:
	var trial: PlumTrial
	var index := 0

	func _draw() -> void:
		draw_rect(Rect2(-3, -30, 6, 30), Color("6b4426"))
		var dir := Vector2.from_angle(trial.angles[index]) * trial.card.arm_length
		draw_line(-dir, dir, Color(0.2, 0.1, 0.05, 0.35), 8.0)
		draw_line(Vector2(0, -30) - dir, Vector2(0, -30) + dir, Color("8a5a34"), 3.0)


class BoardStandIn extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-2, -30, 4, 30), Color("5a3a22"))
		draw_rect(Rect2(-16, -40, 32, 18), Color("c9a46a"))
