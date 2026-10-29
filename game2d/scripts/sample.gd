class_name Sample
extends Node
## 两条路小样 v1 (docs/design/两条路小样-方案-v1.md): what opens after the prologue ("继续逛逛").
##   unlock      the 本钱 (economy.json start_coins), 老周 at the dorm door, the trial board in the training yard, the coin
##               counter beside the HP bar, the repair talks of 老周 / 老伯 / 厨娘 (+ a word from 师父). Nothing of it exists
##               on screen or in the talk rules before (the prologue is untouched).
##   repairs     E at the person -> confirm 是 / 否 -> not enough coins: "还差 N 文", nothing taken -> pay -> fade out / in
##               -> the building changes (outside picture and the room) -> 门派簿 entry (story flag repair_<id>). Once each;
##               afterwards the person says the "after" lines. Prices / 家业 points: data/economy.json.
##   stall       after the kitchen repair: every day when the clock passes stall_hour (08:00) +stall_income once, with the
##               toast "小食摊今日收入 +15".
##   trial       scripts/trial.gd (PlumTrial) - rewards are paid here (reward_trial).
##   saving      request_save(reason) at every save point; the write waits for a calm frame (SaveGame).
## Texts / lines / places: data/sample.json (its scenes are merged into the story's scene table, so they play exactly
## like prologue lines). Art: assets/sample/ (tools/sync_assets.py copies pixel2d/two_paths/output); simple stand-ins are
## drawn while a picture is missing.

signal coins_changed(coins: int)
signal unlocked_now
signal repaired(id: String)
signal income_paid(amount: int)
signal saved(reason: String)

const DATA := "res://data/sample.json"
const ART := "res://assets/sample/"
const REPAIR_ROOM := {"roof": "dorm_main", "dorm_old": "dorm_old", "kitchen": "kitchen"}
const EXTERIOR := {"roof": {"pos": Vector2(160, 928), "file": "exterior/dorm_roof_fixed.png"},
	"kitchen": {"pos": Vector2(1440, 928), "file": "exterior/kitchen_fixed.png"}}

var main: Node
var story: Story
var data: Dictionary
var unlocked := false
var coins := 0
var paid_day := 0                 # last day (counted from stall_hour) the stall income was paid / the stall opened
var trial: PlumTrial
var mouse: Npc
var stall: Node2D
var stall_shape: CollisionShape2D
var coin_panel: PanelContainer
var coin_label: Label
var save_reason := ""             # a save is waiting for a calm frame
var saves: Array[String] = []     # every save written (reasons; tests)
var toasts: Array[String] = []    # every toast shown by the sample (tests)
var shortfalls: Array[int] = []   # every "还差 N 文" (tests)
var incomes := 0                  # number of daily incomes paid (tests)
var exterior_orig: Dictionary = {}   # repair id -> original Texture2D of the building
var exterior_sprites: Dictionary = {}
var _trial_pending := false
var _rooms_fixed: Dictionary = {}    # base room id -> {def, tex}


func _init() -> void:
	name = "Sample"


## Called by Story.setup before the dialogue is built: our scenes and 老周 join the story's tables.
func merge_story_data(sd: Dictionary) -> void:
	_load()
	var scenes: Dictionary = sd.get("scenes", {})
	for id in data.get("scenes", {}):
		scenes[id] = fill_entries(data["scenes"][id])
	var sp: Dictionary = sd.get("speakers", {})
	for id in data.get("speakers", {}):
		sp[id] = data["speakers"][id]


func _load() -> void:
	if not data.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Sample: cannot read " + DATA)
		parsed = {}
	data = parsed


## The numbers in our lines come from the economy table / trial card: "{roof_cost}" etc. are filled in here, so
## changing data/economy.json or cards/trial_plum.tres changes what the characters say.
static func numbers() -> Dictionary:
	var card: TrialCard = load(PlumTrial.CARD)
	return {"roof_cost": Economy.price("roof"), "dorm_old_cost": Economy.price("dorm_old"),
		"kitchen_cost": Economy.price("kitchen"), "start_coins": Economy.start_coins(), "stall_income": Economy.stall_income(),
		"stall_hour": int(Economy.stall_hour()), "repeat": Economy.trial_repeat(),
		"bronze_reward": Economy.trial_reward("bronze"), "silver_reward": Economy.trial_reward("silver"),
		"gold_reward": Economy.trial_reward("gold"), "time_limit": int(card.time_limit), "gold_s": int(card.gold_seconds),
		"silver_s": int(card.silver_seconds), "bronze_s": int(card.bronze_seconds), "dummy_damage": card.dummy_damage,
		"poles": card.pole_points.size(), "fail_pct": int(round(card.fail_hp_fraction * 100.0))}


