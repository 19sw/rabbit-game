class_name VillainStats
extends EnemyStats
## 悬赏恶人数值卡（配置资产层，第④步第一批）：在普通敌人数值卡上多两组 —— 逃跑（黄鼠狼 cards/weasel.tres）和发怒 + 扑击
## （黑虎 cards/tiger.tres）。数值来源：docs/design/第四步-第一批-悬赏与委托-方案-v1.md 第二节的表（生命、伤害、前摇、移动速度
## 照表；其余是手感参数）。其他敌人仍是 EnemyStats，没有这些项（Fighter 按"不会逃、不会怒"处理）。

@export_group("逃跑（血掉到一定比例时跑开一段，再回头打）")
## 生命 ≤ 最大生命 × 这个比例时逃跑一次（0 = 不会逃）
@export var flee_at := 0.0
## 逃跑多少秒
@export var flee_time := 0.0
## 逃跑速度（像素/秒）
@export var flee_speed := 0.0
## 逃完回头后，多快出第一招（秒）
@export var flee_return_wait := 0.3

@export_group("发怒（血掉到一定比例时发怒一次）")
## 生命 ≤ 最大生命 × 这个比例时发怒（0 = 不会发怒）
@export var rage_at := 0.0
## 发怒怒吼用时（这段时间不出招、打不出硬直）
@export var rage_time := 0.0
## 发怒后出招间隔乘以这个数（0.7 = 缩短三成）
@export var rage_interval_factor := 1.0
## 发怒后每次出招是扑击的概率（0 = 不扑）
@export var pounce_chance := 0.0
## 离你多远以内会起扑
@export var pounce_range := 0.0
## 扑击冲出的距离（像素）
@export var pounce_lunge := 0.0
## 扑击用时（秒）
@export var pounce_time := 0.0
