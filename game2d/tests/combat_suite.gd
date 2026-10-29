extends RefCounted
## Combat v1 checks, run by tests/run_tests.gd after the walking-version checks. Real key events (J, Space,
## E, 1/2, arrows / WASD), real physics, real AI. Bots: idle, masher, dodge-only, dodge-then-chase, GP (格挡, K).
## 试玩反馈 v1: the 看破反击 (counter window after a dodge) is gone - the counter comes from GP now; the winning bots
## of every suite use GP (bot_step("gp")); "human" = a human-like GP bot (K 0.30-0.55 s after the wind-up starts,
## a quarter of the blows not guarded at all).

const DOC := "docs/design/战斗数据方案-v1.3.md"   # v1.3: numbers checked against the v1.3 doc (v1.2 stays as history)
# 试玩反馈 v1 (docs/design/试玩反馈-格挡音效-方案-v1.md, client-confirmed 2026-10-27): the 看破反击 fields left the player
# card (rows still in v1.3 appendix A as history) and the 格挡 (GP) fields came in - checked here against that plan.
const REMOVED_FIELDS := ["player.counter_window", "player.counter_multiplier"]
const GP_FIELDS := {"gp_stance": 0.25, "gp_whiff_recover": 0.4, "gp_cooldown": 0.3, "gp_counter_damage": 30,
	"gp_enemy_stagger": 0.6, "gp_hitstop": 0.1, "gp_knockback": 16.0}   # (knock-back: the plan gives no number - attack 2's 16)

var r                     # the runner (SceneTree with check(), frames(), key(), tap(), teleport(), hold_dir() ...)
var main: Node
var player: Player
var combat: Combat
var fox: Fighter
var wolf: Fighter
var boar: Fighter
var bot_results := {}     # for the report
var _j_down := false
var _space_down := false
var _k_down := false
var human_rng := RandomNumberGenerator.new()   # the "human" GP bot's reaction times (seed it per run)
var _human_plan := {}       # [fighter, strike number] -> reaction time (s after the wind-up started) or -1 (not guarded)
var _gp_for := {}           # fighter -> strike number K was pressed for
var _atk_cd := 0.0
var _dodged_for := {}
var _bot_t := 0.0
var _punish_until := -1.0
var fox_min := Vector2.INF
var fox_max := -Vector2.INF
var idle_death_time := 0.0
const V1_IDLE_DEATH := 16.4   # s, measured by this same test with the v1/v1.1 bandit cards (24/10, 48/20)


func _init(runner) -> void:
	r = runner
	main = r.main
	player = r.player
	combat = main.combat
	for f in combat.fighters:
		match f.id:
			"fox": fox = f
			"wolf": wolf = f
			"boar": boar = f


func run() -> void:
	await test_cards_vs_doc()
	await test_art_and_font()
	await test_hud_layout()
	await test_combo_buffer_autoface()
	await test_iframes()
	await test_dodge_success_and_counter()
	await test_swap()
	await test_swap_never_into_walls()
	await test_spar_cancel_and_interaction()
	await test_spar_arena()
	await test_spar_flows_and_bots()
	await test_card_changes_behaviour()
	await test_bandits()
	_release()


# ================================================================== helpers
func _release() -> void:
	r.release_all()
	Input.action_release("attack")
	if _j_down:
		r.key(KEY_J, false)
		_j_down = false
	if _space_down:
		r.key(KEY_SPACE, false)
		_space_down = false
	if _k_down:
		r.key(KEY_K, false)
		_k_down = false


func reset_all() -> void:
	_release()
	if combat.spar_state == "choosing":
		combat.close_choice(false)
	if combat.spar_state == "fighting":
		combat.end_spar(false)
	if combat.spar_state == "result":
		combat._timer = 0.0
		combat._finish_spar()
	if combat.player_dead:
		combat._timer = 0.0
		combat._respawn()
	combat.hitstop_left = 0.0
	combat.frozen = false
	for b in combat.bandits:
		if b.state != "gone" and b.state != "down":
			b.reset_home(true)
	fox.reset_home(true)
	player.reset_combat_state()
	player.full_heal()
	player.input_enabled = true
	player.dash_cooldown_left = 0.0
	await r.frames(3)


func spot_near(n: Node2D) -> Vector2:
	for off in [Vector2(0, 26), Vector2(-26, 0), Vector2(26, 0), Vector2(0, -26)]:
		if r.is_free(n.global_position + off):
			return n.global_position + off
	return Vector2.INF


func start_spar_keys() -> void:
	await r.teleport(spot_near(fox))
	await r.tap(KEY_E)
	await r.tap(KEY_1)
	await r.frames(2)


## Freezes 师兄 for mechanic tests: he chases/stands but never attacks or sidesteps (a private copy of his card).
func calm_fox() -> EnemyStats:
	var orig: EnemyStats = fox.stats
	var calm: EnemyStats = orig.duplicate()
	calm.sidestep_chance = 0.0
	calm.move_speed = 0.0
	calm.interval_min = 9999.0
	calm.interval_max = 9999.0
	fox.stats = calm
	fox.next_attack = 9999.0
	return orig


func press_j() -> void:
	r.key(KEY_J, true)
	_j_down = true


func press_space() -> void:
	r.key(KEY_SPACE, true)
	_space_down = true


func press_k() -> void:
	r.key(KEY_K, true)
	_k_down = true


## Seconds from now until `f`'s blow can reach the player (wind-up left, plus - for a charge / pounce - the time the
## lunge needs to close the gap). What a perfect GP bot aims its K at.
func blow_eta(f: Fighter) -> float:
	var left: float = maxf(0.0, f.stats.windup - f.t) if f.state == "windup" else 0.0
	if f.state == "strike" and f.attack_kind_now() == "charge":
		left = 0.0                # the charge is under way: only the gap is left
	if f.attack_kind_now() != "charge":
		return left
	var speed: float = f._lunge() / maxf(f._strike_t(), 0.01)
	var gap: float = f.global_position.distance_to(player.global_position) - (f.stats.hit_radius + player.stats.body_radius)
	return left + maxf(0.0, gap) / maxf(speed, 1.0)


## A blow from `f` is on its way: its wind-up, or a charge / pounce still closing in (not yet landed).
func blow_coming(f: Fighter) -> bool:
	return f.state == "windup" or (f.state == "strike" and f.attack_kind_now() == "charge" and not f.struck)


