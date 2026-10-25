class_name Combat
extends Node
## Combat manager: fighters (师兄 + bandits), hit resolution (player <-> enemies), hitstop, dodge-success and
## counter feedback, the auto swap ("闪身换位") landing check, the 师兄 spar flow (choice -> fight in the
## training-yard arena -> result -> reset), bandit aggro / leash / knock-out / "山贼被赶跑了！", and player
## death -> respawn. Numbers: cards/*.tres; places and texts: data/combat.json; arena: map_data.json areas.

signal spar_finished(win: bool)
signal spar_closed(win: bool)       # the result panel is gone and both are back home (序章 v1: the story goes on)
signal bandits_cleared_signal
signal respawned                    # after a knock-out the player is back on his feet at the respawn point
signal counter_landed               # 新手指引 v1: a counter (反击) hit an enemy

const DATA_PATH := "res://data/combat.json"
const RULES_CARD := "res://cards/combat_rules.tres"
const CARD_FOR := {"fox": "shixiong", "wolf": "wolf", "boar": "boar"}
const ARENA_LAYER := 8
const ARENA_WALL := 32.0
const CHOICE_CLOSE_DIST := 56.0

var main: Node
var player: Player
var hud: CombatHud
var fx: CombatFx
var nav: NavGrid
var rules: CombatRules
var data: Dictionary
var texts: Dictionary
var rng := RandomNumberGenerator.new()
var fighters: Array[Fighter] = []
var spar_fighter: Fighter
var bandits: Array[Fighter] = []

var frozen := false            # hitstop: everything that fights skips this physics frame
var hitstop_left := 0.0
var bandits_enabled := true    # tests switch the bandit AI off while they check walking / collisions
# 序章 v1 (set by scripts/story.gd; the defaults are the free-play behaviour the combat suites check):
var story_hold := false        # a conversation is on screen: player and fighters stand still, no aggro, no damage
var bandits_active := true     # false = the bandits are not on the road yet / wait for their opening lines
var story_no_leash := false    # the story fight on the road: the bandits do not give up the chase
var revive_bandits_on_death := false   # player knocked out during the story fight: both bandits come back
var spar_state := "none"       # none | choosing | fighting | result
var spar_count := 0
var spar_wins := 0
var last_spar_win := false
var spar_line := ""
var arena_rect := Rect2()
var arena_body: StaticBody2D
var respawn_pos := Vector2.ZERO
var bandits_cleared := false
var player_dead := false
var deaths := 0
var trial_active := false      # 两条路小样 v1: the 梅花桩 trial runs (counts as combat: no regen, no E, doors / yard closed)
# 第③步: a "bout" = the spar flow (fighting -> result -> closed) with another fighter in another rectangle, run by an
# owner (Arena: the ring, three rounds; Disciple: 陪练 with 师弟 in the yard). The owner gets on_bout_result(win) ->
# {title, line, seconds} and on_bout_closed(win); spar_closed / spar_finished are NOT emitted (师兄's story flags stay).
# bout_session = a whole tournament is on (also between rounds): counts as combat, E / doors / saving wait.
var bout_owner: Object = null
var bout_session := false
var bout_end_fraction := -1.0  # lose / win line (fraction of max HP); < 0 = the fighter card's end_fraction
var bout_last_win := false
var _home_spar_fighter: Fighter = null
var _home_arena_rect := Rect2()
var _bout_fighters: Array[Fighter] = []   # fighters that joined `fighters` for bouts (they leave again at end_bout)
var _timer := 0.0
# 第④步第一批: called after an enemy hit lands on the player (before the knock-out check) - the 悬赏 fights use it for
# their 20 % line (Bounty.on_player_hit(f) -> true when it ended the fight; the player is then refilled, not knocked out)
var after_hit: Callable = Callable()


func _init() -> void:
	name = "Combat"
	process_priority = -100
	process_physics_priority = -100


