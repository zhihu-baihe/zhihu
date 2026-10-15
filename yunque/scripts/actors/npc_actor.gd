extends Node3D
class_name NPCActor
## NPC 演员：从数据读取显示名与配色，用 HumanoidBuilder 生成人形并驱动待机动作。
## 数据来源：dialogue.json 的 npcs 段（显示名 / 颜色 / 体型缩放）。

@export var npc_id := "NPC_LIU"
@export var name_override := ""

@onready var model: Node3D = $Model
@onready var label: Label3D = $NameLabel
@onready var interactable: Area3D = $Interactable

var rig: HumanoidRig = null

func _ready() -> void:
	add_to_group("npc")
	var meta := GameData.npc_meta(npc_id)
	var shown := name_override if name_override != "" else GameData.npc_name(npc_id)
	if label:
		label.text = shown
	_build_humanoid(meta)
	var s := float(meta.get("scale", 1.0))
	if not is_equal_approx(s, 1.0) and model:
		model.scale = Vector3.ONE * s
	if interactable and interactable.has_method("set_npc_id"):
		interactable.set_npc_id(npc_id)

func _build_humanoid(meta: Dictionary) -> void:
	if model == null:
		return
	var cfg := {
		"robe": Color(str(meta.get("body", "#7d7d7d"))),
		"trim": Color(str(meta.get("color", "#c9a24a"))),
		"skin": Color(str(meta.get("skin", HumanoidBuilder.DEFAULT_SKIN))),
		"hair": Color(str(meta.get("hair", HumanoidBuilder.DEFAULT_HAIR))),
		"boot": Color(str(meta.get("boot", HumanoidBuilder.DEFAULT_BOOT))),
	}
	rig = HumanoidBuilder.build(model, cfg)

## 供后续 NPC 巡走使用（当前 NPC 全部站定，速度恒为 0）。
func set_locomotion(speed: float) -> void:
	if rig:
		rig.set_locomotion(speed)
