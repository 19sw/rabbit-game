class_name Guide
extends Node
## 新手指引 + 任务面板 v1 (docs/design/新手指引与任务看板-方案-v1.md). Data: data/guide.json.
##   ending     the prologue's last line -> Story._prologue_end: no page any more; everything 继续逛逛 opened opens at once
##              (Sample.unlock), the centre caption "序章 · 完" (~2 s, no key, nothing held) and, once the last scene has
##              closed, 师父's line ("…有不懂的按 Q 看看。"); the guide starts. The objective line never says 序章完成.
##   steps      五步 (combat / trial / repair / stall / board), each latched "done" when its condition is met (in any order),
##              paid once: in order while the guide is on (a step done early is paid when its turn comes), at once when
##              the guide is switched off in the 任务面板. All five paid -> 出师 (+10, 门派簿 "新手指引·出师").
##                combat  a 师兄 spar: one 看破 (dodge success) + one 反击 (counter hit), then a won spar
##                trial   any 梅花桩 medal (story flag trial_*)          repair  the roof (repair_roof)
##                stall   any talk with 厨娘 after the prologue (her repair / stall lines)
##                board   a 委托 turned in (Commission.total) + the 比武 notice board looked at (A-告示牌-* scenes)
##   tracking   one item of the board is tracked: its line is the objective, the gold minimap arrow points at its place.
##              Default: the guide's current step. A tracked item that is finished falls back to the guide (or nothing).
##   captions   centre of the screen, fade in / out: "序章 · 完", "指引完成：…  +N 文", "新手指引·出师  +10 文".
##   model      tabs() -> the 6 tabs of the 任务面板 built from the real game state (scripts/quest_board.gd draws them).
##   saving     capture() under "guide" (save version 5).

const DATA := "res://data/guide.json"
const STEP_IDS := ["combat", "trial", "repair", "stall", "board"]
const TABS := ["guide", "bounty", "com", "repair", "arena", "disciple"]

var main: Node
var story: Story
var sample: Sample
var s3: Step3
var jh: Jianghu
var data: Dictionary
var started := false
var done: Array = [false, false, false, false, false]    # condition met (latched)
var paid: Array = [false, false, false, false, false]    # reward given (once)
var graduated := false
var hidden := false
var dodged := false            # a 看破 in a 师兄 spar (step 1)
var countered := false         # a 反击 in a 师兄 spar
var spar_won := false          # a won 师兄 spar after both
var bear_talked := false       # step 4
var arena_seen := false        # step 5 (the 比武 notice board)
var track := ""                # "" | guide | bounty | com:<kind> | repair:<id> | arena | disciple
var track_mark := 0            # counter value when the item was tracked (bounty turn-ins / arena entries)
var payments: Array = []       # every payment {what, coins} (tests)
var captions: Array[String] = []   # every caption shown (tests)
var caption_layer: CanvasLayer
var caption_label: Label
var hint_label: Label          # step 1 key hint during a 师兄 spar
var _caption_queue: Array = []
var _caption_tween: Tween
var _intro_pending := false

static var _data: Dictionary = {}


func _init() -> void:
	name = "Guide"


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Guide: cannot read " + DATA)
			parsed = {}
		_data = parsed
	return _data


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


func bt(key: String) -> String:
	return String(data.get("board", {}).get(key, key))


func step_def(i: int) -> Dictionary:
	return data.get("steps", [])[i]


## Called by Story.setup before the dialogue is built: our scenes join the story's table.
func merge_story_data(sd: Dictionary) -> void:
	data = load_data()
	var scenes: Dictionary = sd.get("scenes", {})
	for id in data.get("scenes", {}):
		scenes[id] = data["scenes"][id]


func setup(m: Node) -> void:
	main = m
	story = m.story
	sample = m.sample
	s3 = m.step3
	jh = m.jianghu
	data = load_data()
	hidden = bool(data.get("hidden_default", false))
	_build_ui()
	sample.unlocked_now.connect(_on_unlocked)
	story.scene_started.connect(_on_scene_started)
	var c: Combat = m.combat
	c.counter_landed.connect(_on_counter)
	c.spar_closed.connect(_on_spar_closed)
	m.player.dodge_succeeded.connect(_on_dodge)


