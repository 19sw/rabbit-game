class_name PauseMenu
extends CanvasLayer
## Esc 暂停说明页 (v1.2): Esc pauses the whole game (SceneTree.paused: time of day, enemies, player, timers,
## tweens, animations all stop) and shows every key + short play tips. Esc again, E / Enter, or the
## "继续" button resumes exactly where it stopped. This node keeps running while paused (PROCESS_MODE_ALWAYS).
## 启动画面 v1: the title screen's "按键与玩法" page is this same page in help mode (configure_as_help()): the same
## KEYS / TIPS below (one source for both pages), only the heading and the button text differ; it never pauses the
## tree and Esc only closes it (never opens it).

signal opened
signal closed
signal hero_renamed(name: String)     # 改名与起名 v1: the hero was renamed on this page (main saves, the dialogue refreshes)

const TITLE := "暂停 · 按键与玩法"
const KEYS_TITLE := "全部按键"
const TIPS_TITLE := "玩法要点"
const RESUME_TEXT := "继续（Esc）"
## 两条路小样 v1: the play tips come on two pages (the page has no room for more lines): page 1 = TIPS (combat / moving
## around), page 2 = TIPS_SAMPLE (试炼、修缮、铜钱、存档). ← → / A D or the small arrow button turn the page.
const PAGE_TEXT := "%d / %d  ← → 翻页"
const PAGE_BUTTON_TEXT := "▶"
const ABANDON_KEY_TEXT := "（Q）"
## 音效 + 背景音乐 v1: two small buttons in the bottom row, 「音乐：中」 / 「音效：中」, four levels each (关 / 小 / 中 / 大, names
## from data/audio.json). A click moves the level on, or Tab picks a button (lit; the page hint then reads SOUND_HINT) and
## ← / → change it; with none picked ← / → turn
## the tips page as before (↑ / ↓ stay the language). A setting, not part of the save (AudioService keeps it, Sfx reaches
## it). The bottom row is used because the page is already as tall as 480x270 allows.
const SOUND_ROWS := [["music", "音乐"], ["sfx", "音效"]]
const SOUND_LEVELS := ["关", "小", "中", "大"]
const SOUND_HINT := "Tab 选 · ← → 调音量"
const LANG_TEXT := "语言（↑↓）："      # 中英文切换 v1: the language row - a click, or ↑ / ↓ while the page is open
## [key, use]
const KEYS := [
	["WASD / 方向键", "移动"],
	["J / 鼠标左键", "攻击（连按 = 两连击）"],
	["空格 / Shift", "闪避"],
	["K / 鼠标右键", "格挡（GP）"],
	["E", "交谈 / 查看 / 拿起 / 擦 / 打开 / 确认"],
	["走到门口", "进屋 / 出屋（朝门走就行）"],
	["E / 回车 / 空格", "对话：下一句（鼠标左键也行）"],
	["1 / 2 或 ↑↓", "选择（对话 / 切磋 / 派活 1–4）"],
	["B", "门派簿（序章收尾后可看）"],
	["Q", "任务面板（指引、委托……）"],
	["T", "时间快进 1 小时"],
	["L / H", "氛围灯光 / 屏幕提示 开关"],
	["Esc", "暂停 / 回到游戏"],
]
## [name, text]
const TIPS := [
	["两连击", "J 连按两下，第二下更重（8 + 12）。"],
	["闪避无敌", "闪避的一瞬间不会受伤；用完要稍等才能再闪。"],
	["格挡（GP）", "敌人头顶出“!”时按 K：挡住不掉血，自动反击 30；按早了会僵住。"],
	["自动换位", "朝 2 格内的敌人闪避，会绕到它背后。"],
	["闪身追击", "闪避后 0.6 秒内按 J，冲向 3 格内最近的敌人，一定打中。"],
	["切磋", "在练武场找师兄按 E；任一方生命降到 20% 就结束，双方回满。"],
	["回血", "脱离战斗、5 秒没受伤后，每秒回 3 点。"],
	["山贼与复活", "山路上的狼和野猪走近就开打；被打倒在山门外复活，山贼回原位。"],
	["小地图", "左上角的圆以你为中心，星星在圆边上指方向；挡住人时会变透明。"],
]
## [name, text] - page 2 (两条路小样 v1, after the prologue); the {numbers} come from economy.json / the trial card
## (Sample.fill), so the tips always say what the game does
const TIPS_SAMPLE := [
	["铜钱", "序章结束后师父给本钱 {start_coins}。显示在生命条旁边，门派簿里也看得到。"],
	["梅花桩试炼", "练武场木牌按 E 报名。桩依次亮起，踩上亮着的那根；木人桩扫到掉 {dummy_damage} 点，闪避可无敌穿过。"],
	["评价与奖励", "限时 {time_limit} 秒：{gold_s} 秒内金、{silver_s} 秒内银、{bronze_s} 秒内铜。每种评价第一次拿到给铜钱和名望，之后每次 {repeat} 文。"],
	["失败与放弃", "生命降到 {fail_pct}% 或超时就算这次失败（生命回满）；试炼中按 Esc 可以放弃。试炼中不回血。"],
	["修缮", "找老周（屋顶 {roof_cost}）、老伯（旧弟子房 {dorm_old_cost}）、厨娘（厨房 {kitchen_cost}）按 E；钱不够会告诉你还差多少。修好加家业。"],
	["小食摊", "厨房修好后门口开小食摊，每天辰时（{stall_hour} 点）收入 {stall_income} 铜钱。"],
	["存档", "自动保存（剧情、修缮、试炼、收钱、进出门）。启动画面“继续游戏”接着玩。"],
]
## [name, text] - page 3 (第③步: 比武大会, 收徒); the {numbers} come from economy.json (Step3.numbers)
const TIPS_STEP3 := [
	["比武大会", "序章结束那天算第 1 天。第 {interval}、6、9……天的午时到酉时（{open_hour}–{close_hour} 点），村口擂台旁的告示牌按 E 报名，报名费 {fee} 文；每届只能上台一次。"],
	["擂台规则", "连打三轮：猴子、牦牛、蛇。生命掉到 {lose_pct}% 就输，两轮之间回 {between_heal} 点。比赛中不回血、下不了台；按 Esc 可以弃权（Q）。出局后生命回满。"],
	["夺魁奖励", "普通：头一回 {first_win_coins} 文、名望 +{first_win_fame}，之后 {win_coins} 文、+{win_fame}。报名时可选困难（对手不被打断、更凶）：头一回 {hard_first_coins} 文、+{hard_first_fame}，之后 {hard_win_coins} 文、+{hard_win_fame}。名望最多 10 格。"],
	["收徒", "旧弟子房整理好，名望或家业到 {need_fame} 格，第二天辰时山门外会来一个少年。收下后每天辰时扣伙食费 {upkeep} 文，钱不够就先欠着。"],
	["师弟的活", "找师弟按 E 派活，第二天辰时起生效：帮厨（小食摊每天 {cook_income} 文，要先修好厨房）、陪练（每天一回，赢了 +{spar_coins} 文，满 {spar_wins} 胜名望 +1）、打扫（满 {sweep_days} 天家业 +1）。"],
]