func setup(m: Node) -> void:
	main = m
	player = m.player
	player.combat = self
	rules = load(RULES_CARD)
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	texts = data.get("texts", {})
	rng.randomize()
	var rt: Array = data["respawn_tile"]
	respawn_pos = Vector2(rt[0] * 32 + 16, rt[1] * 32 + 16)
	var area: Dictionary = m.data["areas"].get(String(data.get("spar_area", "training")), {})
	var r: Array = area.get("rect_tiles", [19, 24, 25, 12])
	arena_rect = Rect2(r[0] * 32, r[1] * 32, r[2] * 32, r[3] * 32)
	for n in m.npcs:
		if n is Fighter:
			fighters.append(n)
			n.knocked_out.connect(_on_knocked_out)
			if n.id == String(data.get("spar_npc", "fox")):
				spar_fighter = n
			else:
				bandits.append(n)
	# nav grid: map colliders + the NPCs that never move
	var extra: Array = []
	for n in m.npcs:
		if not (n is Fighter):
			extra.append(Rect2(n.global_position + Vector2(-7, -6), Vector2(14, 7)))
	nav = NavGrid.new()
	nav.build(m.data["colliders"], extra, m.map_size)
	fx = CombatFx.new()
	fx.name = "CombatFx"
	m.add_child(fx)
	hud = CombatHud.new()
	m.add_child(hud)
	hud.place_hp(Rect2(m.hud.minimap.position, m.hud.minimap.size))
	player.dodge_succeeded.connect(_on_dodge_success)


static func card_for(npc_id: String) -> String:
	return CARD_FOR.get(npc_id, "")


func t(key: String) -> String:
	return String(texts.get(key, key))


# ------------------------------------------------------------------ queries
func engaged_enemies() -> Array:
	return fighters.filter(func(f): return f.is_active())


