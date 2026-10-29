class_name SkillsFx
extends Node
## 武学与经营 第一批 · 武学 (A): the skills' effects in the world.
##   sprite strips   assets/skills/<name>.png + .json (pixel2d/skills_fx, the pixel-vfx native backend): played once with
##                   an AnimatedSprite2D in the y-sorted world - 燕回旋 尘环 (spin_ring, under the rabbit) + 弧形腿影
##                   (spin_arc, over him), 踏雪 雪花印 (snow_mark, on the ground where the second dodge lands).
##   particles       CPUParticles2D (particles-vfx: CPU particles are the steadier choice on the web build): dust thrown
##                   up when the spin lands, white snow bits on the second dodge, and the faint jade 气流 round the rabbit
##                   while 吐纳功 runs (very few, mostly transparent - never in the way).
## Missing art = the particles still play (nothing fails).

const ART := "res://assets/skills/"

var main: Node
var frames := {}                   # name -> SpriteFrames
var sizes := {}                    # name -> Vector2 (frame size)
var spawned := {}                  # name -> count (tests / screenshots)
var qi_flow: CPUParticles2D        # 吐纳功 running


func setup(m: Node) -> void:
	main = m
	name = "SkillsFx"
	for n in ["spin_ring", "spin_arc", "snow_mark", "tuna_ring", "icons"]:
		_load_strip(n)


func _load_strip(n: String) -> void:
	var png := ART + n + ".png"
	var js := ART + n + ".json"
	if not ResourceLoader.exists(png) or not FileAccess.file_exists(js):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(js))
	if not (meta is Dictionary):
		return
	var tex: Texture2D = load(png)
	var tags: Array = meta.get("meta", {}).get("frameTags", [])
	var order: Array = tags[0]["frames"] if not tags.is_empty() else (meta["frames"] as Dictionary).keys()
	var durs: Array = tags[0].get("durations_ms", []) if not tags.is_empty() else []
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation(n)
	sf.set_animation_loop(n, n == "tuna_ring")
	sf.set_animation_speed(n, 100.0)            # 1 frame unit = 10 ms: each frame's duration is its ms / 10
	var fs := Vector2.ZERO
	for i in order.size():
		var r: Dictionary = meta["frames"][order[i]]["frame"]
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]))
		fs = Vector2(float(r["w"]), float(r["h"]))
		sf.add_frame(n, at, float(durs[i]) / 10.0 if i < durs.size() else 10.0)
	frames[n] = sf
	sizes[n] = fs


func has_art(n: String) -> bool:
	return frames.has(n)


func _note(n: String) -> void:
	spawned[n] = int(spawned.get(n, 0)) + 1


## A one-shot strip at `feet` in the world; `sort_dy` < 0 draws it under a body standing there, > 0 over it.
func play_strip(n: String, feet: Vector2, sort_dy := -1.0) -> AnimatedSprite2D:
	_note(n)
	if not frames.has(n) or main == null:
		return null
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames[n]
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = (feet + Vector2(0, sort_dy)).round()
	s.offset = Vector2(0, -sort_dy)
	s.set_meta("type", "skill_fx_" + n)
	s.add_to_group("skill_fx")
	main.world.add_child(s)
	s.play(n)
	s.animation_finished.connect(s.queue_free)
	return s


# ------------------------------------------------------------------ 燕回旋
func spin_start(feet: Vector2) -> void:
	play_strip("spin_ring", feet, -2.0)
	play_strip("spin_arc", feet + Vector2(0, -8), 10.0)


func spin_land(feet: Vector2) -> void:
	_burst("spin_dust", feet, 16, 0.45, Color(0.85, 0.74, 0.55), Color(0.55, 0.42, 0.28), 34.0, 70.0, 26.0, 60.0)


# ------------------------------------------------------------------ 踏雪二段闪
func snow_start(feet: Vector2) -> void:
	_burst("snow_bits", feet, 10, 0.4, Color(1, 1, 1), Color(0.7, 0.85, 1.0), 6.0, 40.0, 10.0, -20.0)


func snow_land(feet: Vector2) -> void:
	play_strip("snow_mark", feet, -1.0)
	_burst("snow_bits", feet, 8, 0.35, Color(1, 1, 1), Color(0.75, 0.88, 1.0), 4.0, 30.0, 8.0, -30.0)


## One-shot CPU particles (pixel squares) at `feet`: radial throw, a little up-drift, fading out by colour ramp.
func _burst(n: String, feet: Vector2, amount: int, life: float, c0: Color, c1: Color, ring: float, speed: float,
		spread_up: float, gravity: float) -> CPUParticles2D:
	_note(n)
	if main == null:
		return null
	var p := CPUParticles2D.new()
	p.name = "SkillBurst_" + n
	p.position = feet
	p.z_index = 1
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = ring
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, Color(c1.r, c1.g, c1.b, 0.0))
	p.color_ramp = g
	p.add_to_group("skill_fx")
	main.world.add_child(p)
	p.emitting = true
	var t := get_tree().create_timer(life + 0.3, false)
	t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	return p


# ------------------------------------------------------------------ 吐纳功 气流
## The faint jade air round the rabbit while 吐纳功 runs (on = learned).
func set_qi_flow(on: bool) -> void:
	if main == null:
		return
	if not on:
		if qi_flow != null and is_instance_valid(qi_flow):
			qi_flow.queue_free()
		qi_flow = null
		return
	if qi_flow != null and is_instance_valid(qi_flow):
		return
	var p := CPUParticles2D.new()
	p.name = "TunaQiFlow"
	p.position = Vector2(0, -12)
	p.amount = 5
	p.lifetime = 1.6
	p.preprocess = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(9, 10)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector2.ZERO
	p.tangential_accel_min = -6.0
	p.tangential_accel_max = 6.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(0.62, 0.94, 0.86, 0.0))
	g.add_point(0.4, Color(0.62, 0.94, 0.86, 0.32))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.8, 0.75, 0.0))
	p.color_ramp = g
	p.add_to_group("skill_fx")
	main.player.add_child(p)
	p.emitting = true
	qi_flow = p
