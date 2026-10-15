extends Node
## 存档管理器（Autoload: SaveManager）
## 依据：设计文档 §21（BOSS 失败从战前检查点重试、不重置线索与支线状态）、
##       MAP-01 §9（读档后不得出现「灯魇已败但灯桥仍异常」或「NPC 说没见过玩家」的状态冲突）、
##       UE5 设计稿的 FSaveGameData 清单（任务阶段/证据/检查点/一次性对白/装备/材料/时段/地图变体/SaveVersion）。
## 规则：只序列化 GameState 的状态 + 当前场景 + 玩家位置；**派生旗标在载入时重算，不信任文件**。

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := 0
const MANUAL_SLOTS: Array = [1, 2, 3]
## 兜底场景：存档里没有场景路径时回到墨邑城镇
const DEFAULT_WORLD := "res://scenes/world/moyi_town.tscn"

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(slot: int, reason: String)

var last_error := ""
var _suspend_autosave := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	GameState.quest_updated.connect(_on_quest_updated)
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	# 退出前写一次自动存档，避免断电/关窗丢进度
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if SceneRouter.current_world() != null:
			save_game(AUTOSAVE_SLOT, true)
		get_tree().quit()


# ---------------------------------------------------------------- 槽位信息

func slot_path(slot: int) -> String:
	return "%s/slot_%02d.json" % [SAVE_DIR, slot]

func slot_label(slot: int) -> String:
	return "自动存档" if slot == AUTOSAVE_SLOT else "存档槽 %d" % slot

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func slot_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var d := _read_json(slot_path(slot))
	if d.is_empty():
		return {"broken": true}
	var st: Dictionary = d.get("state", {})
	var clues_v = st.get("clues", [])
	var clue_count := 0
	if clues_v is Array:
		clue_count = (clues_v as Array).size()
	elif clues_v is Dictionary:
		clue_count = (clues_v as Dictionary).size()
	var party_v = st.get("party", [])
	var party_size := 0
	if party_v is Array:
		party_size = (party_v as Array).size()
	return {
		"saved_at": str(d.get("saved_at", "")),
		"scene_name": str(d.get("scene_name", "")),
		"clue_count": clue_count,
		"party_size": party_size,
		"save_version": int(d.get("save_version", 0)),
		"broken": false,
	}

func delete_save(slot: int) -> bool:
	if not has_save(slot):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot))) == OK


# ---------------------------------------------------------------- 保存

func save_game(slot: int, quiet := false) -> bool:
	var payload := {
		"save_version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"scene": SceneRouter.current_path,
		"scene_name": SceneRouter.current_scene_name(),
		"player": {"pos": [], "yaw_deg": 0.0},
		"state": GameState.to_dict(),
	}
	var player := SceneRouter.get_player()
	if player != null and player is Node3D:
		var p: Vector3 = (player as Node3D).global_position
		var yaw := 0.0
		if player.has_method("facing_yaw_deg"):
			yaw = float(player.facing_yaw_deg())
		payload["player"] = {"pos": [p.x, p.y, p.z], "yaw_deg": yaw}

	var err := _write_json(slot_path(slot), payload)
	if err != OK:
		last_error = "写入失败（错误码 %d）" % err
		save_failed.emit(slot, last_error)
		GameState.toast.emit("保存失败：%s" % last_error, UITheme.ACCENT_CINNABAR)
		return false
	if not quiet:
		GameState.toast.emit("已保存：%s" % slot_label(slot), UITheme.ACCENT_TEAL)
	game_saved.emit(slot)
	return true


# ---------------------------------------------------------------- 读取

func load_game(slot: int) -> bool:
	if not has_save(slot):
		GameState.toast.emit("没有可读取的存档。", UITheme.INK_SUB)
		return false
	var d := _read_json(slot_path(slot))
	if d.is_empty():
		GameState.toast.emit("存档损坏，无法读取。", UITheme.ACCENT_CINNABAR)
		return false
	var ver := int(d.get("save_version", 0))
	if ver != SAVE_VERSION:
		GameState.toast.emit("存档版本不匹配（%d ≠ %d），暂不支持自动迁移。" % [ver, SAVE_VERSION], UITheme.ACCENT_CINNABAR)
		return false

	# 载入状态：期间挂起自动存档，避免覆盖刚读出的槽位
	_suspend_autosave = true
	GameState.from_dict(d.get("state", {}))
	_suspend_autosave = false

	var scene := str(d.get("scene", DEFAULT_WORLD))
	if scene == "":
		scene = DEFAULT_WORLD
	var pl: Dictionary = d.get("player", {})
	var pos: Array = pl.get("pos", [])
	var spawn := Vector3.INF
	if pos.size() == 3:
		spawn = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var yaw := float(pl.get("yaw_deg", 0.0))
	game_loaded.emit(slot)
	if SceneRouter.is_ready():
		await SceneRouter.change_world(scene, spawn, yaw)
	GameState.toast.emit("已读取：%s" % slot_label(slot), UITheme.ACCENT_TEAL)
	return true


# ---------------------------------------------------------------- 自动存档

func _on_quest_updated(_qid: String, _sid: String, _idx: int, _done: bool) -> void:
	if _suspend_autosave or SceneRouter.current_world() == null:
		return
	save_game(AUTOSAVE_SLOT, true)


# ---------------------------------------------------------------- 工具

func _write_json(path: String, payload: Dictionary) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	return OK

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "无法打开存档（错误码 %d）" % FileAccess.get_open_error()
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = "JSON 解析失败：第 %d 行 %s" % [json.get_error_line(), json.get_error_message()]
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		last_error = "存档顶层不是对象"
		return {}
	return json.data
