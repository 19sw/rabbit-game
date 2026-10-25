class_name Player
extends CharacterBody2D
## The rabbit. The node origin is the point between the feet (used for y-sorting and collision).
## All movement / combat numbers come from the player's stat card (配置资产): res://cards/player.tres (PlayerStats).
## Combat: J = two-hit combo (input buffer, auto-face, slowed movement), Space/Shift = dodge with i-frames,
## dodge success (an enemy strike hits the dodge "shadow") opens the counter window (whole combo x1.5),
## dodging towards a close enemy swaps behind it (validated by Combat, otherwise a normal dodge).
## 闪身追击 (v1.2): attack pressed within chase_window after a dodge ends -> dash (dodge speed) at the nearest
## attackable enemy within chase_range, stop at attack distance / at the first obstacle, then attack 1.

signal dashed(from: Vector2, to: Vector2)
signal dodge_succeeded
signal hurt(amount: int)

const CARD := "res://cards/player.tres"
const AFTERIMAGE_EVERY := 0.025 # s
const AFTERIMAGE_FADE := 0.35   # s
const FOOT_SIZE := Vector2(12, 6)
const KNOCK_TIME := 0.12        # s the hurt knock-back slide takes
const ARENA_LAYER := 8          # collision layer of the sparring-arena walls (only exist during a spar)
const CHASE_MAX_TIME := 0.3     # s, safety cap of one chase dash
const FOCUS_CLICK_GUARD := 0.3  # s after the window gets focus in which a mouse click does not attack

var stats: PlayerStats
var combat: Node                # Combat (set by main); null in isolation
var facing := "down"
var input_enabled := true
var hp := 100
var regen_calm := 0.0           # s out of combat (reset by damage / being in combat); regen starts at stats.regen_delay
var regen_acc := 0.0            # fractional HP not yet added
var regen_active := false       # HP is currently regenerating (drives the HP-bar glow)

# dodge
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_dir := Vector2.ZERO
var dash_speed := 0.0
var iframes_left := 0.0
var swap_target: Node = null    # enemy we are swapping behind (collision exception while swapping)
var swap_from := Vector2.ZERO
var swap_landing := Vector2.ZERO
var last_dodge_was_swap := false
var shadow_pos := Vector2.ZERO  # where the dodge started ("影子" = first afterimage)
var shadow_age := 99.0
var shadow_used := true
var counter_left := 0.0         # counter window remaining
var dodge_successes := 0
var since_dodge_end := 99.0     # seconds since the last dodge / swap ended (闪身追击 window)

# 闪身追击
var chase_target: Node2D = null # enemy we are dashing at (null = not chasing)
var chase_t := 0.0
var chase_counter := false      # the counter window was open when the chase started
var chase_from := Vector2.ZERO
var chase_end := Vector2.ZERO
var chase_blocked := false      # the last chase stopped at an obstacle / arena edge
var chases_started := 0
var last_attack_chased := false # the last attack 1 started with a chase dash

# attack
var attack_stage := 0           # 0 none, 1 = attack 1, 2 = attack 2
var attack_t := 0.0
var attack_hit_done := false
var attack_aim := Vector2.DOWN
var combo_is_counter := false
var attack_buffer_age := 99.0   # seconds since the last attack press (buffered while <= input_buffer)
var lunge_left := 0.0
var attacks_started := 0
var last_hits := 0

# hurt
var stun_left := 0.0
var protect_left := 0.0
var knock_vel := Vector2.ZERO
var knock_left := 0.0
var dead := false

var afterimage_parent: Node
var _afterimage_t := 0.0
var _dash_requested := false
var _attack_requested := false
var _flash_t := 0.0
var _flash_color := Color.WHITE
var _focus_guard_left := 0.0    # s left in which a mouse click only gives the game window focus
var _seen_input := false        # any key / click received yet (web: the very first click only focuses the page)
var first_click_guard := OS.has_feature("web")
var ignored_focus_clicks := 0

var sprite: AnimatedSprite2D
var flash_mat: ShaderMaterial


func _init() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | ARENA_LAYER
	safe_margin = 0.5
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FOOT_SIZE
	shape.shape = rect
	shape.position = Vector2(0, -2)
	add_child(shape)
	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.offset = Vector2(-16, -31)
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = load("res://scripts/flash.gdshader")
	sprite.material = flash_mat
	add_child(sprite)
	stats = load(CARD)
	hp = stats.max_hp


