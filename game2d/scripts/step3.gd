class_name Step3
extends Node
## 第③步 (docs/design/第三步-擂台与收徒-方案-v1.md): what comes after the two-paths sample - the 比武大会 ring at the
## village (scripts/arena.gd) and the first disciple (scripts/disciple.gd). This node is the hub both use:
##   calendar   the day the prologue ends is day 1 (anchor_day = DayNight.day_index(0) then); day N = index - anchor + 1
##   名望 / 家业  the 门派簿 bars = the story-flag points (SectBook.track_value) + what step 3 granted (比武大会 wins, 陪练,
##              收徒, 打扫); every grant is cut at the cap (economy.json arena.fame_max / disciple.estate_max), so a bar
##              never goes past 10 and the save holds exactly what was given
##   texts      data/step3.json (speakers, scenes, talk rules, ui, book); its scenes join the story's table like the
##              sample's; {numbers} come from economy.json, {day} / {next_day} / {edition} / {greeting} / {chat} are
##              filled again each time such a scene starts
##   hooks      Story asks talk_scene / interaction_target / do_action / option_ok / bubble; Sample asks stall_income;
##              SectBook asks book_extras; SaveGame stores capture() under "step3"
## Nothing of it is active before the sample is unlocked (after 继续逛逛) or in the story-less sandbox of older suites.

const DATA := "res://data/step3.json"
const ART := "res://assets/step3/"
const ACTIONS := ["arena_signup", "disciple_accept", "disciple_think", "disciple_job", "disciple_spar"]

var main: Node
var story: Story
var sample: Sample
var data: Dictionary
var arena: Arena
var disciple: Disciple
var anchor_day := -1              # DayNight.day_index(0) of the day the prologue ended (-1 = not yet)
var toasts: Array[String] = []    # every toast step 3 asked for (tests)
var rng := RandomNumberGenerator.new()
var _toast_queue: Array[String] = []
var _templates: Dictionary = {}   # scene id -> raw entries (filled when the scene starts)


func _init() -> void:
	name = "Step3"


## Called by Story.setup before the dialogue is built: our speakers and scenes join the story's tables.
func merge_story_data(sd: Dictionary) -> void:
	_load()
	var scenes: Dictionary = sd.get("scenes", {})
	for id in data.get("scenes", {}):
		_templates[id] = data["scenes"][id]
		scenes[id] = fill_entries(data["scenes"][id], numbers())
	var sp: Dictionary = sd.get("speakers", {})
	for id in data.get("speakers", {}):
		sp[id] = data["speakers"][id]


func _load() -> void:
	if not data.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Step3: cannot read " + DATA)
		parsed = {}
	data = parsed


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


func book(key: String) -> String:
	return String(data.get("book", {}).get(key, key))


## The economy numbers our lines use (changing economy.json changes what the characters say).
static func numbers() -> Dictionary:
	var a := Economy.arena()
	return {"fee": Economy.arena_int("fee"), "between_heal": Economy.arena_int("between_heal"),
		"first_win_coins": Economy.arena_int("first_win_coins"), "win_coins": Economy.arena_int("win_coins"),
		"first_win_fame": Economy.arena_int("first_win_fame"), "win_fame": Economy.arena_int("win_fame"),
		"hard_first_coins": Economy.arena_hard("first_win_coins"), "hard_first_fame": Economy.arena_hard("first_win_fame"),
		"hard_win_coins": Economy.arena_hard("win_coins"), "hard_win_fame": Economy.arena_hard("win_fame"),
		"spar_per_day": int(Economy.job("spar").get("per_day", 1)),
		"interval": Economy.arena_int("interval_days"), "open_hour": int(a.get("open_hour", 12)),
		"close_hour": int(a.get("close_hour", 18)), "lose_pct": int(round(Economy.arena_float("lose_fraction") * 100.0)),
		"upkeep": Economy.disciple_int("upkeep"), "stall_income": Economy.stall_income(),
		"cook_income": int(Economy.job("cook").get("stall_income", 0)),
		"spar_coins": int(Economy.job("spar").get("win_coins", 0)), "spar_wins": int(Economy.job("spar").get("wins_for_fame", 0)),
		"sweep_days": int(Economy.job("sweep").get("days_for_estate", 0)), "need_fame": Economy.disciple_int("need_fame"),
		"need_estate": Economy.disciple_int("need_estate"),
		# placeholders until the scene starts (filled with the day's values then)
		"day": "?", "next_day": "?", "edition": "?", "greeting": "", "chat": ""}


