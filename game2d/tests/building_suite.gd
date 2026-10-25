extends RefCounted
## 房子整栋实心 v1 checks (tests/run_tests.gd runs this suite after the polish suite; quick loop: -- --only-building).
## Real key events and real physics.
##   AC1 every outdoor building (宿舍 x2, 正殿, 厨房, 藏经阁废墟, 村口茅屋 x2): pushing the rabbit into it from the north,
##       east and west (straight and diagonal) with the movement keys never puts one pixel of her sprite on the roof / wall
##       picture; a sweep of every free spot around each building (all frames of the rabbit, union of their pixels) finds
##       no overlap wherever the building is drawn over her; an NPC / bandit sized body cannot get its feet into the
##       footprint, a bandit body pushed at it stops outside
##   AC2 the client's spot (north of the old disciples' house, x 176..344, feet y ~1071): she stops outside the ridge
##   AC3 no building ever fades (the occlusion system has no entry for them); tree canopy, bamboo and the 山门 passage still do
##   AC4 all five doors still work (walk in / out with the keys); every outdoor interactable, puzzle stone, NPC, the bandit
##       trigger, the respawn point, the grove and the stash can still be reached from the spawn

var r
var g: Node
var it: Interiors
var story: Story
var nav
var buildings: Array = []    # {name, sprite, rect, base, image, mask?}
var union_mask := PackedVector2Array()    # pixel offsets (from the rounded feet) of the rabbit, union of all her frames

const SOLID := ["building", "library_ruin"]


func _init(runner) -> void:
	r = runner


func run() -> void:
	r.paused = false
	r.release_all()
	await new_game()
	await test_doors()
	story.enter_sandbox()
	r.main.combat.bandits_enabled = false
	await r.frames(2)
	collect_buildings()
	await test_pushes()
	await test_sweep()
	await test_slides()
	await test_npc_bodies()
	await test_client_spot()
	await test_fade_rules()
	await test_reachability()
	await _free_game()


# ------------------------------------------------------------------ helpers
func _free_game() -> void:
	if g != null and is_instance_valid(g):
		if g.is_inside_tree():
			g.get_parent().remove_child(g)
		g.queue_free()
	g = null
	await r.process_frame


func new_game() -> void:
	await _free_game()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	g = m
	it = m.interiors
	story = m.story
	r.main = m
	r.player = m.player
	r.data = m.data
	r.grid_w = 0
	nav = load("res://tests/nav.gd").new(r, m)
	m.daynight.running = false
	await r.frames(3)


func p() -> Player:
	return g.player


func finish_scene() -> void:
	var n := 0
	while story.busy and n < 400:
		if story.dialogue.choosing:
			await r.tap(KEY_1)
		elif story.dialogue.active:
			await r.tap(KEY_E)
		else:
			await r.frames(2)
		n += 1
	await r.frames(2)


func collect_buildings() -> void:
	buildings.clear()
	for s in g.world.get_children():
		if not (s is Sprite2D) or not (String(s.get_meta("type", "")) in SOLID):
			continue
		var img: Image = s.texture.get_image()
		if img.is_compressed():
			img.decompress()
		var rect := Rect2(s.position + s.offset, Vector2(s.texture.get_width(), s.texture.get_height()))
		var nm := "%s@%d,%d" % [s.get_meta("type"), int(rect.position.x), int(rect.position.y)]
		buildings.append({"name": nm, "sprite": s, "rect": rect, "base": s.position.y, "image": img})
	# union of the rabbit's opaque pixels over every frame of every animation (offsets from the rounded feet)
	var seen := {}
	var sf: SpriteFrames = p().sprite.sprite_frames
	for an in sf.get_animation_names():
		# walking / standing frames only: the combat frames (attack, hurt, down: weapon swing, +-13..15 px) reach further
		if not (an.begins_with("idle_") or an.begins_with("walk_")):
			continue
		for fi in sf.get_frame_count(an):
			var img: Image = sf.get_frame_texture(an, fi).get_image()
			if img.is_compressed():
				img.decompress()
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.5:
						seen[Vector2i(x, y)] = true
	union_mask.clear()
	for k in seen:
		union_mask.append(Vector2(k.x, k.y) + p().sprite.offset)


## Pixels of the rabbit's CURRENT frame on the building picture's opaque pixels (feet = her position; drawn rounded).
func overlap_now(feet: Vector2, b: Dictionary) -> int:
	var spr: AnimatedSprite2D = p().sprite
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var o := feet.round() + spr.offset
	var rect: Rect2 = b["rect"]
	var bi: Image = b["image"]
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				var q := (o + Vector2(x, y) - rect.position)
				var qx := int(q.x)
				var qy := int(q.y)
				if qx >= 0 and qy >= 0 and qx < bi.get_width() and qy < bi.get_height() and bi.get_pixel(qx, qy).a > 0.5:
					n += 1
	return n