## The guide / board exist: after the prologue, not in the old suites' sandbox.
func active() -> bool:
	return sample != null and sample.unlocked and not story.sandbox and story.stage >= 9


# ------------------------------------------------------------------ the new ending
## Story._prologue_end: the caption now; 师父's line once the last scene has closed.
func on_prologue_end() -> void:
	caption(ui("prologue_caption"))
	_intro_pending = true


func _on_unlocked() -> void:
	if not started:
		started = true
		if not hidden:
			track = "guide"
		sample.request_save("guide")


# ------------------------------------------------------------------ conditions
func _in_senior_spar() -> bool:
	var c: Combat = main.combat
	return active() and c.spar_state == "fighting" and c.bout_owner == null and c.spar_fighter != null and c.spar_fighter.id == "fox"


func _on_dodge() -> void:
	if _in_senior_spar() and not dodged:
		dodged = true
		sample.request_save("guide")


func _on_counter() -> void:
	if _in_senior_spar() and not countered:
		countered = true
		sample.request_save("guide")


func _on_spar_closed(win: bool) -> void:
	if active() and win and dodged and countered and not spar_won:
		spar_won = true
		sample.request_save("guide")


func _on_scene_started(id: String) -> void:
	if not active():
		return
	if id.begins_with("X-厨娘") and not bear_talked:
		bear_talked = true
	elif id.begins_with("A-告示牌") and not arena_seen:
		arena_seen = true


## The condition of step i right now.
func condition(i: int) -> bool:
	match i:
		0:
			return dodged and countered and spar_won
		1:
			return ["bronze", "silver", "gold"].any(func(t): return story.flags.get("trial_" + t, false))
		2:
			return sample.is_repaired("roof")
		3:
			return bear_talked
		4:
			return jh.com.total >= 1 and arena_seen
	return false


## The step the guide is on (first one not paid; 5 = all paid).
func current() -> int:
	for i in paid.size():
		if not paid[i]:
			return i
	return paid.size()


func finished() -> bool:
	return graduated


# ------------------------------------------------------------------ every frame
func _process(_delta: float) -> void:
	if main == null:
		return
	_update_hint()
	if not active() or not started:
		return
	if _intro_pending and not story.busy and not story._modal_open():
		_intro_pending = false
		story.play(String(data.get("intro_scene", "G-师父-开始")))
	for i in done.size():
		if not done[i] and condition(i):
			done[i] = true
			sample.request_save("guide")
	if hidden:
		for i in done.size():
			if done[i] and not paid[i]:
				_pay(i)
	else:
		var i := current()
		while i < done.size() and done[i]:
			_pay(i)
			i = current()
	if not graduated and paid.all(func(x): return x):
		graduated = true
		var g := int(data.get("graduate_reward", 10))
		sample.add_coins(g)
		payments.append({"what": "graduate", "coins": g})
		caption(ui("graduate") % g)
		sample.request_save("guide")
	if track != "" and track_done(track):
		track = default_track()
		track_mark = mark_of(track)


func _pay(i: int) -> void:
	paid[i] = true
	var n := int(step_def(i).get("reward", 0))
	sample.add_coins(n)
	payments.append({"what": STEP_IDS[i], "coins": n})
	caption(ui("step_done") % [String(step_def(i).get("title", "")), n])
	if OS.has_feature("web"):
		print("guide: step %d paid %d" % [i + 1, n])
	sample.request_save("guide")


# ------------------------------------------------------------------ switch on / off, tracking
func set_hidden(on: bool) -> void:
	hidden = on
	if on and track == "guide":
		track = ""
	elif not on and track == "" and not graduated:
		track = "guide"
	sample.request_save("guide")


func default_track() -> String:
	return "guide" if not graduated and not hidden else ""


func set_track(key: String) -> void:
	track = key
	track_mark = mark_of(key)
	sample.request_save("guide")


