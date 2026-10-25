class_name Jianghu
extends Node
## 第④步第一批 (docs/design/第四步-第一批-悬赏与委托-方案-v1.md): the 江湖告示榜 at the village plaza, 悬赏 (scripts/bounty.gd)
## and 委托 (scripts/commission.gd). This node is the hub both use:
##   board      a new solid object (art: assets/step4a/props/bounty_board.png, a drawn stand-in until it lands); E opens
##              "看悬赏 / 看委托 / 离开" - the menus are scene entries built in code from the current state (accept, turn in,
##              abandon), played by the story like every other conversation (do: "jh", op: ...).
##   calendar   Step3's day numbers (day 1 = the day the prologue ended). Boards post at rules.post_hour (08:00):
##              post_day() = DayNight.day_index(post_hour) - the calendar day whose 08:00 has passed last.
##   texts      data/jianghu.json (rules, places, lines, ui, book); scenes / speakers join the story's tables.
##   hooks      Story asks talk_scene / interaction_target / interact / do_action / option_ok / poi_points / bubble;
##              Step3 adds our 名望 / 家业 points and 门派簿 lines; SaveGame stores capture() under "jianghu" (version 4).
##   HUD        "正在做的事" under the coin counter (never over the objective line, the toast moves under it, it fades while
##              a prompt / bubble is behind it); red minimap dots for the 悬赏, yellow ones for the 委托's next place.
## Nothing of it exists before the prologue has ended (Step3.active()) or in the sandbox of the older suites.

const DATA := "res://data/jianghu.json"
const ART := "res://assets/step4a/"

var main: Node
var story: Story
var sample: Sample
var s3: Step3
var data: Dictionary
var bounty: Bounty
var com: Commission
var seed := 20261024          # 委托 draw: seed + calendar day (saved; a new game gets a random one)
var board: Node2D
var board_shape: CollisionShape2D
var board_foot := Vector2.ZERO
var board_point := Vector2.ZERO
var board_radius := 22.0
var tasks_panel: PanelContainer
var tasks_label: Label
var toasts: Array[String] = []       # every toast asked for (tests)
var menus: Array[String] = []        # every board menu built (tests): "top" / "bounty" / "commission" / ...
var _board_tex: Texture2D
var _board_frame := Vector2(64, 64)
var _board_anchor := Vector2(32, 61)
var _bubble := {}                    # {text, node, left}

static var _data: Dictionary = {}


func _init() -> void:
	name = "Jianghu"


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Jianghu: cannot read " + DATA)
			parsed = {}
		_data = parsed
	return _data


static func rules() -> Dictionary:
	return load_data().get("rules", {})


static func crules() -> Dictionary:
	return rules().get("commissions", {})


## The numbers the Esc tips use (changing jianghu.json changes what the page says).
static func numbers() -> Dictionary:
	var d := load_data()
	var r := rules()
	var c := crules()
	var k: Dictionary = c.get("kinds", {})
	var b: Array = d.get("bounties", [])
	var out := {"first_day": int(r.get("first_day", 2)), "post_hour": int(r.get("post_hour", 8)),
		"lose_pct": int(round(float(r.get("lose_fraction", 0.2)) * 100.0)),
		"patrol_days": int(r.get("patrol", {}).get("interval_days", 2)), "patrol_coins": int(r.get("patrol", {}).get("coins", 15)),
		"per_day": int(c.get("per_day", 2)), "refresh_hour": int(c.get("refresh_hour", 8)), "estate_every": int(c.get("estate_every", 5)),
		"bonus_at": int(c.get("fame_bonus_at", 5)), "bonus_mult": str(c.get("fame_bonus_mult", 1.5)),
		"max_bounty": int(r.get("max_bounty", 1)), "max_commission": int(r.get("max_commission", 2))}
	for i in b.size():
		out["b%d_coins" % (i + 1)] = int(b[i].get("coins", 0))
		out["b%d_fame" % (i + 1)] = int(b[i].get("fame", 0))
	for id in k:
		out["c_" + String(id)] = int(k[id].get("reward", 0))
	return out


static func fill(text: String, vals: Dictionary) -> String:
	return text.format(vals) if "{" in text else text


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


func book(key: String) -> String:
	return String(data.get("book", {}).get(key, key))


static func art(file: String) -> Texture2D:
	return load(ART + file) if ResourceLoader.exists(ART + file) else null