func overlap_union(feet: Vector2, b: Dictionary) -> int:
	var rect: Rect2 = b["rect"]
	var bi: Image = b["image"]
	var o := feet.round() - rect.position
	var n := 0
	for m in union_mask:
		var qx := int(o.x + m.x)
		var qy := int(o.y + m.y)
		if qx >= 0 and qy >= 0 and qx < bi.get_width() and qy < bi.get_height() and bi.get_pixel(qx, qy).a > 0.5:
			n += 1
	return n


func opaque_at(b: Dictionary, world: Vector2) -> bool:
	var q: Vector2 = world - (b["rect"] as Rect2).position
	var bi: Image = b["image"]
	var qx := int(floor(q.x))
	var qy := int(floor(q.y))
	return qx >= 0 and qy >= 0 and qx < bi.get_width() and qy < bi.get_height() and bi.get_pixel(qx, qy).a > 0.5


## Start spots of the pushes: {pos, dir, side}
func push_plan(b: Dictionary) -> Array:
	var rect: Rect2 = b["rect"]
	var plan := []
	var x := rect.position.x - 4.0
	while x <= rect.end.x + 4.0:
		plan.append({"pos": Vector2(x, rect.position.y - 28.0), "dir": Vector2.DOWN, "side": "N"})
		if int(x - rect.position.x) % 32 == 0:
			plan.append({"pos": Vector2(x, rect.position.y - 28.0), "dir": Vector2(0.7, 1.0).normalized(), "side": "N"})
			plan.append({"pos": Vector2(x, rect.position.y - 28.0), "dir": Vector2(-0.7, 1.0).normalized(), "side": "N"})
		x += 8.0
	var y := rect.position.y + 4.0
	while y < rect.end.y - 2.0:
		plan.append({"pos": Vector2(rect.end.x + 28.0, y), "dir": Vector2.LEFT, "side": "E"})
		plan.append({"pos": Vector2(rect.position.x - 28.0, y), "dir": Vector2.RIGHT, "side": "W"})
		if int(y - rect.position.y) % 24 == 0:
			plan.append({"pos": Vector2(rect.end.x + 28.0, y), "dir": Vector2(-1.0, -0.5).normalized(), "side": "E"})
			plan.append({"pos": Vector2(rect.position.x - 28.0, y), "dir": Vector2(1.0, -0.5).normalized(), "side": "W"})
		y += 8.0
	return plan


# ================================================================== AC1
func test_pushes() -> void:
	r._log("      buildings found: %d" % buildings.size())
	r.check(buildings.size() == 7, "building AC1: 7 outdoor buildings (宿舍 x2, 正殿, 厨房, 藏经阁废墟, 村口茅屋 x2)", str(buildings.map(func(b): return b["name"])))
	var speed: float = p().stats.walk_speed
	var total_bad := []
	for b in buildings:
		var tested := {"N": 0, "E": 0, "W": 0}
		var stopped := 0
		var worst := 0
		var tried := 0
		for st in push_plan(b):
			tried += 1
			var start: Vector2 = st["pos"]
			if not r.is_free(start) or r.main.interiors.room_at(start) != "":
				continue
			await r.teleport(start)
			r.hold_dir(st["dir"])
			var secs := 1.3
			var bad_here := 0
			for i in int(secs * 60.0):
				await r.physics_frame
				var f := p().global_position
				if f.y < float(b["base"]):
					bad_here = maxi(bad_here, overlap_now(f, b))
			r.release_all()
			await r.frames(1)
			var moved := p().global_position.distance_to(start)
			if moved < secs * speed * 0.85:
				stopped += 1
				tested[st["side"]] += 1
			worst = maxi(worst, bad_here)
			if bad_here > 0 and total_bad.size() < 10:
				total_bad.append("%s %s from %s dir %s ended %s overlap %d px" % [b["name"], st["side"], start, st["dir"], p().global_position.round(), bad_here])
		r._log("      %s: %d pushes planned, stopped by the building N %d E %d W %d, worst overlap %d px" % [b["name"], tried, tested["N"], tested["E"], tested["W"], worst])
		var sides_ok: bool = tested["N"] >= 3 and (tested["E"] >= 2 or tested["W"] >= 2)
		if b["name"].begins_with("library_ruin"):
			sides_ok = tested["E"] >= 5 and tested["W"] >= 5       # the ruin: its north side is the back wall of the compound
		if not sides_ok:
			total_bad.append("%s: pushes that reached it N %d E %d W %d (too few)" % [b["name"], tested["N"], tested["E"], tested["W"]])
	r.check(total_bad.is_empty(),
		"building AC1: pushing the rabbit into every building from the north, east and west (straight and diagonal, real keys) - zero pixels of her sprite on the roof / wall picture", str(total_bad))


