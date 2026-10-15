extends Node
## 对白引擎（Autoload: DialogueRunner）
## 职责：按「优先级 + 条件 + 已播标记」选择对白节点，逐行播放，播完应用效果。
## 对应设计文档：§19.2 对话优先级、§25 NPC 对话数据示例、MAP-01 §6.2。

signal dialogue_started(node_id: String, lines: Array)
signal line_shown(line_index: int, speaker: String, text: String)
signal dialogue_finished(node_id: String)

var active: bool = false

var _node: Dictionary = {}
var _lines: Array = []
var _index: int = 0

func _ready() -> void:
	# 对白进行中时，玩家移动由 PlayerController 自行让位（读取 active）。
	set_process(false)


## 是否有可用对白（用于交互提示「(暂无可谈内容)」）。
func has_dialogue(npc_id: String) -> bool:
	return not select_node(npc_id).is_empty()

## 选择一个节点：
## 1. 取该 NPC 的全部节点 → 2. 过滤条件 → 3. 过滤 play_once 已播 → 4. 取 priority 最高。
func select_node(npc_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -100000
	for node in GameData.dialogue_nodes_for(npc_id):
		if not GameState.matches(node.get("required", []), node.get("forbidden", [])):
			continue
		if bool(node.get("play_once", false)) and GameState.is_dialogue_seen(str(node.get("id", ""))):
			continue
		var p := int(node.get("priority", 0))
		if p > best_priority:
			best_priority = p
			best = node
	return best

## 与 NPC 交谈。
func start_npc(npc_id: String) -> bool:
	var node := select_node(npc_id)
	if node.is_empty():
		GameState.toast.emit("%s 现在没什么要说的。" % GameData.npc_name(npc_id), Color(0.7, 0.72, 0.7))
		return false
	return start_node(str(node.get("id", "")))

## 按节点 ID 直接播放（调查点 / 门 / 触发器 / 过场使用）。
func start_node(node_id: String) -> bool:
	if active:
		return false
	var node := GameData.dialogue_node(node_id)
	if node.is_empty():
		push_warning("[DialogueRunner] 未知对白节点：%s" % node_id)
		return false
	if not GameState.matches(node.get("required", []), node.get("forbidden", [])):
		return false
	_node = node
	_lines = node.get("lines", [])
	_index = 0
	if _lines.is_empty():
		_apply_effects(node.get("effects", {}))
		GameState.mark_dialogue_seen(node_id)
		return false
	active = true
	set_process(true)
	dialogue_started.emit(node_id, _lines)
	_emit_line()
	return true

## 推进一行；说到最后一行时结束并结算。
func advance() -> void:
	if not active:
		return
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_emit_line()

func skip_all() -> void:
	if not active:
		return
	_finish()

func current_node_id() -> String:
	return str(_node.get("id", ""))

func current_line() -> Dictionary:
	if _index < 0 or _index >= _lines.size():
		return {}
	var l = _lines[_index]
	if l is Dictionary:
		return l
	return {"speaker": str(_node.get("speaker", "")), "text": str(l)}

func is_last_line() -> bool:
	return _index >= _lines.size() - 1


# ---------------------------------------------------------------- 内部

func _emit_line() -> void:
	var l := current_line()
	line_shown.emit(_index, str(l.get("speaker", "")), str(l.get("text", "")))

func _finish() -> void:
	var id := current_node_id()
	_apply_effects(_node.get("effects", {}))
	if bool(_node.get("play_once", false)) or str(_node.get("npc", "")) in GameData.NON_NPC_SPEAKERS:
		GameState.mark_dialogue_seen(id)
	active = false
	_index = 0
	_lines = []
	_node = {}
	set_process(false)
	dialogue_finished.emit(id)

func _apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	for flag in effects.get("set_flags", {}).keys():
		GameState.set_flag(str(flag), bool(effects["set_flags"][flag]))
	for flag in effects.get("clear_flags", []):
		GameState.clear_flag(str(flag))
	var add_clue = effects.get("add_clue", null)
	if add_clue != null:
		for cid in (add_clue if add_clue is Array else [add_clue]):
			GameState.add_clue(str(cid))
	var add_item = effects.get("add_item", null)
	if add_item is Dictionary:
		GameState.add_item(str(add_item.get("id", "")), int(add_item.get("count", 1)))
	var sq = str(effects.get("start_quest", ""))
	if sq != "":
		# 任务本身由旗标驱动；这里只保证支线在日志中出现。
		GameState.refresh_quests()
	var ap = effects.get("add_party", null)
	if ap != null:
		GameState.add_party(ap)
