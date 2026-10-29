class_name Sfx
extends RefCounted
## 音效 + 背景音乐 v1: sounds for every script (static calls: Sfx.play("gp_success"), Sfx.music("opening"), Sfx.auto() ...).
## The state lives in the autoload node "AudioService" (scripts/audio_service.gd); this class only reaches it, so scripts
## compile even where autoload names are not known yet (the headless test runner) - and without it every call does nothing.
## Event names and which sound / track they use: data/audio.json ("events", "scenes").

static func service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioService") if tree != null and tree.root != null else null


## Plays the sound of an event (data/audio.json "events": gp_success, hit, hit_heavy, player_hurt, dodge, telegraph,
## knockdown, dialogue_page, choice_move, coin, guide_complete, quest_complete, panel_open) - or a sound id itself.
static func play(event: String) -> void:
	var s := service()
	if s != null:
		s.play(event)


## Forces a track ("day" / "night" / "battle" / "opening"; "" = silence) with a 1 s cross-fade. The same track again
## does nothing. Sfx.auto() hands the music back to the game.
static func music(track: String) -> void:
	var s := service()
	if s != null:
		s.force_music(track)


## Music chosen by the game again: title screen -> opening; in the game battle while fighting, else day / night by the clock.
static func auto() -> void:
	var s := service()
	if s != null:
		s.auto_music()


## kind "music" / "sfx" -> level 0..3 (关 / 小 / 中 / 大).
static func volume(kind: String) -> int:
	var s := service()
	return s.get_level(kind) if s != null else 0


static func set_volume(kind: String, level: int) -> void:
	var s := service()
	if s != null:
		s.set_level(kind, level)


## The track playing now ("" = none).
static func current_track() -> String:
	var s := service()
	return s.track if s != null else ""
