extends RefCounted
## 改名与起名 v1 checks (docs/design/游戏改名与主角起名-方案-v1.md, section 五 测试), run by tests/run_tests.gd, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-naming
## Real key events throughout: the name is typed into the LineEdit as key events carrying the character (what the
## browser's input method hands over when a 拼音 word is committed).
##   title     《山门小院》: the pixel logo (the new generator's picture, its text = data/title.json), the English line
##             The Mountain Courtyard, window / project / loading-page names; no DEMO / 动物武侠 / Animal Wuxia shown
##   new game  新游戏 -> the naming box (filled with 小兔, all selected) before the opening; type 阿糯 -> Enter -> the
##             opening -> the prologue: the speaker plate, narration, NPC lines, 门派簿 all say 阿糯; 徒儿 / 兔儿 / 师兄
##             and every NPC name unchanged; Enter on the untouched box = 小兔; Esc goes back to the menu
##   checks    empty / all spaces refused; a 6th 字 cannot be typed; a character missing from the font -> 「这个字显示不了，
##             换一个吧」, 确定 refused; typed E / Q / B / T / Space / arrows are letters, never game keys
##   saves     the name saves and loads (继续游戏); an older save (no name) loads as 小兔; a broken one is refused
##   Esc 改名  R / the button on the paused Esc page -> rename at once (free), a line on screen updates, Esc cancels
##   English   Momo: every line that said Little Rabbit says Momo; 12 letters; default = Little Rabbit
##   font      the 3755 GB2312 level-1 hanzi are in the UI font

var r
var tt                      # title_suite helpers (new title, click, wait for the game)
var title: TitleScreen
var was_naming := true
var was_opening := false
var cjk := RegEx.create_from_string("[\\x{3400}-\\x{9fff}]")

## Every data line that names the hero (the token {name}): [file, scene, index]
const NAME_LINES := [
	["story", "S1-擦水渍", 4], ["story", "S4-厨娘-任务前", 0], ["story", "S8-找到瓦片", 2], ["story", "S9-师父-收尾", 6],
	["story", "S9-师父-收尾", 9], ["story", "S9-师父-收尾", 19], ["sample", "X-老周-修屋顶", 0],
	["sample", "X-厨娘-修厨房", 0], ["step3", "D-老伯-有人拜师", 0], ["jianghu", "J-馒头-送", 0],
	["jianghu", "J-村民-名望", 1],
]


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	r.root.size = Vector2i(1440, 810)
	was_naming = NamingPanel.enabled
	was_opening = Opening.enabled
	NamingPanel.enabled = true
	Lang.set_lang("zh")
	SaveGame.erase()
	PlayerName.reset()
	tt = load("res://tests/title_suite.gd").new(r)
	test_static_title()
	test_data_tokens()
	test_font()
	await test_title_screen("zh")
	await test_title_screen("en")
	Lang.set_lang("zh")
	await test_new_game_named()
	await test_default_enter()
	await test_checks_and_keys()
	await test_save_load()
	await test_old_save()
	await test_esc_rename()
	await test_english_momo()
	Lang.set_lang("zh")
	await _free_title()
	SaveGame.erase()
	PlayerName.reset()
	NamingPanel.enabled = was_naming
	Opening.enabled = was_opening


# ------------------------------------------------------------------ helpers
func _free_title() -> void:
	if title != null and is_instance_valid(title):
		if title.is_inside_tree():
			title.get_parent().remove_child(title)
		title.queue_free()
	title = null
	await r.process_frame


func new_title() -> void:
	# (no game of an earlier check may stay in the tree: its dialogue / Esc page would take the keys)
	for n in r.root.get_children():
		if n.get_script() == load("res://scripts/main.gd") or n.name == "TitleFadeIn" or n is TitleScreen:
			n.get_parent().remove_child(n)
			n.queue_free()
	await _free_title()
	tt.title = null
	await tt.new_title()
	title = tt.title


func free_game(m: Node) -> void:
	await tt.free_game(m)


## A key event that types `ch` (what a keyboard / an input method delivers to the LineEdit).
func type_char(ch: String) -> void:
	var ev := InputEventKey.new()
	var up := ch.to_upper()
	var code := OS.find_keycode_from_string(up) if ch.length() == 1 and ch.unicode_at(0) < 0x80 and ch != " " else KEY_NONE
	if ch == " ":
		code = KEY_SPACE
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	Input.parse_input_event(ev)
	await r.frames(1)
	var up_ev := ev.duplicate()
	up_ev.pressed = false
	up_ev.unicode = 0
	Input.parse_input_event(up_ev)
	await r.frames(1)


func type_text(t: String) -> void:
	for ch in t:
		await type_char(ch)


## Clears the box (select all + Backspace, both real keys: Backspace is a key event; select-all through the LineEdit).
func clear_box(p: NamingPanel) -> void:
	p.line.select_all()
	await r.tap(KEY_BACKSPACE)


