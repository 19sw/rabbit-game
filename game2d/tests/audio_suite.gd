extends RefCounted
## 音效 + 背景音乐 v1 checks (docs/design/试玩反馈-格挡音效-方案-v1.md 第二节; task packet B), run by tests/run_tests.gd,
## or alone:  godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-audio
##   files     12 sound effects + 4 loops in assets/audio, every loop >= 40 s and looping over all its frames
##   data      data/audio.json: four volume levels 关 / 小 / 中 / 大, the event -> sound and scene -> track tables
##   music     title -> opening; game: day / night by the clock, battle in 切磋 / 山贼 / 比武 / 悬赏 / 试炼 (held 2 s),
##             Sfx.music / Sfx.auto, same track = nothing, 1 s cross-fade, a new game hands the music back
##   events    every combat signal (A's Combat signals) and UI event plays its sound; real keys where the game has them
##   volume    the four levels reach the players; 关 plays nothing
##   Esc page  音乐 / 音效 rows: real mouse clicks and ↑↓ ←→ keys; inside the page and the screen in Chinese and English
##   settings  user://settings.cfg [audio] (language kept), read back by a fresh service; never in the save
##   web       nothing before the first key / click, the music starts with it
##   headless  the Dummy audio driver plays without errors
## The player's own setting file is never touched (the suite points the service at user://test_audio_settings.cfg).

const SFX_IDS := ["gp", "hit", "hit_heavy", "hurt", "dodge", "telegraph", "ko", "page", "cursor", "coin", "complete", "panel"]
## 武学与经营 第一批 (A): three more sounds and their events (燕回旋 / 踏雪二段闪 / 学会吐纳功). The checks below count the
## twelve above AND these: "12" became "12 + 3 = 15" - every old sound and event is still checked one by one.
const SKILL_SFX := ["skill_spin", "skill_snow", "skill_tuna"]
const SKILL_EVENTS := {"skill_spin": "skill_spin", "skill_snow_step": "skill_snow", "skill_tuna_learned": "skill_tuna"}
const TRACKS := ["day", "night", "battle", "opening"]
## The plan's events (方案 第二节) -> the sound each must play.
const EVENTS := {"gp_success": "gp", "hit": "hit", "hit_heavy": "hit_heavy", "player_hurt": "hurt", "dodge": "dodge",
	"telegraph": "telegraph", "knockdown": "ko", "dialogue_page": "page", "choice_move": "cursor", "coin": "coin",
	"guide_complete": "complete", "quest_complete": "complete", "panel_open": "panel"}
## A's Combat signals (run message [A -> B] 战斗信号接口) -> [arguments, sound]
const COMBAT_SIGNALS := [
	["gp_success", "F", "gp"], ["player_hit_enemy", "F,8,false", "hit"], ["player_hit_enemy", "F,12,true", "hit_heavy"],
	["player_hurt", "F,5", "hurt"], ["dodge_started", "false", "dodge"], ["enemy_alert", "F", "telegraph"],
	["enemy_down", "F", "ko"], ["player_down", "", "ko"], ["choice_moved", "1", "cursor"]]
const TEST_SETTINGS := "user://test_audio_settings.cfg"

var r
var ss          # sample_suite: new_game / _title / _wait_game / finish_scene
var tt          # title_suite: click / button_screen_pos
var au: Node
var data: Dictionary
var min_scale := 1.0      # the smallest page scale _rows_fit saw


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	SaveGame.erase()
	r.root.size = Vector2i(1440, 810)        # the game's real view: 480x270
	au = r.root.get_node_or_null("AudioService")
	if not r.check(au != null and Sfx.service() == au, "audio: the AudioService autoload runs and Sfx reaches it"):
		return
	ss = load("res://tests/sample_suite.gd").new(r)
	tt = load("res://tests/title_suite.gd").new(r)
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	au.unlocked = true
	var keep_levels: Dictionary = au.levels.duplicate()
	var keep_lang := Lang.current()          # the English check run (GAME_LANG=en) runs this suite in English
	test_files()
	test_data()
	test_headless()
	await test_title_music()
	await test_game_music()
	await test_combat_events()
	await test_real_fight()
	await test_ui_events()
	await test_volume_levels()
	await test_esc_rows()
	await test_settings_outside_save()
	await test_web_gate()
	au.levels = keep_levels
	au.levels_changed.emit()
	Lang.set_lang(keep_lang)
	Sfx.auto()
	await ss._free_game()
	SaveGame.erase()