## Should the GP bot press K for `f` now? perfect: so that the stance (0.25 s) is up when the blow arrives (K about
## 0.12 s before it); human: at its planned reaction time after the wind-up started (0.30-0.55 s), or never (25 %).
func gp_time_ok(f: Fighter, human: bool) -> bool:
	if not blow_coming(f) or _gp_for.get(f, -1) == attack_id(f):
		return false
	if human:
		var key := [f.get_instance_id(), attack_id(f)]
		if not _human_plan.has(key):
			_human_plan[key] = -1.0 if human_rng.randf() < 0.25 else human_rng.randf_range(0.30, 0.55)
		var rt: float = _human_plan[key]
		var since: float = f.t if f.state == "windup" else f.stats.windup + f.t
		return rt >= 0.0 and since >= rt
	return blow_eta(f) <= 0.12


## Which attack of `f` this is (its strike count when the wind-up started; the count goes up as the blow starts).
func attack_id(f: Fighter) -> int:
	return f.strikes if f.state == "windup" else f.strikes - 1


## One bot decision (called once per physics frame).
## kind: idle | masher | dodger | chase | gp | human | dodger_p | chase_p | gp_p
##   chase     : dodges at the end of a wind-up (into 师兄 = swap), then attacks at once - inside the 0.6 s chase window
##               this is the 闪身追击 (v1.2; 试玩反馈 v1: locked on, it always lands)
##   dodger    : same dodges, but waits until the chase window is over before attacking (no chase)
##   gp        : presses K (格挡) so that the stance is up when the blow lands, lets the counter run; otherwise walks in
##               and attacks
##   human     : like gp, but K comes 0.30-0.55 s after the wind-up starts and a quarter of the blows are not guarded
##   *_p       : "punish-only" variants - attack only during the 2 s after a dodge / a caught blow, otherwise keep ~50 px away
func bot_step(kind: String) -> void:
	if _j_down:
		r.key(KEY_J, false)
		_j_down = false
	if _space_down:
		r.key(KEY_SPACE, false)
		_space_down = false
	if _k_down:
		r.key(KEY_K, false)
		_k_down = false
	_atk_cd -= 1.0 / 60.0
	_bot_t += 1.0 / 60.0
	if kind == "idle" or player.dead:
		r.hold_dir(Vector2.ZERO)
		return
	var enemies := combat.engaged_enemies()
	if enemies.is_empty():
		r.hold_dir(Vector2.ZERO)
		return
	var target: Node2D = enemies[0]
	for e in enemies:
		if e.global_position.distance_to(player.global_position) < target.global_position.distance_to(player.global_position):
			target = e
	var to: Vector2 = target.global_position - player.global_position
	var d := to.length()
	var base := kind.trim_suffix("_p")
	var punish_only := kind.ends_with("_p")
	if base == "gp" or base == "human":
		if player.gp_countering or player.in_gp_stance():
			r.hold_dir(Vector2.ZERO)
			if player.gp_countering:
				_punish_until = _bot_t + 2.0
			return
		for f in enemies:
			var tf: Vector2 = f.global_position - player.global_position
			var reach: float = f.stats.attack_range + 40.0 if f.attack_kind_now() != "charge" else f._lunge() + 50.0
			if tf.length() < reach and gp_time_ok(f, base == "human"):
				_gp_for[f] = attack_id(f)
				if player.gp_cooldown_left <= 0.0 and not player.is_dashing() and player.stun_left <= 0.0:
					r.hold_dir(Vector2.ZERO)
					press_k()
					return
	if base == "dodger" or base == "chase":
		for f in enemies:
			var tf: Vector2 = f.global_position - player.global_position
			var reach: float = f.stats.attack_range + 40.0 if f.stats.attack_kind != "charge" else f.stats.strike_lunge + 50.0
			if f.state == "windup" and f.stats.windup - f.t <= 0.2 and tf.length() < reach and _dodged_for.get(f, -1) != f.strikes \
					and not player.is_dashing() and player.dash_cooldown_left <= 0.0:
				var dir := tf.normalized().orthogonal()
				if base == "chase" and tf.length() <= 60.0 and f.stats.attack_kind != "charge":
					dir = tf.normalized()   # dodge into him -> swap behind
				r.hold_dir(dir)
				press_space()
				_dodged_for[f] = f.strikes
				_punish_until = _bot_t + 2.0
				return
		if base == "dodger" and player.since_dodge_end <= player.stats.chase_window:
			# "会闪避但不追击": waits until the chase window has passed before attacking again
			r.hold_dir(Vector2.ZERO)
			return
		if base == "chase" and not player.is_dashing() and player.since_dodge_end <= player.stats.chase_window \
				and d <= player.stats.chase_range and _atk_cd <= 0.0:
			# 闪身追击: press J right after the dodge - the rabbit dashes in by itself
			r.hold_dir(Vector2.ZERO)
			press_j()
			_atk_cd = 0.1
			return
	if punish_only and _bot_t > _punish_until:
		# wait for his attack: stay close enough that he attacks, never swing
		r.hold_dir(to.normalized() if d > 50.0 else Vector2.ZERO)
		return
	r.hold_dir(to.normalized() if d > 34.0 else Vector2.ZERO)
	if d < 62.0 and _atk_cd <= 0.0:
		press_j()
		_atk_cd = 0.1


## Runs one spar with a bot. Returns {win, time, hp, fox_hp}
func run_spar(kind: String, seed_v: int, limit := 90.0) -> Dictionary:
	await reset_all()
	combat.rng.seed = seed_v
	human_rng.seed = seed_v
	_dodged_for = {}
	_gp_for = {}
	_human_plan = {}
	_punish_until = -1.0
	await start_spar_keys()
	var t := 0.0
	while combat.spar_state == "fighting" and t < limit:
		bot_step(kind)
		await r.physics_frame
		t += 1.0 / 60.0
		fox_min = fox_min.min(fox.global_position)
		fox_max = fox_max.max(fox.global_position)
	_release()
	var res := {"win": combat.spar_state == "result" and combat.last_spar_win, "time": t, "hp": player.hp, "fox_hp": fox.hp,
		"ended": combat.spar_state == "result"}
	return res


