class_name Tuning
extends RefCounted
## Loads data/tuning.json (外部文件层：调参数据). Nothing in here has built-in defaults on purpose:
## the numbers live in the file, so the client can change them without touching code.

const PATH := "res://data/tuning.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		reload()
	return _data


static func reload() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Tuning: cannot read " + PATH)
		parsed = {}
	_data = parsed


static func day_seconds() -> float:
	return float(data()["day_length_minutes"]) * 60.0


static func color(a: Array) -> Color:
	return Color(a[0], a[1], a[2])
