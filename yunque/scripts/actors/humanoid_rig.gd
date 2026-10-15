class_name HumanoidRig
extends Node3D
## 程序化人形骨架：用「Node3D 关节层级 + 每帧程序化驱动」代替蒙皮骨骼。
##
## 为什么不用 Skeleton3D + 蒙皮网格：本项目零预算、无外部美术资源，
## 蒙皮需要先在 Blender 里建好模型和权重。用刚体部件 + 关节旋转可以完全用代码生成，
## 改一个参数就能换体型与配色，玩家与 NPC 共用同一套，且不需要任何动画文件。
##
## 关节约定（模型正面朝 -Z，与 PlayerController 的朝向约定一致）：
##   Rotation.x > 0  → 该部件向 -Z（前）摆
##   膝关节只允许 rotation.x < 0（人的膝不能反折）

@export var walk_cycle := 1.85      # 相位推进率（弧度/秒 / (米/秒)）：3.4m/s 走 ≈ 2 步/秒
@export var stride_scale := 0.60    # 大腿摆幅（弧度）
@export var arm_scale := 0.48       # 手臂摆幅（弧度）
@export var phase_offset := 0.0     # 让各 NPC 的待机动作不同步

var hip: Node3D
var spine: Node3D
var neck: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var skirt: Node3D

## 由外部（PlayerController / NPCActor）每帧写入的水平速度（m/s）。
var motion_speed := 0.0

var _phase := 0.0
var _t := 0.0
var _blend := 0.0        # 0 = 静止待机，1 = 行走
var _hip_base_y := 0.9

func bind() -> void:
	hip = get_node_or_null("Hip")
	spine = get_node_or_null("Hip/Spine")
	neck = get_node_or_null("Hip/Spine/Neck")
	shoulder_l = get_node_or_null("Hip/Spine/ShoulderL")
	shoulder_r = get_node_or_null("Hip/Spine/ShoulderR")
	elbow_l = get_node_or_null("Hip/Spine/ShoulderL/ElbowL")
	elbow_r = get_node_or_null("Hip/Spine/ShoulderR/ElbowR")
	hip_l = get_node_or_null("Hip/HipL")
	hip_r = get_node_or_null("Hip/HipR")
	knee_l = get_node_or_null("Hip/HipL/KneeL")
	knee_r = get_node_or_null("Hip/HipR/KneeR")
	skirt = get_node_or_null("Hip/Skirt")
	if hip != null:
		_hip_base_y = hip.position.y

## 外部每帧调用：传入当前水平速度（0 表示站立）。
func set_locomotion(speed: float) -> void:
	motion_speed = speed

func _process(delta: float) -> void:
	_t += delta
	var moving := motion_speed > 0.12
	_blend = move_toward(_blend, 1.0 if moving else 0.0, delta * 5.5)
	if moving:
		# 步频与速度成正比：走得快 → 迈步快
		_phase += delta * walk_cycle * motion_speed
	var spd := clampf(motion_speed / 3.4, 0.0, 1.9)
	var sw := sin(_phase)
	var sw_opp := sin(_phase + PI)
	var idle := 1.0 - _blend
	var breath := sin(_t * 1.65 + phase_offset)

	# ---------------- 腿 ----------------
	if hip_l != null:
		hip_l.rotation.x = stride_scale * sw * _blend
	if hip_r != null:
		hip_r.rotation.x = stride_scale * sw_opp * _blend
	# 膝只向后弯，且在后摆（蹬地/抬腿）时弯得最多
	if knee_l != null:
		knee_l.rotation.x = -(0.06 + 1.0 * maxf(0.0, -sw)) * _blend
	if knee_r != null:
		knee_r.rotation.x = -(0.06 + 1.0 * maxf(0.0, -sw_opp)) * _blend

	# ---------------- 手臂（与同侧腿反相） ----------------
	if shoulder_l != null:
		shoulder_l.rotation.x = -arm_scale * sw * _blend
		# 待机时手臂自然外张，行走时收拢一点
		shoulder_l.rotation.z = 0.075 + 0.022 * breath * idle - 0.035 * _blend
	if shoulder_r != null:
		shoulder_r.rotation.x = -arm_scale * sw_opp * _blend
		shoulder_r.rotation.z = -0.075 - 0.022 * breath * idle + 0.035 * _blend
	if elbow_l != null:
		elbow_l.rotation.x = (0.16 + 0.24 * maxf(0.0, sw)) * _blend + 0.10 * idle
	if elbow_r != null:
		elbow_r.rotation.x = (0.16 + 0.24 * maxf(0.0, sw_opp)) * _blend + 0.10 * idle

	# ---------------- 骨盆与躯干 ----------------
	if hip != null:
		# 每一步重心上下起伏两次（左右腿各一次）
		hip.position.y = _hip_base_y + (0.032 * sin(2.0 * _phase) - 0.012) * _blend + 0.007 * breath * idle
		hip.rotation.z = 0.05 * sin(_phase) * _blend
	if spine != null:
		# 速度越快身体越前倾；静止时只有呼吸的轻微起伏
		spine.rotation.x = (-0.03 - 0.085 * spd) * _blend - 0.013 * breath * idle
		spine.rotation.y = -0.085 * sw * _blend
		spine.rotation.z = 0.035 * sin(_phase) * _blend
	if neck != null:
		neck.rotation.y = 0.055 * sin(_t * 0.62 + phase_offset) * idle
		neck.rotation.x = 0.02 * breath * idle
	if skirt != null:
		# 袍摆随步子摆动（幅度要够，否则腿会从摆外穿出去）
		skirt.rotation.x = -0.16 * sw * _blend
		skirt.rotation.z = 0.045 * sin(_phase) * _blend
