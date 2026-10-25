class_name Fighter
extends Npc
## A fighting NPC: 师兄 (sparring partner) or a bandit (狼 / 野猪). Numbers from its stat card (EnemyStats,
## res://cards/<card>.tres). Until it is engaged it is an ordinary standing NPC.
## AI: chase -> wind-up (red glow, "!" once the direction locks) -> strike / charge -> recover -> wait a random
## interval. Super armour during wind-up and strike (if the card says so; v1.2: 师兄 has none), stagger + knock-back otherwise,
## poise (no re-stagger for a while), optional sidestep (师兄), turning takes time (turn_time = half a turn).
## Bandits: aggro inside aggro_range, give up and walk home (full HP) when the player is leash_range from home,
## knocked out at 0 HP (down pose, fade, gone for this session).

signal knocked_out(f: Fighter)
signal enraged(f: Fighter)        # 第④步第一批: a VillainStats card's rage started (黑虎)
signal fled(f: Fighter)           # 第④步第一批: a VillainStats card's flight started (黄鼠狼)

const ARENA_LAYER := 8
const FACE_TO_ATTACK := deg_to_rad(40.0)   # must roughly face the player before starting a wind-up
const REPATH_EVERY := 0.25
const KNOCK_TIME := 0.12

var stats: EnemyStats
var card := ""
var role := "bandit"          # "bandit" | "spar"
var combat: Node              # Combat
var hp := 1
var state := "idle"           # idle chase windup strike recover stagger sidestep return yield down gone
var engaged := false          # shows name plate + HP bar, AI running
var home := Vector2.ZERO
var angle := PI * 0.5         # facing angle (radians, 0 = right, PI/2 = down)
var t := 0.0
var next_attack := 1.0
var poise_left := 0.0
var sidestep_cd := 0.0
var strike_dir := Vector2.DOWN
var struck := false
var combo_left := 0           # 第③步: more strikes of this attack still to come (EnemyStats.strikes_per_attack)
var alert := false            # "!" above the head (direction locked)
var knock_vel := Vector2.ZERO
var knock_left := 0.0
var move_vel := Vector2.ZERO
var strikes := 0              # statistics for tests
var hits_landed := 0
var flash_mat: ShaderMaterial
var _path := PackedVector2Array()
var _repath := 0.0
var _flash_t := 0.0
var _return_t := 0.0
# 第④步第一批 (VillainStats cards only; every other card never enters these branches):
var has_fled := false         # ran away once (flee_at)
var raged := false            # enraged (rage_at): shorter intervals, pounces
var kind_now := ""            # attack kind of the attack under way ("" = the card's); a pounce is a "charge"
var pounces := 0              # statistics for tests
var _flee_target := Vector2.ZERO
var _base_tint := Color.WHITE
var _rage_pending := false


func setup_fighter(d: Dictionary, card_name: String, fighter_role: String, c: Node) -> void:
	setup(d)
	card = card_name
	role = fighter_role
	combat = c
	stats = load("res://cards/%s.tres" % card_name)
	hp = stats.max_hp
	home = global_position
	angle = CharSheet.dir_vector(home_dir).angle()
	collision_mask = 1 | 2 | ARENA_LAYER
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = load("res://scripts/flash.gdshader")
	sprite.material = flash_mat
	add_to_group("fighters")


func is_active() -> bool:
	return engaged and state not in ["down", "gone", "return", "yield", "idle"]


func is_attack_state() -> bool:
	return state == "windup" or state == "strike" or state == "gap"


func facing_vec() -> Vector2:
	return Vector2.from_angle(angle)


func _frozen() -> bool:
	return combat != null and combat.frozen


# ------------------------------------------------------------------ control from Combat
func engage(start_wait := -1.0) -> void:
	engaged = true
	state = "chase"
	t = 0.0
	next_attack = start_wait if start_wait >= 0.0 else _interval()
	poise_left = 0.0
	sidestep_cd = 0.0
	_path = PackedVector2Array()


