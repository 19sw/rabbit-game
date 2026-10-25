extends Node2D
## Builds the whole region from assets/map/map_data.json (written by tools/sync_assets.py):
## ground, y-sorted objects / NPCs / player, collision, camera, ambience lights and the HUD.
## 序章 v1: the story (scripts/story.gd, data/story.json) decides what E does, which "按 E …" prompt shows, the
## objective / star, the walking bubbles; it starts the opening conversation as soon as the scene is built.
## 室内图进游戏 v1: the rooms (scripts/interiors.gd) sit in the same world to the right of the map; the camera limits,
## minimap position and the indoor light follow the room the player is in.

const MAP_DATA := "res://assets/map/map_data.json"
const GROUND_CHUNK := 256
const INTERACT_DIST := 44.0     # px between feet for the "按 E 交谈" prompt

var data: Dictionary
var map_size := Vector2.ZERO
var ground: Node2D
var world: Node2D
var solids: StaticBody2D
var player: Player
var npcs: Array[Npc] = []
var camera: Camera2D
var ambience: Ambience
var hud: Hud
var daynight: DayNight
var objectives: Objectives
var combat: Combat
var pause_menu: PauseMenu
var story: Story
var sample: Sample              # 两条路小样 v1 (scripts/sample.gd): coins, repairs, the trial, saving
var step3: Step3                # 第③步 (scripts/step3.gd): the 比武大会 ring, the first disciple
var jianghu: Jianghu            # 第④步第一批 (scripts/jianghu.gd): the 江湖告示榜, 悬赏, 委托
var prompt_npc: Npc = null      # NPC whose prompt is showing
var prompt_target: Dictionary = {}   # what E would use right now (Story.interaction_target())
var camera_target: Node2D = null     # 序章 v1 ending: the camera rests on 师父 while the rabbit walks out
var interiors: Interiors
var occlusion: Occlusion
var indoor_k := 0.0             # 打磨 v1: 0 outdoors .. 1 indoors, eased (no colour jump at a door)
var _k_room := ""               # the room the indoor look blends towards


static func ensure_input_actions() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"dash": [KEY_SPACE, KEY_SHIFT], "interact": [KEY_E], "attack": [KEY_J],
		"choice_1": [KEY_1], "choice_2": [KEY_2], "choice_3": [KEY_3], "choice_4": [KEY_4], "sect_book": [KEY_B],
		"toggle_ambience": [KEY_L], "toggle_hint": [KEY_H], "time_skip": [KEY_T], "pause": [KEY_ESCAPE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		if action == "attack":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			InputMap.action_add_event(action, mb)


func _ready() -> void:
	ensure_input_actions()
	data = JSON.parse_string(FileAccess.get_file_as_string(MAP_DATA))
	map_size = Vector2(data["pixel_width"], data["pixel_height"])
	_build_ground()
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	_build_objects()
	_build_colliders()
	interiors = Interiors.new()
	add_child(interiors)
	interiors.build(self)
	combat = Combat.new()
	add_child(combat)   # before the world: it decides the hitstop freeze at the start of each physics frame
	move_child(combat, 0)
	for n in data["npcs"]:
		var card := Combat.card_for(n["id"])
		if card != "":
			var f := Fighter.new()
			world.add_child(f)
			f.setup_fighter(n, card, "spar" if n["id"] == "fox" else "bandit", combat)
			npcs.append(f)
		else:
			var npc := Npc.new()
			world.add_child(npc)
			npc.setup(n)
			npcs.append(npc)
	player = Player.new()
	player.name = "Player"
	world.add_child(player)
	player.afterimage_parent = world
	player.setup(Vector2(data["spawn"]["x"], data["spawn"]["y"]), data["spawn"].get("dir", "down"))
	interiors.place_npcs()
	occlusion = Occlusion.new()
	add_child(occlusion)
	occlusion.setup(self)
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_size.x)
	camera.limit_bottom = int(map_size.y)
	add_child(camera)
	camera.make_current()
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.build(data["lights"])
	daynight = DayNight.new()
	daynight.name = "DayNight"
	add_child(daynight)
	objectives = Objectives.new()
	hud = Hud.new()
	add_child(hud)
	combat.setup(self)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	sample = Sample.new()
	add_child(sample)
	step3 = Step3.new()
	add_child(step3)
	jianghu = Jianghu.new()
	add_child(jianghu)
	story = Story.new()
	add_child(story)
	story.setup(self)
	sample.setup(self)
	step3.setup(self)
	jianghu.setup(self)
	# 两条路小样 v1 存档: 继续游戏 hands a checked saved state over (SaveGame.pending); otherwise the opening starts
	var saved: Variant = SaveGame.pending
	SaveGame.pending = null
	if saved is Dictionary:
		SaveGame.restore(self, saved)
	else:
		story.start()
		if SaveGame.pending_broken:
			SaveGame.pending_broken = false
			hud.show_toast(SaveGame.BROKEN_TEXT, 3.5)
			print("save: unreadable, started fresh")
	for id in interiors.rooms:
		hud.minimap.add_room(id, interiors.rooms[id]["base_tex"], interiors.origin(id))
	indoor_k = 1.0 if interiors.room_at(player.global_position) != "" else 0.0
	_refresh_time_and_objective()
	_update_camera()


