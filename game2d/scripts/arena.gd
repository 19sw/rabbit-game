class_name Arena
extends Node
## 第③步 · 村口比武大会 (plan section 一). Rules / numbers: data/economy.json "arena"; opponents' fighting numbers:
## cards/monkey|yak|snake.tres; lines / places: data/step3.json.
##   calendar   every interval_days (3) days, on day 3, 6, 9 ... (Step3.day_number) from open_hour (12:00) until
##              close_hour (18:00, not included) the notice board takes entries; edition N = day / 3. Otherwise the board
##              (and the 门派簿) say "下届比武大会：第 N 天午时".
##   entry      fee (10 文); short -> "还差 N 文", nothing taken. One entry per edition: after a win, a loss or 弃权 the
##              board says 本届已参加.
##   session    Combat.bout_session on (counts as combat: no regen, no E, no doors, no saving); the ring's own collider
##              off, the arena walls round the fight rectangle; per round: intro (banner "第 2 轮：铁牛帮 牦牛" + the
##              opponent's line over his head, nobody moves) -> fight (Combat.start_bout: 20 % of max HP loses) -> result
##              panel -> next round with +between_heal HP (cap max HP) / out / champion. Esc page: 弃权 (Q).
##              Leaving the ring: HP refilled, standing at the ring's exit, the ring is solid again, a save.
##   rewards    first title first_win_coins + first_win_fame 名望, later win_coins + win_fame (cut at fame_max);
##              the 门派簿 lists "比武大会·夺魁（第 N 届）".
##   difficulty 补充 v1.1: at the board 报名 asks 普通 / 困难 (this edition only, same fee). 困难 = the rounds' card_hard
##              cards (same HP / damage, super armour, denser attacks, the monkey strikes twice, the yak charges more
##              often, the snake sidesteps 60 %) and economy.json arena.hard rewards (first hard title / later ones,
##              cut at the same cap); the 门派簿 lists "比武大会·夺魁·困难（第 N 届）". "First" counts per difficulty.
## Art: assets/step3/ (ring, notice board; manifest.json places them); drawn stand-ins until it lands.

const INTRO_SECONDS := 2.4
const RESULT_SECONDS := 2.6
const CHAMPION_SECONDS := 4.0

var main: Node
var s3: Step3
var ring_outer := Rect2()
var fight_rect := Rect2()
var player_start := Vector2.ZERO
var enemy_start := Vector2.ZERO
var exit_pos := Vector2.ZERO
var board_pos := Vector2.ZERO
var board_radius := 34.0
var ring_layer: Node2D            # ground level (under every character)
var ring_node: Node2D
var ring_front: Node2D            # front ropes / posts over the fighters (only with the real art)
var ring_shapes: Array[CollisionShape2D] = []
var board: Node2D
var board_shape: CollisionShape2D
var opponents: Array[Fighter] = []   # round order
var round_defs: Array = []           # economy.json arena.rounds
var state := "idle"                  # idle | intro | fight | result | between
var round := 0                       # 0-based round index while a session runs
var intro_left := 0.0
var entered_edition := 0             # last edition signed up for (saved)
var wins: Array = []                 # editions won in 普通 (saved)
var hard_wins: Array = []            # editions won in 困难 (saved)
var difficulty := "normal"           # of the edition entered last (saved): normal | hard
var cards_normal: Array[EnemyStats] = []
var cards_hard: Array[EnemyStats] = []
var fame_points := 0                 # 名望 given by titles (saved; cut at the cap)
var last_outcome := ""               # champion | out | forfeit (tests)
var last_reward: Dictionary = {}     # {coins, fame} of the last title (tests)
var sessions := 0                    # tournaments started (tests)
var shortfalls: Array[int] = []      # every "还差 N 文" (tests)
var _signup_pending := false
var _hidden_on := false


func _init() -> void:
	name = "Arena"


