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
		"roof":
			# 建筑近景（斜俯）：验收屋面曲率、正脊翘头、檐下椽头、石台基
			add_child(cam)
			cam.fov = 50.0
			cam.look_at_from_position(Vector3(4.5, 7.5, 31.5), Vector3(-13.5, 3.4, 21), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"facade":
			# 正立面（平视）：验收格子窗、檐柱、门洞与招牌
			add_child(cam)
			cam.fov = 52.0
			cam.look_at_from_position(Vector3(2.5, 2.4, 24), Vector3(-9.5, 2.9, 24), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"base":
			# 墙基特写（低机位近距）：验收台明 / 踏跺 / 勒脚 / 压顶石 / 柱础 的层叠关系
			add_child(cam)
			cam.fov = 40.0
			cam.look_at_from_position(Vector3(-2.6, 1.60, 25.2), Vector3(-9.6, 0.85, 23.6), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"gate":
			# 城门（城内向北望南门）：验收门楣、匾额、女儿墙、箭楼亮窗与门楣灯笼串
			add_child(cam)
			cam.fov = 50.0
			cam.look_at_from_position(Vector3(0, 2.0, 21.0), Vector3(0, 5.0, 42.0), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.4).timeout
		"char":
			# 角色特写：验收人形比例、配色、待机姿态与佩剑
			add_child(cam)
			cam.fov = 40.0
			var pl := SceneRouter._find_player(SceneRouter.current_world())
			var pb := Vector3(0, 0, 34)
			if pl:
				pb = (pl as Node3D).global_position
			cam.look_at_from_position(pb + Vector3(2.3, 1.45, 2.9), pb + Vector3(0, 0.98, 0), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.5).timeout
		"npc":
			# NPC 特写：站在 NPC 正前方拍摄（模型的正面是 -Z）
			add_child(cam)
			cam.fov = 42.0
			var npcs := get_tree().get_nodes_in_group("npc")
			var target := Vector3(-5.2, 0, 33.5)
			var nyaw := 120.0
			if npcs.size() > 1:
				var n2 := npcs[1] as Node3D
				target = n2.global_position
				nyaw = rad_to_deg(n2.rotation.y)
			var nr := deg_to_rad(nyaw)
			var nfwd := Vector3(-sin(nr), 0.0, -cos(nr))
			cam.look_at_from_position(target + nfwd * 3.5 + Vector3(0, 1.45, 0),
				target + Vector3(0, 1.02, 0), Vector3.UP)
			cam.current = true
			await get_tree().create_timer(0.5).timeout
		"walk":
			# 步态验收：把角色冻结在步态的一个特定相位上（静态截图看不出动画）
			add_child(cam)
			cam.fov = 42.0
			var pl3 := SceneRouter._find_player(SceneRouter.current_world())
			if pl3:
				var pb3: Vector3 = (pl3 as Node3D).global_position
				cam.look_at_from_position(pb3 + Vector3(2.5, 1.5, 3.0), pb3 + Vector3(0, 0.95, 0), Vector3.UP)
				cam.current = true
				(pl3 as Node).set_physics_process(false)
				var r = pl3.get("rig")
				if r is HumanoidRig:
					var hr := r as HumanoidRig
					hr.set_process(false)
					hr.motion_speed = 3.4
					hr.set("_blend", 1.0)
					hr.set("_phase", 1.30)
					hr.call("_process", 0.0)
			await get_tree().create_timer(0.3).timeout
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