func setup(start: Vector2, dir: String) -> void:
	global_position = start
	facing = dir
	sprite.sprite_frames = CharSheet.frames_for("rabbit")
	_play("idle")


func move_input() -> Vector2:
	if not input_enabled or dead:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func is_dashing() -> bool:
	return dash_time_left > 0.0


func is_attacking() -> bool:
	return attack_stage > 0 or is_chasing()


func is_chasing() -> bool:
	return chase_target != null


func is_stunned() -> bool:
	return stun_left > 0.0


func is_invulnerable() -> bool:
	return iframes_left > 0.0 or protect_left > 0.0 or dead


func full_heal() -> void:
	hp = stats.max_hp


## 脱战回血 v1.3: called every physics frame by Combat (which is paused with the tree). Fractional HP accumulates,
## the visible hp stays an int.
func tick_regen(delta: float, in_combat: bool) -> void:
	if in_combat or dead:
		regen_calm = 0.0
		regen_acc = 0.0
		regen_active = false
		return
	regen_calm += delta
	if regen_calm < stats.regen_delay or hp >= stats.max_hp:
		regen_acc = 0.0
		regen_active = false
		return
	regen_acc += stats.regen_per_sec * delta
	var whole := int(regen_acc)
	regen_acc -= whole
	hp = mini(hp + whole, stats.max_hp)
	regen_active = hp < stats.max_hp


func _frozen() -> bool:
	return combat != null and combat.frozen


func _physics_process(delta: float) -> void:
	_focus_guard_left = maxf(0.0, _focus_guard_left - delta)
	if combat != null and combat.story_hold and not dead:
		# 序章 v1: a conversation is on screen - stand still (breathing idle), nothing advances
		velocity = Vector2.ZERO
		_play("idle")
		sprite.speed_scale = 1.0
		return
	if _frozen():
		sprite.speed_scale = 0.0
		return
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	iframes_left = maxf(0.0, iframes_left - delta)
	protect_left = maxf(0.0, protect_left - delta)
	counter_left = maxf(0.0, counter_left - delta)
	shadow_age += delta
	if not is_dashing():
		since_dodge_end += delta
	attack_buffer_age += delta
	_update_flash(delta)
	var dir := move_input()
	if _attack_requested:
		_attack_requested = false
		attack_buffer_age = 0.0
	if _dash_requested:
		_dash_requested = false
		try_dash(dir)
	if dead:
		velocity = Vector2.ZERO
		_play_action("down", "idle")
	elif stun_left > 0.0:
		stun_left -= delta
		knock_left -= delta
		velocity = knock_vel if knock_left > 0.0 else Vector2.ZERO
		move_and_slide()
		_play_action("hurt", "idle")
	elif is_dashing():
		dash_time_left -= delta
		velocity = dash_dir * dash_speed
		if swap_target != null:
			# land exactly on the checked landing point (no overshoot on the last frame)
			velocity = (swap_landing - global_position).limit_length(dash_speed * delta) / delta
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = AFTERIMAGE_EVERY
			spawn_afterimage()
		move_and_slide()
		if dash_time_left <= 0.0:
			dash_cooldown_left = stats.dodge_cooldown
			since_dodge_end = 0.0
			_end_swap()
		_play("walk")
		sprite.speed_scale = 2.0
	elif is_chasing():
		_update_chase(delta)
	else:
		_try_start_attack()
		if is_chasing():
			_update_chase(delta)
			sprite.position = global_position.round() - global_position
			return
		if attack_stage > 0:
			_update_attack(delta, dir)
		else:
			velocity = dir.normalized() * stats.walk_speed if dir != Vector2.ZERO else Vector2.ZERO
			facing = CharSheet.dir_from_vector(dir, facing)
			_play("walk" if velocity.length() > 1.0 else "idle")
			sprite.speed_scale = 1.0
		move_and_slide()
	if swap_target != null and not is_dashing():
		_end_swap()
	# draw on whole pixels so the pixel art never shimmers
	sprite.position = global_position.round() - global_position


func _unhandled_input(event: InputEvent) -> void:
	# event based, so even a very short tap between two physics ticks is never lost
	if not input_enabled or dead:
		return
	if event is InputEventMouseButton and event.pressed and is_focus_click():
		# the click that gives the (web) page / window focus must not swing
		ignored_focus_clicks += 1
		_seen_input = true
		get_viewport().set_input_as_handled()
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_seen_input = true
	if event.is_action_pressed("dash", false):
		_dash_requested = true
	elif event.is_action_pressed("attack", false):
		_attack_requested = true


