class_name Bounty
extends Node
## 第④步第一批 · 武道：江湖悬赏 (plan section 二). Rules / numbers: data/jianghu.json (rules, bounties, patrol); fighting numbers:
## cards/weasel.tres (黄鼠狼: flees at half HP), cards/wolf_bounty.tres (狼山贼, the prologue wolf's look and AI, 60 / 8),
## cards/tiger.tres (黑虎: enrages at half HP - intervals x0.7, pounces).
##   order      three main bounties, one after the other: the first is posted on day first_day (2) at post_hour (08:00);
##              after a turn-in the next is posted the next calendar day at 08:00 (ready_day). Once the three are turned
##              in, a 巡山 (2 狼山贼, 15 文, no 名望) is posted every interval_days (2) days from the next day's 08:00
##              (editions); an edition nobody took is replaced by the next one.
##   board      at most one 悬赏 at a time: 接榜 -> the villains stand at their place (red ring on the ground, red dots on the
##              minimap); 放弃 any time, no penalty (the bounty stays on the board); 交榜 after the win pays the coins and
##              the 名望 once (cut at the cap) and writes the 门派簿 entry.
##   fight      walking into a villain's aggro_range plays its line (the first time the longer intro), then they all
##              come. No regen while they are engaged (Combat.in_combat), no E, no saving. Walking leash_range away from
##              their place: they go back and heal. HP at or under lose_fraction (20 %) of max: lost - HP refilled, back
##              at the bounty's retreat point, the villains back at their place with full HP, nothing taken. All knocked
##              out: won (they are gone), the turn-in waits at the board.
## The villains are pooled Fighters (role "bandit") created once and hidden; present ones join Combat.fighters.

var main: Node
var jh: Jianghu
var defs: Array = []                 # the three main bounties (jianghu.json "bounties")
var patrol_def: Dictionary = {}
var main_done := 0                   # main bounties turned in (saved)
var ready_day := -1                  # post day (DayNight.day_index(post_hour)) of the next main bounty; -1 = day first_day (saved)
var patrol_from := -1                # post day of the first 巡山 edition; -1 = not open yet (saved)
var patrol_taken := -1               # last 巡山 edition taken (saved)
var patrols_done := 0                # 巡山 turned in (saved)
var fame_points := 0                 # 名望 given (cut at the cap) (saved)
var losses := 0                      # fights lost (saved, statistics)
var active: Dictionary = {}          # {} or {type: main|patrol, index, edition, state: accepted|won, intro: bool} (saved)
var paid: Array = []                 # every turn-in {coins, fame} (tests)
var pools: Dictionary = {}           # def id -> Array[Fighter]
var villains: Array = []             # the Fighters standing now
var marker: Node2D
var _last_offer := ""
var _fight_on := false
var _armed := true


func _init() -> void:
	name = "Bounty"


func setup(m: Node, hub: Jianghu) -> void:
	main = m
	jh = hub
	defs = jh.data.get("bounties", [])
	patrol_def = jh.data.get("patrol", {})
	CharSheet.alias("weasel", "fox")
	CharSheet.alias("tiger", "boar")
	for d in defs + [patrol_def]:
		var list: Array = []
		var i := 0
		for e in d.get("enemies", []):
			var f := Fighter.new()
			main.world.add_child(f)
			var pos := Jianghu._vec(e["pos"])
			f.setup_fighter({"id": String(e.get("sprite", "wolf")), "title": String(e.get("title", "")), "name": String(e.get("name", "")),
				"x": pos.x, "y": pos.y, "dir": String(e.get("dir", "down"))}, String(e["card"]), "bandit", main.combat)
			f.name = "Bounty_%s_%d" % [String(d.get("id", "")), i]
			if not CharSheet.has_own_art(f.id):
				f.sprite.self_modulate = Color(1.0, 0.8, 0.45) if f.id == "weasel" else (Color(0.85, 0.55, 0.3) if f.id == "tiger" else Color.WHITE)
			f.knocked_out.connect(_on_knocked_out)
			f.enraged.connect(_on_enraged)
			f.fled.connect(_on_fled)
			_hide_fighter(f)
			list.append(f)
			i += 1
		pools[String(d.get("id", ""))] = list
	marker = MarkerRing.new()
	marker.name = "BountyMarker"
	marker.visible = false
	main.add_child(marker)
	main.move_child(marker, main.world.get_index())     # on the ground, under every character


func _hide_fighter(f: Fighter) -> void:
	var c: Combat = main.combat
	if c.fighters.has(f):
		c.fighters.erase(f)
	if c.hud != null and c.hud.plates.has(f):
		c.hud.plates[f]["panel"].visible = false
	f.reset_home(true)
	f.visible = false
	f.collision_layer = 0


