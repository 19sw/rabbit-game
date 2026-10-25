class_name Commission
extends Node
## 第④步第一批 · 兴宗：接委托 (plan section 三). Rules / numbers: data/jianghu.json rules.commissions; places: places;
## texts: kinds / scenes / ui.
##   daily      offers belong to a calendar day: from refresh_hour (08:00) to midnight. The first frame of a new day's
##              08:00 draws per_day (2) kinds out of the six (those whose needs_repair is done - 送馒头 needs the
##              kitchen), from seed + calendar day only (RandomNumberGenerator seeded with "seed:day".hash()), so a test
##              (or a reload) gets the same two. At midnight the day's offers are void (taken but not turned in = gone,
##              no penalty); 00:00-08:00 the board has none. The offers and their progress are saved; a load on the same
##              day keeps them (nothing drawn twice, nothing paid twice: a turned-in offer is "done").
##   kinds      送馒头 小食摊 E -> 茶摊老板; 送信 茶摊老板 -> 山门老伯; 找鸡 E at the chick in the road grass -> it follows (it
##              walks the player's own foot trail, so it never stands in a wall, and it has no collision) -> back at 村口
##              (pen); 挖竹笋 3 glowing spots in the grove; 找玉佩 1 spot; 补篱笆 3 fence gaps east of the village (broken
##              while the day's offer is not finished, mended after E). Then 交差 at the board.
##   pay        reward x fame_bonus_mult (1.5, rounded half up) while 名望 >= fame_bonus_at (5); every estate_every (5)
##              turned in: 家业 +1 (cut at the cap).

const KINDS := ["bun", "letter", "chicken", "shoots", "jade", "fence"]
const LAST_STEP := {"bun": 2, "letter": 2, "chicken": 2, "shoots": 1, "jade": 1, "fence": 1}
const FOLLOW_GAP := 22.0
const CHICK_SPEED := 150.0

var main: Node
var jh: Jianghu
var day := -1                 # calendar day of the offers (-1 = none) (saved)
var offers: Array = []        # [{kind, state: open|taken|done, step, count, spots: [], picked: []}] (saved)
var total := 0                # turned in, all days (saved)
var estate_points := 0        # 家业 given (saved)
var chick_state := "none"     # none | lost | follow | home (saved)
var paid: Array = []          # every turn-in {kind, coins, estate} (tests)
var draws := 0                # days drawn (tests)
var expired := 0              # taken offers that went void at midnight (tests)
var chick: Npc
var chick_trail := PackedVector2Array()
var chick_max_wall := 0       # tests: frames the chick stood inside a collider while following (must stay 0)
var glows: Dictionary = {}    # "shoots:i" / "jade:i" -> Glow
var gaps: Array = []          # FenceGap x3
var stall_point := Vector2.ZERO
var pen := Vector2.ZERO


func _init() -> void:
	name = "Commission"


func places() -> Dictionary:
	return jh.data.get("places", {})


func setup(m: Node, hub: Jianghu) -> void:
	main = m
	jh = hub
	var pl := places()
	stall_point = Jianghu._vec(pl.get("stall", {}).get("interact", [1598, 1034]))
	pen = Jianghu._vec(pl.get("pen", [1250, 1772]))
	# the chick (assets/characters/chick.png; 老伯's sheet, small and white, until the art lands)
	CharSheet.alias("chick", "duck")
	chick = Npc.new()
	main.world.add_child(chick)
	chick.setup({"id": "chick", "title": "小鸡", "name": "小鸡", "x": pen.x, "y": pen.y, "dir": "down"})
	chick.name = "Chick"
	chick.collision_layer = 0
	if not CharSheet.has_own_art("chick"):
		chick.sprite.scale = Vector2(0.55, 0.55)
		chick.sprite.position = Vector2(7, 14)
	chick.visible = false
	var shoot_tex := Jianghu.art("props/bamboo_shoot_spot.png")
	var jade_tex := Jianghu.art("props/jade_spot.png")
	for pair in [["shoots", "shoot_spots", shoot_tex], ["jade", "jade_spots", jade_tex]]:
		var list: Array = pl.get(pair[1], [])
		for i in list.size():
			var g := Glow.new()
			g.tex = pair[2]
			g.tint = Color(0.75, 1.0, 0.5) if pair[0] == "shoots" else Color(0.6, 1.0, 0.85)
			g.position = Jianghu._vec(list[i])
			g.name = "Glow_%s_%d" % [pair[0], i]
			g.visible = false
			main.world.add_child(g)
			glows["%s:%d" % [pair[0], i]] = g
	var gap_tex := Jianghu.art("props/fence_gap.png")
	for a in pl.get("fence_gaps", []):
		var fg := FenceGap.new()
		fg.tex = gap_tex
		fg.position = Jianghu._vec(a) + Vector2(0, 31)      # y-sorted by its foot (the tile's bottom row)
		fg.name = "FenceGap_%d" % gaps.size()
		fg.set_meta("type", "fence_gap")
		fg.visible = false
		main.world.add_child(fg)
		gaps.append(fg)