func wait_naming(limit := 120) -> NamingPanel:
	for i in limit:
		await r.process_frame
		if title != null and is_instance_valid(title) and title.naming != null and title.naming.is_open:
			return title.naming
	return null


func _opening() -> Opening:
	return _find(r.root, func(n): return n is Opening and n.state != "done")


func _find(n: Node, pred: Callable) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var f := _find(c, pred)
		if f != null:
			return f
	return null


## Window position of the centre of a control on a CanvasLayer (its canvas transform, then the window stretch).
func at(c: Control) -> Vector2:
	return c.get_viewport().get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))


## Waits (pressing E only when a line is fully shown) until the hero speaks; returns his plate ("" = never).
func wait_hero_line(dlg: Dialogue, limit := 1500) -> String:
	for i in limit:
		if dlg.active and dlg.kind == "speaker" and String(dlg.entry.get("who", "")) == "rabbit":
			return dlg.name_label.text
		if dlg.active and not dlg.is_typing() and i % 8 == 0:
			await r.tap(KEY_E)
		else:
			await r.process_frame
	return ""


## E through the opening until the game is there.
func through_opening() -> Node:
	for i in 60:
		if _opening() == null and r.current_scene != null and r.current_scene.name == "Main":
			break
		await r.tap(KEY_E)
	return await tt.wait_for_game(200)


## Shows `entries` one after another through the game's own dialogue box (Dialogue.say, the path every scene line
## takes); returns [[speaker plate, line as on screen (Lang.t)], ...].
func show_lines(dlg: Dialogue, entries: Array) -> Array:
	var out := []
	for e in entries:
		if not (e is Dictionary) or not e.has("text"):
			continue
		dlg.say(e)
		await r.frames(2)
		out.append([dlg.name_label.atr(dlg.name_label.text), dlg.screen_text, dlg.full_text])
		dlg.close()
		dlg.line_done.emit()
		await r.frames(1)
	return out


func data_of(f: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % f))


func name_entries() -> Array:
	var out := []
	for x in NAME_LINES:
		out.append(data_of(x[0])["scenes"][x[1]][x[2]])
	return out


## Every Label / Button text on screen under `n` (as shown: translated), for the "no DEMO" check.
func shown_texts(n: Node, out: Array) -> Array:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return out
	if n is Label or n is Button:
		out.append(n.atr(n.text) if n.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else n.text)
	for c in n.get_children():
		shown_texts(c, out)
	return out


# ------------------------------------------------------------------ title
func test_static_title() -> void:
	var td: Dictionary = data_of("title")
	var stamp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/title/title_logo.json"))
	var gen_png := ProjectSettings.globalize_path("res://").path_join("../pixel2d/title/logo/output/title_logo.png").simplify_path()
	var same := FileAccess.get_file_as_bytes(gen_png) == FileAccess.get_file_as_bytes("res://assets/title/title_logo.png")
	var old_kept := FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("../pixel2d/title/logo/old/title_logo_v1.png").simplify_path())
	r.check(td["title"] == "山门小院" and stamp["text"] == "山门小院" and same and old_kept,
		"naming 一: data/title.json is 山门小院; the game's logo is the new generator's picture (pixel2d/title/logo/output, its text 山门小院); the old logo kept in logo/old",
		str([td["title"], stamp["text"], same, old_kept]))
	var proj := String(ProjectSettings.get_setting("application/config/name"))
	var shell := FileAccess.get_file_as_string("res://web/shell.html")
	var en: String = Lang.translation().translate_text("山门小院")
	var bad := []
	for pair in [["project.godot", FileAccess.get_file_as_string("res://project.godot")], ["web/shell.html", shell],
			["data/title.json", FileAccess.get_file_as_string("res://data/title.json")]]:
		for w in ["DEMO", "Demo", "动物武侠", "Animal Wuxia"]:
			if w in String(pair[1]):
				bad.append("%s: %s" % [pair[0], w])
	r.check(proj == "山门小院" and "<title>山门小院</title>" in shell and "\"title\": \"The Mountain Courtyard\"" in shell
		and en == "The Mountain Courtyard" and bad.is_empty(),
		"naming 一: window / tab title 山门小院 (project name, the loading page; English: The Mountain Courtyard); no DEMO / 动物武侠 / Animal Wuxia in them",
		str([proj, en, bad]))


func test_title_screen(lang: String) -> void:
	Lang.set_lang(lang)
	await new_title()
	await r.frames(3)
	var texts := shown_texts(title, [])
	var bad := texts.filter(func(t): return "DEMO" in String(t) or "动物武侠" in String(t) or "Animal Wuxia" in String(t))
	var logo_ok := title.logo != null and title.logo_label == null and title.logo.visible
	var en_line := title.logo_en.visible and title.logo_en.text == "The Mountain Courtyard"
	var ok := logo_ok and bad.is_empty() and (en_line if lang == "en" else not title.logo_en.visible)
	r.check(ok, "naming 一 (%s): the title screen shows the pixel logo 山门小院%s; nothing on it says DEMO / 动物武侠 / Animal Wuxia" % [lang,
		" and the English line 'The Mountain Courtyard' under it" if lang == "en" else ""], str([logo_ok, title.logo_en.text, bad]))