## True when a mouse click right now would only be giving the game window focus.
func is_focus_click() -> bool:
	if _focus_guard_left > 0.0:
		return true
	return first_click_guard and not _seen_input


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focus_guard_left = FOCUS_CLICK_GUARD


# ------------------------------------------------------------------ attack
func _try_start_attack() -> void:
	if attack_buffer_age > stats.input_buffer or dead or not input_enabled:
		return
	if attack_stage == 0:
		if _try_start_chase():
			return
		_start_attack(1)
	elif attack_stage == 1 and attack_t >= stats.combo_window:
		_start_attack(2)


func _start_attack(stage: int, chased := false) -> void:
	if stage == 1:
		last_attack_chased = chased
	attack_stage = stage
	attack_t = 0.0
	attack_hit_done = false
	attack_buffer_age = 99.0
	attacks_started += 1
	if OS.has_feature("web"):
		print("combat: attack %d" % stage)   # lets tools/web_smoke.py confirm the J key works in the browser
	if stage == 1:
		combo_is_counter = false
	var aim := CharSheet.dir_vector(facing)
	var mv := move_input()
	if mv != Vector2.ZERO:
		aim = mv.normalized()
	if combat != null:
		var t: Node2D = combat.nearest_enemy(global_position, stats.auto_face_range)
		if chased and is_instance_valid(_chase_last_target) and _chase_last_target.is_active():
			t = _chase_last_target
		if t != null and t.global_position.distance_to(global_position) > 0.5:
			aim = (t.global_position - global_position).normalized()
	attack_aim = aim
	facing = CharSheet.dir_from_vector(aim, facing)
	lunge_left = stats.lunge_time
	var length := stats.attack1_length if stage == 1 else stats.attack2_length
	var impact := stats.attack1_impact if stage == 1 else stats.attack2_impact
	_play_action("attack%d" % stage, "walk", length, impact, true)


func _update_attack(delta: float, dir: Vector2) -> void:
	attack_t += delta
	var length := stats.attack1_length if attack_stage == 1 else stats.attack2_length
	var impact := stats.attack1_impact if attack_stage == 1 else stats.attack2_impact
	velocity = dir.normalized() * stats.walk_speed * stats.attack_move_factor if dir != Vector2.ZERO else Vector2.ZERO
	if lunge_left > 0.0:
		lunge_left -= delta
		velocity += attack_aim * (stats.lunge_distance / stats.lunge_time)
	if not attack_hit_done and attack_t >= impact:
		attack_hit_done = true
		_resolve_hit()
	if attack_t >= length:
		attack_stage = 0


func _resolve_hit() -> void:
	var stage := attack_stage
	var counter := combo_is_counter if stage == 2 else (counter_left > 0.0 or (last_attack_chased and chase_counter))
	var dmg := stats.attack1_damage if stage == 1 else stats.attack2_damage
	var knock := stats.attack1_knockback if stage == 1 else stats.attack2_knockback
	var center := global_position + attack_aim * stats.hit_offset
	last_hits = 0
	if combat != null:
		last_hits = combat.player_attack(center, stats.hit_radius, dmg, knock, counter, attack_aim, stage)
	if stage == 1:
		# the counter window is spent by the first hit that lands inside it; the whole combo counts
		combo_is_counter = counter and last_hits > 0
		if combo_is_counter:
			counter_left = 0.0
		chase_counter = false


# ------------------------------------------------------------------ 闪身追击
var _chase_last_target: Node2D = null


## Attack pressed shortly after a dodge with an enemy in range: start the chase dash instead of attacking in place.
func _try_start_chase() -> bool:
	if combat == null or since_dodge_end > stats.chase_window:
		return false
	var t: Node2D = combat.nearest_enemy(global_position, stats.chase_range)
	if t == null:
		return false
	attack_buffer_age = 99.0
	chase_counter = counter_left > 0.0
	_chase_last_target = t
	since_dodge_end = 99.0          # one chase per dodge
	if global_position.distance_to(t.global_position) <= chase_stop_distance():
		_start_attack(1, true)      # already in reach: attack at once (still counts as the chase hit)
		return true
	chase_target = t
	chase_t = 0.0
	chase_from = global_position
	chase_end = global_position
	chase_blocked = false
	chases_started += 1
	_afterimage_t = 0.0
	facing = CharSheet.dir_from_vector(t.global_position - global_position, facing)
	if OS.has_feature("web"):
		print("combat: chase")
	return true


