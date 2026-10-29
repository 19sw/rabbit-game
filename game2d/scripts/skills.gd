class_name Skills
extends Node
## 武学与经营 第一批 · 武学 (developer A; docs/design/武学与经营-第一批-方案-v1.md 第一节).
## Data: data/skills.json (names, texts, conditions, scenes), cards/skills/*.tres (numbers).
##   learning   名望 >= need_fame -> 师父 (crane) gives the trial (skills_assign) -> trial passed -> 师父 teaches (skills_teach)
##              -> the ring caption 「学会：…」 with the edge flash once the conversation has closed. Trials:
##                spar_gp       a 师兄 spar in which trial_need GP (格挡) succeed - win or lose (counted after it was given)
##                meditate      sitting on a 正殿 蒲团, E -> K-打坐 (warns about the 委托) -> Schedule.meditate: the
##                              "等到天亮" night itself with the caption 静坐吐纳…… to the next 08:00
##                trial_silver  梅花桩 银 or 金 (flags trial_silver / trial_gold) - an old medal counts at once
##   moves      U / I slots (O is registered, empty this batch); the first move learned goes into U. 燕回旋 = Player.start_spin
##              + Combat.skill_spin; its cooldown runs here. 踏雪二段闪 (body art, always on): Player asks snow_window().
##              吐纳功 (inner art, always running): max HP +20 through set_max_hp_bonus, regen 3 s / 5 per s.
##   max HP     set_max_hp_bonus(source, amount): the one place every max-HP bonus goes through (B's 药膳 +15 too).
##              player.stats is a private copy of cards/player.tres with max_hp = base + every bonus.
##   qi         气槽: counted (hits / GP) but not shown this batch (方案 第六节).
##   UI         门派簿 page 武学 (SectBook.add_page), 任务面板 tab 武学 (Guide.tabs), U / I icons + caption (SkillsHud).
##   save       capture() / restore() as the optional "skills" section of the save (an old save: nothing learned).

signal learned(id: String)          # the moment a skill is learned (B's 进阶指引 step 4 listens)
signal trial_passed(id: String)

const DATA := "res://data/skills.json"
const PLAYER_CARD := "res://cards/player.tres"
const SLOT_KEYS := {"u": "U", "i": "I", "o": "O"}
const SKILL_ORDER_BOOK := ["swallow_spin", "snow_step", "tuna"]   # page order: moves, body art, inner art

var main: Node
var data: Dictionary
var cards := {}                     # id -> Resource
var base_stats: PlayerStats         # the card itself (never changed)
var learned_ids: Array = []         # in the order learned
var slots := {"u": "", "i": ""}     # slot -> move id ("" = empty)
var inner := ""                     # the inner art running
var trials := {}                    # id -> {"state": "none" | "assigned" | "passed", "best": int}
var bonuses := {}                   # max-HP bonus source -> amount
var cooldowns := {}                 # move id -> seconds left
var spar_gp := 0                    # GP caught in the 师兄 spar under way
var qi := 0                         # 气槽 (not shown)
var hud: SkillsHud
var fx: SkillsFx
var book_sel := 0
var casts: Array = []               # every cast {id, slot} (tests)
var teach_log: Array = []           # (tests)
var meditations := 0
var _fanfare: Array = []            # ids learned whose caption waits for the conversation to close
var _meditate_pending := false
var meditating := false

static var _data: Dictionary = {}


func _init() -> void:
	name = "Skills"


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = parsed if parsed is Dictionary else {"skills": {}, "order": []}
	return _data


func setup(m: Node) -> void:
	main = m
	data = load_data()
	for id in order():
		var c := String(skill(id).get("card", ""))
		if c != "" and ResourceLoader.exists(c):
			cards[id] = load(c)
	base_stats = load(PLAYER_CARD)
	var p: Player = m.player
	p.stats = base_stats.duplicate()
	p.skills = self
	fx = SkillsFx.new()
	m.add_child(fx)
	fx.setup(m)
	hud = SkillsHud.new()
	m.add_child(hud)
	hud.setup(self)
	var c: Combat = m.combat
	c.gp_success.connect(_on_gp)
	c.spar_finished.connect(func(_w): spar_gp = 0)
	c.spar_closed.connect(func(_w): spar_gp = 0)
	c.player_hit_enemy.connect(func(_e, _d, _h): add_qi(int(data.get("qi", {}).get("hit", 0))))
	p.spin_started.connect(func(): fx.spin_start(p.global_position))
	p.spin_landed.connect(func(_n): fx.spin_land(p.global_position))
	p.second_dash_started.connect(_on_second_dash)
	p.second_dash_landed.connect(func(at): fx.snow_land(at))
	m.story.sect_book.add_page("skills", book_t("title"), self)
	_recompute()


