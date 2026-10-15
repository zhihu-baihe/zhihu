extends Node3D
class_name NPCActor
## NPC 演员：从数据读取显示名与配色，并把 npc_id 交给子节点的交互组件。
## 数据来源：dialogue.json 的 npcs 段（显示名 / 颜色 / 体型缩放）。

@export var npc_id := "NPC_LIU"
@export var name_override := ""

@onready var body: MeshInstance3D = $Model/Body
@onready var head: MeshInstance3D = $Model/Head
@onready var hat: MeshInstance3D = $Model/Hat
@onready var label: Label3D = $NameLabel
@onready var interactable: Area3D = $Interactable

func _ready() -> void:
	add_to_group("npc")
	var meta := GameData.npc_meta(npc_id)
	var shown := name_override if name_override != "" else GameData.npc_name(npc_id)
	if label:
		label.text = shown
	_apply_colors(meta)
	var s := float(meta.get("scale", 1.0))
	if not is_equal_approx(s, 1.0):
		$Model.scale = Vector3.ONE * s
	if interactable and interactable.has_method("set_npc_id"):
		interactable.set_npc_id(npc_id)

func _apply_colors(meta: Dictionary) -> void:
	var body_color := Color(str(meta.get("body", "#7d7d7d")))
	var accent := Color(str(meta.get("color", "#c9a24a")))
	if body:
		body.material_override = MatCache.solid(body_color, 0.85)
	if head:
		head.material_override = MatCache.solid(body_color.lightened(0.28), 0.8)
	if hat:
		hat.material_override = MatCache.solid(accent, 0.7)
