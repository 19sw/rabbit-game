class_name SaveGame
extends RefCounted
## 两条路小样 v1 · 存档 (plan section 9): one automatic save slot in user:// (the browser keeps it in IndexedDB).
## File: {"game": GAME_ID, "version": VERSION, "saved_at": unix time, "reason": "...", "state": {...}} as JSON.
## What is in "state" (capture()): story progress and gating (stage, flags, objective, wiping, puzzle, bubbles, 门派簿),
## the dorm opening's water, bandits, coins / repairs / trial results / stall day (Sample), the clock, where the rabbit
## is (indoors or out follows from the position) and his HP.
## When: Sample.request_save(reason) after story progress, a repair, the end of a trial, the daily income and a door; the
## write waits for a calm frame (no conversation / modal page / spar / trial / door fade), so a save never catches a
## half-played scene. Reading never hangs: a missing, unreadable, wrong-version or malformed file is reported with
## "存档无法读取，已重新开始" and the game starts fresh (the bad file is kept as save_bad.json for a look).
## Tests and screenshot scripts (a SceneTree script as the main loop) use user://test_save.json, never the real slot.
## 第③步: VERSION 2 adds the "step3" section (Step3.capture: the 比武大会 calendar anchor, entries / titles / 名望 given,
## the disciple's state, job, upkeep debt and progress). A version-1 file (第②步) is upgraded on reading (upgrade()):
## step 3 starts empty, and day 1 of the 比武大会 calendar is taken as the game's first day (a step-2 save does not record
## the day the prologue ended; the prologue is normally finished on that first day) - a step-2 save from before the end of
## the prologue (sample.unlocked false) gets no day 1 yet: it is set when the prologue really ends.
## 补充 v1.1: VERSION 3 adds the 比武大会 difficulty of the edition entered last + the 困难 titles, and the 陪练 count of the
## day (陪练 is counted per calendar day now); a version-2 file is upgraded with 普通 / no 困难 titles / count 1 if a
## 陪练 was recorded.
## 第④步第一批: VERSION 4 adds the "jianghu" section (Jianghu.capture: the 委托 seed, 悬赏 progress - main bounties turned
## in, the next posting day, 巡山 editions, the bounty taken and whether it is won -, the day's 委托 offers with their progress,
## the chick, the totals and the 名望 / 家业 given). Versions 1-3 are upgraded with an empty section: nothing of step 4a
## happened yet (the first 悬赏 is posted on day 2 of Step3's calendar, i.e. at once for a game already past it).
## 新手指引 v1: VERSION 5 adds the "guide" section (Guide.capture: steps done / paid, 出师, switched off, the step-1 / step-4 /
## step-5 marks, the tracked item). Versions 1-4 get Guide.upgrade_state: a save made after the prologue has the guide
## running with every step its state already meets marked done and paid - without paying any coins.
## 改名与起名 v1: "player" may hold "name" (the hero's name the player chose). Optional - no version change: an older
## file has none and loads as 小兔; a name that is not text is refused like any broken field; text this version cannot
## show (empty, too long, a character missing from the font) loads as 小兔 (PlayerName.from_save).

const GAME_ID := "dongwu-wuxia-demo"
const VERSION := 5
const OLDEST_VERSION := 1     # older files are upgraded (upgrade()); anything else is refused
const SLOT := "user://save.json"
const TEST_SLOT := "user://test_save.json"
const BROKEN_TEXT := "存档无法读取，已重新开始"
const WORLD_MAX := Vector2(4800, 2400)  # the map (2048 x 1920) and the rooms to its right all lie inside this

static var path_override := ""          # tests may point the slot elsewhere
static var pending: Variant = null      # state handed from the title screen's 继续游戏 to the next main scene
static var pending_broken := false      # 继续游戏 found a bad file: the new game shows BROKEN_TEXT
static var writes := 0                  # statistics (tests)
static var last_reason := ""


static func path() -> String:
	if path_override != "":
		return path_override
	var ml := Engine.get_main_loop()
	if ml != null and ml.get_script() != null:
		return TEST_SLOT       # running under tests/*.gd: never touch the player's save
	return SLOT


static func exists() -> bool:
	return FileAccess.file_exists(path())


static func erase() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(path().get_file()):
		dir.remove(path().get_file())


## Writes `state` (atomically: temp file, then rename). Returns true on success.
static func write(state: Dictionary, reason := "") -> bool:
	var doc := {"game": GAME_ID, "version": VERSION, "saved_at": int(Time.get_unix_time_from_system()), "reason": reason,
		"state": state}
	var p := path()
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: cannot write " + tmp)
		return false
	f.store_string(JSON.stringify(doc, "", true, true))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(p.get_file()):
		dir.remove(p.get_file())
	var err := dir.rename(tmp.get_file(), p.get_file())
	if err != OK:
		push_warning("SaveGame: rename failed (%d)" % err)
		return false
	writes += 1
	last_reason = reason
	if OS.has_feature("web"):
		print("save: written (%s)" % reason)
	return true