# ================================================================== tests
func test_cards_vs_doc() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(DOC)
	var md := FileAccess.get_file_as_string(path)
	r.check(md.length() > 1000, "AC1 doc: 战斗数据方案-v1.3.md exists", path)
	var app := md.substr(md.find("## 附录 A"))
	var cards := {}
	for c in ["player", "shixiong", "wolf", "boar", "combat_rules"]:
		cards[c] = load("res://cards/%s.tres" % c)
	var bad := ""
	var n := 0
	var seen := {}
	var re := RegEx.new()
	re.compile("(?m)^\\| (\\w+) \\| (\\w+) \\| ([^|]+?) \\|")
	var removed_ok := true
	for m in re.search_all(app):
		var card := m.get_string(1)
		if not cards.has(card):
			continue
		var field := m.get_string(2)
		if REMOVED_FIELDS.has(card + "." + field):
			removed_ok = removed_ok and not field in cards[card]
			continue
		var want := m.get_string(3).strip_edges()
		var res: Resource = cards[card]
		if not field in res:
			bad += "%s.%s missing; " % [card, field]
			continue
		var got = res.get(field)
		var ok := false
		match typeof(got):
			TYPE_BOOL: ok = str(got).to_lower() == want
			TYPE_STRING: ok = got == want
			_: ok = absf(float(got) - want.to_float()) < 1e-6
		if not ok:
			bad += "%s.%s card=%s doc=%s; " % [card, field, got, want]
		n += 1
		seen[card + "." + field] = true
	var gp_bad := ""
	for k in GP_FIELDS:
		seen["player." + k] = true
		if not k in cards["player"] or absf(float(cards["player"].get(k)) - float(GP_FIELDS[k])) > 1e-6:
			gp_bad += "%s=%s (plan %s) " % [k, cards["player"].get(k), GP_FIELDS[k]]
	# every value on every card is listed in the doc (试玩反馈 v1: the GP fields in the feedback plan, checked above)
	var undocumented := ""
	for c in cards:
		for p in cards[c].get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not seen.has(c + "." + p["name"]):
				undocumented += c + "." + p["name"] + " "
	r.check(bad == "" and n >= 98, "AC1 cards: all %d values in appendix A of v1.3 match the .tres cards (试玩反馈 v1: the 2 看破反击 rows are gone from the card)" % n, bad)
	r.check(removed_ok, "试玩反馈 v1 cards: the 看破反击 fields (counter_window, counter_multiplier) are no longer on the player card")
	r.check(gp_bad == "", "试玩反馈 v1 cards: the GP numbers on cards/player.tres are the plan's (stance 0.25, too early 0.4, cooldown 0.3, counter 30, stagger 0.6, hitstop 0.1)", gp_bad)
	r.check(undocumented == "", "AC1 cards: every card field is documented (v1.3 appendix A; the GP fields: 试玩反馈 plan, above)", undocumented)
	# key decisions spelled out
	var sx: EnemyStats = cards["shixiong"]
	var pl: PlayerStats = cards["player"]
	# v1.2 (client-confirmed table): 师兄 120 HP / 12 dmg / 0.85 s wind-up / 1.4-2.2 s interval / 10% sidestep /
	# no super armour / stagger delays his next attack 0.5 s; 狼 60/14, 野猪 110/22; 闪身追击 0.6 s / 96 px
	var wo: EnemyStats = cards["wolf"]
	var bo: EnemyStats = cards["boar"]
	r.check(sx.max_hp == 120 and sx.damage == 12 and sx.windup == 0.85 and sx.interval_min == 1.4 and sx.interval_max == 2.2
		and sx.sidestep_chance == 0.1 and not sx.super_armor and sx.stagger_delays_attack and sx.stagger_attack_delay == 0.5
		and not sx.can_swap and wo.max_hp == 60 and wo.damage == 14 and bo.max_hp == 110 and bo.damage == 22
		and pl.gp_counter_damage == 30 and pl.dodge_iframes == 0.3 and pl.chase_window == 0.6 and pl.chase_range == 96.0,
		"AC1 decisions (v1.2 table; 试玩反馈 v1: GP counter 30 = the old 12 + 18 counter): 师兄 120/12, wind-up 0.85, interval 1.4-2.2, sidestep 10%, no super armour, stagger delay 0.5; 狼 60/14; 野猪 110/22; chase 0.6 s / 96 px")
	# hits to lose: 6 hits leave 28 (> 20), the 7th ends it
	var hp := pl.max_hp
	var hits := 0
	while hp > int(floor(pl.max_hp * sx.end_fraction)):
		hp -= sx.damage
		hits += 1
	r.check(hits == 7, "AC1 math: 师兄 at 12 damage beats the player on the 7th hit (v1.2)", "%d hits" % hits)
	for s in ["相对 v1.1 的变化", "挨 7 下输", "向上取整", "96 点", "587 px", "493 px", "闪身追击", "0.6 秒", "推迟下一招"]:
		if not s in md:
			r.check(false, "AC1 doc: contains '%s'" % s)
	r.check(not Tuning.data().has("walk_speed") and str(Tuning.data().get("_已迁移", "")).contains("player.tres"),
		"AC1 data: tuning.json no longer holds walk_speed and says where it went")


func test_art_and_font() -> void:
	var art_present := FileAccess.file_exists("res://assets/combat/rabbit_combat.json")
	if art_present:
		var all := true
		for id in ["rabbit", "fox", "wolf", "boar"]:
			for a in ["attack1", "attack2", "hurt", "down"]:
				all = all and CharSheet.has_action(id, a)
			if id != "rabbit":
				all = all and CharSheet.has_action(id, "windup")
		r.check(all and combat.fx.art and combat.fx.effects.has("slash") and combat.fx.effects.has("alert"),
			"art: combat sheets (4 characters) and effect sheets are loaded through the sync tool")
		var sf: SpriteFrames = CharSheet.frames_for("rabbit")
		var tex: Texture2D = sf.get_frame_texture("attack1_right", 0)
		r.check(tex.get_width() == 32 and tex.get_height() == 32, "art: combat frames are 32x32")
	else:
		r.check(not CharSheet.has_action("rabbit", "attack1"), "art: no combat art yet - walk-frame fallback in use")
	# every UI character used by combat exists in the bitmap font
	var font: Font = load("res://fonts/ui_font.fnt")
	var text := FileAccess.get_file_as_string("res://data/combat.json") + "生命/0123456789▶" + Hud.HINT_TEXT + PauseMenu.all_text()
	for n in main.npcs:
		text += n.full_name
	var missing := ""
	for c in text:
		if c != "\n" and c != " " and not font.has_char(c.unicode_at(0)):
			missing += c
	r.check(missing == "", "font: every combat UI character exists in the font", missing)


func test_hud_layout() -> void:
	await reset_all()
	await r.frames(2)
	var hp_rect: Rect2 = combat.hud.hp_panel.get_global_rect()
	var mm: Minimap = main.hud.minimap
	var others := {"minimap": Rect2(mm.global_position, mm.size), "objective": main.hud.objective.get_global_rect(),
		"clock": main.hud.clock.get_global_rect(), "hint": main.hud.hint.get_global_rect()}
	var ov := ""
	for k in others:
		if hp_rect.intersects(others[k]):
			ov += k + " "
	r.check(combat.hud.hp_label.text == "生命 100/100" and ov == "" and hp_rect.position.x < 240 and hp_rect.position.y < 20,
		"AC7 HUD: '生命 100/100' bar next to the minimap, overlapping nothing", "%s %s %s" % [combat.hud.hp_label.text, hp_rect, ov])


