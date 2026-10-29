class_name Story
extends Node
## 打磨 v1 (script v4): the opening is the bucket filling up and overflowing (S1-醒来: bucket_fill -> bucket_overflow ->
## sit_up -> get_up); stage 0 then has two objectives: 擦干地上的水 (take the rag in the corner - S1-抹布 -, E at the
## puddle three times - the third plays S1-擦水渍, which pours the bucket out) and 看看桌上的字条 (the note only after
## wiping). E at the puddle without the rag shows ui.need_rag. The wardrobe (S1-衣柜) opens a panel with the clothes.
## 序章 v1: the prologue of region 1 as a small state machine driven by data/story.json (every line, choice and step)
## and data/objectives.json (the objective texts + star targets). Script v3 (室内图进游戏 v1): the opening happens in
## the dorm room (asleep in bed -> the drip on his forehead -> sitting up -> out of bed), 师父 / 厨娘 are inside the hall /
## kitchen (scripts/interiors.gd), optional lines of every room (interactables with a "room").
##   stage 0      opening conversation (S1-醒来, no objective yet), then "看看桌上的字条" until S1-字条 is read
##   stage 1..8   objective N of objectives.json is shown; talking / fighting / the puzzle moves it on
##   stage 9      序章完成 (after the ending; the player may keep walking around)
## Talk rules per NPC and stage (gating: 厨娘 before 师父 -> 任务前, "之后" lines), auto scenes (opening, bandit
## opening lines, entering the grove, finding the tiles), the spar of step 2 (mandatory, both results go on), the
## bandits of step 6 (absent before step 5 is done, intro -> fight, lose -> respawn + S6-失败 with both bandits back,
## win -> gone for good), walking bubbles after step 7 (each once), the stele puzzle (青石 -> 苔石 -> 裂石), the
## ending (门派簿 -> 师父 alone -> 序章 · 完 -> 回到启动画面), and the 门派簿 key B afterwards.
## While a conversation is on screen the player and every fighter stand still (Combat.story_hold); time of day goes on.
## enter_sandbox(): the story layer off (bandits on the road, 师兄 invites at once) - only for the older test suites,
## which check walking / collisions / combat mechanics, like their existing bandits_enabled = false switch.

signal scene_started(id: String)
signal scene_finished(id: String)
signal stage_changed(stage: int)

const DATA_PATH := "res://data/story.json"
const TITLE_SCENE := "res://scenes/title.tscn"
const INTERACT_DIST := 44.0

var main: Node
var data: Dictionary
var dialogue: Dialogue
var sect_book: SectBook
var prologue_end: PrologueEnd
var fx: StoryFx
var sandbox := false
var stage := 0
var flags: Dictionary = {}
var busy := false                 # a scene is running
var current_scene := ""
var played: Array[String] = []    # every scene id in the order it started (tests)
var book_unlocked := false
var _run_id := 0
var _after: Array = []            # actions to run when the running scene has closed

# step 2
var story_spar_pending := false
# walking bubbles
var bubble_done: Array[bool] = []
var _bubble_index := -1
var _bubble_left := 0.0
var bubbles_shown: Array[String] = []
# puzzle
var stones: Dictionary = {}       # type -> {pos: Vector2, sprite: Sprite2D}
var stele_pos := Vector2.ZERO
var stash_pos := Vector2.ZERO
var gate_sprite: Sprite2D
var gate_shapes: Array[CollisionShape2D] = []
var gate_halves: Array[Sprite2D] = []
var progress := 0
var errors := 0
var hint_given := false
var solved := false
var bows: Array[String] = []      # every bow (tests)
# 打磨 v1: wiping the floor
var wipes := 0
var hints_shown: Array[String] = []   # need_rag hints (tests)
var wardrobe_panel: WardrobePanel


func _init() -> void:
	name = "Story"


