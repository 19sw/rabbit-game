extends Node
## Autoload "AudioService" (音效 + 背景音乐 v1; scripts use it through the static class Sfx, scripts/sfx.gd).
##
## Sounds: assets/audio/sfx/<id>.wav and music/<id>.wav (synthesised by audio/tools/generate_audio.py, copied by
## tools/sync_assets.py). Which event plays which sound and which scene plays which track: data/audio.json.
## - Sound effects: a small pool of players; the same sound at most once per min_repeat_seconds; "关" = not played.
##   Requests of one frame are played together at its end, so a 完成 that also pays coins sounds once (data "suppress").
## - Music: two players cross-fade (crossfade_seconds). The same track again does nothing. Auto mode picks it: the title
##   screen -> "title"; in the game "battle" while Combat.in_combat() (held battle_hold_seconds after), otherwise
##   "night" / "day" by the game clock. Sfx.music(id) forces a track (the opening film), Sfx.auto() hands it back; a new
##   game (a Combat entering the tree) hands it back too.
## - Wiring without touching the game scripts: every node that enters the tree is looked at once (node_added); Combat,
##   Dialogue, Sample, the panels, Guide / Bounty / Commission and the TitleScreen are connected or watched by name.
## - Volume: two settings (music / sfx), four levels each (data "volume_levels"). A setting, not part of the save:
##   user://settings.cfg [audio] (the language lives in the same file under [game]), on the web also localStorage
##   "aw_audio". Automated runs never read or write the player's setting.
## - Web: browsers keep a page silent until the player does something, so nothing plays before the first key / click /
##   touch; the track asked for meanwhile starts then.
## Runs while the game is paused (the Esc page opens with a sound, the music goes on).

signal levels_changed

const DATA := "res://data/audio.json"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SETTINGS := "user://settings.cfg"
const WEB_KEY := "aw_audio"
const KINDS := ["music", "sfx"]
const LOG_MAX := 400
const SILENT_DB := -80.0

var data: Dictionary = {}
var levels := {"music": 2, "sfx": 2}
var settings_path := SETTINGS
var persist := true                 # false in automated runs (tests switch it on with their own settings_path)
var unlocked := true                # web: false until the first input
var track := ""                     # the track that plays now (or starts once unlocked)
var forced := ""                    # Sfx.music(id)
var forced_on := false
var sfx_log: Array = []             # tests: [{event, id, played}] - every sound effect asked for
var sfx_count := 0                  # tests: sound effects asked for so far (sfx_log keeps the last LOG_MAX)
var music_log: Array = []           # tests: every track change ("" = silence)
var sfx_streams := {}               # id -> AudioStream
var music_streams := {}             # id -> AudioStream
var voices: Array[AudioStreamPlayer] = []
var music_players: Array[AudioStreamPlayer] = []
var music_gain := {}                # player -> [gain 0..1, target 0..1]
var _next_voice := 0
var _last_play := {}                # id -> _clock when it last played
var _pending: Array = []            # events of this frame, played at its end
var _flush_queued := false
var _clock := 0.0                   # seconds of _process time (the same-sound gap is measured in game frames)
var _battle_hold := 0.0
var _combat: WeakRef = null
var _title: WeakRef = null
var _title_sel := -1
var _dialogues: Array = []          # [WeakRef, pages_shown, choice_index, active] (dialogues without the 'advanced' signal)
var _counters: Array = []           # [WeakRef, property, last size, event]
var _coins := {}                    # Sample instance id -> coins at the start of this frame
var _samples: Array = []            # WeakRef of every Sample


func _ready() -> void:
	name = "AudioService"
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_data()
	if _under_test():
		persist = false
	if OS.has_feature("web"):
		unlocked = false
	_load_settings()
	for i in int(data.get("voices", 8)):
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		voices.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		add_child(m)
		music_players.append(m)
		music_gain[m] = [0.0, 0.0]
	get_tree().node_added.connect(_on_node_added)