# ================================================================== helpers
func mark() -> int:
	return au.sfx_count


## Sound effects asked for since `m` ([{event, id, played}]).
func since(m: int) -> Array:
	var n: int = au.sfx_count - m
	return au.sfx_log.slice(maxi(0, au.sfx_log.size() - n))


func ids(entries: Array) -> Array:
	return entries.map(func(e): return String(e["id"]))


func settle(n := 3) -> void:
	await r.frames(n)


## Seconds of music time (physics frames at 60 per second).
func wait_s(s: float) -> void:
	await r.frames(int(round(s * 60.0)))


## A real mouse click on a control of a CanvasLayer page: its centre in the viewport, through the window stretch.
func click_ctl(c: Control) -> void:
	var vp_pos: Vector2 = c.get_global_transform_with_canvas() * (c.size * 0.5)
	await tt.click(r.root.get_final_transform() * vp_pos)


func playing_track() -> String:
	var p: AudioStreamPlayer = au.music_player()
	if p == null or not p.playing or p.stream == null:
		return ""
	return p.stream.resource_path.get_file().get_basename()


# ================================================================== files + data
func test_files() -> void:
	var bad := []
	for id in SFX_IDS + SKILL_SFX:
		var path := "res://assets/audio/sfx/%s.wav" % id
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if not (s is AudioStreamWAV) or s.get_length() < 0.03 or s.get_length() > 1.2:
			bad.append(id)
	var dir: Array = Array(DirAccess.get_files_at("res://assets/audio/sfx")).filter(func(f): return f.ends_with(".wav"))
	r.check(bad.is_empty() and dir.size() == SFX_IDS.size() + SKILL_SFX.size(), "audio files: 12 + 3 (武学) = 15 sound effects in assets/audio/sfx, each loads and lasts 0.03-1.2 s",
		"bad %s, %d files" % [bad, dir.size()])
	var loops := {}
	for id in TRACKS:
		var s: AudioStream = au._music_stream(id)
		var ok := s is AudioStreamWAV
		if ok:
			var w: AudioStreamWAV = s
			ok = w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_begin == 0 \
				and w.loop_end == int(round(w.get_length() * w.mix_rate)) and w.get_length() >= 40.0
			loops[id] = "%.1fs %d-%d" % [w.get_length(), w.loop_begin, w.loop_end]
		if not ok:
			bad.append(id)
	r.check(bad.is_empty(), "audio files: 4 music loops (day / night / battle / opening), each >= 40 s, looping over every frame",
		str(loops))
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	var man_ok: bool = man is Dictionary and (man["sfx"] as Dictionary).size() == SFX_IDS.size() + SKILL_SFX.size() \
		and (SFX_IDS + SKILL_SFX).all(func(i): return (man["sfx"] as Dictionary).has(i)) and (man["music"] as Dictionary).size() == 4
	r.check(man_ok, "audio files: the generator's manifest came along (12 + 3 sfx, each by name, + 4 music)")