func reset_home(full_hp := true) -> void:
	engaged = false
	state = "idle"
	t = 0.0
	alert = false
	velocity = Vector2.ZERO
	knock_left = 0.0
	global_position = home
	if full_hp:
		hp = stats.max_hp
	angle = CharSheet.dir_vector(home_dir).angle()
	facing = home_dir
	collision_layer = 1
	visible = true
	modulate.a = 1.0
	sprite.rotation = 0.0
	sprite.speed_scale = 1.0
	_set_flash(Color.WHITE, 0.0)
	if has_fled or raged:
		_set_rage_look(false)
	has_fled = false
	raged = false
	_rage_pending = false
	kind_now = ""
	face(home_dir)


func yield_fight() -> void:
	state = "yield"
	alert = false
	velocity = Vector2.ZERO
	_set_flash(Color.WHITE, 0.0)
	_play_idle()


func start_return() -> void:
	state = "return"
	engaged = false
	alert = false
	_return_t = 0.0
	_path = PackedVector2Array()
	_set_flash(Color.WHITE, 0.0)


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not engaged and state == "idle":
		return
	if _frozen():
		sprite.speed_scale = 0.0 if not combat.story_hold else 1.0
		if combat.story_hold and state != "down":
			_play_idle()
		return
	sprite.speed_scale = 1.0
	if _rage_pending and engaged and state in ["chase", "recover", "stagger"]:
		_start_rage()
	t += delta
	poise_left -= delta
	sidestep_cd -= delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_flash(Color.WHITE, 0.0)
	var player: Node2D = combat.player if combat != null else null
	match state:
		"chase":
			next_attack -= delta
			_chase(delta, player)
		"windup":
			_windup(delta, player)
		"strike":
			_strike(delta, player)
		"gap":
			# 第③步: between the strikes of a multi-strike attack (no new wind-up): turn to him and strike again
			velocity = Vector2.ZERO
			if player != null:
				_turn_toward(player.global_position - global_position, delta)
			if t >= float(stats.get("combo_gap")):
				_begin_strike()
		"recover":
			velocity = Vector2.ZERO
			if t >= stats.recover:
				_go("chase")
				next_attack = _interval()
			# hold the (non-looping) attack pose while recovering; idle otherwise
			if not (sprite.animation.begins_with("attack") and CharSheet.has_action(id, "attack1")):
				_play_idle()
		"stagger":
			next_attack -= delta
			knock_left -= delta
			velocity = knock_vel if knock_left > 0.0 else Vector2.ZERO
			if t >= stats.stagger:
				poise_left = stats.poise
				_go("chase")
				if stats.stagger_delays_attack:
					next_attack = maxf(next_attack, stats.stagger_attack_delay)
			_play_action("hurt", "idle")
		"sidestep":
			next_attack -= delta
			if t >= stats.sidestep_time:
				velocity = Vector2.ZERO
				_go("chase")
			elif CharSheet.has_action(id, "sidestep"):
				_play_action("sidestep", "walk")    # 第③步: the snake's hop (the slide itself is the velocity above)
			else:
				_play_walk()
		"return":
			_return(delta)
		"flee":
			# 第④步第一批 (黄鼠狼): runs away from him for flee_time, then turns round and comes back at once
			next_attack -= delta
			_turn_toward(_flee_target - global_position, delta)
			velocity = _steer_to(_flee_target, delta) * _vf("flee_speed", stats.move_speed)
			_play_walk()
			sprite.speed_scale = 1.5
			if t >= _vf("flee_time", 0.0) or global_position.distance_to(_flee_target) < 6.0:
				velocity = Vector2.ZERO
				sprite.speed_scale = 1.0
				_go("chase")
				next_attack = _vf("flee_return_wait", 0.3)
		"rage":
			# 第④步第一批 (黑虎): the roar - stands still, cannot be staggered, then fights on enraged
			velocity = Vector2.ZERO
			_play_action("rage", "idle")
			if t >= _vf("rage_time", 0.5):
				_go("chase")
				next_attack = minf(next_attack, 0.3)
		"yield":
			velocity = Vector2.ZERO
		"down":
			velocity = Vector2.ZERO
			_play_action("down", "idle")
			if t >= 0.5:
				modulate.a = clampf(1.0 - (t - 0.5) / maxf(stats.defeat_fade, 0.01), 0.0, 1.0)
			if t >= 0.5 + stats.defeat_fade:
				state = "gone"
				visible = false
				knocked_out.emit(self)
		"gone":
			velocity = Vector2.ZERO
	if state != "gone" and state != "down":
		move_and_slide()
	if state == "strike" and attack_kind_now() == "charge" and not struck and player != null:
		_charge_contact(player)
	facing = CharSheet.dir_from_vector(facing_vec(), facing)
	sprite.position = global_position.round() - global_position