func reload_data() -> void:
	var txt := FileAccess.get_file_as_string(DATA)
	var d: Variant = JSON.parse_string(txt) if txt != "" else null
	data = d if d is Dictionary else {}
	var dl: Dictionary = data.get("default_level", {})
	for k in KINDS:
		levels[k] = clampi(int(dl.get(k, 2)), 0, level_count() - 1)


static func _under_test() -> bool:
	var ml := Engine.get_main_loop()
	return DisplayServer.get_name() == "headless" or (ml != null and ml.get_script() != null)


# ------------------------------------------------------------------ volume
func level_count() -> int:
	return maxi(1, (data.get("volume_levels", [{}, {}, {}, {}]) as Array).size())


func level_names() -> Array:
	return (data.get("volume_levels", []) as Array).map(func(v): return String(v.get("name", "")))


func get_level(kind: String) -> int:
	return int(levels.get(kind, 0))


## The linear volume of a level (data "volume_levels").
func level_linear(level: int) -> float:
	var lv: Array = data.get("volume_levels", [])
	if level < 0 or level >= lv.size():
		return 0.0
	return float(lv[level].get("linear", 0.0))


func set_level(kind: String, level: int) -> void:
	if not kind in KINDS:
		return
	level = clampi(level, 0, level_count() - 1)
	if levels[kind] == level:
		return
	levels[kind] = level
	_store_settings()
	levels_changed.emit()


func _gain(kind: String) -> float:
	return level_linear(get_level(kind)) * float(data.get(kind + "_trim", 1.0))


static func _db(v: float) -> float:
	return SILENT_DB if v <= 0.0001 else maxf(SILENT_DB, linear_to_db(v))


func _load_settings() -> void:
	if not persist:
		return
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % WEB_KEY)
		var d: Variant = JSON.parse_string(str(v)) if str(v) != "" else null
		if d is Dictionary:
			for k in KINDS:
				if d.has(k):
					levels[k] = clampi(int(d[k]), 0, level_count() - 1)
			return
	var cf := ConfigFile.new()
	if cf.load(settings_path) == OK:
		for k in KINDS:
			levels[k] = clampi(int(cf.get_value("audio", k, levels[k])), 0, level_count() - 1)


func _store_settings() -> void:
	if not persist:
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('%s',%s)}catch(e){}" % [WEB_KEY, JSON.stringify(JSON.stringify(levels))])
	var cf := ConfigFile.new()
	cf.load(settings_path)              # keeps the other settings in the file ([game] lang)
	for k in KINDS:
		cf.set_value("audio", k, levels[k])
	cf.save(settings_path)


# ------------------------------------------------------------------ sound effects
## The sound id of an event (or the id itself).
func sound_for(event: String) -> String:
	return String((data.get("events", {}) as Dictionary).get(event, event))


func play(event: String) -> void:
	_pending.append(event)
	_queue_flush()


func _queue_flush() -> void:
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_flush_queued = false
	_poll_counters()
	var evs := _pending
	_pending = []
	var sup: Dictionary = data.get("suppress", {})
	var drop := {}
	for e in evs:
		for x in sup.get(e, []):
			drop[String(x)] = true
	var done := {}
	for e in evs:
		if drop.has(e) or done.has(e):
			continue
		done[e] = true
		_play_now(e)


func _play_now(event: String) -> void:
	var id := sound_for(event)
	var st := _sfx_stream(id)
	var g := _gain("sfx")
	var recent := _clock - float(_last_play.get(id, -100.0)) < float(data.get("min_repeat_seconds", 0.03))
	var played := st != null and g > 0.0001 and unlocked and not recent and not voices.is_empty()
	if played:
		_last_play[id] = _clock
		var p := voices[_next_voice]
		_next_voice = (_next_voice + 1) % voices.size()
		p.stream = st
		p.volume_db = _db(g)
		p.play()
	sfx_log.append({"event": event, "id": id, "played": played})
	sfx_count += 1
	if sfx_log.size() > LOG_MAX:
		sfx_log = sfx_log.slice(sfx_log.size() - LOG_MAX)


func _sfx_stream(id: String) -> AudioStream:
	if not sfx_streams.has(id):
		var path := SFX_DIR + id + ".wav"
		sfx_streams[id] = load(path) if ResourceLoader.exists(path) else null
	return sfx_streams[id]


