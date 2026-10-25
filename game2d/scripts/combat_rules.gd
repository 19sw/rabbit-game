class_name CombatRules
extends Resource
## 战斗通用规则卡（配置资产层）：game2d/cards/combat_rules.tres。
## 数值来源：docs/design/战斗数据方案-v1.2.md 第 4.1 节。

## 背后倍率（预留，1 = 不加成）
@export var back_multiplier := 1.0
## 难度倍率（预留）
@export var difficulty_multiplier := 1.0
## 顿帧：普通命中时画面停顿多少秒
@export var hitstop := 0.05
## 顿帧：反击命中
@export var counter_hitstop := 0.08
## 复活时恢复多少生命（1 = 回满）
@export var respawn_heal_fraction := 1.0
## 被打倒后黑屏多少秒再复活
@export var death_seconds := 1.5
## 切磋结束后结果显示多少秒
@export var spar_result_seconds := 2.5