static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Called by Story.setup before the dialogue is built: our scenes and speakers join the story's tables.
func merge_story_data(sd: Dictionary) -> void:
	data = load_data()
	var scenes: Dictionary = sd.get("scenes", {})
	for id in data.get("scenes", {}):
		scenes[id] = data["scenes"][id]
	scenes["J-告示榜"] = []
	var sp: Dictionary = sd.get("speakers", {})
	for id in data.get("speakers", {}):
		sp[id] = data["speakers"][id]


func setup(m: Node) -> void:
	main = m
	story = m.story
	sample = m.sample
	s3 = m.step3
	data = load_data()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed = rng.randi_range(1, 999999)
	_build_board()
	_build_tasks()
	bounty = Bounty.new()
	add_child(bounty)
	bounty.setup(m, self)
	com = Commission.new()
	add_child(com)
	com.setup(m, self)
	m.combat.after_hit = bounty.on_player_hit
	set_present(false)


## The game is past the prologue (and not the old suites' sandbox).
func active() -> bool:
	return s3 != null and s3.active()


# ------------------------------------------------------------------ calendar
func post_hour() -> float:
	return float(rules().get("post_hour", 8))


## The calendar day whose post_hour (08:00) has passed last (DayNight day index from that hour).
func post_day() -> int:
	return main.daynight.day_index(post_hour())


func cal_day() -> int:
	return main.daynight.day_index(0)


## Day number (Step3's calendar: day 1 = the prologue's last day) of a clock day index.
func day_no(idx: int) -> int:
	return idx - maxi(s3.anchor_day, 0) + 1


# ------------------------------------------------------------------ the board
func _build_board() -> void:
	var pl: Dictionary = data.get("places", {}).get("board", {})
	board_foot = _vec(pl.get("foot", [1300, 1740]))
	board_point = _vec(pl.get("interact", [1300, 1749]))
	board_radius = float(pl.get("radius", 22))
	var col: Array = pl.get("collision", [-26, -9, 52, 10])
	var tex := art("props/bounty_board.png")
	if tex != null:
		_board_tex = tex
		_board_frame = Vector2(tex.get_width() / 2.0, tex.get_height())
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(Vector2.ZERO, _board_frame)
		s.offset = -_board_anchor
		board = s
	else:
		board = BoardStandIn.new()
	board.name = "JianghuBoard"
	board.position = board_foot
	board.set_meta("type", "jianghu_board")
	main.world.add_child(board)
	board_shape = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(float(col[2]), float(col[3]))
	board_shape.shape = sh
	board_shape.position = board_foot + Vector2(float(col[0]) + float(col[2]) * 0.5, float(col[1]) + float(col[3]) * 0.5)
	board_shape.set_meta("kind", "jianghu_board")
	board_shape.disabled = true
	main.solids.add_child(board_shape)


## The board's collision rectangle (map px).
func board_rect() -> Rect2:
	var sh: RectangleShape2D = board_shape.shape
	return Rect2(board_shape.position - sh.size * 0.5, sh.size)


func set_present(on: bool) -> void:
	board.visible = on
	board_shape.set_deferred("disabled", not on)
	com.set_present(on)


## Frame 1 ("有新告示": red silk, a red seal) while something can be taken.
func _paint_board() -> void:
	var fresh := not bounty.offer().is_empty() and bounty.active.is_empty()
	fresh = fresh or com.offers.any(func(o): return String(o["state"]) == "open")
	board.set_meta("fresh", fresh)
	if _board_tex != null and board is Sprite2D:
		(board as Sprite2D).region_rect = Rect2(Vector2((1 if fresh else 0) * _board_frame.x, 0), _board_frame)
	elif board is BoardStandIn:
		(board as BoardStandIn).fresh = fresh
		board.queue_redraw()


func interaction_target(p: Vector2, best_d: float) -> Dictionary:
	if not active():
		return {}
	var out := {}
	var d := board_point.distance_to(p)
	if d <= board_radius and d < best_d:
		out = {"kind": "jianghu", "id": "board", "prompt": ui("prompt_board"), "prompt_pos": board_foot + Vector2(0, -66), "dist": d}
		best_d = d
	var t := com.interaction_target(p, best_d)
	if not t.is_empty():
		out = t
	return out


func interact(t: Dictionary) -> void:
	if String(t.get("id", "")) == "board":
		open_board()
	else:
		com.interact(t)


func open_board() -> void:
	story.data["scenes"]["J-告示榜"] = menu_top()
	story.play("J-告示榜")


func _line(text: String) -> Dictionary:
	return {"kind": "告示", "text": text}


