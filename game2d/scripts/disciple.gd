class_name Disciple
extends Node
## 第③步 · 招收第一个弟子 (plan section 二). Rules / numbers: data/economy.json "disciple"; 陪练 fighting numbers:
## cards/squirrel.tres; lines / places: data/step3.json "youngster".
##   state      none -> coming (the condition holds: 旧弟子房 整理好 AND (名望 >= need_fame OR 家业 >= need_estate); he is
##              due at the next arrive_hour, 08:00) -> waiting (a 少年 at 山门外, 老伯 says 山门外有人想拜师) -> joined (收下).
##              再想想 leaves him waiting; the next talk asks again.
##   joined     he is "师弟": 家业 +join_estate, the 门派簿 entry; by day (day_hour..night_hour) he walks about the dorm yard
##              (on 陪练 days he waits in the 练武场), at night he is in the old dorm room.
##   daily      each time the clock passes upkeep_hour (08:00), once per day however far it jumped (DayNight.day_index):
##              the day that ended counts for 打扫 (every days_for_estate days 家业 +1, cut at estate_max), the job chosen
##              the day before takes effect, the upkeep is charged - what the coins cannot cover becomes debt
##              ("伙食钱不够了"), and debt is paid back from the coins as soon as there are any. Coins never go below 0.
##   jobs       E at him -> 派活 (帮厨 greyed until the kitchen is repaired / 陪练 / 打扫) - from the next 08:00 on.
##              帮厨: the stall pays job.cook.stall_income (25) instead of 15 (Sample asks stall_income(day)).
##              陪练: jobs.spar.per_day times per calendar day (counted from midnight, so 07:xx + 08:xx is one day) a spar with him in the 练武场 (Combat.start_bout, his card is weaker than 师兄's); a win
##              +win_coins, every wins_for_fame wins 名望 +1.  打扫: see daily.
## The effective job of a day is a pure function of the day (job_next from job_from), so the stall and the upkeep agree
## whatever order the nodes run in.
## 武学与经营 第一批 (B): a 4th job 种地 ("farm", shown in 派活 only once the farm is open - show_if fm_farm_open): every 09:00 Farm
## waters each planted plot not watered yet when job_on(that work day) == "farm"; he never sows or harvests. By day he
## walks about the farm path with a bucket (farm.json disciple.walk_rects), at night the old dorm as always. The upkeep is
## unchanged. Taking him in shows Farm's one-time hint (师弟可以派去种地…).

var main: Node
var s3: Step3
var spec: Dictionary
var npc: Fighter
var state := "none"          # none | coming | waiting | joined
var arrive_day := -1         # DayNight.day_index(arrive_hour) on which he turns up
var asked := false           # 再想想 was answered at least once
var join_day := -1           # work day (day_index(upkeep_hour)) he was taken in
var tick_day := -1           # last work day whose start (08:00) has been processed
var debt := 0
var job := "none"            # the job of the current work day (after the last tick)
var job_next := "none"       # chosen, takes effect on work day job_from
var job_from := -1
var spar_day := -1           # calendar day (DayNight.day_index(0)) of the last 陪练 bout - he is in the yard 06:00-20:00
var spar_count := 0          # 陪练 bouts on spar_day (at most jobs.spar.per_day)
var spar_wins := 0
var spar_fame := 0           # 名望 given by 陪练 (cut at the cap)
var sweep_days := 0
var sweep_estate := 0        # 家业 given by 打扫
var join_estate := 0         # 家业 given by 收徒
var place := "hidden"        # hidden | gate | yard | spar | night
var upkeep_paid := 0         # statistics (tests)
var upkeep_days := 0
var repaid := 0
var spars := 0
var _spar_pending := false
var _target := Vector2.INF
var _wait := 0.0
var _stuck := 0.0
var _last_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var bucket_sprite: Sprite2D      # 武学与经营 第一批 (B): carried while he works the farm


func _init() -> void:
	name = "Disciple"
	process_priority = 1        # after Sample: at 08:00 the stall pays first, then the upkeep is charged


