extends SceneTree
## Combat v1.2 screenshots -> screenshots/v12_*.png (needs a window, ~30 s):
##   godot --path game2d -s tests/shots_v12.gd        (tools/screenshots_v12.sh)
## Esc help page, 闪身追击 afterimages + hit, chase that counts as a counter, bandit name plates side by side /
## stacked, spar result panel (no damage number on it), "切磋开始！" + "看破！", the key hint with the Esc line.
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
	if d.x > 0.01: Input.action_press("move_right", d.x)
	if d.x < -0.01: Input.action_press("move_left", -d.x)
	if d.y > 0.01: Input.action_press("move_down", d.y)
	if d.y < -0.01: Input.action_press("move_up", -d.y)


func place(p: Vector2, dir := "down") -> void:
	hold(Vector2.ZERO)
	player.global_position = p
	player.velocity = Vector2.ZERO
	player.facing = dir
	player.dash_cooldown_left = 0.0
	await frames(4)


func calm() -> void:
	var c: EnemyStats = fox.stats.duplicate()
	c.sidestep_chance = 0.0
	c.move_speed = 0.0
	c.interval_min = 9999.0
	c.interval_max = 9999.0
	fox.stats = c
	fox.next_attack = 9999.0


func dodge(d: Vector2) -> void:
	player.dash_cooldown_left = 0.0
	hold(d)
	await frames(1)
	await tap(KEY_SPACE)
	hold(Vector2.ZERO)
	await until(func(): return not player.is_dashing(), 30)


func pin(b: Fighter, p: Vector2) -> void:
	var st: EnemyStats = b.stats.duplicate()
	st.move_speed = 0.0
	st.interval_min = 9999.0
	st.interval_max = 9999.0
	st.aggro_range = 0.0
	st.leash_range = 0.0
	b.stats = st
	b.global_position = p
	b.engage(9999.0)
	b.next_attack = 9999.0


func _run() -> void:
	await frames(10)
	player = main.player
	combat = main.combat
	fox = combat.spar_fighter
	main.daynight.running = false
	main.daynight.set_hour(10.0)
	combat.bandits_enabled = false
	# 0 key hint with the new Esc line (start of the game)
	await place(fox.global_position + Vector2(-60, 70), "up")
	await frames(10)
	await shot("v12_00_hint_esc_line")
	main.hud.toggle_hint()
	# 1 Esc page over the training yard
	await tap(KEY_ESCAPE)
	await frames(3)
	await shot("v12_01_esc_page")
	await tap(KEY_ESCAPE)
	await frames(3)
	# 2 spar start banner + 看破 at the same time
	await place(fox.global_position + Vector2(0, 26), "up")
	await tap(KEY_E)
	await tap(KEY_1)
	calm()
	await place(fox.global_position + Vector2(36, 0), "left")
	fox.angle = 0.0
	fox.next_attack = 0.0
	await until(func(): return fox.state == "windup" and fox.stats.windup - fox.t <= 0.15)
	combat.hud.show_banner(combat.t("spar_start"), "", 1.2)
	await dodge(Vector2(-0.4, 0.92).normalized())
	fox.next_attack = 9999.0
	await frames(1)
	await shot("v12_02_banner_and_kanpo")
	# 3 chase that is a counter: afterimages on the way, then the gold hit
	key(KEY_J, true)
	await frames(3)
	key(KEY_J, false)
	await shot("v12_03_chase_counter_dash")
	await until(func(): return player.attack_stage == 1 and player.attack_hit_done, 40)
	await frames(1)
	await shot("v12_04_chase_counter_hit")
	await frames(50)
	# 4 plain chase (no 看破): afterimages + white hit number
	await place(fox.global_position + Vector2(-80, -86), "down")
	await dodge(Vector2.DOWN)
	key(KEY_J, true)
	await frames(2)
	key(KEY_J, false)
	await frames(1)
	await shot("v12_05_chase_afterimage")
	await until(func(): return player.attack_stage == 1 and player.attack_hit_done, 40)
	await frames(1)
	await shot("v12_06_chase_hit")
	await frames(50)
	# 5 spar result after the final hit: no damage number on the panel
	fox.hp = 26
	for i in 10:
		if combat.spar_state != "fighting":
			break
		await place(fox.global_position + Vector2(-30, 0), "right")
		await tap(KEY_J)
		await frames(14)
	await until(func(): return combat.spar_state == "result", 120)
	await frames(2)
	await shot("v12_07_spar_result_no_numbers")
	await until(func(): return combat.spar_state == "none", 300)
	# 6 bandits close together: name plates never on the other bandit's body
	var wolf: Fighter = combat.bandits.filter(func(b): return b.id == "wolf")[0]
	var boar: Fighter = combat.bandits.filter(func(b): return b.id == "boar")[0]
	pin(wolf, Vector2(520, 1450))
	pin(boar, Vector2(520, 1476))
	await place(Vector2(470, 1462), "right")
	await frames(6)
	await shot("v12_08_bandit_plates_stacked")
	pin(wolf, Vector2(520, 1450))
	pin(boar, Vector2(540, 1452))
	await place(Vector2(530, 1500), "up")
	await frames(6)
	await shot("v12_09_bandit_plates_side_by_side")
	print("done")
	quit(0)