func _opt(text: String, op: String, arg := -1, grey := false) -> Dictionary:
	var o := {"text": text, "then": [] if op == "" else [{"do": "jh", "op": op, "arg": arg}]}
	if grey:
		o["grey_unless"] = "jh_never"
	return o


func menu_top() -> Array:
	menus.append("top")
	return [_line(ui("board_title")), {"choice": [_opt(ui("opt_bounty"), "bounties"), _opt(ui("opt_commission"), "commissions"),
		_opt(ui("opt_leave"), "")]}]


func menu_bounties() -> Array:
	menus.append("bounty")
	var b := bounty
	var today := day_no(cal_day())
	if not b.active.is_empty():
		var def := b.current_def()
		if String(b.active["state"]) == "won":
			var fame := int(def.get("fame", 0)) if String(b.active["type"]) == "main" else int(rules().get("patrol", {}).get("fame", 0))
			var coins := b.reward_coins()
			return [_line(ui("bounty_won") % [b.active_name(), coins, ui("bounty_fame_part") % fame if fame > 0 else ""]),
				{"choice": [_opt(ui("opt_turnin_bounty"), "b_turnin"), _opt(ui("opt_back"), "top")]}]
		return [_line(ui("bounty_active") % [b.active_name(), String(def.get("place", ""))]),
			{"choice": [_opt(ui("opt_abandon_bounty"), "b_abandon"), _opt(ui("opt_back"), "top")]}]
	var off := b.offer()
	if off.is_empty():
		if b.main_done < b.defs.size():
			return [_line(ui("bounty_none_next") % [day_no(b.first_ready()), today]), {"choice": [_opt(ui("opt_back"), "top")]}]
		return [_line(ui("patrol_none_next") % [day_no(b.next_patrol_post()), today]), {"choice": [_opt(ui("opt_back"), "top")]}]
	if String(off["type"]) == "main":
		var d: Dictionary = b.defs[int(off["index"])]
		return [_line(ui("bounty_offer") % [int(off["index"]) + 1, String(d["name"]), String(d.get("place", "")), int(d.get("coins", 0)),
			int(d.get("fame", 0)), String(d.get("desc", ""))]),
			{"choice": [_opt(ui("opt_accept_bounty"), "b_accept"), _opt(ui("opt_back"), "top")]}]
	return [_line(ui("patrol_offer") % [int(rules().get("patrol", {}).get("coins", 15)), String(b.patrol_def.get("desc", "")),
		day_no(b.edition_post(int(off["edition"]) + 1))]),
		{"choice": [_opt(ui("opt_accept_bounty"), "b_accept"), _opt(ui("opt_back"), "top")]}]


func menu_commissions() -> Array:
	menus.append("commission")
	var c := com
	if c.offers.is_empty():
		return [_line(ui("commission_none")), {"choice": [_opt(ui("opt_back"), "top")]}]
	var lines := [ui("commission_head") + (ui("commission_bonus") % [s3.value("fame"), mult_text()] if c.bonus_on() else "")]
	var opts := []
	var taken := c.taken_count()
	for i in c.offers.size():
		var o: Dictionary = c.offers[i]
		var nm := c.kind_name(String(o["kind"]))
		var st := String(o["state"])
		var status := ui("commission_open")
		if st == "done":
			status = ui("commission_done")
			opts.append(_opt(ui("opt_c_done") % nm, "", i, true))
		elif st == "taken" and c.complete(o):
			status = ui("commission_ready")
			opts.append(_opt(ui("opt_c_turnin") % nm, "c_turnin", i))
		elif st == "taken":
			status = ui("commission_taken") % c.step_text(o)
			opts.append(_opt(ui("opt_c_abandon") % nm, "c_ask_abandon", i))
		else:
			var full := taken >= int(rules().get("max_commission", 2))
			opts.append(_opt((ui("opt_c_full") if full else ui("opt_c_accept")) % nm, "c_detail", i, full))
		lines.append(ui("commission_line") % [i + 1, nm, c.reward(String(o["kind"])), status])
	opts.append(_opt(ui("opt_leave"), ""))
	return [_line("\n".join(lines)), {"choice": opts}]


## The 名望 bonus multiplier as written on the board ("1.5"), from rules.commissions.fame_bonus_mult.
static func mult_text() -> String:
	var m := float(crules().get("fame_bonus_mult", 1.5))
	return str(int(m)) if is_equal_approx(m, floorf(m)) else String.num(m, 2).rstrip("0")