func test_sweep() -> void:
	# every free spot around each building, drawn behind it: not one pixel of any rabbit frame on the building
	var bad := []
	var spots := 0
	for b in buildings:
		var rect: Rect2 = b["rect"]
		var worst := 0
		var n := 0
		var y := rect.position.y - 10.0
		while y < float(b["base"]):
			var x := rect.position.x - 14.0
			while x <= rect.end.x + 14.0:
				var f := Vector2(x, y)
				if r.is_free(f):
					n += 1
					var o := overlap_union(f, b)
					if o > worst:
						worst = o
					if o > 0 and bad.size() < 10:
						bad.append("%s %s %d px" % [b["name"], f, o])
				x += 2.0
			y += 2.0
		spots += n
		r._log("      sweep %s: %d free spots, worst overlap %d px" % [b["name"], n, worst])
	r.check(bad.is_empty() and spots > 5000,
		"building AC1: sweep of %d free spots (2 px grid) around the buildings - wherever the building is drawn over her no pixel of any of her frames is on it" % spots, str(bad))


func test_npc_bodies() -> void:
	# An NPC / bandit body (14 x 7 foot box, Npc.setup) can never have its feet inside the footprint (static check over
	# every opaque pixel row of every building), and a bandit-sized body pushed at the building from N / E / W stops outside.
	var bad := []
	var tested := 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 7)
	for b in buildings:
		var rect: Rect2 = b["rect"]
		var y := rect.position.y + 1.0
		while y < float(b["base"]) - 1.0:
			var x := rect.position.x + 1.0
			while x < rect.end.x - 1.0:
				var f := Vector2(x, y)
				if opaque_at(b, f):
					tested += 1
					var q := PhysicsShapeQueryParameters2D.new()
					q.shape = shape
					q.transform = Transform2D(0.0, f + Vector2(0, -2.5))
					q.collision_mask = 1
					if g.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty():
						if bad.size() < 10:
							bad.append("%s %s" % [b["name"], f])
				x += 4.0
			y += 4.0
	r.check(bad.is_empty() and tested > 3000,
		"building AC1: an NPC / bandit body cannot put its feet on any of %d sampled building pixels (collision covers the whole footprint)" % tested, str(bad))
	# live: a bandit-sized body walks at every building
	var probe := CharacterBody2D.new()
	probe.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	probe.collision_layer = 0
	probe.collision_mask = 1
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -2.5)
	probe.add_child(cs)
	g.add_child(probe)
	var inside := []
	var pushes := 0
	for b in buildings:
		for st in push_plan(b):
			var start: Vector2 = st["pos"]
			if int(start.x + start.y) % 16 != 0 and int(start.x + start.y) % 16 != 8:
				continue
			probe.global_position = start
			if not r.is_free(start):
				continue
			var blocked := false
			for i in 80:
				probe.velocity = (st["dir"] as Vector2) * 120.0
				probe.move_and_slide()
				await r.physics_frame
				if probe.global_position.y < float(b["base"]) and opaque_at(b, probe.global_position):
					blocked = true
					break
			pushes += 1
			if blocked and inside.size() < 10:
				inside.append("%s %s from %s" % [b["name"], probe.global_position.round(), start])
	probe.queue_free()
	r.check(inside.is_empty() and pushes > 100,
		"building AC1: a bandit-sized body pushed at every building from N / E / W (%d pushes) never gets its feet onto the building" % pushes, str(inside))
	# the real wolf: put him beside the old disciples' house and let him try to walk into it
	var wolf: Npc = null
	for n in g.npcs:
		if n.id == "wolf":
			wolf = n
	r.check(wolf != null and wolf is Fighter, "building AC1: the bandit (wolf) exists as a Fighter")


