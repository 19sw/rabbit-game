class_name Schedule
extends Node
## 坐下与人物作息 v1 (docs/design/坐下与人物作息-方案-v1.md sections 二 and 三). Numbers / texts: data/schedule.json.
##   who        the people of schedule.json "people" (师父, 师兄, 厨娘, 老伯, 茶摊老板, 村民, 老周). 师弟 (disciple.gd keeps
##              his own day) and the bandits / bounty villains are not in it and never touched.
##   when       asleep while sleep <= hour or hour < wake (across midnight), worked out from DayNight.hour every frame -
##              nothing is saved: a night-time save loads with them gone. Only after the prologue (prologue_first: the
##              same test as Step3.active()); never in the older suites' sandbox.
##   changes    going: "呼……" over the head, the picture fades out in fade_seconds (a ghost copy fades; the person is
##              gone - no prompt, no collision, no minimap star / arrow - at once); coming back: the ghost fades in on the
##              spot, then the person is there again (solid once the rabbit is not standing on that spot). Deferred while a
##              conversation / page / spar / fight / 比武 / 试炼 / door fade is on (they leave when it is over). The first
##              frame (a new game, a load) and the "等到天亮" night apply without fades.
##   师兄       at night he is visible asleep in his own bed in the dorm (assets/schedule/fox_asleep_bed.png over the
##              senior_bed furniture); E there: his dream line as a bubble (schedule.json people.fox.dream).
##   等到天亮   wait_until_morning() (the 任务面板 button): fade to black, "一夜过去……", the clock goes forward exactly as the
##              T key does (steps of tuning.json time_skip_hours with physics frames in between, so the stall, the upkeep,
##              the bounties and the 委托 at midnight / 08:00 run as they do for T), lands on wait.to_hour (08:00) of the next
##              morning (or of today between 00:00 and 08:00), fade back in. The rabbit stays where he is.
## Bubbles (the "呼……", the dream, the seats' first-time lines) go through Story.bubble() -> the HUD bubble.

signal wait_started
signal wait_finished

const DATA := "res://data/schedule.json"
const BED_ART := "res://assets/schedule/fox_asleep_bed.png"
const SOLID_CLEAR := 13.0          # px: a woken person turns solid once the rabbit's feet are this far away

var main: Node
var data: Dictionary
var state := {}                    # id -> "awake" | "asleep" (what is applied now)
var changes: Array = []            # every change {id, to, hour, instant} (tests)
var waiting := false               # the "等到天亮" night is running
var is_open := false               # = waiting; the Esc page treats us as an open page (group modal_ui)
var waits := 0                     # nights skipped with the button (tests)
var wait_steps: Array = []         # the clock steps of the last night (tests)
var night_black_frames := 0        # physics frames the last night stayed black with its caption (tests)
var dreams := 0                    # dream lines shown (tests)
var bed_sprite: Sprite2D
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var fade_label: Label
var _applied_once := false
var _pending_solid := {}           # id -> true while the woken person waits for the rabbit to step off the spot
var _bubbles: Array = []           # [{text, pos: Vector2, node: Node2D or null, lift: float, left: float, who}]
var _ghosts: Array = []            # fading copies (tests look at them)

static var _data: Dictionary = {}


func _init() -> void:
	name = "Schedule"
	add_to_group("modal_ui")


static func load_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Schedule: cannot read " + DATA)
			parsed = {"people": {}, "wait": {}, "ui": {}}
		_data = parsed
	return _data


func setup(m: Node) -> void:
	main = m
	data = load_data()
	for id in people():
		state[id] = "awake"
	_build_bed()
	_build_fade()


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


func people() -> Dictionary:
	return data.get("people", {})


func person(id: String) -> Dictionary:
	return people().get(id, {})


func wait_cfg() -> Dictionary:
	return data.get("wait", {})


func wait_hour() -> float:
	return float(wait_cfg().get("to_hour", 8))


# ------------------------------------------------------------------ who sleeps when
## The schedule runs: after the prologue (unless prologue_first is off), never in the sandbox of the older suites.
func active() -> bool:
	if main == null or main.story == null or main.story.sandbox:
		return false
	if not bool(data.get("prologue_first", true)):
		return true
	var smp = main.get("sample")
	return smp != null and smp.unlocked and main.story.stage >= 9


