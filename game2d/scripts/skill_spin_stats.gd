class_name SkillSpinStats
extends Resource
## 燕回旋（招式）数值卡（配置资产层）。文件：game2d/cards/skills/swallow_spin.tres。
## 数值来源：docs/design/武学与经营-第一批-方案-v1.md 第一节 2「三招的数字」（tests/skills_suite.gd 逐项比对）。
## 时间单位：秒；距离：像素（1 格 = 32 px）。

## 伤害（打中身边一圈的每个敌人各一次）
@export var damage := 15
## 范围半径（像素）：敌人的受击圈碰到这个圈就算打中（1.5 格 = 48 像素）
@export var radius := 48.0
## 出招：按下到打中的时间
@export var impact := 0.15
## 全程：整个动作的时长（这段时间不能走、不能出别的招，可以闪避打断）
@export var length := 0.5
## 把敌人推开多少像素（再乘以敌人的 1 - 击退抗性）
@export var knockback := 24.0
## 没有霸体（super_armor）的敌人硬直多久；有霸体的（牦牛、黑虎……）只掉血
@export var stagger := 0.3
## 冷却（从按下算）
@export var cooldown := 4.0
