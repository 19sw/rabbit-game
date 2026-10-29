class_name SkillTunaStats
extends Resource
## 吐纳功（内功）数值卡（配置资产层）。文件：game2d/cards/skills/tuna.tres。学会就自动运转。
## 数值来源：docs/design/武学与经营-第一批-方案-v1.md 第一节 2「三招的数字」（tests/skills_suite.gd 逐项比对）。

## 生命上限加成（100 -> 120）。走 Skills.set_max_hp_bonus("tuna", ...)，和药膳（+15）叠加
@export var max_hp_bonus := 20
## 脱战回血的等待（秒），代替主角卡的 regen_delay（5 -> 3）
@export var regen_delay := 3.0
## 脱战回血速度（点/秒），代替主角卡的 regen_per_sec（3 -> 5）
@export var regen_per_sec := 5.0