func setup(m: Node, hub: Step3) -> void:
	main = m
	s3 = hub
	round_defs = Economy.arena().get("rounds", [])
	var rd: Dictionary = s3.data.get("ring", {})
	ring_outer = _rect(rd.get("outer", [640, 1668, 288, 132]))
	fight_rect = _rect(rd.get("fight", [664, 1692, 240, 92]))
	player_start = _vec(rd.get("player_start", [712, 1744]))
	enemy_start = _vec(rd.get("enemy_start", [856, 1744]))
	exit_pos = _vec(rd.get("exit", [784, 1820]))
	var bd: Dictionary = s3.data.get("board", {})
	board_pos = _vec(bd.get("pos", [968, 1716]))
	board_radius = float(bd.get("radius", 34))
	_apply_manifest()
	_build_ring()
	_build_board()
	_build_opponents()
	set_present(false)


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The art manifest (assets/step3/manifest.json "exterior") decides where the ring and the board stand.
func _apply_manifest() -> void:
	var ring := Step3.manifest("exterior", "ring")
	if not ring.is_empty():
		var cols: Array = ring.get("collision_map_px", [])
		if not cols.is_empty():
			ring_outer = _rect(cols[0])
		if ring.has("floor_rect_map_px"):
			fight_rect = _rect(ring["floor_rect_map_px"])
		var st: Dictionary = ring.get("start_map_px", {})
		if st.has("player"):
			player_start = _vec(st["player"])
		if st.has("opponent"):
			enemy_start = _vec(st["opponent"])
		if ring.has("exit_point_map_px"):
			exit_pos = _vec(ring["exit_point_map_px"])
	var b := Step3.manifest("exterior", "notice_board")
	if not b.is_empty() and b.has("interact_point_map_px"):
		board_pos = _vec(b["interact_point_map_px"])


# ------------------------------------------------------------------ building
var ropes_back: Node2D            # the ropes: only during a match (real art)
var ropes_front: Node2D
var hidden_objects: Array = []    # map sprites / colliders the ring replaces (manifest hide_objects)
var _board_tex: Texture2D
var _board_frame := Vector2(48, 56)