func test_combo_buffer_autoface() -> void:
	await reset_all()
	await start_spar_keys()
	var orig := calm_fox()
	var fp := fox.global_position
	await r.teleport(fp + Vector2(-30, 0))
	player.facing = "up"
	await r.frames(2)
	var hp0 := fox.hp
	# J -> attack 1, auto-faces 师兄 (30 px away, inside 96)
	await r.tap(KEY_J)
	var faced := player.facing
	var stage1 := player.attack_stage
	await r.frames(8)   # 12 frames = 0.2 s: the 0.17 s impact has happened
	var hp1 := fox.hp
	r.check(stage1 == 1 and faced == "right" and hp0 - hp1 == 8, "AC3 combo: J starts attack 1, auto-faces the enemy, hits for 8",
		"stage %d facing %s dmg %d" % [stage1, faced, hp0 - hp1])
	r.check(combat.fx.spawned.get("slash", 0) > 0 and "8" in combat.hud.number_texts(), "AC7 feedback: slash effect and damage number '8' shown")
	# press J again at ~0.2 s (before the 0.30 s combo window): buffered, attack 2 starts at 0.30 s
	await r.frames(0)
	await r.tap(KEY_J)
	var buffered_stage := player.attack_stage
	var t_wait := 0
	while player.attack_stage != 2 and t_wait < 30:
		await r.physics_frame
		t_wait += 1
	var started_at := player.attack_t
	await r.frames(16)
	var hp2 := fox.hp
	r.check(buffered_stage == 1 and t_wait <= 10 and started_at < 0.1, "AC3 buffer: an early second press is remembered and becomes attack 2 at the combo window",
		"attack 2 started after %d more frames" % t_wait)
	r.check(hp1 - hp2 == 12, "AC3 combo: attack 2 hits for 12", "%d" % (hp1 - hp2))
	await r.frames(40)
	r.check(player.attack_stage == 0, "AC3 combo: only two hits - the combo ends after attack 2")
	# a press too early (more than 0.30 s before attack 2 ends) is NOT kept
	await r.tap(KEY_J)
	await r.frames(14)
	await r.tap(KEY_J)   # ~0.27 s into attack 1 -> buffered -> attack 2
	await r.frames(10)
	await r.tap(KEY_J)   # early in attack 2 (0.63 s long): expires before it ends
	await r.frames(50)
	r.check(player.attack_stage == 0, "AC3 buffer: presses older than 0.30 s are dropped (no third attack)")
	# auto-face only inside 96 px
	await r.teleport(fp + Vector2(-130, 0))
	player.facing = "up"
	await r.frames(2)
	await r.tap(KEY_J)
	r.check(player.facing == "up", "AC3 auto-face: an enemy 130 px away (outside 96 px) does not turn the player")
	await r.frames(40)
	# slowed movement while attacking
	await r.teleport(fp + Vector2(-60, 60))
	r.hold_dir(Vector2.DOWN)
	await r.frames(1)
	press_j()
	await r.frames(1)
	r.key(KEY_J, false); _j_down = false
	await r.frames(9)   # lunge over
	var p0 := player.global_position
	await r.frames(12)
	var v := (player.global_position - p0).length() / 0.2
	r.release_all()
	r.check(player.attack_stage == 1 and absf(v - player.stats.walk_speed * player.stats.attack_move_factor) < 6.0,
		"AC3 attack: moving while attacking is slowed to 0.2x walking speed", "%.1f px/s" % v)
	fox.stats = orig
	await reset_all()


func test_iframes() -> void:
	await reset_all()
	await start_spar_keys()
	var orig := calm_fox()
	await r.teleport(fox.global_position + Vector2(0, 30))
	player.facing = "left"
	await r.frames(2)
	var hp0 := player.hp
	await r.tap(KEY_SPACE)
	# during the dodge (and up to 0.30 s after pressing) a strike right on the player does nothing
	combat.enemy_strike(fox, player.global_position, 24.0)
	await r.frames(8)
	combat.enemy_strike(fox, player.global_position, 24.0)
	var during := player.hp
	await r.frames(14)   # > 0.30 s since the press
	combat.enemy_strike(fox, player.global_position, 24.0)
	var after := player.hp
	r.check(during == hp0 and after == hp0 - fox.stats.damage, "AC3 i-frames: hits during the 0.30 s dodge window do no damage; after it they do",
		"hp %d -> during %d -> after %d" % [hp0, during, after])
	r.check(player.is_stunned() and "-%d" % fox.stats.damage in combat.hud.number_texts(), "AC7 hurt: stun + red damage number")
	await r.frames(1)
	combat.enemy_strike(fox, player.global_position, 24.0)
	r.check(player.hp == after, "AC3 hurt: 0.55 s protection after being hit")
	fox.stats = orig
	await reset_all()


## Puts 师兄 into a real wind-up right in front of the player; returns when the strike is `lead` seconds away.
func _fox_windup_until(lead: float) -> void:
	fox.next_attack = 0.0
	var guard := 0
	while not (fox.state == "windup" and fox.stats.windup - fox.t <= lead) and guard < 400:
		await r.physics_frame
		guard += 1


