extends CanvasLayer
class_name DialogueBox
## 对白 UI（依据 CHAR-UI-02 v0.4 §UI-07）：底部单层对白框，说话人 + 不超过 2—3 行对白。
## 纸白底 + 墨色正文 + 朱砂小标记；不使用深色底框与金边。
## 输入：对白进行中，E / 空格 / 回车 / 鼠标左键 = 立即显示全文或推进到下一行。
## frame lock：用 E 触发对白的那一帧不能立刻把第一行跳过去。

const CHARS_PER_SECOND := 38.0

@onready var panel: PanelContainer = $Panel
@onready var name_row: HBoxContainer = $Panel/Margin/VBox/NameRow
@onready var name_label: Label = $Panel/Margin/VBox/NameRow/NameLabel
@onready var text_label: Label = $Panel/Margin/VBox/TextLabel
@onready var hint_label: Label = $Panel/Margin/VBox/HintLabel

var _full_text := ""
var _revealed := 0.0
var _typing := false
var _lock_frame := -1
var _blip_steps := 0

func _ready() -> void:
	UITheme.apply(self, UITheme.build())
	panel.visible = false
	DialogueRunner.dialogue_started.connect(_on_started)
	DialogueRunner.line_shown.connect(_on_line)
	DialogueRunner.dialogue_finished.connect(_on_finished)

func _process(delta: float) -> void:
	if not _typing:
		return
	_revealed += CHARS_PER_SECOND * delta
	var n := int(_revealed)
	# 打字音：每 3 个字响一次，否则密到像噪音（音量压得很低）
	var steps := n / 3
	if steps != _blip_steps:
		_blip_steps = steps
		AudioDirector.play_sfx("dialogue_blip", -19.0, 0.07)
	if n >= _full_text.length():
		_revealed = float(_full_text.length())
		_typing = false
		hint_label.text = "E / 空格 继续"
	text_label.text = _full_text.substr(0, int(_revealed))

func _unhandled_input(event: InputEvent) -> void:
	if not DialogueRunner.active:
		return
	if Engine.get_process_frames() <= _lock_frame:
		return
	var advance := false
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		advance = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if not advance:
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_revealed = float(_full_text.length())
		_typing = false
		text_label.text = _full_text
		hint_label.text = "E / 空格 继续"
	else:
		DialogueRunner.advance()

func _on_started(_node_id: String, _lines: Array) -> void:
	panel.visible = true
	_lock_frame = Engine.get_process_frames()

func _on_line(_index: int, speaker: String, text: String) -> void:
	# 旁白（用「（……）」包裹）不显示名字，正文转次级墨色
	var is_narration := speaker.begins_with("（")
	name_row.visible = not is_narration
	name_label.text = speaker
	text_label.modulate = UITheme.INK_SUB if is_narration else UITheme.INK_MAIN
	_full_text = text
	_revealed = 0.0
	_typing = true
	_blip_steps = 0
	text_label.text = ""
	hint_label.text = "E / 空格 跳过"

func _on_finished(_node_id: String) -> void:
	panel.visible = false
	_typing = false
	_full_text = ""
	text_label.text = ""
