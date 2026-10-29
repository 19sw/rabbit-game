extends RefCounted
## 中英文切换 v1 checks (docs/design/中英文切换-方案-v1.md), run by tests/run_tests.gd, or alone:
##   godot --headless --fixed-fps 60 --path game2d -s tests/run_tests.gd -- --only-i18n
## The English mode is switched on inside the run (Lang.set_lang) and back to Chinese at the end. Every other suite keeps
## checking the Chinese game; here the layout checks of the earlier rounds run again in English (every dialogue line and
## choice, every Esc page, the full 门派簿, the HUD list, every toast, both boards, the captions, every 任务面板 tab).
## The whole run in English (GAME_LANG=en GAME_LANG_LOG=<file>) lists every text that was on screen without English -
## tools/check_english.sh does that and must report 0.

var r
var tt                # title_suite (its title / click helpers)
var s4                # step4a_suite (game, all_lines, the layout checks)
var gs                # guide_suite (the 任务面板 layout check)
var report := {}
var cjk := RegEx.create_from_string(LangTranslation.CJK)


func _init(runner) -> void:
	r = runner


func run() -> void:
	if r.main != null and is_instance_valid(r.main) and r.main.is_inside_tree():
		r.main.get_parent().remove_child(r.main)
	r.paused = false
	r.release_all()
	r.root.size = Vector2i(1440, 810)
	SaveGame.erase()
	var ss = load("res://tests/sample_suite.gd").new(r)
	var t3 = load("res://tests/step3_suite.gd").new(r)
	t3.ss = ss
	s4 = load("res://tests/step4a_suite.gd").new(r)
	s4.ss = ss
	s4.t3 = t3
	gs = load("res://tests/guide_suite.gd").new(r)
	gs.ss = ss
	gs.t3 = t3
	gs.s4 = s4
	tt = load("res://tests/title_suite.gd").new(r)
	Lang.set_lang("zh")
	await test_catalog()
	await test_data_coverage()
	await test_title_switch()
	await test_live_switch()
	await test_midline()
	Lang.set_lang("en")
	# the earlier rounds' "nothing leaves the screen" checks, now with the English texts
	await s4.test_dialogue_fit()
	await s4.test_screens()
	await gs.test_layout()
	await test_english_unscaled()
	await test_english_paging()
	Lang.set_lang("zh")
	await ss._free_game()
	if tt.title != null and is_instance_valid(tt.title):
		tt.title.queue_free()
	SaveGame.erase()
	print("I18N REPORT ", report)


## data/i18n/en.json: every line has English, and a template has the same placeholders in both languages.
func test_catalog() -> void:
	var lines := {}
	for f in DirAccess.get_files_at("res://data/i18n"):
		if f.begins_with("en") and f.ends_with(".json"):
			var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/" + f))
			lines.merge(doc["lines"], true)
	var bad := []
	var ph := RegEx.create_from_string("\\{\\d\\}")
	for zh in lines:
		var en := String(lines[zh])
		var a := ph.search_all(String(zh)).map(func(m): return m.get_string())
		var b := ph.search_all(en).map(func(m): return m.get_string())
		a.sort()
		b.sort()
		if en.strip_edges() == "" and String(zh).strip_edges() != "":
			bad.append("empty: " + String(zh))
		elif cjk.search(en) != null:
			bad.append("Chinese left in the English: " + String(zh))
		elif not b.all(func(x): return x in a):
			bad.append("placeholders: " + String(zh))   # (English may leave one out - 辰时 08:00 -> 08:00 - never invent one)
	for t in Lang.translation().templates:
		if not (t["re"] as RegEx).is_valid():
			bad.append("bad pattern: " + String(t["zh"]))
	report["catalog"] = {"lines": lines.size(), "templates": Lang.translation().templates.size()}
	r.check(bad.is_empty() and lines.size() > 700,
		"i18n: data/i18n/en*.json have %d Chinese -> English lines (%d templates with {0} {1}...), none empty, no Chinese left in the English" % [lines.size(), Lang.translation().templates.size()],
		str(bad.slice(0, 8)))