func mark_of(key: String) -> int:
	if key == "bounty":
		return jh.bounty.main_done + jh.bounty.patrols_done
	if key == "arena":
		return s3.arena.entered_edition
	return 0


## Is the tracked thing finished (-> back to the guide / nothing)?
func track_done(key: String) -> bool:
	if key == "guide":
		return graduated or hidden
	if key == "bounty":
		return jh.bounty.main_done + jh.bounty.patrols_done > track_mark
	if key.begins_with("com:"):
		var o := _offer(key.trim_prefix("com:"))
		return o.is_empty() or String(o["state"]) == "done"
	if key.begins_with("repair:"):
		return sample.is_repaired(key.trim_prefix("repair:"))
	if key == "arena":
		return s3.arena.entered_edition > track_mark
	if key == "disciple":
		return s3.disciple.state == "joined"
	return true


func _offer(kind: String) -> Dictionary:
	for o in jh.com.offers:
		if String(o["kind"]) == kind:
			return o
	return {}


## The objective line (without "目标：") for the tracked item; null before the guide exists (the prologue's own goals).
func objective_text() -> Variant:
	if not active():
		return null
	if track == "":
		return ""
	if track == "guide":
		var i := current()
		return String(step_def(i).get("objective", "")) if i < done.size() else ""
	for tab in tabs():
		for it in tab["items"]:
			if String(it.get("key", "")) == track:
				return String(it.get("obj", it["text"]))
	return ""


## World point the gold minimap arrow points at (null = no arrow).
func track_world() -> Variant:
	if not active() or track == "":
		return null
	return target_of(track)


func _npc_pos(id: String) -> Variant:
	var n = story._npc(id)
	return n.global_position if n != null and n.visible else null


func target_of(key: String) -> Variant:
	if key == "guide":
		match current():
			0:
				return _npc_pos("fox")
			1:
				return sample.trial.board_point()
			2:
				return sample.mouse.global_position if sample.mouse != null else null
			3:
				return _npc_pos("bear")
			4:
				return jh.board_point if not (jh.com.total >= 1) else s3.arena.board_point()
		return null
	if key == "bounty":
		var b := jh.bounty
		if not b.active.is_empty() and String(b.active["state"]) == "accepted" and not b.villains.is_empty():
			return b.villains[0].global_position
		return jh.board_point
	if key.begins_with("com:"):
		var o := _offer(key.trim_prefix("com:"))
		if o.is_empty():
			return jh.board_point
		var ts: Array = jh.com.targets_of(o)
		return ts[0] if not ts.is_empty() else jh.board_point
	if key.begins_with("repair:"):
		var who := {"roof": "mouse", "dorm_old": "dog", "kitchen": "bear"}
		var id := String(who.get(key.trim_prefix("repair:"), ""))
		if id == "mouse":
			return sample.mouse.global_position if sample.mouse != null else null
		return _npc_pos(id)
	if key == "arena":
		return s3.arena.board_point()
	if key == "disciple":
		var dc := s3.disciple
		if not sample.is_repaired("dorm_old"):
			return _npc_pos("dog")
		if dc.npc.visible:
			return dc.npc.global_position
		return null
	return null


# ------------------------------------------------------------------ the 任务面板's content (from the real state)
## [{id, name, items: [{text, state: done|current|open|locked|info, key, action: track|toggle|"", obj}]}]
func tabs() -> Array:
	var names: Array = data.get("board", {}).get("tabs", [])
	var out := []
	for i in TABS.size():
		out.append({"id": TABS[i], "name": String(names[i]) if i < names.size() else TABS[i], "items": call("_tab_" + TABS[i])})
	return out


func _yn(v: bool) -> String:
	return ui("yes") if v else ui("no")