func setup(m: Node) -> void:
	main = m
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Story: cannot read " + DATA_PATH)
		data = {"scenes": {}}
	if m.get("sample") != null:
		m.sample.merge_story_data(data)     # 两条路小样 v1: its scenes / 老周 join the tables (story.json untouched)
	if m.get("step3") != null:
		m.step3.merge_story_data(data)      # 第③步: opponents, 少年 / 师弟, their scenes (data/step3.json)
	if m.get("jianghu") != null:
		m.jianghu.merge_story_data(data)    # 第④步第一批: villains, 委托 scenes (data/jianghu.json)
	if m.get("guide") != null:
		m.guide.merge_story_data(data)      # 新手指引 v1: 师父's line after the prologue (data/guide.json)
	if not sandbox:
		Skills.merge_story_data(data)       # 武学 (A): 师父传功 / 打坐 scenes (data/skills.json)
	if m.get("farm") != null:
		m.farm.merge_story_data(data)       # 经营 (B): 厨娘's menu, 师弟's 种地 (data/farm.json; sample.json / step3.json untouched)
	dialogue = Dialogue.new()
	m.add_child(dialogue)
	dialogue.setup(data)
	sect_book = SectBook.new()
	m.add_child(sect_book)
	prologue_end = PrologueEnd.new()
	m.add_child(prologue_end)
	prologue_end.setup(data.get("ui", {}))
	fx = StoryFx.new()
	m.add_child(fx)
	wardrobe_panel = WardrobePanel.new()
	m.add_child(wardrobe_panel)
	wardrobe_panel.setup(ui("wardrobe_title"))
	bubble_done.resize(data.get("bubbles", {}).get("lines", []).size())
	bubble_done.fill(false)
	# puzzle pieces from the map (map_data.json objects / colliders)
	for o in m.data["objects"]:
		var t: String = o["type"]
		var tex_size := Vector2(32, 32)
		var tex: Texture2D = load("res://assets/map/" + o["tex"])
		if tex:
			tex_size = tex.get_size()
		var base := Vector2(float(o["x"]) + tex_size.x * 0.5, float(o["sort_y"]))
		if t.begins_with("stone_"):
			stones[t] = {"pos": base}
		elif t == "stele":
			stele_pos = base
		elif t == "tile_stash":
			stash_pos = base
	for s in m.world.get_children():
		if s is Sprite2D:
			var t: String = s.get_meta("type", "")
			if t.begins_with("stone_") and stones.has(t):
				stones[t]["sprite"] = s
			elif t == "bamboo_gate":
				gate_sprite = s
	for cs in m.solids.get_children():
		if cs.get_meta("kind", "") == "bamboo_gate":
			gate_shapes.append(cs)
	var c: Combat = m.combat
	c.spar_closed.connect(_on_spar_closed)
	c.bandits_cleared_signal.connect(_on_bandits_cleared)
	c.respawned.connect(_on_respawned)


## Story mode: bandits off the road, opening conversation.
func start() -> void:
	main.interiors.start_opening()
	var c: Combat = main.combat
	c.bandits_active = false
	c.story_no_leash = true
	c.revive_bandits_on_death = true
	c.set_bandits_present(false)
	play(String(data.get("opening_scene", "S1-醒来")))


## The story layer off, for the older suites (see the class comment). Objective 1 shown, bandits on the road.
func enter_sandbox() -> void:
	sandbox = true
	_run_id += 1
	busy = false
	current_scene = ""
	_after.clear()
	dialogue.close()
	_hold(false)
	var c: Combat = main.combat
	c.bandits_active = true
	c.story_no_leash = false
	c.revive_bandits_on_death = false
	c.set_bandits_present(true)
	stage = 1
	main.objectives.reset()
	main.interiors.enter_sandbox()
	main.hud.show_hint()


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


func scene(id: String) -> Array:
	return data["scenes"].get(id, [])


func set_stage(n: int, step := "") -> void:
	stage = n
	if step != "":
		main.objectives.set_step(step)
	else:
		main.objectives.set_stage(n)
	if OS.has_feature("web"):
		print("story: stage %d" % n)
	stage_changed.emit(n)


# ------------------------------------------------------------------ scenes
func in_conversation() -> bool:
	return busy


func _hold(on: bool) -> void:
	var c: Combat = main.combat
	c.story_hold = on
	var p: Player = main.player
	if on:
		p.input_enabled = false
		p.velocity = Vector2.ZERO
		main.hud.hide_hint_now()
	else:
		p.input_enabled = not (c.spar_state == "choosing" or c.spar_state == "result" or c.player_dead)


## Plays a scene (non-blocking for the caller; the scene runs as a coroutine).
func play(id: String) -> void:
	if not data["scenes"].has(id):
		push_error("Story: no scene " + id)
		return
	_play(id)


