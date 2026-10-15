extends Area3D
class_name TriggerZone
## 剧情触发器（设计文档 §24 事件驱动）：进入范围且条件满足时播放对白，只触发一次。
## 用于「纸轿穿过人群、阿禾追进侧巷」这类不由玩家点击触发的过场。

@export var dialogue_id := ""
@export var required_flags: PackedStringArray = []
@export var forbidden_flags: PackedStringArray = []
@export var one_shot := true
@export var radius := 6.0

var _fired := false

func _ready() -> void:
	add_to_group("trigger_zone")
	monitoring = true
	monitorable = false
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is SphereShape3D:
		var s: SphereShape3D = cs.shape.duplicate()
		s.radius = radius
		cs.shape = s
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _fired and one_shot:
		return
	if not body.is_in_group("player"):
		return
	if DialogueRunner.active:
		return
	if dialogue_id == "" or GameState.is_dialogue_seen(dialogue_id):
		return
	if not GameState.matches(required_flags, forbidden_flags):
		return
	if DialogueRunner.start_node(dialogue_id):
		_fired = true