func test_data_tokens() -> void:
	# every name line has the token; no data text calls the hero 小兔 any more except the two 小兔子 (species) lines
	var with_token := 0
	for e in name_entries():
		if PlayerName.TOKEN in String(e["text"]):
			with_token += 1
	var left := []
	for f in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and f != "naming.json":
			var raw := FileAccess.get_file_as_string("res://data/" + f)
			var doc = JSON.parse_string(raw)
			_collect_xiaotu(doc, f, left)
	var story: Dictionary = data_of("story")
	var plate: String = story["speakers"]["rabbit"]["name"]
	r.check(with_token == NAME_LINES.size() and left == ["opening.json: 还有一只小兔子。", "story.json: 站住！哪来的小兔子？"] and plate == "{name}",
		"naming 二: the %d lines that name the hero and 小兔's speaker plate use {name}; the only 小兔 left are the two 小兔子 (a little rabbit, not his name)" % NAME_LINES.size(),
		str([with_token, left, plate]))
	# 徒儿 / 兔儿 / 师兄 untouched by the name, NPC names untouched
	PlayerName.choose("阿糯")
	var lost := []
	var n_titles := 0
	for f in ["story", "sample", "step3", "jianghu", "skills", "farm"]:
		var d: Dictionary = data_of(f)
		for sc in d.get("scenes", {}):
			for e in _entries(d["scenes"][sc]):
				var t := String(e["text"])
				var filled := PlayerName.fill(t)
				for w in ["徒儿", "兔儿", "师兄"]:
					if w in t:
						n_titles += 1
						if t.count(w) != filled.count(w):
							lost.append(t)
				if PlayerName.TOKEN in filled or ("{name}" in t and not "阿糯" in filled):
					lost.append(t)
	var sp: Dictionary = story["speakers"]
	var npc_names := []
	for id in sp:
		if id != "rabbit":
			npc_names.append(String(sp[id]["name"]))
	var npc_ok := not npc_names.any(func(n): return "{" in n or "阿糯" in n)
	PlayerName.reset()
	r.check(lost.is_empty() and n_titles >= 10 and npc_ok,
		"naming 二: with the name 阿糯 every 徒儿 / 兔儿 / 师兄 in the lines stays (%d lines), every {name} is filled, the NPC names stay" % n_titles,
		str(lost.slice(0, 5)))


func _entries(v: Variant) -> Array:
	var out := []
	if v is Dictionary:
		if v.has("text") and v["text"] is String:
			out.append(v)
		for k in v:
			if k != "text":
				out.append_array(_entries(v[k]))
	elif v is Array:
		for x in v:
			out.append_array(_entries(x))
	return out


func _collect_xiaotu(v: Variant, f: String, out: Array, key := "") -> void:
	if v is Dictionary:
		for k in v:
			if not String(k).begins_with("_"):
				_collect_xiaotu(v[k], f, out, String(k))
	elif v is Array:
		for x in v:
			_collect_xiaotu(x, f, out, key)
	elif v is String and "小兔" in v:
		out.append("%s: %s" % [f, v])


func test_font() -> void:
	var f: Font = load("res://fonts/ui_font.fnt")
	var chars := FileAccess.get_file_as_string("res://fonts/ui_font.chars.txt")
	var hanzi := 0
	var missing := ""
	for ch in chars:
		var c := ch.unicode_at(0)
		if c >= 0x4E00 and c <= 0x9FFF:
			hanzi += 1
		if c > 32 and not f.has_char(c):
			missing += ch
	# first / last GB2312 level-1 characters, a few name characters; 亍 (level 2, D8A1) and 龘 are not in it
	var spot := "啊座糯豆满楼耳团云月".split("")
	var spot_ok := Array(spot).all(func(ch): return f.has_char(ch.unicode_at(0)))
	var out_ok := not f.has_char("亍".unicode_at(0)) and not f.has_char("龘".unicode_at(0))
	r.check(hanzi >= 3755 and missing == "" and spot_ok and out_ok,
		"naming 三: the UI font has the 3755 common hanzi (GB2312 level 1; %d hanzi in all), every listed character drawable; 亍 / 龘 (rare) are not" % hanzi,
		str([hanzi, missing.substr(0, 20), spot_ok, out_ok]))
	var bad := []
	for lang in ["zh", "en"]:
		Lang.set_lang(lang)
		for n in PlayerName.random_names() + [PlayerName.DEFAULT]:
			var s := PlayerName.shown(String(n))
			if not PlayerName.validate(s)["ok"]:
				bad.append(lang + ":" + s)
	Lang.set_lang("zh")
	r.check(bad.is_empty() and PlayerName.random_names().size() >= 6,
		"naming 二: every random name (阿糯、白小楼、月白、团子、云白、长耳 …) and 小兔 pass the checks in Chinese and in English (Little Rabbit = 12 letters)", str(bad))