func test_dodge_success_and_counter() -> void:
	await reset_all()
	await start_spar_keys()
	var orig := calm_fox()
	var calm: EnemyStats = fox.stats
	calm.move_speed = 0.0
	await r.teleport(fox.global_position + Vector2(36, 0))
	fox.angle = PI   # facing the player (left?) - make him face right, towards the player
	fox.angle = 0.0
	await r.frames(2)
	var succ0 := player.dodge_successes
	# too early: dodge 0.5 s before the strike -> the strike does not hit the shadow in time -> no success
	await _fox_windup_until(0.5)
	r.hold_dir(Vector2.DOWN)
	await r.tap(KEY_SPACE)
	r.release_all()
	await r.frames(40)
	var early_ok := player.dodge_successes == succ0
	r.check(early_ok, "AC3 dodge: dodging 0.5 s before the strike is NOT a dodge success (shadow rule: 0.30 s)")
	fox.next_attack = 9999.0
	await r.frames(60)
	await r.teleport(fox.global_position + Vector2(36, 0))
	player.dash_cooldown_left = 0.0
	fox.angle = 0.0
	var hp0 := player.hp
	# right timing: 0.15 s before the strike, side-step
	await _fox_windup_until(0.15)
	r.check(combat.fx.alert_visible(fox), "AC7 wind-up: red '!' over 师兄 once his direction is locked")
	r.hold_dir(Vector2.DOWN)
	await r.tap(KEY_SPACE)
	r.release_all()
	await r.frames(12)
	r.check(player.dodge_successes == succ0 + 1 and player.hp == hp0 and "看破！" in combat.hud.number_texts(),
		"AC3 dodge success: dodging at the end of the wind-up -> success ('看破！'), no damage",
		"successes %d hp %d %s" % [player.dodge_successes, player.hp, combat.hud.number_texts()])
	fox.next_attack = 9999.0
	# 试玩反馈 v1: no 看破反击 any more - the combo right after a dodge success is the ordinary 8 + 12, no gold 反击
	# (the counter now comes from GP: 12 + 18 = 30, gold numbers - tests/gp_suite.gd)
	var gold0: int = combat.hud.number_texts().filter(func(s): return "反击" in s).size()
	var arcs0: int = combat.fx.spawned.get("slash_counter", 0) + combat.fx.spawned.get("counter_text", 0)
	var fh0 := fox.hp
	r.hold_dir((fox.global_position - player.global_position).normalized())
	var g := 0
	while player.global_position.distance_to(fox.global_position) > 40 and g < 40:
		await r.physics_frame
		g += 1
	r.release_all()
	await r.tap(KEY_J)
	await r.frames(12)
	var d1 := fh0 - fox.hp
	await r.tap(KEY_J)
	await r.frames(30)
	var d2 := fh0 - fox.hp - d1
	var gold := combat.hud.number_texts().filter(func(s): return "反击" in s)
	var arcs: int = combat.fx.spawned.get("slash_counter", 0) + combat.fx.spawned.get("counter_text", 0)
	r.check(d1 == 8 and d2 == 12 and gold.size() == gold0 and arcs == arcs0,
		"试玩反馈 v1: 看破反击 is gone - the combo right after a dodge success does the ordinary 8 + 12 (no x1.5, no gold 反击)",
		"%d + %d, gold %s" % [d1, d2, gold])
	fox.stats = orig
	await reset_all()


func test_swap() -> void:
	await reset_all()
	await start_spar_keys()
	var orig := calm_fox()
	var fp := fox.global_position
	await r.teleport(fp + Vector2(-40, 0))
	await r.frames(2)
	r.hold_dir(Vector2.RIGHT)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	var ghosts := 0
	for i in 12:
		if not player.is_dashing():
			break
		await r.physics_frame
		ghosts = maxi(ghosts, r.get_nodes_in_group("afterimage").size())
	r.release_all()
	await r.frames(4)
	var p := player.global_position
	r.check(player.last_dodge_was_swap and p.x > fp.x + 20 and absf(p.distance_to(fp) - 28.0) < 4.0 and r.is_free(p) and ghosts >= 3,
		"AC3 swap: dodging towards 师兄 (40 px) lands behind him (~28 px) with afterimages", "end %s fox %s ghosts %d" % [p.round(), fp, ghosts])
	await r.frames(40)
	# from below at an angle > 60 deg: normal dodge
	await r.teleport(fp + Vector2(-40, 0))
	player.dash_cooldown_left = 0.0
	r.hold_dir(Vector2.UP)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	await r.frames(14)
	r.release_all()
	r.check(not player.last_dodge_was_swap and player.global_position.y < fp.y - 50, "AC3 swap: dodging 90 deg away from the enemy is a normal dodge")
	await r.frames(40)
	# too far (80 px > 64): normal dodge
	await r.teleport(fp + Vector2(-80, 0))
	r.hold_dir(Vector2.RIGHT)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	await r.frames(14)
	r.release_all()
	r.check(not player.last_dodge_was_swap and player.global_position.x < fp.x, "AC3 swap: an enemy 80 px away (> 64) is not swapped with")
	fox.stats = orig
	await reset_all()


func test_swap_never_into_walls() -> void:
	## A pinned bandit is placed right next to every kind of obstacle (walls, cliffs, buildings, fences, trees...);
	## the player dodges into it from the other side. The landing would be inside / beyond the obstacle, so the
	## swap must fall back to a normal dodge: the player must end on free ground on the starting side.
	await reset_all()
	var w := wolf
	var orig: EnemyStats = w.stats
	var pin: EnemyStats = orig.duplicate()
	pin.move_speed = 0.0
	pin.interval_min = 9999.0
	pin.interval_max = 9999.0
	pin.turn_time = 99.0
	w.stats = pin
	var tested := 0
	var swaps_ok := 0
	var bad := []
	var cases := []
	var by_kind := {}
	for c in r.data["colliders"]:
		if c["kind"] == "bounds":
			continue
		var k: String = c["kind"]
		if by_kind.get(k, 0) >= (24 if k == "tile" else 6):
			continue
		by_kind[k] = by_kind.get(k, 0) + 1
		var rc: Array = c["rect"]
		var rect := Rect2(rc[0], rc[1], rc[2], rc[3])
		var cx := rect.get_center().x
		cases.append([rect, Vector2(cx, rect.end.y + 8), Vector2(cx, rect.end.y + 8 + 34), Vector2.UP, k])       # from below
		cases.append([rect, Vector2(cx, rect.position.y - 2), Vector2(cx, rect.position.y - 2 - 34), Vector2.DOWN, k])  # from above
	for cs in cases:
		var rect: Rect2 = cs[0]
		var wp: Vector2 = cs[1]
		var pp: Vector2 = cs[2]
		if not r.is_free(pp) or not _free_for_npc(wp, w):
			continue
		await r.teleport(pp)
		w.global_position = wp
		w.engage(9999.0)
		w.next_attack = 9999.0
		w.angle = (pp - wp).angle()
		player.dash_cooldown_left = 0.0
		await r.frames(2)
		r.hold_dir(cs[3])
		await r.frames(1)
		await r.tap(KEY_SPACE)
		await r.frames(14)
		r.release_all()
		await r.frames(2)
		tested += 1
		var e := player.global_position
		var same_side: bool = e.y > rect.end.y - 1.0 if cs[3] == Vector2.UP else e.y < rect.position.y + 1.0
		if not r.is_free(e) or not same_side:
			bad.append("%s %s: start %s -> %s (swap %s)" % [cs[4], rect, pp, e.round(), player.last_dodge_was_swap])
	# positive control in the open: the same setup without an obstacle does swap
	await r.teleport(Vector2(1000, 1060))
	w.global_position = Vector2(1000, 1026)
	player.dash_cooldown_left = 0.0
	await r.frames(2)
	r.hold_dir(Vector2.UP)
	await r.frames(1)
	await r.tap(KEY_SPACE)
	await r.frames(14)
	r.release_all()
	swaps_ok = 1 if player.last_dodge_was_swap and player.global_position.y < 1026 else 0
	w.stats = orig
	w.reset_home(true)
	r.check(bad.is_empty() and tested > 60 and swaps_ok == 1,
		"AC3 swap safety: next to %d obstacles (walls, cliffs, buildings, fences, trees, rocks...) the swap never lands inside or beyond them" % tested,
		"kinds %s; failures %s" % [by_kind.keys(), bad])
	await reset_all()