func _go(s: String) -> void:
	state = s
	t = 0.0
	struck = false
	if s != "windup":
		alert = false
		_set_flash(Color.WHITE, 0.0)


func _interval() -> float:
	var v: float = combat.rng.randf_range(stats.interval_min, stats.interval_max)
	return v * _vf("rage_interval_factor", 1.0) if raged else v


## A VillainStats number (`def` for every other card).
func _vf(key: String, def: float) -> float:
	if stats is VillainStats:
		return float(stats.get(key))
	return def


## The kind of the attack under way: the card's, or "charge" for a 黑虎 pounce.
func attack_kind_now() -> String:
	return kind_now if kind_now != "" else stats.attack_kind


func is_pounce() -> bool:
	return kind_now == "charge" and stats.attack_kind != "charge"


func _lunge() -> float:
	return _vf("pounce_lunge", stats.strike_lunge) if is_pounce() else stats.strike_lunge


func _strike_t() -> float:
	return _vf("pounce_time", stats.strike_time) if is_pounce() else stats.strike_time


func _hit_off() -> float:
	return 0.0 if is_pounce() else stats.hit_offset


func _turn_toward(v: Vector2, delta: float) -> void:
	if v.length() < 0.01:
		return
	var target := v.angle()
	var rate := PI / maxf(stats.turn_time, 0.01)
	var diff := wrapf(target - angle, -PI, PI)
	angle = wrapf(angle + clampf(diff, -rate * delta, rate * delta), -PI, PI)


func _chase(delta: float, player: Node2D) -> void:
	if player == null:
		return
	var to := player.global_position - global_position
	var dist := to.length()
	_turn_toward(to, delta)
	# occasional sidestep when the player attacks close by (师兄)
	if stats.sidestep_chance > 0.0 and sidestep_cd <= 0.0 and dist < stats.sidestep_trigger and player.is_attacking():
		sidestep_cd = stats.sidestep_cooldown
		if combat.rng.randf() < stats.sidestep_chance:
			var side := to.normalized().orthogonal() * (1.0 if combat.rng.randf() < 0.5 else -1.0)
			velocity = side * (stats.sidestep_distance / maxf(stats.sidestep_time, 0.01))
			_go("sidestep")
			return
	if dist > stats.stop_distance:
		velocity = _steer_to(player.global_position, delta) * stats.move_speed
		_play_walk()
	else:
		velocity = Vector2.ZERO
		_play_idle()
	var facing_ok := absf(wrapf(to.angle() - angle, -PI, PI)) < FACE_TO_ATTACK
	var reach := stats.attack_range
	if raged:
		reach = maxf(reach, _vf("pounce_range", 0.0))
	if dist <= reach and next_attack <= 0.0 and facing_ok:
		velocity = Vector2.ZERO
		kind_now = stats.attack_kind
		if raged and _vf("pounce_chance", 0.0) > 0.0 and (dist > stats.attack_range or combat.rng.randf() < _vf("pounce_chance", 0.0)):
			kind_now = "charge"       # 黑虎 enraged: this attack is a pounce (a charge with its own reach)
		_go("windup")


func _windup(delta: float, player: Node2D) -> void:
	velocity = Vector2.ZERO
	var lock_t := stats.windup * stats.lock_fraction
	if t < lock_t and player != null:
		_turn_toward(player.global_position - global_position, delta)
	alert = t >= lock_t
	_set_flash(Color(1.0, 0.18, 0.12), 0.25 + 0.2 * sin(t * 30.0))
	_play_action("windup", "idle")
	if t >= stats.windup:
		combo_left = maxi(1, int(stats.get("strikes_per_attack"))) - 1 if stats is ComboStats else 0
		_begin_strike()