## [name, text] - page 4 (第④步第一批: 江湖告示榜, 悬赏, 委托); the {numbers} come from data/jianghu.json (Jianghu.numbers)
const TIPS_JIANGHU := [
	["江湖告示榜", "村口小广场。最多 {max_bounty} 条悬赏、{max_commission} 条委托；放弃不罚。"],
	["悬赏", "第 {first_day} 天辰时贴第一条：黄鼠狼（{b1_coins} 文、名望 +{b1_fame}）、狼山贼三人组（{b2_coins} 文、+{b2_fame}）、黑虎（{b3_coins} 文、+{b3_fame}）。交一条，次日辰时贴下一条。"],
	["打恶人", "接榜后恶人才出现（红点）。生命掉到 {lose_pct}% 判负：回满血、恶人还在、不扣钱；交榜才领赏。"],
	["巡山", "三条揭完后每 {patrol_days} 天辰时贴一条（2 个狼山贼，{patrol_coins} 文，不加名望），没接的被下一条换掉。"],
	["委托", "每天辰时贴 {per_day} 条，子时前交差，过时作废。送馒头 {c_bun}、送信 {c_letter}、找鸡 {c_chicken}、挖竹笋 {c_shoots}、找玉佩 {c_jade}、补篱笆 {c_fence} 文；黄点指路。"],
	["委托奖励", "满 {estate_every} 条家业 +1；名望 ≥{bonus_at} 报酬 ×{bonus_mult}（四舍五入）。"],
]

