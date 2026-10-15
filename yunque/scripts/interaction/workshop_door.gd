extends Interactable
class_name WorkshopDoor
## 废灯坊暗门：入口开放条件 = 罗班主确认（MSQ_OLD_LANTERN_WORKSHOP_OPEN）
## 兜底条件 = 三条线索齐全（设计文档 §21「少调查线索不阻止进入迷宫」）。

@export var dialogue_open := ""
@export var dialogue_locked := ""
@export var open_flag := "MSQ_OLD_LANTERN_WORKSHOP_OPEN"
@export var fallback_flag := "ALL_CLUES"

func can_interact() -> bool:
	return true

func _is_open() -> bool:
	return GameState.has_flag(open_flag) or (fallback_flag != "" and GameState.has_flag(fallback_flag))

func get_prompt() -> String:
	return prompt_text if _is_open() else "查看 废灯坊暗门（封着）"

func _on_interact(_who: Node) -> void:
	var is_open := _is_open()
	if is_open and not GameState.has_flag(open_flag):
		GameState.set_flag(open_flag, true)
	DialogueRunner.start_node(dialogue_open if is_open else dialogue_locked)
