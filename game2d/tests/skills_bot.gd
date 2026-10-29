extends "res://tests/combat_suite.gd"
## 武学 (A): the skill bots for tests/skills_suite.gd - tests/combat_suite.gd's bots plus the U key (燕回旋).
##   "masher_u"   the attack-masher (walks in, J as fast as it can, never guards) that also presses U whenever an enemy
##                stands inside the spin's reach and the move is ready - "会用燕回旋的机器人" against the plain masher
##   "gp_u"       the GP bot (K as the blow comes, J otherwise) plus the same U - reported for reference
##   "gp_only"    K at each blow and nothing else (the 燕回旋 trial: 3 GP in one 师兄 spar)
##   "spin_spam"  presses only U, as fast as it can, walking at the nearest enemy and never looking at its attacks
##                (no J, no K, no dodge) - "只狂按招式、不看敌人"
## Every other kind is combat_suite's own bot.

var _u_down := false
var u_presses := 0


func _release_u() -> void:
	if _u_down:
		r.key(KEY_U, false)
		_u_down = false


func _release() -> void:
	_release_u()
	super._release()


func press_u() -> void:
	r.key(KEY_U, true)
	_u_down = true
	u_presses += 1


func _nearest() -> Node2D:
	var best: Node2D = null
	for e in combat.engaged_enemies():
		if best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = e
	return best


func _spin_ready() -> bool:
	var sk = main.get("skills")
	return sk != null and sk.has_learned("swallow_spin") and sk.cooldown_left("swallow_spin") <= 0.0 and player.can_cast() \
		and player.attack_stage == 0 and not player.is_chasing()


func bot_step(kind: String) -> void:
	_release_u()
	if kind == "spin_spam":
		if _j_down:
			r.key(KEY_J, false)
			_j_down = false
		if player.dead:
			r.hold_dir(Vector2.ZERO)
			return
		var t := _nearest()
		if t == null:
			r.hold_dir(Vector2.ZERO)
			return
		var to: Vector2 = t.global_position - player.global_position
		r.hold_dir(to.normalized() if to.length() > 30.0 else Vector2.ZERO)
		if _spin_ready():
			press_u()
		return
	if kind == "gp_only":
		# a careful player for the 燕回旋 trial: K at each blow, never J (the counters alone: 3 x 30 < 师兄's 96 to go)
		_punish_until = -1.0
		super.bot_step("gp_p")
		return
	if kind == "masher_u" or kind == "gp_u":
		var t2 := _nearest()
		if t2 != null and _spin_ready() and not player.gp_countering and not player.in_gp_stance():
			var sk = main.get("skills")
			var reach: float = float(sk.card("swallow_spin").radius) + float(t2.stats.body_radius) - 4.0
			if t2.global_position.distance_to(player.global_position) <= reach:
				if _j_down:
					r.key(KEY_J, false)
					_j_down = false
				r.hold_dir(Vector2.ZERO)
				press_u()
				return
		super.bot_step("masher" if kind == "masher_u" else "gp")
		return
	super.bot_step(kind)