## Every Chinese text in the data files (dialogue, names, places, board / HUD / Esc wording) has English. Scene ids
## ("S1-醒来", "J-黑虎-胜" - names in the data, never shown) and the single 时辰 characters (only shown inside "辰时 08:00",
## which becomes "08:00") are not texts.
func test_data_coverage() -> void:
	Lang.set_lang("en")
	var bad := []
	var n := 0
	var ids := RegEx.create_from_string("^[A-Z][A-Z0-9]*-")
	var stack := []
	for f in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json"):
			stack.append([JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f)), f, ""])
	while not stack.is_empty():
		var it = stack.pop_back()
		var v = it[0]
		if v is Dictionary:
			for k in v:
				if not String(k).begins_with("_") and String(k) != "shichen":
					stack.append([v[k], it[1], String(k)])
		elif v is Array:
			for x in v:
				stack.append([x, it[1], it[2]])
		elif v is String and cjk.search(v) != null and ids.search(v) == null:
			n += 1
			var en := Lang.t(String(v))
			if cjk.search(en) != null:
				bad.append("%s:%s '%s'" % [it[1], it[2], String(v).substr(0, 24)])
	# texts written in the scripts (the Esc page's keys and tips, HUD lines)
	for k in PauseMenu.KEYS:
		for x in k:
			n += 1
			if cjk.search(Lang.t(String(x))) != null:
				bad.append("Esc key '%s'" % x)
	for tips in [PauseMenu.TIPS, PauseMenu.TIPS_SAMPLE, PauseMenu.TIPS_STEP3, PauseMenu.TIPS_JIANGHU]:
		for tip in tips:
			n += 1
			var line := "%s：%s" % [tip[0], PauseMenu._fill_tip(tips, tip[1])]
			if cjk.search(Lang.t(line)) != null:
				bad.append("Esc tip '%s'" % tip[0])
	for x in [PauseMenu.TITLE, PauseMenu.KEYS_TITLE, PauseMenu.TIPS_TITLE, PauseMenu.RESUME_TEXT, Hud.HINT_TEXT,
			Hud.AMBIENCE_ON_TEXT, Hud.AMBIENCE_OFF_TEXT, Hud.PROMPT_TEXT]:
		n += 1
		if cjk.search(Lang.t(String(x))) != null:
			bad.append("'%s'" % String(x).substr(0, 16))
	Lang.set_lang("zh")
	report["data_texts"] = n
	r.check(bad.is_empty() and n > 800, "i18n: all %d Chinese texts of the data files and the Esc / HUD wording translate to English (nothing left Chinese)" % n,
		str(bad.slice(0, 10)))


## The title screen: 「中文 | English」 in the top-right corner, a click (or ← →) switches, the buttons / name follow.
func test_title_switch() -> void:
	await tt.new_title()
	var title: TitleScreen = tt.title
	var vp: Vector2 = title.get_viewport().get_visible_rect().size
	var sw: LangSwitch = title.lang_switch
	await r.frames(2)
	var rect := sw.rect()
	var corner := rect.end.x > vp.x - 30.0 and rect.position.y < 20.0 and Rect2(Vector2.ZERO, vp).encloses(rect)
	var start_b: Button = title.button("start")
	var zh_w := start_b.get_combined_minimum_size().x
	var b_en: Button = sw.buttons["en"]
	# window pixels of the button's centre (a CanvasLayer control: its canvas transform, then the window stretch)
	var at: Vector2 = b_en.get_viewport().get_final_transform() * (b_en.get_global_transform_with_canvas() * (b_en.size * 0.5))
	await tt.mouse_move(at)
	var hovered = title.get_viewport().gui_get_hovered_control()
	await tt.click(at)
	await r.frames(3)
	var after_click := Lang.current()
	var name_en := title.logo_en.visible and title.logo_en.text == "The Mountain Courtyard"   # 改名与起名 v1: the new name
	var shown := start_b.atr(start_b.text)
	await r.tap(KEY_LEFT)
	await r.frames(2)
	var after_key := Lang.current()
	r.check(corner and after_click == "en" and shown == "New Game" and name_en and after_key == "zh" and not title.logo_en.visible,
		"i18n: the title screen has 「中文 | English」 in its top-right corner; a click on English shows 'New Game' and the English name under the logo; ← / → switches back",
		str([rect, after_click, shown, name_en, after_key, zh_w, hovered.get_path() if hovered else null]))
	# the title's help page (the Esc page in help mode) has no second switch, and the title's corner switch hides under it
	title.help.open()
	await r.frames(2)
	var hidden_on_help := not sw.visible
	title.help.close()
	await r.frames(2)
	r.check(not title.help.lang_box.visible and hidden_on_help and sw.visible,
		"i18n: the title's 按键与玩法 page has no language row, and the corner switch hides while that page is open (it would sit on the page)")
	title.queue_free()
	await r.process_frame