func _sprite(tex: Texture2D, at: Vector2, sort_y := -1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	if sort_y < 0.0:
		s.position = at
	else:
		s.position = Vector2(at.x, sort_y)
		s.offset = Vector2(0, at.y - sort_y)
	return s


func _build_ring() -> void:
	ring_layer = Node2D.new()
	ring_layer.name = "ArenaRingLayer"
	main.add_child(ring_layer)
	main.move_child(ring_layer, main.world.get_index())    # on the ground: under every character
	var man := Step3.manifest("exterior", "ring")
	var layers: Dictionary = man.get("layers", {})
	var base_tex := Step3.art(String(layers.get("base", {}).get("file", ""))) if not layers.is_empty() else null
	var rects: Array = []
	if base_tex != null:
		var at := _vec(man.get("map_px", [ring_outer.position.x, ring_outer.position.y]))
		var sort_y := float(man.get("sort_y", ring_outer.end.y))
		ring_node = _sprite(base_tex, at)
		var rb := Step3.art(String(layers.get("ropes_back", {}).get("file", "")))
		if rb != null:
			ropes_back = _sprite(rb, at)
			ropes_back.name = "ArenaRopesBack"
			ring_layer.add_child(ropes_back)
		var ft := Step3.art(String(layers.get("front", {}).get("file", "")))
		if ft != null:
			ring_front = _sprite(ft, at, sort_y)
			ring_front.name = "ArenaRingFront"
			ring_front.set_meta("type", "arena_ring_front")
			main.world.add_child(ring_front)
		var rf := Step3.art(String(layers.get("ropes_front", {}).get("file", "")))
		if rf != null:
			ropes_front = _sprite(rf, at, sort_y)
			ropes_front.name = "ArenaRopesFront"
			main.world.add_child(ropes_front)
		rects = man.get("collision_map_px", [])
		for h in man.get("hide_objects", []):
			_find_hidden(h)
	else:
		var st := RingStandIn.new()
		st.outer = ring_outer
		st.fight = fight_rect
		ring_node = st
	ring_node.name = "ArenaRing"
	ring_node.set_meta("type", "arena_ring")
	ring_layer.add_child(ring_node)
	if ropes_back != null:
		ring_layer.move_child(ropes_back, -1)
	# outside a tournament the ring is solid (a raised platform); during one its own shapes are off and the arena walls
	# round the fight rectangle (the deck's floor) hold both fighters in
	if rects.is_empty():
		rects = [[ring_outer.position.x, ring_outer.position.y, ring_outer.size.x, ring_outer.size.y]]
	for r in rects:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(float(r[2]), float(r[3]))
		cs.shape = sh
		cs.position = Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
		cs.set_meta("kind", "arena_ring")
		cs.disabled = true
		main.solids.add_child(cs)
		ring_shapes.append(cs)
	_show_ropes(false)


## A map object (sprite + its collider) standing where the ring goes (PM ruling: hidden while the ring is there).
func _find_hidden(h: Dictionary) -> void:
	var o: Dictionary = h.get("game2d_object_at_time_of_writing", {})
	var c: Dictionary = h.get("game2d_collider_at_time_of_writing", {})
	var entry := {"sprite": null, "shape": null, "rect": []}
	for spr in main.world.get_children():
		if spr is Sprite2D and spr.texture != null and spr.texture.resource_path.ends_with("/" + String(o.get("tex", "?"))) \
				and absf(spr.position.x - float(o.get("x", -1))) < 0.5 and absf(spr.position.y - float(o.get("sort_y", -1))) < 0.5:
			entry["sprite"] = spr
	var cr: Array = c.get("rect", [])
	if cr.size() == 4:
		var centre := Vector2(float(cr[0]) + float(cr[2]) * 0.5, float(cr[1]) + float(cr[3]) * 0.5)
		for cs in main.solids.get_children():
			if cs is CollisionShape2D and cs.position.distance_to(centre) < 0.5 and String(cs.get_meta("kind", "")) == String(c.get("kind", "")):
				entry["shape"] = cs
		entry["rect"] = cr
	hidden_objects.append(entry)


func _apply_hidden(on: bool) -> void:
	var gone := []
	for e in hidden_objects:
		if e["sprite"] != null:
			e["sprite"].visible = not on
		if e["shape"] != null:
			e["shape"].set_deferred("disabled", on)
		if on and not (e["rect"] as Array).is_empty():
			gone.append(e["rect"])
	# the fighters' path grid without those two trees (they are gone while the ring stands)
	var c: Combat = main.combat
	var cols: Array = main.data["colliders"].filter(func(cd): return not gone.any(func(rr): return cd["rect"] == rr))
	var extra: Array = []
	for n in main.npcs:
		if not (n is Fighter) and n.visible:
			extra.append(Rect2(n.global_position + Vector2(-7, -6), Vector2(14, 7)))
	c.nav.build(cols, extra, main.map_size)


func _show_ropes(on: bool) -> void:
	if ropes_back != null:
		ropes_back.visible = on
	if ropes_front != null:
		ropes_front.visible = on


func _build_board() -> void:
	var man := Step3.manifest("exterior", "notice_board")
	var tex := Step3.art(String(man.get("file", ""))) if not man.is_empty() else null
	var col := Rect2(-16, -5, 32, 6)
	var foot := board_pos
	if tex != null:
		_board_tex = tex
		var fs: Array = man.get("frame_size", [48, 56])
		_board_frame = Vector2(float(fs[0]), float(fs[1]))
		var at := _vec(man.get("map_px", [board_pos.x - 24, board_pos.y - 64]))
		var fa: Array = man.get("foot_anchor_in_frame", [24, 53])
		foot = at + Vector2(float(fa[0]), float(fa[1]))
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(Vector2.ZERO, _board_frame)
		s.offset = -Vector2(float(fa[0]), float(fa[1]))
		board = s
		if man.has("collision_map_px"):
			var c: Array = man["collision_map_px"]
			col = Rect2(float(c[0]) - foot.x, float(c[1]) - foot.y, float(c[2]), float(c[3]))
		board_radius = float(s3.data.get("board", {}).get("radius_art", 26))
	else:
		board = BoardStandIn.new()
	board.name = "ArenaBoard"
	board.position = foot
	board.set_meta("type", "arena_board")
	main.world.add_child(board)
	board_shape = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = col.size
	board_shape.shape = sh
	board_shape.position = foot + col.get_center()
	board_shape.set_meta("kind", "arena_board")
	board_shape.disabled = true
	main.solids.add_child(board_shape)


## The board's picture: the 报名 banner hangs while entries are open.
func _paint_board() -> void:
	if _board_tex == null or not (board is Sprite2D):
		return
	var f := 1 if can_enter() else 0
	(board as Sprite2D).region_rect = Rect2(Vector2(f * _board_frame.x, 0), _board_frame)
	board.set_meta("frame", f)


func _build_opponents() -> void:
	var od: Dictionary = s3.data.get("opponents", {})
	for rdef in round_defs:
		var id := String(rdef["id"])
		var o: Dictionary = od.get(id, {})
		CharSheet.alias(id, String(o.get("stand_in", "boar")))
		var f := Fighter.new()
		main.world.add_child(f)
		f.setup_fighter({"id": id, "title": String(o.get("title", rdef.get("name", id))),
			"name": String(o.get("name", "%s · %s" % [rdef.get("school", ""), rdef.get("name", id)])),
			"x": enemy_start.x, "y": enemy_start.y, "dir": "left"}, String(rdef["card"]), "spar", main.combat)
		f.name = "Arena_" + id
		cards_normal.append(f.stats)
		cards_hard.append(load("res://cards/%s.tres" % String(rdef.get("card_hard", rdef["card"]))))
		if not CharSheet.has_own_art(id) and o.has("tint"):
			var t: Array = o["tint"]
			f.sprite.self_modulate = Color(float(t[0]), float(t[1]), float(t[2]))
		_hide(f)
		opponents.append(f)


func _hide(f: Fighter) -> void:
	f.reset_home(true)
	f.visible = false
	f.collision_layer = 0


## After the prologue (继续逛逛) the ring and the board stand at the village; before it nothing of them exists.
func set_present(on: bool) -> void:
	ring_layer.visible = on
	board.visible = on
	if ring_front != null:
		ring_front.visible = on
	if not hidden_objects.is_empty() and on != _hidden_on:
		_hidden_on = on
		_apply_hidden(on)
	board_shape.set_deferred("disabled", not on)
	for cs in ring_shapes:
		cs.set_deferred("disabled", not on or state != "idle")


func _physics_process(delta: float) -> void:
	if main == null:
		return
	var want := s3.active()
	if want != board.visible:
		set_present(want)
	if want:
		_paint_board()
	if state == "intro":
		if main.combat.story_hold:
			return
		main.player.input_enabled = false
		main.player.velocity = Vector2.ZERO
		intro_left -= delta
		if intro_left <= 0.0:
			_start_fight()


# ------------------------------------------------------------------ calendar
func interval() -> int:
	return maxi(1, Economy.arena_int("interval_days"))


func is_event_day(n: int) -> bool:
	return n >= 1 and n % interval() == 0


func edition_of(n: int) -> int:
	return n / interval()


## The edition of today when today is a tournament day, else 0.
func edition_today() -> int:
	var n := s3.day_number()
	return edition_of(n) if is_event_day(n) else 0


func open_now() -> bool:
	var h: float = main.daynight.hour
	return is_event_day(s3.day_number()) and h >= Economy.arena_float("open_hour") and h < Economy.arena_float("close_hour")


## The board takes an entry right now (open, not entered this edition, no tournament running).
func can_enter() -> bool:
	return open_now() and entered_edition < edition_today() and state == "idle"


## The day of the next tournament still to come for the player: today while it can still be entered (before or during
## the hours), else the next tournament day.
func next_day() -> int:
	var n := s3.day_number()
	if is_event_day(n) and main.daynight.hour < Economy.arena_float("close_hour") and entered_edition < edition_of(n):
		return n
	return (n / interval() + 1) * interval()


func book_line() -> String:
	if can_enter():
		return s3.book("open_arena") % s3.day_number()
	return s3.book("next_arena") % [next_day(), s3.day_number()]


func book_entries() -> Array:
	var out := []
	for pair in [[wins, "arena_win"], [hard_wins, "arena_win_hard"]]:
		var list: Array = pair[0]
		if list.is_empty():
			continue
		var parts := list.map(func(w): return str(int(w)))
		if parts.size() > 4:
			parts = ["…"] + parts.slice(parts.size() - 3)
		out.append(s3.book(String(pair[1])) % "、".join(parts))
	return out


# ------------------------------------------------------------------ the board
func board_point() -> Vector2:
	return board_pos


func interaction_target(p: Vector2, best_d: float) -> Dictionary:
	if state != "idle" or not board.visible:
		return {}
	var d := board_pos.distance_to(p)
	if d > board_radius or d >= best_d:
		return {}
	return {"kind": "step3", "id": "arena_board", "prompt": s3.ui("prompt_board"), "prompt_pos": board.position + Vector2(0, -58),
		"dist": d}


func poi_points() -> Array:
	return [board_pos, ring_outer.get_center()]


func board_scene() -> String:
	if can_enter():
		return "A-告示牌-报名"
	if open_now() and entered_edition >= edition_today():
		return "A-告示牌-已参加"
	return "A-告示牌-平时"


func open_board() -> void:
	main.story.play(board_scene())


## "do": "arena_signup" (inside the board scene): the fee, or the shortfall message.
func signup(token: int, diff := "normal") -> void:
	var story: Story = main.story
	if not can_enter():
		return
	var fee := Economy.arena_int("fee")
	var coins: int = s3.sample.coins
	if coins < fee:
		shortfalls.append(fee - coins)
		await story.dialogue.say({"kind": "提示", "text": s3.ui("not_enough") % (fee - coins)})
		if token != story._run_id:
			return
		await story._run_entries(story.scene("A-钱不够"), token)
		return
	s3.sample.add_coins(-fee, s3.ui("fee_paid") % fee)
	entered_edition = edition_today()
	difficulty = "hard" if diff == "hard" else "normal"
	_signup_pending = true


## The board scene has closed: the tournament starts.
func after_scene() -> void:
	if _signup_pending:
		_signup_pending = false
		begin()


# ------------------------------------------------------------------ the tournament
func begin() -> void:
	var c: Combat = main.combat
	var p: Player = main.player
	sessions += 1
	state = "between"
	round = 0
	last_outcome = ""
	c.bout_session = true
	for cs in ring_shapes:
		cs.disabled = true      # at once: he is placed on the deck this frame (a deferred change would push him off)
	_show_ropes(true)
	p.full_heal()
	p.reset_combat_state()
	main.pause_menu.set_abandon_action(s3.ui("forfeit"), forfeit)
	if OS.has_feature("web"):
		print("arena: start (edition %d)" % entered_edition)
	_round_intro()


func current() -> Fighter:
	return opponents[round] if round < opponents.size() else null


func opponent_data(i: int) -> Dictionary:
	var id := String(round_defs[i]["id"])
	return s3.data.get("opponents", {}).get(id, {})


func round_title(i: int) -> String:
	var rd: Dictionary = round_defs[i]
	return s3.ui("round_banner") % [i + 1, String(rd.get("school", "")), String(rd.get("name", ""))]


func _round_intro() -> void:
	var c: Combat = main.combat
	var p: Player = main.player
	var f := current()
	f.stats = cards_hard[round] if difficulty == "hard" else cards_normal[round]
	f.home = enemy_start
	f.home_dir = "left"
	f.reset_home(true)
	c.spar_state = "between"
	p.global_position = player_start
	p.velocity = Vector2.ZERO
	p.facing = "right"
	p.sprite.play("idle_right")
	p.input_enabled = false
	state = "intro"
	intro_left = INTRO_SECONDS
	c.hud.show_banner(round_title(round), s3.ui("hard_tag") if difficulty == "hard" else "", INTRO_SECONDS - 0.4)
	if OS.has_feature("web"):
		print("arena: round %d" % (round + 1))


## The opponent's line over his head during the intro.
func bubble() -> Dictionary:
	if state != "intro" or current() == null:
		return {}
	var f := current()
	return {"text": String(opponent_data(round).get("intro", "")), "pos": f.head_position(), "who": f.id}


func _start_fight() -> void:
	state = "fight"
	var p: Player = main.player
	if not fight_rect.has_point(p.global_position):
		p.global_position = player_start
	main.combat.start_bout(current(), fight_rect, self, Economy.arena_float("lose_fraction"))


## Combat: a round is decided. Pays the title (once) when the last round is won. Returns the result panel's texts.
func on_bout_result(win: bool) -> Dictionary:
	state = "result"
	var od := opponent_data(round)
	var who := String(od.get("title", ""))
	var last := round >= opponents.size() - 1
	if win and last:
		var info := _reward()
		var parts := [s3.ui("reward_coins") % int(info["coins"])]
		parts.append(s3.ui("reward_fame") % int(info["fame"]) if int(info["fame"]) > 0 else s3.ui("fame_full"))
		return {"title": s3.ui("champion_hard" if difficulty == "hard" else "champion"), "line": "%s：%s\n%s" % [who, String(od.get("lose", "")), "  ".join(parts)],
			"seconds": CHAMPION_SECONDS}
	if win:
		return {"title": s3.ui("round_win") % (round + 1),
			"line": "%s：%s\n%s" % [who, String(od.get("lose", "")), s3.ui("heal_next") % Economy.arena_int("between_heal")],
			"seconds": RESULT_SECONDS}
	return {"title": s3.ui("round_lose") % (round + 1), "line": "%s：%s" % [who, String(od.get("win", ""))],
		"seconds": RESULT_SECONDS}


## Combat: the result panel is gone.
func on_bout_closed(win: bool) -> void:
	var p: Player = main.player
	_hide(current())
	if win and round < opponents.size() - 1:
		p.hp = mini(p.hp + Economy.arena_int("between_heal"), p.stats.max_hp)
		round += 1
		state = "between"
		_round_intro()
	else:
		_end_session("champion" if win else "out")


func _reward() -> Dictionary:
	var hard := difficulty == "hard"
	var list := hard_wins if hard else wins
	var first := list.is_empty()
	var coins := Economy.arena_hard("first_win_coins" if first else "win_coins") if hard \
		else Economy.arena_int("first_win_coins" if first else "win_coins")
	var want := Economy.arena_hard("first_win_fame" if first else "win_fame") if hard \
		else Economy.arena_int("first_win_fame" if first else "win_fame")
	var fame := s3.grant("fame", want)
	fame_points += fame
	list.append(entered_edition)
	s3.sample.add_coins(coins)
	last_reward = {"coins": coins, "fame": fame, "first": first, "hard": hard}
	return last_reward


## Esc page: 弃权 (any time during the session). The edition counts as entered.
func forfeit() -> void:
	if state == "idle":
		return
	if state == "result" and main.combat.bout_last_win and round >= opponents.size() - 1:
		_end_session("champion")    # the title is already paid: leaving the result early is not a forfeit
		return
	_end_session("forfeit")


func _end_session(outcome: String) -> void:
	var c: Combat = main.combat
	var p: Player = main.player
	c.end_bout()
	c.bout_session = false
	for i in opponents.size():
		opponents[i].stats = cards_normal[i]
		_hide(opponents[i])
	state = "idle"
	last_outcome = outcome
	for cs in ring_shapes:
		cs.set_deferred("disabled", not board.visible)
	_show_ropes(false)
	p.full_heal()
	p.reset_combat_state()
	p.global_position = exit_pos
	p.velocity = Vector2.ZERO
	p.facing = "down"
	p.sprite.play("idle_down")
	p.input_enabled = true
	main.pause_menu.set_abandon_action("", Callable())
	if outcome == "out":
		s3.toast(s3.ui("out_refill"))
	elif outcome == "forfeit":
		s3.toast(s3.ui("forfeited"))
	if OS.has_feature("web"):
		print("arena: %s" % outcome)
	s3.request_save("arena")


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"entered_edition": 0, "wins": [], "fame": 0, "difficulty": "normal", "hard_wins": []}


