extends Interactable
class_name NPCInteractable
## NPC 交谈交互：交给 DialogueRunner 按优先级选对白。

@export var npc_id := ""

func set_npc_id(v: String) -> void:
	npc_id = v

func get_prompt() -> String:
	if npc_id == "":
		return prompt_text
	if not DialogueRunner.has_dialogue(npc_id):
		return "%s（暂时无话）" % GameData.npc_name(npc_id)
	return "与 %s 交谈" % GameData.npc_name(npc_id)

func can_interact() -> bool:
	return not disabled and DialogueRunner.has_dialogue(npc_id)

func _on_interact(_who: Node) -> void:
	DialogueRunner.start_npc(npc_id)