## Reads and checks the slot: {ok: bool, state: Dictionary, error: String}. Never throws, never waits.
static func read() -> Dictionary:
	var p := path()
	if not FileAccess.file_exists(p):
		return {"ok": false, "state": {}, "error": "missing"}
	var text := FileAccess.get_file_as_string(p)
	var doc = JSON.parse_string(text) if text.strip_edges() != "" else null
	if typeof(doc) != TYPE_DICTIONARY:
		return {"ok": false, "state": {}, "error": "not json"}
	if String(doc.get("game", "")) != GAME_ID:
		return {"ok": false, "state": {}, "error": "other game"}
	var v = doc.get("version", null)
	if not (v is float or v is int) or float(v) != floorf(float(v)) or int(v) < OLDEST_VERSION or int(v) > VERSION:
		return {"ok": false, "state": {}, "error": "version %s" % str(v)}
	var st = doc.get("state", null)
	if typeof(st) == TYPE_DICTIONARY and int(v) < VERSION:
		st = upgrade(st, int(v))
	var why := validate(st)
	if why != "":
		return {"ok": false, "state": {}, "error": why}
	return {"ok": true, "state": normalize(st), "error": ""}


## Moves a bad slot out of the way (save_bad.json) so 继续游戏 is greyed out until the next save.
static func quarantine() -> void:
	var p := path()
	var dir := DirAccess.open("user://")
	if dir == null or not dir.file_exists(p.get_file()):
		return
	var bad := p.get_file().get_basename() + "_bad.json"
	if dir.file_exists(bad):
		dir.remove(bad)
	dir.rename(p.get_file(), bad)


# ------------------------------------------------------------------ upgrading
## A state of an older version brought up to VERSION (a copy; the sections that did not change are kept as they are).
static func upgrade(st: Dictionary, from_version: int) -> Dictionary:
	var out := st.duplicate(true)
	if from_version < 2 and not out.has("step3"):
		out["step3"] = Step3.defaults()      # 第②步 -> 第③步: nothing of step 3 happened yet; anchor_day 0
		var smp = out.get("sample", {})
		if smp is Dictionary and not bool(smp.get("unlocked", false)):
			out["step3"]["anchor_day"] = -1  # saved during the prologue: day 1 is the day it really ends
	if from_version < 3 and out.get("step3") is Dictionary:
		var a = out["step3"].get("arena")
		if a is Dictionary:
			if not a.has("difficulty"):
				a["difficulty"] = "normal"
			if not a.has("hard_wins"):
				a["hard_wins"] = []
		var d = out["step3"].get("disciple")
		if d is Dictionary and not d.has("spar_count"):
			d["spar_count"] = 1 if (d.get("spar_day") is float or d.get("spar_day") is int) and float(d["spar_day"]) >= 0.0 else 0
	if from_version < 4 and not out.has("jianghu"):
		out["jianghu"] = Jianghu.defaults()     # 第③步 -> 第④步第一批: no 悬赏 / 委托 yet
	if from_version < 5 and not out.has("guide"):
		out["guide"] = Guide.upgrade_state(out)  # 新手指引 v1: steps already met count as done + paid (no coins)
	return out