## numbers() + today's values (calendar, 师弟's greeting / chat line).
func values() -> Dictionary:
	var v := numbers()
	if main != null:
		v["day"] = day_number()
		v["next_day"] = arena.next_day() if arena != null else 0
		v["edition"] = arena.edition_today() if arena != null else 0
		if disciple != null:
			v["greeting"] = disciple.greeting()
			var chats: Array = data.get("chats", [])
			v["chat"] = String(chats[rng.randi() % chats.size()]) if not chats.is_empty() else ""
	return v


static func fill(text: String, vals: Dictionary) -> String:
	return text.format(vals) if "{" in text else text


static func fill_entries(v: Variant, vals: Dictionary) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = fill(v[k], vals) if k == "text" and v[k] is String else fill_entries(v[k], vals)
		return out
	if v is Array:
		return v.map(func(x): return fill_entries(x, vals))
	return v


static func art(file: String) -> Texture2D:
	return load(ART + file) if ResourceLoader.exists(ART + file) else null


## An entry of the step-3 art manifest (assets/step3/manifest.json, copied from pixel2d by tools/sync_assets.py) or {}.
static func manifest(section: String, key: String) -> Dictionary:
	var p := ART + "manifest.json"
	if not FileAccess.file_exists(p):
		return {}
	var m = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(m) != TYPE_DICTIONARY or not (m.get(section, null) is Dictionary):
		return {}
	var v = m[section].get(key, {})
	return v if v is Dictionary else {}


func setup(m: Node) -> void:
	main = m
	story = m.story
	sample = m.sample
	_load()
	rng.randomize()
	arena = Arena.new()
	add_child(arena)
	arena.setup(m, self)
	disciple = Disciple.new()
	add_child(disciple)
	disciple.setup(m, self)
	story.scene_started.connect(_on_scene_started)
	story.scene_finished.connect(_on_scene_finished)
	story.sect_book.provider = self


## Step 3 runs: after 继续逛逛 (the sample unlocked), not in the sandbox of the older suites.
func active() -> bool:
	return sample != null and sample.unlocked and not story.sandbox and story.stage >= 9


## Sample.unlock: the prologue has just ended - today is day 1.
func on_unlock() -> void:
	if anchor_day < 0:
		anchor_day = main.daynight.day_index(0)


## Day number of the 比武大会 calendar (day 1 = the day the prologue ended; the day changes at midnight).
func day_number() -> int:
	return main.daynight.day_index(0) - maxi(anchor_day, 0) + 1


# ------------------------------------------------------------------ 名望 / 家业
func _track(id: String) -> Dictionary:
	for tr in story.sect_book.data.get("tracks", []):
		if String(tr["id"]) == id:
			return tr
	return {}


func cap(track: String) -> int:
	return Economy.arena_int("fame_max") if track == "fame" else Economy.disciple_int("estate_max")


## Points step 3 gave on a track.
func extra(track: String) -> int:
	var jh = main.get("jianghu") if main != null else null
	var j := 0
	if jh != null and jh.bounty != null:
		j = jh.bounty.fame_points if track == "fame" else jh.com.estate_points     # 第④步第一批: 悬赏 / 委托
	if track == "fame":
		return arena.fame_points + disciple.spar_fame + j
	return disciple.join_estate + disciple.sweep_estate + j


func raw_value(track: String) -> int:
	return SectBook.track_value(_track(track), story.flags) + extra(track)


## The bar value (never above the cap).
func value(track: String) -> int:
	return mini(raw_value(track), cap(track))


## How many of `want` points fit under the cap right now (the caller adds them to its own counter).
func grant(track: String, want: int) -> int:
	return clampi(want, 0, maxi(0, cap(track) - raw_value(track)))