func menu_commission_detail(i: int) -> Array:
	menus.append("detail")
	var o: Dictionary = com.offers[i]
	var k := String(o["kind"])
	var kd: Dictionary = data.get("kinds", {}).get(k, {})
	return [_line(ui("commission_detail") % [String(kd.get("client", "")), com.kind_name(k), com.reward(k), String(kd.get("desc", ""))]),
		{"choice": [_opt(ui("opt_c_accept") % com.kind_name(k), "c_accept", i), _opt(ui("opt_back"), "commissions")]}]


func menu_abandon(i: int) -> Array:
	menus.append("abandon")
	var o: Dictionary = com.offers[i]
	return [_line(ui("abandon_question") % [com.kind_name(String(o["kind"])), com.step_text(o)]),
		{"choice": [_opt(ui("opt_confirm_abandon"), "c_abandon", i), _opt(ui("opt_keep"), "commissions")]}]


func handles(action: String) -> bool:
	return action == "jh"


## "do": "jh" entries (the board's menus, and the steps inside our scenes).
func do_action(e: Dictionary, token: int) -> void:
	var op := String(e.get("op", ""))
	var arg := int(e.get("arg", -1))
	match op:
		"top":
			await story._run_entries(menu_top(), token)
		"bounties":
			await story._run_entries(menu_bounties(), token)
		"commissions":
			await story._run_entries(menu_commissions(), token)
		"c_detail":
			await story._run_entries(menu_commission_detail(arg), token)
		"c_ask_abandon":
			await story._run_entries(menu_abandon(arg), token)
		"b_accept":
			var msg := bounty.accept()
			if msg != "":
				await _say(msg)
		"b_abandon":
			await _say(bounty.abandon())
		"b_turnin":
			var msg2 := bounty.turn_in()
			if msg2 != "":
				await _say(msg2)
		"b_engage":
			bounty.engage_all()
		"c_accept":
			var m3 := com.accept(arg)
			if m3 != "":
				await _say(m3)
		"c_abandon":
			await _say(com.abandon(arg))
		"c_turnin":
			var m4 := com.turn_in(arg)
			if m4 != "":
				await _say(m4)
		"c_step":
			com.step(String(e.get("cid", "")))


func _say(t: String) -> void:
	await story.dialogue.say(_line(t))


func option_ok(key: String) -> bool:
	return key != "jh_never"


# ------------------------------------------------------------------ talk (委托 steps, villagers after 名望 >= 5)
func talk_scene(npc_id: String) -> String:
	if not active():
		return ""
	var sc := com.talk_scene(npc_id)
	if sc != "":
		return sc
	var t: Dictionary = data.get("talk", {})
	var famous := s3.value("fame") >= int(crules().get("fame_bonus_at", 5))
	if famous and t.has(npc_id + "_fame"):
		return String(t[npc_id + "_fame"])
	if t.has(npc_id):
		return String(t[npc_id])
	return ""


func poi_points() -> Array:
	if not active():
		return []
	var out := [board_point]
	out.append_array(com.poi_points())
	return out


## A line over a character's head (`delay` s later - e.g. after a banner - for `seconds`).
func say_bubble(text: String, node: Node2D, seconds := 2.0, delay := 0.0) -> void:
	_bubble = {"text": text, "node": node, "left": seconds + delay, "show_from": seconds}


func bubble() -> Dictionary:
	if _bubble.is_empty() or not is_instance_valid(_bubble["node"]) or float(_bubble["left"]) > float(_bubble["show_from"]):
		return {}
	var n: Node2D = _bubble["node"]
	var pos := n.global_position + Vector2(0, -32)
	return {"text": String(_bubble["text"]), "pos": pos, "who": String(n.get("id")) if n.get("id") != null else ""}


func toast(t: String) -> void:
	toasts.append(t)
	s3.toast(t)


func request_save(reason: String) -> void:
	sample.request_save(reason)


# ------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if main == null:
		return
	if not _bubble.is_empty():
		_bubble["left"] = float(_bubble["left"]) - delta
		if float(_bubble["left"]) <= 0.0:
			_bubble = {}
	var want := active()
	if want != board.visible:
		set_present(want)
	if not want:
		tasks_panel.visible = false
		main.hud.minimap.set_marks([])
		return
	_paint_board()
	_update_tasks()
	var marks := bounty.marks()
	marks.append_array(com.marks())
	main.hud.minimap.set_marks(marks)


