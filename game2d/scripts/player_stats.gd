class_name PlayerStats
extends Resource
## 主角数值卡（配置资产层）。文件：game2d/cards/player.tres。
## 数值来源：docs/design/战斗数据方案-v1.3.md 第 4.2 节（附录 A 有逐项对照，自动测试会比对）。
## 时间单位：秒；距离：像素（1 格 = 32 px）；速度：像素/秒；角度：度。

@export_group("生命与移动")
## 最大生命
@export var max_hp := 100
## 走路速度（像素/秒）。v1.1 起从 data/tuning.json 迁到这里
@export var walk_speed := 133.0
## 身体受击圈半径：敌人的命中圈碰到这个圈就算打中
@export var body_radius := 10.0

@export_group("两连击")
## 攻击 1 伤害
@export var attack1_damage := 8
## 攻击 1：按下到打中的时间
@export var attack1_impact := 0.17
## 攻击 1：整个动作的时长
@export var attack1_length := 0.49
## 攻击 1：把敌人击退多少像素
@export var attack1_knockback := 6.0
## 攻击 2 伤害
@export var attack2_damage := 12
## 攻击 2：开始到打中的时间
@export var attack2_impact := 0.22
## 攻击 2：整个动作的时长
@export var attack2_length := 0.63
## 攻击 2：把敌人击退多少像素
@export var attack2_knockback := 16.0
## 连招窗口：攻击 1 开始多少秒后可以接攻击 2
@export var combo_window := 0.30
## 输入缓冲：提前多少秒按攻击也会被记住
@export var input_buffer := 0.30
## 命中圈中心在身前多少像素
@export var hit_offset := 32.0
## 命中圈半径
@export var hit_radius := 24.0
## 出手前冲距离
@export var lunge_distance := 8.0
## 出手前冲用时
@export var lunge_time := 0.12
## 攻击中移动速度 = 走路速度 × 这个倍数
@export var attack_move_factor := 0.2
## 出手时自动转向这个距离内最近的敌人
@export var auto_face_range := 96.0

@export_group("闪避")
## 闪避速度（像素/秒）；闪避距离 = 速度 × 用时 ≈ 86 px
@export var dodge_speed := 540.0
## 闪避用时
@export var dodge_time := 0.16
## 闪避无敌时间（从按下算），也是“闪避成功”的判定时间
@export var dodge_iframes := 0.30
## 闪避冷却（闪避结束后）
@export var dodge_cooldown := 0.60
## 攻击中能否用闪避打断自己的攻击
@export var dodge_cancels_attack := true

@export_group("闪身换位")
## 按闪避时，敌人在这个距离内才会换位
@export var swap_range := 64.0
## 按的方向和“朝向敌人”的夹角不超过这么多度才会换位
@export var swap_angle := 60.0
## 落在敌人身后多少像素
@export var swap_behind := 28.0

@export_group("格挡（GP，试玩反馈 v1）")
## 按 K / 鼠标右键后格挡架势持续多久；这段时间里被敌人打中 = GP 成功（不掉血、自动反击）
@export var gp_stance := 0.25
## 按早了（架势结束时还没被打到）的收招：这段时间不能动、不能闪避、不能攻击
@export var gp_whiff_recover := 0.4
## 冷却：架势结束后多少秒内不能再按 K
@export var gp_cooldown := 0.3
## GP 成功后原地自动反击的总伤害（两下：按攻击 1 : 攻击 2 的比例拆开，8:12 → 12 + 18）
@export var gp_counter_damage := 30
## GP 成功时敌人的硬直（秒）；有霸体（super_armor）的敌人不硬直
@export var gp_enemy_stagger := 0.6
## GP 成功时的画面停顿（秒）
@export var gp_hitstop := 0.1
## GP 成功时把敌人弹开多少像素（再乘以敌人的 1 - 击退抗性）
@export var gp_knockback := 16.0

@export_group("闪身追击（v1.2）")
## 闪避结束后多少秒内按攻击，会冲向附近的敌人再出手（冲刺速度 = 闪避速度 dodge_speed）
@export var chase_window := 0.6
## 追击范围（锁定范围，3 格 = 96 像素）：最近的敌人在这个距离内才会冲过去，冲刺中一直追着它，贴身才出手，一定打中（否则原地出招）
@export var chase_range := 96.0

@export_group("受击")
## 受击硬直（不能动作）
@export var hurt_stun := 0.40
## 受击击退（像素）
@export var hurt_knockback := 12.0
## 受击后保护时间（从挨打那一刻算，期间不再受伤）
@export var hurt_protect := 0.55

@export_group("脱战回血（v1.3）")
## 脱战回血开始前的等待：不在战斗中、并且距离上次受伤/脱离战斗满这么多秒才开始回血
@export var regen_delay := 5.0
## 回血速度（点/秒），回到最大生命为止
@export var regen_per_sec := 3.0