func set_present(on: bool) -> void:
	for fg in gaps:
		fg.visible = on
	if not on:
		chick.visible = false
		for g in glows.values():
			g.visible = false


# ------------------------------------------------------------------ the day's offers
func kind_def(k: String) -> Dictionary:
	return Jianghu.crules().get("kinds", {}).get(k, {})


func kind_name(k: String) -> String:
	return String(jh.data.get("kinds", {}).get(k, {}).get("name", k))


func eligible(k: String) -> bool:
	var need := String(kind_def(k).get("needs_repair", ""))
	return need == "" or jh.sample.is_repaired(need)


func need_count(k: String) -> int:
	return maxi(1, int(kind_def(k).get("count", 1)))


func bonus_on() -> bool:
	return jh.s3.value("fame") >= int(Jianghu.crules().get("fame_bonus_at", 5))


## The pay for a kind right now (x1.5 rounded half up while 名望 >= 5).
func reward(k: String) -> int:
	var base := float(kind_def(k).get("reward", 0))
	if bonus_on():
		base *= float(Jianghu.crules().get("fame_bonus_mult", 1.5))
	return int(floor(base + 0.5))


## The day the board's offers belong to right now (-1 = between midnight and 08:00).
func offer_day() -> int:
	# 新手指引 v1: the day the prologue ends has its two offers at once, whatever the hour (step 5 never waits for 08:00)
	if jh.s3.anchor_day >= 0 and jh.cal_day() == jh.s3.anchor_day:
		return jh.cal_day()
	var h: float = main.daynight.hour
	if h >= float(Jianghu.crules().get("refresh_hour", 8)) and h < float(Jianghu.crules().get("expire_hour", 24)):
		return jh.cal_day()
	return -1