func _tab_guide() -> Array:
	var out := []
	var cur := current()
	for i in STEP_IDS.size():
		var d := step_def(i)
		var mark := ui("yes") if paid[i] else ("▶" if i == cur else "·")
		var t := bt("step") % [mark, i + 1, String(d["title"]), int(d["reward"])]
		t += "\n" + bt("step_detail") % [String(d["todo"]), String(d["place"])]
		var prog := ""
		if i == 0:
			prog = ui("progress_combat") % [_yn(dodged), _yn(countered), _yn(spar_won)]
		elif i == 4:
			prog = ui("progress_board") % [_yn(jh.com.total >= 1), _yn(arena_seen)]
		if prog != "" and not paid[i]:
			t += "\n" + bt("step_progress") % prog
		var st := "done" if paid[i] else ("current" if i == cur else "open")
		out.append({"text": t, "state": st, "key": "guide", "action": "" if paid[i] or hidden else "track",
			"obj": String(d["objective"])})
	out.append({"text": bt("graduate_item") % [ui("yes") if graduated else "·", int(data.get("graduate_reward", 10))]
		+ "\n" + bt("graduate_detail") % String(data.get("book", "")), "state": "done" if graduated else "info", "key": "", "action": ""})
	if not graduated:
		out.append({"text": (bt("toggle_on") if hidden else bt("toggle_off")) + "\n" + bt("toggle_detail"), "state": "info", "key": "",
			"action": "toggle"})
	return out


func _tab_bounty() -> Array:
	var b := jh.bounty
	var out := []
	var r := Jianghu.rules()
	if not b.active.is_empty():
		var d := b.current_def()
		var won := String(b.active["state"]) == "won"
		var t := bt("bounty_won") % [b.active_name(), b.reward_coins(), b.reward_fame()] if won else \
			bt("bounty_taken") % [b.active_name(), String(d.get("place", "")), b.reward_coins(), b.reward_fame()]
		out.append({"text": t, "state": "current", "key": "bounty", "action": "track", "obj": t.get_slice(" · ", 0) + (" · 回榜交榜" if won else " · " + String(d.get("place", "")))})
	var off := b.offer()
	if not off.is_empty() and b.active.is_empty():
		var t2 := ""
		if String(off["type"]) == "main":
			var d2: Dictionary = b.defs[int(off["index"])]
			t2 = bt("bounty_offer") % [String(d2["name"]), String(d2["place"]), int(d2["coins"]), int(d2["fame"])]
		else:
			t2 = bt("bounty_patrol") % int(r.get("patrol", {}).get("coins", 15))
		out.append({"text": t2 + "\n" + bt("bounty_where"), "state": "open", "key": "bounty", "action": "track", "obj": t2.get_slice(" · ", 0) + " · 去告示榜接榜"})
	if b.active.is_empty() and off.is_empty():
		var nd := jh.day_no(b.first_ready()) if b.main_done < b.defs.size() else jh.day_no(b.next_patrol_post())
		out.append({"text": bt("bounty_next") % nd, "state": "locked", "key": "", "action": ""})
	out.append({"text": bt("bounty_done") % [b.main_done, b.patrols_done], "state": "info", "key": "", "action": ""})
	return out


func _tab_com() -> Array:
	var c := jh.com
	var out := []
	if c.offers.is_empty():
		out.append({"text": bt("com_none"), "state": "locked", "key": "", "action": ""})
	for o in c.offers:
		var k := String(o["kind"])
		var st := String(o["state"])
		var status := bt("com_open")
		var state := "open"
		if st == "done":
			status = bt("com_done")
			state = "done"
		elif st == "taken" and c.complete(o):
			status = bt("com_ready")
			state = "current"
		elif st == "taken":
			status = bt("com_taken") % c.step_text(o)
			state = "current"
		var kd: Dictionary = jh.data.get("kinds", {}).get(k, {})
		var t := bt("com_item") % [c.kind_name(k), String(kd.get("client", "")) + "托付", status, c.reward(k)]
		out.append({"text": t, "state": state, "key": "com:" + k, "action": "" if st == "done" else "track",
			"obj": "委托：%s · %s" % [c.kind_name(k), status]})
	var every := maxi(1, int(Jianghu.crules().get("estate_every", 5)))
	out.append({"text": bt("com_total") % [c.total, c.total % every, every, every], "state": "info", "key": "", "action": ""})
	return out


