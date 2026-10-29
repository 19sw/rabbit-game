extends SceneTree
## Combat v1 screenshots -> screenshots/combat_*.png (needs a window, ~40 s):
##   godot --path game2d -s tests/shots_combat.gd        (tools/screenshots_combat.sh)
## Spar invitation, wind-up "!", slash + damage number, dodge success / counter, swap afterimage, result,
## bandits engaged, boar charge, bandits driven off, knocked out + respawn, and a 4x close-up of the actions.
const T := 32.0
var main: Node
var player: Player
var combat: Combat
var fox: Fighter
var out_dir := "res://screenshots/"


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func until(cond: Callable, limit := 600) -> bool:
	for i in limit:
		if cond.call():
			return true
		await physics_frame
	return false


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("saved ", name, " ", img.get_size())


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)


func hold(d: Vector2) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if d.x > 0.3: Input.action_press("move_right")
	if d.x < -0.3: Input.action_press("move_left")
	if d.y > 0.3: Input.action_press("move_down")
	if d.y < -0.3: Input.action_press("move_up")


func place(p: Vector2, dir := "down") -> void:
	hold(Vector2.ZERO)
	player.global_position = p
	player.velocity = Vector2.ZERO
	player.facing = dir
	await frames(4)


func calm() -> EnemyStats:
	var orig: EnemyStats = fox.stats
	var c: EnemyStats = orig.duplicate()
	c.sidestep_chance = 0.0
	c.move_speed = 0.0
	c.interval_min = 9999.0
	c.interval_max = 9999.0
	fox.stats = c
	fox.next_attack = 9999.0
	return orig


func _run() -> void:
	await frames(10)
	player = main.player
	combat = main.combat
	fox = combat.spar_fighter
	main.hud.toggle_hint()
	main.daynight.running = false
	main.daynight.set_hour(10.0)
	combat.bandits_enabled = false
	# 1 invitation
	await place(fox.global_position + Vector2(0, 26), "up")
	await tap(KEY_E)
	await frames(6)
	await shot("combat_01_spar_invite")
	await tap(KEY_1)
	await frames(30)
	await shot("combat_02_spar_start")
	var orig := calm()
	# 2 wind-up with "!"
	await place(fox.global_position + Vector2(36, 0), "left")
	fox.angle = 0.0
	fox.next_attack = 0.0
	await until(func(): return fox.state == "windup" and fox.alert)
	await frames(4)
	await shot("combat_03_windup_alert")
	# 3 dodge success -> walk back -> counter combo (gold)
	await until(func(): return fox.state == "windup" and fox.stats.windup - fox.t <= 0.15 or fox.state == "strike")
	hold(Vector2.DOWN)
	await tap(KEY_SPACE)
	hold(Vector2.ZERO)
	await frames(6)
	await shot("combat_04_dodge_success")
	fox.next_attack = 9999.0
	hold((fox.global_position - player.global_position).normalized())
	await until(func(): return player.global_position.distance_to(fox.global_position) < 40, 60)
	hold(Vector2.ZERO)
	# (试玩反馈 v1: no counter window after a dodge any more - this is now an ordinary hit; GP pictures: tests/shots_gp.gd)
	await tap(KEY_J)
	await until(func(): return player.attack_stage > 0 and player.attack_hit_done, 40)
	await frames(1)
	await shot("combat_05_counter_hit")
	await frames(40)
	# 4 normal slash + damage number
	await place(fox.global_position + Vector2(-30, 0), "right")
	await tap(KEY_J)
	await until(func(): return player.attack_stage > 0 and player.attack_hit_done, 40)
	await frames(1)
	await shot("combat_06_slash_hit_number")
	await frames(40)
	# 5 swap afterimage
	await place(fox.global_position + Vector2(-40, 4), "right")
	player.dash_cooldown_left = 0.0
	hold(Vector2.RIGHT)
	await frames(1)
	await tap(KEY_SPACE)
	hold(Vector2.ZERO)
	await frames(2)
	await shot("combat_07_swap_afterimage")
	await frames(30)
	# 6 result
	fox.stats = orig
	fox.hp = 45
	fox.next_attack = 9999.0
	for i in 30:
		if combat.spar_state != "fighting":
			break
		await place(fox.global_position + Vector2(-30, 0), "right")
		await tap(KEY_J)
		await frames(20)
	await until(func(): return combat.spar_state == "result", 120)
	await frames(10)
	await shot("combat_08_spar_result_win")
	await until(func(): return combat.spar_state == "none", 300)
	# 7 bandits engaged + boar charge
	combat.bandits_enabled = true
	var boar: Fighter = combat.bandits.filter(func(b): return b.id == "boar")[0]
	var wolf: Fighter = combat.bandits.filter(func(b): return b.id == "wolf")[0]
	await place(Vector2(600, 1440), "left")
	await frames(40)
	await shot("combat_09_bandits_engaged")
	await until(func(): return boar.state == "strike" and boar.t > 0.12, 900)
	await shot("combat_10_boar_charge")
	# 8 knocked out -> respawn
	await until(func(): return combat.player_dead, 3000)
	await frames(40)
	await shot("combat_11_player_down")
	await until(func(): return not combat.player_dead, 300)
	await frames(30)
	await shot("combat_12_respawn")
	# 9 drive them off (scripted: let the player land counters - bandits set to 1 HP for the picture)
	await place(Vector2(512, 1440), "left")
	await until(func(): return wolf.engaged and boar.engaged, 120)
	player.protect_left = 999.0
	for b in [wolf, boar]:
		b.hp = 1
	for i in 40:
		var near: Node2D = combat.nearest_enemy(player.global_position, 400)
		if near == null:
			break
		hold((near.global_position - player.global_position).normalized() if near.global_position.distance_to(player.global_position) > 34 else Vector2.ZERO)
		await tap(KEY_J)
		await frames(6)
	hold(Vector2.ZERO)
	await until(func(): return combat.bandits_cleared, 300)
	await frames(10)
	await shot("combat_13_bandits_driven_off")
	player.protect_left = 0.0
	print("done")
	quit(0)
