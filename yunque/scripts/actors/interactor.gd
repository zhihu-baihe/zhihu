extends Node3D
class_name Interactor
## 交互探测器（玩家子节点）
## 采用「拉取」模型：HUD 每帧读取 current_prompt()，不依赖信号时序。
## 交互键 E：对白进行中不响应（推进对白由 DialogueBox 负责）。

@export var interact_range := 3.4
@export var scan_interval := 0.1

var nearest: Node = null

var _scan_t := 0.0

func _ready() -> void:
	add_to_group("interactor")

func current_prompt() -> String:
	if nearest == null or not is_instance_valid(nearest):
		return ""
	if nearest.has_method("get_prompt"):
		return str(nearest.get_prompt())
	return "互动"

func _process(delta: float) -> void:
	if DialogueRunner.active or GameState.ui_blocked:
		if nearest != null:
			nearest = null
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = scan_interval
		nearest = _find_nearest()

func _unhandled_input(event: InputEvent) -> void:
	if DialogueRunner.active or GameState.ui_blocked:
		return
	if event.is_action_pressed("interact"):
		if nearest != null and is_instance_valid(nearest) and nearest.has_method("interact"):
			AudioDirector.play_ui("ui_click", -15.0)
			nearest.interact(get_parent())
			get_viewport().set_input_as_handled()

func _find_nearest() -> Node:
	var best: Node = null
	var best_d := interact_range
	var here := global_position
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not n.has_method("can_interact"):
			continue
		if not n.can_interact():
			continue
		var d := here.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best