func setup(m: Node, hub: Step3) -> void:
	main = m
	s3 = hub
	spec = s3.data.get("youngster", {})
	_rng.randomize()
	var id := String(spec.get("id", "squirrel"))
	CharSheet.alias(id, String(spec.get("stand_in", "mouse")))
	npc = Fighter.new()
	main.world.add_child(npc)
	var g: Array = spec.get("gate", [944, 1404])
	npc.setup_fighter({"id": id, "title": String(spec.get("title_before", "少年")), "name": String(spec.get("name_before", "")),
		"x": g[0], "y": g[1], "dir": String(spec.get("gate_dir", "up"))}, String(Economy.job("spar").get("card", "squirrel")),
		"spar", main.combat)
	npc.name = "Npc_" + id
	npc.collision_mask = 1 | 2 | Fighter.ARENA_LAYER   # walls, furniture, the player; the yard walls during 陪练
	if not CharSheet.has_own_art(id) and spec.has("tint"):
		var t: Array = spec["tint"]
		npc.sprite.self_modulate = Color(float(t[0]), float(t[1]), float(t[2]))
	_set_present(false)
	bucket_sprite = Sprite2D.new()
	bucket_sprite.texture = load("res://assets/farm/bucket.png") if ResourceLoader.exists("res://assets/farm/bucket.png") else null
	bucket_sprite.region_enabled = true
	bucket_sprite.region_rect = Rect2(0, 0, 16, 16)
	bucket_sprite.position = Vector2(10, -9)
	bucket_sprite.visible = false
	npc.add_child(bucket_sprite)


func _set_present(on: bool) -> void:
	npc.visible = on
	npc.collision_layer = 1 if on else 0
	if on and not main.npcs.has(npc):
		main.npcs.append(npc)
	elif not on and main.npcs.has(npc):
		main.npcs.erase(npc)


func _v(key: String, def: Array) -> Vector2:
	var a: Array = spec.get(key, def)
	return Vector2(float(a[0]), float(a[1]))


# ------------------------------------------------------------------ the condition, the arrival
func condition() -> bool:
	return s3.sample.is_repaired(String(Economy.disciple().get("need_repair", "dorm_old"))) \
		and (s3.value("fame") >= Economy.disciple_int("need_fame") or s3.value("estate") >= Economy.disciple_int("need_estate"))


func work_day() -> int:
	return main.daynight.day_index(float(Economy.disciple_int("upkeep_hour")))


func _process(_delta: float) -> void:
	if main == null or not s3.active():
		return
	match state:
		"none":
			if condition():
				state = "coming"
				arrive_day = main.daynight.day_index(float(Economy.disciple_int("arrive_hour"))) + 1
				if OS.has_feature("web"):
					print("disciple: condition met")
				s3.request_save("disciple")
		"coming":
			if main.daynight.day_index(float(Economy.disciple_int("arrive_hour"))) >= arrive_day:
				state = "waiting"
				s3.toast(s3.ui("youngster_came"))
				if OS.has_feature("web"):
					print("disciple: at the gate")
				s3.request_save("disciple")
		"joined":
			_daily()
			_repay()
	_update_place()


func _daily() -> void:
	var d := work_day()
	if tick_day >= d:
		return
	while tick_day < d:
		tick_day += 1
		_start_work_day(tick_day)
	s3.request_save("upkeep")


## The start (08:00) of work day `day`: the day before counts for 打扫, the chosen job takes effect, the upkeep.
func _start_work_day(day: int) -> void:
	if job_on(day - 1) == "sweep" and day - 1 > join_day:
		sweep_days += 1
		var need := maxi(1, int(Economy.job("sweep").get("days_for_estate", 5)))
		if sweep_days % need == 0:
			var g := s3.grant("estate", 1)
			sweep_estate += g
			if g > 0:
				s3.toast(s3.ui("sweep_estate") % need)
	if job_from >= 0 and day >= job_from:
		job = job_next
		job_from = -1
	_repay()
	var fee := Economy.disciple_int("upkeep")
	var pay := mini(fee, s3.sample.coins)
	if pay > 0:
		s3.sample.add_coins(-pay)
	upkeep_paid += pay
	upkeep_days += 1
	debt += fee - pay
	if fee - pay > 0:
		s3.toast(s3.ui("upkeep_short") % debt)
	else:
		s3.toast(s3.ui("upkeep") % fee)
	if OS.has_feature("web"):
		print("disciple: upkeep day %d debt %d" % [day, debt])


## Debt is paid back from the coins as soon as there are any.
func _repay() -> void:
	if debt <= 0 or s3.sample.coins <= 0:
		return
	var pay := mini(debt, s3.sample.coins)
	debt -= pay
	repaid += pay
	s3.sample.add_coins(-pay)
	s3.toast(s3.ui("upkeep_repaid") % pay)
	s3.request_save("upkeep")


## The job on work day `day` (the chosen one once its day has come).
func job_on(day: int) -> String:
	if job_from >= 0 and day >= job_from:
		return job_next
	return job


func job_today() -> String:
	return job_on(work_day()) if state == "joined" else "none"