# ------------------------------------------------------------------ HUD: 正在做的事
func _build_tasks() -> void:
	var hud: Hud = main.hud
	tasks_panel = hud._panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	tasks_panel.name = "Tasks"
	tasks_label = hud._label("", 9, Color(1.0, 0.93, 0.78))
	tasks_label.add_theme_constant_override("line_spacing", -1)
	tasks_panel.add_child(tasks_label)
	tasks_panel.visible = false
	var root: Control = hud.get_child(0)
	root.add_child(tasks_panel)
	root.move_child(tasks_panel, hud.prompt.get_index())    # under the prompt, the bubble and the toast
	hud.tasks = tasks_panel


func task_lines() -> Array:
	var out := []
	out.append_array(bounty.task_lines())
	out.append_array(com.task_lines())
	return out


func _update_tasks() -> void:
	var lines := task_lines()
	var hud: Hud = main.hud
	if lines.is_empty() or not sample.coin_panel.visible:
		tasks_panel.visible = false
		tasks_label.text = ""
		return
	var text := "\n".join(lines)
	if tasks_label.text != text:
		tasks_label.text = text
		tasks_panel.size = Vector2.ZERO
	tasks_panel.visible = true
	tasks_panel.size = tasks_panel.get_combined_minimum_size()
	var coin: Control = sample.coin_panel
	var pos := Vector2(coin.position.x, coin.position.y + coin.size.y + 3.0)
	var r := Rect2(pos, tasks_panel.size)
	if hud.objective.visible and r.grow(1).intersects(hud.objective.get_global_rect()):
		pos.y = hud.objective.get_global_rect().end.y + 3.0
	var clock_r: Rect2 = hud.clock.get_global_rect()
	if Rect2(pos, tasks_panel.size).intersects(clock_r):
		pos.y = clock_r.end.y + 3.0
	tasks_panel.position = pos.round()
	var rect := tasks_panel.get_global_rect()
	# the toast goes under the list (Sample put it under the coin row this frame)
	hud.set_toast_top(maxf(hud.toast.position.y, roundf(rect.end.y + 3.0)))
	# a "按 E" prompt / bubble behind the list: the list fades, the prompt stays readable
	var covered := false
	for c in [hud.prompt, hud.bubble]:
		if c.visible and c.get_global_rect().intersects(rect):
			covered = true
	tasks_panel.modulate.a = 0.2 if covered else 1.0


# ------------------------------------------------------------------ 门派簿
func book_entries(track: String) -> Array:
	return bounty.book_entries() if track == "fame" else com.book_entries()


## One status line (the 门派簿 page must still fit the 480 x 270 screen with everything of step 3 on it).
func book_lines() -> Array:
	return [bounty.book_line() + book("joiner") + com.book_line()]


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"seed": 20261024, "bounty": Bounty.defaults(), "com": Commission.defaults()}


func capture() -> Dictionary:
	return {"seed": seed, "bounty": bounty.capture(), "com": com.capture()}


func restore(d: Dictionary) -> void:
	seed = int(d["seed"])
	bounty.restore(d["bounty"])
	com.restore(d["com"])


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing section jianghu"
	if not SaveGame._type_ok(d.get("seed"), "num"):
		return "bad jianghu.seed"
	var why := Bounty.validate(d.get("bounty"))
	if why != "":
		return why
	return Commission.validate(d.get("com"))


## Stand-in while the art is missing: two posts, a little roof, red paper (悬赏) left and yellow (委托) right.
class BoardStandIn extends Node2D:
	var fresh := false

	func _draw() -> void:
		draw_rect(Rect2(-28, -8, 56, 6), Color(0.1, 0.06, 0.03, 0.3))
		draw_rect(Rect2(-24, -46, 4, 46), Color("5a3a22"))
		draw_rect(Rect2(20, -46, 4, 46), Color("5a3a22"))
		draw_rect(Rect2(-30, -58, 60, 8), Color("3e4a6a"))
		draw_rect(Rect2(-26, -50, 52, 30), Color("c9a876"))
		draw_rect(Rect2(-23, -47, 21, 24), Color("b8392b"))
		draw_rect(Rect2(2, -47, 21, 24), Color("e8c860"))
		for i in 3:
			draw_line(Vector2(-20, -42 + i * 6), Vector2(-5, -42 + i * 6), Color(0.95, 0.85, 0.7), 1.0)
			draw_line(Vector2(5, -42 + i * 6), Vector2(20, -42 + i * 6), Color(0.35, 0.22, 0.1), 1.0)
		if fresh:
			draw_rect(Rect2(-26, -20, 52, 3), Color("d0302a"))
			draw_circle(Vector2(18, -26), 3.0, Color("d0302a"))