var is_open := false
var help_only := false          # title-screen help page: no pausing, Esc never opens it
var root: Control
var title_label: Label
var panel: PanelContainer
var resume_button: Button
var key_labels: Array[Label] = []
var tip_labels: Array[Label] = []         # page 1 (TIPS)
var sample_tip_labels: Array[Label] = []  # page 2 (TIPS_SAMPLE)
var step3_tip_labels: Array[Label] = []   # page 3 (TIPS_STEP3)
var jianghu_tip_labels: Array[Label] = [] # page 4 (TIPS_JIANGHU)
var tip_pages: Array[VBoxContainer] = []
var page := 0
var page_label: Label
var page_button: Button
var abandon_button: Button
var lang_box: HBoxContainer          # 中英文切换 v1 (hidden on the title's help page: the title has its own switch)
var lang_buttons := {}
var _abandon_action: Callable = Callable()
var sound_buttons := {}              # "music" / "sfx" -> Button "音乐：中" (a click moves the level on; lit while Tab picked it)
var sound_focus := -1                # -1 = none, 0 = 音乐, 1 = 音效
var _was_paused := false
## 改名与起名 v1: the title row has the hero's name on the left ("名字：小兔") and 「改名（R）」 on the right (not on the title
## screen's help page); the button / R opens the naming box (rename mode: free, at once; Esc / 取消 leaves it as it was).
var name_label: Label
var rename_button: Button
var rename_panel: NamingPanel