func order() -> Array:
	return data.get("order", [])


func skill(id: String) -> Dictionary:
	return data.get("skills", {}).get(id, {})


func sname(id: String) -> String:
	return String(skill(id).get("name", id))


func card(id: String) -> Resource:
	return cards.get(id)


func book_t(key: String) -> String:
	return String(data.get("book", {}).get(key, key))


func board_t(key: String) -> String:
	return String(data.get("board", {}).get(key, key))


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


## After the prologue, never in the older suites' sandbox (the same gate as the guide / schedule).
func active() -> bool:
	if main == null or main.story == null or main.story.sandbox:
		return false
	var smp = main.get("sample")
	return smp != null and smp.unlocked and main.story.stage >= 9


func fame() -> int:
	var s3 = main.get("step3") if main != null else null
	return int(s3.value("fame")) if s3 != null else 0


# ------------------------------------------------------------------ queries (B: has_learned)
func has_learned(id: String) -> bool:
	return learned_ids.has(id)


func has_any_move() -> bool:
	for id in learned_ids:
		if String(skill(id).get("kind", "")) == "move":
			return true
	return false


func slot_key(slot: String) -> String:
	return String(SLOT_KEYS.get(slot, slot.to_upper()))


func slot_of(id: String) -> String:
	for s in slots:
		if String(slots[s]) == id:
			return s
	return ""


# ------------------------------------------------------------------ max HP (B: 药膳)
## The one entry for every max-HP bonus: `source` "tuna" (吐纳功 +20, set here), "yaoshan" (B's 药膳 +15), ...
## amount 0 removes it. Max HP = cards/player.tres max_hp + every bonus; a higher max raises the current HP by the
## difference, a lower one cuts it to the new max.
func set_max_hp_bonus(source: String, amount: int) -> void:
	if amount == 0:
		bonuses.erase(source)
	else:
		bonuses[source] = amount
	_recompute()


func max_hp_bonus(source := "") -> int:
	if source != "":
		return int(bonuses.get(source, 0))
	var t := 0
	for k in bonuses:
		t += int(bonuses[k])
	return t


func max_hp() -> int:
	return base_stats.max_hp + max_hp_bonus()


func _recompute() -> void:
	if main == null:
		return
	var tuna: SkillTunaStats = card("tuna")
	if has_learned("tuna") and tuna != null:
		bonuses["tuna"] = tuna.max_hp_bonus
	else:
		bonuses.erase("tuna")
	var p: Player = main.player
	var st: PlayerStats = p.stats
	if st == base_stats:
		st = base_stats.duplicate()
		p.stats = st
	var old := st.max_hp
	st.max_hp = max_hp()
	var running := has_learned("tuna") and tuna != null
	st.regen_delay = tuna.regen_delay if running else base_stats.regen_delay
	st.regen_per_sec = tuna.regen_per_sec if running else base_stats.regen_per_sec
	if st.max_hp > old:
		p.hp += st.max_hp - old
	p.hp = mini(p.hp, st.max_hp)
	fx.set_qi_flow(running and inner == "tuna")


# ------------------------------------------------------------------ moves
func snow_window() -> float:
	var c: SkillSnowStats = card("snow_step")
	return c.window if has_learned("snow_step") and c != null else 0.0


func snow_ratio() -> float:
	var c: SkillSnowStats = card("snow_step")
	return c.distance_ratio if c != null else 1.0


func cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


func cooldown_fraction(id: String) -> float:
	var c = card(id)
	if c == null or not ("cooldown" in c) or float(c.cooldown) <= 0.0:
		return 0.0
	return clampf(cooldown_left(id) / float(c.cooldown), 0.0, 1.0)