func _play(id: String) -> void:
	_run_id += 1
	var token := _run_id
	busy = true
	current_scene = id
	played.append(id)
	if OS.has_feature("web"):
		print("story: dialogue %s" % id)
	scene_started.emit(id)
	_hold(true)
	await _run_entries(scene(id), token)
	if token != _run_id:
		return
	dialogue.close()
	busy = false
	current_scene = ""
	if wardrobe_panel.is_open:
		_close_wardrobe()
	_hold(false)
	scene_finished.emit(id)
	var after := _after.duplicate()
	_after.clear()
	for a in after:
		_do_after(a)


func _run_entries(entries: Array, token: int) -> void:
	var i := 0
	while i < entries.size():
		if token != _run_id:
			return
		var e: Dictionary = entries[i]
		var next: Dictionary = entries[i + 1] if i + 1 < entries.size() else {}
		if e.has("choice"):
			i += 1
			continue     # already handled with the line before it
		if e.has("text") and e.get("show", true):
			if next.has("choice"):
				# 第③步: an option can be hidden ("show_if") or greyed ("grey_unless") by a Step3 condition
				var shown_opts: Array = (next["choice"] as Array).filter(func(o): return _option_ok(o, "show_if"))
				var opts: Array = shown_opts.map(func(o): return o["text"])
				var off: Array = shown_opts.map(func(o): return not _option_ok(o, "grey_unless"))
				await dialogue.say(e, opts, off)
				if token != _run_id:
					return
				var pick: Dictionary = shown_opts[clampi(dialogue.last_choice, 0, opts.size() - 1)]
				flags["choice_" + current_scene] = dialogue.last_choice
				await _run_entries(pick.get("then", []), token)
			else:
				await dialogue.say(e)
		if token != _run_id:
			return
		if e.has("do"):
			await _do(e, token)
		i += 1


## 第③步: an option's condition (key "show_if" / "grey_unless" -> Step3.option_ok); true when it has none.
func _option_ok(o: Dictionary, key: String) -> bool:
	if not o.has(key):
		return true
	if String(o[key]).begins_with("fm_") and main.get("farm") != null:
		return main.farm.option_ok(String(o[key]))      # 经营 (B): 种地 only once the farm is open
	if String(o[key]).begins_with("jh_") and main.get("jianghu") != null:
		return main.jianghu.option_ok(String(o[key]))
	var s3 = main.get("step3")
	return s3 != null and s3.option_ok(String(o[key]))


## Actions inside a scene. Some wait (门派簿, walking out, 序章 · 完); some run after the scene has closed.
func _do(e: Dictionary, token: int) -> void:
	match String(e["do"]):
		"set_stage":
			set_stage(int(e["stage"]), String(e.get("step", "")))
		"set_step":
			main.objectives.set_step(String(e["step"]))
			if OS.has_feature("web"):
				print("story: step %s" % e["step"])
		"set_flag":
			flags[String(e["flag"])] = true
		"show_key_hint":
			_after.append("show_key_hint")
		"start_story_spar":
			_after.append("start_story_spar")
		"spar_invite":
			_after.append("spar_invite")
		"bandits_appear":
			main.combat.set_bandits_present(true)
		"bandits_fight":
			_after.append("bandits_fight")
		"get_item":
			flags["item_" + String(e["item"])] = true
			main.hud.show_toast(ui("get_item") % String(e["item"]))
		"open_sect_book":
			dialogue.close()
			await open_book(true)
		"walk_out":
			dialogue.close()
			await _walk_out()
		"prologue_end":
			dialogue.close()
			await _prologue_end(token)
		# v4 opening (scripts/interiors.gd acts the 画面 lines out)
		"bucket_fill":
			dialogue.close()
			await main.interiors.bucket_fill()
		"bucket_overflow":
			dialogue.close()
			await main.interiors.bucket_overflow()
		"take_rag":
			flags["has_rag"] = true
			main.interiors.take_rag()
		"wipe_done":
			await main.interiors.wipe_to(3)
			flags["floor_wiped"] = true
		"pour_bucket":
			dialogue.close()
			await main.interiors.pour_bucket()
		"open_wardrobe":
			main.interiors.set_wardrobe_open(true)
			wardrobe_panel.open()
		"close_wardrobe":
			_close_wardrobe()
		"sit_up":
			await main.interiors.sit_up()
		"get_up":
			dialogue.close()
			await main.interiors.get_up()
		_:
			var smp = main.get("sample")
			var s3 = main.get("step3")
			if smp != null and smp.handles(String(e["do"])):
				await smp.do_action(e, token)     # 两条路小样 v1: repair / trial_start
			elif s3 != null and s3.handles(String(e["do"])):
				await s3.do_action(e, token)      # 第③步: signing up, 收下 / 再想想, jobs, 陪练
			elif main.get("jianghu") != null and main.jianghu.handles(String(e["do"])):
				await main.jianghu.do_action(e, token)   # 第④步第一批: the board's menus, 委托 steps, villains engage
			elif main.get("skills") != null and main.skills.handles(String(e["do"])):
				main.skills.do_action(e, token)          # 武学 (A): skills_assign / skills_teach / skills_meditate
			elif main.get("farm") != null and main.farm.handles(String(e["do"])):
				await main.farm.do_action(e, token)      # 经营 (B): 厨娘's menus, planting, 师弟's 派活 with 种地
			else:
				push_warning("Story: unknown action " + String(e["do"]))