func _build_ground() -> void:
	ground = Node2D.new()
	ground.name = "Ground"
	add_child(ground)
	var tex: Texture2D = load("res://assets/map/ground.png")
	# split into chunks so each piece only receives the lantern lights near it
	for y in range(0, tex.get_height(), GROUND_CHUNK):
		for x in range(0, tex.get_width(), GROUND_CHUNK):
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.region_enabled = true
			s.region_rect = Rect2(x, y, mini(GROUND_CHUNK, tex.get_width() - x), mini(GROUND_CHUNK, tex.get_height() - y))
			s.position = Vector2(x, y)
			ground.add_child(s)


func _build_objects() -> void:
	var cache := {}
	for o in data["objects"]:
		if not cache.has(o["tex"]):
			cache[o["tex"]] = load("res://assets/map/" + o["tex"])
		var s := Sprite2D.new()
		s.texture = cache[o["tex"]]
		s.centered = false
		# node position = base line (used by the y-sort), the picture hangs above it
		s.position = Vector2(o["x"], o["sort_y"])
		s.offset = Vector2(0, float(o["y"]) - float(o["sort_y"]))
		s.set_meta("type", o["type"])
		world.add_child(s)


func _build_colliders() -> void:
	solids = StaticBody2D.new()
	solids.name = "Solids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	for c in data["colliders"]:
		var r: Array = c["rect"]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r[2], r[3])
		cs.shape = shape
		cs.position = Vector2(r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)
		cs.set_meta("kind", c["kind"])
		solids.add_child(cs)


func _unhandled_input(event: InputEvent) -> void:
	if combat.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_ambience"):
		toggle_ambience()
	elif event.is_action_pressed("toggle_hint"):
		hud.toggle_hint()
	elif event.is_action_pressed("time_skip"):
		daynight.skip()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("sect_book"):
		story.open_book_by_key()


func toggle_ambience() -> void:
	ambience.toggle()
	hud.show_toast(Hud.AMBIENCE_ON_TEXT if ambience.enabled else Hud.AMBIENCE_OFF_TEXT)


func nearest_npc() -> Npc:
	var best: Npc = null
	var best_d := INTERACT_DIST
	for n in npcs:
		if not n.visible:
			continue   # knocked-out bandits
		var d := n.global_position.distance_to(player.global_position)
		if d <= best_d:
			best_d = d
			best = n
	return best


## E: talk to the NPC / look at the thing the prompt is on (the story decides what happens). True if something did.
func interact() -> bool:
	if combat.blocks_interaction():
		return false
	return story.interact()


func _refresh_time_and_objective(delta := 0.0) -> void:
	var room := interiors.room_at(player.global_position)
	var look := daynight.look()
	var lamps := daynight.lamp_level()
	# 打磨 v1: indoor_k eases between the outdoor and the indoor look (tuning indoor.blend_seconds) - a door never makes
	# the colour jump in one frame
	if room != "":
		_k_room = room
	var secs := maxf(0.01, float(Tuning.data()["indoor"]["blend_seconds"]))
	indoor_k = move_toward(indoor_k, 1.0 if room != "" else 0.0, delta / secs)
	ambience.apply_look(blended_look(look, lamps), lamps)
	interiors.apply_light(lamps, indoor_k if room != "" else 0.0, ambience.enabled)
	hud.set_clock(daynight.clock_text())
	hud.set_objective(objectives.hud_text(Hud.OBJECTIVE_PREFIX))
	# minimap: centred on her, the room picture indoors; the star aims at the target / a room's door / her doorway
	var star: Variant = story.star_world()
	var target: Variant = interiors.minimap_target(star, room) if star != null else null
	var ct := get_viewport().get_canvas_transform()
	var cover := [ct * player.global_position]
	for w in story.poi_points():
		cover.append(ct * (w as Vector2))
	hud.update_minimap(player.global_position, room, CharSheet.dir_vector(player.facing), target, cover,
		story.busy, delta)


## The applied look: outdoor look of the hour blended with the indoor one by indoor_k.
func blended_look(look: Dictionary, lamps: float) -> Dictionary:
	if indoor_k <= 0.0 or _k_room == "":
		return look
	var ind := Interiors.indoor_look(look, lamps, _k_room)
	if indoor_k >= 1.0:
		return ind
	return {"tint": (look["tint"] as Color).lerp(ind["tint"], indoor_k),
		"desaturate": lerpf(look["desaturate"], ind["desaturate"], indoor_k),
		"vignette": lerpf(look["vignette"], ind["vignette"], indoor_k), "name": ind["name"]}


func _process(delta: float) -> void:
	_update_camera()
	_refresh_time_and_objective(delta)
	prompt_target = story.interaction_target() if not combat.blocks_interaction() else {}
	if not prompt_target.is_empty():
		prompt_npc = prompt_target.get("npc", null)
		hud.show_prompt(prompt_target["prompt_pos"], prompt_target["prompt"])
	else:
		prompt_npc = null
		hud.hide_prompt()
	# walking bubbles of the story (they never stop the player); above the prompt when both are on the same NPC
	var b: Dictionary = story.bubble()
	if not b.is_empty():
		var lift := Vector2(0, -16) if prompt_npc != null and prompt_npc.id == b["who"] else Vector2.ZERO
		hud.show_bubble(b["text"], b["pos"] + lift)
	else:
		hud.hide_bubble()


func _update_camera() -> void:
	var focus: Vector2 = camera_target.global_position if camera_target != null and is_instance_valid(camera_target) else player.global_position
	interiors.apply_camera(camera, focus)
	camera.global_position = (focus + Vector2(0, -12)).round()


## Visible world rectangle (after the camera limits are applied).
func view_rect() -> Rect2:
	var vp_size := get_viewport_rect().size / camera.zoom
	var c := camera.get_screen_center_position()
	return Rect2(c - vp_size * 0.5, vp_size)