static func fill(text: String) -> String:
	return text.format(numbers()) if "{" in text else text


## A copy of scene entries with every "text" (lines and choice options) filled in.
static func fill_entries(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = fill(v[k]) if k == "text" and v[k] is String else fill_entries(v[k])
		return out
	if v is Array:
		return v.map(func(x): return fill_entries(x))
	return v


func ui(key: String) -> String:
	return String(data.get("ui", {}).get(key, key))


static func art(file: String) -> Texture2D:
	return load(ART + file) if ResourceLoader.exists(ART + file) else null


func setup(m: Node) -> void:
	main = m
	story = m.story
	_load()
	_build_mouse()
	_build_stall()
	_build_coin_panel()
	_load_rooms_fixed()
	for id in EXTERIOR:
		var spr := _building_at(EXTERIOR[id]["pos"])
		if spr != null:
			exterior_sprites[id] = spr
			exterior_orig[id] = spr.texture
	trial = PlumTrial.new()
	m.add_child(trial)
	trial.setup(m, self)
	story.stage_changed.connect(func(_n): request_save("story"))
	story.scene_finished.connect(_on_scene_finished)
	m.interiors.transition_finished.connect(func(_r): request_save("door"))


# ------------------------------------------------------------------ building the pieces (hidden until unlock)
func _build_mouse() -> void:
	var spec: Dictionary = data.get("mouse", {})
	if spec.is_empty():
		return
	var real := ResourceLoader.exists("res://assets/characters/mouse.png")
	mouse = Npc.new()
	main.world.add_child(mouse)
	var sd := spec.duplicate()
	if not real:
		sd["id"] = "dog"          # stand-in until the art lands: 老伯's sheet, greyed
	mouse.setup(sd)
	mouse.id = String(spec["id"])
	mouse.name = "Npc_" + mouse.id
	if not real:
		mouse.sprite.modulate = Color(0.62, 0.62, 0.68)
	_set_mouse_present(false)


func _set_mouse_present(on: bool) -> void:
	if mouse == null:
		return
	mouse.visible = on
	mouse.collision_layer = 1 if on else 0
	# he is one of the game's NPCs (talk, prompts, minimap) only once the sample is open
	if on and not main.npcs.has(mouse):
		main.npcs.append(mouse)
	elif not on and main.npcs.has(mouse):
		main.npcs.erase(mouse)


func _build_stall() -> void:
	var spec: Dictionary = data.get("food_stall", {})
	if spec.is_empty():
		return
	var tex := art("exterior/food_stall.png")
	var pos := Vector2(spec["pos"][0], spec["pos"][1])
	var sort_y := float(spec.get("sort_y", pos.y + 62))
	var col: Array = spec["collider"]
	var man := _manifest_entry("exterior", "food_stall")
	if not man.is_empty():
		if man.has("map_px"):
			pos = Vector2(man["map_px"][0], man["map_px"][1])
		if man.has("sort_y"):
			sort_y = float(man["sort_y"])
		if man.has("collision_map_px"):
			col = man["collision_map_px"]
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(pos.x, sort_y)
		s.offset = Vector2(0, pos.y - sort_y)
		stall = s
	else:
		stall = StallStandIn.new()
		stall.position = Vector2(pos.x, sort_y)
		(stall as StallStandIn).top = pos.y - sort_y
	stall.name = "FoodStall"
	stall.set_meta("type", "food_stall")
	stall.visible = false
	main.world.add_child(stall)
	stall_shape = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(col[2], col[3])
	stall_shape.shape = sh
	stall_shape.position = Vector2(col[0] + col[2] * 0.5, col[1] + col[3] * 0.5)
	stall_shape.set_meta("kind", "food_stall")
	stall_shape.disabled = true
	main.solids.add_child(stall_shape)


func _build_coin_panel() -> void:
	var hud: Hud = main.hud
	coin_panel = hud._panel(Color(0.10, 0.08, 0.09, 0.72), Color(0.85, 0.72, 0.5, 0.9))
	coin_panel.name = "Coins"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_tex := art("ui/coin.png")
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(12, 12)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	coin_label = hud._label("", 9, Color(1.0, 0.88, 0.5))
	row.add_child(coin_label)
	coin_panel.add_child(row)
	coin_panel.visible = false
	hud.get_child(0).add_child(coin_panel)


func _building_at(p: Vector2) -> Sprite2D:
	for s in main.world.get_children():
		if s is Sprite2D and String(s.get_meta("type", "")) == "building" and s.position.distance_to(p) < 1.0:
			return s
	return null


## An entry of the art manifest (assets/sample/manifest.json, copied from pixel2d/two_paths/output) or {}.
func _manifest_entry(section: String, key: String) -> Dictionary:
	var p := ART + "manifest.json"
	if not FileAccess.file_exists(p):
		return {}
	var m = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(m) != TYPE_DICTIONARY or not (m.get(section, null) is Dictionary):
		return {}
	var v = m[section].get(key, {})
	return v if v is Dictionary else {}


func _load_rooms_fixed() -> void:
	var p := ART + "interiors/rooms_fixed.json"
	if not FileAccess.file_exists(p):
		return
	var rd = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(rd) != TYPE_DICTIONARY:
		return
	for r in rd.get("rooms", []):
		var base := String(r.get("base_id", ""))
		if base != "" and ResourceLoader.exists(ART + "interiors/%s.png" % r["id"]):
			_rooms_fixed[base] = {"def": r, "tex": ART + "interiors/" + String(r["id"])}


# ------------------------------------------------------------------ unlock
## 继续逛逛 (or a restored save at stage 9 that was not unlocked yet): everything of the sample appears; the 本钱 is paid
## once (grant = false when a save is restored - the coins come from the save).
func unlock(grant := true) -> void:
	if unlocked or story.sandbox:
		return
	unlocked = true
	var s3 = main.get("step3")
	if s3 != null:
		s3.on_unlock()     # 第③步: the day the prologue ends is day 1 of the 比武大会 calendar
	_show_unlocked()
	if grant:
		add_coins(Economy.start_coins(), ui("start_coins") % Economy.start_coins())
	if OS.has_feature("web"):
		print("sample: unlocked")
	unlocked_now.emit()
	request_save("unlock")


func _show_unlocked() -> void:
	_set_mouse_present(true)
	trial.set_enabled(true)
	coin_panel.visible = true
	_refresh_coins()
	_place_coin_panel()


func add_coins(n: int, toast := "") -> void:
	coins = maxi(0, coins + n)
	_refresh_coins()
	if toast != "":
		toast_text(toast)
	coins_changed.emit(coins)


func toast_text(t: String) -> void:
	toasts.append(t)
	main.hud.show_toast(t)


func _refresh_coins() -> void:
	coin_label.text = ui("coins") % coins
	story.sect_book.coins = coins if unlocked else -1
	story.sect_book.coins_text = ui("book_coins")


# ------------------------------------------------------------------ hooks used by the story
## Scene an NPC says after the prologue ("" = the story's own rules decide).
func talk_scene(npc_id: String) -> String:
	if not unlocked or story.stage < 9:
		return ""
	for rule in data.get("talk", {}).get(npc_id, []):
		if rule.has("unless") and story.flags.get(String(rule["unless"]), false):
			continue
		if rule.has("if") and not story.flags.get(String(rule["if"]), false):
			continue
		return String(rule["scene"])
	return ""


## True when this room thing has gone with a repair (the dorm bucket after the roof).
func hides_thing(id: String) -> bool:
	var f := String(data.get("hide_things", {}).get(id, ""))
	return f != "" and story.flags.get(f, false)


## The scene a room thing plays (the repaired room has its own line for some things).
func thing_scene(id: String, scene: String) -> String:
	var o: Dictionary = data.get("thing_overrides", {}).get(id, {})
	if not o.is_empty() and story.flags.get(String(o.get("if", "")), false):
		return String(o["scene"])
	return scene


## E targets of the sample closer than `best_d`: the trial board. {} = none.
func interaction_target(p: Vector2, best_d: float) -> Dictionary:
	if not unlocked or trial == null or not trial.board_usable():
		return {}
	var pos := trial.board_point()
	var d := pos.distance_to(p)
	if d > float(data.get("trial_sign", {}).get("radius", 34)) or d >= best_d:
		return {}
	return {"kind": "thing", "id": "trial_sign", "scene": "X-试炼木牌", "action": "", "prompt": ui("prompt_sign"),
		"prompt_pos": pos + Vector2(0, -50)}


func poi_points() -> Array:
	return [trial.board_point()] if unlocked and trial != null else []


func handles(action: String) -> bool:
	return action in ["repair", "trial_start"]


## Story `do` actions of our scenes (awaited inside the running scene).
func do_action(e: Dictionary, token: int) -> void:
	match String(e["do"]):
		"repair":
			await _repair(e, token)
		"trial_start":
			_trial_pending = true


func _on_scene_finished(_id: String) -> void:
	if _trial_pending:
		_trial_pending = false
		trial.begin()
	request_save("story")


# ------------------------------------------------------------------ repairs
func repaired_ids() -> Array:
	return Economy.REPAIRS.filter(func(id): return story.flags.get("repair_" + id, false))


func is_repaired(id: String) -> bool:
	return story.flags.get("repair_" + id, false)


func _repair(e: Dictionary, token: int) -> void:
	var id := String(e["repair"])
	if is_repaired(id):
		return
	var price := Economy.price(id)
	if coins < price:
		shortfalls.append(price - coins)
		await story.dialogue.say({"kind": "提示", "text": ui("not_enough") % (price - coins)})
		if token != story._run_id:
			return
		if e.has("short_scene"):
			await story._run_entries(story.scene(String(e["short_scene"])), token)
		return
	add_coins(-price, ui("paid") % price)
	story.dialogue.close()
	var fade: ColorRect = main.interiors.fade_rect
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_interval(0.5)
	await tw.finished
	story.flags["repair_" + id] = true
	apply_repair_visuals(id)
	if id == "kitchen":
		paid_day = main.daynight.day_index(Economy.stall_hour())    # opens now: the next stall_hour pays
	if OS.has_feature("web"):
		print("sample: repaired %s" % id)
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.45)
	await tw2.finished
	repaired.emit(id)
	request_save("repair")
	if token != story._run_id:
		return
	if e.has("done_scene"):
		await story._run_entries(story.scene(String(e["done_scene"])), token)