# ------------------------------------------------------------------ what is on the board
func first_ready() -> int:
	return ready_day if ready_day >= 0 else maxi(jh.s3.anchor_day, 0) + int(Jianghu.rules().get("first_day", 2)) - 1


func patrol_interval() -> int:
	return maxi(1, int(Jianghu.rules().get("patrol", {}).get("interval_days", 2)))


## Post day of 巡山 edition k.
func edition_post(k: int) -> int:
	return patrol_from + k * patrol_interval()


func edition_now() -> int:
	if patrol_from < 0 or jh.post_day() < patrol_from:
		return -1
	return (jh.post_day() - patrol_from) / patrol_interval()


func next_patrol_post() -> int:
	if patrol_from < 0:
		return jh.cal_day() + 1
	return edition_post(edition_now() + 1) if edition_now() >= 0 else patrol_from


## What the board offers (when nothing is taken): {} / {type: main, index} / {type: patrol, edition}.
func offer() -> Dictionary:
	if main_done < defs.size():
		if jh.post_day() >= first_ready():
			return {"type": "main", "index": main_done}
		return {}
	var k := edition_now()
	if k >= 0 and k > patrol_taken:
		return {"type": "patrol", "edition": k}
	return {}


func current_def() -> Dictionary:
	if active.is_empty():
		return {}
	return defs[int(active["index"])] if String(active["type"]) == "main" else patrol_def


func active_name() -> String:
	return String(current_def().get("name", ""))


func reward_coins() -> int:
	if String(active.get("type", "")) == "patrol":
		return int(Jianghu.rules().get("patrol", {}).get("coins", 15))
	return int(current_def().get("coins", 0))


func reward_fame() -> int:
	if String(active.get("type", "")) == "patrol":
		return int(Jianghu.rules().get("patrol", {}).get("fame", 0))
	return int(current_def().get("fame", 0))


# ------------------------------------------------------------------ board actions (return the line to show)
func accept() -> String:
	if not active.is_empty():
		return jh.ui("bounty_slot_full")
	var off := offer()
	if off.is_empty():
		return ""
	if String(off["type"]) == "main":
		active = {"type": "main", "index": int(off["index"]), "edition": -1, "state": "accepted", "intro": false}
	else:
		patrol_taken = int(off["edition"])
		active = {"type": "patrol", "index": -1, "edition": int(off["edition"]), "state": "accepted", "intro": false}
	if OS.has_feature("web"):
		print("bounty: accepted %s" % active_name())
	jh.request_save("bounty")
	return jh.ui("bounty_accepted") % [active_name(), String(current_def().get("place", ""))]


func abandon() -> String:
	if active.is_empty():
		return ""
	var nm := active_name()
	if String(active["type"]) == "patrol" and patrol_taken == int(active["edition"]):
		patrol_taken = int(active["edition"]) - 1      # still on the board while its edition lasts
	active = {}
	_set_present(false)
	jh.request_save("bounty")
	return jh.ui("bounty_abandoned") % nm


## Pays a won bounty once; the next one is posted the next calendar day at 08:00.
func turn_in() -> String:
	if active.is_empty() or String(active["state"]) != "won":
		return ""
	var coins := reward_coins()
	var want := reward_fame()
	var fame := jh.s3.grant("fame", want)
	fame_points += fame
	jh.sample.add_coins(coins)
	paid.append({"coins": coins, "fame": fame, "type": String(active["type"])})
	if String(active["type"]) == "main":
		main_done += 1
		ready_day = jh.cal_day() + 1
		if main_done >= defs.size() and patrol_from < 0:
			patrol_from = jh.cal_day() + 1
	else:
		patrols_done += 1
	active = {}
	if OS.has_feature("web"):
		print("bounty: paid %d" % coins)
	jh.request_save("bounty")
	var fame_part := ""
	if want > 0:
		fame_part = jh.ui("bounty_paid_fame") % fame if fame > 0 else jh.ui("bounty_paid_fame_full")
	return jh.ui("bounty_paid") % [coins, fame_part]


# ------------------------------------------------------------------ the villains
func _pool() -> Array:
	return pools.get(String(current_def().get("id", "")), [])


func _set_present(on: bool) -> void:
	var c: Combat = main.combat
	if on:
		villains = _pool()
		for f in villains:
			f.reset_home(true)
			if not c.fighters.has(f):
				c.fighters.append(f)
	else:
		for list in pools.values():
			for f in list:
				if f.visible or c.fighters.has(f):
					_hide_fighter(f)
		villains = []
	_fight_on = false


func engage_all() -> void:
	for f in villains:
		if f.visible and f.state == "idle":
			f.engage(0.6)
	_fight_on = true


