class_name DayNight
extends Node
## 24-hour clock + colour curve. All numbers come from data/tuning.json (Tuning).
## hour: 0.0 .. 24.0.  One game day = day_length_minutes of real time.

var hour := 8.0
var total_hours := 8.0      # 两条路小样 v1: hours since day 0 00:00, only ever goes forward (daily income, save)
var running := true
var _periods: Array = []


func _init() -> void:
	var d := Tuning.data()
	hour = float(d["start_hour"])
	total_hours = hour
	_periods = d["periods"]


func _process(delta: float) -> void:
	if running:
		advance_seconds(delta)


func advance_seconds(real_seconds: float) -> void:
	advance_hours(real_seconds * 24.0 / Tuning.day_seconds())


func advance_hours(h: float) -> void:
	hour = fposmod(hour + h, 24.0)
	total_hours += maxf(h, 0.0)


func skip() -> void:
	advance_hours(float(Tuning.data()["time_skip_hours"]))


## Jumps the clock to hour h (the day counter moves forward to the next time it is h o'clock, or stays when it is h now).
func set_hour(h: float) -> void:
	total_hours += fposmod(h - hour, 24.0)
	hour = fposmod(h, 24.0)


## Day number (0 = the first day) counted from `boundary` o'clock: the day changes each time the clock passes it.
func day_index(boundary := 0.0) -> int:
	return int(floor((total_hours - boundary) / 24.0))


## Restores a saved clock (both the hour and the forward counter).
func restore(h: float, total: float) -> void:
	hour = fposmod(h, 24.0)
	total_hours = total


## "酉时 18:00"
func clock_text() -> String:
	var minutes := int(floor(hour * 60.0)) % 1440
	var names: Array = Tuning.data()["shichen"]
	var idx := int(floor((float(minutes) / 60.0 + 1.0) / 2.0)) % 12   # 23:00-01:00 = 子
	return "%s时 %02d:%02d" % [names[idx], minutes / 60, minutes % 60]


## Interpolated look at the current hour: {tint, desaturate, vignette, name}.
func look() -> Dictionary:
	var a: Dictionary = _periods[0]
	var b: Dictionary = _periods[_periods.size() - 1]
	for i in range(_periods.size() - 1):
		if hour >= float(_periods[i]["hour"]) and hour <= float(_periods[i + 1]["hour"]):
			a = _periods[i]
			b = _periods[i + 1]
			break
	var span := float(b["hour"]) - float(a["hour"])
	var f := 0.0 if span <= 0.0 else smoothstep(0.0, 1.0, (hour - float(a["hour"])) / span)
	var ca := Tuning.color(a["tint"])
	var cb := Tuning.color(b["tint"])
	return {
		"tint": ca.lerp(cb, f),
		"desaturate": lerpf(float(a["desaturate"]), float(b["desaturate"]), f),
		"vignette": lerpf(float(a["vignette"]), float(b["vignette"]), f),
		"name": a["name"] if f < 0.5 else b["name"],
	}


## 0 = lanterns off (daytime) .. 1 = fully lit (evening / night), smooth ramps at dusk and dawn.
func lamp_level() -> float:
	var l: Dictionary = Tuning.data()["lamps"]
	var h := hour
	if h >= float(l["on_start"]):
		return smoothstep(float(l["on_start"]), float(l["on_full"]), h)
	if h <= float(l["off_end"]):
		return 1.0 - smoothstep(float(l["off_start"]), float(l["off_end"]), h)
	return 0.0
