class_name Economy
extends RefCounted
## 两条路小样 v1: the economy table (外部文件层) - data/economy.json: 本钱, trial rewards, the repeat reward, the food
## stall's daily income and hour, the three repairs (price, 家业 points, who to ask), 名望 points per trial tier.
## No numbers live in code: everything is read from the file (tests/sample_suite.gd compares it with the plan).

const PATH := "res://data/economy.json"
const TIERS := ["bronze", "silver", "gold"]      # worst -> best
const REPAIRS := ["roof", "dorm_old", "kitchen"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		reload()
	return _data


static func reload() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Economy: cannot read " + PATH)
		parsed = {}
	_data = parsed


static func start_coins() -> int:
	return int(data().get("start_coins", 0))


static func trial_reward(tier: String) -> int:
	return int(data().get("trial_rewards", {}).get(tier, 0))


static func trial_repeat() -> int:
	return int(data().get("trial_repeat", 0))


static func tiers_cumulative() -> bool:
	return bool(data().get("trial_tiers_cumulative", true))


static func stall_income() -> int:
	return int(data().get("stall_income", 0))


static func stall_hour() -> float:
	return float(data().get("stall_hour", 8))


static func repair(id: String) -> Dictionary:
	return data().get("repairs", {}).get(id, {})


static func price(id: String) -> int:
	return int(repair(id).get("price", 0))


static func fame_points(tier: String) -> int:
	return int(data().get("fame", {}).get(tier, 0))


## Sect-book points a story flag adds to a track: 名望 "trial_<tier>", 家业 "repair_<id>" (0 for every other flag).
static func points_for(track: String, flag: String) -> int:
	if track == "fame" and flag.begins_with("trial_"):
		return fame_points(flag.trim_prefix("trial_"))
	if track == "estate" and flag.begins_with("repair_"):
		return int(repair(flag.trim_prefix("repair_")).get("estate", 0))
	return 0


## Which tiers a finishing time earns (card thresholds): [] = too slow; cumulative -> every tier whose line it is within.
static func tiers_for_time(seconds: float, card: TrialCard) -> Array:
	var out := []
	if seconds <= card.bronze_seconds:
		out.append("bronze")
	if seconds <= card.silver_seconds:
		out.append("silver")
	if seconds <= card.gold_seconds:
		out.append("gold")
	return out


## Best tier of a time ("" = none).
static func best_tier(seconds: float, card: TrialCard) -> String:
	var t := tiers_for_time(seconds, card)
	return "" if t.is_empty() else String(t[t.size() - 1])


# ------------------------------------------------------------------ 第③步 (docs/design/第三步-擂台与收徒-方案-v1.md)
## The 比武大会 rules (economy.json "arena"): interval_days, open_hour, close_hour, fee, rounds, lose_fraction,
## between_heal, first_win_coins / first_win_fame, win_coins / win_fame, fame_max.
static func arena() -> Dictionary:
	return data().get("arena", {})


static func arena_int(key: String) -> int:
	return int(arena().get(key, 0))


static func arena_float(key: String) -> float:
	return float(arena().get(key, 0.0))


## 补充 v1.1: the 困难 rewards (economy.json arena.hard): first_win_coins, first_win_fame, win_coins, win_fame.
static func arena_hard(key: String) -> int:
	return int(arena().get("hard", {}).get(key, 0))


## The 收徒 rules (economy.json "disciple"): conditions, upkeep, day / night hours, jobs.
static func disciple() -> Dictionary:
	return data().get("disciple", {})


static func disciple_int(key: String) -> int:
	return int(disciple().get(key, 0))


static func job(id: String) -> Dictionary:
	return disciple().get("jobs", {}).get(id, {})
