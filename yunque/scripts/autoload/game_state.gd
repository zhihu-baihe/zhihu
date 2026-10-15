extends Node
## 运行时状态（Autoload: GameState）
## 职责：旗标、线索、物品、队伍、时间段、已播对白标记、任务阶段重算。
## 原则（设计文档 §21 / MAP-01 §6.1）：只存状态与规则，不碰 UI；阶段随旗标实时重算。

signal flag_changed(flag: String, value: bool)
signal clue_added(clue_id: String, count: int, total: int)
signal item_changed(item_id: String, total: int)
signal party_changed(member_ids: Array)
signal quest_updated(quest_id: String, stage_id: String, stage_index: int, complete: bool)
signal time_band_changed(band: String)
## 通用提示条：UI 订阅它显示「拾取 / 线索 / 旗标」等短提示。
signal toast(text: String, color: Color)

## 派生旗标：不写死在剧本里，由状态自动维护，供对白条件复用。
const FLAG_ANY_CLUE := "ANY_CLUE"
const FLAG_ALL_CLUES := "ALL_CLUES"

var flags: Dictionary = {}          # String -> bool
var clues: Dictionary = {}          # String -> true
var items: Dictionary = {}          # String -> int
var party: Array = []               # Array[String] 角色 ID，按入队顺序
var party_levels: Dictionary = {}   # String -> int
var seen_dialogues: Dictionary = {} # String -> true（play_once 已播标记）
var time_band: String = "dusk"

var _quest_stage_cache: Dictionary = {}   # quest_id -> stage_id

func _ready() -> void:
	time_band = str(GameData.map_data("map_moyi").get("time_band_default", "dusk"))
	_refresh_derived_flags()
	_refresh_all_quests()


# ---------------------------------------------------------------- 旗标

func set_flag(flag: String, value: bool = true) -> void:
	if flag == "":
		return
	if flags.get(flag, false) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)
	_refresh_derived_flags()
	_refresh_all_quests()

func clear_flag(flag: String) -> void:
	if flags.has(flag):
		flags.erase(flag)
		flag_changed.emit(flag, false)
		_refresh_derived_flags()
		_refresh_all_quests()

func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))

func has_flags(list) -> bool:
	for f in _as_list(list):
		if not has_flag(str(f)):
			return false
	return true

func has_any_flag(list) -> bool:
	for f in _as_list(list):
		if has_flag(str(f)):
			return true
	return false

## 对白/交互通用条件判断：required 全部满足，forbidden 全都不满足。
func matches(required, forbidden) -> bool:
	if not has_flags(required):
		return false
	for f in _as_list(forbidden):
		if has_flag(str(f)):
			return false
	return true


# ---------------------------------------------------------------- 线索

func add_clue(clue_id: String) -> void:
	if clue_id == "" or clues.has(clue_id):
		return
	clues[clue_id] = true
	# 线索同时作为旗标写入：对白条件、任务阶段、交互门禁都用 flags 判断（设计文档 §21 证据标记）。
	flags[clue_id] = true
	flag_changed.emit(clue_id, true)
	var entry := GameData.clue_entry(clue_id)
	var label := str(entry.get("name", clue_id))
	toast.emit("获得线索：%s（%d/%d）" % [label, clue_count(), clue_total()], Color(0.94, 0.86, 0.63))
	clue_added.emit(clue_id, clue_count(), clue_total())
	_refresh_derived_flags()
	_refresh_all_quests()

func has_clue(clue_id: String) -> bool:
	return clues.has(clue_id)

func clue_count() -> int:
	return clues.size()

func clue_total() -> int:
	return maxi(1, GameData.clue_ids().size())

func clue_journal() -> Array:
	var out: Array = []
	for cid in clues.keys():
		out.append(str(GameData.clue_entry(cid).get("journal", cid)))
	return out


# ---------------------------------------------------------------- 物品