func lose_line() -> int:
	var p: Player = main.player
	return int(floor(p.stats.max_hp * float(Jianghu.rules().get("lose_fraction", 0.2))))


## Combat.after_hit: a villain's blow landed. True when it ended the fight (lost: the player is refilled at once).
func on_player_hit(f: Fighter) -> bool:
	if not villains.has(f):
		return false
	if main.player.hp <= lose_line():
		_lose()
		return true
	return false


func _physics_process(_delta: float) -> void:
	if main == null:
		return
	if not jh.active():
		if not villains.is_empty():
			_set_present(false)
		marker.visible = false
		return
	var want := not active.is_empty() and String(active["state"]) == "accepted"
	if want and villains.is_empty():
		_set_present(true)
	elif not want and not villains.is_empty():
		_set_present(false)
	_update_marker()
	var key := str(offer())
	if key != _last_offer:
		if _last_offer != "" and active.is_empty() and not offer().is_empty():
			jh.toast(jh.ui("toast_new_bounty"))
		_last_offer = key
	if villains.is_empty():
		return
	var c: Combat = main.combat
	var p: Player = main.player
	var engaged: bool = villains.any(func(f): return f.engaged)
	if engaged:
		if p.hp <= lose_line() and not c.player_dead:
			_lose()
			return
		# leash: the player is leash_range away from every villain's place -> they all walk back and heal
		var near_home := INF
		for f in villains:
			near_home = minf(near_home, f.home.distance_to(p.global_position))
		var leash: float = villains[0].stats.leash_range
		if leash > 0.0 and near_home > leash:
			for g in villains:
				if g.engaged:
					g.start_return()
			_fight_on = false
			_armed = false
		return
	# after giving up the chase they only come again once the player has stepped away and walks back in
	if not _armed:
		_armed = villains.all(func(f): return f.global_position.distance_to(p.global_position) > f.stats.aggro_range + 24.0)
		if not _armed:
			return
	var story: Story = main.story
	if story.busy or story._modal_open() or c.story_hold or c.player_dead or c.spar_state != "none" or c.bout_session \
			or main.interiors.transitioning or c.trial_active:
		return
	for f in villains:
		if f.visible and f.state == "idle" and f.global_position.distance_to(p.global_position) <= f.stats.aggro_range:
			var sc: Dictionary = current_def().get("scenes", {})
			var first := not bool(active.get("intro", false))
			active["intro"] = true
			for g in villains:
				g.face_towards(p.global_position)
			story.play(String(sc.get("intro" if first else "again", "")))
			return


func _lose() -> void:
	var c: Combat = main.combat
	var p: Player = main.player
	losses += 1
	_fight_on = false
	_armed = true
	for f in villains:
		f.reset_home(true)
	c.hitstop_left = 0.0
	p.full_heal()
	p.reset_combat_state()
	p.global_position = Jianghu._vec(current_def().get("retreat", [p.global_position.x, p.global_position.y]))
	p.velocity = Vector2.ZERO
	p.facing = "down"
	p.sprite.play("idle_down")
	c.hud.fade_out(jh.ui("toast_lost"), 0.15)
	get_tree().create_timer(0.5, false).timeout.connect(func(): c.hud.fade_in(0.4))
	jh.toast(jh.ui("toast_lost"))
	if OS.has_feature("web"):
		print("bounty: lost")
	var sc := String(current_def().get("scenes", {}).get("lose", ""))
	if sc != "":
		main.story.play(sc)


func _on_knocked_out(f: Fighter) -> void:
	if not villains.has(f) or active.is_empty() or String(active["state"]) != "accepted":
		return
	if not villains.all(func(v): return v.state == "gone"):
		return
	active["state"] = "won"
	_fight_on = false
	jh.toast(jh.ui("toast_bounty_won"))
	if OS.has_feature("web"):
		print("bounty: won %s" % active_name())
	var sc := String(current_def().get("scenes", {}).get("win", ""))
	_set_present(false)
	if sc != "":
		main.story.play(sc)
	jh.request_save("bounty")


func _on_enraged(f: Fighter) -> void:
	main.combat.hud.show_banner(jh.ui("toast_rage"), jh.ui("toast_rage_sub"), 1.4)
	jh.say_bubble(jh.ui("rage_bubble"), f, 1.8, 1.9)     # after the banner (never under it)


func _on_fled(f: Fighter) -> void:
	jh.say_bubble(jh.ui("flee_bubble"), f, 1.4)


func _update_marker() -> void:
	var on := not villains.is_empty() and villains.any(func(f): return f.visible and f.state == "idle")
	marker.visible = on
	if on:
		var c := Vector2.ZERO
		for f in villains:
			c += f.home
		marker.position = c / float(villains.size())


