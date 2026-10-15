extends Interactable
class_name CluePoint
## 调查点：播放指定对白；若对白效果给予了线索，则本调查点自动熄灭。

@export var dialogue_id := ""
@export var clue_id := ""
@export var marker_node_path: NodePath = ^"Marker"

var _marker: Node3D = null
var _t := 0.0

func _ready() -> void:
	super._ready()
	_marker = get_node_or_null(marker_node_path) as Node3D
	if clue_id != "" and GameState.has_clue(clue_id):
		_set_spent()

func _process(delta: float) -> void:
	if _marker == null or not _marker.visible:
		return
	_t += delta
	_marker.rotation.y = _t * 0.8
	_marker.position.y = 0.95 + sin(_t * 1.6) * 0.06

func get_prompt() -> String:
	if disabled:
		return ""
	return prompt_text

func _on_interact(_who: Node) -> void:
	if dialogue_id == "":
		return
	var started := DialogueRunner.start_node(dialogue_id)
	if not started:
		return
	await DialogueRunner.dialogue_finished
	if clue_id != "" and GameState.has_clue(clue_id):
		_set_spent()

func _set_spent() -> void:
	set_disabled(true)
	if _marker:
		_marker.visible = false
	var mesh := get_node_or_null("Marker") as MeshInstance3D
	if mesh:
		mesh.visible = false