func capture() -> Dictionary:
	return {"entered_edition": entered_edition, "wins": wins.duplicate(), "fame": fame_points, "difficulty": difficulty,
		"hard_wins": hard_wins.duplicate()}


func restore(d: Dictionary) -> void:
	entered_edition = int(d["entered_edition"])
	wins = (d["wins"] as Array).map(func(x): return int(x))
	hard_wins = (d["hard_wins"] as Array).map(func(x): return int(x))
	difficulty = String(d["difficulty"])
	fame_points = int(d["fame"])


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing step3.arena"
	for k in ["entered_edition", "fame"]:
		if not SaveGame._type_ok(d.get(k), "num") or float(d[k]) < 0.0:
			return "bad step3.arena." + k
	for k in ["wins", "hard_wins"]:
		if not (d.get(k) is Array):
			return "bad step3.arena." + k
		for w in d[k]:
			if not SaveGame._type_ok(w, "num"):
				return "bad step3.arena." + k
	if not (String(d.get("difficulty", "")) in ["normal", "hard"]):
		return "bad step3.arena.difficulty"
	return ""


## Stand-ins while the art is missing: a plank platform with four posts and red ropes; a notice board.
class RingStandIn extends Node2D:
	var outer := Rect2()
	var fight := Rect2()

	func _draw() -> void:
		var o := outer
		draw_rect(Rect2(o.position + Vector2(3, 5), o.size), Color(0.1, 0.06, 0.03, 0.3))
		draw_rect(o, Color("8a5a34"))
		draw_rect(o.grow(-4), Color("b98a55"))
		var y := o.position.y + 8.0
		while y < o.end.y - 6.0:
			draw_line(Vector2(o.position.x + 4, y), Vector2(o.end.x - 4, y), Color("a87a48"), 1.0)
			y += 8.0
		draw_rect(Rect2(o.position.x, o.end.y - 6, o.size.x, 6), Color("6b4426"))
		var f := fight.grow(6)
		var posts := [f.position, Vector2(f.end.x, f.position.y), Vector2(f.position.x, f.end.y), f.end]
		for rope_y in [-14.0, -8.0]:
			var pts := PackedVector2Array([f.position + Vector2(0, rope_y), Vector2(f.end.x, f.position.y + rope_y),
				f.end + Vector2(0, rope_y), Vector2(f.position.x, f.end.y + rope_y), f.position + Vector2(0, rope_y)])
			draw_polyline(pts, Color("c0392b"), 1.0)
		for pp in posts:
			draw_rect(Rect2(pp + Vector2(-2, -18), Vector2(4, 18)), Color("5a3a22"))
			draw_rect(Rect2(pp + Vector2(-3, -20), Vector2(6, 3)), Color("e0b040"))


class BoardStandIn extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-14, -30, 3, 30), Color("5a3a22"))
		draw_rect(Rect2(11, -30, 3, 30), Color("5a3a22"))
		draw_rect(Rect2(-18, -44, 36, 20), Color("e8d8b0"))
		draw_rect(Rect2(-18, -44, 36, 3), Color("b23a2a"))
		for i in 3:
			draw_line(Vector2(-12, -36 + i * 4), Vector2(12, -36 + i * 4), Color(0.3, 0.2, 0.1), 1.0)
