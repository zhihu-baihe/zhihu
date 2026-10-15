extends CanvasLayer
class_name GameHUD
## HUD：任务追踪、线索计数、交互提示、拾取/线索提示条、队伍状态。
## 交互提示采用「拉取」模型：每帧向 Interactor 取当前可交互对象，避免信号时序问题。

@onready var quest_title: Label = $QuestPanel/VBox/QuestTitle
@onready var quest_objective: Label = $QuestPanel/VBox/QuestObjective
@onready var clue_line: Label = $QuestPanel/VBox/ClueLine
@onready var prompt_label: Label = $InteractionPrompt
@onready var toast_box: VBoxContainer = $ToastBox
@onready var party_box: VBoxContainer = $PartyPanel/PartyBox
@onready var hint_bar: Label = $HintBar

var _interactor: Node = null

func _ready() -> void:
	GameState.quest_updated.connect(_on_quest_updated)
	GameState.clue_added.connect(_on_clue_added)
	GameState.item_changed.connect(_on_item_changed)
	GameState.party_changed.connect(_on_party_changed)
	GameState.toast.connect(_on_toast)
	DialogueRunner.dialogue_started.connect(func(_a, _b): _update_prompt())
	DialogueRunner.dialogue_finished.connect(func(_a): _update_prompt())
	hint_bar.text = "WASD 移动 · Shift 疾行 · E 交互 · Esc 释放鼠标 · 点击画面收回鼠标"
	_refresh_quests()
	_refresh_party()

func _process(_delta: float) -> void:
	if _interactor == null or not is_instance_valid(_interactor):
		var arr := get_tree().get_nodes_in_group("interactor")
		_interactor = arr[0] if arr.size() > 0 else null
	_update_prompt()

func _update_prompt() -> void:
	var txt := ""
	if not DialogueRunner.active and _interactor != null and is_instance_valid(_interactor):
		txt = str(_interactor.current_prompt())
	prompt_label.text = "［E］%s" % txt if txt != "" else ""
	prompt_label.visible = txt != ""


# ---------------------------------------------------------------- 提示条

func _on_toast(text: String, color: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.modulate = color
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
	lb.add_theme_constant_override("outline_size", 6)
	toast_box.add_child(lb)
	var tw := create_tween()
	tw.tween_property(lb, "modulate:a", 0.0, 2.6).set_delay(1.4)
	tw.tween_callback(lb.queue_free)


# ---------------------------------------------------------------- 任务 / 线索

func _refresh_quests() -> void:
	var main_title := ""
	var objective := ""
	for q in GameState.active_quests():
		if str(q.get("type", "")) == "main":
			main_title = str(q.get("title", ""))
			objective = "· %s" % str(q.get("objective", ""))
		else:
			objective += "\n· ［支线］%s" % str(q.get("objective", ""))
	quest_title.text = main_title
	quest_objective.text = objective
	clue_line.text = "线索 %d / %d" % [GameState.clue_count(), GameState.clue_total()]

func _on_quest_updated(_qid: String, _sid: String, _idx: int, _done: bool) -> void:
	_refresh_quests()

func _on_clue_added(_cid: String, _n: int, _t: int) -> void:
	_refresh_quests()

func _on_item_changed(_id: String, _total: int) -> void:
	pass


# ---------------------------------------------------------------- 队伍

func _refresh_party() -> void:
	for c in party_box.get_children():
		c.queue_free()
	if GameState.party.is_empty():
		# 主角在开场即视为在场（不依赖 add_party）
		_add_party_row("SCN_ShenZhaoye", 1)
		return
	for cid in GameState.party:
		_add_party_row(str(cid), int(GameState.party_levels.get(cid, 1)))

func _add_party_row(character_id: String, level: int) -> void:
	var st := _stats_for(character_id, level)
	var row := VBoxContainer.new()
	var name_lb := Label.new()
	name_lb.text = "%s  Lv%d" % [GameData.character_name(character_id), level]
	name_lb.add_theme_font_size_override("font_size", 18)
	name_lb.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
	name_lb.add_theme_constant_override("outline_size", 6)
	var hp := Label.new()
	hp.text = "HP %d   MP %d" % [int(st.get("HP", 0)), int(st.get("MP", 0))]
	hp.add_theme_font_size_override("font_size", 16)
	hp.modulate = Color(0.82, 0.86, 0.8)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(160, 3)
	bar.color = Color(0.35, 0.55, 0.42)
	row.add_child(name_lb)
	row.add_child(hp)
	row.add_child(bar)
	party_box.add_child(row)

## 等级可能落在表的档位之间：取不超过该等级的最大档位。
func _stats_for(character_id: String, level: int) -> Dictionary:
	var table: Dictionary = GameData.character(character_id).get("table", {})
	var best_lv := -1
	var best: Dictionary = {}
	for k in table.keys():
		var lv := int(k)
		if lv <= level and lv > best_lv:
			best_lv = lv
			best = table[k]
	if best.is_empty() and not table.is_empty():
		best = table[table.keys()[0]]
	return best

func _on_party_changed(_members: Array) -> void:
	_refresh_party()