func stall_income(day: int) -> int:
	if state == "joined" and job_on(day) == "cook" and s3.sample.is_repaired("kitchen"):
		return int(Economy.job("cook").get("stall_income", Economy.stall_income()))
	return Economy.stall_income()


# ------------------------------------------------------------------ talking
func talk_scene(npc_id: String) -> String:
	var talk: Dictionary = s3.data.get("talk", {})
	if npc_id == "dog" and state == "waiting":
		return String(talk.get("dog_waiting", ""))
	if npc_id != npc.id or not npc.visible:
		return ""
	if state == "waiting":
		return String(talk.get("youngster_again" if asked else "youngster_first", ""))
	if state == "joined":
		return String(talk.get("disciple", ""))
	return ""


func greeting() -> String:
	var g: Dictionary = s3.data.get("greetings", {})
	if state != "joined":
		return ""
	if job_from >= 0 and job_from > work_day() and job == "none":
		return String(g.get("pending", ""))
	var j := job_today()
	if j == "farm" and main.get("farm") != null:
		return main.farm.ui("greeting_farm")
	if j == "spar" and spars_left_today() <= 0:
		return String(g.get("spar_used", ""))
	return String(g.get(j, g.get("none", "")))


func accept() -> void:
	if state != "waiting":
		return
	state = "joined"
	join_day = work_day()
	tick_day = join_day
	join_estate = s3.grant("estate", Economy.disciple_int("join_estate"))
	npc.title = String(spec.get("title_after", "师弟"))
	npc.full_name = String(spec.get("name_after", "师弟"))
	if join_estate > 0:
		s3.toast(s3.ui("joined_toast") % join_estate)
	if OS.has_feature("web"):
		print("disciple: joined")
	if main.get("farm") != null:
		main.farm.on_disciple_joined()      # 武学与经营 第一批 (B): the one-time 种地 hint
	s3.request_save("disciple")


func think() -> void:
	asked = true


## "do": "disciple_job": from the next 08:00 on.
func assign(j: String, token: int) -> void:
	var story: Story = main.story
	if not (j in ["cook", "spar", "sweep", "farm"]):
		return
	if j == "cook" and not s3.sample.is_repaired("kitchen"):
		return
	if j == "farm" and not farm_open():
		return
	var pending := job_next if job_from >= 0 else job
	var sc := "D-师弟-派活-same" if j == pending else "D-师弟-派活-" + j
	if j != pending:
		job_next = j
		job_from = work_day() + 1
		s3.request_save("job")
	await story._run_entries(story.scene(sc), token)


func today() -> int:
	return main.daynight.day_index(0)


func spars_left_today() -> int:
	var per := int(Economy.job("spar").get("per_day", 1))
	return per - (spar_count if spar_day == today() else 0)


func can_spar_now() -> bool:
	return state == "joined" and job_today() == "spar" and spars_left_today() > 0 and place == "spar" \
		and not main.combat.bout_running()


func request_spar() -> void:
	if can_spar_now():
		_spar_pending = true


func after_scene() -> void:
	if _spar_pending:
		_spar_pending = false
		_start_spar()
	if state == "joined" and npc.title != String(spec.get("title_after", "师弟")):
		npc.title = String(spec.get("title_after", "师弟"))


# ------------------------------------------------------------------ 陪练
func _start_spar() -> void:
	if not can_spar_now():
		return
	var c: Combat = main.combat
	var p: Player = main.player
	spars += 1
	npc.home = _v("spar_spot", [1350, 880])
	npc.home_dir = "left"
	npc.reset_home(true)
	p.global_position = _v("spar_player", [1296, 896])
	p.velocity = Vector2.ZERO
	p.full_heal()
	c.start_bout(npc, c.arena_rect, self, -1.0, c.t("spar_start"))


func on_bout_result(win: bool) -> Dictionary:
	if spar_day != today():
		spar_day = today()
		spar_count = 0
	spar_count += 1
	var lines: Dictionary = s3.data.get("spar", {})
	var pool: Array = lines.get("win" if win else "lose", [""])
	var line := "师弟：" + String(pool[_rng.randi() % pool.size()])
	if not win:
		return {"title": s3.ui("spar_title_lose"), "line": line, "seconds": 2.5}
	spar_wins += 1
	var coins := int(Economy.job("spar").get("win_coins", 0))
	s3.sample.add_coins(coins)
	var extra := s3.ui("spar_reward") % coins
	var need := maxi(1, int(Economy.job("spar").get("wins_for_fame", 5)))
	if spar_wins % need == 0:
		var g := s3.grant("fame", 1)
		spar_fame += g
		if g > 0:
			extra += "  " + s3.ui("spar_fame") % need
	return {"title": s3.ui("spar_title_win"), "line": line + "\n" + extra, "seconds": 2.5}


