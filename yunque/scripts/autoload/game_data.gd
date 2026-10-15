extends Node
## 数据注册中心（Autoload: GameData）
## 职责：启动时读取 res://data/*.json，建立索引，并做一次完整性校验。
## 设计文档对应：UE5_DataTables 各 DT_ 表 → Godot 侧的 JSON 数据源。
## 只做「读 + 查 + 校验」，不保存任何运行时状态（状态归 GameState）。

signal data_loaded(ok: bool, problems: PackedStringArray)

const DATA_DIR := "res://data/"
const FILES := {
	"characters": "characters.json",
	"items": "items.json",
	"dialogue": "dialogue.json",
	"quests": "quests.json",
	"map_moyi": "map_moyi.json",
}

## 系统保留的「非 NPC 说话方」标识：用于调查点、过场与道具触发。
const NON_NPC_SPEAKERS := ["SYSTEM", "CUTSCENE"]

var raw: Dictionary = {}
var problems := PackedStringArray()

var _characters: Dictionary = {}
var _items: Dictionary = {}
var _npc_meta: Dictionary = {}
var _dialogue_by_id: Dictionary = {}
var _dialogue_by_npc: Dictionary = {}
var _quests: Dictionary = {}
var _clues: Dictionary = {}

func _ready() -> void:
	for key in FILES:
		raw[key] = _load_json(DATA_DIR + FILES[key])
	_build_indexes()
	_validate()
	if problems.is_empty():
		print("[GameData] 数据加载完成：对白 %d 条 / NPC %d 名 / 任务 %d 条 / 线索 %d 条 / 物品 %d 件。" % [
			_dialogue_by_id.size(), _npc_meta.size(), _quests.size(), _clues.size(), _items.size()])
	else:
		for p in problems:
			push_warning("[GameData] " + p)
		print("[GameData] 数据校验发现 %d 个问题（详见上方 warning）。" % problems.size())
	data_loaded.emit(problems.is_empty(), problems)