func test_data() -> void:
	var lv: Array = data.get("volume_levels", [])
	var names: Array = lv.map(func(v): return String(v["name"]))
	var lin: Array = lv.map(func(v): return float(v["linear"]))
	var rising: bool = lin.size() == 4 and lin[0] == 0.0 and lin[1] > 0.0 and lin[1] < lin[2] and lin[2] < lin[3] and lin[3] <= 1.0
	r.check(names == ["关", "小", "中", "大"] and rising, "audio data: four volume levels 关 / 小 / 中 / 大, 关 = silent, rising",
		str(lin))
	var ev: Dictionary = data.get("events", {})
	var ev_ok := ev.size() == EVENTS.size() + SKILL_EVENTS.size()
	for k in EVENTS:
		ev_ok = ev_ok and String(ev.get(k, "")) == EVENTS[k]
	for k in SKILL_EVENTS:
		ev_ok = ev_ok and String(ev.get(k, "")) == SKILL_EVENTS[k]
	var used := {}
	for k in ev:
		used[String(ev[k])] = true
	r.check(ev_ok and used.size() == SFX_IDS.size() + SKILL_SFX.size(), "audio data: event -> sound table covers the plan's 13 events + the 3 武学 events and uses all 12 + 3 sounds",
		str(ev))
	var sc: Dictionary = data.get("scenes", {})
	r.check(sc.get("title") == "opening" and sc.get("opening") == "opening" and sc.get("day") == "day"
		and sc.get("night") == "night" and sc.get("battle") == "battle" and float(data.get("crossfade_seconds", 0)) == 1.0,
		"audio data: scene -> track table (title / opening -> opening, day, night, battle), 1 s cross-fade", str(sc))
	var dl: Dictionary = data.get("default_level", {})
	r.check(int(dl.get("music", -1)) == 2 and int(dl.get("sfx", -1)) == 2, "audio data: default volume 中 for both")


func test_headless() -> void:
	var m := mark()
	au.play("nonexistent_sound")
	var p: AudioStreamPlayer = au.voices[0]
	p.stream = load("res://assets/audio/sfx/coin.wav")
	p.play()
	r.check(AudioServer.get_driver_name() == "Dummy" and p.playing and au._sfx_stream("nonexistent_sound") == null,
		"audio headless: no sound device (Dummy driver) - players run, an unknown sound is skipped without an error",
		AudioServer.get_driver_name())
	p.stop()


# ================================================================== music
func test_title_music() -> void:
	var t: TitleScreen = await ss._title()
	await settle(4)
	r.check(au.track == "opening" and playing_track() == "opening", "audio music: the title screen plays the opening track",
		"%s / %s" % [au.track, playing_track()])
	var m := mark()
	await r.tap(KEY_DOWN)
	await settle()
	r.check("cursor" in ids(since(m)), "audio events: moving on the title menu (↓) plays the option sound", str(ids(since(m))))
	m = mark()
	t.activate(t.index_of("help"))
	await settle()
	r.check(t.help.is_open and "panel" in ids(since(m)), "audio events: the title's 按键与玩法 page opens with the panel sound")
	await r.tap(KEY_ESCAPE)
	await settle()
	# 新游戏: the game's music takes over (day at 08:00), one track fading into the other over 1 s
	var before: int = au.music_log.size()
	t.start_game("new")
	var g: Node = await ss._wait_game()
	await settle(2)
	var switched: bool = g != null and au.track == "day"
	var old: AudioStreamPlayer = null
	var new: AudioStreamPlayer = au.music_player()
	for p in au.music_players:
		if p != new:
			old = p
	await wait_s(0.45)
	var mid := [au.music_gain[new][0], au.music_gain[old][0], old.playing]
	await wait_s(0.75)
	var end := [au.music_gain[new][0], au.music_gain[old][0], old.playing]
	r.check(switched and au.music_log.slice(before) == ["day"], "audio music: 新游戏 -> the day track (08:00)", str(au.music_log.slice(before)))
	r.check(mid[0] > 0.3 and mid[0] < 0.8 and mid[1] > 0.2 and mid[1] < 0.7 and mid[2] and end[0] == 1.0 and end[1] == 0.0 and not end[2],
		"audio music: the change cross-fades over 1 s (half-way both play, after it only the new one)", "mid %s end %s" % [mid, end])