## In the game: the Esc page's 「中文 | English」 switches every text at once (HUD, objective, Esc page) and nothing
## of the game state changes; the setting is not part of the save.
func test_live_switch() -> void:
	await s4.game()
	await r.frames(3)
	var g: Node = s4.g
	var hud = g.hud
	var pm: PauseMenu = g.pause_menu
	var obj_zh: String = hud.objective_label.text
	var coins0: int = g.sample.coins
	pm.open()
	await r.frames(2)
	var row_ok := pm.lang_box.is_visible_in_tree() and Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size).encloses(pm.lang_box.get_global_rect())
	var eb: Button = pm.lang_buttons["en"]
	eb.pressed.emit()
	await r.frames(3)
	var title_en := pm.title_label.atr(pm.title_label.text)
	var panel_ok := Rect2(Vector2.ZERO, g.get_viewport().get_visible_rect().size).encloses(pm.panel.get_global_rect())
	# ↑ / ↓ on the page switch too (← → turn the tip pages)
	await r.tap(KEY_UP)
	var key_zh := Lang.current()
	await r.tap(KEY_DOWN)
	var key_en := Lang.current()
	var row_label: String = (pm.lang_box.get_child(0) as Label).atr((pm.lang_box.get_child(0) as Label).text)
	pm.close()
	await r.frames(2)
	r.check(key_zh == "zh" and key_en == "en" and row_label == "Language (↑↓):",
		"i18n: on the Esc page ↑ / ↓ switch the language as well (the row says 'Language (↑↓):')", str([key_zh, key_en, row_label]))
	var obj_en: String = hud.objective_label.atr(hud.objective_label.text)
	var save_doc := SaveGame.capture(g)
	r.check(row_ok and Lang.current() == "en" and title_en == "Paused · Controls & Tips" and panel_ok and obj_en.begins_with("Goal: ")
		and hud.objective_label.text == obj_zh and g.sample.coins == coins0 and not JSON.stringify(save_doc).contains("\"lang\""),
		"i18n: the Esc page's 「中文 | English」 switches the whole game at once (Esc page, objective line '%s'); the page still fits; the game state and the save are untouched" % obj_en,
		str([row_ok, title_en, panel_ok, obj_en]))
	Lang.set_lang("zh")
	await r.frames(2)


## A line on screen while the language changes: it is shown again in the new language, inside the box, from its first
## page - and back.
func test_midline() -> void:
	await s4.game()
	await r.frames(3)
	var story = s4.story
	var dlg: Dialogue = s4.dlg
	story.data["scenes"]["T-语言"] = [{"who": "crane", "text": "一条，是去江湖上闯——比武、试炼、行侠，让天下人重新知道咱们的功夫。这叫名望。"}, {"kind": "提示", "text": "（下一句）"}]
	story.play("T-语言")
	await r.frames(6)
	var zh_page := dlg.page_text
	Lang.set_lang("en")
	await r.frames(3)
	var en_page := dlg.page_text
	var fits := dlg.lines_for(en_page) <= dlg.line_capacity() and not dlg.is_typing()
	var name_en := dlg.name_label.atr(dlg.name_label.text)
	Lang.set_lang("zh")
	await r.frames(3)
	var back := dlg.page_text
	for i in 20:
		if not story.busy:
			break
		await r.tap(KEY_E)
	r.check(en_page.begins_with("One is") and fits and name_en == "Master" and back == zh_page and dlg.full_text != "",
		"i18n: a line on screen switches language at once (师父 -> Master, the line in English inside the box) and back",
		str([en_page.substr(0, 30), name_en, back.substr(0, 10)]))