func _free_for_npc(p: Vector2, ex: Node2D) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var s := RectangleShape2D.new()
	s.size = Vector2(14, 7)
	q.shape = s
	q.transform = Transform2D(0.0, p + Vector2(0, -2.5))
	q.collision_mask = 1
	q.exclude = [ex.get_rid(), player.get_rid()]
	return main.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func test_spar_cancel_and_interaction() -> void:
	await reset_all()
	await r.teleport(spot_near(fox))
	await r.tap(KEY_E)
	var shown: bool = combat.hud.choice.visible and combat.hud.choice_title.text == "来过两招？" \
		and "切磋" in combat.hud.choice_opts[0].text and "算了" in combat.hud.choice_opts[1].text
	await r.tap(KEY_2)
	await r.frames(3)
	r.check(shown and combat.spar_state == "none" and not fox.engaged and not combat.hud.choice.visible and player.input_enabled,
		"AC4 spar: E -> '来过两招？ 切磋 / 算了'; key 2 (算了) does not start a fight")
	# arrow keys + E: down selects 算了
	await r.tap(KEY_E)
	await r.tap(KEY_DOWN)
	var sel := combat.hud.choice_index
	await r.tap(KEY_E)
	await r.frames(3)
	r.check(sel == 1 and combat.spar_state == "none" and not fox.engaged, "AC4 spar: ↓ + E also chooses 算了")
	# ↑ + E starts it
	await r.tap(KEY_E)
	await r.tap(KEY_DOWN)
	await r.tap(KEY_UP)
	await r.tap(KEY_E)
	await r.frames(3)
	r.check(combat.spar_state == "fighting" and fox.engaged and combat.hud.plate_visible(fox),
		"AC4 spar: ↑ + E chooses 切磋 - fight starts, 师兄 shows name plate + HP bar")
	r.check(combat.hud.banner.text == "切磋开始！", "AC4 spar: start message shown", combat.hud.banner.text)
	# other NPCs cannot be talked to during the spar
	var crane: Npc = main.npcs.filter(func(n): return n.id == "crane")[0]
	var saved := player.global_position
	player.global_position = spot_near(crane)
	await r.frames(3)
	var talk: bool = main.interact()
	var prompt: bool = main.hud.prompt.visible
	await r.tap(KEY_E)
	r.check(not talk and not prompt and not main.hud.bubble.visible, "AC4 spar: during the spar E does nothing and no '按 E 交谈' prompt appears")
	player.global_position = saved
	await reset_all()


func test_spar_arena() -> void:
	await reset_all()
	await start_spar_keys()
	var orig := calm_fox()
	var arena := combat.arena_rect
	var worst := ""
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
		r.hold_dir(d)
		for i in 8:
			await r.frames(20)
			player.dash_cooldown_left = 0.0
			await r.tap(KEY_SPACE)
		var p := player.global_position
		if not arena.grow(1).has_point(p):
			worst += "%s->%s " % [d, p.round()]
	r.release_all()
	r.check(worst == "", "AC4 arena: walking and dashing at every edge never leaves the 练武场 during a spar", "arena %s %s" % [arena, worst])
	fox.stats = orig
	await reset_all()
	# after the spar the walls are gone: the player can walk out
	await r.teleport(Vector2(1000, 1140))
	await r.push(Vector2.DOWN, 0.8)
	r.check(player.global_position.y > arena.end.y, "AC4 arena: after the spar the yard is open again")


