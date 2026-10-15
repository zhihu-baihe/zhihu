extends Node
## 主场景脚本：装配世界、UI 与淡入淡出；并支持命令行截图（开发期自检用）。
## 用法：
##   godot --path . -- --screenshot=shots/town.png --shot-view=town
##   --shot-view: player（默认，跟随玩家）/ town（城镇俯瞰）/ bridge（千灯桥）

@onready var world_root: Node = $WorldRoot
@onready var fade: ColorRect = $FadeLayer/Fade

var _shot_path := ""
var _shot_view := "player"

func _ready() -> void:
	SceneRouter.setup(world_root, fade)
	_parse_args()
	await SceneRouter.change_world("res://scenes/world/moyi_town.tscn", Vector3.INF, 0.0, 0.3)
	if _shot_path != "":
		await _capture()

func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--screenshot="):
			_shot_path = a.substr("--screenshot=".length())
		elif a.begins_with("--shot-view="):
			_shot_view = a.substr("--shot-view=".length())

func _capture() -> void:
	await get_tree().create_timer(1.2).timeout
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 400.0
	match _shot_view:
		"town":
			add_child(cam)
			cam.fov = 50.0
			cam.look_at_from_position(Vector3(40, 40, 46), Vector3(0, 2, -12), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"bridge":
			add_child(cam)
			cam.fov = 55.0
			cam.look_at_from_position(Vector3(0, 9, -45), Vector3(0, 3, -27), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"menu":
			var mp := get_node_or_null("MenuPanel")
			if mp and mp.has_method("open"):
				mp.open()
			await get_tree().create_timer(0.6).timeout
		"menu_save":
			var mp2 := get_node_or_null("MenuPanel")
			if mp2 and mp2.has_method("open"):
				mp2.open()
				mp2.set("page", 3)
				mp2.call("_refresh")
			await get_tree().create_timer(0.8).timeout
		"dialogue":
			DialogueRunner.start_node("MOYI_ATANG_010")
			await get_tree().create_timer(0.25).timeout
			DialogueRunner.advance()
			await get_tree().create_timer(0.25).timeout
			DialogueRunner.advance()
			await get_tree().create_timer(1.8).timeout
		_:
			# 跟随玩家视角：直接使用玩家相机
			pass
	await _shoot()

func _shoot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	if err == OK:
		print("[Main] 截图已保存：%s（%dx%d）" % [_shot_path, img.get_width(), img.get_height()])
	else:
		push_error("[Main] 截图保存失败，错误码 %d" % err)
	get_tree().quit()