# ------------------------------------------------------------------ schema
## "" when `st` has every field with the right type (and sane values), else what is wrong.
static func validate(st: Variant) -> String:
	if typeof(st) != TYPE_DICTIONARY:
		return "state is not an object"
	var spec := {
		"story": {"stage": "num", "flags": "dict", "book_unlocked": "bool", "objective": "num", "wipes": "num",
			"progress": "num", "errors": "num", "hint_given": "bool", "solved": "bool", "bubbles": "array"},
		"player": {"pos": "vec", "facing": "str", "hp": "num"},
		"time": {"hour": "num", "total": "num"},
		"dorm": {"water_level": "num", "water_cap": "num", "puddle": "num", "pours": "num", "bed": "str"},
		"combat": {"bandits": "array", "bandits_active": "bool", "bandits_cleared": "bool"},
		"sample": {"unlocked": "bool", "coins": "num", "paid_day": "num", "trial_runs": "num", "trial_best": "num"},
	}
	for sec in spec:
		var d = st.get(sec, null)
		if typeof(d) != TYPE_DICTIONARY:
			return "missing section " + sec
		for k in spec[sec]:
			if not d.has(k):
				return "missing %s.%s" % [sec, k]
			if not _type_ok(d[k], spec[sec][k]):
				return "bad type %s.%s" % [sec, k]
	var s: Dictionary = st["story"]
	if int(s["stage"]) < 0 or int(s["stage"]) > 9:
		return "stage out of range"
	if not (String(st["player"]["facing"]) in ["down", "left", "right", "up"]):
		return "bad facing"
	# 改名与起名 v1: player.name is optional (older saves have none); when present it must be text
	if st["player"].has("name") and not (st["player"]["name"] is String):
		return "bad player.name"
	if float(st["player"]["hp"]) < 1.0:
		return "bad hp"
	var pp: Array = st["player"]["pos"]
	if float(pp[0]) < 0.0 or float(pp[1]) < 0.0 or float(pp[0]) > WORLD_MAX.x or float(pp[1]) > WORLD_MAX.y:
		return "position outside the world"
	if not (String(st["dorm"]["bed"]) in ["sleeping", "sitting", "empty"]):
		return "bad bed"
	for b in st["combat"]["bandits"]:
		if typeof(b) != TYPE_DICTIONARY or not _type_ok(b.get("state"), "str") or not _type_ok(b.get("visible"), "bool") \
				or not _type_ok(b.get("solid"), "bool"):
			return "bad bandit"
	for v in s["bubbles"]:
		if typeof(v) != TYPE_BOOL:
			return "bad bubble"
	for k in s["flags"]:
		var fv = s["flags"][k]
		if not (fv is bool or fv is float or fv is int):
			return "bad flag " + str(k)
	if float(st["sample"]["coins"]) < 0.0:
		return "negative coins"
	var why3 := Step3.validate(st.get("step3", null))
	if why3 != "":
		return why3
	var why4 := Jianghu.validate(st.get("jianghu", null))
	if why4 != "":
		return why4
	var whyg := Guide.validate(st.get("guide", null))
	if whyg != "":
		return whyg
	# 武学与经营 第一批: optional sections (an older save has none -> nothing learned, no farm); checked when present
	if st.has("skills"):
		var whysk := Skills.validate(st["skills"])
		if whysk != "":
			return whysk
	if st.has("farm"):
		var whyf := Farm.validate(st["farm"])        # 武学与经营 第一批 (B)
		if whyf != "":
			return whyf
	return ""


static func _type_ok(v: Variant, t: String) -> bool:
	match t:
		"num":
			return (v is float or v is int) and is_finite(float(v))
		"bool":
			return v is bool
		"str":
			return v is String
		"dict":
			return v is Dictionary
		"array":
			return v is Array
		"vec":
			return v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int) \
				and is_finite(float(v[0])) and is_finite(float(v[1]))
	return false