## 房子整栋实心 v1 fix: holding a diagonal into a wall / eave, she keeps sliding along it (no snag on the small steps of
## the eave silhouette). Sides: N (down+right / down+left along the roof), E and W (up / down along the walls).
func test_slides() -> void:
	var speed: float = p().stats.walk_speed
	var bad := []
	var total := 0
	var snags_log := []
	for b in buildings:
		var rect: Rect2 = b["rect"]
		var base: float = b["base"]
		var runs := [
			["N down-right", Vector2(rect.position.x - 6.0, rect.position.y - 24.0), Vector2(1, 1).normalized(), func(f): return f.x > rect.end.x + 12.0 or f.y > base + 6.0],
			["N down-left", Vector2(rect.end.x + 6.0, rect.position.y - 24.0), Vector2(-1, 1).normalized(), func(f): return f.x < rect.position.x - 12.0 or f.y > base + 6.0],
			["E left-down", Vector2(rect.end.x + 20.0, rect.position.y + 6.0), Vector2(-1, 1).normalized(), func(f): return f.y > base + 6.0],
			["E left-up", Vector2(rect.end.x + 20.0, base - 6.0), Vector2(-1, -1).normalized(), func(f): return f.y < rect.position.y - 4.0],
			["W right-down", Vector2(rect.position.x - 20.0, rect.position.y + 6.0), Vector2(1, 1).normalized(), func(f): return f.y > base + 6.0],
			["W right-up", Vector2(rect.position.x - 20.0, base - 6.0), Vector2(1, -1).normalized(), func(f): return f.y < rect.position.y - 4.0],
		]
		for run in runs:
			var start: Vector2 = run[1]
			if not r.is_free(start):
				continue
			await r.teleport(start)
			r.hold_dir(run[2])
			var hist := [p().global_position]
			var worst_stall := 0
			var stall := 0
			var done := false
			var where := Vector2.ZERO
			for i in 300:
				await r.physics_frame
				var f := p().global_position
				hist.append(f)
				if run[3].call(f):
					done = true
					break
				# stalled = she moved less than 4 px in the last half second while the keys are held
				if hist.size() > 30 and f.distance_to(hist[hist.size() - 31]) < 4.0:
					stall += 1
					if stall > worst_stall:
						worst_stall = stall
						where = f
				else:
					stall = 0
			r.release_all()
			await r.frames(1)
			total += 1
			if worst_stall >= 1:
				var why := _snag_reason(where, run[2])
				if why != "":
					snags_log.append("%s %s: stalled %d frames at %s - %s" % [b["name"], run[0], worst_stall, where.round(), why])
	for l in snags_log:
		r._log("      slide: " + l)
	r.check(snags_log.is_empty() and total >= 30, "building fix: holding a diagonal into the walls / eaves of every building (%d slides along N, E, W) she keeps sliding - no snag on the eave steps" % total, str(snags_log))


## A stall is a legitimate concave corner (a wing / wall she walked into) or a SNAG on a small step. It is a snag when
## nudging her sideways by <= 6 px (away from the wall) frees the way on in the held direction, and only buildings
## (no lantern, fence, tree...) are around her. Returns "" for a legitimate stop.
func _snag_reason(f: Vector2, d: Vector2) -> String:
	var q := PhysicsShapeQueryParameters2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Player.FOOT_SIZE + Vector2(8, 8)
	q.shape = rs
	q.transform = Transform2D(0.0, f + Vector2(0, -2))
	q.collision_mask = 1
	q.exclude = [p().get_rid()]
	# which collision shapes: use the kinds of the shapes the rect touches
	var touching := []
	for cs in g.solids.get_children():
		var sh := cs as CollisionShape2D
		var rect := Rect2(sh.position - (sh.shape as RectangleShape2D).size * 0.5, (sh.shape as RectangleShape2D).size)
		if rect.intersects(Rect2(f + Vector2(-10, -9), Vector2(20, 18))):
			touching.append(String(sh.get_meta("kind", "")))
	for k in touching:
		if not (k in SOLID):
			return ""
	var sx := 1.0 if d.x > 0.0 else -1.0
	var sy := 1.0 if d.y > 0.0 else -1.0
	for k in [2.0, 4.0, 6.0]:
		for c in [Vector2(-sx * k, 0), Vector2(0, -sy * k)]:
			# after the nudge she goes on along the other axis of the held direction (down / along the wall)
			var along := Vector2(0, sy * 12.0) if c.x != 0.0 else Vector2(sx * 12.0, 0)
			if r.is_free(f + c) and r.is_free(f + c + along):
				return "a %d px sideways step %s would free the way (small ledge)" % [int(k), c]
	return ""


# ================================================================== AC2
func test_client_spot() -> void:
	var dorm: Dictionary = {}
	for b in buildings:
		if int((b["rect"] as Rect2).position.x) == 160 and int((b["rect"] as Rect2).position.y) == 1056:
			dorm = b
	var rows := []
	var ok := true
	for x in [176.0, 200.0, 260.0, 320.0, 344.0]:
		await r.teleport(Vector2(x, 1040))
		r.hold_dir(Vector2.DOWN)
		var worst := 0
		for i in 80:
			await r.physics_frame
			worst = maxi(worst, overlap_now(p().global_position, dorm))
		r.release_all()
		await r.frames(2)
		var f := p().global_position
		rows.append("x%d -> feet %s overlap %d" % [int(x), f.round(), worst])
		if worst != 0 or f.y > 1064.0:
			ok = false
	for line in rows:
		r._log("      client spot: " + line)
	r.check(ok, "building AC2: north of the old disciples' house (x 176..344) she is stopped at the ridge (feet y <= 1064), no pixel overlap", str(rows))
	# the old standing spot (feet y 1071) is inside the roof now - she cannot be put there by walking
	r.check(not r.is_free(Vector2(260, 1071)), "building AC2: the client's old spot (260, 1071) is now solid ground (roof)")