func marks() -> Array:
	var out := []
	for f in villains:
		if f.visible and f.state not in ["down", "gone"]:
			out.append({"point": f.global_position, "color": Color(0.95, 0.15, 0.12)})
	return out


func task_lines() -> Array:
	if active.is_empty():
		return []
	if String(active["state"]) == "won":
		return [jh.ui("hud_bounty_won") % active_name()]
	return [jh.ui("hud_bounty") % [active_name(), String(current_def().get("place", ""))]]


# ------------------------------------------------------------------ 门派簿
func book_entries() -> Array:
	# one line for all of them (修复 v1: the 门派簿 must fit the 480 x 270 screen when everything is done)
	if main_done <= 0:
		return []
	var names := []
	for i in mini(main_done, defs.size()):
		names.append(String(defs[i].get("book", "")))
	var line := jh.book("bounty_entry") % jh.book("bounty_entry_sep").join(names)
	if patrols_done > 0:
		line += jh.book("joiner") + String(patrol_def.get("book", "巡山 %d 回")) % patrols_done
	return [line]


func book_line() -> String:
	if not active.is_empty():
		var n := int(active["index"]) + 1 if String(active["type"]) == "main" else main_done
		return jh.book("bounty_won" if String(active["state"]) == "won" else "bounty_doing") % [n, active_name()]
	if main_done >= defs.size():
		return jh.book("patrol_line") % patrols_done
	var s := jh.book("bounty_line") % main_done
	if offer().is_empty():
		s += jh.book("bounty_next") % jh.day_no(first_ready())
	return s


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"main_done": 0, "ready_day": -1, "patrol_from": -1, "patrol_taken": -1, "patrols_done": 0, "fame": 0, "losses": 0,
		"active": {"type": "", "index": -1, "edition": -1, "state": "", "intro": false}}


func capture() -> Dictionary:
	var a := {"type": "", "index": -1, "edition": -1, "state": "", "intro": false}
	if not active.is_empty():
		a = {"type": String(active["type"]), "index": int(active["index"]), "edition": int(active["edition"]),
			"state": String(active["state"]), "intro": bool(active["intro"])}
	return {"main_done": main_done, "ready_day": ready_day, "patrol_from": patrol_from, "patrol_taken": patrol_taken,
		"patrols_done": patrols_done, "fame": fame_points, "losses": losses, "active": a}


func restore(d: Dictionary) -> void:
	main_done = int(d["main_done"])
	ready_day = int(d["ready_day"])
	patrol_from = int(d["patrol_from"])
	patrol_taken = int(d["patrol_taken"])
	patrols_done = int(d["patrols_done"])
	fame_points = int(d["fame"])
	losses = int(d["losses"])
	var a: Dictionary = d["active"]
	active = {} if String(a["type"]) == "" else {"type": String(a["type"]), "index": int(a["index"]), "edition": int(a["edition"]),
		"state": String(a["state"]), "intro": bool(a["intro"])}
	_set_present(false)
	_last_offer = ""


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing jianghu.bounty"
	for k in ["main_done", "ready_day", "patrol_from", "patrol_taken", "patrols_done", "fame", "losses"]:
		if not SaveGame._type_ok(d.get(k), "num"):
			return "bad jianghu.bounty." + k
	for k in ["main_done", "patrols_done", "fame", "losses"]:
		if float(d[k]) < 0.0:
			return "bad jianghu.bounty." + k
	if int(d["main_done"]) > 3:
		return "bad jianghu.bounty.main_done"
	var a = d.get("active")
	if typeof(a) != TYPE_DICTIONARY:
		return "bad jianghu.bounty.active"
	if not (String(a.get("type", "?")) in ["", "main", "patrol"]) or not (String(a.get("state", "?")) in ["", "accepted", "won"]):
		return "bad jianghu.bounty.active"
	if not SaveGame._type_ok(a.get("index"), "num") or not SaveGame._type_ok(a.get("edition"), "num") or not (a.get("intro") is bool):
		return "bad jianghu.bounty.active"
	if String(a["type"]) == "main" and (int(a["index"]) < 0 or int(a["index"]) > 2):
		return "bad jianghu.bounty.active.index"
	if (String(a["type"]) == "") != (String(a["state"]) == ""):
		return "bad jianghu.bounty.active.state"
	return ""


## The red ring on the ground where the accepted bounty's villains wait (+ a small bobbing "!" flag).
class MarkerRing extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var k := 0.5 + 0.5 * sin(_t * 4.0)
		draw_arc(Vector2.ZERO, 30.0 + 3.0 * k, 0.0, TAU, 40, Color(0.95, 0.15, 0.12, 0.55 + 0.3 * k), 2.0)
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.95, 0.15, 0.12, 0.25), 1.0)
