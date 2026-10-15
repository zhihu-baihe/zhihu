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

@onready var camera_yaw: Node3D = $CameraYaw
@onready var arm: SpringArm3D = $CameraYaw/SpringArm3D
@onready var model: Node3D = $Model

var _facing := 0.0

func _ready() -> void:
	add_to_group("player")
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