func _begin_strike() -> void:
	var second := state == "gap"
	strike_dir = facing_vec()
	_go("strike")
	strikes += 1
	if is_pounce():
		pounces += 1
	velocity = strike_dir * (_lunge() / maxf(_strike_t(), 0.01))
	if attack_kind_now() != "charge":
		struck = true
		combat.enemy_strike(self, global_position + strike_dir * stats.hit_offset, stats.hit_radius)
	if is_pounce() and CharSheet.has_action(id, "pounce"):
		_play_action("pounce", "walk", _strike_t(), -1.0, true)
	elif attack_kind_now() == "charge" and CharSheet.has_action(id, "charge"):
		_play_action("charge", "walk", 0.0, -1.0, true)
	else:
		_play_action("attack2" if second and CharSheet.has_action(id, "attack2") else "attack1", "walk",
			stats.strike_time + stats.recover * 0.5, -1.0, true)


func _strike(_delta: float, _player: Node2D) -> void:
	velocity = strike_dir * (_lunge() / maxf(_strike_t(), 0.01))
	if attack_kind_now() == "charge":
		combat.enemy_shadow_check(global_position + strike_dir * _hit_off(), stats.hit_radius)
	if t >= _strike_t():
		velocity = Vector2.ZERO
		if combo_left > 0:
			combo_left -= 1
			_go("gap")
		else:
			_go("recover")


func _charge_contact(player: Node2D) -> void:
	var center := global_position + strike_dir * _hit_off()
	combat.enemy_shadow_check(center, stats.hit_radius)
	if center.distance_to(player.global_position) <= stats.hit_radius + player.stats.body_radius:
		struck = true   # one charge hits at most once
		combat.enemy_strike(self, center, stats.hit_radius)


func _return(delta: float) -> void:
	_return_t += delta
	var to := home - global_position
	if to.length() < 3.0 or _return_t > 8.0:
		reset_home(true)
		return
	_turn_toward(to, delta)
	velocity = _steer_to(home, delta) * stats.move_speed
	_play_walk()


## Direction to walk towards `target`: straight when the line is clear, else along an A* path on the nav grid.
func _steer_to(target: Vector2, delta: float) -> Vector2:
	var nav: NavGrid = combat.nav if combat != null else null
	if nav == null or nav.line_clear(global_position, target):
		_path = PackedVector2Array()
		return (target - global_position).normalized()
	_repath -= delta
	if _path.is_empty() or _repath <= 0.0:
		_repath = REPATH_EVERY
		_path = nav.path(global_position, target)
	while _path.size() > 0 and global_position.distance_to(_path[0]) < 4.0:
		_path.remove_at(0)
	if _path.is_empty():
		return (target - global_position).normalized()
	return (_path[0] - global_position).normalized()


# ------------------------------------------------------------------ getting hit
## Player hit. Returns true if it landed.
func take_hit(dmg: int, from_pos: Vector2, knock: float) -> bool:
	if not engaged or state in ["down", "gone", "return", "yield", "idle"]:
		return false
	hp = maxi(hp - dmg, 0)
	_set_flash(Color(1, 1, 1), 0.85)
	_flash_t = 0.1
	if role == "bandit" and hp <= 0:
		_knock_out()
		return true
	if state == "flee" or state == "rage":
		return true          # 第④步第一批: running away / roaring - hurt, never staggered
	if stats is VillainStats and _villain_turn(from_pos):
		return true
	var armored := stats.super_armor and is_attack_state()
	if not armored and poise_left <= 0.0:
		var away := global_position - from_pos
		away = away.normalized() if away.length() > 0.5 else -facing_vec()
		knock_vel = away * (knock * (1.0 - stats.knock_resist) / KNOCK_TIME)
		knock_left = KNOCK_TIME
		if state == "strike" or state == "recover":
			# v1.2 fix: the attack already happened - the usual wait after recovering still applies (before, a
			# stagger here skipped it and the next wind-up came only stagger_attack_delay later)
			next_attack = maxf(next_attack, _interval())
		_go("stagger")
	return true