## U / I / O pressed (Player). Returns true when a move started.
func try_cast(slot: String) -> bool:
	var id := String(slots.get(slot, ""))
	if id == "" or not has_learned(id) or cooldown_left(id) > 0.0:
		return false
	var p: Player = main.player
	if not p.can_cast():
		return false
	var seats = main.get("seats")
	if seats != null and seats.sitting != "":
		return false
	match id:
		"swallow_spin":
			var c: SkillSpinStats = card(id)
			p.start_spin(c)
			cooldowns[id] = c.cooldown
			Sfx.play("skill_spin")
		_:
			return false
	casts.append({"id": id, "slot": slot})
	return true


func _physics_process(delta: float) -> void:
	if main == null or main.combat == null or main.combat.story_hold:
		return
	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)


func _on_second_dash(from: Vector2) -> void:
	fx.snow_start(from)
	Sfx.play("skill_snow_step")


# ------------------------------------------------------------------ 气槽 (not shown this batch)
func add_qi(n: int) -> void:
	qi = clampi(qi + n, 0, int(data.get("qi", {}).get("max", 100)))


# ------------------------------------------------------------------ trials
func trial_state(id: String) -> String:
	return String(trials.get(id, {}).get("state", "none"))


func trial_best(id: String) -> int:
	return int(trials.get(id, {}).get("best", 0))


func _set_trial(id: String, state: String) -> void:
	var t: Dictionary = trials.get(id, {"state": "none", "best": 0})
	t["state"] = state
	trials[id] = t


## The trial is done: 梅花桩 银 / 金 counts whenever it was won; the others once given and passed.
func passed(id: String) -> bool:
	if String(skill(id).get("trial", "")) == "trial_silver":
		var f: Dictionary = main.story.flags
		return bool(f.get("trial_silver", false)) or bool(f.get("trial_gold", false)) or trial_state(id) == "passed"
	return trial_state(id) == "passed"


## 名望 is enough and it is not learned yet.
func available(id: String) -> bool:
	return active() and not has_learned(id) and fame() >= int(skill(id).get("need_fame", 99))


func assign(id: String) -> void:
	if trial_state(id) == "none":
		_set_trial(id, "assigned")
		spar_gp = 0
	_save("skills_trial")


func pass_trial(id: String) -> void:
	if trial_state(id) == "passed" or has_learned(id):
		return
	_set_trial(id, "passed")
	trial_passed.emit(id)
	main.hud.show_toast(ui("trial_passed").format({"name": sname(id)}), 2.5)
	Sfx.play("quest_complete")
	_save("skills_trial")


func _on_gp(f) -> void:
	add_qi(int(data.get("qi", {}).get("gp", 0)))
	var c: Combat = main.combat
	if c.bout_owner != null or c.spar_state != "fighting" or f == null or f.id != "fox":
		return
	spar_gp += 1
	for id in order():
		if String(skill(id).get("trial", "")) == "spar_gp" and trial_state(id) == "assigned":
			var t: Dictionary = trials[id]
			t["best"] = maxi(int(t.get("best", 0)), spar_gp)
			if spar_gp >= int(skill(id).get("trial_need", 3)):
				pass_trial(id)


## 打坐 can start now: sitting on a 正殿 蒲团 while the 吐纳功 trial is given and not done.
func can_meditate() -> bool:
	var seats = main.get("seats")
	if seats == null or seats.sitting == "" or meditating or not active():
		return false
	if not (data.get("meditate", {}).get("seats", []) as Array).has(seats.sitting):
		return false
	var sch = main.get("schedule")
	if sch != null and sch.waiting:
		return false
	for id in order():
		if String(skill(id).get("trial", "")) == "meditate" and trial_state(id) == "assigned" and not has_learned(id):
			return true
	return false


## Seats hook: E while sitting. True = used (he stays seated, the 打坐 question comes up).
func sit_interact() -> bool:
	if not can_meditate() or main.story.busy:
		return false
	main.story.play(String(data.get("meditate", {}).get("scene", "K-打坐")))
	return true


func _start_meditation() -> void:
	var sch = main.get("schedule")
	if sch == null or meditating:
		return
	meditating = true
	meditations += 1
	if not sch.meditate(String(data.get("meditate", {}).get("caption", ""))):
		meditating = false
		return
	await sch.wait_finished
	meditating = false
	for id in order():
		if String(skill(id).get("trial", "")) == "meditate" and trial_state(id) == "assigned":
			pass_trial(id)