## The repaired look (outside picture, the room, the stall). Called again on a restored save; safe to repeat.
func apply_repair_visuals(id: String) -> void:
	if EXTERIOR.has(id) and exterior_sprites.has(id):
		var spr: Sprite2D = exterior_sprites[id]
		var t := art(String(EXTERIOR[id]["file"]))
		if t != null:
			spr.texture = t
		else:
			spr.modulate = Color(1.08, 1.04, 0.96)     # stand-in until the art lands
		spr.set_meta("repaired", true)
	var room := String(REPAIR_ROOM.get(id, ""))
	if room != "":
		if _rooms_fixed.has(room):
			main.interiors.apply_variant(room, _rooms_fixed[room]["def"], _rooms_fixed[room]["tex"])
		elif id == "roof":
			main.interiors.stop_leak(room)
		else:
			main.interiors.rooms[room]["nodes"][0].modulate = Color(1.12, 1.08, 1.0)   # stand-in
		main.interiors.set_meta("repaired_" + room, true)
	if id == "roof":
		main.interiors.stop_leak("dorm_main")
	if id == "kitchen" and stall != null:
		stall.visible = true
		stall_shape.set_deferred("disabled", false)


func stall_open() -> bool:
	return unlocked and is_repaired("kitchen")


# ------------------------------------------------------------------ trial rewards (called by PlumTrial)
## Pays a finished run: first time for each tier its coins + 名望 (flags trial_<tier>), otherwise the repeat reward.
## Returns {tiers_new: [...], coins: n, fame: n}.
func reward_trial(seconds: float) -> Dictionary:
	var tiers := Economy.tiers_for_time(seconds, trial.card)
	if not Economy.tiers_cumulative() and not tiers.is_empty():
		tiers = [tiers[tiers.size() - 1]]
	var fresh := []
	var gain := 0
	var fame := 0
	for t in tiers:
		if not story.flags.get("trial_" + t, false):
			story.flags["trial_" + t] = true
			fresh.append(t)
			gain += Economy.trial_reward(t)
			fame += Economy.fame_points(t)
	if fresh.is_empty() and not tiers.is_empty():
		gain = Economy.trial_repeat()
	if gain > 0:
		add_coins(gain)
	return {"tiers_new": fresh, "coins": gain, "fame": fame}