## JSON has only floats: whole numbers back to ints, recursively (so a restored state compares equal to a captured one).
static func normalize(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = normalize(v[k])
		return out
	if v is Array:
		return v.map(func(x): return normalize(x))
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e12:
		return int(v)
	return v


## The state through a JSON round trip (what a save + load gives back) - tests compare snapshots this way.
static func roundtrip(st: Dictionary) -> Dictionary:
	return normalize(JSON.parse_string(JSON.stringify(st, "", true, true)))


# ------------------------------------------------------------------ capture / restore
static func capture(main: Node) -> Dictionary:
	var story: Story = main.story
	var p: Player = main.player
	var it: Interiors = main.interiors
	var c: Combat = main.combat
	var bandits := []
	for b in c.bandits:
		bandits.append({"id": b.id, "state": "gone" if b.state == "gone" or b.state == "down" else "idle",
			"visible": b.visible and b.state != "down", "solid": b.collision_layer != 0 and b.state != "down"})
	return {
		"story": {"stage": story.stage, "flags": story.flags.duplicate(true), "book_unlocked": story.book_unlocked,
			"objective": main.objectives.index, "wipes": story.wipes, "progress": story.progress, "errors": story.errors,
			"hint_given": story.hint_given, "solved": story.solved, "bubbles": Array(story.bubble_done)},
		"player": {"pos": [p.global_position.x, p.global_position.y], "facing": p.facing, "hp": p.hp,
			"room": it.room_at(p.global_position), "name": PlayerName.value()},
		"time": {"hour": main.daynight.hour, "total": main.daynight.total_hours},
		"dorm": {"water_level": it.water_level, "water_cap": it.water_cap, "puddle": it.puddle_size, "pours": it.pours,
			"bed": it.bed_state},
		"combat": {"bandits": bandits, "bandits_active": c.bandits_active, "bandits_cleared": c.bandits_cleared},
		"sample": main.sample.capture(),
		"step3": main.step3.capture(),
		"jianghu": main.jianghu.capture(),
		"guide": main.guide.capture(),
		"skills": main.skills.capture() if main.get("skills") != null else Skills.defaults(),   # 武学与经营 第一批 (A)
		"farm": main.farm.capture() if main.get("farm") != null else Farm.defaults(),   # 武学与经营 第一批 (B)
	}


## Puts the game into a saved state instead of starting the opening (main._ready). `st` must have passed validate().
static func restore(main: Node, st: Dictionary) -> void:
	var story: Story = main.story
	var p: Player = main.player
	var it: Interiors = main.interiors
	var c: Combat = main.combat
	var s: Dictionary = st["story"]
	# the story configuration of Story.start(), without the opening scene
	c.story_no_leash = true
	c.revive_bandits_on_death = true
	story.stage = int(s["stage"])
	story.flags = (s["flags"] as Dictionary).duplicate(true)
	story.book_unlocked = bool(s["book_unlocked"])
	story.wipes = int(s["wipes"])
	story.errors = int(s["errors"])
	story.hint_given = bool(s["hint_given"])
	story.progress = int(s["progress"])
	var bub: Array = s["bubbles"]
	for i in mini(bub.size(), story.bubble_done.size()):
		story.bubble_done[i] = bool(bub[i])
	main.objectives.set_index(int(s["objective"]))
	# the stele puzzle: lit stones, the parted clump
	var order := story._order()
	for i in mini(story.progress, order.size()):
		var id := String(order[i])
		if story.stones.has(id):
			story.fx.set_glow(id, story.stones[id]["pos"])
	if bool(s["solved"]):
		story.solved = true
		story.part_gate()
	# bandits
	var cb: Dictionary = st["combat"]
	c.bandits_cleared = bool(cb["bandits_cleared"])
	c.bandits_active = bool(cb["bandits_active"])
	var saved: Array = cb["bandits"]
	for i in c.bandits.size():
		var b: Fighter = c.bandits[i]
		var bs: Dictionary = saved[i] if i < saved.size() else {"state": "idle", "visible": false, "solid": false}
		b.reset_home(true)
		if String(bs["state"]) == "gone":
			b.state = "gone"
		b.visible = bool(bs["visible"])
		b.collision_layer = 1 if bool(bs["solid"]) else 0
	# the dorm (opening leftovers: bed, bucket, puddle, rag)
	var d: Dictionary = st["dorm"]
	it._set_bed(String(d["bed"]))
	it.water_level = float(d["water_level"])
	it.water_cap = float(d["water_cap"])
	it.puddle_size = float(d["puddle"])
	it.pours = int(d["pours"])
	it.overflowing = false
	if story.flags.get("has_rag", false):
		it.take_rag()
	# the clock
	main.daynight.restore(float(st["time"]["hour"]), float(st["time"]["total"]))
	# 武学与经营 第一批: restored before the rabbit's HP below, so a max of 120 / 135 is in place when it is clamped
	if main.get("skills") != null:
		main.skills.restore(st.get("skills", Skills.defaults()))
	if main.get("farm") != null:
		main.farm.restore(st.get("farm", Farm.defaults()))     # 经营 (B): the 药膳 bonus is re-applied here too
	# the rabbit
	var pl: Dictionary = st["player"]
	# 改名与起名 v1: the hero's name (an older save has none -> 小兔; a name this version cannot show -> 小兔 too)
	PlayerName.choose(PlayerName.from_save(pl.get("name", PlayerName.DEFAULT)))
	var pos: Array = pl["pos"]
	main.camera_target = null
	p.sprite.modulate.a = 1.0
	p.global_position = Vector2(float(pos[0]), float(pos[1]))
	var on_map := Rect2(Vector2.ZERO, main.map_size).has_point(p.global_position)
	if not on_map and it.room_at(p.global_position) == "":
		p.global_position = Vector2(main.data["spawn"]["x"], main.data["spawn"]["y"])   # nowhere real: the dorm door
	p.facing = String(pl["facing"])
	p.sprite.play("idle_" + p.facing)
	p.velocity = Vector2.ZERO
	p.hp = clampi(int(pl["hp"]), 1, p.stats.max_hp)
	it.current = ""
	it._armed = false
	main.indoor_k = 1.0 if it.room_at(p.global_position) != "" else 0.0
	# the two-paths sample (coins, repairs and their looks, trial results, the stall)
	main.sample.restore(st["sample"])
	main.step3.restore(st["step3"])
	main.jianghu.restore(st["jianghu"])
	main.guide.restore(st["guide"])
	if OS.has_feature("web"):
		print("save: restored (stage %d)" % story.stage)