# ------------------------------------------------------------------ learning
## Learns `id` (state now; the caption once no conversation is on screen). False if already learned.
func learn(id: String, fanfare := true) -> bool:
	if has_learned(id) or skill(id).is_empty():
		return false
	learned_ids.append(id)
	_set_trial(id, "passed")
	match String(skill(id).get("kind", "")):
		"move":
			if String(slots.get("u", "")) == "":
				slots["u"] = id
			elif String(slots.get("i", "")) == "":
				slots["i"] = id
		"inner":
			if inner == "":
				inner = id
	_recompute()
	teach_log.append(id)
	if fanfare:
		_fanfare.append(id)
	learned.emit(id)
	_save("skills_learned")
	return true


func learned_caption(id: String) -> String:
	var s := slot_of(id)
	return String(skill(id).get("learned_caption", "")).format({"key": slot_key(s) if s != "" else ""})


func _process(_delta: float) -> void:
	if main == null:
		return
	if not _fanfare.is_empty() and not main.story.busy:
		for id in _fanfare:
			hud.show_learned(learned_caption(id))
			if id == "tuna":
				Sfx.play("skill_tuna_learned")
			Sfx.play("quest_complete")
		_fanfare.clear()
	if _meditate_pending and not main.story.busy:
		_meditate_pending = false
		_start_meditation()
	# 打坐's prompt over the seated rabbit (Story's prompts are off while sitting)
	if can_meditate() and not main.story.busy and not main.story._modal_open():
		main.hud.show_prompt(main.player.global_position + Vector2(0, -34), String(data.get("meditate", {}).get("prompt", "")))


# ------------------------------------------------------------------ 师父 (Story hooks)
## Story.setup: the scenes join the story's table (story.json is not touched).
static func merge_story_data(sd: Dictionary) -> void:
	var d := load_data()
	var scenes: Dictionary = sd.get("scenes", {})
	for id in d.get("scenes", {}):
		scenes[id] = d["scenes"][id]


## Story.talk_scene hook: what 师父 says about the skills now ("" = nothing; the other lines then).
func talk_scene(npc_id: String) -> String:
	if npc_id != "crane" or not active():
		return ""
	var tk: Dictionary = data.get("talk", {})
	for id in order():                                  # a passed trial: he teaches
		if available(id) and passed(id):
			return String(tk[id]["teach"])
	for id in order():                                  # a new one: he gives the trial
		if available(id) and trial_state(id) == "none":
			return String(tk[id]["assign"])
	for id in order():                                  # one under way: a reminder
		if available(id) and trial_state(id) == "assigned":
			return String(tk[id]["wait"])
	return ""


func handles(action: String) -> bool:
	return action in ["skills_assign", "skills_teach", "skills_meditate"]


func do_action(e: Dictionary, _token: int) -> void:
	match String(e["do"]):
		"skills_assign":
			assign(String(e.get("skill", "")))
		"skills_teach":
			learn(String(e.get("skill", "")))
		"skills_meditate":
			_meditate_pending = true


func _save(reason: String) -> void:
	var smp = main.get("sample")
	if smp != null and smp.unlocked:
		smp.request_save(reason)


# ------------------------------------------------------------------ 任务面板 tab 武学 (Guide.tabs hook)
func _trial_text(id: String) -> String:
	var tt: Dictionary = data.get("board", {}).get("trial_text", {})
	var need := int(skill(id).get("trial_need", 1))
	return String(tt.get(String(skill(id).get("trial", "")), "")).format({"need": need, "best": mini(trial_best(id), need)})


func master_asleep() -> bool:
	var sch = main.get("schedule")
	return sch != null and (sch.absent("crane") or sch.should_sleep("crane"))


