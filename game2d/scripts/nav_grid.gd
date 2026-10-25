class_name NavGrid
extends RefCounted
## Walkable grid for the fighters (8 px cells), built from the collision rectangles in map_data.json plus the
## standing NPCs. A cell is free when an enemy's foot box (FOOT, centred on the cell) touches no obstacle.
## Enemies walk straight at their target when the line is clear, otherwise follow an A* path around obstacles.

const CELL := 8
const FOOT := Vector2(14, 7)     # must match npc.gd (shape 14 x 7, 2.5 px above the feet)
const FOOT_UP := 2.5

var w := 0
var h := 0
var free := PackedByteArray()
var astar := AStarGrid2D.new()


func build(colliders: Array, extra_rects: Array, map_size: Vector2) -> void:
	w = int(ceil(map_size.x / CELL))
	h = int(ceil(map_size.y / CELL))
	free.resize(w * h)
	free.fill(1)
	var rects: Array[Rect2] = []
	for c in colliders:
		var r: Array = c["rect"]
		rects.append(Rect2(r[0], r[1], r[2], r[3]))
	for r in extra_rects:
		rects.append(r)
	for r in rects:
		# cells whose foot box would overlap r
		var grown := Rect2(r.position - Vector2(FOOT.x * 0.5, FOOT.y * 0.5 - FOOT_UP), r.size + FOOT)
		var x0 := clampi(int(floor(grown.position.x / CELL)), 0, w - 1)
		var y0 := clampi(int(floor(grown.position.y / CELL)), 0, h - 1)
		var x1 := clampi(int(floor(grown.end.x / CELL)), 0, w - 1)
		var y1 := clampi(int(floor(grown.end.y / CELL)), 0, h - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var c := cell_center(gx, gy)
				if c.x > grown.position.x and c.x < grown.end.x and c.y > grown.position.y and c.y < grown.end.y:
					free[gy * w + gx] = 0
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL * 0.5, CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for gy in h:
		for gx in w:
			if free[gy * w + gx] == 0:
				astar.set_point_solid(Vector2i(gx, gy))


func cell_center(gx: int, gy: int) -> Vector2:
	return Vector2(gx * CELL + CELL * 0.5, gy * CELL + CELL * 0.5)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, w - 1), clampi(int(p.y / CELL), 0, h - 1))


func is_free_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and free[c.y * w + c.x] == 1


func nearest_free(c: Vector2i) -> Vector2i:
	if is_free_cell(c):
		return c
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d := c + Vector2i(dx, dy)
				if is_free_cell(d):
					return d
	return c


## True when every cell along the segment is free (a conservative "can walk straight there" test).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(ceil(d.length() / 4.0))
	for i in range(1, n + 1):
		if not is_free_cell(cell_of(a + d * (float(i) / n))):
			return false
	return true


## A* path (cell centres, first point dropped) from a to b; empty when unreachable.
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := nearest_free(cell_of(a))
	var cb := nearest_free(cell_of(b))
	var pts := astar.get_point_path(ca, cb)
	if pts.size() > 0:
		pts.remove_at(0)
	return pts