func _init() -> void:
	name = "PauseMenu"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing under the page can be clicked while paused
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.11, 0.08, 0.08, 0.96), Color(0.92, 0.76, 0.45), 6, 4))
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	var title := _label(TITLE, 12, Color(1.0, 0.88, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 4)
	name_label = _label("", 9, Color(0.85, 0.78, 0.6))
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = false
	head_row.add_child(name_label)
	head_row.add_child(title)
	rename_button = Button.new()
	rename_button.name = "Rename"
	rename_button.text = PlayerName.ui("rename_button")
	rename_button.focus_mode = Control.FOCUS_NONE
	rename_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rename_button.add_theme_font_size_override("font_size", 9)
	rename_button.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7))
	rename_button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.5))
	rename_button.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.5))
	rename_button.add_theme_stylebox_override("normal", _box(Color(0.2, 0.15, 0.13, 0.9), Color(0.75, 0.6, 0.4), 3, 0))
	rename_button.add_theme_stylebox_override("hover", _box(Color(0.3, 0.2, 0.15, 0.95), Color(1.0, 0.86, 0.5), 3, 0))
	rename_button.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.2, 0.15, 0.95), Color(1.0, 0.86, 0.5), 3, 0))
	rename_button.pressed.connect(open_rename)
	head_row.add_child(rename_button)
	col.add_child(head_row)
	title_label = title
	col.add_child(_rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	col.add_child(body)

	# left: every key
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 1)
	left.add_child(_label(KEYS_TITLE, 10, Color(1.0, 0.82, 0.45)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	for k in KEYS:
		var kl := _label(k[0], 9, Color(1.0, 0.93, 0.7))
		var ul := _label(k[1], 9, Color(0.95, 0.92, 0.86))
		grid.add_child(kl)
		grid.add_child(ul)
		key_labels.append(kl)
		key_labels.append(ul)
	left.add_child(grid)
	body.add_child(left)

	var sep := ColorRect.new()
	sep.color = Color(0.92, 0.76, 0.45, 0.35)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sep)

	# right: short play tips (two pages, see PAGE_TEXT)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var tips_title := _label(TIPS_TITLE, 10, Color(1.0, 0.82, 0.45))
	tips_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tips_title)
	page_label = _label("", 8, Color(0.85, 0.78, 0.6))
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(page_label)
	page_button = Button.new()
	page_button.text = PAGE_BUTTON_TEXT
	page_button.focus_mode = Control.FOCUS_NONE
	page_button.add_theme_font_size_override("font_size", 8)
	page_button.add_theme_color_override("font_color", Color(0.27, 0.14, 0.1))
	page_button.add_theme_color_override("font_hover_color", Color(0.6, 0.18, 0.08))
	page_button.add_theme_stylebox_override("normal", _box(Color(1.0, 0.95, 0.84), Color(0.47, 0.24, 0.16), 3, 0))
	page_button.add_theme_stylebox_override("hover", _box(Color(1.0, 0.88, 0.62), Color(0.6, 0.18, 0.08), 3, 0))
	page_button.add_theme_stylebox_override("pressed", _box(Color(0.98, 0.8, 0.5), Color(0.6, 0.18, 0.08), 3, 0))
	page_button.pressed.connect(func(): turn_page(1))
	head.add_child(page_button)
	right.add_child(head)
	for tips in [TIPS, TIPS_SAMPLE, TIPS_STEP3, TIPS_JIANGHU]:
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 1)
		for tip in tips:
			var l := _label("", 9, Color(0.95, 0.92, 0.86))
			l.text = "%s：%s" % [tip[0], _fill_tip(tips, tip[1])]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # line breaking that never starts a line with 。”，
			l.custom_minimum_size = Vector2(238, 0)
			pg.add_child(l)
			if tips == TIPS:
				tip_labels.append(l)
			elif tips == TIPS_SAMPLE:
				sample_tip_labels.append(l)
			elif tips == TIPS_STEP3:
				step3_tip_labels.append(l)
			else:
				jianghu_tip_labels.append(l)
		right.add_child(pg)
		tip_pages.append(pg)
	body.add_child(right)

	col.add_child(_rule())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	resume_button = Button.new()
	resume_button.text = RESUME_TEXT
	resume_button.focus_mode = Control.FOCUS_NONE   # Space (= dash) must not resume by accident; Enter / E do
	resume_button.add_theme_font_size_override("font_size", 10)
	resume_button.add_theme_color_override("font_color", Color(0.27, 0.14, 0.1))
	resume_button.add_theme_color_override("font_hover_color", Color(0.6, 0.18, 0.08))
	resume_button.add_theme_color_override("font_focus_color", Color(0.27, 0.14, 0.1))
	resume_button.add_theme_color_override("font_pressed_color", Color(0.6, 0.18, 0.08))
	resume_button.add_theme_stylebox_override("normal", _box(Color(1.0, 0.95, 0.84), Color(0.47, 0.24, 0.16), 10, 1))
	resume_button.add_theme_stylebox_override("hover", _box(Color(1.0, 0.88, 0.62), Color(0.6, 0.18, 0.08), 10, 1))
	resume_button.add_theme_stylebox_override("pressed", _box(Color(0.98, 0.8, 0.5), Color(0.6, 0.18, 0.08), 10, 1))
	resume_button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(0.6, 0.18, 0.08), 10, 1))
	resume_button.pressed.connect(close)
	foot.add_child(resume_button)
	# 两条路小样 v1: "放弃试炼" - only while the 梅花桩 trial runs (set_abandon_action)
	abandon_button = Button.new()
	abandon_button.text = ""
	abandon_button.focus_mode = Control.FOCUS_NONE
	abandon_button.add_theme_font_size_override("font_size", 10)
	abandon_button.add_theme_color_override("font_color", Color(1.0, 0.93, 0.85))
	abandon_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))
	abandon_button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 0.9))
	abandon_button.add_theme_stylebox_override("normal", _box(Color(0.55, 0.16, 0.1), Color(0.95, 0.75, 0.5), 10, 1))
	abandon_button.add_theme_stylebox_override("hover", _box(Color(0.7, 0.2, 0.12), Color(1.0, 0.85, 0.55), 10, 1))
	abandon_button.add_theme_stylebox_override("pressed", _box(Color(0.8, 0.25, 0.15), Color(1.0, 0.85, 0.55), 10, 1))
	abandon_button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(1.0, 0.85, 0.55), 10, 1))
	abandon_button.visible = false
	abandon_button.pressed.connect(abandon)
	foot.add_child(abandon_button)
	foot.add_theme_constant_override("separation", 10)
	# 中英文切换 v1: 「中文 | English」 on the pause page - a click switches the language of everything at once
	lang_box = HBoxContainer.new()
	lang_box.add_theme_constant_override("separation", 2)
	lang_box.add_child(_label(LANG_TEXT, 9, Color(0.85, 0.78, 0.6)))
	for opt in [["zh", "中文"], ["en", "English"]]:
		if opt[0] == "en":
			var bar := _label("|", 9, Color(0.8, 0.76, 0.7, 0.7))
			bar.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			lang_box.add_child(bar)
		var lb := Button.new()
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lb.text = opt[1]
		lb.flat = true
		lb.focus_mode = Control.FOCUS_NONE
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lb.add_theme_font_size_override("font_size", 9)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			lb.add_theme_stylebox_override(st, empty)
		var code: String = opt[0]
		lb.pressed.connect(func(): Lang.set_lang(code))
		lang_box.add_child(lb)
		lang_buttons[code] = lb
	_build_sound_rows(foot)
	foot.add_child(lang_box)
	show_page(0)