# ================================================================== AC3
func _spot_for(occ: Occlusion, idx: int, min_cov: float, x_min := -INF, x_max := INF) -> Vector2:
	var rect: Rect2 = occ.entries[idx]["rect"]
	var s: Sprite2D = occ.sprite_of(idx)
	var best := Vector2.INF
	var best_c := min_cov
	var y := rect.position.y + 2.0
	while y < s.position.y - 1.0:
		var x := maxf(rect.position.x + 6.0, x_min)
		while x < minf(rect.end.x - 6.0, x_max):
			var f := Vector2(x, y)
			if r.is_free(f) and it.room_at(f) == "":
				var cv := occ.coverage(idx, f)
				if cv > best_c:
					best_c = cv
					best = f
			x += 4.0
		y += 2.0
	return best


func test_fade_rules() -> void:
	var occ: Occlusion = g.occlusion
	var bad := []
	for e in occ.entries:
		if String(e["type"]) in SOLID:
			bad.append(e["type"])
	r.check(bad.is_empty() and occ.entries.size() > 100,
		"building AC3: the fade system has no entry for any building (%d pictures watched: trees, bamboo, gate...)" % occ.entries.size(), str(bad))
	# nothing in the whole map that fades is a building: walk the reachable ground with the fade running
	var minimum := float(Tuning.data()["occlusion"]["min_alpha"])
	var types := {"tree": -1, "bamboo": -1, "gate": -1, "village_arch": -1}
	for i in occ.entries.size():
		var t := String(occ.entries[i]["type"])
		if types.has(t) and types[t] == -1:
			var spot := _spot_for(occ, i, 0.2 if t == "gate" else 0.3)
			if spot != Vector2.INF:
				types[t] = i
	var report := []
	var fails := []
	for t in types:
		var idx: int = types[t]
		if idx < 0:
			if t == "village_arch":
				report.append("village_arch: nothing drawn over a free spot (posts only)")
				continue
			fails.append(t + ": no covering spot found")
			continue
		var s: Sprite2D = occ.sprite_of(idx)
		var spot := _spot_for(occ, idx, 0.3 if t != "gate" else 0.2)
		await r.teleport(spot)
		await r.frames(40)
		var feet := p().global_position
		var mid := Occlusion.body_rect(feet).get_center()
		var strength := occ.strength_of(s)
		var alpha := occ.alpha_at(s, mid)
		var shader_on: bool = s.material is ShaderMaterial
		await r.teleport(r.find_free_near(Vector2(feet.x, s.position.y + 24.0), 40))
		await r.frames(40)
		# (another character may still be behind the same picture - e.g. 老伯 at the gate: only her own hole must be gone)
		var off_ok: bool = not idx in occ.covering(p().global_position) and occ.alpha_at(s, Occlusion.body_rect(p().global_position).get_center()) > 0.99
		report.append("%s idx %d: feet %s fade %.2f alpha %.2f shader %s, in front -> off %s" % [t, idx, feet.round(), strength, alpha, shader_on, off_ok])
		if not (strength > 0.99 and alpha <= minimum + 0.02 and shader_on and off_ok):
			fails.append(report[-1])
	for line in report:
		r._log("      " + line)
	r.check(fails.is_empty(), "building AC3: tree canopy, bamboo and the 山门 gate tower still fade around her (and clear when she steps out)", str(fails))
	# the 山门 passage: she walks through it with the keys, the gate still fades there and does not block her
	await r.teleport(Vector2(1040, 1340))
	r.hold_dir(Vector2.UP)
	var faded := false
	var gate_idx := -1
	for i in occ.entries.size():
		if String(occ.entries[i]["type"]) == "gate":
			gate_idx = i
	var enter_y := p().global_position.y
	for i in 150:
		await r.physics_frame
		if gate_idx >= 0 and occ.strength_of(occ.sprite_of(gate_idx)) > 0.9:
			faded = true
	r.release_all()
	r.check(faded and p().global_position.y < 1150.0, "building AC3: walking up through the 山门 passage the gate tower fades around her and she gets through (y %.0f -> %.0f)" % [enter_y, p().global_position.y])
	await r.teleport(Vector2(1424, 1790))
	r.hold_dir(Vector2.DOWN)
	await r.frames(150)
	r.release_all()
	r.check(p().global_position.y > 1805.0, "building AC3: the 村口牌坊 passage stays passable (y %.0f)" % p().global_position.y)