## English never shrinks a panel (方案第四节: the font size stays): every Esc page and a completely full 门派簿 keep
## scale 1 at 480x270, 640x360 and 500x280; the 任务面板 tab names fit their column.
func test_english_unscaled() -> void:
	await s4.game()
	await r.frames(3)
	var g: Node = s4.g
	var pm: PauseMenu = g.pause_menu
	var bad := []
	var b = s4.b
	b.main_done = 3
	b.patrols_done = 12
	s4.cm.total = 23
	s4.s3.arena.wins = [1, 2, 3, 4, 5, 6]
	s4.s3.arena.hard_wins = [7, 8, 9]
	for f in ["trial_bronze", "trial_silver", "trial_gold", "repair_roof", "repair_dorm_old", "repair_kitchen"]:
		s4.story.flags[f] = true
	for w in [Vector2i(1440, 810), Vector2i(1920, 810), Vector2i(1000, 560)]:
		var vp: Vector2 = await s4.set_window(w)
		pm.open()
		for pgi in pm.tip_pages.size():
			pm.show_page(pgi)
			await r.frames(2)
			if pm.panel.scale.x < 0.999 or not Rect2(Vector2.ZERO, vp).encloses(pm.panel.get_global_rect()):
				bad.append("%s Esc %d scale %.3f" % [w, pgi + 1, pm.panel.scale.x])
		pm.close()
		await r.frames(2)
		s4.story.book_unlocked = true
		await r.tap(KEY_B)
		await r.frames(3)
		var bp: Control = s4.story.sect_book.panel
		if bp.scale.x < 0.999 or not Rect2(Vector2.ZERO, vp).encloses(bp.get_global_rect()):
			bad.append("%s book scale %.3f %s" % [w, bp.scale.x, bp.get_global_rect()])
		await r.tap(KEY_ESCAPE)
		await r.frames(2)
	await s4.set_window(Vector2i(1440, 810))
	# the 任务面板's tab names (drawn text) stay inside the tab column
	var qb = g.quest_board
	g.guide.started = true
	await r.tap(KEY_Q)
	await r.frames(3)
	for l in qb.tab_labels:
		var f: Font = l.get_theme_font("font")
		var tw := f.get_string_size(l.atr(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		if tw > l.size.x + 0.5 or l.get_global_rect().end.x > qb.list_box.get_global_rect().position.x:
			bad.append("tab '%s' %.0f > %.0f" % [l.atr(l.text), tw, l.size.x])
	await r.tap(KEY_Q)
	await r.frames(2)
	r.check(bad.is_empty(), "i18n: in English no panel is scaled down - every Esc page and a full 门派簿 keep scale 1 at 480x270, 640x270 and 500x280; the 任务面板 tab names fit their column", str(bad))


## English pages break between words: a long English speech is cut into pages that fit, end at a full stop / a word,
## and lose no word.
func test_english_paging() -> void:
	await s4.game()
	await r.frames(3)
	# 黑虎's real lines in English, run together (each line alone fits one page)
	var parts := []
	for id in ["J-黑虎-上场", "J-黑虎-胜"]:
		for e in s4.jh.data["scenes"][id]:
			if String(e.get("who", "")) == "tiger":
				parts.append(Lang.t(String(e["text"])))
	var en := " ".join(parts)
	var b2: Array = await s4.play_pages(en, "tiger")
	var pages: int = b2[0]
	var seen: Array = b2[1]
	var ok_ends := true
	for i in range(0, pages - 1):
		var pg: String = b2[2][i]
		var nxt: String = b2[2][i + 1]
		# a page never ends inside a word: the next page starts a new word
		if not (pg.ends_with(".") or pg.ends_with("!") or pg.ends_with("?") or pg.ends_with(",") or en.contains(pg + " " + nxt.substr(0, 3))):
			ok_ends = false
	var joined := " ".join(b2[2]).replace("  ", " ")
	report["english_paging"] = b2[2]
	r.check(pages >= 2 and seen.size() == pages + 1 and joined.replace(" ", "") == en.replace(" ", "") and ok_ends and cjk.search(joined) == null
		and seen[-1] == Lang.t("（下一句）"),
		"i18n: a long speech in English shows in %d pages, each ending between words, nothing lost" % pages, str(b2[2]))