func test_game_music() -> void:
	await ss.new_game()
	var g: Node = ss.g
	var c: Combat = g.combat
	await settle()
	var seen := {}
	seen["08:00"] = au.track
	g.daynight.set_hour(20.0)
	await settle()
	seen["20:00"] = au.track
	g.daynight.set_hour(3.0)
	await settle()
	seen["03:00"] = au.track
	g.daynight.set_hour(7.0)
	await settle()
	seen["07:00"] = au.track
	r.check(seen == {"08:00": "day", "20:00": "night", "03:00": "night", "07:00": "day"},
		"audio music: day / night follow the game clock (night from 18:30 to 06:00)", str(seen))
	# 切磋: the real spar flow (师兄's invitation -> fight); the battle track stays 2 s after it is over
	c.start_spar()
	await settle()
	var spar: String = au.track
	c.end_spar(true)
	c._finish_spar()
	await wait_s(1.0)
	var held: String = au.track
	await wait_s(1.3)
	var back: String = au.track
	r.check(spar == "battle" and held == "battle" and back == "day",
		"audio music: 切磋 plays the battle track, held 2 s after the fight, then back to day", "%s %s %s" % [spar, held, back])
	# 山贼 / 悬赏 (an engaged enemy), 比武 (a bout session), 试炼 (the trial)
	var kinds := {}
	for k in ["bandit", "bout", "trial"]:
		if k == "bandit":
			c.bandits[0].engaged = true
		elif k == "bout":
			c.bout_session = true
		else:
			c.trial_active = true
		await settle()
		kinds[k] = au.track
		c.bandits[0].engaged = false
		c.bout_session = false
		c.trial_active = false
		await wait_s(2.3)
		kinds[k + "_after"] = au.track
	r.check(kinds["bandit"] == "battle" and kinds["bout"] == "battle" and kinds["trial"] == "battle"
		and kinds["bandit_after"] == "day" and kinds["bout_after"] == "day" and kinds["trial_after"] == "day",
		"audio music: 山贼 / 悬赏 (enemy engaged), 比武 (bout), 试炼 (trial) play the battle track", str(kinds))
	# forced track (the opening film) / same track again / silence / back to auto
	Sfx.music("opening")
	await settle()
	var forced: bool = au.track == "opening" and playing_track() == "opening"
	var p: AudioStreamPlayer = au.music_player()
	var n: int = au.music_log.size()
	await wait_s(0.5)
	var pos := p.get_playback_position()
	Sfx.music("opening")
	await settle()
	var same: bool = au.music_log.size() == n and au.music_player() == p and p.get_playback_position() >= pos
	Sfx.music("")
	await wait_s(1.2)
	var silent: bool = au.track == "" and au.music_players.all(func(x): return not x.playing)
	Sfx.auto()
	await settle()
	r.check(forced and same and silent and au.track == "day",
		"audio music: Sfx.music forces a track, the same track again changes nothing, \"\" fades to silence, Sfx.auto hands back",
		"%s %s %s %s" % [forced, same, silent, au.track])
	Sfx.music("opening")
	await ss.new_game()
	await settle()
	r.check(au.track == "day" and not au.forced_on, "audio music: a new game (after the opening film) hands the music back to the game")


# ================================================================== events
func _arg(spec: String, f: Node) -> Array:
	var out := []
	for a in spec.split(",", false):
		if a == "F":
			out.append(f)
		elif a == "true" or a == "false":
			out.append(a == "true")
		else:
			out.append(int(a))
	return out


func test_combat_events() -> void:
	await ss.new_game()
	var c: Combat = ss.g.combat
	var f: Node = c.spar_fighter
	for s in COMBAT_SIGNALS:
		var sig: String = s[0]
		if not c.has_signal(sig):
			r.check(false, "audio events: Combat.%s plays %s.wav" % [sig, s[2]], "Combat has no signal '%s' (A's interface)" % sig)
			continue
		await r.frames(4)                   # past the same-sound minimum gap
		var m := mark()
		c.callv("emit_signal", [sig] + _arg(s[1], f))
		await settle()
		var got := ids(since(m))
		r.check(got == [s[2]], "audio events: Combat.%s(%s) plays %s.wav" % [sig, s[1], s[2]], str(got))
	# the dialogue box's own signals (A) or, without them, its page counter / highlighted option
	var dlg: Dialogue = ss.dlg
	await ss.finish_scene()
	var m := mark()
	dlg.say({"who": "fox", "text": "测试"}, ["是", "否"])
	await r.frames(30)
	if not dlg.choosing:
		await r.tap(KEY_E)
		await r.frames(4)
	var m2 := mark()
	await r.tap(KEY_DOWN)
	await settle()
	var moved := ids(since(m2))
	await r.tap(KEY_E)
	await settle()
	r.check("cursor" in moved and "page" in ids(since(m)),
		"audio events: a dialogue line plays the page sound, ↓ on its options the option sound", "%s / %s" % [moved, ids(since(m))])