func _tab_repair() -> Array:
	var out := []
	var names: Dictionary = data["board"]["repair_names"]
	var who: Dictionary = data["board"]["repair_who"]
	for id in Economy.REPAIRS:
		if sample.is_repaired(id):
			out.append({"text": bt("repair_done") % String(names[id]), "state": "done", "key": "", "action": ""})
		else:
			var t := bt("repair_item") % [String(names[id]), String(who[id][0]), String(who[id][1]), Economy.price(id),
				int(Economy.repair(id).get("estate", 0))]
			out.append({"text": t, "state": "open", "key": "repair:" + id, "action": "track", "obj": "修缮：%s · 找%s" % [names[id], who[id][0]]})
	return out


func _tab_arena() -> Array:
	var ar := s3.arena
	var out := []
	var t := ""
	if ar.can_enter():
		t = bt("arena_open") % Economy.arena_int("fee")
	elif ar.open_now():
		t = bt("arena_entered") % ar.next_day()
	else:
		t = bt("arena_next") % [ar.next_day(), Economy.arena_int("fee")]
	out.append({"text": t, "state": "current" if ar.can_enter() else "open", "key": "arena", "action": "track",
		"obj": "比武大会：第 %d 天午时 · 村口擂台" % ar.next_day() if not ar.can_enter() else "比武大会：今天报名中 · 村口擂台"})
	out.append({"text": bt("arena_titles") % [ar.wins.size() + ar.hard_wins.size(), ar.hard_wins.size(), Economy.arena_int("first_win_coins"),
		Economy.arena_int("first_win_fame")], "state": "info", "key": "", "action": ""})
	return out


func _tab_disciple() -> Array:
	var dc := s3.disciple
	var out := []
	match dc.state:
		"joined":
			out.append({"text": bt("disciple_joined") % [dc.job_name(dc.job_today()), Economy.disciple_int("upkeep")], "state": "done", "key": "", "action": ""})
		"waiting":
			out.append({"text": bt("disciple_waiting"), "state": "current", "key": "disciple", "action": "track", "obj": "收徒：去山门外见少年"})
		"coming":
			out.append({"text": bt("disciple_coming"), "state": "locked", "key": "", "action": ""})
		_:
			var need := Economy.disciple_int("need_fame")
			var dorm := sample.is_repaired(String(Economy.disciple().get("need_repair", "dorm_old")))
			var t := bt("disciple_need") % [bt("disciple_dorm_ok") if dorm else bt("disciple_dorm_no"), s3.value("fame"), need,
				s3.value("estate"), Economy.disciple_int("need_estate"), need]
			out.append({"text": t, "state": "open", "key": "disciple", "action": "track", "obj": "收徒：整理旧弟子房，名望或家业到 %d 格" % need})
	return out