## Distance to the target at which the chase stops: the enemy sits on the centre of the attack circle.
func chase_stop_distance() -> float:
	return stats.hit_offset


func _update_chase(delta: float) -> void:
	var t := chase_target
	if t == null or not is_instance_valid(t) or not t.is_active():
		_finish_chase()
		return
	chase_t += delta
	var to: Vector2 = t.global_position - global_position
	var dist := to.length()
	var step := minf(stats.dodge_speed * delta, maxf(0.0, dist - chase_stop_distance()))
	velocity = Vector2.ZERO
	if step > 0.01:
		var motion := to.normalized() * step
		var arena: Rect2 = combat.arena_rect.grow(-6) if combat != null and combat.spar_state == "fighting" else Rect2()
		if arena.has_area() and not arena.has_point(global_position + motion):
			chase_blocked = true    # never leave the sparring arena
		elif move_and_collide(motion) != null:
			chase_blocked = true    # wall / object / body in the way: attack from here
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = AFTERIMAGE_EVERY
			spawn_afterimage(Color(1.0, 0.95, 0.7, 0.75))
	facing = CharSheet.dir_from_vector(to, facing)
	_play("walk")
	sprite.speed_scale = 2.0
	if chase_blocked or global_position.distance_to(t.global_position) <= chase_stop_distance() + 0.5 or chase_t >= CHASE_MAX_TIME:
		_finish_chase()


func _finish_chase() -> void:
	chase_end = global_position
	chase_target = null
	velocity = Vector2.ZERO
	_start_attack(1, true)


func _cancel_chase() -> void:
	chase_target = null
	chase_counter = false


# ------------------------------------------------------------------ dodge
func try_dash(dir: Vector2) -> bool:
	if dead or stun_left > 0.0 or not input_enabled:
		return false
	if is_dashing() or dash_cooldown_left > 0.0:
		return false
	if is_chasing():
		_cancel_chase()
	if attack_stage > 0:
		if not stats.dodge_cancels_attack:
			return false
		attack_stage = 0
	dash_speed = stats.dodge_speed
	last_dodge_was_swap = false
	var enemy: Node2D = null
	if dir != Vector2.ZERO:
		dash_dir = dir.normalized()
		if combat != null:
			enemy = combat.swap_candidate(global_position, dash_dir)
	elif combat != null and combat.nearest_enemy(global_position, stats.auto_face_range) != null:
		# no direction pressed while fighting: hop back, away from the nearest enemy
		var e: Node2D = combat.nearest_enemy(global_position, stats.auto_face_range)
		dash_dir = (global_position - e.global_position).normalized()
		if dash_dir == Vector2.ZERO:
			dash_dir = -CharSheet.dir_vector(facing)
	else:
		dash_dir = CharSheet.dir_vector(facing)
	var start := global_position
	shadow_pos = start
	shadow_age = 0.0
	shadow_used = false
	iframes_left = stats.dodge_iframes
	dash_time_left = stats.dodge_time
	if enemy != null:
		var landing: Variant = combat.swap_landing(self, enemy)
		if landing != null:
			var to: Vector2 = landing - start
			dash_dir = to.normalized()
			dash_speed = to.length() / stats.dodge_time
			swap_target = enemy
			swap_from = start
			swap_landing = landing
			add_collision_exception_with(enemy)
			last_dodge_was_swap = true
	facing = CharSheet.dir_from_vector(dash_dir, facing)
	if last_dodge_was_swap:
		# land looking back at the enemy
		facing = CharSheet.dir_from_vector(-dash_dir, facing)
	_afterimage_t = 0.0
	if OS.has_feature("web"):
		print("combat: dodge%s" % (" (swap)" if last_dodge_was_swap else ""))
	dashed.emit(start, start + dash_dir * dash_speed * stats.dodge_time)
	return true


func _end_swap() -> void:
	if swap_target == null:
		return
	if is_instance_valid(swap_target):
		remove_collision_exception_with(swap_target)
		facing = CharSheet.dir_from_vector(swap_target.global_position - global_position, facing)
	swap_target = null