# ------------------------------------------------------------------ new game
func test_new_game_named() -> void:
	SaveGame.erase()
	Opening.enabled = true
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var p := await wait_naming()
	var open_ok := p != null and p.mode == "new" and p.line.text == "小兔" and p.line.has_focus() and p.line.is_editing() \
		and p.line.get_selected_text() == "小兔" and _opening() == null and not title.starting
	r.check(open_ok, "naming 二: 新游戏 opens the naming box first (「给这只小兔起个名字吧」, filled with 小兔 and selected, keyboard in the box) - no opening yet",
		str([p != null, p.line.text if p else "", p.title_label.text if p else ""]))
	if p == null:
		return
	r.check(p.title_label.text == "给这只小兔起个名字吧" and p.confirm_button.visible and p.random_button.visible
		and not p.cancel_button.visible and p.limit_label.text == "最多 5 个汉字或 12 个字母",
		"naming 二: the box has 确定 / 随机 and 「最多 5 个汉字或 12 个字母」 (the plan's layout; R1: the rule names both)", str([p.title_label.text, p.limit_label.text]))
	# 随机 picks from the list
	var picks := {}
	for i in 6:
		await tt.click(at(p.random_button))
		picks[p.line.text] = true
	var all_listed := picks.keys().all(func(n): return n in PlayerName.random_names())
	r.check(picks.size() >= 3 and all_listed and p.is_open, "naming 二: 随机 (mouse) fills the box with names from data/naming.json, a different one each time",
		str(picks.keys()))
	# typing replaces the selection: 阿糯 as the input method would commit it
	p.line.select_all()
	await type_text("阿糯")
	var typed := p.line.text
	await r.tap(KEY_ENTER)
	await r.frames(2)
	r.check(typed == "阿糯" and not p.is_open and PlayerName.value() == "阿糯" and title.starting,
		"naming 二: typing 阿糯 + Enter takes the name and the game starts", str([typed, PlayerName.value()]))
	var o := await _wait_opening()
	r.check(o != null and o.mode == "new", "naming 二: then the opening plays (after the name, before the game)")
	var main: Node = await through_opening()
	if main == null:
		r.check(false, "naming 二: the game starts after the opening")
		return
	await r.frames(3)
	var story: Story = main.story
	var dlg: Dialogue = story.dialogue
	# the prologue's own opening: E until 小兔's first own line
	var plates := [await wait_hero_line(dlg)]
	var portrait_ok := dlg.current_portrait() != null
	r.check(plates == ["阿糯"] and portrait_ok, "naming 二: the opening scene in the dorm - his speaker plate says 阿糯 (with his portrait)", str(plates))
	# every line that named 小兔, through the real dialogue box
	while story.busy:
		await r.tap(KEY_E)
		if dlg.choosing:
			await r.tap(KEY_1)
	var shown := await show_lines(dlg, name_entries())
	var bad := []
	for x in shown:
		if not "阿糯" in String(x[1]) or "小兔" in String(x[1]) or "{" in String(x[1]):
			bad.append(x[1])
	r.check(bad.is_empty() and shown.size() == NAME_LINES.size(),
		"naming 二: narration, hints and NPC lines that named him say 阿糯 instead (e.g. '%s')" % (shown[1][1] if shown.size() > 1 else ""), str(bad))
	# a real scene (story.play) - 厨娘's line
	story.play("S4-厨娘-任务前")
	await r.frames(3)
	var bear_line := dlg.screen_text
	var bear_plate := dlg.name_label.text
	while story.busy:
		await r.tap(KEY_E)
	r.check(bear_line == "哎哟阿糯，饭还没好呢，先去正殿，师父等着你。" and bear_plate == "厨娘",
		"naming 二: 厨娘 says '哎哟阿糯，…' (her own name plate unchanged)", bear_line)
	# 徒儿 / 兔儿 (师父) and 师兄 (师弟) on screen unchanged
	var sk: Dictionary = data_of("skills")
	var s3: Dictionary = data_of("step3")
	var keep := await show_lines(dlg, [sk["scenes"]["K-师父-吐纳功-考验"][0], {"who": "crane", "text": "兔儿，你的身法还差一口气。"},
		s3["scenes"]["D-师弟-派活-spar"][0]])
	var keep_ok := keep.size() == 3 and String(keep[0][1]).begins_with("徒儿") and String(keep[1][1]).begins_with("兔儿") \
		and "等师兄" in String(keep[2][1]) and not keep.any(func(x): return "阿糯" in String(x[1]))
	r.check(keep_ok, "naming 二: 师父 still says 徒儿 / 兔儿, 师弟 still says 师兄", str(keep.map(func(x): return x[1])))
	# the 委托 thanks
	var com: Commission = main.jianghu.com
	com.offers = [{"kind": "bun", "state": "taken", "step": 99, "count": 0, "spots": [], "picked": []}]
	var thanks: String = com.turn_in(0)          # the real 交差 text (shown in the dialogue box)
	r.check("多谢阿糯兄弟" in thanks, "naming 二: the 送馒头 thanks say '多谢阿糯兄弟'", thanks)
	# 门派簿
	story.book_unlocked = true
	story.open_book()
	await r.frames(4)
	var book: SectBook = story.sect_book
	var book_name := book.name_label.text if book.name_label != null else ""
	var book_fits := book.panel.scale.x >= 0.999
	book.close()
	await r.frames(2)
	r.check(book_name == "弟子：阿糯" and book_fits, "naming 二: the 门派簿 says 弟子：阿糯 (on the close-hint line, the page still at scale 1)", book_name)
	await free_game(main)
	Opening.enabled = was_opening