# ------------------------------------------------------------------ hooks used by the story / sample / book
func talk_scene(npc_id: String) -> String:
	if not active():
		return ""
	return disciple.talk_scene(npc_id)


func handles(action: String) -> bool:
	return action in ACTIONS


func do_action(e: Dictionary, token: int) -> void:
	match String(e["do"]):
		"arena_signup":
			await arena.signup(token, String(e.get("difficulty", "normal")))
		"disciple_accept":
			disciple.accept()
		"disciple_think":
			disciple.think()
		"disciple_job":
			await disciple.assign(String(e.get("job", "")), token)
		"disciple_spar":
			disciple.request_spar()


func option_ok(key: String) -> bool:
	match key:
		"kitchen":
			return sample.is_repaired("kitchen")
		"spar_now":
			return disciple.can_spar_now()
	return false


func interaction_target(p: Vector2, best_d: float) -> Dictionary:
	if not active():
		return {}
	return arena.interaction_target(p, best_d)


func interact(t: Dictionary) -> void:
	arena.open_board()


func poi_points() -> Array:
	return arena.poi_points() if active() else []


func bubble() -> Dictionary:
	return arena.bubble() if arena != null else {}


func stall_income(day: int) -> int:
	return disciple.stall_income(day) if disciple != null else Economy.stall_income()


func _on_scene_started(id: String) -> void:
	if _templates.has(id):
		story.data["scenes"][id] = fill_entries(_templates[id], values())


func _on_scene_finished(_id: String) -> void:
	arena.after_scene()
	disciple.after_scene()


## 门派簿 additions (SectBook.provider).
func book_extras() -> Dictionary:
	var out := {"points": {"fame": extra("fame"), "estate": extra("estate")}, "entries": {"fame": [], "estate": []}, "lines": []}
	if not active():
		return out
	out["entries"]["fame"].append_array(arena.book_entries())
	out["entries"]["fame"].append_array(disciple.book_entries("fame"))
	out["entries"]["estate"].append_array(disciple.book_entries("estate"))
	out["lines"].append(arena.book_line())
	out["lines"].append_array(disciple.book_lines())
	var jh = main.get("jianghu")
	if jh != null:
		out["entries"]["fame"].append_array(jh.book_entries("fame"))      # 第④步第一批: 揭榜 / 巡山, 委托
		out["entries"]["estate"].append_array(jh.book_entries("estate"))
		out["lines"].append_array(jh.book_lines())
	var gd = main.get("guide")
	if gd != null:
		out["entries"]["fame"].append_array(gd.book_entries())          # 新手指引·出师
	return out


# ------------------------------------------------------------------ toasts (one after the other, never over another)
func toast(t: String) -> void:
	toasts.append(t)
	_toast_queue.append(t)


func _process(_delta: float) -> void:
	if main == null or _toast_queue.is_empty():
		return
	var tl: Label = main.hud.toast
	if tl.modulate.a <= 0.01:
		var t: String = _toast_queue.pop_front()
		main.hud.show_toast(t, 1.6)


# ------------------------------------------------------------------ saving
func request_save(reason: String) -> void:
	sample.request_save(reason)


static func defaults() -> Dictionary:
	return {"anchor_day": 0, "arena": Arena.defaults(), "disciple": Disciple.defaults()}


func capture() -> Dictionary:
	return {"anchor_day": anchor_day, "arena": arena.capture(), "disciple": disciple.capture()}


func restore(d: Dictionary) -> void:
	anchor_day = int(d["anchor_day"])
	if anchor_day < 0 and sample.unlocked:
		anchor_day = main.daynight.day_index(0)
	arena.restore(d["arena"])
	disciple.restore(d["disciple"])


## "" when the step-3 section of a save is well formed.
static func validate(st: Variant) -> String:
	if typeof(st) != TYPE_DICTIONARY:
		return "missing section step3"
	if not SaveGame._type_ok(st.get("anchor_day"), "num"):
		return "bad step3.anchor_day"
	var why := Arena.validate(st.get("arena"))
	if why != "":
		return why
	return Disciple.validate(st.get("disciple"))
