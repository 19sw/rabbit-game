extends Node
## Autoload "LangService" (中英文切换 v1; scripts use it through the static class Lang, scripts/lang_api.gd): which language the game is played in, and the one translator every text goes through.
##
## How it works: all the game's wording stays Chinese in the code and data files. Godot shows every Label / Button
## through the TranslationServer, so `LangTranslation` (registered here) turns each Chinese text into English when the
## language is English - whole lines from data/i18n/en.json, and lines with numbers / names in them from its templates
## ("铜钱 {0}" -> "Coins {0}"). Switching the language re-draws every text on screen at once.
## The choice is a setting, not part of the save: user://settings.cfg, and on the web also localStorage "aw_lang" (the
## loading page reads the same key, so its 「中文 | English」 switch and the game's agree).
## First start: the browser's / system's language (Chinese -> 中文, anything else -> English).

signal changed(lang: String)

const LANGS := ["zh", "en"]
const SETTINGS := "user://settings.cfg"
const WEB_KEY := "aw_lang"

var lang := "zh"
var translation: LangTranslation


func _ready() -> void:
	translation = LangTranslation.new()
	translation.locale = "en"
	TranslationServer.add_translation(translation)
	var start := _stored()
	if start == "":
		start = _detect()
	_apply(start, false)


## "zh" / "en". Saves the choice and re-draws everything.
func set_lang(l: String) -> void:
	if not l in LANGS or l == lang:
		return
	_apply(l, true)


## The loading page's 「中文 | English」 may have been clicked after this autoload started: the title screen asks again.
func sync_web() -> void:
	if not OS.has_feature("web") or OS.get_environment("GAME_LANG") in LANGS:
		return
	var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % WEB_KEY)
	if str(v) in LANGS and str(v) != lang:
		_apply(str(v), false)


func toggle() -> void:
	set_lang("en" if lang == "zh" else "zh")


func is_en() -> bool:
	return lang == "en"


## The text as the player sees it now (for code that measures or pages text itself, e.g. the dialogue box).
func t(text: String) -> String:
	if lang == "zh" or text == "":
		return text
	return translation.translate_text(text)


func _apply(l: String, save: bool) -> void:
	lang = l
	translation.active = l == "en"
	TranslationServer.set_locale("en" if l == "en" else "zh")
	if save:
		_store(l)
	changed.emit(l)


func _stored() -> String:
	var env := OS.get_environment("GAME_LANG")          # tests / screenshots pick the language explicitly
	if env in LANGS:
		return env
	if DisplayServer.get_name() == "headless":
		return "zh"                                       # automated runs default to Chinese whatever the machine says
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % WEB_KEY)
		if str(v) in LANGS:
			return str(v)
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		var s := str(cf.get_value("game", "lang", ""))
		if s in LANGS:
			return s
	return ""


func _store(l: String) -> void:
	if OS.get_environment("GAME_LANG") in LANGS or DisplayServer.get_name() == "headless":
		return                                            # tests never overwrite the player's setting
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('%s','%s')}catch(e){}" % [WEB_KEY, l])
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("game", "lang", l)
	cf.save(SETTINGS)


## Tests: GAME_LANG_LOG=<file> - every text that was on screen in English mode but had no English is listed there.
func _exit_tree() -> void:
	if translation == null:
		return
	var path := OS.get_environment("GAME_LANG_LOG")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(translation.missing.keys(), "\t"))
	# the translator is a script object: hand it back before the engine shuts its scripting down (it crashed at quit)
	TranslationServer.remove_translation(translation)
	translation = null


func _detect() -> String:
	var loc := OS.get_locale_language()
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("(navigator.languages&&navigator.languages[0])||navigator.language||''")
		loc = str(v)
	return "zh" if loc.to_lower().begins_with("zh") else "en"