func _wait_opening(limit := 120) -> Opening:
	for i in limit:
		await r.process_frame
		var o := _opening()
		if o != null:
			return o
	return null


func test_default_enter() -> void:
	SaveGame.erase()
	PlayerName.choose("团子")         # what a previous game left: 新游戏 starts again from 小兔
	Opening.enabled = false
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var p := await wait_naming()
	var filled := p.line.text if p else ""
	await r.tap(KEY_ENTER)
	var main: Node = await tt.wait_for_game(200)
	var plate := ""
	if main != null:
		await r.frames(3)
		plate = await wait_hero_line(main.story.dialogue)
	r.check(filled == "小兔" and PlayerName.value() == "小兔" and plate == "小兔",
		"naming 二: 新游戏 + Enter on the untouched box = 小兔 (the name plate says 小兔, as before)", str([filled, plate]))
	await free_game(main)
	Opening.enabled = was_opening


# ------------------------------------------------------------------ checks + keys
func test_checks_and_keys() -> void:
	SaveGame.erase()
	Opening.enabled = false
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var p := await wait_naming()
	if p == null:
		r.check(false, "naming checks: the box opens")
		return
	# empty
	await clear_box(p)
	await r.tap(KEY_ENTER)
	var empty_ok := p.is_open and p.error == "empty" and p.error_label.text == "名字不能是空的" and not title.starting
	# only spaces (half- and full-width)
	await type_text("  ")
	await type_char("　")
	await r.tap(KEY_ENTER)
	var spaces_ok := p.is_open and p.error == "empty" and not title.starting
	r.check(empty_ok and spaces_ok, "naming 二: an empty name or one of only spaces cannot be confirmed (「名字不能是空的」)",
		str([empty_ok, spaces_ok, p.line.text]))
	# 6th 字 cannot be typed
	await clear_box(p)
	await type_text("一二三四五六")
	var five := p.line.text
	var long_err := p.error
	await r.tap(KEY_ENTER)
	r.check(five == "一二三四五" and long_err == "too_long" and PlayerName.value() == "一二三四五" and title.starting,
		"naming 二: at most 5 字 - the 6th does not go in (「名字太长了」), the 5 are accepted", str([five, long_err]))
	await free_game(await tt.wait_for_game(200))
	# a character missing from the font
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	p = await wait_naming()
	await clear_box(p)
	await type_text("阿龘")
	var live := p.error_label.text
	await r.tap(KEY_ENTER)
	await tt.click(at(p.confirm_button))
	var refused := p.is_open and not title.starting and PlayerName.value() == "小兔"
	r.check(live == "这个字显示不了，换一个吧" and refused,
		"naming 二: a character the font cannot draw (龘) shows 「这个字显示不了，换一个吧」; Enter / 确定 do nothing", str([live, refused]))
	# game keys typed into the box are letters
	await clear_box(p)
	var sel_before := title.selected
	var acts_before := title.activations.size()
	var lang_before := Lang.current()
	for k in [KEY_UP, KEY_DOWN]:
		await r.tap(k)
	await type_text("eqbt h")
	var as_text := p.line.text
	r.check(as_text == "eqbt h" and title.selected == sel_before and title.activations.size() == acts_before
		and Lang.current() == lang_before and p.is_open and not title.help.is_open,
		"naming 二: E / Q / B / T / H / Space / ↑↓ typed in the box are only letters - the menu, the help page and the language do not react",
		str([as_text, title.activations]))
	# 6 letters are too many in Chinese mode (5 counted, the space not counted)
	r.check(PlayerName.counted(as_text) == 5, "naming 二: spaces are not counted against the limit", str(PlayerName.counted(as_text)))
	# Esc: back to the menu, nothing started
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	r.check(not p.is_open and not title.starting and not title.help.is_open and PlayerName.value() == "小兔",
		"naming 二: Esc in the box goes back to the title menu (no game, the name not changed)")
	# over an existing save: 确定 the overwrite question, then Esc in the box -> the save is still there
	SaveGame.write({"x": 1}, "test")
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)         # 会覆盖存档，确定吗？
	title._confirm_select(0)
	await r.tap(KEY_ENTER)
	p = await wait_naming()
	var asked := p != null
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	r.check(asked and SaveGame.exists() and not title.starting,
		"naming 二: 新游戏 over a save: after 确定 the box opens; Esc there leaves the old save untouched")
	SaveGame.erase()
	Opening.enabled = was_opening


