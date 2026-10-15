extends Interactable
class_name PickupPoint
## 拾取点：获得物品、可选设置旗标，然后自毁。
## 若目标旗标已存在（读档/重进），builder 不会重建它。

@export var item_id := ""
@export var count := 1
@export var flag_on_take := ""
@export var display_label := ""

func get_prompt() -> String:
	if display_label != "":
		return "拾取 %s" % display_label
	return prompt_text

func _on_interact(_who: Node) -> void:
	if item_id == "":
		return
	GameState.add_item(item_id, count)
	if flag_on_take != "":
		GameState.set_flag(flag_on_take, true)
	queue_free()
