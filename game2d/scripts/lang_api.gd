class_name Lang
extends RefCounted
## 中英文切换 v1: the language, for every script (static calls: Lang.t(text), Lang.is_en(), Lang.set_lang("en") ...).
## The state lives in the autoload node "LangService" (scripts/lang.gd); this class only reaches it, so scripts compile
## even where autoload names are not known yet (the headless test runner).

static func service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("LangService") if tree != null and tree.root != null else null


## "zh" / "en"
static func current() -> String:
	var s := service()
	return s.lang if s != null else "zh"


static func is_en() -> bool:
	return current() == "en"


## The text as the player sees it now (Chinese as it is; in English through data/i18n/en.json).
static func t(text: String) -> String:
	var s := service()
	return s.t(text) if s != null else text


static func set_lang(l: String) -> void:
	var s := service()
	if s != null:
		s.set_lang(l)


static func toggle() -> void:
	var s := service()
	if s != null:
		s.toggle()


static func sync_web() -> void:
	var s := service()
	if s != null:
		s.sync_web()


## Calls f(lang) whenever the language changes.
static func on_changed(f: Callable) -> void:
	var s := service()
	if s != null:
		s.changed.connect(f)


static func translation() -> LangTranslation:
	var s := service()
	return s.translation if s != null else null