# ------------------------------------------------------------------ saves
func _game_from_title_continue() -> Node:
	await new_title()
	title.select(title.index_of("continue"))
	await r.tap(KEY_ENTER)
	return await tt.wait_for_game(200)


func _direct_game() -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	r.root.add_child(m)
	r.current_scene = m
	await r.frames(3)
	return m


func _plate_now(m: Node) -> String:
	var dlg: Dialogue = m.story.dialogue
	dlg.say({"who": "rabbit", "text": "测试"})
	await r.frames(2)
	var t := dlg.name_label.text
	dlg.close()
	dlg.line_done.emit()
	return t


func test_save_load() -> void:
	SaveGame.erase()
	PlayerName.choose("白小楼")
	var m := await _direct_game()
	var st := SaveGame.capture(m)
	var wrote := SaveGame.write(st, "test")
	var in_file: String = String(SaveGame.read()["state"]["player"].get("name", ""))
	await free_game(m)
	PlayerName.reset()
	var g := await _game_from_title_continue()
	var plate := await _plate_now(g) if g != null else ""
	r.check(wrote and in_file == "白小楼" and PlayerName.value() == "白小楼" and plate == "白小楼",
		"naming 四: the name is in the save (state.player.name) and comes back with 继续游戏 (plate 白小楼)", str([in_file, plate]))
	# a save written now and read back keeps every other field too
	var again := SaveGame.roundtrip(SaveGame.capture(g)) if g != null else {}
	r.check(again.get("player", {}).get("name", "") == "白小楼", "naming 四: save -> load -> save keeps the name")
	await free_game(g)


func test_old_save() -> void:
	# an older save (no player.name) -> 小兔
	PlayerName.choose("月白")
	var m := await _direct_game()
	var st := SaveGame.capture(m)
	(st["player"] as Dictionary).erase("name")
	SaveGame.write(st, "old")
	await free_game(m)
	var g := await _game_from_title_continue()
	var plate := await _plate_now(g) if g != null else ""
	r.check(g != null and PlayerName.value() == "小兔" and plate == "小兔",
		"naming 四: an older save without a name loads, the hero is 小兔", str([PlayerName.value(), plate]))
	await free_game(g)
	# a name that is not text is refused like any broken field; text this version cannot show loads as 小兔
	var st2 := st.duplicate(true)
	st2["player"]["name"] = 5
	var why := SaveGame.validate(st2)
	st2["player"]["name"] = "龘龘"
	var ok_bad_glyph := SaveGame.validate(st2) == "" and PlayerName.from_save("龘龘") == "小兔" and PlayerName.from_save("") == "小兔" \
		and PlayerName.from_save("阿糯") == "阿糯" and PlayerName.from_save("Momo") == "Momo"
	r.check(why == "bad player.name" and ok_bad_glyph,
		"naming 四: player.name that is not text -> the save is refused ('bad player.name'); an empty / undrawable name loads as 小兔", why)
	# R1: the rule by characters (any UI language): 5 汉字 / 12 letters / mixed share the room
	var rule := [PlayerName.fits("一二三四五"), PlayerName.fits("一二三四五六"), PlayerName.fits("Abcdefghijkl"),
		PlayerName.fits("Abcdefghijklm"), PlayerName.fits("阿糯 Momo"), PlayerName.fits("一二三四五A"), PlayerName.fits("Little Rabbit")]
	Lang.set_lang("en")
	var en_ok: bool = not PlayerName.validate("一二三四五六")["ok"] and PlayerName.validate("一二三四五")["ok"]
	Lang.set_lang("zh")
	var zh_ok: bool = PlayerName.validate("Abcdefghijkl")["ok"] and not PlayerName.validate("Abcdefghijklm")["ok"]
	r.check(rule == [true, false, true, false, true, false, true] and en_ok and zh_ok,
		"naming R1: the length rule follows the characters in both languages: 5 汉字 yes / 6 no, 12 letters yes / 13 no, 阿糯 Momo yes, 5 汉字 + a letter no",
		str([rule, en_ok, zh_ok]))
	# R1: a saved name over the limit (12 汉字, written by hand) -> the save loads, the hero is 小兔
	var st3 := st.duplicate(true)
	st3["player"]["name"] = "一二三四五六七八九十甲乙"
	SaveGame.write(st3, "long")
	var g3 := await _game_from_title_continue()
	var plate3 := await _plate_now(g3) if g3 != null else ""
	r.check(g3 != null and PlayerName.value() == "小兔" and plate3 == "小兔",
		"naming R1: a save whose name has 12 汉字 still loads (继续游戏), the name falls back to 小兔", str([PlayerName.value(), plate3]))
	await free_game(g3)
	SaveGame.erase()
	PlayerName.reset()