func on_bout_closed(_win: bool) -> void:
	main.combat.end_bout()
	main.player.full_heal()
	npc.reset_home(true)
	npc.collision_layer = 1
	s3.request_save("spar")


# ------------------------------------------------------------------ where he is
func _want_place() -> String:
	match state:
		"waiting":
			return "gate"
		"joined":
			var h: float = main.daynight.hour
			if h < float(Economy.disciple_int("day_hour")) or h >= float(Economy.disciple_int("night_hour")):
				return "night"
			if job_today() == "farm" and farm_open():
				return "farm"
			return "spar" if job_today() == "spar" else "yard"
	return "hidden"


func _update_place() -> void:
	var c: Combat = main.combat
	if main.story.busy or c.bout_owner == self:
		return
	var want := _want_place()
	if want != place:
		place = want
		_go_to_place()
	# out of the way while the yard is closed for the trial / a 师兄 spar (he never blocks a pole or a fight)
	if place == "spar" and npc.visible:
		var busy_yard: bool = c.trial_active or (c.spar_state != "none" and c.bout_owner != self)
		npc.collision_layer = 0 if busy_yard else 1


func _go_to_place() -> void:
	if place == "hidden":
		_set_present(false)
		return
	_set_present(true)
	var it: Interiors = main.interiors
	var pos := npc.global_position
	var dir := "down"
	match place:
		"gate":
			pos = _v("gate", [944, 1404])
			dir = String(spec.get("gate_dir", "up"))
		"yard":
			pos = _v("yard_home", [470, 1000])
		"farm":
			pos = _farm_v("home", [1712, 1040])
		"spar":
			pos = _v("spar_spot", [1350, 880])
			dir = "left"
		"night":
			pos = it.world_point(String(spec.get("night_room", "dorm_old")), _v("night_spot", [85, 152]))
	npc.home = pos
	npc.home_dir = dir
	npc.reset_home(true)
	bucket_sprite.visible = place == "farm"
	_target = Vector2.INF
	_wait = _rng.randf_range(0.5, 2.0)


## Daytime in the dorm yard: walk to a random free point of the yard rectangles (straight lines only), rest, again.
func _physics_process(delta: float) -> void:
	if main == null or not (place == "yard" or place == "farm") or not npc.visible or npc.engaged:
		return
	var c: Combat = main.combat
	var p: Player = main.player
	if main.story.busy or c.story_hold or npc.global_position.distance_to(p.global_position) < 48.0:
		npc.velocity = Vector2.ZERO
		if not main.story.busy:
			npc.sprite.play("idle_" + npc.facing)
		return
	if _wait > 0.0:
		_wait -= delta
		npc.velocity = Vector2.ZERO
		npc.sprite.play("idle_" + npc.facing)
		return
	if _target == Vector2.INF:
		_target = _pick_target()
		_stuck = 0.0
		_last_pos = npc.global_position
		if _target == Vector2.INF:
			_wait = 1.0
			return
	var to := _target - npc.global_position
	if to.length() < 3.0:
		_target = Vector2.INF
		_wait = _rng.randf_range(1.5, 4.0)
		npc.velocity = Vector2.ZERO
		return
	npc.velocity = to.normalized() * float(spec.get("walk_speed", 46))
	npc.facing = CharSheet.dir_from_vector(to, npc.facing)
	npc.sprite.play("walk_" + npc.facing)
	npc.move_and_slide()
	_stuck += delta
	if _stuck >= 0.6:
		if npc.global_position.distance_to(_last_pos) < 4.0:
			_target = Vector2.INF      # blocked: rest, then somewhere else
			_wait = 1.0
		_stuck = 0.0
		_last_pos = npc.global_position


func _pick_target() -> Vector2:
	var rects: Array = spec.get("yard_rects", [])
	var on_farm: bool = place == "farm" and main.get("farm") != null
	if on_farm:
		rects = main.farm.walk_rects()      # 菜园扩建 v1: the whole field once expanded
	var nav: NavGrid = main.combat.nav
	for i in 12:
		if rects.is_empty():
			break
		var r: Array = rects[_rng.randi() % rects.size()]
		var q := Vector2(_rng.randf_range(float(r[0]), float(r[0]) + float(r[2])), _rng.randf_range(float(r[1]), float(r[1]) + float(r[3])))
		if on_farm:
			# (the nav grid is built once from the map, where the whole field is solid: Farm knows what is open now)
			if main.farm.walk_clear(npc.global_position, q):
				return q
		elif nav == null or nav.line_clear(npc.global_position, q):
			return q
	return Vector2.INF


