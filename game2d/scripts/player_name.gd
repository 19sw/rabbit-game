class_name PlayerName
extends RefCounted
## 改名与起名 v1 (docs/design/游戏改名与主角起名-方案-v1.md): the hero's name, chosen by the player.
##
## The data files write the hero's name as the token {name} (story / jianghu / sample / step3 lines, the speaker name
## of "rabbit", the 门派簿 line); fill() puts the name in when the text is shown (Dialogue.say, the 委托 thanks, the
## 门派簿). English: data/i18n/en*.json keep those lines as {0}-templates ("{0}来啦。…" -> "Here comes {0}. …"), so the
## translator translates the filled line and the name inside it: the default 小兔 becomes Little Rabbit, the random
## names have English too (阿糯 -> Mochi), any other name stays as typed.
## Not names (left alone): 小兔子 (the opening's "a little rabbit", a bandit's 哪来的小兔子), 兔子, 兔儿 / 徒儿 (师父),
## 师兄 (师弟), every NPC's name.
## The name is part of the save (state.player.name; an older save has none -> 小兔). Static, so it outlives the switch
## from the title screen to the game scene; 新游戏 sets it from the naming panel (scripts/naming_panel.gd).

const DATA := "res://data/naming.json"
const TOKEN := "{name}"
const DEFAULT := "小兔"
const FONT_PATH := "res://fonts/ui_font.fnt"
const HARD_MAX := 24              # never more characters than this, whatever the language (spaces included)

static var current := DEFAULT
static var changes := 0           # statistics (tests)
static var _data: Dictionary = {}
static var _font: Font = null


## naming.json (texts, limits, the random names).
static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
		_data = d if d is Dictionary else {}
	return _data


static func ui(key: String) -> String:
	return String(data().get("ui", {}).get(key, key))


static func value() -> String:
	return current


static func choose(n: String) -> void:
	n = n.strip_edges()
	if n == "":
		n = DEFAULT
	if n != current:
		changes += 1
	current = n


static func reset() -> void:
	current = DEFAULT


## `text` with the hero's name in place of {name}.
static func fill(text: String) -> String:
	return fill_with(text, current)


static func fill_with(text: String, n: String) -> String:
	return text.replace(TOKEN, n) if TOKEN in text else text


## R1: the length rule depends on the characters, never on the UI language: at most 5 汉字 (naming.json max_chars),
## a name of letters at most 12 (max_letters_en); spaces are not counted. Mixed names share the room: a 汉字 (any wide
## CJK / full-width character) weighs max_letters_en, a letter max_chars, the total at most max_chars * max_letters_en
## (3 汉字 + 4 letters fit; 5 汉字 + 1 letter do not) - so no name ever holds more than 5 汉字.
static func max_hanzi() -> int:
	return int(data().get("max_chars", 5))


static func max_letters() -> int:
	return int(data().get("max_letters_en", 12))


static func is_wide(ch: String) -> bool:
	return ch.unicode_at(0) >= 0x2E80


## Weight of a name against the room max_hanzi() * max_letters() (spaces weigh nothing).
static func weight(n: String) -> int:
	var w := 0
	for ch in n:
		if ch == " " or ch == "　" or ch == "\t":
			continue
		w += max_letters() if is_wide(ch) else max_hanzi()
	return w


static func fits(n: String) -> bool:
	return weight(n.strip_edges()) <= max_hanzi() * max_letters() and n.length() <= HARD_MAX


## Characters that count against the limit (everything but spaces).
static func counted(n: String) -> int:
	var k := 0
	for ch in n:
		if ch != " " and ch != "　" and ch != "\t":
			k += 1
	return k


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


## First character the game's font cannot draw ("" = every one can).
static func missing_char(n: String) -> String:
	var f := font()
	for ch in n:
		var c := ch.unicode_at(0)
		if c == 0x20 or c == 0x3000:
			continue
		if c < 0x20 or c == 0x7F or (f != null and not f.has_char(c)):
			return ch
	return ""


## Checks a typed name: {ok: bool, name: String (trimmed), error: "" | "empty" | "too_long" | "missing_char", char}.
static func validate(typed: String) -> Dictionary:
	var n := typed.strip_edges()
	n = n.replace("　", " ").strip_edges()       # full-width spaces count as spaces (all-space names are empty)
	if n == "":
		return {"ok": false, "name": n, "error": "empty", "char": ""}
	var bad := missing_char(n)
	if bad != "":
		return {"ok": false, "name": n, "error": "missing_char", "char": bad}
	if not fits(n):
		return {"ok": false, "name": n, "error": "too_long", "char": ""}
	return {"ok": true, "name": n, "error": "", "char": ""}


## The message for an error code (Chinese; English through data/i18n like every other text).
static func error_text(code: String) -> String:
	if code == "":
		return ""
	return String(data().get("errors", {}).get(code, code))


## The random names (Chinese; in English each is shown in its English form, see shown()).
static func random_names() -> Array:
	return data().get("random_names", [])


## The name as the player sees it in the naming box now: in English the default / random names in their English form.
static func shown(n: String) -> String:
	return Lang.t(n) if Lang.is_en() else n


## Back from what was typed to the name kept: when the English form of the default or of a random name was typed (or
## left there), the Chinese original is kept - it then shows in its own form in either language.
static func canonical(n: String) -> String:
	if not Lang.is_en():
		return n
	for c in [DEFAULT] + random_names():
		if Lang.t(String(c)) == n:
			return String(c)
	return n


## A name read from a save: a string that passes the checks for either language, else the default (an older save, or a
## name the font of this version cannot draw, still loads).
static func from_save(v: Variant) -> String:
	if not (v is String):
		return DEFAULT
	var n := String(v).strip_edges()
	if n == "" or missing_char(n) != "" or not fits(n):
		return DEFAULT        # R1: too long for the rule (e.g. 12 汉字 written by hand) -> 小兔, the save still loads
	return n