## The real fight (A's combat code emitting its own signals): 师兄's wind-up "!" rings, Space dodges with a swoosh, J hits.
func test_real_fight() -> void:
	await ss.new_game()
	var g: Node = ss.g
	g.story.enter_sandbox()
	await r.frames(4)
	var c: Combat = g.combat
	c.start_spar()
	var m := mark()
	var got := {}
	for i in 900:                                   # up to 15 s: wait for his wind-up, then dodge and swing
		await r.process_frame
		var now := ids(since(m))
		if "telegraph" in now and not got.has("dodge_tried"):
			got["dodge_tried"] = true
			await r.tap(KEY_SPACE)
		# swing until one lands (he side-steps at random, so a single swing can miss); at most 6 swings
		var landed := "hit" in now or "hit_heavy" in now
		if got.has("dodge_tried") and not landed and int(got.get("j", 0)) < 6:
			var p: Player = g.player
			if p.global_position.distance_to(c.spar_fighter.global_position) < 40.0:
				got["j"] = int(got.get("j", 0)) + 1
				await r.tap(KEY_J)
				await r.frames(20)
		var all := ids(since(m))
		if "telegraph" in all and "dodge" in all and ("hit" in all or "hit_heavy" in all):
			break
	var seen := ids(since(m))
	if c.spar_state == "fighting":
		c.end_spar(true)
		c._finish_spar()
	r.check("telegraph" in seen and "dodge" in seen, "audio events (real fight): 师兄's wind-up rings the 叮, Space dodges with the swoosh",
		str(seen))
	r.check("hit" in seen or "hit_heavy" in seen or not got.has("j"), "audio events (real fight): J landing on 师兄 plays a hit sound", str(seen))


func test_ui_events() -> void:
	await ss.new_game()
	var g: Node = ss.g
	# the opening conversation of a new game: E turns the page
	for i in 400:
		if ss.dlg.active and ss.dlg._guard <= 0.0:
			break
		await r.process_frame
	var was_active: bool = ss.dlg.active
	var m := mark()
	await r.tap(KEY_E)
	await r.frames(4)
	await r.tap(KEY_E)
	for i in 90:
		if "page" in ids(since(m)):
			break
		await r.process_frame
	r.check(was_active and "page" in ids(since(m)), "audio events: E in a conversation plays the page sound (real key)",
		"%s %s" % [was_active, ids(since(m))])
	await ss.finish_scene()
	# coins: a gain rings, a payment does not
	m = mark()
	ss.smp.add_coins(5)
	await settle()
	var gain := ids(since(m))
	m = mark()
	ss.smp.add_coins(-3)
	await settle()
	r.check(gain == ["coin"] and ids(since(m)).is_empty(), "audio events: coins gained play the coin sound, coins paid do not",
		"%s / %s" % [gain, ids(since(m))])
	# a guide step paid (its coins come with it: one 完成 sound, not two)
	m = mark()
	g.guide._pay(0)
	await settle()
	var gs := ids(since(m))
	r.check(gs == ["complete"], "audio events: a guide step done plays the complete sound (its coins do not ring on top)", str(gs))
	# a 委托 / 悬赏 turned in
	m = mark()
	g.jianghu.com.paid.append({"kind": "test", "coins": 10, "estate": 0})
	g.sample.add_coins(10)
	await settle()
	var cs := ids(since(m))
	m = mark()
	g.jianghu.bounty.paid.append({"coins": 10, "fame": 0, "type": "test"})
	await settle()
	r.check(cs == ["complete"] and ids(since(m)) == ["complete"], "audio events: a 委托 / 悬赏 turned in plays the complete sound",
		"%s / %s" % [cs, ids(since(m))])
	# panels: the Esc page (real key), the 任务面板, the 门派簿
	await r.frames(4)
	m = mark()
	await r.tap(KEY_ESCAPE)
	await settle()
	var esc := ids(since(m))
	await r.tap(KEY_ESCAPE)
	await r.frames(4)
	m = mark()
	g.quest_board.open()
	await settle()
	var qb := ids(since(m))
	g.quest_board.close()
	await r.frames(4)
	m = mark()
	g.story.sect_book.open(g.story.flags)
	await settle()
	var book := ids(since(m))
	g.story.sect_book.close()
	await settle()
	r.check(esc == ["panel"] and qb == ["panel"] and book == ["panel"],
		"audio events: opening the Esc page (Esc), the 任务面板 and the 门派簿 plays the panel sound", "%s %s %s" % [esc, qb, book])