func _do_after(a: String) -> void:
	var c: Combat = main.combat
	match a:
		"show_key_hint":
			main.hud.show_hint()
		"start_story_spar":
			story_spar_pending = true
			c.start_spar()
		"spar_invite":
			if c.spar_state == "none" and not c.blocks_interaction():
				c.open_choice()
		"bandits_fight":
			flags["bandits_intro_done"] = true
			c.bandits_active = true
			c.engage_bandits()


# ------------------------------------------------------------------ talking / looking
## Scene an NPC has to say right now (talk rules of story.json; "" = nothing -> no prompt).
func talk_scene(npc_id: String) -> String:
	if sandbox:
		return "spar" if npc_id == main.combat.spar_fighter.id else ""
	var sk = main.get("skills")
	if sk != null:
		var ks: String = sk.talk_scene(npc_id)       # 武学 (A): 师父传功 (only 师父, only when a skill is due)
		if ks != "":
			return ks
	var jh = main.get("jianghu")
	if jh != null:
		var js: String = jh.talk_scene(npc_id)       # 第④步第一批: 委托 steps (茶摊老板 / 老伯), villagers after 名望 5
		if js != "":
			return js
	var s3 = main.get("step3")
	if s3 != null:
		var s3s: String = s3.talk_scene(npc_id)      # 第③步 (only after the prologue): 少年 / 师弟, 老伯's new line
		if s3s != "":
			return s3s
	var smp = main.get("sample")
	if smp != null:
		var ss: String = smp.talk_scene(npc_id)      # 两条路小样 v1 (only after the prologue)
		if ss != "":
			return ss
	for rule in data.get("talk", {}).get(npc_id, []):
		var st: Array = rule["stage"]
		if stage < int(st[0]) or stage > int(st[1]):
			continue
		if rule.has("unless") and flags.get(String(rule["unless"]), false):
			continue
		return String(rule["scene"])
	return ""


func _stage_ok(spec: Dictionary) -> bool:
	if spec.has("if") and not flags.get(String(spec["if"]), false):
		return false
	if spec.has("unless") and flags.get(String(spec["unless"]), false):
		return false
	if not spec.has("stage"):
		return true
	var st: Array = spec["stage"]
	return stage >= int(st[0]) and stage <= int(st[1])


func _close_wardrobe() -> void:
	wardrobe_panel.close()
	main.interiors.set_wardrobe_open(false)


## 擦水渍: E at the puddle. Without the rag: the hint (UI text ui.need_rag). With it: one wipe (the puddle shrinks one
## ring); the third plays S1-擦水渍 (the last ring, pouring the bucket out, -> 看看桌上的字条).
func wipe() -> void:
	if not flags.get("has_rag", false):
		hints_shown.append(ui("need_rag"))
		main.hud.show_toast(ui("need_rag"))
		if OS.has_feature("web"):
			print("story: hint need_rag")
		return
	wipes += 1
	if OS.has_feature("web"):
		print("story: wipe %d" % wipes)
	if wipes >= 3:
		play("S1-擦水渍")
	else:
		main.interiors.wipe_to(wipes)


## World points the minimap must not cover (it fades when one is under it): visible NPCs + things E works on now.
func poi_points() -> Array:
	var out := []
	for n in main.npcs:
		if n.visible:
			out.append(n.global_position)
	if sandbox:
		return out
	for it in data.get("interactables", []):
		if _stage_ok(it) and not _hidden(it):
			out.append(_thing_pos(it))
	var smp = main.get("sample")
	if smp != null:
		out.append_array(smp.poi_points())
	var s3 = main.get("step3")
	if s3 != null:
		out.append_array(s3.poi_points())
	var jh = main.get("jianghu")
	if jh != null:
		out.append_array(jh.poi_points())
	if main.get("farm") != null:
		out.append_array(main.farm.poi_points())     # 经营 (B): the plots, the glowing gathering spots
	return out


