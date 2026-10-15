extends Node3D
class_name TownWorld
## 墨邑世界场景根节点：应用环境 → 生成地图 → 放置玩家。

@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var moon: DirectionalLight3D = $Moon
@onready var geometry: Node3D = $Geometry
@onready var actors: Node3D = $Actors
@onready var player: CharacterBody3D = $Player

var map: Dictionary = {}
var stats: Dictionary = {}

func _ready() -> void:
	map = GameData.map_data("map_moyi")
	_apply_environment()
	stats = TownBuilder.build(geometry, actors, map)
	var sp: Dictionary = map.get("spawn", {})
	var p: Array = sp.get("pos", [0, 0.2, 38])
	player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if player.has_method("set_spawn_yaw"):
		player.set_spawn_yaw(float(sp.get("yaw_deg", 0.0)))
	print("[TownWorld] 墨邑生成完成：%s，动态灯 %d 盏。" % [str(map.get("display_name", "?")), int(stats.get("lights_used", 0))])
	# 环境音三层（夜风 / 河水 / 虫鸣）按地图配置淡入
	AudioDirector.enter_world(map)

func get_player() -> Node:
	return player

## 供存档记录地图名
func display_name() -> String:
	return str(map.get("display_name", "墨邑古城"))

func _apply_environment() -> void:
	# 时段预设：按当前 time_band 取参数；缺预设时回落到 environment 兜底块。
	var presets: Dictionary = map.get("environment_presets", {})
	var e: Dictionary = presets.get(GameState.time_band, {})
	if e.is_empty():
		e = map.get("environment", {})
	var pal: Dictionary = map.get("palette", {})

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(str(e.get("sky_top", "#101a28")))
	sky_mat.sky_horizon_color = Color(str(e.get("sky_horizon", "#8a5236")))
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(str(e.get("sky_ground_bottom", "#0b0f14")))
	sky_mat.ground_horizon_color = Color(str(e.get("sky_ground_horizon", "#3a3026")))
	sky_mat.ground_curve = 0.1
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = float(e.get("ambient_energy", 0.4))

	env.fog_enabled = bool(e.get("fog_enabled", true))
	env.fog_light_color = Color(str(e.get("fog_color", "#2c3644")))
	env.fog_density = float(e.get("fog_density", 0.011))
	env.fog_sky_affect = float(e.get("fog_sky_affect", 0.35))
	env.fog_aerial_perspective = 0.15

	env.glow_enabled = bool(e.get("glow_enabled", true))
	env.glow_intensity = float(e.get("glow_strength", 0.55))
	env.glow_bloom = float(e.get("glow_bloom", 0.25))
	env.glow_hdr_threshold = 0.85
	env.ssao_enabled = bool(e.get("ssao_enabled", true))
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.4
	# 屏幕空间反射：湿石街与水面反射灯火，是参考图的核心视觉手段
	var ssr := bool(e.get("ssr_enabled", false))
	env.ssr_enabled = ssr
	if ssr:
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 12.0
		env.ssr_depth_tolerance = 0.2
	env.tonemap_mode = int(e.get("tonemap_mode", 3))
	env.tonemap_exposure = float(e.get("tonemap_exposure", 1.05))
	environment.environment = env

	sun.light_color = Color(str(e.get("sun_color", "#9fb6d4")))
	sun.light_energy = float(e.get("sun_energy", 0.3))
	var sr: Array = e.get("sun_rotation_deg", [-34, 122, 0])
	sun.rotation_degrees = Vector3(float(sr[0]), float(sr[1]), float(sr[2]))
	sun.shadow_enabled = true

	moon.light_color = Color(str(e.get("moon_color", "#cfe0ff")))
	moon.light_energy = float(e.get("moon_energy", 0.35))
	var mr: Array = e.get("moon_rotation_deg", [-28, 300, 0])
	moon.rotation_degrees = Vector3(float(mr[0]), float(mr[1]), float(mr[2]))
	moon.shadow_enabled = false
	# 让夜景的地面不至于全黑：给一点来自河面的冷色补光由 sky 环境光承担