# ================================================================== AC4
func test_doors() -> void:
	await finish_scene()
	story.set_stage(2)
	var rooms := ["dorm_main", "storage", "dorm_old", "hall", "kitchen"]
	var bad := []
	for id in rooms:
		await r.teleport(it.exit_spot(id))
		await r.frames(2)
		# walk to the door from further away along the ground, then in
		var res: String = await nav.go_in(id)
		var in_room: bool = it.room_at(p().global_position) == id
		var out: String = ""
		if in_room:
			out = await nav.go_out(id)
		var outside := it.room_at(p().global_position) == ""
		r._log("      door %s: in %s (%s), out %s (%s)" % [id, in_room, res, outside, out])
		if not (in_room and outside):
			bad.append("%s in %s out %s" % [id, in_room, outside])
		# the doorstep itself is free ground inside the trigger strip
		var tr: Rect2 = it.outdoor_trigger(id)
		var free_n := 0
		var y := tr.position.y
		while y <= tr.end.y:
			var x := tr.position.x
			while x <= tr.end.x:
				if r.is_free(Vector2(x, y)):
					free_n += 1
				x += 2.0
			y += 2.0
		if free_n < 10:
			bad.append("%s: only %d free doorstep spots" % [id, free_n])
	r.check(bad.is_empty(), "building AC4: all five doors can still be walked into and out of from the ground in front (real keys, the game's own trigger)", str(bad))
	# 房子整栋实心 v1 fix: wider door windows - diagonal and off-centre approaches enter for every door
	var offs := {"dorm_main": 20.0, "storage": 20.0, "dorm_old": 20.0, "kitchen": 20.0, "hall": 40.0}
	var wbad := []
	var walks := 0
	for id in rooms:
		var d: Dictionary = it.rooms[id]["door"]
		var cases := []
		for dx in [-offs[id], offs[id]]:
			cases.append(["offset %+d up" % int(dx), Vector2(float(d["x"]) + dx, float(d["bottom"]) + 22.0), Vector2.UP])
		for sx in [-1.0, 1.0]:
			cases.append(["diagonal from %s" % ("left" if sx < 0 else "right"), Vector2(float(d["x"]) + sx * 26.0, float(d["bottom"]) + 36.0), Vector2(-sx, -1.0).normalized()])
			cases.append(["off-centre %+d diagonal" % int(sx * offs[id]), Vector2(float(d["x"]) + sx * offs[id], float(d["bottom"]) + 30.0), Vector2(-sx * 0.3, -1.0).normalized()])
		for c in cases:
			var st: Vector2 = c[1]
			if not r.is_free(st):
				st = r.find_free_near(st, 10)
			if st == Vector2.INF:
				wbad.append("%s %s: no free start" % [id, c[0]])
				continue
			await r.teleport(st)
			r.hold_dir(c[2])
			var entered := false
			for i in 200:
				await r.physics_frame
				if it.transitioning:
					entered = true
					break
			r.release_all()
			await nav.settle()
			walks += 1
			if not (entered and it.room_at(p().global_position) == id):
				wbad.append("%s %s from %s" % [id, c[0], st])
			elif it.room_at(p().global_position) == id:
				await nav.go_out(id)
	r.check(wbad.is_empty() and walks >= 30, "building fix: every door (small ones +-20 px, the hall +-40 px off centre) enters from straight, off-centre and diagonal approaches (%d walks)" % walks, str(wbad))
	# walking along each building front (inside the trigger strip, sideways) does not enter
	var nobounce := true
	for id in rooms:
		var d: Dictionary = it.rooms[id]["door"]
		var t0: int = it.transitions
		var y := float(d["bottom"]) + 10.0
		await r.teleport(r.find_free_near(Vector2(float(d["x"]) - 40.0, y), 8))
		r.hold_dir(Vector2.RIGHT)
		await r.frames(70)
		r.hold_dir(Vector2.LEFT)
		await r.frames(70)
		r.release_all()
		if it.transitions != t0 or it.room_at(p().global_position) != "":
			nobounce = false
	r.check(nobounce, "building fix: walking sideways along the front of every building (through the widened door strip) does not enter")
	# the library ruin has no door: pushing into it from the front does not enter anything
	await r.teleport(Vector2(243, 660))
	r.hold_dir(Vector2.UP)
	await r.frames(90)
	r.release_all()
	r.check(it.room_at(p().global_position) == "" and p().global_position.y > 640.0, "building AC4: the sealed library ruin stays solid from the front (no door)", str(p().global_position.round()))


# ---------------------------------------------------------------- true foot box, 2 px grid (from the collision rectangles)
const G2 := 2
var g2_w := 0
var g2_h := 0
var g2_blocked := PackedByteArray()


## Her foot box (12 x 6, x +-6, y -5 .. +1 around the feet) against every collision rectangle, one cell per 2 px.
func build_grid2() -> void:
	g2_w = int(g.data["pixel_width"]) / G2
	g2_h = int(g.data["pixel_height"]) / G2
	g2_blocked.resize(g2_w * g2_h)
	g2_blocked.fill(0)
	for c in g.data["colliders"]:
		var rc: Array = c["rect"]
		var fx0: float = float(rc[0]) - 6.0
		var fx1: float = float(rc[0] + rc[2]) + 6.0
		var fy0: float = float(rc[1]) - 1.0
		var fy1: float = float(rc[1] + rc[3]) + 5.0
		for gy in range(maxi(0, int(floor(fy0 / G2))), mini(g2_h, int(ceil(fy1 / G2)) + 1)):
			var fy := gy * G2 + 1.0
			if fy <= fy0 or fy >= fy1:
				continue
			for gx in range(maxi(0, int(floor(fx0 / G2))), mini(g2_w, int(ceil(fx1 / G2)) + 1)):
				var fx := gx * G2 + 1.0
				if fx > fx0 and fx < fx1:
					g2_blocked[gy * g2_w + gx] = 1