## 两条路小样 v1: a room thing that went with a repair (the dorm bucket) is no longer looked at.
func _hidden(it: Dictionary) -> bool:
	var smp = main.get("sample")
	return smp != null and smp.hides_thing(String(it["id"]))


## What E would do right now: {kind: npc|thing|stone, prompt, prompt_pos, ...} or {} (nothing near / busy).
func interaction_target() -> Dictionary:
	if busy or _modal_open() or main.combat.blocks_interaction() or main.interiors.transitioning:
		return {}
	var sch0 = main.get("schedule")
	if sch0 != null and sch0.blocks_prompts():
		return {}      # 坐下与人物作息 v1: sitting / the 等到天亮 night
	var p: Vector2 = main.player.global_position
	var best: Dictionary = {}
	var bd := INF
	for n in main.npcs:
		if not n.visible:
			continue
		var d: float = n.global_position.distance_to(p)
		if d > INTERACT_DIST or d >= bd:
			continue
		var sc := talk_scene(n.id)
		if sc == "":
			continue
		bd = d
		best = {"kind": "npc", "npc": n, "scene": sc, "prompt": ui("prompt_talk"), "prompt_pos": n.head_position()}
	if sandbox:
		return best
	for it in data.get("interactables", []):
		if not _stage_ok(it) or _hidden(it):
			continue
		var pos := _thing_pos(it)
		var d := pos.distance_to(p)
		if d > float(it.get("radius", 32)) or d >= bd:
			continue
		bd = d
		var pk := String(it.get("prompt", ""))
		var pr := "prompt_" + pk if pk != "" else "prompt_look"
		var smp = main.get("sample")
		var sc := String(it["scene"]) if smp == null else String(smp.thing_scene(String(it["id"]), String(it["scene"])))
		best = {"kind": "thing", "id": it["id"], "scene": sc, "action": String(it.get("action", "")),
			"prompt": ui(pr), "prompt_pos": pos + Vector2(0, -30)}
	var smp2 = main.get("sample")
	if smp2 != null:
		var st: Dictionary = smp2.interaction_target(p, bd)    # the trial board
		if not st.is_empty():
			bd = p.distance_to(smp2.trial.board_point())
			best = st
	var s3 = main.get("step3")
	if s3 != null:
		var t3: Dictionary = s3.interaction_target(p, bd)     # 第③步: the 比武大会 notice board
		if not t3.is_empty():
			bd = float(t3["dist"])
			best = t3
	var jh = main.get("jianghu")
	if jh != null:
		var tj: Dictionary = jh.interaction_target(p, bd)    # 第④步第一批: the 江湖告示榜, 委托 things
		if not tj.is_empty():
			bd = float(tj["dist"])
			best = tj
	var fm = main.get("farm")
	if fm != null:
		var tf: Dictionary = fm.interaction_target(p, bd, best)    # 经营 (B): the well (打水), the plots, gathering spots
		if not tf.is_empty():
			bd = float(tf["dist"])
			best = tf
	var sch = main.get("schedule")
	if sch != null:
		var ts: Dictionary = sch.interaction_target(p, bd, best)    # 坐下与人物作息 v1: 师兄 asleep in his bed
		if not ts.is_empty():
			bd = float(ts["dist"])
			best = ts
	if stage == 7 and not solved:
		var pz: Dictionary = data.get("puzzle", {})
		for id in stones:
			if fx.glows.has(id):
				continue      # already lit
			var pos: Vector2 = stones[id]["pos"]
			var d := pos.distance_to(p)
			if d > float(pz.get("radius", 30)) or d >= bd:
				continue
			bd = d
			best = {"kind": "stone", "id": id, "prompt": ui("prompt_bow"), "prompt_pos": pos + Vector2(0, -26)}
	if best.is_empty() and main.get("seats") != null:
		best = main.seats.interaction_target(p, best)    # 坐下与人物作息 v1: 按 E 坐下 (only when nothing else is in reach)
	return best