## Asleep at `hour` by the table (sleep <= hour < wake, across midnight when sleep > wake).
static func asleep_at(spec: Dictionary, hour: float) -> bool:
	if spec.is_empty() or not spec.has("sleep") or not spec.has("wake"):
		return false
	var s := float(spec["sleep"])
	var w := float(spec["wake"])
	if is_equal_approx(s, w):
		return false
	if s > w:
		return hour >= s or hour < w
	return hour >= s and hour < w


func should_sleep(id: String) -> bool:
	return active() and asleep_at(person(id), main.daynight.hour)


## Somebody of the table is asleep by the clock right now (the button is lit).
func anyone_asleep() -> bool:
	if not active():
		return false
	for id in people():
		if asleep_at(person(id), main.daynight.hour):
			return true
	return false


## The person is gone right now (asleep and applied).
func absent(id: String) -> bool:
	return String(state.get(id, "awake")) == "asleep"


func npc_of(id: String) -> Npc:
	if main == null:
		return null
	for n in main.npcs:
		if n.id == id:
			return n
	if id == "mouse" and main.get("sample") != null and main.sample.mouse != null:
		return main.sample.mouse
	return null


## Something is going on that nobody should vanish in the middle of.
func busy() -> bool:
	var story: Story = main.story
	var c: Combat = main.combat
	if story.busy or story._modal_open() or main.interiors.transitioning:
		return true
	if c.spar_state != "none" or c.trial_active or c.bout_session or c.player_dead or c.in_combat() or c.blocks_interaction():
		return true
	if c.story_hold:
		return true
	var s3 = main.get("step3")
	if s3 != null and s3.get("arena") != null and String(s3.arena.state) != "idle":
		return true
	return false


# ------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if main == null or main.daynight == null:
		return
	_tick_bubbles(delta)
	var instant := waiting or not _applied_once
	_applied_once = true
	if instant or not busy():
		for id in people():
			var want := "asleep" if should_sleep(id) else "awake"
			if want != String(state.get(id, "awake")):
				_apply(id, want, instant)
	_enforce()


func _apply(id: String, want: String, instant: bool) -> void:
	state[id] = want
	changes.append({"id": id, "to": want, "hour": main.daynight.hour, "instant": instant})
	if OS.has_feature("web"):
		print("schedule: %s %s" % [id, want])
	var n := npc_of(id)
	var bed := String(person(id).get("night", "hidden")) == "bed"
	if want == "asleep":
		_pending_solid.erase(id)
		if n != null:
			if not instant and n.visible:
				_ghost(n, 1.0, 0.0)
				if seen_by_rabbit(n):      # R1: only where 小兔 can see him go (on screen, the same room / both outdoors)
					say(ui("bubble"), n.head_position(), null, 0.0, float(data.get("bubble_seconds", 1.2)), id)
			n.visible = false
			n.collision_layer = 0
		if bed:
			_show_bed(true, instant)
	else:
		if n != null and _wants_present(n):
			if instant:
				n.visible = true
				_set_solid(id, n)
			else:
				var g := _ghost(n, 0.0, 1.0)
				g.set_meta("wakes", id)
		if bed:
			_show_bed(false, instant)


## R1 (review round 2): the person is on screen and in the same room as 小兔 (both in the same room, or both outdoors).
## Only then does going to bed show "呼……" - otherwise the HUD would clamp a bubble about nobody to the screen's edge.
func seen_by_rabbit(n: Npc) -> bool:
	var it: Interiors = main.interiors
	if it.room_at(n.global_position) != it.room_at(main.player.global_position):
		return false
	return main.view_rect().has_point(n.global_position) or main.view_rect().has_point(n.head_position())


## Someone else wants this NPC on the map (老周 only once the sample is open: Sample keeps him out of main.npcs before).
func _wants_present(n: Npc) -> bool:
	return main.npcs.has(n)


func _set_solid(id: String, n: Npc) -> void:
	if n.global_position.distance_to(main.player.global_position) < SOLID_CLEAR:
		_pending_solid[id] = true
		n.collision_layer = 0
	else:
		_pending_solid.erase(id)
		n.collision_layer = 1


## Keeps the applied state: an asleep person stays hidden even if another system put him back (Fighter.reset_home).
func _enforce() -> void:
	for id in state:
		var n := npc_of(id)
		if n == null:
			continue
		if String(state[id]) == "asleep":
			if n.visible or n.collision_layer != 0:
				n.visible = false
				n.collision_layer = 0
		elif _pending_solid.has(id) and n.visible:
			_set_solid(id, n)