func nearest_enemy(pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var bd := max_dist
	for f in engaged_enemies():
		var d := pos.distance_to(f.global_position)
		if d <= bd:
			bd = d
			best = f
	return best


func swap_candidate(pos: Vector2, dir: Vector2) -> Node2D:
	var st: PlayerStats = player.stats
	var best: Node2D = null
	var bd := st.swap_range
	for f in engaged_enemies():
		var to: Vector2 = f.global_position - pos
		var d := to.length()
		if d > bd or d < 0.5:
			continue
		if rad_to_deg(absf(dir.angle_to(to))) <= st.swap_angle:
			bd = d
			best = f
	return best


## Landing point behind `enemy` for a swap, or null when it is blocked (wall / object / another body / outside
## the arena, or a wall between the player and the landing point) - then the player does a normal dodge.
func swap_landing(p: Player, enemy: Node2D) -> Variant:
	var away := enemy.global_position - p.global_position
	if away.length() < 0.5:
		return null
	var landing := enemy.global_position + away.normalized() * p.stats.swap_behind
	var space := p.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Player.FOOT_SIZE
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = 1 | ARENA_LAYER
	q.exclude = [p.get_rid(), enemy.get_rid()]
	q.margin = 0.5
	q.transform = Transform2D(0.0, landing + Vector2(0, -2))
	if not space.intersect_shape(q, 1).is_empty():
		return null
	q.transform = Transform2D(0.0, p.global_position + Vector2(0, -2))
	q.motion = landing - p.global_position
	var res := space.cast_motion(q)
	if res.is_empty() or res[0] < 1.0:
		return null
	if spar_state == "fighting" and not arena_rect.grow(-6).has_point(landing):
		return null
	return landing


# ------------------------------------------------------------------ hits
## Player attack resolution. Returns how many enemies were hit.
func player_attack(center: Vector2, radius: float, base: int, knock: float, counter: bool, aim: Vector2, stage: int) -> int:
	var n := 0
	var any_counter := false
	for f in fighters:
		if not f.is_active():
			continue
		if center.distance_to(f.global_position) > radius + f.stats.body_radius:
			continue
		var mult := (player.stats.counter_multiplier if counter else 1.0) * rules.back_multiplier * rules.difficulty_multiplier
		var dmg := maxi(1, int(round(base * mult)))
		if f.take_hit(dmg, player.global_position, knock):
			n += 1
			any_counter = any_counter or counter
			hud.damage_number(f.global_position + Vector2(0, -30), dmg, "counter" if counter else "hit", t("counter"))
			fx.spark((f.global_position + Vector2(0, -12) + (player.global_position + Vector2(0, -12))) * 0.5)
			_check_spar_end()
	fx.slash(player.global_position, aim, stage, counter and n > 0)
	if n > 0:
		hitstop(rules.counter_hitstop if any_counter else rules.hitstop)
		if any_counter and not fx.counter_popup(player.global_position + Vector2(0, -34)):
			hud.show_banner(t("counter") + "！", "", 0.4)
		if any_counter:
			counter_landed.emit()
	return n


## Enemy strike at `center` (circle `radius`): dodge-shadow check, then damage if the player's body is inside.
func enemy_strike(f: Fighter, center: Vector2, radius: float) -> void:
	enemy_shadow_check(center, radius)
	if player_dead or spar_state == "result" or story_hold:
		return
	if center.distance_to(player.global_position) > radius + player.stats.body_radius:
		return
	if player.take_damage(f.stats.damage, f.global_position):
		f.hits_landed += 1
		hud.damage_number(player.global_position + Vector2(0, -30), f.stats.damage, "hurt")
		fx.spark(player.global_position + Vector2(0, -12))
		hitstop(rules.hitstop)
		_check_spar_end()
		if after_hit.is_valid() and after_hit.call(f):
			return
		if player.hp <= 0 and spar_state != "fighting":
			_player_died()


func enemy_shadow_check(center: Vector2, radius: float) -> void:
	player.check_shadow(center, radius)


func _on_dodge_success() -> void:
	hud.screen_flash()
	hud.damage_number(player.global_position + Vector2(0, -34), 0, "text", t("dodge_ok"))


func hitstop(seconds: float) -> void:
	hitstop_left = maxf(hitstop_left, seconds)


# ------------------------------------------------------------------ loop
func _physics_process(delta: float) -> void:
	frozen = hitstop_left > 0.0 or story_hold
	if hitstop_left > 0.0 and not story_hold:
		hitstop_left -= delta
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_on_timer()
	if spar_state == "choosing" and spar_fighter.global_position.distance_to(player.global_position) > CHOICE_CLOSE_DIST:
		close_choice(false)
	if bandits_enabled and bandits_active and not story_hold and not player_dead and spar_state == "none":
		for b in bandits:
			if b.state == "idle" and b.visible and b.stats.aggro_range > 0.0 and b.global_position.distance_to(player.global_position) <= b.stats.aggro_range:
				b.engage()
			elif b.engaged and not story_no_leash and b.stats.leash_range > 0.0 and b.home.distance_to(player.global_position) > b.stats.leash_range:
				b.start_return()
	for f in fighters:
		fx.set_alert(f, f.alert and f.state == "windup" and f.visible)
	# 脱战回血 pauses while the 门派簿 / ending page is open (the tree pause covers the Esc page); dialogue does not block it
	var story = main.get("story")
	if not (story != null and story._modal_open()):
		player.tick_regen(delta, in_combat())


func _process(_delta: float) -> void:
	if hud == null:
		return
	hud.update_player(player.hp, player.stats.max_hp, player.regen_active)
	var mh = main.hud
	var avoid := [hud.hp_panel.get_global_rect(), Rect2(mh.minimap.global_position, mh.minimap.size).grow(1)]
	for c in [mh.objective, mh.clock, mh.hint, hud.result_panel, hud.choice, mh.get("tasks")]:
		if c != null and c.visible:
			avoid.append(c.get_global_rect())
	var ban := hud.banner_rect()
	if ban.has_area():
		avoid.append(ban.grow(2))
	hud.avoid_rects = avoid
	hud.update_plates(fighters, [player.global_position])


## 脱战回血: "in combat" = a spar is on (choosing excluded), or a bandit is engaged. (<5 s since the last damage /
## since leaving combat is handled by Player.regen_calm.)
func in_combat() -> bool:
	if spar_state == "fighting" or spar_state == "result" or trial_active or bout_session:
		return true
	for f in fighters:
		if f.engaged:
			return true
	return false


## True while the E key must not start conversations (spar running / choosing / result, a bandit fight, death).
func blocks_interaction() -> bool:
	if spar_state != "none" or player_dead or trial_active or bout_session:
		return true
	for b in fighters:
		if b.role == "bandit" and b.engaged:
			return true      # the prologue bandits, and (第④步第一批) the 悬赏 villains
	return false


# ------------------------------------------------------------------ spar
func open_choice() -> void:
	spar_state = "choosing"
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	spar_fighter.face_towards(player.global_position)
	hud.show_choice(t("invite"), [t("option_spar"), t("option_cancel")], t("choice_hint"), spar_fighter.head_position(), 0)


## Keyboard for the choice. Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if spar_state != "choosing":
		return false
	if event.is_action_pressed("choice_1"):
		hud.move_choice(0)
		_confirm_choice()
	elif event.is_action_pressed("choice_2"):
		hud.move_choice(1)
		_confirm_choice()
	elif event.is_action_pressed("move_up"):
		hud.move_choice(0)
	elif event.is_action_pressed("move_down"):
		hud.move_choice(1)
	elif event.is_action_pressed("interact"):
		_confirm_choice()
	else:
		return false
	return true


func _confirm_choice() -> void:
	if hud.choice_index == 0:
		close_choice(true)
		start_spar()
	else:
		close_choice(false)
		hud.show_banner(t("spar_cancel"), "", 1.4)


func close_choice(_starting: bool) -> void:
	hud.hide_choice()
	spar_state = "none"
	player.input_enabled = true
	spar_fighter.face(spar_fighter.home_dir)


func start_spar() -> void:
	spar_state = "fighting"
	spar_count += 1
	player.full_heal()
	player.reset_combat_state()
	player.input_enabled = true
	_build_arena()
	if not arena_rect.grow(-8).has_point(player.global_position):
		player.global_position = spar_fighter.global_position + Vector2(0, 40)
	spar_fighter.reset_home(true)
	spar_fighter.engage()
	hud.show_banner(t("spar_start"), "", 1.2)


func _check_spar_end() -> void:
	if spar_state != "fighting":
		return
	var f := spar_fighter
	var frac := bout_end_fraction if bout_owner != null and bout_end_fraction >= 0.0 else f.stats.end_fraction
	var lose := player.hp <= int(floor(player.stats.max_hp * frac))
	var win := f.hp <= int(floor(f.stats.max_hp * frac))
	if lose or win:
		end_spar(win and not lose)


func end_spar(win: bool) -> void:
	if bout_owner != null:
		_end_bout(win)
		return
	spar_state = "result"
	last_spar_win = win
	if win:
		spar_wins += 1
	spar_fighter.yield_fight()
	player.reset_combat_state()
	player.input_enabled = false
	var lines: Array = texts.get("win_lines" if win else "lose_lines", [""])
	spar_line = "师兄：" + String(lines[rng.randi() % lines.size()])
	hud.show_result(t("win") if win else t("lose"), spar_line)
	_timer = rules.spar_result_seconds
	spar_finished.emit(win)


func _finish_spar() -> void:
	if bout_owner != null:
		_close_bout()
		return
	hud.hide_result()
	_remove_arena()
	player.full_heal()
	player.reset_combat_state()
	player.input_enabled = true
	spar_fighter.reset_home(true)
	spar_state = "none"
	spar_closed.emit(last_spar_win)


func _build_arena() -> void:
	_remove_arena()
	arena_body = StaticBody2D.new()
	arena_body.name = "ArenaWalls"
	arena_body.collision_layer = ARENA_LAYER
	arena_body.collision_mask = 0
	var r := arena_rect
	var w := ARENA_WALL
	for rect in [Rect2(r.position.x - w, r.position.y - w, r.size.x + 2 * w, w), Rect2(r.position.x - w, r.end.y, r.size.x + 2 * w, w),
			Rect2(r.position.x - w, r.position.y, w, r.size.y), Rect2(r.end.x, r.position.y, w, r.size.y)]:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = rect.size
		cs.shape = sh
		cs.position = rect.get_center()
		arena_body.add_child(cs)
	var line := Line2D.new()
	line.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	line.width = 1.0
	line.default_color = Color(1.0, 0.85, 0.5, 0.35)
	line.z_index = 1
	arena_body.add_child(line)
	main.add_child(arena_body)


# ------------------------------------------------------------------ bouts (第③步: the ring, 陪练)
## Starts a bout: `f` fights the player inside `rect` (walls like a spar). HP is not touched (the owner decides: the ring
## heals +50 between rounds, 陪练 starts full). Calling it again for the next round keeps the session going.
func start_bout(f: Fighter, rect: Rect2, owner: Object, end_fraction := -1.0, banner := "") -> void:
	if bout_owner == null:
		_home_spar_fighter = spar_fighter
		_home_arena_rect = arena_rect
	bout_owner = owner
	bout_end_fraction = end_fraction
	if not fighters.has(f):
		fighters.append(f)
		_bout_fighters.append(f)
	spar_fighter = f
	arena_rect = rect
	spar_state = "fighting"
	_timer = 0.0
	player.reset_combat_state()
	player.input_enabled = true
	_build_arena()
	f.engage()
	if banner != "":
		hud.show_banner(banner, "", 1.2)


func _end_bout(win: bool) -> void:
	spar_state = "result"
	bout_last_win = win
	spar_fighter.yield_fight()
	player.reset_combat_state()
	player.input_enabled = false
	var info: Dictionary = bout_owner.on_bout_result(win)
	hud.show_result(String(info.get("title", "")), String(info.get("line", "")))
	_timer = float(info.get("seconds", rules.spar_result_seconds))


func _close_bout() -> void:
	hud.hide_result()
	spar_state = "between"      # still not free play: the owner starts the next round or ends the bout
	player.reset_combat_state()
	bout_owner.on_bout_closed(bout_last_win)


## Ends a bout / tournament at once (result over, forfeit): walls down, the 师兄 spar is back to its own fighter / yard.
func end_bout() -> void:
	_remove_arena()
	hud.hide_result()
	if bout_owner != null and _home_spar_fighter != null:
		spar_fighter = _home_spar_fighter
		arena_rect = _home_arena_rect
	bout_owner = null
	bout_end_fraction = -1.0
	for f in _bout_fighters:
		fighters.erase(f)
		if hud.plates.has(f):
			hud.plates[f]["panel"].visible = false
	_bout_fighters.clear()
	spar_state = "none"
	_timer = 0.0
	player.reset_combat_state()
	player.input_enabled = true


func bout_running() -> bool:
	return bout_owner != null


## 两条路小样 v1: the trial closes the training yard with the same walls as a spar (and opens it again).
func close_yard() -> void:
	_build_arena()


func open_yard() -> void:
	_remove_arena()


func yard_closed() -> bool:
	return arena_body != null and is_instance_valid(arena_body)


func _remove_arena() -> void:
	if arena_body != null and is_instance_valid(arena_body):
		arena_body.queue_free()
		main.remove_child(arena_body)
	arena_body = null


# ------------------------------------------------------------------ bandits / death
## 序章 v1: the bandits are only on the road from step 5 on. Hidden = invisible, not solid, never engaged.
func set_bandits_present(on: bool) -> void:
	for b in bandits:
		if on:
			if b.state != "gone" and b.state != "down":
				b.reset_home(true)
		else:
			b.reset_home(true)
			b.visible = false
			b.collision_layer = 0


func engage_bandits() -> void:
	for b in bandits:
		if b.visible and b.state == "idle":
			b.engage()


func _on_knocked_out(f: Fighter) -> void:
	if f.role != "bandit" or bandits_cleared:
		return
	if bandits.all(func(b): return b.state == "gone"):
		bandits_cleared = true
		hud.show_banner(t("bandits_cleared"), "", 2.5)
		bandits_cleared_signal.emit()


func _player_died() -> void:
	if player_dead:
		return
	player_dead = true
	deaths += 1
	player.dead = true
	player.input_enabled = false
	hud.fade_out(t("player_down"), 0.5)
	_timer = rules.death_seconds


func _respawn() -> void:
	player.global_position = respawn_pos
	player.velocity = Vector2.ZERO
	player.reset_combat_state()
	player.hp = maxi(1, int(round(player.stats.max_hp * rules.respawn_heal_fraction)))
	player.input_enabled = true
	player.facing = "down"
	for b in bandits:
		if (b.state != "down" and b.state != "gone") or (revive_bandits_on_death and not bandits_cleared):
			b.reset_home(true)
	player_dead = false
	hud.fade_in(0.4)
	respawned.emit()


func _on_timer() -> void:
	if player_dead:
		_respawn()
	elif spar_state == "result":
		_finish_spar()
