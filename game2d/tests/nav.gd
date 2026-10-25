extends RefCounted
## Walking helper for the story / interior tests (室内图进游戏 v1): plans a walk across the doors with the real movement
## keys. Outdoors it uses the walk grid of tests/run_tests.gd (r._build_grid / r._astar); inside a room it builds the
## same kind of 8 px grid over the room. Going through a door = walking into it (the game's own trigger + fade).
##   walk_to(target) -> "arrived" | "scene" (a conversation started on the way) | "stuck"

const STEP := 8

var r                       # the test runner (tests/run_tests.gd)
var g: Node                 # the game
var grids := {}             # room id -> {origin, w, h, free}
var doors_used := 0


func _init(runner, game: Node) -> void:
	r = runner
	g = game


func it() -> Interiors:
	return g.interiors


func p() -> Player:
	return g.player


# ------------------------------------------------------------------ room grids
func room_grid(id: String) -> Dictionary:
	if grids.has(id):
		return grids[id]
	var rect: Rect2 = it().rooms[id]["rect"]
	var w := int(rect.size.x) / STEP
	var h := int(rect.size.y) / STEP
	var free := PackedByteArray()
	free.resize(w * h)
	for gy in h:
		for gx in w:
			free[gy * w + gx] = 1 if r.is_free(rect.position + Vector2(gx * STEP + STEP * 0.5, gy * STEP + STEP * 0.5)) else 0
	var gr := {"origin": rect.position, "w": w, "h": h, "free": free}
	grids[id] = gr
	return gr


func cell_pos(gr: Dictionary, i: int) -> Vector2:
	return gr["origin"] + Vector2((i % int(gr["w"])) * STEP + STEP * 0.5, (i / int(gr["w"])) * STEP + STEP * 0.5)


func cell_of(gr: Dictionary, pos: Vector2) -> int:
	var l: Vector2 = pos - gr["origin"]
	var gx := clampi(int(l.x / STEP), 0, int(gr["w"]) - 1)
	var gy := clampi(int(l.y / STEP), 0, int(gr["h"]) - 1)
	return gy * int(gr["w"]) + gx


func nearest_free(gr: Dictionary, pos: Vector2) -> int:
	var i := cell_of(gr, pos)
	if gr["free"][i] == 1:
		return i
	var best := -1
	var bd := INF
	for j in (gr["free"] as PackedByteArray).size():
		if gr["free"][j] == 1:
			var d := cell_pos(gr, j).distance_to(pos)
			if d < bd:
				bd = d
				best = j
	return best


## Grid BFS inside a room: which cells can be walked to from `from` (array of 0/1 per cell).
func reachable(id: String, from: Vector2) -> PackedByteArray:
	var gr := room_grid(id)
	var w: int = gr["w"]
	var h: int = gr["h"]
	var seen := PackedByteArray()
	seen.resize(w * h)
	var s := nearest_free(gr, from)
	if s < 0:
		return seen
	seen[s] = 1
	var q := [s]
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var gx := i % w
		var gy := i / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = gx + d.x
			var ny: int = gy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if gr["free"][j] == 1 and seen[j] == 0:
				seen[j] = 1
				q.append(j)
	return seen


func room_path(id: String, from: Vector2, to: Vector2) -> Array:
	var gr := room_grid(id)
	var w: int = gr["w"]
	var h: int = gr["h"]
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(STEP, STEP)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for i in w * h:
		if gr["free"][i] == 0:
			astar.set_point_solid(Vector2i(i % w, i / w))
	var a := nearest_free(gr, from)
	var b := nearest_free(gr, to)
	if a < 0 or b < 0:
		return []
	var ids := astar.get_id_path(Vector2i(a % w, a / w), Vector2i(b % w, b / w))
	var pts := []
	for v in ids:
		pts.append(gr["origin"] + Vector2(v.x * STEP + STEP * 0.5, v.y * STEP + STEP * 0.5))
	if not pts.is_empty():
		pts[-1] = to if r.is_free(to) else pts[-1]
	return pts


# ------------------------------------------------------------------ walking
## Follows `path` with the movement keys. "arrived" | "scene" | "door" (a door fade started) | "stuck".
func follow(path: Array, limit := 90.0) -> String:
	var t := 0.0
	var wp := 0
	var last := p().global_position
	var stuck := 0.0
	var room0 := it().room_at(p().global_position)
	while wp < path.size():
		if g.story.busy:
			r.release_all()
			return "scene"
		if it().transitioning or it().room_at(p().global_position) != room0:
			r.release_all()
			await settle()
			return "door"
		var to: Vector2 = path[wp] - p().global_position
		if to.length() < 3.5:
			wp += 1
			continue
		r.hold_dir(to.normalized())
		await r.physics_frame
		t += 1.0 / 60.0
		stuck = stuck + 1.0 / 60.0 if p().global_position.distance_to(last) < 0.3 else 0.0
		last = p().global_position
		if stuck > 1.5 or t > limit:
			r.release_all()
			r._log("      walk stopped at %s (room '%s') -> %s" % [p().global_position.round(), it().room_at(p().global_position), path[-1]])
			return "stuck"
	r.release_all()
	await r.frames(2)
	return "scene" if g.story.busy else "arrived"


func settle() -> void:
	for i in 120:
		if not it().transitioning:
			break
		await r.physics_frame
	await r.frames(2)


## Walk out through the room door (to the doorway, then on into it). "door" when outside.
func go_out(id: String) -> String:
	var res := await follow(room_path(id, p().global_position, it().entry_spot(id)))
	if res != "arrived" and res != "door":
		return res
	if it().room_at(p().global_position) == "":
		return "door"
	r.hold_dir(Vector2.DOWN)
	for i in 120:
		await r.physics_frame
		if it().transitioning:
			break
	r.release_all()
	await settle()
	if it().room_at(p().global_position) == "":
		doors_used += 1
		return "door"
	return "stuck"


## Walk outdoors to the door of `id`, then into it. "door" when inside.
func go_in(id: String) -> String:
	r._build_grid()
	var res := await follow(r._astar(p().global_position, it().exit_spot(id)), 120.0)
	if res != "arrived" and res != "door":
		return res
	if it().room_at(p().global_position) == id:
		return "door"
	if it().room_at(p().global_position) != "":
		return "door"      # went into another door on the way: walk_to plans again
	r.hold_dir(Vector2.UP)
	for i in 120:
		await r.physics_frame
		if it().transitioning:
			break
	r.release_all()
	await settle()
	if it().room_at(p().global_position) == id:
		doors_used += 1
		return "door"
	return "stuck"


func walk_to(target: Vector2, limit := 120.0) -> String:
	for attempt in 8:
		var cur := it().room_at(p().global_position)
		var dst := it().room_at(target)
		var res := ""
		if cur == dst:
			var path: Array
			if cur == "":
				r._build_grid()
				path = r._astar(p().global_position, target)
			else:
				path = room_path(cur, p().global_position, target)
			res = await follow(path, limit)
			if res != "door":
				return res
			continue
		if cur != "":
			res = await go_out(cur)
		else:
			res = await go_in(dst)
		if res == "scene" or res == "stuck":
			return res
	return "stuck"