# ------------------------------------------------------------------ music
func force_music(id: String) -> void:
	forced = id
	forced_on = true
	_set_track(id)


func auto_music() -> void:
	forced_on = false
	forced = ""
	_set_track(wanted_track())


## The track for a scene (data "scenes": title / opening / day / night / battle).
func track_for(scene: String) -> String:
	return String((data.get("scenes", {}) as Dictionary).get(scene, scene))


func is_night(hour: float) -> bool:
	var a := float(data.get("night_from_hour", 18.5))
	var b := float(data.get("night_until_hour", 6.0))
	return hour >= a or hour < b if a > b else (hour >= a and hour < b)


## What the music should be now.
func wanted_track() -> String:
	if forced_on:
		return forced
	var c: Node = _alive(_combat)
	if c != null and c.is_inside_tree():
		if (c.has_method("in_combat") and c.in_combat()) or _battle_hold > 0.0:
			return track_for("battle")
		var m = c.get("main")
		var dn = m.get("daynight") if m != null and is_instance_valid(m) else null
		if dn != null:
			return track_for("night" if is_night(float(dn.hour)) else "day")
		return track_for("day")
	var t: Node = _alive(_title)
	if t != null and t.is_inside_tree():
		return track_for("title")
	return track


func _music_stream(id: String) -> AudioStream:
	if not music_streams.has(id):
		var path := MUSIC_DIR + id + ".wav"
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s is AudioStreamWAV:
			# the file's smpl loop is read with its end as the last frame; loop over every frame
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(round(w.get_length() * w.mix_rate))
		music_streams[id] = s
	return music_streams[id]


func _set_track(id: String) -> void:
	if id == track:
		return
	track = id
	music_log.append(id)
	if unlocked:
		_start_track(id)


func _start_track(id: String) -> void:
	for p in music_players:
		music_gain[p][1] = 0.0          # everything that plays fades out
	if id == "":
		return
	var st := _music_stream(id)
	if st == null:
		return
	var p: AudioStreamPlayer = music_players[0]
	for q in music_players:            # the quieter player takes the new track
		if music_gain[q][0] < music_gain[p][0]:
			p = q
	p.stream = st
	music_gain[p] = [0.0, 1.0]
	p.volume_db = SILENT_DB
	p.play()


## The player of the current track (tests), or null.
func music_player() -> AudioStreamPlayer:
	for p in music_players:
		if music_gain[p][1] > 0.0:
			return p
	return null


func _process(delta: float) -> void:
	_clock += delta
	var c: Node = _alive(_combat)
	if c != null and c.is_inside_tree() and c.has_method("in_combat") and c.in_combat():
		_battle_hold = float(data.get("battle_hold_seconds", 2.0))
	else:
		_battle_hold = maxf(0.0, _battle_hold - delta)
	_set_track(wanted_track())
	var step := delta / maxf(0.01, float(data.get("crossfade_seconds", 1.0)))
	var mg := _gain("music")
	for p in music_players:
		var g: Array = music_gain[p]
		g[0] = move_toward(g[0], g[1], step)
		p.volume_db = _db(g[0] * mg)
		if g[0] <= 0.0 and g[1] <= 0.0 and p.playing:
			p.stop()
	_poll_title()
	_poll_dialogues()
	_poll_samples()
	if _poll_counters():
		_queue_flush()


# ------------------------------------------------------------------ web: the first input unlocks the sound
func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		unlock()


## Tests: back to a web page before its first input (nothing plays, the next key / click unlocks).
func lock() -> void:
	unlocked = false
	for p in music_players:
		p.stop()
		music_gain[p] = [0.0, 0.0]


func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	_start_track(track)


# ------------------------------------------------------------------ wiring
static func _alive(w: WeakRef) -> Node:
	if w == null:
		return null
	var n = w.get_ref()
	return n if n != null and is_instance_valid(n) else null