func g2_idx(pos: Vector2) -> int:
	return clampi(int(pos.y / G2), 0, g2_h - 1) * g2_w + clampi(int(pos.x / G2), 0, g2_w - 1)


func g2_flood(start: Vector2) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(g2_w * g2_h)
	var s := g2_idx(start)
	if g2_blocked[s] == 1:
		return seen
	seen[s] = 1
	var q := PackedInt32Array([s])
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var gx := i % g2_w
		var gy := i / g2_w
		if gx > 0 and seen[i - 1] == 0 and g2_blocked[i - 1] == 0:
			seen[i - 1] = 1
			q.append(i - 1)
		if gx < g2_w - 1 and seen[i + 1] == 0 and g2_blocked[i + 1] == 0:
			seen[i + 1] = 1
			q.append(i + 1)
		if gy > 0 and seen[i - g2_w] == 0 and g2_blocked[i - g2_w] == 0:
			seen[i - g2_w] = 1
			q.append(i - g2_w)
		if gy < g2_h - 1 and seen[i + g2_w] == 0 and g2_blocked[i + g2_w] == 0:
			seen[i + g2_w] = 1
			q.append(i + g2_w)
	return seen


## A* over the 2 px foot-box grid inside `area` (world rect), as a path of waypoints (every ~8 px, corners kept).
func g2_path(from: Vector2, to: Vector2, area: Rect2, margin := 0) -> Array:
	var ox := int(area.position.x / G2)
	var oy := int(area.position.y / G2)
	var w := int(area.size.x / G2)
	var h := int(area.size.y / G2)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(G2, G2)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for gy in h:
		for gx in w:
			var hit := false
			for dy in range(-margin, margin + 1):
				for dx in range(-margin, margin + 1):
					var yy := oy + gy + dy
					var xx := ox + gx + dx
					if yy >= 0 and xx >= 0 and yy < g2_h and xx < g2_w and g2_blocked[yy * g2_w + xx] == 1:
						hit = true
			if hit:
				astar.set_point_solid(Vector2i(gx, gy))
	var a := Vector2i(int(from.x / G2) - ox, int(from.y / G2) - oy)
	var b := Vector2i(int(to.x / G2) - ox, int(to.y / G2) - oy)
	if astar.is_point_solid(a) or astar.is_point_solid(b):
		return []
	var ids := astar.get_id_path(a, b)
	var pts := []
	for k in ids.size():
		var v: Vector2i = ids[k]
		var pos := Vector2((ox + v.x) * G2 + 1.0, (oy + v.y) * G2 + 1.0)
		if k == 0 or k == ids.size() - 1 or k % 2 == 0:
			pts.append(pos)
	return pts


func _reach_ok(name: String, center: Vector2, radius: float, seen: PackedByteArray, fails: Array, log_lines: Array) -> void:
	var best := INF
	for gy in range(maxi(0, int((center.y - radius) / G2)), mini(g2_h, int((center.y + radius) / G2) + 1)):
		for gx in range(maxi(0, int((center.x - radius) / G2)), mini(g2_w, int((center.x + radius) / G2) + 1)):
			var i := gy * g2_w + gx
			if seen[i] == 1:
				var d := Vector2(gx * G2 + 1.0, gy * G2 + 1.0).distance_to(center)
				best = minf(best, d)
	log_lines.append("%s: nearest reachable spot %.0f px (radius %.0f)" % [name, best, radius])
	if best > radius:
		fails.append("%s at %s: nearest reachable spot %.0f px > %.0f" % [name, center, best, radius])