func _box(bg: Color, border: Color, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y + 1
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.92, 0.76, 0.45, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _fill_tip(tips: Array, text: String) -> String:
	if tips == TIPS_JIANGHU:
		return Jianghu.fill(text, Jianghu.numbers())
	return Step3.fill(text, Step3.numbers()) if tips == TIPS_STEP3 else Sample.fill(text)


## All text shown on the page (font check / tests).
static func all_text() -> String:
	var s := TITLE + KEYS_TITLE + TIPS_TITLE + RESUME_TEXT
	for k in KEYS:
		s += k[0] + k[1]
	for t in TIPS + TIPS_SAMPLE:
		s += t[0] + "：" + Sample.fill(t[1])
	for t in TIPS_STEP3:
		s += t[0] + "：" + Step3.fill(t[1], Step3.numbers())
	for t in TIPS_JIANGHU:
		s += t[0] + "：" + Jianghu.fill(t[1], Jianghu.numbers())
	s += PAGE_TEXT + PAGE_BUTTON_TEXT + ABANDON_KEY_TEXT + "0123456789"
	for row in SOUND_ROWS:
		s += row[1]
	s += "".join(sound_level_names()) + SOUND_HINT
	return s


## Shows tips page `i` (0 = TIPS, 1 = TIPS_SAMPLE, 2 = TIPS_STEP3, 3 = TIPS_JIANGHU).
func show_page(i: int) -> void:
	page = posmod(i, tip_pages.size())
	for j in tip_pages.size():
		tip_pages[j].visible = j == page
	page_label.text = PAGE_TEXT % [page + 1, tip_pages.size()]
	_refresh_sound()
	if is_open:
		_layout()


func turn_page(step: int) -> void:
	show_page(page + step)


## 两条路小样 v1: while the trial runs the page offers "放弃试炼" (button, or Q); `action` is called after the page has
## closed. An empty Callable / text removes the button.
func set_abandon_action(text: String, action: Callable) -> void:
	_abandon_action = action
	abandon_button.text = text + ABANDON_KEY_TEXT if text != "" else ""
	abandon_button.visible = text != "" and action.is_valid()
	if is_open:
		_layout()


func abandon() -> void:
	if not abandon_button.visible or not _abandon_action.is_valid():
		return
	var a := _abandon_action
	close()
	a.call()


## Title-screen help page: same content, own heading / button text, no pausing (see the class comment).
func configure_as_help(heading: String, back_text: String) -> void:
	help_only = true
	name = "HelpPage"
	title_label.text = heading
	resume_button.text = back_text
	rename_button.visible = false      # 改名与起名 v1: only in the game (the title screen names the hero at 新游戏)
	name_label.visible = false
	lang_box.visible = false


func _input(event: InputEvent) -> void:
	if rename_panel != null and rename_panel.is_open:
		return     # 改名与起名 v1: the naming box has the keyboard (it takes Esc itself; typed E / Q / arrows are letters)
	if help_only:
		if is_open and (event.is_action_pressed("pause", false) or event.is_action_pressed("interact", false)
				or (event is InputEventKey and event.pressed and not event.echo
				and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.physical_keycode == KEY_ENTER))):
			close()
			get_viewport().set_input_as_handled()
		elif is_open and _sound_key(event):
			get_viewport().set_input_as_handled()
		elif is_open and (event.is_action_pressed("move_left", false) or event.is_action_pressed("move_right", false)):
			turn_page(-1 if event.is_action_pressed("move_left", false) else 1)
			get_viewport().set_input_as_handled()
		return
	if not is_open and _modal_open():
		return     # 门派簿 / 序章 · 完 are on screen: Esc belongs to them
	if event.is_action_pressed("pause", false):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and _sound_key(event):
		get_viewport().set_input_as_handled()
	elif is_open and (event.is_action_pressed("move_left", false) or event.is_action_pressed("move_right", false)):
		turn_page(-1 if event.is_action_pressed("move_left", false) else 1)
		get_viewport().set_input_as_handled()
	elif is_open and (event.is_action_pressed("move_up", false) or event.is_action_pressed("move_down", false)):
		Lang.toggle()
		get_viewport().set_input_as_handled()
	elif is_open and abandon_button.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_Q or event.keycode == KEY_Q):
		abandon()
		get_viewport().set_input_as_handled()
	elif is_open and rename_button.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_R or event.keycode == KEY_R):
		open_rename()
		get_viewport().set_input_as_handled()
	elif is_open and (event.is_action_pressed("interact", false) or (event is InputEventKey and event.pressed and not event.echo
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.physical_keycode == KEY_ENTER))):
		close()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	var au := Sfx.service()
	if au != null and au.has_signal("levels_changed"):
		au.levels_changed.connect(_refresh_sound)
	_refresh_sound()
	Lang.on_changed(_on_lang_changed)
	_on_lang_changed(Lang.current())