## Called by Combat when an enemy strike resolves. Returns true if this strike counts as a successful dodge:
## it hit the shadow left where the dodge started, no later than dodge_iframes after the dodge was pressed.
func check_shadow(center: Vector2, radius: float) -> bool:
	if shadow_used or shadow_age > stats.dodge_iframes or dead:
		return false
	if shadow_pos.distance_to(center) > radius + stats.body_radius:
		return false
	shadow_used = true
	counter_left = stats.counter_window
	dodge_successes += 1
	flash(Color(1.0, 0.85, 0.3), 0.6, 0.25)
	dodge_succeeded.emit()
	return true


# ------------------------------------------------------------------ hurt
## Enemy hit. Returns true if it did damage (false during dodge i-frames / post-hit protection).
func take_damage(amount: int, from_pos: Vector2) -> bool:
	if is_invulnerable():
		return false
	hp = maxi(hp - amount, 0)
	regen_calm = 0.0
	regen_acc = 0.0
	stun_left = stats.hurt_stun
	protect_left = stats.hurt_protect
	attack_stage = 0
	attack_buffer_age = 99.0
	dash_time_left = 0.0
	_cancel_chase()
	_end_swap()
	var away := global_position - from_pos
	away = away.normalized() if away.length() > 0.5 else -CharSheet.dir_vector(facing)
	knock_vel = away * (stats.hurt_knockback / KNOCK_TIME)
	knock_left = KNOCK_TIME
	flash(Color(1.0, 0.25, 0.2), 0.75, 0.2)
	hurt.emit(amount)
	return true


func reset_combat_state() -> void:
	stun_left = 0.0
	protect_left = 0.0
	iframes_left = 0.0
	counter_left = 0.0
	attack_stage = 0
	attack_buffer_age = 99.0
	knock_left = 0.0
	dash_time_left = 0.0
	combo_is_counter = false
	shadow_used = true
	since_dodge_end = 99.0
	_cancel_chase()
	_end_swap()
	dead = false
	sprite.rotation = 0.0
	flash(Color.WHITE, 0.0, 0.0)


func flash(c: Color, strength: float, seconds: float) -> void:
	_flash_color = c
	_flash_t = seconds
	flash_mat.set_shader_parameter("flash_color", c)
	flash_mat.set_shader_parameter("amount", strength if seconds > 0.0 else 0.0)


func _update_flash(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			flash_mat.set_shader_parameter("amount", 0.0)
	elif counter_left > 0.0:
		# gold shimmer while the counter window is open
		flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.82, 0.25))
		flash_mat.set_shader_parameter("amount", 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.03))
	else:
		flash_mat.set_shader_parameter("amount", 0.0)


# ------------------------------------------------------------------ visuals
func spawn_afterimage(tint := Color(0, 0, 0, 0)) -> void:
	if afterimage_parent == null or sprite.sprite_frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.centered = false
	ghost.offset = sprite.offset
	ghost.global_position = global_position.round()
	ghost.modulate = Color(0.62, 0.86, 1.0, 0.7) if not last_dodge_was_swap else Color(1.0, 0.86, 0.45, 0.75)
	if tint.a > 0.0:
		ghost.modulate = tint
	ghost.add_to_group("afterimage")
	afterimage_parent.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE)
	tw.tween_callback(ghost.queue_free)


func _play(kind: String) -> void:
	var anim := "%s_%s" % [kind, facing]
	sprite.rotation = 0.0
	if sprite.animation != anim:
		sprite.play(anim)
	elif not sprite.is_playing():
		sprite.play(anim)


## Plays a combat action from the combat art when it exists, otherwise `fallback` (walk/idle frames).
func _play_action(action: String, fallback: String, length := 0.0, impact := -1.0, restart := false) -> void:
	var anim := "%s_%s" % [action, facing]
	if CharSheet.has_action("rabbit", action) and sprite.sprite_frames.has_animation(anim):
		if restart or sprite.animation != anim:
			sprite.play(anim)
			sprite.frame = 0
		sprite.speed_scale = CharSheet.action_speed("rabbit", action, length, impact) if length > 0.0 else 1.0
		sprite.rotation = 0.0
		return
	_play(fallback)
	sprite.speed_scale = 2.5 if fallback == "walk" else 1.0
	if action == "down":
		sprite.rotation = -PI * 0.5 if facing != "left" else PI * 0.5
