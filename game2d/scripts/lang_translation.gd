class_name LangTranslation
extends Translation
## 中英文切换 v1: Chinese -> English for every text on screen (see scripts/lang.gd).
##
## data/i18n/en.json (and every data/i18n/en_*.json) "lines" maps a Chinese text to its English text. A line may hold placeholders {0} {1} ... in both
## languages: then it is a template that matches any text with something in those places ("小食摊今日收入 +{0}" also
## matches "小食摊今日收入 +25"), and what stood in a placeholder is translated too (a name, a place).
## A text of several lines that has no entry of its own is translated line by line.
## Nothing found -> the Chinese text stays (and, when GAME_LANG_LOG is set, it is written to that file at exit - the
## tests use this to prove nothing on screen was left untranslated).

const DATA := "res://data/i18n/en.json"
const CJK := "[\\x{3400}-\\x{9fff}\\x{3000}-\\x{303f}\\x{ff00}-\\x{ffef}]"

var active := false
var exact := {}                 # Chinese -> English
var templates := []             # [{re: RegEx, en: String, n: int}] most specific first
var cache := {}
var missing := {}               # texts with Chinese that had no English (only filled while logging)
var logging := false
var _cjk := RegEx.create_from_string(CJK)


func _init() -> void:
	logging = OS.get_environment("GAME_LANG_LOG") != ""
	reload()


func reload() -> void:
	exact.clear()
	templates.clear()
	cache.clear()
	# en.json plus every en_*.json beside it (each part of the game can keep its own English file)
	var lines := {}
	var files := [DATA]
	for f in DirAccess.get_files_at(DATA.get_base_dir()):
		if f.begins_with("en_") and f.ends_with(".json"):
			files.append(DATA.get_base_dir().path_join(f))
	for path in files:
		var doc = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if doc is Dictionary:
			lines.merge(doc.get("lines", {}), true)
	var tpl := []
	for zh in lines:
		var en := String(lines[zh])
		if String(zh).begins_with("_"):
			continue
		if "{0}" in String(zh):
			tpl.append([String(zh), en])
		else:
			exact[String(zh)] = en
	# the template with the most fixed text wins ("{0}：{1}" is the last resort)
	tpl.sort_custom(func(a, b): return _fixed_len(a[0]) > _fixed_len(b[0]))
	for p in tpl:
		var re := RegEx.create_from_string(_pattern(p[0]))
		if re.is_valid():
			# loose = nothing but placeholders and spaces / dots ("{0} {1}", "{0}. {1}"): tried only when nothing else fits
			var fixed := RegEx.create_from_string("\\{\\d\\}").sub(String(p[0]), "", true)
			templates.append({"re": re, "en": p[1], "zh": p[0], "loose": fixed.strip_edges().replace(".", "") == ""})


func _fixed_len(s: String) -> int:
	return RegEx.create_from_string("\\{\\d\\}").sub(s, "", true).length()


## "目标：{0}" -> ^目标：(.+?)$  (everything else literal; the placeholders may hold anything, newlines too)
func _pattern(zh: String) -> String:
	var out := "^"
	var i := 0
	var ph := RegEx.create_from_string("\\{(\\d)\\}")
	for m in ph.search_all(zh):
		out += _escape(zh.substr(i, m.get_start() - i)) + "(?<p%s>[\\s\\S]+?)" % m.get_string(1)
		i = m.get_end()
	return out + _escape(zh.substr(i)) + "$"


func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in "\\^$.|?*+()[]{}" else c
	return out


func has_cjk(s: String) -> bool:
	return _cjk.search(s) != null


func _get_message(src_message: StringName, _context: StringName = &"") -> StringName:
	if not active:
		return &""
	var s := String(src_message)
	if not has_cjk(s):
		return &""
	return StringName(translate_text(s))


func translate_text(s: String) -> String:
	return _tr(s, true)


## log = only for whole texts shown on screen (parts tried while matching are not "missing" on their own)
func _tr(s: String, log := false) -> String:
	if not has_cjk(s):
		return s
	if cache.has(s):
		var hit: String = cache[s]
		if log and logging and has_cjk(hit):
			missing[s] = true
		return hit
	var out = _find(s)
	if out == null:
		out = s
	cache[s] = out
	if log and logging and has_cjk(String(out)):
		missing[s] = true
	return out


## English for `s`, or null when there is none.
func _find(s: String) -> Variant:
	if exact.has(s):
		return exact[s]
	var st := s.strip_edges()
	if st != s and st != "":
		var inner = _find(st)
		if inner != null:
			return s.replace(st, String(inner))
	var partial: Variant = null
	if "\n" in s:
		var parts := []
		for line in s.split("\n"):
			parts.append(_tr(line))
		var joined := "\n".join(parts)
		if not has_cjk(joined):
			return joined
		partial = joined
	var tp = _template(s, false)
	if tp != null and not has_cjk(String(tp)):
		return tp
	# lists the game builds itself: "A · B · C", "黄鼠狼、拦路山贼、黑虎"
	for sep in [" · ", "、"]:
		if sep in s:
			var bits := []
			for b in s.split(sep):
				bits.append(_tr(b))
			var joined2 := (" · " if sep == " · " else ", ").join(bits)
			if not has_cjk(joined2):
				return joined2
	# last resort: the loose patterns "{0} {1}" (two pieces side by side)
	var loose = _template(s, true)
	if loose != null and not has_cjk(String(loose)):
		return loose
	if tp != null:
		return tp
	return partial if partial != null else loose


## The first template (specific ones, or only the loose "{0} {1}" kind) whose pieces all translate; else the first
## match with a piece left Chinese; else null.
func _template(s: String, loose: bool) -> Variant:
	var fallback: Variant = null
	for t in templates:
		if bool(t["loose"]) != loose:
			continue
		var m: RegExMatch = t["re"].search(s)
		if m == null:
			continue
		var en := String(t["en"])
		for name in m.names:
			en = en.replace("{%s}" % name.trim_prefix("p"), _tr(m.get_string(name)))
		if not has_cjk(en):
			return en
		if fallback == null:
			fallback = en
	return fallback
