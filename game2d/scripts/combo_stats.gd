class_name ComboStats
extends EnemyStats
## 连打数值卡（配置资产层，补充 v1.1 困难难度）：在普通敌人数值卡上多两项 —— 困难·猴子 cards/monkey_hard.tres 用它。
## 普通的数值卡（师兄、狼、野猪、擂台对手）仍是 EnemyStats，没有这两项（Fighter 按 1 下处理）。

@export_group("连打")
## 每次出招连打几下（1 = 一下）
@export var strikes_per_attack := 2
## 连打时两下之间停多少秒（不再前摇；比主角被打后的保护时间 + 出招时间长，第二下才打得到）
@export var combo_gap := 0.5