func test_spar_flows_and_bots() -> void:
	# --- full lose flow (idle bot)
	var lose := await run_spar("idle", 11)
	var title_l := combat.hud.result_title.text
	var line_l := combat.hud.result_line.text
	r.check(lose["ended"] and not lose["win"] and lose["hp"] <= 20 and combat.hud.result_panel.visible and title_l == "你输了" and line_l.begins_with("师兄："),
		"AC4/AC5 lose flow: an idle player loses (HP <= 20%%), '你输了' + a line from 师兄", "%s / %s, %.1f s, hp %d" % [title_l, line_l, lose["time"], lose["hp"]])
	await r.frames(int(combat.rules.spar_result_seconds * 60) + 5)
	r.check(combat.spar_state == "none" and player.hp == 100 and fox.hp == fox.stats.max_hp and fox.global_position == fox.home and not fox.engaged,
		"AC4 reset: after the result both are back to full HP and 师兄 returns to his place")
	# --- full win flow (GP bot), then rematch possible
	var win := await run_spar("gp", 21)
	var title_w := combat.hud.result_title.text
	r.check(win["win"] and title_w == "你赢了！" and combat.hud.result_line.text.begins_with("师兄：") and win["fox_hp"] <= 44,
		"AC4/AC5 win flow: the GP bot wins, '你赢了！' + a line from 师兄", "%.1f s, player hp %d" % [win["time"], win["hp"]])
	await r.frames(int(combat.rules.spar_result_seconds * 60) + 5)
	await r.teleport(spot_near(fox))
	await r.tap(KEY_E)
	r.check(combat.hud.choice.visible, "AC4 rematch: E on 师兄 offers the spar again")
	await r.tap(KEY_2)
	# --- bots: idle x3, gp x8, chase x8, dodge-only x8, masher x24 (seeded); the "punish-only" variants only attack
	# after dodging / guarding a blow: chase_p vs dodger_p isolates what the (fixed) 闪身追击 is worth, gp_p what GP is.
	# (试玩反馈 v1: the v1.2 "counter" bot was dodge + 看破反击 + chase; the 看破反击 is gone, so it is now "chase", and the
	# winning bot is the GP one.)
	var stats := {}
	fox_min = Vector2.INF
	fox_max = -Vector2.INF
	for kind in ["idle", "gp", "chase", "dodger", "masher", "gp_p", "chase_p", "dodger_p"]:
		var n: int = {"idle": 3, "gp": 8, "chase": 8, "dodger": 8, "masher": 24, "gp_p": 8, "chase_p": 8, "dodger_p": 8}[kind]
		var wins := 0
		var times := []
		var win_times := []
		var fox_left := []
		for s in n:
			var res := await run_spar(kind, 1000 + s)
			if res["win"]:
				wins += 1
				win_times.append(res["time"])
			times.append(res["time"])
			fox_left.append(res["fox_hp"])
		var mean_w: float = 0.0 if win_times.is_empty() else win_times.reduce(func(a, b): return a + b, 0.0) / win_times.size()
		stats[kind] = {"runs": n, "wins": wins, "mean_win_time": mean_w, "times": times, "fox_hp_left": fox_left}
		r._log("      bot %-7s: %d/%d wins, mean winning time %.1f s, times %s, 师兄 HP left %s" % [kind, wins, n, mean_w,
			times.map(func(x): return snappedf(x, 0.1)), fox_left])
	await reset_all()
	bot_results = stats
	r.check(stats["idle"]["wins"] == 0, "AC5 bot: a player who only stands still always loses", "%d/%d" % [stats["idle"]["wins"], stats["idle"]["runs"]])
	r.check(stats["gp"]["wins"] == stats["gp"]["runs"] and stats["gp_p"]["wins"] == stats["gp_p"]["runs"],
		"AC5 bot (试玩反馈 v1): the GP bot (K so the stance meets the blow) wins every time, also when it only attacks with the GP counter and right after it",
		"%d/%d, punish-only %d/%d" % [stats["gp"]["wins"], stats["gp"]["runs"], stats["gp_p"]["wins"], stats["gp_p"]["runs"]])
	r.check(stats["chase"]["wins"] == stats["chase"]["runs"], "AC5 bot: the dodge-at-wind-up-end + chase bot wins every time",
		"%d/%d" % [stats["chase"]["wins"], stats["chase"]["runs"]])
	# v1.2: AC2 asks "只闪避机器人必胜" and "闪避反击机器人更快获胜" (v1.1 asked for >= 20% faster). In the normal
	# spar both bots mostly finish him in his first one or two attack cycles, so the gap there is small; the
	# punish-only pair isolates the counter + chase advantage (reported in %; v1.1's ">= 20%" bar is not part of
	# the v1.2 acceptance criteria, which only ask for "faster").
	r.check(stats["dodger"]["wins"] == stats["dodger"]["runs"], "AC5 bot: the dodge-only bot wins every time",
		"%d/%d, mean %.1f s" % [stats["dodger"]["wins"], stats["dodger"]["runs"], stats["dodger"]["mean_win_time"]])
	r.check(stats["gp"]["mean_win_time"] < stats["dodger"]["mean_win_time"] and stats["chase"]["mean_win_time"] < stats["dodger"]["mean_win_time"],
		"AC5 bot: the GP bot and the dodge + chase bot both win faster than the dodge-only bot",
		"gp %.2f s, chase %.2f s vs dodge-only %.2f s" % [stats["gp"]["mean_win_time"], stats["chase"]["mean_win_time"], stats["dodger"]["mean_win_time"]])
	r.check(stats["chase_p"]["wins"] == stats["chase_p"]["runs"] and stats["dodger_p"]["wins"] == stats["dodger_p"]["runs"]
		and stats["chase_p"]["mean_win_time"] < stats["dodger_p"]["mean_win_time"],
		"AC5 bot: attacking only after a dodge, the chase wins faster than waiting out the chase window",
		"chase_p %.1f s vs dodger_p %.1f s (%.0f%% less time)" % [stats["chase_p"]["mean_win_time"], stats["dodger_p"]["mean_win_time"],
			100.0 * (1.0 - stats["chase_p"]["mean_win_time"] / maxf(0.01, stats["dodger_p"]["mean_win_time"]))])
	var rate: float = float(stats["masher"]["wins"]) / stats["masher"]["runs"]
	# v1.2: the client wants 师兄 "非常简单" - the masher's win rate must now be high (AC2 target >= 50%; v1.1 was < 50%)
	r.check(rate >= 0.5 and stats["masher"]["runs"] >= 20, "AC5 bot: the attack-masher now wins often - %d/%d = %.0f%% (target >= 50%%)" % [stats["masher"]["wins"], stats["masher"]["runs"], rate * 100.0])
	r.check(combat.arena_rect.grow(1).has_point(fox_min) and combat.arena_rect.grow(1).has_point(fox_max),
		"AC4 arena: 师兄 stayed inside the 练武场 through all bot spars", "%s..%s" % [fox_min.round(), fox_max.round()])


func test_card_changes_behaviour() -> void:
	await reset_all()
	# walk speed comes from the player card
	var orig_speed := player.stats.walk_speed
	player.stats.walk_speed = 200.0
	await r.teleport(r.tile_center(31, 29))
	await r.push(Vector2.RIGHT, 0.5)
	var d1: float = player.global_position.x - r.tile_center(31, 29).x
	player.stats.walk_speed = orig_speed
	await r.teleport(r.tile_center(31, 29))
	await r.push(Vector2.RIGHT, 0.5)
	var d2: float = player.global_position.x - r.tile_center(31, 29).x
	r.check(absf(d1 / 0.5 - 200.0) < 12.0 and absf(d2 / 0.5 - orig_speed) < 12.0, "AC8 card: walking speed follows player.tres walk_speed (200 -> %.0f px/s, back to %.0f)" % [d1 / 0.5, d2 / 0.5])
	# a changed card file (boar max_hp 48 -> 100) changes the boar in game
	var edited: EnemyStats = load("res://cards/boar.tres").duplicate()
	edited.max_hp = 150   # v1.2: the real boar now has 110, so the edit uses 150
	var tmp := "user://boar_edit_test.tres"
	ResourceSaver.save(edited, tmp)
	var reloaded: EnemyStats = ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE)
	var orig: EnemyStats = boar.stats
	boar.stats = reloaded
	boar.reset_home(true)
	var hp_edit := boar.hp
	boar.stats = orig
	boar.reset_home(true)
	r.check(hp_edit == 150 and boar.hp == 110, "AC8 card: a boar card saved with max_hp 150 gives a 150-HP boar; the real card still gives 110")