func _thing_pos(it: Dictionary) -> Vector2:
	if it.has("room"):
		var room := String(it["room"])
		if it.has("item"):
			return main.interiors.anchor(room, String(it["item"]))
		var lp: Array = it["pos"]
		return main.interiors.world_point(room, Vector2(lp[0], lp[1]))
	if it.has("object"):
		return stele_pos + Vector2(0, 8) if it["object"] == "stele" else stash_pos
	var a: Array = it["pos"]
	return Vector2(a[0], a[1])


func interact() -> bool:
	var t := interaction_target()
	if t.is_empty():
		return false
	match t["kind"]:
		"npc":
			var n: Npc = t["npc"]
			if t["scene"] == "spar":
				main.combat.open_choice()
				return true
			n.face_towards(main.player.global_position)
			main.player.facing = CharSheet.dir_from_vector(n.global_position - main.player.global_position, main.player.facing)
			play(t["scene"])
			scene_finished.connect(func(_id): n.face(n.home_dir), CONNECT_ONE_SHOT)
		"thing":
			if t.get("action", "") == "wipe":
				wipe()
			else:
				play(t["scene"])
		"stone":
			bow(t["id"])
		"step3":
			main.step3.interact(t)        # 第③步: the 比武大会 notice board
		"jianghu":
			main.jianghu.interact(t)      # 第④步第一批: the 江湖告示榜, a glowing spot, a fence gap, the chick
		"farm":
			main.farm.interact(t)         # 经营 (B)
		"schedule":
			if t.get("id", "") == "seat":
				main.seats.sit(String(t["seat"]))    # 坐下与人物作息 v1
			else:
				main.schedule.interact(t)            # 师兄's dream line
	return true


func _modal_open() -> bool:
	return sect_book.is_open or prologue_end.is_open


# ------------------------------------------------------------------ the stele puzzle
func _order() -> Array:
	return data.get("puzzle", {}).get("order", [])


## 拜一拜: the right stone lights up and a gust carries leaves to the next one; a wrong one puts every light out.
func bow(id: String) -> void:
	bows.append(id)
	var order := _order()
	var pz: Dictionary = data.get("puzzle", {})
	if progress < order.size() and order[progress] == id:
		progress += 1
		fx.set_glow(id, stones[id]["pos"])
		var from: Vector2 = stones[id]["pos"]
		if progress < order.size():
			fx.wind(from, stones[order[progress]]["pos"])
		else:
			fx.wind(from, gate_center())
			_solve()
	else:
		errors += 1
		progress = 0
		fx.clear_glows()
		fx.chaos(stones[id]["pos"])
		play(String(pz.get("wrong_scene")))
		if errors >= int(pz.get("hint_after_errors", 3)) and not hint_given:
			hint_given = true
			scene_finished.connect(func(_id): play(String(pz.get("hint_scene"))), CONNECT_ONE_SHOT)


func gate_center() -> Vector2:
	if gate_sprite == null:
		return stele_pos
	return gate_sprite.position + Vector2(gate_sprite.texture.get_width() * 0.5, -24)


func _solve() -> void:
	solved = true
	flags["puzzle_solved"] = true
	var t := get_tree().create_timer(1.3, false)
	t.timeout.connect(part_gate)


