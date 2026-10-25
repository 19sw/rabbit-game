class_name Objectives
extends RefCounted
## The prologue's objective list, read from data/objectives.json (外部文件层): the "左上角目标文字" of the script table
## (v4: 11 texts - step 1 has three: "擦干地上的水", "看看桌上的字条", "去练武场找师兄"), each with where the minimap
## star points (star: {npc} / {object} / {pos} / {thing} / {first_of: [spec with "unless" flag, ...]}). Which one is
## current is decided by the story (scripts/story.gd): story stage 0 (after the opening) starts on entry 0
## "擦干地上的水", the story switches to "看看桌上的字条" by id (set_step); stage N >= 1 = entry N + 1; index -1 = no
## objective yet (while the opening conversation runs).

const PATH := "res://data/objectives.json"

signal changed

const OPENING_EXTRA := 1    # entries before "去练武场找师兄" beyond stage 0's own (擦干地上的水 + 看看桌上的字条)

var steps: Array = []
var index := -1


func _init(path := PATH) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Objectives: cannot read " + path)
		return
	steps = parsed.get("steps", [])


## Back to step 1 "去练武场找师兄" (used by the legacy test suites through Story.enter_sandbox()).
func reset() -> void:
	set_stage(1)


## Story stage 0..9 -> entry: stage 0 = the first entry of the opening (擦干地上的水), stage N >= 1 = entry N + 1.
func set_stage(stage: int) -> void:
	set_index(-1 if stage < 0 else (0 if stage == 0 else stage + OPENING_EXTRA))


## Switch to the entry with this id (the opening's sub-steps: wipe_floor -> read_note).
func set_step(id: String) -> void:
	for i in steps.size():
		if String(steps[i].get("id", "")) == id:
			set_index(i)
			return
	push_error("Objectives: no step " + id)


func set_index(i: int) -> void:
	index = clampi(i, -1, steps.size() - 1)
	changed.emit()


func has_current() -> bool:
	return index >= 0 and index < steps.size()


func current() -> Dictionary:
	return steps[index] if has_current() else {}


func current_text() -> String:
	return String(current().get("text", ""))


## Text for the HUD line: "目标：…" (or the plain text for the last step, "" when there is none).
func hud_text(prefix: String) -> String:
	if not has_current():
		return ""
	return current_text() if current().get("plain", false) else prefix + current_text()


## Star spec of the current step (null when the step has no star). `solved` = the grove puzzle is solved.
func star_spec(solved := false, flags: Dictionary = {}) -> Variant:
	if not has_current():
		return null
	var c := current()
	if solved and c.has("star_after_puzzle"):
		return c["star_after_puzzle"]
	var spec: Variant = c.get("star", null)
	if spec is Dictionary and spec.has("first_of"):
		for s in spec["first_of"]:
			if not (s.has("unless") and flags.get(String(s["unless"]), false)):
				return s
		return null
	return spec