func add_item(item_id: String, count: int = 1) -> void:
	if item_id == "" or count == 0:
		return
	var cur := int(items.get(item_id, 0)) + count
	items[item_id] = maxi(0, cur)
	if cur <= 0:
		items.erase(item_id)
	item_changed.emit(item_id, cur)
	toast.emit("获得：%s ×%d" % [GameData.item_name(item_id), count], Color(0.85, 0.92, 0.72))

func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))

func has_item(item_id: String) -> bool:
	return item_count(item_id) > 0


# ---------------------------------------------------------------- 队伍

func add_party(character_ids) -> void:
	var changed := false
	for cid in _as_list(character_ids):
		var id := str(cid)
		if id == "" or party.has(id):
			continue
		party.append(id)
		if not party_levels.has(id):
			party_levels[id] = 5 if id != "SCN_ShenZhaoye" else 1
		changed = true
	if changed:
		party_changed.emit(party.duplicate())
		toast.emit("队伍加入：%s" % [GameData.character_name(str(party[-1]))], Color(0.9, 0.78, 0.6))

func party_has(character_id: String) -> bool:
	return party.has(character_id)


# ---------------------------------------------------------------- 对白已播标记

func mark_dialogue_seen(node_id: String) -> void:
	if node_id != "":
		seen_dialogues[node_id] = true

func is_dialogue_seen(node_id: String) -> bool:
	return bool(seen_dialogues.get(node_id, false))


# ---------------------------------------------------------------- 任务

func refresh_quests() -> void:
	_refresh_all_quests()

func quest_stage(quest_id: String) -> Dictionary:
	var q := GameData.quest(quest_id)
	var stages: Array = q.get("stages", [])
	var idx := 0
	for i in stages.size():
		if has_flags(stages[i].get("complete_on_flags", [])):
			idx = i + 1
		else:
			break
	var complete := idx >= stages.size()
	var cur: Dictionary = stages[mini(idx, stages.size() - 1)] if stages.size() > 0 else {}
	return {
		"quest_id": quest_id,
		"title": str(q.get("title", quest_id)),
		"type": str(q.get("type", "main")),
		"stage_index": idx,
		"stage_id": str(cur.get("id", "")),
		"objective": str(cur.get("objective", "")) if not complete else "（本章已完成的全部阶段）",
		"complete": complete,
		"stage_count": stages.size(),
	}

func active_quests() -> Array:
	var out: Array = []
	var main_id := GameData.main_quest_id()
	for qid in GameData.quest_ids():
		var st := quest_stage(qid)
		# 支线只有在「已推进」或「已完成」后才写进日志，避免开场列出所有支线。
		if qid != main_id and st["stage_index"] == 0 and not st["complete"]:
			continue
		out.append(st)
	return out

func _refresh_all_quests() -> void:
	for qid in GameData.quest_ids():
		var st := quest_stage(qid)
		var prev := str(_quest_stage_cache.get(qid, ""))
		var cur := "%s|%s" % [st["stage_id"], st["complete"]]
		if prev != cur:
			_quest_stage_cache[qid] = cur
			quest_updated.emit(qid, st["stage_id"], st["stage_index"], st["complete"])

func _refresh_derived_flags() -> void:
	var n := clue_count()
	var any_before := bool(flags.get(FLAG_ANY_CLUE, false))
	var all_before := bool(flags.get(FLAG_ALL_CLUES, false))
	var any_now := n >= 1
	var all_now := n >= clue_total()
	flags[FLAG_ANY_CLUE] = any_now
	flags[FLAG_ALL_CLUES] = all_now
	if any_before != any_now:
		flag_changed.emit(FLAG_ANY_CLUE, any_now)
	if all_before != all_now:
		flag_changed.emit(FLAG_ALL_CLUES, all_now)


# ---------------------------------------------------------------- 时间段

func set_time_band(band: String) -> void:
	if band == "" or band == time_band:
		return
	time_band = band
	time_band_changed.emit(band)


# ---------------------------------------------------------------- 工具

static func _as_list(v) -> Array:
	if v == null:
		return []
	if v is Array:
		return v
	if v is PackedStringArray:
		return Array(v)
	return [v]
