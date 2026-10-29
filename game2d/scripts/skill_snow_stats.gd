class_name SkillSnowStats
extends Resource
## 踏雪二段闪（身法）数值卡（配置资产层）。文件：game2d/cards/skills/snow_step.tres。学会就自动生效。
## 数值来源：docs/design/武学与经营-第一批-方案-v1.md 第一节 2「三招的数字」（tests/skills_suite.gd 逐项比对）。

## 闪避落地后多少秒内再按闪避，就是第二闪
@export var window := 0.3
## 第二闪的距离 = 第一闪的这么多倍（用时相同，速度乘这个数；无敌时间相同）
@export var distance_ratio := 0.7
