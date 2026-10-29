class_name Seats
extends Node
## 坐下与人物作息 v1 · 坐下 (docs/design/坐下与人物作息-方案-v1.md section 一). The 8 seats: data/interiors.json "seats" (宿舍 2
## 坐垫, 正殿 4 蒲团, 厨房 烧火的小板凳 + 长凳; room px of the rabbit's feet while sitting, `lift` = the picture raised onto
## the stool / bench while his feet stay in front of its collision box, `radius` of the prompt, `line` = the first-time bubble).
##   E          "按 E 坐下" when nothing else is in reach (every other E target wins: the seats never take a prompt away)
##              and nobody stands on the seat (师父 on his worn 蒲团 by day). 坐姿重画 v1: the seat's `pose` picks the
##              picture - "back" (bench / stool with a table or the stove in front): seen from behind, facing up,
##              assets/schedule/rabbit_sit_back.png; "cross" (cushion / 蒲团 on the floor): cross-legged, facing down,
##              rabbit_sit_cross.png; no pose: the old front picture rabbit_sit.png. Each one breathes (2 frames).
##   stand up   an arrow key / WASD, E or Space: back exactly where he stood before sitting down (or the nearest free spot if
##              somebody turned up there meanwhile) - never inside a wall.
##   bubbles    the seat's line, once per seat per session (not saved), as a bubble over his head (Schedule.say).
## Pure mood: nothing is paid, healed or saved. While sitting: no prompts, J / K / mouse do nothing, T / Esc / Q work.

const DATA := "res://data/interiors.json"
const SIT_ART := "res://assets/schedule/rabbit_sit.png"
const SIT_META := "res://assets/schedule/rabbit_sit.json"
const OCCUPIED := 16.0             # px: a visible person this close to a seat is sitting / standing on it
const ANIM := "sit_down"          # the old front picture (seats without a pose)
## 坐姿重画 v1: seat "pose" -> its picture, animation and facing (pixel2d/sit_pose/tools/generate_sit_pose.py)
const POSES := {
	"back": {"art": "res://assets/schedule/rabbit_sit_back.png", "meta": "res://assets/schedule/rabbit_sit_back.json",
		"anim": "sit_back", "facing": "up"},
	"cross": {"art": "res://assets/schedule/rabbit_sit_cross.png", "meta": "res://assets/schedule/rabbit_sit_cross.json",
		"anim": "sit_cross", "facing": "down"},
}

var main: Node
var seats: Array = []              # interiors.json "seats"
var sitting := ""                  # id of the seat he is on ("" = standing)
var sit_from := Vector2.ZERO       # where he stood before sitting down
var sat: Array[String] = []        # every sit-down (tests)
var stands := 0                    # every stand-up (tests)
var stood_at := Vector2.INF        # where the last stand-up put him (tests)
var said: Dictionary = {}          # seat id -> true once its line was shown
var lines_shown: Array[String] = []


func _init() -> void:
	name = "Seats"


func setup(m: Node) -> void:
	main = m
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	seats = (cfg.get("seats", []) as Array) if cfg is Dictionary else []
	_add_sit_animation(ANIM, SIT_ART, SIT_META)
	for pose in POSES:
		_add_sit_animation(POSES[pose]["anim"], POSES[pose]["art"], POSES[pose]["meta"])


## Adds a 2-frame sitting animation to the rabbit's SpriteFrames once; without the art he sits in his idle frames.
func _add_sit_animation(anim: String, art: String, meta_path: String) -> void:
	var sf: SpriteFrames = CharSheet.frames_for("rabbit")
	if sf.has_animation(anim) or not ResourceLoader.exists(art):
		return
	var tex: Texture2D = load(art)
	var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path)) if FileAccess.file_exists(meta_path) else {}
	var fw := int(meta.get("frame_width", 32)) if meta is Dictionary else 32
	var fh := int(meta.get("frame_height", 32)) if meta is Dictionary else 32
	var n := int(meta.get("frames", 2)) if meta is Dictionary else 2
	sf.add_animation(anim)
	sf.set_animation_speed(anim, float(meta.get("fps", 2)) if meta is Dictionary else 2.0)
	sf.set_animation_loop(anim, true)
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame(anim, at)


## The sitting animation for seat `s` (its pose's, or the old front one when the pose or its art is missing).
func pose_anim(s: Dictionary) -> String:
	var pose := String(s.get("pose", ""))
	var sf: SpriteFrames = CharSheet.frames_for("rabbit")
	if POSES.has(pose) and sf.has_animation(POSES[pose]["anim"]):
		return POSES[pose]["anim"]
	return ANIM


## The way he faces while sitting on `s`: "up" for the back view (facing the table), else "down".
func pose_facing(s: Dictionary) -> String:
	var pose := String(s.get("pose", ""))
	return String(POSES[pose]["facing"]) if POSES.has(pose) and pose_anim(s) != ANIM else "down"


func seat(id: String) -> Dictionary:
	for s in seats:
		if String(s["id"]) == id:
			return s
	return {}