# ================================================================== volume
func test_volume_levels() -> void:
	await ss.new_game()
	await wait_s(1.2)
	var res := []
	var ok := true
	for lv in 4:
		au.set_level("music", lv)
		au.set_level("sfx", lv)
		await settle()
		var want_m: float = au._db(float(data["volume_levels"][lv]["linear"]) * float(data.get("music_trim", 1.0)))
		var p: AudioStreamPlayer = au.music_player()
		var m := mark()
		await r.frames(4)
		au.play("coin")
		await settle()
		var got := since(m)
		var e: Dictionary = got[0] if not got.is_empty() else {"played": false}
		var want_s: float = au._db(float(data["volume_levels"][lv]["linear"]) * float(data.get("sfx_trim", 1.0)))
		var voice: AudioStreamPlayer = au.voices[posmod(au._next_voice - 1, au.voices.size())]
		var good: bool = absf(p.volume_db - want_m) < 0.05 and bool(e["played"]) == (lv > 0) \
			and (lv == 0 or absf(voice.volume_db - want_s) < 0.05)
		ok = ok and good
		res.append("%d: music %.1f dB, sfx %s" % [lv, p.volume_db, "%.1f dB" % voice.volume_db if e["played"] else "off"])
	au.set_level("music", 2)
	au.set_level("sfx", 2)
	r.check(ok, "audio volume: the four levels set the music and sound volume from data/audio.json; 关 plays nothing", str(res))


## "" when the two volume buttons sit inside the page and the page stays inside the screen, unscaled, on every tips page -
## also in the widest case (both at 大 and the 放弃 button of a trial / tournament in the same bottom row). Each page is
## measured after its layout settled (laid out again once the wrapped tips know their width).
func _rows_fit(pm: PauseMenu) -> String:
	var vp: Vector2 = pm.get_viewport().get_visible_rect().size
	var out := ""
	var keep := [Sfx.volume("music"), Sfx.volume("sfx")]
	min_scale = 1.0
	for worst in [false, true]:
		if worst:
			au.set_level("music", 3)
			au.set_level("sfx", 3)
			if not pm.help_only:
				pm.set_abandon_action("放弃试炼", func(): pass)
		for pg in pm.tip_pages.size():
			pm.show_page(pg)
			await r.process_frame
			await r.process_frame
			pm._layout()
			await r.process_frame
			await r.process_frame
			var k: float = pm.panel.scale.x
			min_scale = minf(min_scale, k)
			var rect := Rect2(pm.panel.global_position, pm.panel.size * k)
			if not Rect2(Vector2.ZERO, vp).grow(0.01).encloses(rect) or k < 0.999:
				out += "%spage %d %s scale %.3f in %s; " % ["widest " if worst else "", pg + 1, rect, k, vp]
			for kind in pm.sound_buttons:
				var c: Control = pm.sound_buttons[kind]
				var cr := Rect2(c.get_global_transform().origin, c.size * c.get_global_transform().get_scale())
				if not rect.grow(0.5).encloses(cr) or c.size.x + 0.5 < c.get_combined_minimum_size().x:
					out += "%s '%s' %s; " % [kind, c.get("text"), cr]
	pm.set_abandon_action("", Callable())
	au.set_level("music", keep[0])
	au.set_level("sfx", keep[1])
	pm.show_page(0)
	await r.process_frame
	await r.process_frame
	return out


