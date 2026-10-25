class_name Npc
extends CharacterBody2D
## A standing NPC (idle animation, solid feet). Origin = between the feet.
## A CharacterBody2D (not a StaticBody2D) so the fighting NPCs (Fighter: 师兄, 狼, 野猪) can move; the others never do.

var id := ""
var title := ""          # 称呼, e.g. 师兄
var full_name := ""
var home_dir := "down"
var facing := "down"
var sprite: AnimatedSprite2D


func setup(data: Dictionary) -> void:
	id = data["id"]
	title = data["title"]
	full_name = data["name"]
	name = "Npc_" + id
	home_dir = data.get("dir", "down")
	facing = home_dir
	global_position = Vector2(data["x"], data["y"])
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 7)
	shape.shape = rect
	shape.position = Vector2(0, -2.5)
	add_child(shape)
	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.offset = Vector2(-16, -31)
	sprite.sprite_frames = CharSheet.frames_for(id)
	add_child(sprite)
	# desynchronise the breathing of different NPCs a little
	sprite.play("idle_" + facing)
	sprite.frame = abs(hash(id)) % 2
	sprite.speed_scale = 0.9 + float(abs(hash(id)) % 5) * 0.05


func face(dir: String) -> void:
	facing = dir
	sprite.play("idle_" + dir)


func face_towards(p: Vector2) -> void:
	var d := p - global_position
	face(CharSheet.dir_from_vector(d, facing))


func head_position() -> Vector2:
	return global_position + Vector2(0, -32)