# ------------------------------------------------------------------ every frame
func _process(_delta: float) -> void:
	if main == null:
		return
	if unlocked:
		_place_coin_panel()
		_check_income()
	if save_reason != "" and calm():
		save_now(save_reason)


func _place_coin_panel() -> void:
	var hp: Control = main.combat.hud.hp_panel
	var r := hp.get_global_rect()
	coin_panel.position = Vector2(r.end.x + 4, r.position.y)
	coin_panel.size = coin_panel.get_combined_minimum_size()
	# the toast goes under the top row (HP bar + coins) so the coin counter never covers it - and under the objective
	# line too (新手指引 v1: the guide's objective reaches the middle of the screen, where the toast is centred)
	var bottom := maxf(r.end.y, coin_panel.position.y + coin_panel.size.y)
	if main.hud.objective.visible:
		bottom = maxf(bottom, main.hud.objective.get_global_rect().end.y)
	main.hud.set_toast_top(roundf(bottom + 3.0))


func _check_income() -> void:
	if not stall_open():
		return
	var day: int = main.daynight.day_index(Economy.stall_hour())
	if day <= paid_day:
		return
	paid_day = day        # once per day, however far the clock jumped
	incomes += 1
	var amount := Economy.stall_income()
	var s3 = main.get("step3")
	if s3 != null:
		amount = s3.stall_income(day)     # 第③步: 师弟 helping in the kitchen (帮厨) from the day it takes effect
	add_coins(amount, ui("stall_income") % amount)
	if OS.has_feature("web"):
		print("sample: stall income")
	income_paid.emit(amount)
	request_save("income")