## [{text, state, key, action, obj}] like Guide's items.
func board_items() -> Array:
	var out := []
	var gd = main.get("guide")
	var mark_cur: String = gd.ui("mark_current") if gd != null else "▶"
	var mark_pend: String = gd.ui("mark_pending") if gd != null else "·"
	for id in order():
		var nm := sname(id)
		var need := int(skill(id).get("need_fame", 0))
		var head := board_t("item").format({"mark": mark_cur, "name": nm, "fame": need})
		var key: String = "skill:" + String(id)
		if has_learned(id):
			out.append({"text": board_t("learned").format({"name": nm}), "state": "done", "key": "", "action": "", "obj": ""})
			continue
		if fame() < need:
			out.append({"text": board_t("item").format({"mark": mark_pend, "name": nm, "fame": need}) + "\n"
				+ board_t("need_fame").format({"fame": need, "now": fame()}), "state": "locked", "key": "", "action": "", "obj": ""})
			continue
		var asleep := master_asleep()
		var line := ""
		var obj := ""
		if passed(id):
			line = board_t("trial_done")
			obj = board_t("obj_back").format({"name": nm})
		elif trial_state(id) == "assigned":
			line = board_t("trial").format({"trial": _trial_text(id)})
			obj = board_t("obj_trial").format({"trial": _trial_text(id)})
		else:
			line = board_t("go_master")
			obj = board_t("obj_go").format({"name": nm})
		var needs_master: bool = passed(id) or trial_state(id) == "none"
		if needs_master and asleep:
			line += " · " + board_t("master_asleep")
			obj = board_t("obj_asleep").format({"name": nm})
		out.append({"text": head + "\n" + line, "state": "current", "key": key, "action": "track", "obj": obj})
	return out


func board_tab() -> Dictionary:
	return {"id": "skills", "name": board_t("tab"), "items": board_items()}


func track_done(key: String) -> bool:
	return has_learned(key.trim_prefix("skill:"))


## World point of the gold arrow for "skill:<id>".
func track_target(key: String) -> Variant:
	var id := key.trim_prefix("skill:")
	var crane: Npc = main.story._npc("crane")
	var master_pos: Variant = crane.global_position if crane != null and crane.visible else null
	if passed(id) or trial_state(id) != "assigned":
		return master_pos
	match String(skill(id).get("trial", "")):
		"spar_gp":
			var fox: Npc = main.story._npc("fox")
			return fox.global_position if fox != null and fox.visible else null
		"meditate":
			var seats = main.get("seats")
			if seats != null:
				var s: Dictionary = seats.seat(String((data.get("meditate", {}).get("seats", [""]) as Array)[0]))
				if not s.is_empty():
					return seats.seat_world(s)
		"trial_silver":
			var smp = main.get("sample")
			if smp != null and smp.trial != null:
				return smp.trial.board_point()
	return master_pos


# ------------------------------------------------------------------ 门派簿 page 武学 (SectBook provider)
func book_page_shown() -> bool:
	return active()


func book_page_close_hint() -> String:
	return book_t("close_hint")


func _book_line(id: String) -> Dictionary:
	var nm := sname(id)
	var kind := String(skill(id).get("kind", ""))
	if has_learned(id):
		var state := ""
		if kind == "move":
			var s := slot_of(id)
			state = book_t("in_slot").format({"key": slot_key(s)}) if s != "" else ""
		elif kind == "inner":
			state = book_t("running") if inner == id else ""
		else:
			state = book_t("active")
		return {"name": nm, "state": state, "detail": String(skill(id).get("desc", "")), "learned": true}
	var how := ""
	var need := int(skill(id).get("need_fame", 0))
	if fame() >= need and passed(id):
		how = book_t("how_back")
	elif fame() >= need and trial_state(id) == "assigned":
		how = book_t("how_trial").format({"trial": _trial_text(id)})
	else:
		how = book_t("how_fame").format({"fame": need})
	return {"name": book_t("locked_name"), "state": "", "detail": how, "learned": false}


var book_rows: Array = []           # [{id, name: Label, state: Label, detail: Label}] of the page drawn last (tests)