# ------------------------------------------------------------------ Esc 改名
func test_esc_rename() -> void:
	SaveGame.erase()
	PlayerName.reset()
	var m := await _direct_game()
	var pm: PauseMenu = m.pause_menu
	var story: Story = m.story
	var dlg: Dialogue = story.dialogue
	while story.busy:
		await r.tap(KEY_E)
	# a line with his name on screen, then Esc
	story.play("S4-厨娘-任务前")
	await r.frames(3)
	var before := dlg.screen_text
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var head_ok := pm.is_open and pm.rename_button.visible and pm.name_label.text == "名字：小兔"
	await r.tap(KEY_R)
	await r.frames(2)
	var p: NamingPanel = pm.rename_panel
	var open_ok := p != null and p.is_open and p.mode == "rename" and p.title_label.text == "给他改个名字" and p.cancel_button.visible \
		and p.line.text == "小兔" and m.get_tree().paused
	r.check(head_ok and open_ok, "naming Esc 改名: the paused Esc page shows 名字：小兔 and 「改名（R）」; R opens the box (「给他改个名字」, 确定 / 随机 / 取消), the game stays paused",
		str([head_ok, open_ok]))
	if p == null:
		await free_game(m)
		return
	# typed hotkeys are letters: Q (任务面板), E / Enter-less (closing the page), B, T, Space
	var hour: float = m.daynight.hour
	var qb_refused: int = m.quest_board.refused
	await clear_box(p)
	await type_text("qe b")
	var letters_ok: bool = p.line.text == "qe b" and pm.is_open and p.is_open and not m.quest_board.is_open \
		and m.quest_board.refused == qb_refused and is_equal_approx(m.daynight.hour, hour) and not story.sect_book.is_open
	r.check(letters_ok, "naming Esc 改名: Q / E / B / Space typed in the box are letters - no 任务面板, the Esc page stays, no 门派簿, the clock does not move",
		str([p.line.text, pm.is_open, m.quest_board.refused - qb_refused]))
	# same checks as at 新游戏
	await clear_box(p)
	await r.tap(KEY_ENTER)
	var empty_refused := p.is_open and p.error == "empty"
	await type_text("龘")
	await r.tap(KEY_ENTER)
	var glyph_refused := p.is_open and p.error == "missing_char"
	await clear_box(p)
	await type_text("一二三四五六")
	var capped := p.line.text == "一二三四五"
	r.check(empty_refused and glyph_refused and capped and PlayerName.value() == "小兔",
		"naming Esc 改名: the same checks (empty refused, 龘 refused, 5 字 at most)", str([empty_refused, glyph_refused, p.line.text]))
	# Esc / 取消 = nothing changes
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	var cancelled := not p.is_open and pm.is_open and PlayerName.value() == "小兔"
	r.check(cancelled, "naming Esc 改名: Esc in the box closes only the box (the Esc page stays), the name is unchanged")
	# the button (mouse) -> 团子 -> at once: the page, the line on screen; free (coins unchanged); saved
	var coins: int = m.sample.coins
	await tt.click(at(pm.rename_button))
	var by_mouse := p.is_open
	p.line.select_all()
	await type_text("团子")
	await r.tap(KEY_ENTER)
	await r.frames(2)
	var page_name := pm.name_label.text
	var line_now := dlg.screen_text
	r.check(by_mouse and PlayerName.value() == "团子" and page_name == "名字：团子" and line_now == "哎哟团子，饭还没好呢，先去正殿，师父等着你。"
		and before == "哎哟小兔，饭还没好呢，先去正殿，师父等着你。" and m.sample.coins == coins and pm.is_open,
		"naming Esc 改名: 改名 (mouse) -> 团子 takes effect at once: the page says 名字：团子, the line on screen becomes '哎哟团子，…'; free",
		str([page_name, line_now]))
	await r.tap(KEY_ESCAPE)
	await r.frames(2)
	while story.busy:
		await r.tap(KEY_E)
	var plate := await _plate_now(m)
	await r.frames(10)
	var saves: Array = Array(m.sample.saves)
	var res := SaveGame.read()
	var in_file: String = String(res["state"]["player"].get("name", "")) if res["ok"] else ""
	r.check(not pm.is_open and plate == "团子" and saves.any(func(x): return "rename" in String(x)) and in_file == "团子",
		"naming Esc 改名: back in the game the plate says 团子 and the name is saved at the next calm moment (the save file says 团子)",
		str([plate, saves, in_file]))
	await free_game(m)
	PlayerName.reset()


