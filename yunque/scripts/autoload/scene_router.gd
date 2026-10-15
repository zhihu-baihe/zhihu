extends Node
## 场景路由（Autoload: SceneRouter）
## 职责：世界场景的加载/卸载、黑场淡入淡出、把玩家放到出生点。
## M1 只有一个世界（墨邑）；M2 起用于「城镇 ↔ 旧灯坊迷宫」的切换。

signal world_loaded(path: String)
signal fade_finished()

var _world_root: Node = null
var _fade: ColorRect = null

func setup(world_root: Node, fade_rect: ColorRect) -> void:
	_world_root = world_root
	_fade = fade_rect
	if _fade:
		_fade.color = Color(0, 0, 0, 1)
		_fade.visible = true

## 切换世界场景；spawn 为世界坐标出生点，yaw_deg 为朝向。
func change_world(path: String, spawn: Vector3 = Vector3.INF, yaw_deg: float = 0.0, fade_time: float = 0.35) -> void:
	if _world_root == null:
		push_error("[SceneRouter] 未调用 setup()，无法切换场景。")
		return
	await fade_out(fade_time)
	for child in _world_root.get_children():
		child.queue_free()
	await get_tree().process_frame

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[SceneRouter] 场景加载失败：%s" % path)
		await fade_in(fade_time)
		return
	var world := packed.instantiate()
	_world_root.add_child(world)
	await get_tree().process_frame

	if spawn != Vector3.INF:
		var player := _find_player(world)
		if player:
			player.global_position = spawn
			player.set_spawn_yaw(yaw_deg)
	await fade_in(fade_time)
	world_loaded.emit(path)

func current_world() -> Node:
	if _world_root == null:
		return null
	for c in _world_root.get_children():
		return c
	return null

func fade_out(t: float = 0.35) -> void:
	if _fade == null:
		return
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	await tw.finished
	fade_finished.emit()

func fade_in(t: float = 0.35) -> void:
	if _fade == null:
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, t)
	await tw.finished
	_fade.visible = false
	fade_finished.emit()

func _find_player(world: Node) -> Node:
	if world.has_method("get_player"):
		return world.get_player()
	var found := world.find_child("Player", true, false)
	return found