# ------------------------------------------------------------------ fades
func _fade_secs() -> float:
	return maxf(0.01, float(data.get("fade_seconds", 0.5)))


## A copy of the NPC's current frame fading from a to b; when it fades in, the person appears at its end.
func _ghost(n: Npc, a: float, b: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "ScheduleGhost_" + n.id
	s.texture = n.sprite.sprite_frames.get_frame_texture(n.sprite.animation, n.sprite.frame)
	s.centered = false
	s.offset = n.sprite.offset
	s.scale = n.sprite.scale
	s.position = n.global_position + n.sprite.position
	s.modulate = Color(n.sprite.modulate.r, n.sprite.modulate.g, n.sprite.modulate.b, a)
	s.self_modulate = n.sprite.self_modulate
	s.set_meta("type", "schedule_ghost")
	main.world.add_child(s)
	_ghosts.append(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", b, _fade_secs())
	tw.tween_callback(_ghost_done.bind(s))
	return s


func _ghost_done(s: Sprite2D) -> void:
	var id := String(s.get_meta("wakes", ""))
	if id != "" and String(state.get(id, "awake")) == "awake":
		var n := npc_of(id)
		if n != null and _wants_present(n):
			n.visible = true
			_set_solid(id, n)
	_ghosts.erase(s)
	s.queue_free()


# ------------------------------------------------------------------ 师兄's bed
func _bed_spec() -> Dictionary:
	for id in people():
		if String(person(id).get("night", "")) == "bed":
			var b: Dictionary = person(id).get("bed", {})
			return {"id": id, "room": String(b.get("room", "dorm_main")), "item": String(b.get("item", "senior_bed"))}
	return {}


func _build_bed() -> void:
	var spec := _bed_spec()
	if spec.is_empty() or not ResourceLoader.exists(BED_ART):
		return
	var it: Interiors = main.interiors
	if not it.rooms.has(spec["room"]):
		return
	var f: Dictionary = {}
	for fd in it.rooms[spec["room"]]["def"]["furniture"]:
		if String(fd["name"]) == spec["item"]:
			f = fd
	if f.is_empty():
		return
	var o: Vector2 = it.rooms[spec["room"]]["origin"]
	var r: Array = f["rect"]
	bed_sprite = Sprite2D.new()
	bed_sprite.name = "ScheduleBed_" + String(spec["id"])
	bed_sprite.texture = load(BED_ART)
	bed_sprite.centered = false
	# y-sorted like the bed itself, a hair below its base line so it is always drawn over it (also after a repair
	# rebuilds the room's furniture)
	bed_sprite.position = o + Vector2(float(r[0]), float(f["sort_y"]) + 0.1)
	bed_sprite.offset = Vector2(0, float(r[1]) - float(f["sort_y"]) - 0.1)
	bed_sprite.set_meta("type", "schedule_bed")
	bed_sprite.visible = false
	main.world.add_child(bed_sprite)


func _show_bed(on: bool, instant: bool) -> void:
	if bed_sprite == null:
		return
	if instant:
		bed_sprite.visible = on
		bed_sprite.modulate.a = 1.0
		return
	bed_sprite.visible = true
	bed_sprite.modulate.a = 0.0 if on else 1.0
	var tw := bed_sprite.create_tween()
	tw.tween_property(bed_sprite, "modulate:a", 1.0 if on else 0.0, _fade_secs())
	if not on:
		tw.tween_callback(_bed_fade_done)


func _bed_fade_done() -> void:
	bed_sprite.visible = String(state.get(String(_bed_spec().get("id", "")), "awake")) == "asleep"
	bed_sprite.modulate.a = 1.0


## The sleeping person's bed is shown (tests).
func bed_shown() -> bool:
	return bed_sprite != null and bed_sprite.visible and bed_sprite.modulate.a > 0.99


## World point of the bed's E spot (the furniture anchor).
func bed_point() -> Vector2:
	var spec := _bed_spec()
	if spec.is_empty():
		return Vector2.INF
	var it: Interiors = main.interiors
	var a: Dictionary = it.rooms[spec["room"]]["def"].get("anchors", {})
	if not a.has(spec["item"]):
		return Vector2.INF
	return it.anchor(spec["room"], spec["item"])


# ------------------------------------------------------------------ E: the dream line
## Story.interaction_target hook: the sleeping 师兄's bed (it replaces the empty bed's look). F2: the prompt sits on the
## bed's lower edge and the dream line just above it, so neither covers his face on the pillow.
func interaction_target(p: Vector2, best_d: float, best: Dictionary) -> Dictionary:
	var spec := _bed_spec()
	if spec.is_empty() or not absent(String(spec["id"])) or bed_sprite == null or not bed_sprite.visible:
		return {}
	var bp := bed_point()
	var d := bp.distance_to(p)
	if d > 30.0:
		return {}
	if d >= best_d and String(best.get("id", "")) != spec["item"]:
		return {}
	return {"kind": "schedule", "id": "dream", "who": spec["id"], "prompt": ui("prompt_dream"), "prompt_pos": bp + Vector2(0, 2),
		"dist": d}


func interact(t: Dictionary) -> void:
	if String(t.get("id", "")) == "dream":
		dreams += 1
		var who := String(t.get("who", "fox"))
		say(String(person(who).get("dream", "")), bed_point() + Vector2(0, -16), null, 0.0, float(data.get("line_seconds", 3.0)), who, true)
		if OS.has_feature("web"):
			print("schedule: dream line")


# ------------------------------------------------------------------ bubbles
## A bubble over `pos` (or over `node`'s head, raised by `lift`) for `secs` seconds.
## `action` = the answer to the player's own E (a seat's line, the dream line): shown before every other bubble.
func say(text: String, pos: Vector2, node: Node2D, lift: float, secs: float, who := "", action := false) -> void:
	if text == "":
		return
	_bubbles.append({"text": text, "pos": pos, "node": node, "lift": lift, "left": secs, "who": who, "action": action})


func _tick_bubbles(delta: float) -> void:
	for b in _bubbles:
		b["left"] = float(b["left"]) - delta
	_bubbles = _bubbles.filter(func(b): return float(b["left"]) > 0.0)


## The newest bubble on screen: {text, pos, who} or {} (Story.bubble() shows it on the HUD); `action_only`: only an
## answer to the player's E.
func bubble(action_only := false) -> Dictionary:
	var list: Array = _bubbles.filter(func(x): return bool(x["action"])) if action_only else _bubbles
	if list.is_empty() or waiting:
		return {}
	var b: Dictionary = list[list.size() - 1]
	var pos: Vector2 = b["pos"]
	var nd = b["node"]
	if nd != null and is_instance_valid(nd):
		pos = (nd as Node2D).global_position + Vector2(0, -32.0 - float(b["lift"]))
	return {"text": String(b["text"]), "pos": pos, "who": String(b["who"])}


## Every text of the bubbles now on screen (tests).
func bubble_texts() -> Array:
	return _bubbles.map(func(b): return String(b["text"]))


# ------------------------------------------------------------------ F1: 委托 whose people are asleep
## A 委托 kind that needs somebody who is asleep by the clock right now (schedule.json commission_people: 送馒头 ->
## 茶摊老板, 送信 -> 茶摊老板 and 老伯). The board greys it ("对方已睡，明早再来"); taken ones are not touched.
func commission_asleep(kind: String) -> bool:
	if not active():
		return false
	for id in data.get("commission_people", {}).get(kind, []):
		if asleep_at(person(String(id)), main.daynight.hour):
			return true
	return false


# ------------------------------------------------------------------ minimap: no star / arrow at somebody who is not there
## `v` (a world point or null) unless it is the place of a person who is gone right now.
func filter_target(v: Variant) -> Variant:
	if v == null or not (v is Vector2) or main == null:
		return v
	for id in state:
		if String(state[id]) != "asleep":
			continue
		var n := npc_of(id)
		if n != null and n.global_position.distance_to(v) < 2.0:
			return null
	return v


# ------------------------------------------------------------------ 等到天亮
## The button is shown (after the prologue).
func wait_shown() -> bool:
	return active()


## The button is lit: somebody is asleep and nothing else is running.
func can_wait() -> bool:
	return not waiting and anyone_asleep()


func _build_fade() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.name = "NightFade"
	fade_layer.layer = 25            # over the HUD (10) and the dialogue (20), under the 任务面板 (26) and the Esc page (30)
	add_child(fade_layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.02, 0.02, 0.04, 0.0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	fade_layer.add_child(fade_rect)
	fade_label = Label.new()
	fade_label.text = ui("night_passes")
	fade_label.add_theme_font_size_override("font_size", 12)
	fade_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_label.modulate.a = 0.0
	fade_rect.add_child(fade_label)


## Hours from now to the next wait.to_hour (today's when it is before it, else tomorrow's); 0 = it is that hour now.
func hours_to_morning() -> float:
	return fposmod(wait_hour() - main.daynight.hour, 24.0)


## The 任务面板 button. Returns false (and does nothing) when it is grey.
func wait_until_morning() -> bool:
	if not can_wait():
		return false
	_run_night()
	return true


## 武学 (A) 打坐: the same night with another caption (静坐吐纳……), always to the NEXT wait.to_hour (a full day when it is
## that hour now), whoever is awake. Returns false while a night already runs. wait_finished fires at its end.
func meditate(caption: String) -> bool:
	if waiting:
		return false
	_run_night(caption, true)
	return true


func _run_night(caption := "", force_next := false) -> void:
	waiting = true
	is_open = true
	if not force_next:
		waits += 1
	wait_steps = []
	wait_started.emit()
	if OS.has_feature("web"):
		print("schedule: wait until morning")
	Sfx.play("panel_open")
	var dn: DayNight = main.daynight
	var c: Combat = main.combat
	var p: Player = main.player
	var was_running := dn.running
	dn.running = false
	var held := c.story_hold
	c.story_hold = true               # nobody moves, nobody attacks while the screen is dark
	p.input_enabled = false
	p.velocity = Vector2.ZERO
	var w := wait_cfg()
	var fade := maxf(0.01, float(w.get("fade_seconds", 0.5)))
	var text_secs := maxf(0.0, float(w.get("text_seconds", 1.5)))
	fade_label.text = caption if caption != "" else ui("night_passes")
	fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, fade)
	tw.parallel().tween_property(fade_label, "modulate:a", 1.0, fade)
	await tw.finished
	# the night: the clock goes forward the way the T key moves it, a step at a time with frames in between; the black
	# screen with its caption lasts text_seconds of game time (counted in physics frames)
	var hold_frames := maxi(1, int(round(text_secs * float(Engine.physics_ticks_per_second))))
	var used := 0
	var to_h := wait_hour()
	var need := hours_to_morning()
	if force_next and need < 0.0001:
		need = 24.0
	var target := to_h + 24.0 * roundf((dn.total_hours + need - to_h) / 24.0)   # exactly to_h + 24k (no float drift)
	var step := maxf(0.01, float(Tuning.data()["time_skip_hours"]))
	var steps := maxi(1, ceili(need / step - 0.0001))
	var per := maxi(2, (hold_frames - 4) / steps)
	while target - dn.total_hours > 0.000001:
		var h := minf(step, target - dn.total_hours)
		dn.advance_hours(h)
		if target - dn.total_hours < 0.0001:
			dn.restore(to_h, target)      # the last step lands exactly on 08:00
		wait_steps.append(h)
		for i in per:
			await get_tree().physics_frame
			used += 1
	dn.restore(to_h, target)
	while used < hold_frames:
		await get_tree().physics_frame
		used += 1
	night_black_frames = used
	var tw2 := create_tween()
	tw2.tween_property(fade_rect, "color:a", 0.0, fade)
	tw2.parallel().tween_property(fade_label, "modulate:a", 0.0, fade)
	await tw2.finished
	fade_rect.visible = false
	c.story_hold = held
	var seats = main.get("seats")
	p.input_enabled = not (c.spar_state == "choosing" or c.spar_state == "result" or c.player_dead)
	if seats != null and seats.sitting != "":
		p.velocity = Vector2.ZERO
	dn.running = was_running
	waiting = false
	is_open = false
	wait_finished.emit()
	if OS.has_feature("web"):
		print("schedule: morning")


## While the night runs no key does anything (the T key would add an hour, E would start a conversation in the dark).
func _unhandled_input(event: InputEvent) -> void:
	if waiting and (event is InputEventKey or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()


## Prompts are off while the night runs or the rabbit sits (Story.interaction_target asks).
func blocks_prompts() -> bool:
	if waiting:
		return true
	var seats = main.get("seats") if main != null else null
	return seats != null and seats.sitting != ""