func in_yard_rects(p: Vector2) -> bool:
	for r in spec.get("yard_rects", []):
		if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).grow(8).has_point(p):
			return true
	return false


# ------------------------------------------------------------------ 门派簿
func book_entries(track: String) -> Array:
	var out := []
	if track == "estate":
		if state == "joined":
			out.append(s3.book("joined"))
		if sweep_estate > 0:
			out.append(s3.book("sweep_estate") % sweep_days)
	elif track == "fame" and spar_fame > 0:
		out.append(s3.book("spar_fame") % spar_wins)
	return out


func job_name(j: String) -> String:
	if j == "farm" and main.get("farm") != null:
		return main.farm.ui("job_farm")     # 武学与经营 第一批 (B)
	return String(s3.data.get("ui", {}).get("job_names", {}).get(j, j))


func farm_open() -> bool:
	return main.get("farm") != null and main.farm.opened


func _farm_v(key: String, def: Array) -> Vector2:
	var a: Array = main.farm.data.get("disciple", {}).get(key, def) if main.get("farm") != null else def
	return Vector2(float(a[0]), float(a[1]))


func book_lines() -> Array:
	if state != "joined":
		return []
	var out := []
	var w := work_day()
	if job_from > w:
		out.append(s3.book("disciple_job_next") % [job_name(job_on(w)), job_name(job_next)])
	else:
		out.append(s3.book("disciple_job") % job_name(job_on(w)))
	var sn := maxi(1, int(Economy.job("spar").get("wins_for_fame", 5)))
	var wn := maxi(1, int(Economy.job("sweep").get("days_for_estate", 5)))
	out.append(s3.book("disciple_progress") % [spar_wins % sn, sn, sweep_days % wn, wn])
	if debt > 0:
		out.append(s3.book("debt") % debt)
	return out


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"state": "none", "arrive_day": -1, "asked": false, "join_day": -1, "tick_day": -1, "debt": 0, "job": "none",
		"job_next": "none", "job_from": -1, "spar_day": -1, "spar_count": 0, "spar_wins": 0, "spar_fame": 0, "sweep_days": 0,
		"sweep_estate": 0, "join_estate": 0}


func capture() -> Dictionary:
	return {"state": state, "arrive_day": arrive_day, "asked": asked, "join_day": join_day, "tick_day": tick_day, "debt": debt,
		"job": job, "job_next": job_next, "job_from": job_from, "spar_day": spar_day, "spar_count": spar_count, "spar_wins": spar_wins,
		"spar_fame": spar_fame, "sweep_days": sweep_days, "sweep_estate": sweep_estate, "join_estate": join_estate}


func restore(d: Dictionary) -> void:
	state = String(d["state"])
	arrive_day = int(d["arrive_day"])
	asked = bool(d["asked"])
	join_day = int(d["join_day"])
	tick_day = int(d["tick_day"])
	debt = int(d["debt"])
	job = String(d["job"])
	job_next = String(d["job_next"])
	job_from = int(d["job_from"])
	spar_day = int(d["spar_day"])
	spar_count = int(d["spar_count"])
	spar_wins = int(d["spar_wins"])
	spar_fame = int(d["spar_fame"])
	sweep_days = int(d["sweep_days"])
	sweep_estate = int(d["sweep_estate"])
	join_estate = int(d["join_estate"])
	if state == "joined":
		npc.title = String(spec.get("title_after", "师弟"))
		npc.full_name = String(spec.get("name_after", "师弟"))
	place = ""
	_update_place()


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing step3.disciple"
	var nums := ["arrive_day", "join_day", "tick_day", "debt", "job_from", "spar_day", "spar_count", "spar_wins", "spar_fame", "sweep_days",
		"sweep_estate", "join_estate"]
	for k in nums:
		if not SaveGame._type_ok(d.get(k), "num"):
			return "bad step3.disciple." + k
	for k in ["debt", "spar_count", "spar_wins", "spar_fame", "sweep_days", "sweep_estate", "join_estate"]:
		if float(d[k]) < 0.0:
			return "bad step3.disciple." + k
	if not (String(d.get("state", "")) in ["none", "coming", "waiting", "joined"]):
		return "bad step3.disciple.state"
	if not (d.get("asked") is bool):
		return "bad step3.disciple.asked"
	for k in ["job", "job_next"]:
		if not (String(d.get(k, "")) in ["none", "cook", "spar", "sweep", "farm"]):
			return "bad step3.disciple." + k
	return ""