func test_reachability() -> void:
	build_grid2()
	var spawn := Vector2(g.data["spawn"]["x"], g.data["spawn"]["y"])
	var seen := g2_flood(spawn)
	var sd: Dictionary = story.data
	var fails := []
	var lines := []
	for x in sd["interactables"]:
		if x.has("room"):
			continue
		_reach_ok("thing " + String(x["id"]), story._thing_pos(x), float(x.get("radius", 32)) - 2.0, seen, fails, lines)
	for id in story.stones:
		_reach_ok("stone " + String(id), story.stones[id]["pos"], float(sd["puzzle"].get("radius", 30)) - 2.0, seen, fails, lines)
	# (the stash sits in the pocket behind the bamboo clump: closed until the puzzle is solved - the story suite walks there)
	for n in g.npcs:
		_reach_ok("npc " + n.id, n.global_position, 40.0, seen, fails, lines)
	var gr: Array = sd["grove"]["rect"]
	_reach_ok("grove (north of the wall)", Vector2(560, 300), 30.0, seen, fails, lines)
	_reach_ok("grove rect", Rect2(gr[0], gr[1], gr[2], gr[3]).get_center(), maxf(gr[2], gr[3]) * 0.5, seen, fails, lines)
	var br: Array = sd["bandits"]["trigger_rect"]
	_reach_ok("bandit trigger rect", Rect2(br[0], br[1], br[2], br[3]).get_center(), maxf(br[2], br[3]) * 0.5, seen, fails, lines)
	for n in g.npcs:
		if n.id == "wolf" or n.id == "boar":
			_reach_ok("bandit trigger radius (%s)" % n.id, n.global_position, float(sd["bandits"]["trigger_radius"]) - 100.0, seen, fails, lines)
	_reach_ok("respawn point", g.combat.respawn_pos, 14.0, seen, fails, lines)
	_reach_ok("spawn", spawn, 4.0, seen, fails, lines)
	for id in it.rooms:
		_reach_ok("door " + String(id), it.exit_spot(id), 10.0, seen, fails, lines)
	# the three places of the playtest report
	_reach_ok("breach V1 (north wall, west V)", Vector2(272, 368), 4.0, seen, fails, lines)
	_reach_ok("breach V2 (north wall, east V)", Vector2(304, 368), 4.0, seen, fails, lines)
	_reach_ok("north meadow beyond the breach", Vector2(290, 328), 4.0, seen, fails, lines)
	for line in lines:
		r._log("      reach " + line)
	r.check(fails.is_empty() and lines.size() >= 25,
		"building AC4: %d outdoor places (true 12x6 foot box, 2 px grid, flood from the spawn) - interactables, puzzle stones, NPCs, grove, bandit trigger, respawn, the five doors, both wall breaches - are reachable (the stash behind the bamboo clump opens with the puzzle: story suite)" % lines.size(), str(fails))
	# real walks with the keys, nothing teleported into a strip. Each leg: a 2 px foot-box path that stays >= 4 px clear of every
	# collider (margin 2), followed with the movement keys.
	var wfails := []
	var rows := []
	await r.teleport(spawn)
	r._build_grid()
	var res1: String = await nav.follow(r._astar(spawn, Vector2(770, 440)), 150.0)
	rows.append("spawn -> west of 正殿 (770,440): %s at %s" % [res1, p().global_position.round()])
	if res1 != "arrived":
		wfails.append(rows[-1])
	var strip_area := Rect2(100, 280, 1300, 190)
	var legs := [
		["into the walkway behind 正殿 (770,440 -> 780,400)", Vector2(780, 400), 2],
		["along 正殿's walkway, west end to east end", Vector2(1235, 400), 2],
		["and back to the west end", Vector2(780, 400), 2],
		["from the walkway up through the back gap along the dirt path (1010,400 -> 1008,330)", Vector2(1008, 330), 2],
		["from the grove side back down the path to the walkway", Vector2(1008, 400), 2],
		["along 正殿's walkway west to the 藏经阁 end, then the whole walkway behind 藏经阁 to its west end", Vector2(135, 400), 2],
		["and back east along 藏经阁's walkway", Vector2(400, 400), 2],
	]
	for leg in legs:
		var from: Vector2 = p().global_position
		var path := g2_path(from, leg[1], strip_area, leg[2])
		var res: String = await nav.follow(path, 60.0) if not path.is_empty() else "nopath"
		var at := p().global_position
		rows.append("%s: %s at %s" % [leg[0], res, at.round()])
		if res != "arrived" or at.distance_to(leg[1]) > 8.0:
			wfails.append(rows[-1])
	# both breaches both ways
	var area := Rect2(240, 290, 140, 130)
	for v in [["V1", Vector2(292, 400), Vector2(272, 330)], ["V2", Vector2(330, 400), Vector2(304, 330)]]:
		var south: Vector2 = v[1]
		var north: Vector2 = v[2]
		await r.teleport(south)
		var path := g2_path(south, north, area, 2)
		var up: String = await nav.follow(path, 40.0) if not path.is_empty() else "nopath"
		var at_n := p().global_position
		var crossed: bool = at_n.y < 350.0 and at_n.distance_to(north) < 8.0
		var path_b := g2_path(at_n, south, area, 2)
		var down: String = await nav.follow(path_b, 40.0) if not path_b.is_empty() else "nopath"
		var at_s := p().global_position
		var back: bool = at_s.y > 388.0 and at_s.distance_to(south) < 8.0
		rows.append("breach %s: north %s (%s), south again %s (%s)" % [v[0], up, at_n.round(), down, at_s.round()])
		if not (crossed and back):
			wfails.append(rows[-1])
	for l in rows:
		r._log("      walk " + l)
	r.check(wfails.is_empty(), "building AC4: real key walks from the spawn - around 正殿 into the walkway behind it and its full length both ways, up the back gap's dirt path and back, the full walkway behind 藏经阁 (west pocket included), both wall breaches both ways", str(wfails))