## The two offers of calendar day `d` (deterministic: seed + day; only kinds whose condition holds).
func draw(d: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%d" % [jh.seed, d]).hash()
	var pool: Array = KINDS.filter(func(k): return eligible(k))
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var picks: Array = pool.slice(0, int(Jianghu.crules().get("per_day", 2)))
	picks.sort_custom(func(a, b): return KINDS.find(a) < KINDS.find(b))
	var out := []
	var used := []
	for k in picks:
		var spots := []
		match String(k):
			"chicken":
				spots = [rng.randi_range(0, (places().get("chicken_spots", [[0, 0]]) as Array).size() - 1)]
			"shoots":
				spots = _pick_spots(rng, "shoot_spots", need_count("shoots"), used)
			"jade":
				spots = _pick_spots(rng, "jade_spots", need_count("jade"), used)
			"fence":
				spots = range((places().get("fence_gaps", []) as Array).size())
		out.append({"kind": String(k), "state": "open", "step": 0, "count": 0, "spots": spots, "picked": []})
	return out


func _pick_spots(rng: RandomNumberGenerator, key: String, n: int, used: Array) -> Array:
	var list: Array = places().get(key, [])
	var idx := range(list.size()).filter(func(i): return not used.has(str(list[i])))
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = idx[i]
		idx[i] = idx[j]
		idx[j] = t
	var out: Array = idx.slice(0, n)
	out.sort()
	for i in out:
		used.append(str(list[i]))
	return out


func taken_count() -> int:
	return offers.filter(func(o): return String(o["state"]) == "taken").size()


func complete(o: Dictionary) -> bool:
	return not o.is_empty() and int(o.get("step", 0)) >= int(LAST_STEP.get(String(o.get("kind", "")), 1))


func find_taken(k: String) -> Dictionary:
	for o in offers:
		if String(o["kind"]) == k and String(o["state"]) == "taken":
			return o
	return {}


func step_text(o: Dictionary) -> String:
	var hud: Array = jh.data.get("kinds", {}).get(String(o["kind"]), {}).get("hud", [])
	var s := clampi(int(o["step"]), 0, hud.size() - 1)
	var t := String(hud[s]) if not hud.is_empty() else ""
	return t % [int(o["count"]), need_count(String(o["kind"]))] if "%d" in t else t


# ------------------------------------------------------------------ board actions
func accept(i: int) -> String:
	if i < 0 or i >= offers.size() or String(offers[i]["state"]) != "open":
		return ""
	if taken_count() >= int(Jianghu.rules().get("max_commission", 2)):
		return ""
	var o: Dictionary = offers[i]
	o["state"] = "taken"
	o["step"] = 0
	o["count"] = 0
	o["picked"] = []
	if String(o["kind"]) == "chicken":
		chick_state = "lost"
		_place_chick_at_spot(o)
	if OS.has_feature("web"):
		print("commission: accepted %s" % o["kind"])
	jh.request_save("commission")
	return jh.ui("commission_accepted") % kind_name(String(o["kind"]))


func abandon(i: int) -> String:
	if i < 0 or i >= offers.size() or String(offers[i]["state"]) != "taken":
		return ""
	var o: Dictionary = offers[i]
	o["state"] = "open"
	o["step"] = 0
	o["count"] = 0
	o["picked"] = []
	if String(o["kind"]) == "chicken":
		chick_state = "none"
	jh.request_save("commission")
	return jh.ui("commission_abandoned") % kind_name(String(o["kind"]))


## Pays a finished offer once; every estate_every turned in: 家业 +1 (cut at the cap).
func turn_in(i: int) -> String:
	if i < 0 or i >= offers.size():
		return ""
	var o: Dictionary = offers[i]
	if String(o["state"]) != "taken" or not complete(o):
		return ""
	var k := String(o["kind"])
	var coins := reward(k)
	o["state"] = "done"
	jh.sample.add_coins(coins)
	total += 1
	var every := maxi(1, int(Jianghu.crules().get("estate_every", 5)))
	var est := 0
	var extra := ""
	if total % every == 0:
		est = jh.s3.grant("estate", 1)
		estate_points += est
		extra = "\n" + (jh.ui("commission_estate") % total if est > 0 else jh.ui("commission_estate_full") % total)
	if k == "chicken":
		chick_state = "none"
	paid.append({"kind": k, "coins": coins, "estate": est})
	if OS.has_feature("web"):
		print("commission: paid %s %d" % [k, coins])
	jh.request_save("commission")
	var kd: Dictionary = jh.data.get("kinds", {}).get(k, {})
	return jh.ui("commission_paid") % [String(kd.get("client", "")), String(kd.get("thanks", "")), coins] + extra


## A step done inside one of our scenes ("do": "jh", "op": "c_step", "cid": kind).
func step(k: String) -> void:
	var o := find_taken(k)
	if o.is_empty() or complete(o):
		return
	o["step"] = int(o["step"]) + 1
	match k:
		"bun":
			if int(o["step"]) == 1:
				jh.toast(jh.ui("toast_got_bun"))
		"letter":
			if int(o["step"]) == 1:
				jh.toast(jh.ui("toast_got_letter"))
		"chicken":
			chick_state = "follow"
			chick_trail = PackedVector2Array([chick.global_position, main.player.global_position])
		"jade":
			o["picked"] = [0]
			o["count"] = 1
			jh.toast(jh.ui("toast_jade"))
	jh.request_save("commission")


func dig(spot: int) -> void:
	var o := find_taken("shoots")
	if o.is_empty() or int(o["step"]) != 0 or (o["picked"] as Array).has(spot):
		return
	(o["picked"] as Array).append(spot)
	o["count"] = int(o["count"]) + 1
	jh.toast(jh.ui("toast_shoot") % [int(o["count"]), need_count("shoots")])
	if int(o["count"]) >= need_count("shoots"):
		o["step"] = 1
	jh.request_save("commission")


func mend(gap: int) -> void:
	var o := find_taken("fence")
	if o.is_empty() or int(o["step"]) != 0 or (o["picked"] as Array).has(gap):
		return
	(o["picked"] as Array).append(gap)
	o["count"] = int(o["count"]) + 1
	jh.toast(jh.ui("toast_fence") % [int(o["count"]), need_count("fence")])
	if int(o["count"]) >= need_count("fence"):
		o["step"] = 1
	jh.request_save("commission")


# ------------------------------------------------------------------ the world: E targets, talk, marks
func _offer_of(k: String) -> Dictionary:
	for o in offers:
		if String(o["kind"]) == k:
			return o
	return {}


func interaction_target(p: Vector2, best_d: float) -> Dictionary:
	var r := float(places().get("thing_radius", 26))
	var cands := []      # [pos, radius, target]
	var bun := find_taken("bun")
	if not bun.is_empty() and int(bun["step"]) == 0 and jh.sample.stall_open():
		cands.append([stall_point, float(places().get("stall", {}).get("radius", 28)),
			{"what": "scene", "scene": "J-馒头-取", "prompt": jh.ui("prompt_take"), "prompt_pos": stall_point + Vector2(0, -60)}])
	var ch := find_taken("chicken")
	if not ch.is_empty() and int(ch["step"]) == 0 and chick.visible:
		cands.append([chick.global_position, r, {"what": "scene", "scene": "J-找鸡-找到", "prompt": jh.ui("prompt_chick"),
			"prompt_pos": chick.global_position + Vector2(0, -22)}])
	var sh := find_taken("shoots")
	if not sh.is_empty() and int(sh["step"]) == 0:
		for i in sh["spots"]:
			if not (sh["picked"] as Array).has(i):
				var g: Node2D = glows["shoots:%d" % int(i)]
				cands.append([g.position, r, {"what": "dig", "arg": int(i), "prompt": jh.ui("prompt_dig"), "prompt_pos": g.position + Vector2(0, -24)}])
	var jd := find_taken("jade")
	if not jd.is_empty() and int(jd["step"]) == 0 and not (jd["spots"] as Array).is_empty():
		var g2: Node2D = glows["jade:%d" % int(jd["spots"][0])]
		cands.append([g2.position, r, {"what": "scene", "scene": "J-玉佩-找到", "prompt": jh.ui("prompt_pick"), "prompt_pos": g2.position + Vector2(0, -24)}])
	var fe := find_taken("fence")
	if not fe.is_empty() and int(fe["step"]) == 0:
		for i in fe["spots"]:
			if not (fe["picked"] as Array).has(i):
				cands.append([gap_point(int(i)), r, {"what": "mend", "arg": int(i), "prompt": jh.ui("prompt_mend"),
					"prompt_pos": gap_point(int(i)) + Vector2(0, -36)}])
	var out := {}
	for c in cands:
		var d: float = (c[0] as Vector2).distance_to(p)
		if d <= float(c[1]) and d < best_d:
			best_d = d
			out = c[2]
			out["kind"] = "jianghu"
			out["id"] = "thing"
			out["dist"] = d
	return out


## Where to stand for a fence gap: just north of it (the haystack is south).
func gap_point(i: int) -> Vector2:
	return (gaps[i] as Node2D).position + Vector2(16, -38)


func interact(t: Dictionary) -> void:
	match String(t.get("what", "")):
		"scene":
			main.story.play(String(t["scene"]))
		"dig":
			dig(int(t["arg"]))
		"mend":
			mend(int(t["arg"]))


func talk_scene(npc_id: String) -> String:
	var bun := find_taken("bun")
	var letter := find_taken("letter")
	if npc_id == "tanuki":
		if not bun.is_empty() and int(bun["step"]) == 1:
			return "J-馒头-送"
		if not letter.is_empty() and int(letter["step"]) == 0:
			return "J-送信-取"
	elif npc_id == "dog" and not letter.is_empty() and int(letter["step"]) == 1:
		return "J-送信-送"
	return ""


## Where the taken offers need the player next (yellow minimap dots).
func targets() -> Array:
	var out := []
	for o in offers:
		if String(o["state"]) == "taken":
			out.append_array(targets_of(o))
	return out


## Where one offer needs the player next: the place(s) of its current step; the board when it is to be taken / turned in.
func targets_of(o: Dictionary) -> Array:
	var out := []
	if String(o["state"]) != "taken" or complete(o):
		out.append(jh.board_point)
		return out
	var s := int(o["step"])
	match String(o["kind"]):
		"bun":
			var tn = main.story._npc("tanuki")
			out.append(stall_point if s == 0 else (tn.global_position if tn != null else pen))
		"letter":
			var who = main.story._npc("tanuki" if s == 0 else "dog")
			if who != null:
				out.append(who.global_position)
		"chicken":
			out.append(chick.global_position if s == 0 else pen)
		"shoots":
			for i in o["spots"]:
				if not (o["picked"] as Array).has(i):
					out.append(glows["shoots:%d" % int(i)].position)
		"jade":
			out.append(glows["jade:%d" % int(o["spots"][0])].position)
		"fence":
			for i in o["spots"]:
				if not (o["picked"] as Array).has(i):
					out.append(gap_point(int(i)))
	return out


func marks() -> Array:
	return targets().map(func(q): return {"point": q, "color": Color(1.0, 0.85, 0.2)})


func poi_points() -> Array:
	var out := []
	if chick.visible:
		out.append(chick.global_position)
	for g in glows.values():
		if g.visible:
			out.append(g.position)
	return out


func task_lines() -> Array:
	var out := []
	for o in offers:
		if String(o["state"]) == "taken":
			out.append(jh.ui("hud_commission") % [kind_name(String(o["kind"])), step_text(o)])
	return out


# ------------------------------------------------------------------ every frame
func _physics_process(delta: float) -> void:
	if main == null or not jh.active():
		return
	var want := offer_day()
	if want != day:
		var lost := offers.filter(func(o): return String(o["state"]) == "taken").size()
		if lost > 0:
			expired += lost
			jh.toast(jh.ui("toast_expired"))
		day = want
		offers = draw(day) if day >= 0 else []
		if day >= 0:
			draws += 1
		chick_state = "none"
		if OS.has_feature("web"):
			print("commission: day %d %s" % [day, offers.map(func(o): return o["kind"])])
		jh.request_save("commission")
	_update_things()
	if chick_state == "follow":
		_follow(delta)


func _update_things() -> void:
	var sh := find_taken("shoots")
	var jd := find_taken("jade")
	for key in glows:
		var parts: PackedStringArray = String(key).split(":")
		var o := sh if parts[0] == "shoots" else jd
		var i := int(parts[1])
		glows[key].visible = not o.is_empty() and int(o["step"]) == 0 and (o["spots"] as Array).has(i) and not (o["picked"] as Array).has(i)
	var fe := _offer_of("fence")
	for i in gaps.size():
		var broken := not fe.is_empty() and String(fe["state"]) != "done" and not (fe["picked"] as Array).has(i)
		gaps[i].broken = broken
	var ch := _offer_of("chicken")
	var show := chick_state != "none" and not ch.is_empty() and String(ch["state"]) == "taken"
	if not show and chick_state != "none":
		chick_state = "none"
	chick.visible = show


func _place_chick_at_spot(o: Dictionary) -> void:
	var list: Array = places().get("chicken_spots", [])
	var i := int(o["spots"][0]) if not (o["spots"] as Array).is_empty() else 0
	chick.global_position = Jianghu._vec(list[clampi(i, 0, list.size() - 1)])
	chick.face("down")


## The chick walks the player's own foot trail (every point of it was a free spot for the player's feet).
func _follow(delta: float) -> void:
	var p: Player = main.player
	var pp := p.global_position
	var it: Interiors = main.interiors
	var outdoors := it.room_at(pp) == "" and Rect2(Vector2.ZERO, main.map_size).has_point(pp)
	if chick_trail.is_empty():
		chick_trail.append(pp)
	var last := chick_trail[chick_trail.size() - 1]
	if pp.distance_to(last) > 48.0:
		# a door (or any jump): it waits outside; when the player is back outdoors it is at his heels again
		chick_trail = PackedVector2Array([pp])
		if outdoors:
			chick.global_position = pp
		return
	if not outdoors:
		return
	if pp.distance_to(last) >= 1.0:
		chick_trail.append(pp)
	var remaining := chick.global_position.distance_to(chick_trail[0])
	for i in range(1, chick_trail.size()):
		remaining += chick_trail[i - 1].distance_to(chick_trail[i])
	var moved := false
	if remaining > FOLLOW_GAP:
		var stepv := minf(maxf(CHICK_SPEED, remaining * 3.0) * delta, remaining - FOLLOW_GAP)
		var from := chick.global_position
		while stepv > 0.001 and chick_trail.size() > 0:
			var tgt := chick_trail[0]
			var d := chick.global_position.distance_to(tgt)
			if d <= stepv:
				chick.global_position = tgt
				stepv -= d
				if chick_trail.size() > 1:
					chick_trail.remove_at(0)
				else:
					break
			else:
				chick.global_position += (tgt - chick.global_position) / d * stepv
				stepv = 0.0
		var mv := chick.global_position - from
		if mv.length() > 0.05:
			moved = true
			chick.facing = CharSheet.dir_from_vector(mv, chick.facing)
	var anim := ("walk_" if moved else "idle_") + chick.facing
	if chick.sprite.animation != anim:
		chick.sprite.play(anim)
	if _in_wall(chick.global_position):
		chick_max_wall += 1
	if chick.global_position.distance_to(pen) <= float(places().get("pen_radius", 56)):
		chick_state = "home"
		var o := find_taken("chicken")
		if not o.is_empty() and int(o["step"]) == 1:
			o["step"] = 2
		chick.face("down")
		jh.toast(jh.ui("toast_chick_home"))
		jh.say_bubble(jh.ui("chick_bubble"), chick, 1.6)
		jh.request_save("commission")


## Is a point inside a solid map collider (tests: the chick must never be)?
func _in_wall(q: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	var pq := PhysicsPointQueryParameters2D.new()
	pq.position = q
	pq.collision_mask = 1
	pq.exclude = [main.player.get_rid()]
	for hit in space.intersect_point(pq, 4):
		if hit["collider"] == main.solids:
			return true
	return false


# ------------------------------------------------------------------ 门派簿
func book_entries() -> Array:
	return [jh.book("commission_estate") % total] if total > 0 else []


func book_line() -> String:
	var every := maxi(1, int(Jianghu.crules().get("estate_every", 5)))
	return jh.book("commission_line") % [total, total % every, every]


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"day": -1, "offers": [], "total": 0, "estate": 0, "chick": {"state": "none", "pos": [0, 0]}}


func capture() -> Dictionary:
	return {"day": day, "offers": offers.duplicate(true), "total": total, "estate": estate_points,
		"chick": {"state": chick_state, "pos": [chick.global_position.x, chick.global_position.y]}}


func restore(d: Dictionary) -> void:
	day = int(d["day"])
	offers = []
	for o in d["offers"]:
		offers.append({"kind": String(o["kind"]), "state": String(o["state"]), "step": int(o["step"]), "count": int(o["count"]),
			"spots": (o["spots"] as Array).map(func(x): return int(x)), "picked": (o["picked"] as Array).map(func(x): return int(x))})
	total = int(d["total"])
	estate_points = int(d["estate"])
	chick_state = String(d["chick"]["state"])
	var cp: Array = d["chick"]["pos"]
	chick.global_position = Vector2(float(cp[0]), float(cp[1]))
	chick_trail = PackedVector2Array()
	if chick_state == "follow":
		# at his heels again - or, when the save was made indoors, waiting outside that room's door (修复 v1)
		var room: String = main.interiors.room_at(main.player.global_position)
		chick.global_position = main.interiors.exit_spot(room) if room != "" else main.player.global_position
	elif chick_state == "lost":
		var o := find_taken("chicken")
		if not o.is_empty():
			_place_chick_at_spot(o)
	_update_things()


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing jianghu.com"
	for k in ["day", "total", "estate"]:
		if not SaveGame._type_ok(d.get(k), "num"):
			return "bad jianghu.com." + k
	if float(d["total"]) < 0.0 or float(d["estate"]) < 0.0:
		return "bad jianghu.com.total"
	if not (d.get("offers") is Array):
		return "bad jianghu.com.offers"
	for o in d["offers"]:
		if typeof(o) != TYPE_DICTIONARY or not (String(o.get("kind", "")) in KINDS) or not (String(o.get("state", "")) in ["open", "taken", "done"]):
			return "bad jianghu.com.offer"
		for k in ["step", "count"]:
			if not SaveGame._type_ok(o.get(k), "num") or float(o[k]) < 0.0:
				return "bad jianghu.com.offer." + k
		for k in ["spots", "picked"]:
			if not (o.get(k) is Array):
				return "bad jianghu.com.offer." + k
			for x in o[k]:
				if not SaveGame._type_ok(x, "num") or float(x) < 0.0:
					return "bad jianghu.com.offer." + k
	var c = d.get("chick")
	if typeof(c) != TYPE_DICTIONARY or not (String(c.get("state", "")) in ["none", "lost", "follow", "home"]) or not SaveGame._type_ok(c.get("pos"), "vec"):
		return "bad jianghu.com.chick"
	return ""


## A glowing spot on the grove floor (frames 0-2 of the art, 6 fps; a drawn pulse until it lands).
class Glow extends Node2D:
	var tex: Texture2D
	var tint := Color(0.8, 1.0, 0.5)
	var _t := 0.0

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if tex != null:
			var f := int(_t * 6.0) % 3
			draw_texture_rect_region(tex, Rect2(-16, -26, 32, 32), Rect2(f * 32, 0, 32, 32))
			return
		var k := 0.5 + 0.5 * sin(_t * 5.0)
		draw_circle(Vector2(0, -4), 6.0 + 2.0 * k, Color(tint.r, tint.g, tint.b, 0.25 + 0.25 * k))
		draw_circle(Vector2(0, -4), 2.5, Color(1, 1, 0.85, 0.9))


## A fence gap east of the village: frame 0 broken, frame 1 mended (tile-aligned, drawn above its foot point).
class FenceGap extends Node2D:
	var tex: Texture2D
	var broken := false:
		set(v):
			if v != broken:
				broken = v
				queue_redraw()

	func _draw() -> void:
		if tex != null:
			draw_texture_rect_region(tex, Rect2(0, -31, 32, 32), Rect2(0 if broken else 32, 0, 32, 32))
			return
		var c := Color("8a5a34")
		draw_rect(Rect2(2, -24, 4, 22), c)
		draw_rect(Rect2(26, -24, 4, 22), c)
		if broken:
			draw_line(Vector2(6, -19), Vector2(14, -16), c, 2.0)
			draw_line(Vector2(8, -4), Vector2(24, -2), c, 2.0)
		else:
			draw_rect(Rect2(2, -20, 28, 3), Color("b98a55"))
			draw_rect(Rect2(2, -11, 28, 3), Color("b98a55"))