## "沙——": the clump parts (two halves slide aside) and stops blocking the way to the stash.
func part_gate() -> void:
	for cs in gate_shapes:
		cs.set_deferred("disabled", true)
	fx.float_text(String(data.get("puzzle", {}).get("parted_text", "")), gate_center())
	if gate_sprite == null or not gate_halves.is_empty():
		return
	var tex := gate_sprite.texture
	var w := tex.get_width()
	for side in [0, 1]:
		var h := Sprite2D.new()
		h.texture = tex
		h.centered = false
		h.region_enabled = true
		h.region_rect = Rect2(side * w / 2, 0, w / 2, tex.get_height())
		h.position = gate_sprite.position + Vector2(side * w / 2, 0)
		h.offset = gate_sprite.offset
		h.set_meta("type", "bamboo_gate_half")
		main.world.add_child(h)
		gate_halves.append(h)
		var tw := h.create_tween()
		tw.set_parallel(true)
		tw.tween_property(h, "position:x", h.position.x + (-13.0 if side == 0 else 13.0), 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(h, "skew", -0.18 if side == 0 else 0.18, 0.8)
	gate_sprite.visible = false
	if OS.has_feature("web"):
		print("story: bamboo parted")


func gate_open() -> bool:
	return not gate_shapes.is_empty() and gate_shapes.all(func(cs): return cs.disabled)


# ------------------------------------------------------------------ triggers (every frame)
func _process(delta: float) -> void:
	_update_bubble(delta)
	if sandbox or busy or _modal_open():
		return
	var c: Combat = main.combat
	if c.player_dead or c.spar_state != "none":
		return
	var p: Vector2 = main.player.global_position
	if stage == 5 and not c.bandits_cleared:
		if _in_bandit_zone(p):
			if not flags.get("bandits_intro_done", false):
				play(String(data["bandits"]["intro_scene"]))
				for b in c.bandits:
					b.face_towards(p)
			elif c.bandits.all(func(b): return b.state == "idle"):
				c.engage_bandits()      # back after a knock-out: they come at once
	elif stage == 7:
		var gr: Array = data["grove"]["rect"]
		if not flags.get("grove_entered", false) and Rect2(gr[0], gr[1], gr[2], gr[3]).has_point(p):
			flags["grove_entered"] = true
			play(String(data["grove"]["enter_scene"]))
		elif solved and not flags.get("tiles_found", false) and p.distance_to(stash_pos) <= float(data["puzzle"].get("stash_radius", 44)):
			play(String(data["puzzle"]["stash_scene"]))


func _in_bandit_zone(p: Vector2) -> bool:
	var bd: Dictionary = data["bandits"]
	for b in main.combat.bandits:
		if b.visible and b.global_position.distance_to(p) <= float(bd.get("trigger_radius", 230)):
			return true
	var r: Array = bd.get("trigger_rect", [0, 0, 0, 0])
	return Rect2(r[0], r[1], r[2], r[3]).has_point(p)


func _on_spar_closed(win: bool) -> void:
	if win:
		flags["spar_won"] = true
	if story_spar_pending:
		story_spar_pending = false
		var rs: Dictionary = data.get("spar_result_scenes", {})
		play(String(rs.get("win" if win else "lose")))


func _on_bandits_cleared() -> void:
	if sandbox or stage != 5:
		return
	play(String(data["bandits"]["win_scene"]))


func _on_respawned() -> void:
	if sandbox or stage != 5:
		return
	play(String(data["bandits"]["lose_scene"]))


# ------------------------------------------------------------------ walking bubbles (after step 7)
func _update_bubble(delta: float) -> void:
	if _bubble_index >= 0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble_index = -1
		return
	var bb: Dictionary = data.get("bubbles", {})
	if sandbox or stage < int(bb.get("stage_from", 7)) or busy:
		return
	var lines: Array = bb.get("lines", [])
	var p: Vector2 = main.player.global_position
	for i in lines.size():
		if bubble_done[i]:
			continue
		var n := _npc(String(lines[i]["who"]))
		if n != null and n.global_position.distance_to(p) <= float(bb.get("radius", 80)):
			bubble_done[i] = true
			_bubble_index = i
			_bubble_left = float(bb.get("seconds", 4.0))
			bubbles_shown.append(String(lines[i]["text"]))
			return


## The bubble on screen: {text, pos} or {}.
func bubble() -> Dictionary:
	var sch = main.get("schedule")
	if sch != null:
		var own: Dictionary = sch.bubble(true)    # 坐下与人物作息 v1: what E just did (a seat's line, the dream line) first
		if not own.is_empty():
			return own
	if _bubble_index < 0:
		var s3 = main.get("step3")
		var sb: Dictionary = s3.bubble() if s3 != null else {}
		if sb.is_empty() and main.get("jianghu") != null:
			sb = main.jianghu.bubble()
		if sb.is_empty() and main.get("schedule") != null:
			sb = main.schedule.bubble()      # 坐下与人物作息 v1: "呼……", the dream line, a seat's line
		return sb
	var l: Dictionary = data["bubbles"]["lines"][_bubble_index]
	var n := _npc(String(l["who"]))
	if n == null:
		return {}
	return {"text": String(l["text"]), "pos": n.head_position(), "who": l["who"]}


func _npc(id: String) -> Npc:
	for n in main.npcs:
		if n.id == id:
			return n
	return null


# ------------------------------------------------------------------ minimap star
func star_world() -> Variant:
	var spec: Variant = main.objectives.star_spec(solved, flags)
	if spec == null:
		return null
	if spec.has("npc"):
		var n := _npc(String(spec["npc"]))
		return n.global_position if n != null else null
	if spec.has("object"):
		return stele_pos if spec["object"] == "stele" else stash_pos
	if spec.has("thing"):
		for it in data.get("interactables", []):
			if it["id"] == spec["thing"]:
				return _thing_pos(it)
		return null
	var a: Array = spec["pos"]
	return Vector2(a[0], a[1])


## 试玩反馈 v1: the gold minimap arrow during the prologue - only for "擦干地上的水": the rag until it is taken, then
## the puddle (the same target as the star). null otherwise (after the prologue the guide drives the arrow).
func prologue_track() -> Variant:
	if not main.objectives.has_current() or String(main.objectives.current().get("id", "")) != "wipe_floor":
		return null
	return star_world()


# ------------------------------------------------------------------ 门派簿 and the ending
func open_book(first := false) -> void:
	book_unlocked = true
	if first:
		flags["book_opened"] = true
	sect_book.open(flags)
	await sect_book.closed


## B: open the book again once it has been opened at the end of the prologue.
func open_book_by_key() -> bool:
	if not book_unlocked or busy or _modal_open() or main.combat.blocks_interaction():
		return false
	main.player.input_enabled = false
	main.combat.story_hold = true
	sect_book.open(flags)
	sect_book.closed.connect(func(): _hold(false), CONNECT_ONE_SHOT)
	return true


func _walk_out() -> void:
	var crane := _npc("crane")
	main.camera_target = crane
	var p: Player = main.player
	p.facing = "down"
	p.sprite.play("walk_down")
	var tw := p.create_tween()
	tw.tween_property(p.sprite, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(p, "global_position", p.global_position + Vector2(0, 36), 1.2)   # towards the hall door
	await tw.finished
	if OS.has_feature("web"):
		print("story: walked out")


## 新手指引 v1 (client 2026-10-24): no 序章 · 完 page and no 回到启动画面 / 继续逛逛 choice any more - the game goes on
## exactly as 继续逛逛 did (camera back, the rabbit outside the hall, Sample.unlock: everything after the prologue opens and
## is saved); a "序章 · 完" caption fades in and out in the middle of the screen (~2 s) and the guide starts.
## 武学与经营 第一批 (B, 方案 第三点五节): it is a transition now - the objective line goes, the whole screen fades to black
## (~1.5 s), the rabbit is put outside the hall facing the yard and the camera comes back while it is black, "序章 · 完"
## fades in and out on the black (~2 s), the screen fades back in (~1.5 s); only then stage 9, Sample.unlock (本钱 +30)
## and the guide (step 1, the gold arrow, 师父's line). No choice box; nobody moves and Esc does not open meanwhile.
var prologue_fade: PrologueFade


func _prologue_end(_token: int) -> void:
	var tr: Dictionary = main.guide.data.get("prologue_transition", {}) if main.get("guide") != null else {}
	if prologue_fade == null:
		prologue_fade = PrologueFade.new()
		main.add_child(prologue_fade)
	prologue_fade.is_open = true
	main.objectives.set_index(-1)        # no objective line / star while it fades (never 序章完成)
	await prologue_fade.fade_to(1.0, float(tr.get("fade_out_seconds", 1.5)))
	main.camera_target = null
	main.player.sprite.modulate.a = 1.0
	if main.interiors.room_at(main.player.global_position) != "":
		main.interiors.place_outside(main.interiors.room_at(main.player.global_position))   # he walked out of the hall
	main.player.facing = "down"
	main.player.sprite.play("idle_down")
	main.indoor_k = 0.0
	if main.get("guide") != null:
		main.guide.caption(main.guide.ui("prologue_caption"))
	await get_tree().create_timer(float(tr.get("caption_seconds", 2.0)), false).timeout
	await prologue_fade.fade_to(0.0, float(tr.get("fade_in_seconds", 1.5)))
	prologue_fade.is_open = false
	set_stage(9)
	flags["prologue_done"] = true
	if main.get("sample") != null:
		main.sample.unlock()      # 两条路小样 v1 opens now (本钱 +30)
	if main.get("guide") != null:
		main.guide.on_prologue_end(false)


func return_to_title() -> void:
	if OS.has_feature("web"):
		print("story: back to title")
	var smp = main.get("sample")
	if smp != null and not sandbox and stage >= 9:
		smp.save_now("prologue_end")      # 两条路小样 v1: 继续游戏 picks up after the prologue
	get_tree().change_scene_to_file(TITLE_SCENE)