func _on_lang_changed(_l: String) -> void:
	for code in lang_buttons:
		var c := Color(1.0, 0.88, 0.5) if code == Lang.current() else Color(0.8, 0.76, 0.7, 0.7)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			lang_buttons[code].add_theme_color_override(fc, c)
	_refresh_sound()                   # 音效 + 背景音乐 v1: the volume buttons are written in the new language
	_refresh_name()
	if is_open:
		_layout.call_deferred()        # the texts changed length: fit the page to the screen again


func _modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
		if n.is_open:
			return true
	return false


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	if not help_only:
		_was_paused = get_tree().paused
		get_tree().paused = true
	root.visible = true
	sound_focus = -1
	_refresh_name()
	show_page(0)
	_layout()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	if not help_only:
		get_tree().paused = _was_paused
	closed.emit()


## Centred, and never taller / wider than the screen (修复 v1): when the page would not fit, the tips column first gets
## wider (fewer wrapped lines); only if that is not enough the whole panel is scaled down a little.
const TIP_WIDTH := 238.0
const SCREEN_MARGIN := 3.0


func _layout() -> void:
	_balance_head()
	var vp := get_viewport().get_visible_rect().size
	var room := vp - Vector2(SCREEN_MARGIN, SCREEN_MARGIN) * 2.0
	panel.scale = Vector2.ONE
	var tw := TIP_WIDTH
	_set_tip_width(tw)
	var sz := panel.get_combined_minimum_size()
	while sz.y > room.y + 0.5 and sz.x + 12.0 <= room.x:
		tw += 12.0
		_set_tip_width(tw)
		sz = panel.get_combined_minimum_size()
	panel.size = sz
	var k := minf(1.0, minf((room.x + 0.5) / sz.x, (room.y + 0.5) / sz.y))   # (half a pixel: text heights are not whole pixels)
	panel.scale = Vector2(k, k)
	panel.position = ((vp - sz * k) * 0.5).round()


func _set_tip_width(w: float) -> void:
	for pg in tip_pages:
		for l in pg.get_children():
			if l is Label:
				l.custom_minimum_size = Vector2(w, 0)
	panel.reset_size()


# ------------------------------------------------------------------ 改名与起名 v1: rename
## The name on the left and the button on the right get the same width, so the heading stays in the middle.
func _balance_head() -> void:
	if name_label == null or rename_button == null:
		return
	name_label.custom_minimum_size = Vector2.ZERO
	rename_button.custom_minimum_size = Vector2.ZERO
	if not rename_button.visible:
		return
	var w := maxf(name_label.get_combined_minimum_size().x, rename_button.get_combined_minimum_size().x)
	name_label.custom_minimum_size = Vector2(w, 0)
	rename_button.custom_minimum_size = Vector2(w, 0)


func _refresh_name() -> void:
	if name_label != null:
		name_label.text = PlayerName.ui("name_line").replace("{0}", PlayerName.value())


