class_name CharSheet
extends RefCounted
## Builds SpriteFrames from a pixel2d character sheet (assets/characters/<id>.png + .json):
## rows = directions (down, left, right, up), columns 0-1 idle, 2-5 walk. Animations: "idle_<dir>", "walk_<dir>".
## Combat actions (optional art, copied by tools/sync_assets.py from pixel2d/characters/output/combat/):
## assets/combat/<id>_combat.png + <id>_combat.json, rows = "directions", "frame_size" [w, h], JSON "actions" list
## attack1 / attack2 / windup / hurt / down with start (or first_column), count (or frames), fps, hit_frame.
## They become animations "<action>_<dir>". When the files are missing nothing is added and the game falls back
## to the walk frames (see has_action()).

const DIRS := ["down", "left", "right", "up"]
const COMBAT_ACTIONS := ["attack1", "attack2", "windup", "hurt", "down", "charge"]

static var _cache := {}
static var _actions := {}   # id -> {action: {"count", "fps", "hit_frame"}}
static var _aliases := {}   # 第③步: id -> stand-in id, used while assets/characters/<id>.png does not exist yet


## 第③步: a character whose art has not landed yet borrows another sheet (its own id stays everywhere else: talk rules,
## speakers, tests). Once assets/characters/<id>.png exists the alias is ignored.
static func alias(id: String, stand_in: String) -> void:
	_aliases[id] = stand_in


static func has_own_art(id: String) -> bool:
	return ResourceLoader.exists("res://assets/characters/%s.png" % id)


static func frames_for(id: String) -> SpriteFrames:
	if _cache.has(id):
		return _cache[id]
	if _aliases.has(id) and not has_own_art(id):
		var sf_alias := frames_for(String(_aliases[id]))
		_cache[id] = sf_alias
		_actions[id] = _actions.get(String(_aliases[id]), {})
		return sf_alias
	var tex: Texture2D = load("res://assets/characters/%s.png" % id)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/%s.json" % id))
	var fw := int(meta.get("frame_width", 32))
	var fh := int(meta.get("frame_height", 32))
	var rows: Array = meta.get("rows", DIRS)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in meta["animations"]:
		var a: Dictionary = meta["animations"][anim_name]
		for r in rows.size():
			var key := "%s_%s" % [anim_name, rows[r]]
			sf.add_animation(key)
			sf.set_animation_speed(key, float(a.get("fps", 8)))
			sf.set_animation_loop(key, bool(a.get("loop", true)))
			for i in int(a["frames"]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2((int(a["first_column"]) + i) * fw, r * fh, fw, fh)
				sf.add_frame(key, at)
	_add_combat_actions(id, sf)
	_cache[id] = sf
	return sf


static func _add_combat_actions(id: String, sf: SpriteFrames) -> void:
	_actions[id] = {}
	var json_path := "res://assets/combat/%s_combat.json" % id
	var png_path := "res://assets/combat/%s_combat.png" % id
	if not FileAccess.file_exists(json_path) or not ResourceLoader.exists(png_path):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(meta) != TYPE_DICTIONARY:
		push_warning("CharSheet: cannot read " + json_path)
		return
	var tex: Texture2D = load(png_path)
	var fs: Array = meta.get("frame_size", [meta.get("frame_width", 32), meta.get("frame_height", 32)])
	var fw := int(fs[0])
	var fh := int(fs[1])
	var rows: Array = meta.get("directions", meta.get("rows", DIRS))
	var acts: Dictionary = meta.get("actions", meta.get("animations", {}))
	for act in acts:
		var a: Dictionary = acts[act]
		var start := int(a.get("start", a.get("first_column", 0)))
		var count := int(a.get("count", a.get("frames", 1)))
		var fps := float(a.get("fps", 10))
		if count <= 0:
			continue
		for r in rows.size():
			var key := "%s_%s" % [act, rows[r]]
			if sf.has_animation(key):
				continue
			sf.add_animation(key)
			sf.set_animation_speed(key, fps)
			sf.set_animation_loop(key, bool(a.get("loop", false)))
			for i in count:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2((start + i) * fw, r * fh, fw, fh)
				sf.add_frame(key, at)
		_actions[id][act] = {"count": count, "fps": fps, "hit_frame": int(a.get("hit_frame", -1))}


## True when the combat art for this character has the action (otherwise the caller uses the walk frames).
static func has_action(id: String, action: String) -> bool:
	frames_for(id)
	return _actions.get(id, {}).has(action)


static func action_info(id: String, action: String) -> Dictionary:
	frames_for(id)
	return _actions.get(id, {}).get(action, {})


## Speed scale that makes an action animation last `length` seconds, with its hit frame (if any) shown at `impact`.
static func action_speed(id: String, action: String, length: float, impact := -1.0) -> float:
	var info := action_info(id, action)
	if info.is_empty() or length <= 0.0:
		return 1.0
	var natural := float(info["count"]) / float(info["fps"])
	var want := length
	if impact > 0.0 and int(info["hit_frame"]) > 0:
		natural = float(info["hit_frame"]) / float(info["fps"])
		want = impact
	return clampf(natural / want, 0.25, 4.0)


static func dir_vector(dir: String) -> Vector2:
	match dir:
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		"up":
			return Vector2.UP
	return Vector2.DOWN


static func dir_from_vector(v: Vector2, current: String) -> String:
	## Dominant axis wins; on an exact diagonal keep the current facing if it is one of the two components.
	if v == Vector2.ZERO:
		return current
	var h := "right" if v.x > 0 else "left"
	var vv := "down" if v.y > 0 else "up"
	if absf(absf(v.x) - absf(v.y)) < 0.01:
		if current == h or current == vv:
			return current
		return h
	return h if absf(v.x) > absf(v.y) else vv