func _on_node_added(n: Node) -> void:
	var sc = n.get_script()
	if sc == null:
		return
	match (sc as Script).get_global_name():
		"Combat":
			_hook_combat(n)
		"Dialogue":
			_hook_dialogue(n)
		"Sample":
			_coins[n.get_instance_id()] = int(n.get("coins"))
			_samples.append(weakref(n))
			n.coins_changed.connect(_on_coins.bind(n.get_instance_id()))
		"PauseMenu", "QuestBoard", "SectBook":
			if n.has_signal("opened"):
				n.opened.connect(play.bind("panel_open"))
		"Guide":
			_counters.append([weakref(n), "payments", 0, "guide_complete"])
		"Bounty", "Commission":
			_counters.append([weakref(n), "paid", 0, "quest_complete"])
		"TitleScreen":
			_title = weakref(n)
			_title_sel = -1


func _hook_combat(c: Node) -> void:
	_combat = weakref(c)
	_battle_hold = 0.0
	if forced_on:                       # a new game: the music is the game's again (the opening film is over)
		forced_on = false
		forced = ""
	var simple := {"gp_success": ["gp_success", 1], "player_hurt": ["player_hurt", 2], "dodge_started": ["dodge", 1],
		"enemy_alert": ["telegraph", 1], "enemy_down": ["knockdown", 1], "player_down": ["knockdown", 0],
		"choice_moved": ["choice_move", 1]}
	for sig in simple:
		if c.has_signal(sig):
			var ev: String = simple[sig][0]
			var n_args: int = simple[sig][1]
			c.connect(sig, play.bind(ev).unbind(n_args) if n_args > 0 else play.bind(ev))
	if c.has_signal("player_hit_enemy"):
		c.connect("player_hit_enemy", func(_e, _dmg, heavy): play("hit_heavy" if heavy else "hit"))


func _hook_dialogue(d: Node) -> void:
	if d.has_signal("advanced"):
		d.connect("advanced", play.bind("dialogue_page"))
		if d.has_signal("choice_moved"):
			d.connect("choice_moved", play.bind("choice_move").unbind(1))
		if d.has_signal("choice_picked"):
			d.connect("choice_picked", play.bind("dialogue_page").unbind(1))
	else:
		# a dialogue box without those signals: a new page shown / the highlighted option moved
		_dialogues.append([weakref(d), -1, -1, false])


func _on_coins(coins: int, sid: int) -> void:
	var before := int(_coins.get(sid, coins))
	_coins[sid] = coins
	if coins > before:
		play("coin")


func _poll_counters() -> bool:
	var any := false
	var keep: Array = []
	for w in _counters:
		var n: Node = _alive(w[0])
		if n == null:
			continue
		keep.append(w)
		var v = n.get(w[1])
		var size: int = (v as Array).size() if v is Array else 0
		if size > int(w[2]):
			_pending.append(String(w[3]))
			any = true
		w[2] = size
	_counters = keep
	return any


func _poll_title() -> void:
	var t: Node = _alive(_title)
	if t == null or not t.is_node_ready():
		return
	var sel := int(t.get("selected"))
	if _title_sel >= 0 and sel != _title_sel:
		play("choice_move")
	_title_sel = sel


func _poll_dialogues() -> void:
	var keep: Array = []
	for w in _dialogues:
		var d: Node = _alive(w[0])
		if d == null:
			continue
		keep.append(w)
		var pages := int(d.get("pages_shown"))
		var on := bool(d.get("active"))
		var ci := int(d.get("choice_index")) if bool(d.get("choosing")) else -1
		if w[1] >= 0 and (pages > w[1] or (w[3] and not on)):
			play("dialogue_page")         # a new page / line, or the last one closed by the player
		elif w[2] >= 0 and ci >= 0 and ci != w[2]:
			play("choice_move")
		w[1] = pages
		w[2] = ci
		w[3] = on
	_dialogues = keep


## The coins at the start of each frame (this node runs first): a loaded save sets them without the signal.
func _poll_samples() -> void:
	var keep: Array = []
	for w in _samples:
		var n: Node = _alive(w)
		if n != null:
			keep.append(w)
			_coins[n.get_instance_id()] = int(n.get("coins"))
	_samples = keep