# ------------------------------------------------------------------ captions, the spar hint
func _build_ui() -> void:
	caption_layer = CanvasLayer.new()
	caption_layer.name = "GuideCaptions"
	caption_layer.layer = 15
	main.add_child(caption_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	caption_layer.add_child(root)
	caption_label = Label.new()
	caption_label.add_theme_font_size_override("font_size", 14)
	caption_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	caption_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	caption_label.add_theme_constant_override("shadow_offset_x", 1)
	caption_label.add_theme_constant_override("shadow_offset_y", 1)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.modulate.a = 0.0
	root.add_child(caption_label)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -26
	hint_label.offset_bottom = -10
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.text = String(data.get("spar_hint", ""))
	hint_label.visible = false
	root.add_child(hint_label)


## A line in the middle of the screen (fade in, hold, fade out; ~caption_seconds), one after the other. Never holds play.
func caption(text: String) -> void:
	captions.append(text)
	_caption_queue.append(text)
	if _caption_tween == null or not _caption_tween.is_valid() or not _caption_tween.is_running():
		_next_caption()


func _next_caption() -> void:
	if _caption_queue.is_empty():
		return
	caption_label.text = _caption_queue.pop_front()
	var secs := float(data.get("caption_seconds", 2.0))
	_caption_tween = caption_label.create_tween()
	_caption_tween.tween_property(caption_label, "modulate:a", 1.0, 0.3)
	_caption_tween.tween_interval(maxf(0.2, secs - 0.8))
	_caption_tween.tween_property(caption_label, "modulate:a", 0.0, 0.5)
	_caption_tween.tween_callback(_next_caption)


func caption_showing() -> bool:
	return caption_label.modulate.a > 0.01


## Step 1's key hint while a 师兄 spar runs (and the guide is on that step).
func _update_hint() -> void:
	var want := _in_senior_spar() and started and not hidden and not paid[0] and current() == 0
	if want != hint_label.visible:
		hint_label.visible = want
		if want:
			main.hud.hide_hint_now()


# ------------------------------------------------------------------ 门派簿
func book_entries() -> Array:
	return [String(data.get("book", ""))] if graduated else []


# ------------------------------------------------------------------ saving
static func defaults() -> Dictionary:
	return {"started": false, "done": [false, false, false, false, false], "paid": [false, false, false, false, false],
		"graduated": false, "hidden": bool(load_data().get("hidden_default", false)), "dodged": false, "countered": false,
		"spar_won": false, "bear_talked": false, "arena_seen": false, "track": "", "track_mark": 0}


func capture() -> Dictionary:
	return {"started": started, "done": done.duplicate(), "paid": paid.duplicate(), "graduated": graduated, "hidden": hidden,
		"dodged": dodged, "countered": countered, "spar_won": spar_won, "bear_talked": bear_talked, "arena_seen": arena_seen,
		"track": track, "track_mark": track_mark}


func restore(d: Dictionary) -> void:
	started = bool(d["started"])
	done = (d["done"] as Array).map(func(x): return bool(x))
	paid = (d["paid"] as Array).map(func(x): return bool(x))
	graduated = bool(d["graduated"])
	hidden = bool(d["hidden"])
	dodged = bool(d["dodged"])
	countered = bool(d["countered"])
	spar_won = bool(d["spar_won"])
	bear_talked = bool(d["bear_talked"])
	arena_seen = bool(d["arena_seen"])
	track = String(d["track"])
	track_mark = int(d["track_mark"])
	_intro_pending = false


## An older save (version < 5): the guide starts empty; for a save made after the prologue it is already running and every
## step whose condition the save already meets counts as done AND paid - without coins (no money for old players).
static func upgrade_state(st: Dictionary) -> Dictionary:
	var d := defaults()
	var smp: Dictionary = st.get("sample", {}) if st.get("sample") is Dictionary else {}
	if not bool(smp.get("unlocked", false)):
		return d
	var flags: Dictionary = st.get("story", {}).get("flags", {}) if st.get("story") is Dictionary else {}
	var com_total := 0
	var jh_st = st.get("jianghu")
	if jh_st is Dictionary and jh_st.get("com") is Dictionary:
		com_total = int(jh_st["com"].get("total", 0))
	var met := [bool(flags.get("spar_won", false)),
		["bronze", "silver", "gold"].any(func(t): return bool(flags.get("trial_" + t, false))),
		bool(flags.get("repair_roof", false)),
		bool(flags.get("repair_kitchen", false)),     # (the 厨娘 talk is not in old saves: a repaired kitchen means she did)
		com_total >= 1]
	d["started"] = true
	d["done"] = met.duplicate()
	d["paid"] = met.duplicate()
	d["graduated"] = met.all(func(x): return x)
	d["track"] = "" if d["graduated"] else "guide"
	return d


static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "missing section guide"
	for k in ["started", "graduated", "hidden", "dodged", "countered", "spar_won", "bear_talked", "arena_seen"]:
		if not (d.get(k) is bool):
			return "bad guide." + k
	for k in ["done", "paid"]:
		if not (d.get(k) is Array) or (d[k] as Array).size() != STEP_IDS.size() or not (d[k] as Array).all(func(x): return x is bool):
			return "bad guide." + k
	if not (d.get("track") is String) or not SaveGame._type_ok(d.get("track_mark"), "num"):
		return "bad guide.track"
	for i in STEP_IDS.size():
		if bool(d["paid"][i]) and not bool(d["done"][i]):
			return "bad guide.paid"
	return ""