func test_bandits() -> void:
	await reset_all()
	combat.bandits_enabled = true
	# respawn point
	var rp := combat.respawn_pos
	r.check(r.is_free(rp) and rp.distance_to(wolf.home) > wolf.stats.aggro_range + 300 and rp.distance_to(boar.home) > boar.stats.aggro_range + 250
		and absf(rp.distance_to(wolf.home) - 587) < 1 and absf(rp.distance_to(boar.home) - 493) < 1,
		"AC6 respawn: below the gate stairs (tile 32,43), free ground, 587 / 493 px from 狼 / 野猪 (v1.1 4.1)", "%s %.0f %.0f" % [rp, rp.distance_to(wolf.home), rp.distance_to(boar.home)])
	# not aggro far away
	await r.teleport(r.find_free_near(Vector2(900, 1430)))
	await r.frames(10)
	var calm := not wolf.engaged and not boar.engaged
	# walk into range -> both engage, name plates + bars
	await r.teleport(r.find_free_near(Vector2(512, 1440)))
	await r.frames(3)
	var engaged: bool = wolf.engaged and boar.engaged and combat.hud.plate_visible(wolf) and combat.hud.plate_visible(boar)
	r.check(calm and engaged, "AC6 bandits: not engaged from afar; entering the 192 px discovery range starts the fight with name plates + HP bars")
	r.check(wolf.hp == 60 and boar.hp == 110 and wolf.stats.damage == 14 and boar.stats.damage == 22 and wolf.stats.move_speed > boar.stats.move_speed,
		"AC3/AC6 bandits (v1.2): 狼 60 HP / 14 dmg, 野猪 110 HP / 22 dmg from their cards")
	# chase speeds (measured)
	await reset_all()
	combat.bandits_enabled = true
	await r.teleport(r.find_free_near(Vector2(512, 1650)))
	await r.frames(2)
	r.hold_dir(Vector2.ZERO)
	var w0 := wolf.global_position
	var b0 := boar.global_position
	var vw := 0.0
	var vb := 0.0
	for i in 20:
		await r.physics_frame
	vw = (wolf.global_position - w0).length() / (20.0 / 60.0)
	vb = (boar.global_position - b0).length() / (20.0 / 60.0)
	r.check(absf(vw - wolf.stats.move_speed) < 20 and absf(vb - boar.stats.move_speed) < 15, "AC6 bandits: measured chase speed 狼 %.0f px/s vs 野猪 %.0f px/s (cards 126 / 80)" % [vw, vb])
	# leash: run far away -> both walk home with full HP
	wolf.hp = 5
	await r.teleport(r.tile_center(32, 43))
	var g := 0
	while (wolf.state != "idle" or boar.state != "idle") and g < 900:
		await r.physics_frame
		g += 1
	r.check(wolf.state == "idle" and boar.state == "idle" and wolf.hp == 60 and wolf.global_position.distance_to(wolf.home) < 4,
		"AC6 leash: beyond 320 px from home the bandits give up, walk back and heal", "%.1f s" % (g / 60.0))
	# boar charge: isolate the boar (wolf parked), watch one charge
	await reset_all()
	combat.bandits_enabled = true
	wolf.stats = wolf.stats.duplicate()
	wolf.stats.aggro_range = 0.0
	await r.teleport(r.find_free_near(Vector2(700, 1440)))
	boar.add_collision_exception_with(player)   # let the charge run its full length (we only measure it)
	await r.frames(2)
	var charge_from := Vector2.ZERO
	var charge_max := 0.0
	var seen_alert := false
	g = 0
	while g < 600:
		await r.physics_frame
		g += 1
		if boar.state == "windup":
			charge_from = boar.global_position
			seen_alert = seen_alert or combat.fx.alert_visible(boar)
		elif boar.state == "strike":
			charge_max = maxf(charge_max, boar.global_position.distance_to(charge_from))
		elif boar.state == "recover" and charge_max > 0.0:
			break
		# stay a bit away so the boar has room to charge (and can't reach to stun us)
		r.hold_dir(Vector2.ZERO)
	boar.remove_collision_exception_with(player)
	r.check(charge_max >= 70.0 and seen_alert, "AC6 boar: wind-up with '!' then a straight charge (%.0f px in 0.3 s)" % charge_max)
	wolf.stats = load("res://cards/wolf.tres")
	# player death -> message -> respawn, full HP, bandits reset
	await reset_all()
	combat.bandits_enabled = true
	await r.teleport(r.find_free_near(Vector2(512, 1450)))
	var t := 0.0
	var damaged_bandit := false
	while not combat.player_dead and t < 90.0:
		bot_step("idle")
		if t > 1.0 and not damaged_bandit:
			wolf.hp = 10   # we'll check it is restored on respawn
			damaged_bandit = true
		await r.physics_frame
		t += 1.0 / 60.0
	await r.frames(20)
	var msg: String = combat.hud.fade_label.text
	var dark: float = combat.hud.fade.color.a
	await r.frames(int(combat.rules.death_seconds * 60) + 10)
	r.check(msg == "你被打倒了" and dark > 0.3 and combat.deaths == 1, "AC6 death: an idle player is knocked out by the bandits -> '你被打倒了' (%.1f s)" % t)
	idle_death_time = t
	# v1.2 AC3: bandits are stronger - an idle player now goes down clearly faster than in v1 (measured 16.4 s there)
	r.check(t < V1_IDLE_DEATH * 0.85, "AC3 bandits stronger: idle death %.1f s vs v1 %.1f s (%.0f%% faster)" % [t, V1_IDLE_DEATH, 100.0 * (1.0 - t / V1_IDLE_DEATH)])
	r.check(not combat.player_dead and player.hp == 100 and player.global_position.distance_to(combat.respawn_pos) < 1.0
		and wolf.state == "idle" and boar.state == "idle" and wolf.hp == 60 and boar.hp == 110 and wolf.global_position == wolf.home,
		"AC6 respawn: back at the respawn point with full HP; bandits back home with full HP")
	# fight them both: GP bot -> both knocked out -> "山贼被赶跑了！", gone for good
	await r.teleport(r.find_free_near(Vector2(512, 1440)))
	_dodged_for = {}
	_gp_for = {}
	t = 0.0
	var banner_seen := ""
	while not combat.bandits_cleared and t < 120.0:
		bot_step("gp")
		await r.physics_frame
		t += 1.0 / 60.0
		if combat.player_dead:
			break
	_release()
	banner_seen = combat.hud.banner.text
	r.check(combat.bandits_cleared and banner_seen == "山贼被赶跑了！" and wolf.state in ["gone", "down"] and boar.state in ["gone", "down"],
		"AC6 bandits: the GP bot knocks out both (%.1f s, %d deaths) -> '山贼被赶跑了！'" % [t, combat.deaths - 1], banner_seen)
	await r.frames(150)
	r.check(not wolf.visible and not boar.visible and wolf.state == "gone", "AC6 bandits: knocked-out bandits fade out and stay gone")
	await r.teleport(r.find_free_near(Vector2(512, 1440)))
	await r.frames(30)
	r.check(not wolf.engaged and not boar.engaged and not combat.blocks_interaction(), "AC6 bandits: nothing re-engages after they were driven off")
