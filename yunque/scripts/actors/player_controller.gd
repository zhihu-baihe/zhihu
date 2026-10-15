extends CharacterBody3D
class_name PlayerController
## 第三人称角色控制器（沈照野）
## 相机：Yaw 节点负责水平旋转，SpringArm3D 负责俯仰与避障。
## 对白进行中（DialogueRunner.active）不接收移动输入。

@export var walk_speed := 3.4
@export var run_speed := 6.0
@export var acceleration := 14.0
@export var friction := 18.0
@export var gravity := 22.0
@export var mouse_sensitivity := 0.0022
@export var pitch_min_deg := -58.0
@export var pitch_max_deg := 28.0
@export var turn_speed := 12.0

## 沈照野的配色（青蓝外袍 + 铜金缘边），与人物档案一致。
@export var robe_color := Color("#4b6284")
@export var trim_color := Color("#c09a4e")
@export var skin_color := Color("#d6b394")
@export var hair_color := Color("#221d1a")
@export var carries_sword := true

@onready var camera_yaw: Node3D = $CameraYaw
@onready var arm: SpringArm3D = $CameraYaw/SpringArm3D
@onready var model: Node3D = $Model

var rig: HumanoidRig = null
var _facing := 0.0

func _ready() -> void:
	add_to_group("player")
	_build_humanoid()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build_humanoid() -> void:
	if model == null:
		return
	rig = HumanoidBuilder.build(model, {
		"robe": robe_color,
		"trim": trim_color,
		"skin": skin_color,
		"hair": hair_color,
		"weapon": carries_sword,
		"phase_offset": 0.0,
	})

## 供出生点使用：设置初始朝向（度）。
func set_spawn_yaw(deg: float) -> void:
	_facing = deg_to_rad(deg)
	camera_yaw.rotation.y = _facing
	if model:
		model.rotation.y = _facing

## 供存档使用：当前朝向（度）。
func facing_yaw_deg() -> float:
	return rad_to_deg(_facing)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		arm.rotation.x = clampf(
			arm.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	elif event.is_action_pressed("ui_cancel") and not GameState.ui_blocked:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	var dir := Vector2.ZERO
	if not DialogueRunner.active and not GameState.ui_blocked:
		dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# 以相机水平朝向为基准换算世界方向
	var b := camera_yaw.global_transform.basis
	var wish := Vector3(b.x.x * dir.x + b.z.x * dir.y, 0.0, b.x.z * dir.x + b.z.z * dir.y)
	if wish.length() > 0.01:
		wish = wish.normalized()

	var speed := walk_speed
	if Input.is_action_pressed("sprint") and not DialogueRunner.active and not GameState.ui_blocked:
		speed = run_speed

	if wish.length() > 0.01:
		velocity.x = move_toward(velocity.x, wish.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()

	if model:
		if wish.length() > 0.01:
			# 模型的正面是 -Z：rotation.y = atan2(-x, -z)
			_facing = atan2(-wish.x, -wish.z)
		model.rotation.y = lerp_angle(model.rotation.y, _facing, turn_speed * delta)

	# 驱动程序化人形：水平速度决定步频与摆幅
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if rig:
		rig.set_locomotion(hspeed)
	# 脚步声按移动距离触发，与帧率无关
	AudioDirector.tick_footsteps(hspeed, delta, is_on_floor())