func test_esc_rows() -> void:
	await ss.new_game()
	var g: Node = ss.g
	var pm: PauseMenu = g.pause_menu
	if pm.get("sound_buttons") == null:
		r.check(false, "audio Esc page: 音乐 / 音效 volume controls on the Esc page", "PauseMenu has no volume controls")
		return
	await ss.finish_scene()
	await r.tap(KEY_ESCAPE)
	await settle()
	var texts: Array = [pm.sound_buttons["music"].text, pm.sound_buttons["sfx"].text]
	var foot: Node = pm.resume_button.get_parent()
	var same_row: bool = foot.is_ancestor_of(pm.sound_buttons["music"]) and foot.is_ancestor_of(pm.sound_buttons["sfx"])
	var want := ["Music: Mid", "SFX: Mid"] if Lang.is_en() else ["音乐：中", "音效：中"]
	r.check(pm.is_open and texts == want and same_row,
		"audio Esc page: 「音乐：中」「音效：中」 in the bottom row with 继续 and the language", str(texts))
	var fit_zh: String = await _rows_fit(pm)
	# real mouse clicks: each click moves the level on (中 -> 大 -> 关 -> 小 ...)
	var seen := []
	await click_ctl(pm.sound_buttons["music"])
	seen.append(pm.sound_buttons["music"].text)
	for i in 3:
		await click_ctl(pm.sound_buttons["sfx"])
		seen.append(pm.sound_buttons["sfx"].text)
	await settle()
	var want_seen := ["Music: High", "SFX: High", "SFX: Off", "SFX: Low"] if Lang.is_en() else ["音乐：大", "音效：大", "音效：关", "音效：小"]
	r.check(seen == want_seen and Sfx.volume("music") == 3 and Sfx.volume("sfx") == 1 and pm.is_open,
		"audio Esc page: clicking a volume button steps through 关 / 小 / 中 / 大 (real mouse clicks)", str(seen))
	# keys: Tab picks 音乐, ← lowers it; Tab picks 音效, → raises it; Tab again = none, → turns the tips page as before
	var steps := []
	await r.tap(KEY_TAB)
	steps.append(pm.sound_focus)
	await r.tap(KEY_LEFT)
	steps.append(Sfx.volume("music"))
	await r.tap(KEY_TAB)
	steps.append(pm.sound_focus)
	await r.tap(KEY_RIGHT)
	steps.append(Sfx.volume("sfx"))
	await r.tap(KEY_RIGHT)
	await r.tap(KEY_RIGHT)
	steps.append(Sfx.volume("sfx"))
	var lit := func(k: String) -> bool:
		return ((pm.sound_buttons[k] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(Color(1.0, 0.88, 0.5))
	var mark_on: bool = lit.call("sfx") and not lit.call("music") and pm.page_label.text == PauseMenu.SOUND_HINT
	await r.tap(KEY_TAB)
	steps.append(pm.sound_focus)
	var page0: int = pm.page
	await r.tap(KEY_RIGHT)
	steps.append(pm.page - page0)
	var lang0 := Lang.current()
	await r.tap(KEY_DOWN)
	var lang_key: bool = Lang.current() != lang0
	await r.tap(KEY_DOWN)
	r.check(steps == [0, 2, 1, 2, 3, -1, 1] and mark_on and lang_key and Lang.current() == lang0 and pm.is_open,
		"audio Esc page: Tab picks 音乐 / 音效 (lit, hint shown), ←→ changes it (stops at 大); with none picked → still turns the page and ↑↓ still switch the language",
		"%s lit %s lang %s" % [steps, mark_on, lang_key])
	await r.tap(KEY_ESCAPE)
	await settle()
	# English
	Lang.set_lang("en")
	await settle()
	await r.tap(KEY_ESCAPE)
	await settle()
	var en_texts: Array = [pm.sound_buttons["music"].text, pm.sound_buttons["sfx"].text]
	var fit_en: String = await _rows_fit(pm)
	await r.tap(KEY_ESCAPE)
	Lang.set_lang(lang0)
	await settle()
	r.check(fit_zh == "" and fit_en == "" and en_texts == ["Music: Mid", "SFX: High"],
		"audio Esc page: the volume buttons sit inside the page and every tips page stays unscaled inside 480x270 - also with both at 大 and the 放弃 button - Chinese and English",
		"zh: %s en: %s %s" % [fit_zh, fit_en, en_texts])
	# the title screen's 按键与玩法 page (same page in help mode) has them too
	var t: TitleScreen = await ss._title()
	t.help.open()
	await settle()
	var help_fit: String = await _rows_fit(t.help)
	var before := Sfx.volume("music")
	await click_ctl(t.help.sound_buttons["music"])
	var help_click: bool = Sfx.volume("music") == (before + 1) % 4
	t.help.close()
	await settle()
	r.check(help_fit == "" and help_click, "audio Esc page: the title's 按键与玩法 page has the same buttons (fits, clickable)", help_fit)
	au.set_level("music", 2)
	au.set_level("sfx", 2)


# ================================================================== settings, not the save
func test_settings_outside_save() -> void:
	await ss.new_game()
	var g: Node = ss.g
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var cf := ConfigFile.new()
	cf.set_value("game", "lang", "en")
	cf.save(TEST_SETTINGS)
	au.settings_path = TEST_SETTINGS
	au.persist = true
	var writes: int = SaveGame.writes
	var snap_before := JSON.stringify(SaveGame.capture(g))
	au.set_level("music", 1)
	au.set_level("sfx", 3)
	await settle()
	var writes_after: int = SaveGame.writes
	var snap_after := JSON.stringify(SaveGame.capture(g))
	var cf2 := ConfigFile.new()
	var loaded := cf2.load(TEST_SETTINGS) == OK
	var stored: bool = loaded and int(cf2.get_value("audio", "music", -1)) == 1 and int(cf2.get_value("audio", "sfx", -1)) == 3
	var lang_kept: bool = loaded and String(cf2.get_value("game", "lang", "")) == "en"
	var fresh: Node = load("res://scripts/audio_service.gd").new()
	fresh.reload_data()
	fresh.settings_path = TEST_SETTINGS
	fresh.persist = true
	fresh._load_settings()
	var read_back: bool = fresh.levels == {"music": 1, "sfx": 3}
	fresh.free()
	r.check(stored and lang_kept and read_back, "audio settings: saved in the settings file [audio] (the language line kept) and read back at start",
		"stored %s lang %s read %s" % [stored, lang_kept, read_back])
	g.sample.save_now("test")
	var save_txt := FileAccess.get_file_as_string(SaveGame.path())
	var in_save := "audio" in save_txt or "\"music\"" in save_txt or "\"sfx\"" in save_txt or "volume" in save_txt
	r.check(writes_after == writes and snap_before == snap_after and not in_save and save_txt != "",
		"audio settings: changing the volume writes no save and the save holds no volume (separate from the game)",
		"writes %d->%d, capture same %s, in save %s" % [writes, writes_after, snap_before == snap_after, in_save])
	au.persist = false
	au.settings_path = au.SETTINGS
	au.set_level("music", 2)
	au.set_level("sfx", 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	SaveGame.erase()


# ================================================================== web: silent until the first input
func test_web_gate() -> void:
	await ss.new_game()
	await settle()
	au.lock()                                   # a web page that nobody has clicked yet
	var m := mark()
	Sfx.play("coin")
	Sfx.music("battle")
	await wait_s(0.5)
	var first := since(m)
	var silent: bool = not au.music_players.any(func(p): return p.playing) and first.size() == 1 and not bool(first[0]["played"]) \
		and au.track == "battle"
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(200, 200)
	Input.parse_input_event(mv)
	await settle()
	var still: bool = not au.unlocked
	await r.tap(KEY_F9)                         # any key (F9 does nothing in the game)
	await settle()
	var started: bool = au.unlocked and playing_track() == "battle"
	await r.frames(4)
	m = mark()
	Sfx.play("coin")
	await settle()
	var after := since(m)
	r.check(silent and still and started and after.size() == 1 and bool(after[0]["played"]),
		"audio web: nothing plays before the first key / click (a mouse move is not enough); the music asked for starts with it",
		"silent %s still %s started %s" % [silent, still, started])
	Sfx.auto()
	await settle()
