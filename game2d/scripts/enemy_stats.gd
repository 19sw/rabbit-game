class_name EnemyStats
extends Resource
## 敌人数值卡（配置资产层）：师兄 shixiong.tres、狼 wolf.tres、野猪 boar.tres（game2d/cards/）。
## 数值来源：docs/design/战斗数据方案-v1.2.md 第 4.3、4.4 节（附录 A 有逐项对照，自动测试会比对）。
## 时间单位：秒；距离：像素（1 格 = 32 px）；速度：像素/秒。

@export_group("生命与移动")
## 生命
@export var max_hp := 30
## 移动速度（像素/秒）
@export var move_speed := 95.0
## 身体受击圈半径
@export var body_radius := 10.0
## 转身时间（转半圈要多少秒）
@export var turn_time := 0.3

@export_group("出招")
## 离你多近开始前摇
@export var attack_range := 46.0
## 追击时停在离你多远
@export var stop_distance := 38.0
## 出招方式：strike = 原地出招（可带前冲），出招第一刻判定；charge = 冲撞，冲撞全程身体周围都能撞到人
@export_enum("strike", "charge") var attack_kind := "strike"
## 命中圈中心在身前多少像素（冲撞填 0：以身体为中心）
@export var hit_offset := 34.0
## 命中圈半径
@export var hit_radius := 24.0
## 前摇（身体发红）
@export var windup := 0.55
## 前摇进行到多少比例后锁定方向（同时头顶出现“!”）
@export var lock_fraction := 0.6
## 出招用时
@export var strike_time := 0.18
## 出招时向前冲多少像素（冲撞 = 冲撞距离）
@export var strike_lunge := 12.0
## 收招（空档）
@export var recover := 0.5
## 出招间隔：每次收招后随机等待的最短时间
@export var interval_min := 0.6
## 出招间隔：最长时间
@export var interval_max := 1.2
## 伤害
@export var damage := 19
## 前摇和出招时霸体（打不断）
@export var super_armor := true

@export_group("挨打")
## 被打硬直
@export var stagger := 0.3
## 被打出硬直后，下一招会不会被推迟
@export var stagger_delays_attack := false
## 推迟的话，硬直结束后下一招至少再等多少秒
@export var stagger_attack_delay := 0.0
## 免硬直时间：硬直结束后这么久内不会再被打出硬直
@export var poise := 1.2
## 击退抗性：0 = 正常击退，0.6 = 只剩 40%
@export var knock_resist := 0.6

@export_group("侧步（只在追击时）")
## 你在附近攻击时侧步的概率（0 = 不会）
@export var sidestep_chance := 0.0
## 侧步之后多少秒内不再侧步
@export var sidestep_cooldown := 0.0
## 侧步距离
@export var sidestep_distance := 0.0
## 侧步用时
@export var sidestep_time := 0.0
## 你在多近攻击时会考虑侧步
@export var sidestep_trigger := 0.0

@export_group("其他")
## 会不会闪身换位（v1.1：都不会）
@export var can_swap := false
## 切磋结束比例：生命 ≤ 最大生命 × 这个比例就结束（0 = 不是切磋，会被打倒）
@export var end_fraction := 0.0
## 发现距离：你走进这个距离就开打（0 = 不会主动开打）
@export var aggro_range := 0.0
## 放弃追击距离：你离它的原位超过这个距离，它就回原位并回满血（0 = 不放弃）
@export var leash_range := 0.0
## 被打倒后淡出用时
@export var defeat_fade := 1.0
