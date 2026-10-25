class_name TrialCard
extends Resource
## 试炼卡（配置资产层）：game2d/cards/trial_plum.tres —— 梅花桩试炼的全部数字。
## 数值来源：docs/design/两条路小样-方案-v1.md 第 3 节（桩数、限时、评价线、木人桩伤害）；路线、转速、判定大小由开发定。
## 坐标单位：地图像素（1 格 = 32 像素）。

## 一共几根梅花桩（依次亮起，踩中亮着的那根下一根才亮）
@export var pole_count := 12
## 每根桩的站立点（桩顶中心，地图像素），按亮起的顺序；数量必须等于 pole_count
@export var pole_points: PackedVector2Array = PackedVector2Array()
## 脚底离站立点多近（像素）算踩中
@export var step_radius := 12.0
## 限时（秒），超过就失败
@export var time_limit := 60.0
## 金：多少秒内完成
@export var gold_seconds := 40.0
## 银：多少秒内完成
@export var silver_seconds := 50.0
## 铜：多少秒内完成
@export var bronze_seconds := 60.0
## 木人桩的位置（桩脚，地图像素）
@export var dummy_points: PackedVector2Array = PackedVector2Array()
## 木人桩一开始的木臂角度（度，0 = 朝东，顺时针）
@export var dummy_start_degrees: PackedFloat32Array = PackedFloat32Array()
## 木人桩转速（度 / 秒；负数 = 逆时针）
@export var dummy_turn_degrees: PackedFloat32Array = PackedFloat32Array()
## 木臂长度（像素，从桩脚量起，两边各一条）
@export var arm_length := 40.0
## 木臂半宽（像素）+ 玩家脚底半径 = 扫中的距离
@export var arm_half_width := 4.0
@export var player_hit_radius := 6.0
## 被扫到掉多少生命
@export var dummy_damage := 8
## 被扫到硬直多少秒
@export var dummy_stun := 0.45
## 生命降到最大生命的多少（比例）就算这次失败（生命回满）
@export var fail_hp_fraction := 0.2
## 报名后开场停顿（秒，显示“开始”字样，计时还没开始）
@export var intro_seconds := 1.0
## 评价画面显示多少秒（也可以按 E 提前关掉）
@export var result_seconds := 3.0