func book_page_fill(book: SectBook, col: VBoxContainer) -> void:
	book_sel = clampi(book_sel, 0, SKILL_ORDER_BOOK.size() - 1)
	book_rows = []
	var su := String(slots.get("u", ""))
	var si := String(slots.get("i", ""))
	var sl := book.page_label(book_t("slot_line").format({"u": sname(su) if su != "" else book_t("slot_empty"),
		"i": sname(si) if si != "" else book_t("slot_empty")}), 10, Color(0.5, 0.2, 0.08), false)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sl)
	var heads := {"move": book_t("moves"), "body": book_t("body"), "inner": book_t("inner")}
	for i in SKILL_ORDER_BOOK.size():
		var id: String = SKILL_ORDER_BOOK[i]
		col.add_child(book.page_label(String(heads[String(skill(id).get("kind", ""))]), 10, Color(0.3, 0.14, 0.08), false))
		var bl := _book_line(id)
		var on := i == book_sel
		var lrn := bool(bl["learned"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(16, 16)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if String(skill(id).get("kind", "")) == "move" and hud.icon_tex.has(id):
			ic.texture = hud.icon_tex[id]
			if not lrn:
				ic.modulate = Color(0.12, 0.1, 0.1, 0.55)     # the grey silhouette
		row.add_child(ic)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 3)
		top.add_child(book.page_label("▶" if on else " ", 10, Color(0.62, 0.18, 0.08), false))
		var nl := book.page_label(String(bl["name"]), 10,
			Color(0.62, 0.18, 0.08) if on else (Color(0.22, 0.16, 0.12) if lrn else Color(0.5, 0.46, 0.42)), false)
		top.add_child(nl)
		var stl := book.page_label(String(bl["state"]), 9, Color(0.3, 0.45, 0.2), false)
		stl.visible = String(bl["state"]) != ""
		top.add_child(stl)
		v.add_child(top)
		var dl := book.page_label(String(bl["detail"]), 9, Color(0.35, 0.25, 0.18) if lrn else Color(0.5, 0.46, 0.42))
		dl.set_meta("wrap_inset", 20.0)
		v.add_child(dl)
		row.add_child(v)
		col.add_child(row)
		book_rows.append({"id": id, "name": nl, "state": stl, "detail": dl})


func book_page_input(book: SectBook, event: InputEvent) -> bool:
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		book_sel = clampi(book_sel + (1 if event.is_action_pressed("move_down") else -1), 0, SKILL_ORDER_BOOK.size() - 1)
		Sfx.play("choice_move")
		book.set_page(book.page)
		return true
	if event.is_action_pressed("interact"):
		book_activate(SKILL_ORDER_BOOK[book_sel])
		book.set_page(book.page)
		return true
	return false


## E on the 武学 page: a learned move goes into U (or from U into I); an inner art starts running.
func book_activate(id: String) -> bool:
	if not has_learned(id):
		return false
	match String(skill(id).get("kind", "")):
		"move":
			var s := slot_of(id)
			var to := "i" if s == "u" else "u"
			var other := String(slots.get(to, ""))
			slots[to] = id
			if s != "":
				slots[s] = other            # swapped with what was there (or emptied)
			_save("skills_slot")
			return true
		"inner":
			if inner != id:
				inner = id
				_recompute()
				_save("skills_inner")
			return true
	return false


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"learned": [], "slots": {"u": "", "i": ""}, "inner": "", "trials": {}}


func capture() -> Dictionary:
	return {"learned": learned_ids.duplicate(), "slots": slots.duplicate(), "inner": inner, "trials": trials.duplicate(true)}


func restore(d: Variant) -> void:
	var dd: Dictionary = d if d is Dictionary and validate(d) == "" else defaults()
	learned_ids = (dd["learned"] as Array).map(func(x): return String(x)).filter(func(x): return not skill(x).is_empty())
	slots = {"u": String(dd["slots"].get("u", "")), "i": String(dd["slots"].get("i", ""))}
	inner = String(dd["inner"])
	trials = {}
	for id in dd["trials"]:
		var t: Dictionary = dd["trials"][id]
		trials[String(id)] = {"state": String(t.get("state", "none")), "best": int(t.get("best", 0))}
	cooldowns = {}
	spar_gp = 0
	_fanfare.clear()
	_recompute()


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "bad skills"
	if not (d.get("learned") is Array) or not (d["learned"] as Array).all(func(x): return x is String):
		return "bad skills.learned"
	if not (d.get("slots") is Dictionary) or not (d["slots"] as Dictionary).values().all(func(x): return x is String):
		return "bad skills.slots"
	if not (d.get("inner") is String):
		return "bad skills.inner"
	if not (d.get("trials") is Dictionary):
		return "bad skills.trials"
	for k in d["trials"]:
		var t = d["trials"][k]
		if not (t is Dictionary) or not (String(t.get("state", "")) in ["none", "assigned", "passed"]) \
				or not SaveGame._type_ok(t.get("best", 0), "num"):
			return "bad skills.trials"
	return ""