## 第④步第一批: the one-time flight (flee_at) / rage (rage_at) of a VillainStats card. True when one started.
func _villain_turn(from_pos: Vector2) -> bool:
	var frac := float(hp) / float(maxi(1, stats.max_hp))
	if not has_fled and _vf("flee_at", 0.0) > 0.0 and frac <= _vf("flee_at", 0.0):
		has_fled = true
		alert = false
		var away := global_position - from_pos
		away = away.normalized() if away.length() > 0.5 else -facing_vec()
		var dist := _vf("flee_speed", stats.move_speed) * _vf("flee_time", 1.0)
		_flee_target = global_position + away * dist
		var nav: NavGrid = combat.nav if combat != null else null
		if nav != null:
			# not into a wall: the farthest clear point along the way (or sideways when straight back is blocked)
			var best := global_position
			for turn in [0.0, 0.5, -0.5, 1.0, -1.0]:
				var dir := away.rotated(turn)
				var k := 1.0
				while k > 0.2:
					var q: Vector2 = global_position + dir * dist * k
					if nav.line_clear(global_position, q):
						if q.distance_to(global_position) > best.distance_to(global_position) + 1.0:
							best = q
						break
					k -= 0.2
			_flee_target = best
		_go("flee")
		fled.emit(self)
		return true
	if not raged and not _rage_pending and _vf("rage_at", 0.0) > 0.0 and frac <= _vf("rage_at", 0.0):
		if is_attack_state():
			_rage_pending = true      # the blow under way still lands; he roars right after it
			return false
		_start_rage()
		return true
	return false


func _start_rage() -> void:
	_rage_pending = false
	raged = true
	alert = false
	_set_rage_look(true)
	_go("rage")
	enraged.emit(self)


## 黑虎's red look: the _rage sheets when the art has them, else a red tint on the stand-in.
func _set_rage_look(on: bool) -> void:
	var rage_id := id + "_rage"
	if on and CharSheet.has_own_art(rage_id):
		var anim := sprite.animation
		sprite.sprite_frames = CharSheet.frames_for(rage_id)
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
	elif not on and sprite.sprite_frames != CharSheet.frames_for(id):
		sprite.sprite_frames = CharSheet.frames_for(id)
		sprite.play("idle_" + facing)
	if on:
		_base_tint = sprite.modulate
		if not CharSheet.has_own_art(rage_id):
			sprite.modulate = Color(1.25, 0.7, 0.62)
	else:
		sprite.modulate = Color.WHITE if _base_tint == Color.WHITE else _base_tint
		_base_tint = Color.WHITE


func _knock_out() -> void:
	_go("down")
	engaged = false
	alert = false
	collision_layer = 0
	velocity = Vector2.ZERO


func _set_flash(c: Color, amount: float) -> void:
	if flash_mat == null:
		return
	flash_mat.set_shader_parameter("flash_color", c)
	flash_mat.set_shader_parameter("amount", amount)


# ------------------------------------------------------------------ animation
func _play_walk() -> void:
	_play_anim("walk_" + facing)


func _play_idle() -> void:
	_play_anim("idle_" + facing)


func _play_anim(a: String) -> void:
	sprite.rotation = 0.0
	if sprite.animation != a or not sprite.is_playing():
		sprite.play(a)


func _play_action(action: String, fallback: String, length := 0.0, impact := -1.0, restart := false) -> void:
	var anim := "%s_%s" % [action, facing]
	if CharSheet.has_action(id, action) and sprite.sprite_frames.has_animation(anim):
		if restart or sprite.animation != anim:
			sprite.play(anim)
			sprite.frame = 0
		sprite.speed_scale = CharSheet.action_speed(id, action, length, impact) if length > 0.0 else 1.0
		sprite.rotation = 0.0
		return
	_play_anim(fallback + "_" + facing)
	if action == "down":
		sprite.rotation = -PI * 0.5 if facing != "left" else PI * 0.5