# ------------------------------------------------------------------ saving
func request_save(reason: String) -> void:
	if story == null or story.sandbox:
		return
	if save_reason == "":
		save_reason = reason
	elif not reason in save_reason.split("+"):
		save_reason += "+" + reason      # one write for everything that happened since the last calm frame


## Nothing is half-done right now: no conversation / modal page / spar / bandit fight / trial / door fade.
func calm() -> bool:
	if story.sandbox or story.busy or story._modal_open() or main.interiors.transitioning:
		return false
	if main.combat.blocks_interaction() or main.combat.story_hold:
		return false
	if trial != null and trial.state != "idle":
		return false
	if main.player.dead or main.player.sprite.modulate.a < 1.0:
		return false
	return true


func save_now(reason: String) -> bool:
	save_reason = ""
	var ok := SaveGame.write(SaveGame.capture(main), reason)
	if ok:
		saves.append(reason)
		saved.emit(reason)
	return ok


func capture() -> Dictionary:
	return {"unlocked": unlocked, "coins": coins, "paid_day": paid_day, "trial_runs": trial.runs if trial else 0,
		"trial_best": trial.best_time if trial else 0.0}


func restore(d: Dictionary) -> void:
	coins = int(d["coins"])
	paid_day = int(d["paid_day"])
	if trial != null:
		trial.runs = int(d["trial_runs"])
		trial.best_time = float(d["trial_best"])
	if bool(d["unlocked"]):
		unlocked = true
		_show_unlocked()
	for id in Economy.REPAIRS:
		if is_repaired(id):
			apply_repair_visuals(id)
	_refresh_coins()
	if not unlocked and story.stage >= 9 and story.flags.get("prologue_done", false):
		unlock(true)    # the prologue ended with 回到启动画面: it opens now


## Stand-in food stall (drawn) until the picture exists.
class StallStandIn extends Node2D:
	var top := -62.0

	func _draw() -> void:
		var t := top
		draw_rect(Rect2(4, t + 30, 56, 28), Color("7a4a2a"))
		draw_rect(Rect2(0, t + 22, 64, 10), Color("b23a2a"))
		draw_rect(Rect2(14, t + 34, 16, 10), Color("e8dcc0"))
		draw_rect(Rect2(34, t + 34, 16, 10), Color("e8dcc0"))
		draw_rect(Rect2(20, t + 8, 24, 12), Color("f0e2b0"))