## World point of the rabbit's feet while sitting on `s`.
func seat_world(s: Dictionary) -> Vector2:
	var p: Array = s["pos"]
	return main.interiors.world_point(String(s["room"]), Vector2(float(p[0]), float(p[1])))


## Where the seat itself is (his lap while sitting) - used for "somebody is on it".
func seat_center(s: Dictionary) -> Vector2:
	return seat_world(s) + Vector2(0, -float(s.get("lift", 0)) - 4.0)


func occupied(s: Dictionary) -> bool:
	var c := seat_center(s)
	for n in main.npcs:
		if n.visible and n.global_position.distance_to(c) < OCCUPIED:
			return true
	return false


# ------------------------------------------------------------------ E
## Story.interaction_target hook: only when nothing else is in reach (`best` empty).
func interaction_target(p: Vector2, best: Dictionary) -> Dictionary:
	if sitting != "" or not best.is_empty() or main.story.sandbox:
		return {}
	var out := {}
	var bd := INF
	for s in seats:
		var w := seat_world(s)
		var d := w.distance_to(p)
		if d > float(s.get("radius", 24)) or d >= bd or occupied(s):
			continue
		bd = d
		out = {"kind": "schedule", "id": "seat", "seat": String(s["id"]), "prompt": main.schedule.ui("prompt_sit"),
			"prompt_pos": w + Vector2(0, -34.0 - float(s.get("lift", 0))), "dist": d}
	return out


func sit(id: String) -> bool:
	var s := seat(id)
	if s.is_empty() or sitting != "" or occupied(s):
		return false
	var p: Player = main.player
	sitting = id
	sit_from = p.global_position
	sat.append(id)
	p.velocity = Vector2.ZERO
	p.set_physics_process(false)
	p.global_position = seat_world(s)
	p.facing = pose_facing(s)
	p.sprite.rotation = 0.0
	p.sprite.offset = Vector2(-16, -31.0 - float(s.get("lift", 0)))   # every sitting sheet is anchored at (16, 31)
	p.sprite.position = p.global_position.round() - p.global_position
	p.sprite.speed_scale = 1.0
	var anim := pose_anim(s)
	p.sprite.play(anim if p.sprite.sprite_frames.has_animation(anim) else "idle_" + p.facing)
	var line := String(s.get("line", ""))
	if line != "" and not said.has(id):
		said[id] = true
		lines_shown.append(line)
		main.schedule.say(line, Vector2.ZERO, p, float(s.get("lift", 0)), float(main.schedule.data.get("line_seconds", 3.0)), "rabbit", true)
	if OS.has_feature("web"):
		print("seats: sit %s" % id)
	return true


func stand() -> void:
	if sitting == "":
		return
	var p: Player = main.player
	sitting = ""
	stands += 1
	var to := sit_from
	if not _free(to):
		to = _free_near(to)
	p.global_position = to
	stood_at = to
	p.velocity = Vector2.ZERO
	p.sprite.offset = Vector2(-16, -31)
	p.set("_dash_requested", false)
	p.set("_attack_requested", false)
	p.set("_gp_requested", false)
	p.set_physics_process(true)
	p.sprite.play("idle_" + p.facing)
	if OS.has_feature("web"):
		print("seats: stand up")


func _free(at: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var r := RectangleShape2D.new()
	r.size = Player.FOOT_SIZE
	q.shape = r
	q.transform = Transform2D(0.0, at + Vector2(0, -2))
	q.collision_mask = 1
	q.exclude = [main.player.get_rid()]
	return main.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _free_near(at: Vector2) -> Vector2:
	for rad in range(4, 41, 4):
		for off in [Vector2(0, rad), Vector2(0, -rad), Vector2(rad, 0), Vector2(-rad, 0), Vector2(rad, rad), Vector2(-rad, rad),
				Vector2(rad, -rad), Vector2(-rad, -rad)]:
			if _free(at + off):
				return at + off
	return at


## While sitting: a direction, E or Space stands him up; attack / guard do nothing. Runs before the Player and Main
## (a later child of Main), so the key that stands him up does nothing else.
func _unhandled_input(event: InputEvent) -> void:
	if sitting == "" or not (event is InputEventKey or event is InputEventMouseButton):
		return
	var sch = main.get("schedule")
	if sch != null and sch.waiting:
		return
	var sk = main.get("skills")
	if event.is_action_pressed("interact") and sk != null and sk.sit_interact():
		get_viewport().set_input_as_handled()     # 武学 (A): E on a 正殿 蒲团 during the 吐纳功 trial = 打坐 (he stays seated)
		return
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down") or event.is_action_pressed("move_left") \
			or event.is_action_pressed("move_right") or event.is_action_pressed("interact") or event.is_action_pressed("dash"):
		stand()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") or (InputMap.has_action("gp") and event.is_action_pressed("gp")):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if sitting == "" or main == null:
		return
	var p: Player = main.player
	var anim := pose_anim(seat(sitting))
	if p.sprite.animation != anim and p.sprite.sprite_frames.has_animation(anim):
		p.sprite.play(anim)
	if p.dead or main.story.sandbox:
		stand()
