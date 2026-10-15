extends Area3D
class_name Interactable
## 统一交互入口（设计文档 §23 BP_Interactable）。
## 用「组 + 距离」判定，不依赖物理层配置；条件用旗标表达。

@export var prompt_text := "互动"
@export var required_flags: PackedStringArray = []
@export var forbidden_flags: PackedStringArray = []

var disabled := false

func _ready() -> void:
	add_to_group("interactable")
	monitoring = false
	monitorable = false

func can_interact() -> bool:
	if disabled:
		return false
	return GameState.matches(required_flags, forbidden_flags)

func get_prompt() -> String:
	return prompt_text

func set_disabled(v: bool) -> void:
	disabled = v

## 返回是否真的触发了交互。
func interact(who: Node) -> bool:
	if not can_interact():
		return false
	_on_interact(who)
	return true

func _on_interact(_who: Node) -> void:
	pass