# ------------------------------------------------------------------ English
func test_english_momo() -> void:
	SaveGame.erase()
	Lang.set_lang("en")
	Opening.enabled = false
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	var p := await wait_naming()
	if p == null:
		r.check(false, "naming English: the box opens")
		return
	var filled := p.line.text
	var head := p.title_label.atr(p.title_label.text)
	var lim := p.limit_label.atr(p.limit_label.text)
	# R1: the limit follows the characters, not the UI language - 12 汉字 typed in English mode stop at 5
	await clear_box(p)
	await type_text("一二三四五六七八九十甲乙")
	var hanzi_capped := p.line.text
	await r.tap(KEY_ENTER)
	var hanzi_taken := PlayerName.value()
	r.check(hanzi_capped == "一二三四五",
		"naming R1: English mode, 12 汉字 typed -> only 5 go in (the same 5-汉字 limit as in Chinese)", hanzi_capped)
	r.check(hanzi_taken == "一二三四五", "naming R1: ... and those 5 are what Enter takes", hanzi_taken)
	var main0: Node = await tt.wait_for_game(200)
	await free_game(main0)
	await new_title()
	title.select(title.index_of("start"))
	await r.tap(KEY_ENTER)
	p = await wait_naming()
	if p == null:
		r.check(false, "naming English: the box opens again")
		return
	# 12 letters at most (a 13th does not go in)
	await clear_box(p)
	await type_text("Abcdefghijklm")
	var capped := p.line.text
	# a random name in English
	await tt.click(at(p.random_button))
	var rnd := p.line.text
	var rnd_en := PlayerName.random_names().any(func(n): return Lang.t(String(n)) == rnd)
	r.check(filled == "Little Rabbit" and head == "Name this little rabbit" and lim == "Up to 12 letters (5 Chinese characters)" and capped == "Abcdefghijkl"
		and rnd_en and cjk.search(rnd) == null,
		"naming English: the box says 'Name this little rabbit', is filled with 'Little Rabbit', 'Up to 12 letters' (a 13th letter does not go in); 随机 gives English names",
		str([filled, head, lim, capped, rnd]))
	p.line.select_all()
	await type_text("Momo")
	await r.tap(KEY_ENTER)
	var main: Node = await tt.wait_for_game(200)
	if main == null:
		r.check(false, "naming English: the game starts")
		Lang.set_lang("zh")
		return
	await r.frames(3)
	var dlg: Dialogue = main.story.dialogue
	while main.story.busy:
		await r.tap(KEY_E)
	var shown := await show_lines(dlg, name_entries())
	var bad := []
	for x in shown:
		if not "Momo" in String(x[1]) or "Little Rabbit" in String(x[1]) or cjk.search(String(x[1])) != null:
			bad.append(x[1])
	var plate := await _plate_now(main)
	var plate_shown := dlg.name_label.atr(plate)
	r.check(bad.is_empty() and shown.size() == NAME_LINES.size() and plate_shown == "Momo" and PlayerName.value() == "Momo",
		"naming English: name Momo - every line that said Little Rabbit says Momo (e.g. '%s'), the plate says Momo" % (shown[6][1] if shown.size() > 6 else ""),
		str(bad.slice(0, 4)))
	# the default in English is still Little Rabbit
	PlayerName.reset()
	var shown2 := await show_lines(dlg, name_entries())
	var bad2 := shown2.filter(func(x): return not "Little Rabbit" in String(x[1]) or cjk.search(String(x[1])) != null)
	var plate2 := dlg.name_label.atr(await _plate_now(main))
	r.check(bad2.is_empty() and plate2 == "Little Rabbit",
		"naming English: with the default name every one of these lines says Little Rabbit (as before) and the plate too", str(bad2.slice(0, 3)))
	# a random name chosen in English is kept as the Chinese original (shows in its own form in either language)
	PlayerName.reset()
	Lang.set_lang("en")
	main.pause_menu.open()
	await r.frames(2)
	var en_head: String = main.pause_menu.name_label.atr(main.pause_menu.name_label.text)
	main.pause_menu.open_rename()
	await r.frames(2)
	var rp: NamingPanel = main.pause_menu.rename_panel
	rp.line.select_all()
	await type_text("一二三四五六七八九十甲乙")      # R1: the Esc rename has the same 5-汉字 limit in English mode
	var esc_capped := rp.line.text
	r.check(esc_capped == "一二三四五", "naming R1: Esc 改名 in English mode: 12 汉字 typed -> 5 go in", esc_capped)
	rp.line.select_all()
	await type_text("Mochi")
	await r.tap(KEY_ENTER)
	var kept := PlayerName.value()
	main.pause_menu.close()
	await r.frames(2)
	r.check(en_head == "Name: Little Rabbit" and kept == "阿糯",
		"naming English: the Esc page says 'Name: Little Rabbit'; renaming to 'Mochi' (阿糯's English) keeps 阿糯", str([en_head, kept]))
	await free_game(main)
	Lang.set_lang("zh")
	PlayerName.reset()
	Opening.enabled = was_opening