# ---------------------------------------------------------------- 加载与索引

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		problems.append("缺少数据文件：%s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		problems.append("无法打开数据文件：%s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		problems.append("JSON 解析失败 %s：第 %d 行 —— %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		problems.append("JSON 顶层不是对象：%s" % path)
		return {}
	return json.data


func _build_indexes() -> void:
	for c in _array(raw.get("characters", {}), "characters"):
		_characters[str(c.get("id", ""))] = c
	for it in _array(raw.get("items", {}), "items"):
		_items[str(it.get("id", ""))] = it

	var dlg: Dictionary = raw.get("dialogue", {})
	for npc_id in dlg.get("npcs", {}):
		_npc_meta[str(npc_id)] = dlg["npcs"][npc_id]
	for node in _array(dlg, "nodes"):
		var id := str(node.get("id", ""))
		var npc := str(node.get("npc", ""))
		_dialogue_by_id[id] = node
		if not _dialogue_by_npc.has(npc):
			_dialogue_by_npc[npc] = []
		_dialogue_by_npc[npc].append(node)

	for q in _array(raw.get("quests", {}), "quests"):
		_quests[str(q.get("id", ""))] = q
	for c in _array(raw.get("quests", {}), "clues"):
		_clues[str(c.get("id", ""))] = c


static func _array(dict: Dictionary, key: String) -> Array:
	var v = dict.get(key, [])
	return v if v is Array else []


# ---------------------------------------------------------------- 查询 API

func character(id: String) -> Dictionary:
	return _characters.get(id, {})

func character_name(id: String) -> String:
	var c := character(id)
	return str(c.get("display_name", id))

func item(id: String) -> Dictionary:
	return _items.get(id, {})

func item_name(id: String) -> String:
	var it := item(id)
	return str(it.get("name", id))

func npc_meta(npc_id: String) -> Dictionary:
	return _npc_meta.get(npc_id, {})

func npc_name(npc_id: String) -> String:
	var m := npc_meta(npc_id)
	return str(m.get("name", npc_id))

func dialogue_node(node_id: String) -> Dictionary:
	return _dialogue_by_id.get(node_id, {})

func dialogue_nodes_for(npc_id: String) -> Array:
	return _dialogue_by_npc.get(npc_id, [])

func quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {})

func quest_ids() -> Array:
	return _quests.keys()

func main_quest_id() -> String:
	for id in _quests:
		if str(_quests[id].get("type", "")) == "main":
			return id
	return ""

func clue_ids() -> Array:
	return _clues.keys()

func clue_entry(clue_id: String) -> Dictionary:
	return _clues.get(clue_id, {})

func map_data(map_key: String) -> Dictionary:
	return raw.get(map_key, {})

func all_problems() -> PackedStringArray:
	return problems


# ---------------------------------------------------------------- 校验

func _validate() -> void:
	var dlg: Dictionary = raw.get("dialogue", {})

	# 1) 对白节点的说话方、效果引用
	for node in _array(dlg, "nodes"):
		var nid := str(node.get("id", ""))
		var npc := str(node.get("npc", ""))
		if npc == "":
			problems.append("对白 %s 缺少 npc 字段。" % nid)
		elif not _npc_meta.has(npc) and not NON_NPC_SPEAKERS.has(npc):
			problems.append("对白 %s 引用了未定义的 NPC：%s" % [nid, npc])
		var eff: Dictionary = node.get("effects", {})
		var add_item = eff.get("add_item", null)
		if add_item is Dictionary:
			var iid2 := str(add_item.get("id", ""))
			if iid2 != "" and not _items.has(iid2):
				problems.append("对白 %s 的 add_item 引用未知物品：%s" % [nid, iid2])
		var add_clue = eff.get("add_clue", null)
		if add_clue != null:
			var list: Array = add_clue if add_clue is Array else [add_clue]
			for cid in list:
				if not _clues.has(str(cid)):
					problems.append("对白 %s 的 add_clue 引用未定义线索：%s" % [nid, cid])
		var sq = str(eff.get("start_quest", ""))
		if sq != "" and not _quests.has(sq):
			problems.append("对白 %s 的 start_quest 引用未知任务：%s" % [nid, sq])
		if _array(node, "lines").is_empty():
			problems.append("对白 %s 没有任何台词。" % nid)

	# 2) 任务结构
	for qid in _quests:
		var q: Dictionary = _quests[qid]
		var stages := _array(q, "stages")
		if stages.is_empty():
			problems.append("任务 %s 没有任何阶段。" % qid)
		for st in stages:
			if _array(st, "complete_on_flags").is_empty():
				problems.append("任务 %s 阶段 %s 缺少 complete_on_flags。" % [qid, st.get("id", "?")])

	# 3) 地图：交互点、触发器、NPC、对白引用
	var map: Dictionary = raw.get("map_moyi", {})
	for it in _array(map, "interactables"):
		var iid := str(it.get("id", ""))
		for key in ["dialogue", "dialogue_open", "dialogue_locked"]:
			var d := str(it.get(key, ""))
			if d != "" and not _dialogue_by_id.has(d):
				problems.append("交互点 %s 的 %s 引用未定义对白：%s" % [iid, key, d])
		var item_id := str(it.get("item", ""))
		if item_id != "" and not _items.has(item_id):
			problems.append("交互点 %s 引用未定义物品：%s" % [iid, item_id])
	for trg in _array(map, "triggers"):
		var d2 := str(trg.get("dialogue", ""))
		if d2 != "" and not _dialogue_by_id.has(d2):
			problems.append("触发器 %s 引用未定义对白：%s" % [trg.get("id", "?"), d2])
	for npc in _array(map, "npcs"):
		var nid2 := str(npc.get("id", ""))
		if not _npc_meta.has(nid2):
			problems.append("地图 NPC %s 不在 dialogue.json 的 npcs 中。" % nid2)
		elif dialogue_nodes_for(nid2).is_empty():
			problems.append("地图 NPC %s 没有任何对白节点。" % nid2)