## 「改名（R）」: the naming box over the page (the game stays paused); 确定 renames at once (free), Esc / 取消 does not.
func open_rename() -> void:
	if help_only or not is_open or not rename_button.visible:
		return
	if rename_panel == null:
		rename_panel = NamingPanel.new()
		add_child(rename_panel)
		rename_panel.confirmed.connect(_on_renamed)
	if not rename_panel.is_open:
		rename_panel.open("rename")


func _on_renamed(n: String) -> void:
	_refresh_name()
	_layout.call_deferred()
	if OS.has_feature("web"):
		print("naming: renamed")
	hero_renamed.emit(n)


# ------------------------------------------------------------------ 音效 + 背景音乐 v1: volume in the bottom row
## The level names (data/audio.json "volume_levels"; 关 / 小 / 中 / 大 without it).
static func sound_level_names() -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	if d is Dictionary and d.get("volume_levels") is Array and not (d["volume_levels"] as Array).is_empty():
		return (d["volume_levels"] as Array).map(func(v): return String(v.get("name", "")))
	return SOUND_LEVELS


func _build_sound_rows(foot: HBoxContainer) -> void:
	var box := HBoxContainer.new()
	box.name = "Sound"
	box.add_theme_constant_override("separation", 2)
	for row in SOUND_ROWS:
		var kind: String = row[0]
		var b := Button.new()
		b.name = "Sound_" + kind
		b.focus_mode = Control.FOCUS_NONE
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # written in the current language by _refresh_sound
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(_on_sound_clicked.bind(kind))
		box.add_child(b)
		sound_buttons[kind] = b
	foot.add_child(box)


## A click moves the level on: 关 -> 小 -> 中 -> 大 -> 关.
func _on_sound_clicked(kind: String) -> void:
	_on_sound_pressed(kind, (Sfx.volume(kind) + 1) % sound_level_names().size())


func _on_sound_pressed(kind: String, level: int) -> void:
	Sfx.set_volume(kind, level)
	_refresh_sound()
	if kind == "sfx":
		Sfx.play("choice_move")          # the new loudness, heard at once


## Tab picks a volume button (音乐 -> 音效 -> none); ← / → change the picked one. True when the key was used.
func _sound_key(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB):
		sound_focus = posmod(sound_focus + 2, SOUND_ROWS.size() + 1) - 1
		_refresh_sound()
		return true
	if sound_focus >= 0 and (event.is_action_pressed("move_left", true) or event.is_action_pressed("move_right", true)):
		var kind: String = SOUND_ROWS[sound_focus][0]
		var step := -1 if event.is_action_pressed("move_left", true) else 1
		var lv := clampi(Sfx.volume(kind) + step, 0, sound_level_names().size() - 1)
		if lv != Sfx.volume(kind):
			_on_sound_pressed(kind, lv)
		return true
	return false


## The text of a volume button now: "音乐：中" / "Music: Mid".
func sound_text(kind: String) -> String:
	var row: Array = SOUND_ROWS[0] if kind == SOUND_ROWS[0][0] else SOUND_ROWS[1]
	var names := sound_level_names()
	var lv := clampi(Sfx.volume(kind), 0, names.size() - 1)
	if Lang.is_en():
		return "%s: %s" % [Lang.t(row[1]), Lang.t(names[lv])]
	return "%s：%s" % [row[1], names[lv]]


func _refresh_sound() -> void:
	if page_label != null and not tip_pages.is_empty():
		page_label.text = SOUND_HINT if sound_focus >= 0 else PAGE_TEXT % [page + 1, tip_pages.size()]
	for i in SOUND_ROWS.size():
		var kind: String = SOUND_ROWS[i][0]
		if not sound_buttons.has(kind):
			continue
		var b: Button = sound_buttons[kind]
		b.text = sound_text(kind)
		var picked := sound_focus == i
		var fc := Color(0.27, 0.14, 0.1) if picked else Color(1.0, 0.93, 0.7)
		for c in ["font_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, fc)
		b.add_theme_color_override("font_hover_color", fc if picked else Color(1.0, 0.88, 0.5))
		var sb := _box(Color(1.0, 0.88, 0.5), Color(0.6, 0.18, 0.08), 3, 0) if picked \
			else _box(Color(0.2, 0.15, 0.13, 0.9), Color(0.75, 0.6, 0.4), 3, 0)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
