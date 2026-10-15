class_name TownBuilder
extends RefCounted
## 墨邑灰盒生成器：把 data/map_moyi.json 的逻辑布局翻译成实际几何体、灯光、NPC 与交互点。
## 设计意图：地图是数据，不是手写节点树；M3 起把 _building / _stall 等替换为模块化模型即可，
## 不需要重做布局与任务数据。

const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
const CLUE_SCENE := preload("res://scenes/props/interact_clue.tscn")
const PICKUP_SCENE := preload("res://scenes/props/interact_pickup.tscn")
const DOOR_SCENE := preload("res://scenes/props/workshop_door.tscn")
const TRIGGER_SCENE := preload("res://scenes/props/trigger_zone.tscn")

## 全场景动态光预算：超过后灯笼只发光、不再挂 OmniLight，避免灰盒阶段就爆光照。
## 30 → 26：分配方式从「先到先得」改成「按重要性 + 最小间距」（见 _allocate_lantern_lights），
## 顺便把余量留给摊位、井亭与桥面 —— 旧实现里它们压根分不到灯。
const LIGHT_BUDGET_MAX := 26
## 全局灯光能量缩放：夜景验收要求「蓝灰环境光 + 暖灯」，避免灯笼过曝、暗部丢细节。
const LIGHT_ENERGY_SCALE := 0.75
## 灯笼动态光的候选。**不在 _lantern_row 里直接建灯**，原因见 _allocate_lantern_lights。
static var _lantern_lights: Array[Dictionary] = []
static var _lights_left := LIGHT_BUDGET_MAX

## 灯笼抖动（位置 / 高度 / 形状 / 尺寸 / 亮度）的随机种子。
## **固定种子是刻意的**：截图必须能复现，否则每次跑出来都不一样，改动的效果就无从对比。
## 要换一版排列，改这个数即可。
const BUILD_SEED := 20261015
static var _rng := RandomNumberGenerator.new()

static func reset_budget() -> void:
	_lights_left = LIGHT_BUDGET_MAX
	_lantern_lights.clear()
	_rng.seed = BUILD_SEED


# ================================================================ 入口

## 构建整个地图。返回附加信息（出生点等）。
static func build(geometry: Node3D, actors: Node3D, map: Dictionary) -> Dictionary:
	reset_budget()
	var pal: Dictionary = map.get("palette", {})

	for t in _arr(map, "terrain"):
		_terrain(geometry, t, pal)
	for w in _arr(map, "walls"):
		_wall(geometry, w, pal)
	if map.has("gate"):
		_gate(geometry, map["gate"], pal)
	for s in _arr(map, "streets"):
		_street(geometry, s, pal)
	if map.has("bridge"):
		_bridge(geometry, map["bridge"], pal)
	for b in _arr(map, "buildings"):
		_building(geometry, b, pal)
	if map.has("stage"):
		_stage(geometry, map["stage"], pal)
	for s in _arr(map, "stalls"):
		_stall(geometry, s, pal)
	for r in _arr(map, "lantern_rows"):
		_lantern_row(geometry, r, pal)
	for p in _arr(map, "props"):
		_prop(geometry, p, pal)
	for m in _arr(map, "mountains"):
		_mountain(geometry, m, pal)
	for pg in _arr(map, "pagodas"):
		_pagoda(geometry, pg, pal)

	for n in _arr(map, "npcs"):
		_npc(actors, n)
	for i in _arr(map, "interactables"):
		_interactable(actors, i)
	for t in _arr(map, "triggers"):
		_trigger(actors, t)

	# 灯笼的动态光放在最后分配：此时城门 / 桥头 / 戏台 / 摊位已经拿到灯，
	# 剩下的预算才是灯笼能用的（旧实现是反过来的，见 _allocate_lantern_lights）。
	_allocate_lantern_lights(geometry)

	return {"lights_used": LIGHT_BUDGET_MAX - _lights_left}


# ================================================================ 基础几何

static func _col(pal: Dictionary, key: String, fallback := "#888888") -> Color:
	return Color(str(pal.get(key, fallback)))

## 调色板键 → 真实 PBR 贴图集。[贴图集名, 世界平铺尺度]
## 没有映射的键继续用纯色，保证灰盒与正式资产可以逐块替换、互不影响。
##
## world_scale 怎么来的（不要肉眼试，跑 tools/calibrate_textures.py 一次算好）
## ---------------------------------------------------------------------------
## 三平面映射是 `uv = 世界坐标 × world_scale`，所以：
##     一个贴图周期的实际边长 = 1 / world_scale
##     单块尺寸 = 周期边长 ÷ 贴图内该方向的块数
## 反过来：world_scale = 1 / (块数 × 目标单块尺寸)
## 块数取 NormalGL/Displacement 图的主频（FFT），不是彩图——彩图会有伪峰。
##
##   roof       RoofTilesQing  横 19 条脊 × 0.18 m(筒瓦瓦垄) = 3.425 m → 0.292
##   stone      PavingStones070 12 × 12 块 × 0.45 m(方石)    = 5.405 m → 0.185
##   stone_dark 同上，但取 0.347 m 的碎料尺度给勒脚/踏跺      = 4.167 m → 0.240
##   wood       PlanksWood      纵 16 道板缝 × 0.22 m(板宽)   = 3.571 m → 0.280
##   cloth_*    FabricWeave     横 35 根织线 × 5.7 mm         = 0.200 m → 5.000
##   wall       Plaster001      无周期结构（抹灰），尺度不敏感
const TEX_ROOT := "res://assets/processed/textures/"
const TEX_MAP := {
	"roof": ["RoofTilesQing", 0.292],
	"roof_dark": ["RoofTilesQing", 0.292],
	"wall": ["Plaster001", 0.32],
	"stone": ["PavingStones070", 0.185],
	"stone_dark": ["PavingStones070", 0.24],
	"wood": ["PlanksWood", 0.28],
	"wood_dark": ["PlanksWood", 0.28],
	"cloth_red": ["FabricWeave", 5.0],
	"cloth_gold": ["FabricWeave", 5.0],
	"cloth_green": ["FabricWeave", 5.0],
}

static var _mat_cache: Dictionary = {}

## 取材质：调色板键有贴图集时返回「贴图 + 该键颜色作色调」，否则回退纯色。
## tint_override 用于需要压暗/变体的场合（如墙帽、湿石街）。
static func _mat(pal: Dictionary, key: String, roughness := 0.85,
		tint_override := Color(0, 0, 0, 0), double_sided := false) -> Material:
	var color := _col(pal, key)
	if tint_override.a > 0.0:
		color = tint_override
	if not TEX_MAP.has(key):
		if not double_sided:
			return MatCache.solid(color, roughness)
		var sk := "DS|%s|%.2f" % [color.to_html(true), roughness]
		if _mat_cache.has(sk):
			return _mat_cache[sk]
		var sm := MatCache.solid(color, roughness).duplicate() as StandardMaterial3D
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[sk] = sm
		return sm
	var entry: Array = TEX_MAP[key]
	var set_name := str(entry[0])
	var world_scale := float(entry[1])
	var ck := "%s|%s|%.2f|%.2f|%s" % [set_name, color.to_html(true), world_scale, roughness, str(double_sided)]
	if _mat_cache.has(ck):
		return _mat_cache[ck]
	var base := TEX_ROOT + set_name + "/" + set_name + "_1K-JPG_"
	var m := MatCache.textured(base + "Color.jpg", base + "NormalGL.jpg",
		base + "Roughness.jpg", base + "AmbientOcclusion.jpg", world_scale, color, roughness, 1.0, double_sided)
	_mat_cache[ck] = m
	return m

static func _make_body(parent: Node3D, nm: String, pos: Vector3, yaw_deg: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(body)
	return body

static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material,
		collide := true, yaw_deg := 0.0, nm := "Box") -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	if not collide:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation.y = deg_to_rad(yaw_deg)
		parent.add_child(mi)
		return mi
	var body := _make_body(parent, nm, pos, yaw_deg)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = mesh
	mi2.material_override = mat
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(mi2)
	body.add_child(cs)
	return body

static func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float,
		mat: Material, collide := true, nm := "Cyl") -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	if not collide:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := _make_body(parent, nm, pos, 0.0)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = mesh
	mi2.material_override = mat
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(mi2)
	body.add_child(cs)
	return body

static func _prism(parent: Node3D, pos: Vector3, size: Vector3, mat: Material,
		yaw_deg := 0.0, nm := "Prism") -> Node3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	var body := _make_body(parent, nm, pos, yaw_deg)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5) * size, Vector3(0.5, -0.5, -0.5) * size,
		Vector3(0.0, 0.5, -0.5) * size, Vector3(-0.5, -0.5, 0.5) * size,
		Vector3(0.5, -0.5, 0.5) * size, Vector3(0.0, 0.5, 0.5) * size,
	])
	cs.shape = shape
	body.add_child(mi)
	body.add_child(cs)
	return body

static func _sphere(parent: Node3D, pos: Vector3, radius: float, mat: Material,
		nm := "Sphere", collide := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := _make_body(parent, nm + "Body", pos, 0.0)
		var cs := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		cs.shape = shape
		body.add_child(cs)
	return mi

## 斜面（坡道）：局部 X 轴方向抬升 rise_deg。
static func _ramp(parent: Node3D, pos: Vector3, size: Vector3, rise_deg: float,
		yaw_deg: float, mat: Material, nm := "Ramp") -> Node3D:
	var body := _make_body(parent, nm, pos, yaw_deg)
	body.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(rise_deg))
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(mi)
	body.add_child(cs)
	return body

static func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float,
		attenuation := 1.0) -> void:
	if _lights_left <= 0:
		return
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * LIGHT_ENERGY_SCALE
	l.omni_range = range_m
	# 衰减指数 >1 让光斑边缘更柔：默认 1.0 时灯笼在石面上是一块硬边圆斑。
	l.omni_attenuation = attenuation
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = range_m * 2.5
	l.distance_fade_length = 12.0
	parent.add_child(l)
	_lights_left -= 1

static func _label(parent: Node3D, pos: Vector3, text: String, color: Color,
		font_size := 72, pixel_size := 0.006, yaw_deg := 0.0) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = font_size
	lb.pixel_size = pixel_size
	lb.modulate = color
	lb.outline_size = 10
	lb.outline_modulate = Color(0.05, 0.05, 0.06, 0.9)
	lb.position = pos
	lb.rotation.y = deg_to_rad(yaw_deg)
	lb.no_depth_test = false
	lb.shaded = false
	parent.add_child(lb)
	return lb


# ================================================================ 中式木构构件
#
# 参考图的辨识度来自**造型**而非贴图：屋面要「反宇」（脊陡、檐缓、角翘），
# 要有正脊与翘头、檐下密排椽头、立面檐柱与格子窗、底部石台基。
# 这些全部程序化生成，不依赖任何外部模型；布局仍完全由 map_moyi.json 驱动。

## 盒体 8 顶点（顺序固定，与 CUBE_INDEX 配套）。
static func _box_verts(c: Vector3, s: Vector3) -> Array:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	return [
		c + Vector3(-hx, -hy, -hz), c + Vector3(hx, -hy, -hz),
		c + Vector3(hx, hy, -hz), c + Vector3(-hx, hy, -hz),
		c + Vector3(-hx, -hy, hz), c + Vector3(hx, -hy, hz),
		c + Vector3(hx, hy, hz), c + Vector3(-hx, hy, hz),
	]

## 12 个三角形索引（逆时针 = 法线朝外）。
const CUBE_INDEX := [
	0, 3, 2, 0, 2, 1,
	4, 5, 6, 4, 6, 7,
	0, 4, 7, 0, 7, 3,
	1, 2, 6, 1, 6, 5,
	3, 7, 6, 3, 6, 2,
	0, 1, 5, 0, 5, 4,
]

## 把一批盒体合并成单个网格。
## 一副立面的椽头 + 窗棂就是几十根木头，逐个建节点会让场景树爆掉，所以合并。
## boxes: [[Vector3 中心, Vector3 尺寸], ...]（中心为 origin/yaw 定义的空间）
static func _merged(parent: Node3D, nm: String, mat: Material, origin: Vector3,
		yaw_deg: float, boxes: Array) -> MeshInstance3D:
	if boxes.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bi in boxes.size():
		var e = boxes[bi]
		var c: Vector3 = e[0]
		var s: Vector3 = e[1]
		var vs := _box_verts(c, s)
		for i: int in CUBE_INDEX:
			var v: Vector3 = vs[i]
			st.set_uv(Vector2(v.x, v.z) * 0.5)
			st.add_vertex(v)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = origin
	mi.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(mi)
	return mi

## 世界坐标版合并：盒体坐标已经是世界坐标（轴对齐的柱础、窗棂用这个）。
static func _merged_world(parent: Node3D, nm: String, mat: Material, boxes: Array) -> MeshInstance3D:
	return _merged(parent, nm, mat, Vector3.ZERO, 0.0, boxes)

## 屋脊方向（局部 +X）在世界空间的方向。
static func _ridge_dir(yaw_deg: float) -> Vector3:
	var r := deg_to_rad(yaw_deg)
	return Vector3(cos(r), 0.0, -sin(r))

## 曲面屋面：中式「反宇」双坡顶 + 翼角起翘。
## 局部坐标：+X 沿屋脊，Z 为坡向，Y 向上；center 为屋脊中点的水平位置（世界）。
## eave_h / ridge_h 为檐口 / 正脊相对地面的高度。
static func _roof_curved(parent: Node3D, center: Vector3, yaw_deg: float,
		length: float, half_depth: float, eave_h: float, ridge_h: float,
		mat: Material, nm := "RoofCurved", opts: Dictionary = {}) -> MeshInstance3D:
	var lift := float(opts.get("corner_lift", 0.6))
	var q := float(opts.get("curve", 1.75))
	var camber := float(opts.get("ridge_camber", 0.06))
	var u_seg := maxi(4, int(opts.get("u_seg", 12)))
	var v_seg := maxi(3, int(opts.get("v_seg", 8)))
	var verts: Array = []
	for iu in range(u_seg + 1):
		for iv in range(v_seg + 1):
			var u := float(iu) / float(u_seg)
			var v := float(iv) / float(v_seg) * 2.0 - 1.0
			var ax := absf(v)
			var along := absf(2.0 * u - 1.0)
			# 举折：脊部陡、檐口缓，两坡在正脊处成折角。
			# 方向若反了（脊平檐陡）中式感立刻消失，这是屋面辨识度的第一要素。
			var y := eave_h + (ridge_h - eave_h) * pow(1.0 - ax, q)
			y += camber * (1.0 - along) * (1.0 - ax)
			# 翼角起翘：只在四角抬起
			y += lift * pow(along, 3.0) * pow(ax, 2.5)
			verts.append(Vector3((u - 0.5) * length, y, v * half_depth))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iu in range(u_seg):
		for iv in range(v_seg):
			var i00 := iu * (v_seg + 1) + iv
			var i01 := i00 + 1
			var i10 := (iu + 1) * (v_seg + 1) + iv
			var i11 := i10 + 1
			for i: int in [i00, i01, i11, i00, i11, i10]:
				var p: Vector3 = verts[i]
				st.set_uv(Vector2(p.x, p.z) * 0.6)
				st.add_vertex(p)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = center
	mi.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(mi)
	return mi

## 正脊：脊身 + 两端翘头（只做块面示意，不做具象兽形）。
## center 为正脊中心（世界，含高度）。
static func _ridge_set(parent: Node3D, center: Vector3, yaw_deg: float, length: float,
		mat_body: Material, mat_tip: Material, opts: Dictionary = {}) -> void:
	var w := float(opts.get("width", 0.46))
	var hh := float(opts.get("height", 0.32))
	var inset := float(opts.get("ridge_inset", 0.5))
	var span := length * 0.5 - inset
	if span < 0.6:
		span = maxf(0.3, length * 0.5 - 0.15)
	_box(parent, center, Vector3(span * 2.0, hh, w), mat_body, false, yaw_deg, "RidgeBody")
	var dir := _ridge_dir(yaw_deg)
	for s: float in [-1.0, 1.0]:
		var tip_pos: Vector3 = center + dir * (s * span)
		var tip := _box(parent, tip_pos, Vector3(0.4, hh + 0.34, w * 0.94), mat_tip, false, yaw_deg, "RidgeTip")
		if tip is Node3D:
			(tip as Node3D).rotate_object_local(Vector3(0, 0, 1), deg_to_rad(s * 28.0))

## 檐下密排椽头。
static func _rafter_boxes(center: Vector3, yaw_deg: float, length: float, half_depth: float,
		eave_h: float, opts: Dictionary = {}) -> Array:
	var spacing := float(opts.get("spacing", 0.48))
	var inset := float(opts.get("inset", 0.5))
	var out: Array = []
	var dir := _ridge_dir(yaw_deg)
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var span := maxf(1.0, length - inset * 2.0)
	var n := maxi(2, int(span / spacing))
	var sz := Vector3(0.13, 0.15, 0.6)
	for i in range(n + 1):
		var t := float(i) / float(n)
		var base := center + dir * ((t - 0.5) * span) + Vector3(0.0, eave_h - 0.13, 0.0)
		for s: float in [-1.0, 1.0]:
			out.append([base + perp * (s * (half_depth - 0.14)), sz])
	return out

## 格子窗棂：窗框 + 竖棂 + 一道横绦环。替代表面贴一块自发光方块。
static func _window_boxes(center: Vector3, east_side: bool, w: float, h: float) -> Array:
	var out: Array = []
	var t := 0.075
	var d := 0.1
	if east_side:
		out.append([center + Vector3(0, h * 0.5, 0), Vector3(d, t, w)])
		out.append([center + Vector3(0, -h * 0.5, 0), Vector3(d, t, w)])
		out.append([center + Vector3(0, 0, -w * 0.5), Vector3(d, h, t)])
		out.append([center + Vector3(0, 0, w * 0.5), Vector3(d, h, t)])
		var n := maxi(2, int(w / 0.28))
		for i in range(1, n):
			var z := (float(i) / float(n) - 0.5) * w
			out.append([center + Vector3(0, 0, z), Vector3(d * 0.7, h, t * 0.6)])
		out.append([center + Vector3(0, h * 0.12, 0), Vector3(d * 0.7, t * 0.6, w)])
	else:
		out.append([center + Vector3(0, h * 0.5, 0), Vector3(w, t, d)])
		out.append([center + Vector3(0, -h * 0.5, 0), Vector3(w, t, d)])
		out.append([center + Vector3(-w * 0.5, 0, 0), Vector3(t, h, d)])
		out.append([center + Vector3(w * 0.5, 0, 0), Vector3(t, h, d)])
		var n2 := maxi(2, int(w / 0.28))
		for i in range(1, n2):
			var x := (float(i) / float(n2) - 0.5) * w
			out.append([center + Vector3(x, 0, 0), Vector3(t * 0.6, h, d * 0.7)])
		out.append([center + Vector3(0, h * 0.12, 0), Vector3(w, t * 0.6, d * 0.7)])
	return out

## 一座完整的曲面屋顶套装：屋面 + 正脊 + 檐下椽头（三者共用一套尺寸推导）。
static func _roof_kit(parent: Node3D, center: Vector3, yaw_deg: float, along: float,
		half_depth: float, eave_h: float, ridge_h: float, roof_mat: Material,
		ridge_mat: Material, wood_mat: Material, opts: Dictionary = {}) -> void:
	_roof_curved(parent, center, yaw_deg, along, half_depth, eave_h, ridge_h, roof_mat, "Roof", opts)
	_ridge_set(parent, center + Vector3(0, ridge_h, 0), yaw_deg, along - 0.2, ridge_mat, ridge_mat, opts)
	if bool(opts.get("rafters", true)):
		_merged_world(parent, "Rafters", wood_mat,
			_rafter_boxes(center, yaw_deg, along, half_depth, eave_h, opts))


# ================================================================ 地面与道路

static func _terrain(parent: Node3D, t: Dictionary, pal: Dictionary) -> void:
	var pos := _v3(t.get("pos", [0, 0, 0]))
	var size := _v3(t.get("size", [10, 1, 10]))
	_box(parent, pos, size, _mat(pal, str(t.get("mat", "stone")), 0.95, _col(pal, str(t.get("mat", "stone")), "#6f6a62").darkened(0.18)), true, 0.0, "Terrain")

static func _street(parent: Node3D, s: Dictionary, pal: Dictionary) -> void:
	var kind := str(s.get("kind", "street"))
	# 湿石街：低粗糙度 + SSR，让灯笼在石面上留下反射（参考图的核心视觉手段）
	var street_key := str(s.get("mat", "stone"))
	# 粗糙度 0.42 → 0.66：石板本身不该这么光。0.42 时整条街都是镜面，
	# 反射要靠 SSR 只出现在近处与水面（见 town_world.gd 的 ssr_fade_in）。
	var wet_mat := _mat(pal, street_key, 0.66, _col(pal, street_key).darkened(0.18))
	if kind == "plaza":
		var pos := _v3(s.get("pos", [0, 0, 0]))
		var size := _v3(s.get("size", [10, 0, 10]))
		_box(parent, Vector3(pos.x, 0.03, pos.z), Vector3(size.x, 0.06, size.z),
			wet_mat, false, 0.0, "Plaza")
		return
	var a := _v2(s.get("from", [0, 0]))
	var b := _v2(s.get("to", [0, 0]))
	var width := float(s.get("width", 6.0))
	var d := b - a
	var length := d.length()
	if length <= 0.01:
		return
	var yaw := _yaw_from_dir(d)
	_box(parent, Vector3((a.x + b.x) * 0.5, 0.03, (a.y + b.y) * 0.5),
		Vector3(length, 0.06, width), wet_mat, false, yaw, "Street")

## 远景山体：低模锥体，靠雾与冷色做剪影（第三层）
static func _mountain(parent: Node3D, p: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(p.get("pos", [0, 0]))
	var r := float(p.get("radius", 40.0))
	var h := float(p.get("height", 55.0))
	var mesh := CylinderMesh.new()
	mesh.top_radius = r * 0.06
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 12
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Mountain"
	mi.mesh = mesh
	mi.material_override = MatCache.solid(_col(pal, str(p.get("mat", "ridge")), "#1e2633"), 1.0)
	mi.position = Vector3(pos.x, h * 0.5 - 30.0, pos.y)
	parent.add_child(mi)

## 远景塔：层叠方塔 + 出檐，河对岸山中的地标剪影。
## 118 m 外的塔只有 ~110 px 高，加实体光没有意义（灯照不到、预算也不够），
## 所以「亮」全部由**自发光 + bloom**承担：每层四面一扇暖窗 + 每层檐口一圈冷白轮廓光。
static func _pagoda(parent: Node3D, p: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(p.get("pos", [0, 0]))
	var tiers := maxi(1, int(p.get("tiers", 3)))
	var base := float(p.get("base", 6.0))
	var tier_h := float(p.get("height", 4.0))
	var wall_mat := MatCache.solid(_col(pal, str(p.get("wall_mat", "wood_dark")), "#4f3a27"), 0.9)
	var roof_mat := MatCache.solid(_col(pal, str(p.get("mat", "roof_dark")), "#333c46"), 0.85)
	var win_mat := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 1.15, 0.7)
	var edge_mat := MatCache.emissive(Color(1.0, 0.90, 0.72), 0.80, 0.75)
	var win_boxes: Array = []
	var edge_boxes: Array = []
	var y := 0.0
	for i in tiers:
		var scale_f := 1.0 - 0.18 * float(i)
		var w := base * scale_f
		_box(parent, Vector3(pos.x, y + tier_h * 0.4, pos.y), Vector3(w, tier_h * 0.8, w), wall_mat, false, 0.0, "PagodaTier")
		_prism(parent, Vector3(pos.x, y + tier_h * 0.9, pos.y), Vector3(w * 1.5, tier_h * 0.42, w * 1.5), roof_mat, 0.0, "PagodaRoof")
		# 亮窗：每层四面各一扇，贴在塔身外皮 5 cm 处
		for ax in 4:
			var a := TAU * float(ax) / 4.0
			var d := Vector3(sin(a), 0.0, cos(a))
			var thin: Vector3 = Vector3(0.10, 1.5, 1.15) if absf(d.x) > 0.5 else Vector3(1.15, 1.5, 0.10)
			win_boxes.append([Vector3(pos.x, y + tier_h * 0.42, pos.y) + d * (w * 0.5 + 0.05), thin])
		# 轮廓灯：檐口下沿一圈冷白细线。远处只剩这几条线，也认得出是塔
		var ry := y + tier_h * 0.9 - tier_h * 0.21
		var ew := w * 0.75 - 0.03
		for s: float in [-1.0, 1.0]:
			edge_boxes.append([Vector3(pos.x, ry, pos.y + s * ew), Vector3(ew * 2.0, 0.09, 0.09)])
			edge_boxes.append([Vector3(pos.x + s * ew, ry, pos.y), Vector3(0.09, 0.09, ew * 2.0)])
		y += tier_h * 0.85
	_prism(parent, Vector3(pos.x, y + tier_h * 0.35, pos.y), Vector3(base * 0.5, tier_h * 0.8, base * 0.5), roof_mat, 0.0, "PagodaSpire")
	_merged_world(parent, "PagodaWindows", win_mat, win_boxes)
	_merged_world(parent, "PagodaEdgeGlow", edge_mat, edge_boxes)

static func _wall(parent: Node3D, w: Dictionary, pal: Dictionary) -> void:
	var a := _v2(w.get("from", [0, 0]))
	var b := _v2(w.get("to", [0, 0]))
	var h := float(w.get("height", 5.0))
	var th := float(w.get("thickness", 1.0))
	var d := b - a
	var length := d.length()
	if length <= 0.01:
		return
	var yaw := _yaw_from_dir(d)
	var wall_key := str(w.get("mat", "wall"))
	var wall_col := _col(pal, wall_key, "#a89a88")
	var mat := _mat(pal, wall_key, 0.9)
	_box(parent, Vector3((a.x + b.x) * 0.5, h * 0.5, (a.y + b.y) * 0.5),
		Vector3(length, h, th), mat, true, yaw, "Wall")
	# 墙帽，给灰盒一点轮廓
	_box(parent, Vector3((a.x + b.x) * 0.5, h + 0.12, (a.y + b.y) * 0.5),
		Vector3(length + 0.2, 0.24, th + 0.24), _mat(pal, wall_key, 0.9, wall_col.darkened(0.25)), false, yaw, "WallCap")


# ================================================================ 城门

static func _gate(parent: Node3D, g: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(g.get("pos", [0, 0]))
	var off := float(g.get("tower_offset", 7.0))
	var tsize := _v3(g.get("tower_size", [8, 6, 7.5]))
	var beam_y := float(g.get("beam_y", 6.0))
	var wall_mat := _mat(pal, "wall", 0.9)
	var roof_mat := _mat(pal, "roof", 0.8, Color(0, 0, 0, 0), true)
	var ridge_mat := _mat(pal, "roof_dark", 0.85)
	var wood_dark := _mat(pal, "wood_dark", 0.9)
	var base_mat := _mat(pal, "stone_dark", 0.95)
	# 城台基座
	_box(parent, Vector3(pos.x, 0.5, pos.y), Vector3(off * 2.0 + tsize.x, 1.0, tsize.z + 1.2),
		base_mat, true, 0.0, "GateBase")
	for s in [-1.0, 1.0]:
		var tp := Vector3(pos.x + off * s, tsize.y * 0.5 + 1.0, pos.y)
		_box(parent, tp, tsize, wall_mat, true, 0.0, "GateTower")
		# 箭楼曲面屋顶（脊沿世界 X，与城墙同向）
		_roof_kit(parent, Vector3(tp.x, 0.0, tp.z), 0.0,
			tsize.x + 1.7, (tsize.z + 1.9) * 0.5, tsize.y + 0.85, tsize.y + 2.7,
			roof_mat, ridge_mat, wood_dark, {"corner_lift": 0.7, "spacing": 0.5})
		# 箭楼动态光：原来挂在 z = pos.y + 2.6（城**外**），玩家在城内什么都照不到。
		# 挪到城门内侧，同时给门楣下的灯笼串补光。
		_light(parent, Vector3(pos.x + off * s, 2.9, pos.y - tsize.z * 0.5 - 1.0),
			_col(pal, "lantern", "#ffb457"), 2.0, 11.0)
	# 门楣（过梁）
	_box(parent, Vector3(pos.x, beam_y, pos.y), Vector3(off * 2 + 2.0, 1.3, tsize.z * 0.8),
		_mat(pal, "wood_dark", 0.9), false, 0.0, "GateBeam")
	# 门楣上女儿墙 + 压顶石：城楼平台的观感，且不与两侧箭楼屋顶打架
	_box(parent, Vector3(pos.x, beam_y + 1.15, pos.y), Vector3(off * 2 + 3.0, 1.0, tsize.z * 0.9),
		wall_mat, false, 0.0, "GateParapet")
	_box(parent, Vector3(pos.x, beam_y + 1.78, pos.y), Vector3(off * 2 + 3.3, 0.26, tsize.z * 0.9 + 0.3),
		roof_mat, false, 0.0, "GateCoping")
	for i in 6:
		var t := (float(i) / 5.0 - 0.5) * (off * 2.0 + 1.6)
		_box(parent, Vector3(pos.x + t, beam_y + 1.72, pos.y - tsize.z * 0.45 - 0.1),
			Vector3(0.5, 0.5, 0.4), wall_mat, false, 0.0, "Crenel")

	# ---- 自发光窗：箭楼朝城内那一面各两扇 ----
	# 城门原是纯剪影，加两排暖窗才有「城楼上有人」的活气，且不花动态光预算。
	# 必须配木棂 —— 只放一块自发光板会被读成灯箱，不是窗。
	var gwin_mat := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 0.85, 0.6)
	var gwin_boxes: Array = []
	var gframe_boxes: Array = []
	for s in [-1.0, 1.0]:
		for k: float in [-1.0, 1.0]:
			var wc := Vector3(pos.x + off * s + k * 1.9, 3.3, pos.y - tsize.z * 0.5 - 0.07)
			gwin_boxes.append([wc, Vector3(1.05, 1.45, 0.12)])
			gframe_boxes.append_array(_window_boxes(wc, false, 1.05, 1.45))
	_merged_world(parent, "GateWindows", gwin_mat, gwin_boxes)
	_merged_world(parent, "GateWindowFrame", wood_dark, gframe_boxes)

	# ---- 门楣下一排灯笼（自发光；26 盏动态光预算已满，这里靠 bloom 出光）----
	var lam_top := beam_y - 0.65
	var lam_mat := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 1.25)
	var cord_boxes: Array = []
	for i in 5:
		var lx := pos.x + (float(i) / 4.0 - 0.5) * (off * 2.0 - 1.4)
		var lc := Vector3(lx, lam_top - 0.31, pos.y - tsize.z * 0.5 - 0.34)
		_cylinder(parent, lc, 0.30, 0.62, lam_mat, false, "GateLantern")
		_cylinder(parent, lc + Vector3(0, 0.37, 0), 0.055, 0.14, wood_dark, false, "GateLanternCap")
		var ch := lam_top - (lc.y + 0.31) - 0.07
		if ch > 0.05:
			cord_boxes.append([lc + Vector3(0, 0.31 + ch * 0.5, 0), Vector3(0.05, ch, 0.05)])
	_merged_world(parent, "GateLanternCord", wood_dark, cord_boxes)

	var plaque := str(g.get("plaque", "城门"))
	_label(parent, Vector3(pos.x, beam_y + 0.2, pos.y - tsize.z * 0.45), plaque,
		Color(0.98, 0.9, 0.66), 96, 0.007, 180.0)


# ================================================================ 建筑

## 环绕墙基的一道石活（勒脚 / 压顶石）→ 盒体清单。
##   outer_t   = 这道石活的厚度（墙厚 + 两侧出挑之和）
##   y0 / y1   = 上下沿
##   door_axis = 0 无门；1 门在 ±X 两面之一；2 门在 ±Z 两面之一
##   door_side = 有门的那一面（-1 / +1）
##   gap_half  = 门洞两侧各留的净空半宽
## 有门的那一面断成两段 —— 0.36 m 高的石活横过门洞，会把门下半截直接砌死。
static func _course_boxes(pos: Vector2, fp: Vector2, outer_t: float, y0: float, y1: float,
		door_axis: int, door_side: float, gap_half: float) -> Array:
	var out: Array = []
	var cy := (y0 + y1) * 0.5
	var hh := y1 - y0
	var t := outer_t
	for s: float in [-1.0, 1.0]:
		# ±Z 两条边：板沿 X 铺，长度盖过角部
		if door_axis == 2 and is_equal_approx(s, door_side):
			var seg := fp.x * 0.5 + t * 0.5 - gap_half
			if seg > 0.25:
				for k: float in [-1.0, 1.0]:
					out.append([Vector3(pos.x + k * (gap_half + seg * 0.5), cy, pos.y + s * fp.y * 0.5),
						Vector3(seg, hh, t)])
		else:
			# 两端各缩 0.015：避免与 ±X 那道板的外侧面共面（共面 = z-fighting 闪面）
			out.append([Vector3(pos.x, cy, pos.y + s * fp.y * 0.5),
				Vector3(fp.x + t - 0.03, hh, t)])
		# ±X 两条边：板沿 Z 铺，两端缩进 t/4 埋进上面那两条边里
		if door_axis == 1 and is_equal_approx(s, door_side):
			var seg2 := fp.y * 0.5 - t * 0.25 - gap_half
			if seg2 > 0.25:
				for k2: float in [-1.0, 1.0]:
					out.append([Vector3(pos.x + s * fp.x * 0.5, cy, pos.y + k2 * (gap_half + seg2 * 0.5)),
						Vector3(t, hh, seg2)])
		else:
			out.append([Vector3(pos.x + s * fp.x * 0.5, cy, pos.y),
				Vector3(t, hh, fp.y - t * 0.5)])
	return out


static func _building(parent: Node3D, b: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(b.get("pos", [0, 0]))
	var fp := _v2(b.get("footprint", [10, 8]))
	var h := float(b.get("height", 3.4))
	var yaw := float(b.get("yaw_deg", 90.0))
	var wall_key := str(b.get("wall_mat", "wall"))
	var roof_key := str(b.get("roof_mat", "roof"))
	var wall_mat := _mat(pal, wall_key, 0.9)
	var roof_mat := _mat(pal, roof_key, 0.82, Color(0, 0, 0, 0), true)  # 双面：檐下看得到瓦底
	var ridge_mat := _mat(pal, "roof_dark", 0.85)
	var wood_mat := _mat(pal, "wood", 0.85)
	var wood_dark := _mat(pal, "wood_dark", 0.9)
	var stone_mat := _mat(pal, "stone_dark", 0.95)
	var win_mat := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 1.3, 0.6)
	var th := 0.35
	var front := _front_dir(yaw)
	var east_side := absf(front.x) > 0.5
	var fsign := signf(front.x) if east_side else signf(front.z)

	# ---- 石台基 + 正面踏跺 + 勒脚（均不碰撞：保留原墙碰撞，避免门槛卡住玩家）----
	const PLINTH_H := 0.28        # 台明高度
	const PLINTH_OUT := 0.55      # 台明每侧出挑
	const LE_TOP := 0.64          # 勒脚顶面（勒脚净高 0.36）
	const CAP_TOP := 0.76         # 压顶石顶面
	var door_w := 1.8
	_box(parent, Vector3(pos.x, PLINTH_H * 0.5, pos.y),
		Vector3(fp.x + PLINTH_OUT * 2.0, PLINTH_H, fp.y + PLINTH_OUT * 2.0),
		stone_mat, false, 0.0, "Plinth")
	# 踏跺必须从**台明外缘**往外退着排，不能从建筑中心量。
	# 旧实现是 `dist = 0.76 + (2-k)*0.42`（相对中心），只有 footprint 2~3 m 时才成立；
	# 现在进深 11 m，三级台阶整个埋在 0.28 m 高的台明板里，一张都没露出来。
	const TREAD := 0.30
	var base_edge := (fp.x if east_side else fp.y) * 0.5 + PLINTH_OUT
	for k in 3:
		var half := 0.14 * (float(k) + 1.0) / 3.0
		var dist := base_edge + TREAD * (0.5 + float(2 - k))
		if east_side:
			_box(parent, Vector3(pos.x + fsign * dist, half, pos.y),
				Vector3(TREAD, half * 2.0, 2.4), stone_mat, false, 0.0, "Step")
		else:
			_box(parent, Vector3(pos.x, half, pos.y + fsign * dist),
				Vector3(2.4, half * 2.0, TREAD), stone_mat, false, 0.0, "Step")

	# ---- 勒脚（石砌墙脚）+ 压顶石：文档 08 §2.4 要的两道真实构件 ----
	# 各只占 1 个合并网格，不逐面建节点。压顶换一种粗糙度，好在月光下留一条横向亮线。
	# 门洞那一面必须断开：门扇下沿贴地，横过门洞的石活会把门下半截砌死。
	var door_axis := 1 if east_side else 2
	var door_side := -fsign       # 门洞开在「正面」的反侧（见下面的四面墙代码）
	var gap_half := door_w * 0.5 + 0.15
	var stone_tint := _col(pal, "stone_dark", "#9a948a")
	_merged_world(parent, "PlinthCourse", _mat(pal, "stone_dark", 0.95, stone_tint.darkened(0.12)),
		_course_boxes(pos, fp, th + 0.20, PLINTH_H, LE_TOP, door_axis, door_side, gap_half))
	_merged_world(parent, "PlinthCap", _mat(pal, "stone_dark", 0.86, stone_tint),
		_course_boxes(pos, fp, th + 0.34, LE_TOP, CAP_TOP, door_axis, door_side, gap_half))

	# ---- 四面墙（保留原有门洞逻辑）----
	_box(parent, Vector3(pos.x, h * 0.5, pos.y - fp.y * 0.5), Vector3(fp.x, h, th), wall_mat, true, 0.0, "WallN")
	_box(parent, Vector3(pos.x, h * 0.5, pos.y + fp.y * 0.5), Vector3(fp.x, h, th), wall_mat, true, 0.0, "WallS")
	if east_side:
		var wx := pos.x - signf(front.x) * fp.x * 0.5
		var z0 := pos.y - fp.y * 0.5
		var z1 := pos.y + fp.y * 0.5
		var door_z := pos.y
		_box(parent, Vector3(wx, h * 0.5, (z0 + door_z - door_w * 0.5) * 0.5), Vector3(th, h, door_z - door_w * 0.5 - z0), wall_mat, true, 0.0, "WallA")
		_box(parent, Vector3(wx, h * 0.5, (z1 + door_z + door_w * 0.5) * 0.5), Vector3(th, h, z1 - door_z - door_w * 0.5), wall_mat, true, 0.0, "WallB")
		_box(parent, Vector3(wx, h - 0.35, door_z), Vector3(th, 0.7, door_w), wall_mat, true, 0.0, "WallLintel")
		_box(parent, Vector3(wx - signf(front.x) * 0.12, 1.05, door_z), Vector3(0.14, 2.1, door_w - 0.2), wood_mat, false, 0.0, "DoorLeaf")
	else:
		var wz := pos.y - signf(front.z) * fp.y * 0.5
		var x0 := pos.x - fp.x * 0.5
		var x1 := pos.x + fp.x * 0.5
		var door_x := pos.x
		_box(parent, Vector3((x0 + door_x - door_w * 0.5) * 0.5, h * 0.5, wz), Vector3(door_x - door_w * 0.5 - x0, h, th), wall_mat, true, 0.0, "WallA")
		_box(parent, Vector3((x1 + door_x + door_w * 0.5) * 0.5, h * 0.5, wz), Vector3(x1 - door_x - door_w * 0.5, h, th), wall_mat, true, 0.0, "WallB")
		_box(parent, Vector3(door_x, h - 0.35, wz), Vector3(door_w, 0.7, th), wall_mat, true, 0.0, "WallLintel")
		_box(parent, Vector3(door_x, 1.05, wz - signf(front.z) * 0.12), Vector3(door_w - 0.2, 2.1, 0.14), wood_mat, false, 0.0, "DoorLeaf")

	# ---- 曲面屋面套装（举折双坡 + 正脊 + 檐下椽头）----
	var overhang := 0.9
	var eave_h := h - 0.12
	var along := (fp.y if east_side else fp.x) + overhang * 2.0
	var half_depth := ((fp.x if east_side else fp.y) + overhang * 2.0) * 0.5
	# 屋脊高度按屋面的水平投影反推，而不是按墙高：
	# 中式屋面坡度约 28°，用「墙高 × 0.4」只会得到 13° 的塌屋顶。
	var roof_h := clampf(half_depth * 0.44, 1.5, 3.6)
	var ridge_h := h + roof_h
	var roof_yaw := _yaw_from_dir(Vector2(0, 1)) if east_side else 0.0
	var rc := Vector3(pos.x, 0.0, pos.y)
	_roof_kit(parent, rc, roof_yaw, along, half_depth, eave_h, ridge_h,
		roof_mat, ridge_mat, wood_dark,
		{"corner_lift": 0.62, "spacing": 0.48, "inset": 0.55})

	# ---- 前檐檐柱 + 柱础 ----
	var face_span := (fp.y if east_side else fp.x)
	var wall_out := (fp.x if east_side else fp.y) * 0.5 + 0.16
	var n_col := 4
	for i in n_col:
		var t := float(i) / float(n_col - 1)
		var off := (t - 0.5) * (face_span - 0.9)
		var cp: Vector3
		if east_side:
			cp = Vector3(pos.x + fsign * wall_out, 0.0, pos.y + off)
		else:
			cp = Vector3(pos.x + off, 0.0, pos.y + fsign * wall_out)
		_cylinder(parent, cp + Vector3(0, eave_h * 0.5, 0), 0.125, eave_h, wood_mat, false, "Pillar")
		# 柱础必须坐在压顶石上（CAP_TOP = 0.76）。原来是 0~0.34 —— 加了勒脚之后会被整根埋进石活里。
		_cylinder(parent, cp + Vector3(0, CAP_TOP + 0.17, 0), 0.24, 0.34, stone_mat, false, "PillarBase")

	# ---- 檐口瓦口压边（沿屋檐外缘一道，压住瓦的收口）----
	_merged(parent, "EaveBand", roof_mat, rc, roof_yaw, [
		[Vector3(0, eave_h + 0.02, half_depth - 0.12), Vector3(along, 0.2, 0.3)],
		[Vector3(0, eave_h + 0.02, -(half_depth - 0.12)), Vector3(along, 0.2, 0.3)],
	])

	# ---- 额枋：连接檐柱的水平横梁，中式立面最关键的横向韵律 ----
	var fang_h := eave_h - 0.17
	var fang_boxes: Array = []
	for s: float in [-1.0, 1.0]:
		if east_side:
			fang_boxes.append([Vector3(pos.x + s * wall_out, fang_h, pos.y),
				Vector3(0.18, 0.26, face_span + 0.2)])
		else:
			fang_boxes.append([Vector3(pos.x, fang_h, pos.y + s * wall_out),
				Vector3(face_span + 0.2, 0.26, 0.18)])
	_merged_world(parent, "Fang", wood_mat, fang_boxes)

	# ---- 格子窗（窗棂合并网格 + 窗内暖光）----
	var span := face_span - 2.4
	var n_win := maxi(2, int(span / 2.6))
	var win_boxes: Array = []
	var light_boxes: Array = []
	for i in n_win:
		var t := 0.0 if n_win <= 1 else float(i) / float(n_win - 1)
		var al := lerpf(-span * 0.5, span * 0.5, t)
		if absf(al) < 1.5:
			continue
		var wp: Vector3
		if east_side:
			wp = Vector3(pos.x + fsign * (fp.x * 0.5 + 0.055), h * 0.6, pos.y + al)
		else:
			wp = Vector3(pos.x + al, h * 0.6, pos.y + fsign * (fp.y * 0.5 + 0.055))
		win_boxes.append_array(_window_boxes(wp, east_side, 1.05, 0.85))
		var back := Vector3(-fsign * 0.06, 0, 0) if east_side else Vector3(0, 0, -fsign * 0.06)
		light_boxes.append([wp + back, Vector3(0.04, 0.78, 0.98) if east_side else Vector3(0.98, 0.78, 0.04)])
	_merged_world(parent, "Windows", wood_dark, win_boxes)
	_merged_world(parent, "WindowGlow", win_mat, light_boxes)

	# ---- 地栿（木压脚）：坐在压顶石上。接缝已被勒脚接管，这里只剩横向收头 ----
	if east_side:
		_box(parent, Vector3(pos.x + fsign * (fp.x * 0.5 + 0.05), CAP_TOP + 0.12, pos.y),
			Vector3(0.16, 0.24, fp.y), wood_dark, false, 0.0, "Beam")
	else:
		_box(parent, Vector3(pos.x, CAP_TOP + 0.12, pos.y + fsign * (fp.y * 0.5 + 0.05)),
			Vector3(fp.x, 0.24, 0.16), wood_dark, false, 0.0, "Beam")

	# ---- 招牌 ----
	var sign_text := str(b.get("sign", ""))
	if sign_text != "":
		var front_half := (fp.x if east_side else fp.y) * 0.5
		var sp := Vector3(pos.x, 0, pos.y) + front * (front_half + 0.34) + Vector3(0, h * 0.72, 0)
		_box(parent, sp, Vector3(2.6, 0.7, 0.1) if east_side else Vector3(0.1, 0.7, 2.6),
			wood_dark, false, yaw, "Sign")
		_label(parent, sp + front * 0.24 + Vector3(0, 0.02, 0), sign_text,
			Color(0.98, 0.9, 0.66), 64, 0.005, _label_yaw(front))
		_light(parent, sp + front * 0.9 + Vector3(0, -0.15, 0), _col(pal, "lantern", "#ffb457"), 1.6, 7.0)


# ================================================================ 傩戏台

static func _stage(parent: Node3D, s: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(s.get("pos", [0, 0]))
	var size := _v2(s.get("size", [12, 8]))
	var h := float(s.get("height", 1.0))
	var yaw := float(s.get("yaw_deg", 270.0))
	var wood := _mat(pal, "wood", 0.85)
	var wood_dark := _mat(pal, "wood_dark", 0.85)
	var roof := _mat(pal, "roof", 0.8, Color(0, 0, 0, 0), true)
	var ridge_mat := _mat(pal, "roof_dark", 0.85)
	var cloth := _mat(pal, str(s.get("curtain", "cloth_red")), 0.95)

	_box(parent, Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x, h, size.y), wood, true, 0.0, "StageDeck")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(parent, Vector3(pos.x + sx * (size.x * 0.5 - 0.6), h + 2.3, pos.y + sz * (size.y * 0.5 - 0.6)),
				0.16, 4.6, wood_dark, true, "Pillar")
	# 傩戏台曲面屋顶：出檐深、翼角翘得比民居更高（公共建筑等级更高）
	_roof_kit(parent, Vector3(pos.x, 0.0, pos.y), 0.0, size.x + 2.4, (size.y + 2.4) * 0.5,
		h + 4.9, h + 7.4, roof, ridge_mat, wood_dark,
		{"corner_lift": 0.85, "spacing": 0.55, "inset": 0.6})
	# 后台幕布（背对观众的一侧 = -front）
	var front := _front_dir(yaw)
	var back := -front
	var half := (absf(front.x) > 0.5)  # 正面朝东西 → 幕后沿 Z 排布
	var curtain_pos := Vector3(pos.x, 0, pos.y) + back * ((size.x * 0.5 if half else size.y * 0.5) - 0.3) + Vector3(0, h + 1.6, 0)
	var csize: Vector3 = Vector3(0.16, 3.0, size.y - 1.2) if half else Vector3(size.x - 1.2, 3.0, 0.16)
	_box(parent, curtain_pos, csize, cloth, false, 0.0, "Curtain")
	# 两盏戏台灯
	_light(parent, Vector3(pos.x - front.x * 2.0, h + 3.4, pos.y - front.z * 2.0), _col(pal, "lantern", "#ffb457"), 2.4, 11.0)
	_sphere(parent, Vector3(pos.x - front.x * 2.0, h + 3.4, pos.y - front.z * 2.0), 0.34,
		MatCache.emissive(_col(pal, "lantern", "#ffb457"), 2.6), "StageLantern")
	var sign_text := str(s.get("sign", ""))
	if sign_text != "":
		var sp := Vector3(pos.x, 0, pos.y) + front * ((size.x * 0.5 if half else size.y * 0.5) + 0.2) + Vector3(0, h + 4.2, 0)
		_box(parent, sp, Vector3(12.0, 1.1, 0.12) if half else Vector3(0.12, 1.1, 12.0), wood_dark, false, 0.0, "StageSign")
		_label(parent, sp + front * 0.2, sign_text, Color(0.98, 0.9, 0.66), 96, 0.006, _label_yaw(front))
	# 上台坡道（自观众一侧登台）
	var ramp_len := h / maxf(0.15, sin(deg_to_rad(20.0)))
	_ramp(parent, Vector3(pos.x - front.x * (size.x * 0.5 + ramp_len * 0.5 * 0.94), h * 0.5, pos.y - front.z * (size.y * 0.5 + ramp_len * 0.5 * 0.94)),
		Vector3(ramp_len, 0.22, 2.4), 20.0, _yaw_from_dir(Vector2(front.x, front.z)), wood, "StageRamp")


# ================================================================ 摊铺

static func _stall(parent: Node3D, s: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(s.get("pos", [0, 0]))
	var size := _v2(s.get("size", [3.2, 2.4]))
	var yaw := float(s.get("yaw_deg", 0.0))
	var wood := _mat(pal, "wood", 0.85)
	var cloth := _mat(pal, str(s.get("cloth", "cloth_red")), 0.95)
	var h := 2.3
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(parent, Vector3(pos.x + sx * (size.x * 0.5 - 0.12), h * 0.5, pos.y + sz * (size.y * 0.5 - 0.12)),
				0.05, h, wood, false, "StallLeg")
	_box(parent, Vector3(pos.x, 0.85, pos.y), Vector3(size.x, 0.12, size.y * 0.7), wood, true, yaw, "StallCounter")
	_prism(parent, Vector3(pos.x, h + 0.28, pos.y), Vector3(size.x + 0.5, 0.55, size.y + 0.5), cloth, yaw, "StallAwning")
	_sphere(parent, Vector3(pos.x - size.x * 0.35, 1.9, pos.y - size.y * 0.3), 0.22,
		MatCache.emissive(_col(pal, "lantern", "#ffb457"), 2.4), "StallLantern")
	_light(parent, Vector3(pos.x, 1.95, pos.y), _col(pal, "lantern", "#ffb457"), 1.55, 6.5, 1.6)


# ================================================================ 灯笼

## 灯笼：沿直线等距排开，但**每一项都做小幅抖动**。
##
## 旧实现有四层周期性叠在一起，一眼就是程序生成的：等距（3.0/3.25/4.25/5.38 m）、
## 等高（3.2~4.0）、`i % 2` 严格球柱交替、亮度固定。四条周期叠加后，
## 走三根杆就能预判第四根长什么样 —— 这才是「机械」的根源，不是杆子不够多。
##
## 抖动幅度刻意都压得很小（位置 ±0.30 m、高度 ±0.35 m、尺寸 0.85~1.16）：
## 灯笼街的秩序感是资产，破的是「复读机」感，不是秩序本身。
static func _lantern_row(parent: Node3D, r: Dictionary, pal: Dictionary) -> void:
	var a := _v2(r.get("from", [0, 0]))
	var b := _v2(r.get("to", [0, 0]))
	var count := int(r.get("count", 5))
	var height := float(r.get("height", 3.6))
	var light_every := maxi(1, int(r.get("light_every", 2)))
	var off := _v2(r.get("offset", [0, 0]))
	var warm := str(r.get("mat", "lantern"))
	var pmat := _mat(pal, "wood_dark", 0.9)
	var lcolor := _col(pal, warm, "#ffb457")
	var dir := b - a
	# 抖动必须沿**街道方向**（改间距），横向抖会把灯笼推到对向那一排身上
	var tangent := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	# 每行一个固定相位：左右两排本来是镜像对称的，同相位呼吸会更假
	var row_phase := _rng.randf() * TAU
	for i in count:
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		var slide := _rng.randf_range(-0.30, 0.30)
		var p := Vector3(lerpf(a.x, b.x, t) + off.x + tangent.x * slide, 0.0,
			lerpf(a.y, b.y, t) + off.y + tangent.y * slide)
		var h := height + _rng.randf_range(-0.35, 0.35)
		var s := _rng.randf_range(0.85, 1.16)
		# 亮度 ±12%，量化成 5 档：不量化就是给 47 个灯笼各建一份材质，MatCache 就白做了
		var bri := _lantern_bright_step()
		var lmat := MatCache.emissive(lcolor, 1.25 * bri)
		_cylinder(parent, p + Vector3(0, h * 0.5, 0), 0.07, h, pmat, false, "LanternPole")
		_box(parent, p + Vector3(0, h, 0), Vector3(1.0, 0.08, 0.08), pmat, false, 0.0, "LanternArm")
		var lp := p + Vector3(0.35, h - 0.34 * s, 0)
		_lantern_body(parent, lp, s, lmat)
		_cylinder(parent, lp + Vector3(0, 0.34 * s, 0), 0.06 * s, 0.16 * s, lmat, false, "LanternCap")
		if i % light_every == 0:
			_lantern_lights.append({
				"pos": lp, "color": lcolor,
				"energy": 1.55, "range": 6.5, "atten": 1.6,
				"bri": bri, "phase": row_phase + _rng.randf() * TAU,
				"period": _rng.randf_range(3.0, 6.0),
			})

## 灯笼外形：球 / 柱 / 方 按权重随机（60 / 25 / 15），替代旧的 `i % 2` 严格交替。
static func _lantern_body(parent: Node3D, lp: Vector3, s: float, lmat: Material) -> void:
	var roll := _rng.randf()
	if roll < 0.60:
		_sphere(parent, lp, 0.30 * s, lmat, "Lantern", false)
	elif roll < 0.85:
		_cylinder(parent, lp, 0.27 * s, 0.58 * s, lmat, false, "LanternCyl")
	else:
		_box(parent, lp, Vector3(0.50 * s, 0.56 * s, 0.50 * s), lmat, false, 0.0, "LanternBox")

## 亮度抖动档位（0.88 ~ 1.12，共 5 档），供自发光材质复用。
static func _lantern_bright_step() -> float:
	const STEPS := 5
	var raw := _rng.randf_range(0.88, 1.12)
	var idx := clampi(int(round((raw - 0.88) / 0.24 * float(STEPS - 1))), 0, STEPS - 1)
	return 0.88 + 0.24 * float(idx) / float(STEPS - 1)

## 灯笼动态光的**延迟分配**。
##
## 为什么不照旧在 _lantern_row 里直接建灯：`build()` 的顺序是先城门 → 桥头 → 戏台 →
## 摊位 → 灯笼 → 道具 → 远景塔，而 `_light()` 是**先到先得**。旧预算 30 盏时，
## 前 9 盏被城门/桥头/戏台拿走，剩下的全被 47 个灯笼抢光 ——
## 结果是**摊位、井亭、桥面一盏动态光都没有**，而河对岸最远那排灯笼反而亮着。
##
## 改成收集候选、最后统一分配，并加一条最小间距：
## 既让「重要性高」的先拿到灯，又强制它们沿街铺开（否则近距离候选会挤在一处）。
static func _allocate_lantern_lights(parent: Node3D) -> void:
	var budget := _lights_left
	if budget <= 0 or _lantern_lights.is_empty():
		return
	# 重要性：主街中轴 > 沿街次排 > 河埠。离出生点（z≈34）越远越不需要实体光，
	# 那里有自发光灯笼 + bloom 就够了。
	_lantern_lights.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _lantern_weight(Vector3(x["pos"])) > _lantern_weight(Vector3(y["pos"])))
	# 最小间距 4.4 m：略大于主街灯笼间距(3.25 m)，保证 26 盏预算不会被一段吃光
	const MIN_GAP := 4.4
	var placed: Array[Vector3] = []
	for c in _lantern_lights:
		if placed.size() >= budget:
			break
		var p := Vector3(c["pos"])
		var too_close := false
		for q in placed:
			if p.distance_to(q) < MIN_GAP:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		_glow_light(parent, p, Color(c["color"]), float(c["energy"]) * float(c["bri"]),
			float(c["range"]), float(c["atten"]), float(c["phase"]), float(c["period"]))

static func _lantern_weight(p: Vector3) -> float:
	return 1.0 / (1.0 + absf(p.x) * 0.35 + absf(p.z - 30.0) * 0.045)

## 带呼吸的灯笼灯：与 `_light()` 同一套预算，只是挂 `LanternGlow` 脚本。
static func _glow_light(parent: Node3D, pos: Vector3, color: Color, energy: float,
		range_m: float, attenuation: float, phase: float, period: float) -> void:
	if _lights_left <= 0:
		return
	var l := LanternGlow.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * LIGHT_ENERGY_SCALE
	l.omni_range = range_m
	l.omni_attenuation = attenuation
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = range_m * 2.5
	l.distance_fade_length = 12.0
	# 呼吸的基准值必须与首帧能量一致，否则挂上脚本的瞬间会跳一下
	l.base_energy = energy * LIGHT_ENERGY_SCALE
	l.phase = phase
	l.period = period
	parent.add_child(l)
	_lights_left -= 1


# ================================================================ 道具

static func _prop(parent: Node3D, p: Dictionary, pal: Dictionary) -> void:
	var kind := str(p.get("kind", "crate"))
	var pos := _v3(p.get("pos", [0, 0, 0]))
	var yaw := float(p.get("yaw_deg", 0.0))
	match kind:
		"tree":
			var s := float(p.get("scale", 1.0))
			var trunk := _mat(pal, "wood_dark", 0.95)
			var leaf := MatCache.solid(_col(pal, "leaf", "#3f5a3a"), 0.95)
			var leaf2 := MatCache.solid(_col(pal, "leaf_dark", "#2c4229"), 0.95)
			_cylinder(parent, Vector3(pos.x, 1.6 * s, pos.z), 0.2 * s, 3.2 * s, trunk, true, "Trunk")
			_sphere(parent, Vector3(pos.x, 3.4 * s, pos.z), 1.7 * s, leaf, "Foliage")
			_sphere(parent, Vector3(pos.x + 0.9 * s, 3.9 * s, pos.z - 0.5 * s), 1.15 * s, leaf2, "Foliage2")
			_sphere(parent, Vector3(pos.x - 0.9 * s, 3.6 * s, pos.z + 0.6 * s), 1.05 * s, leaf, "Foliage3")
		"bamboo":
			var n := int(p.get("count", 6))
			var leafm := MatCache.solid(_col(pal, "leaf_dark", "#2c4229"), 0.9)
			var stalkm := MatCache.solid(_col(pal, "leaf", "#3f5a3a"), 0.85)
			for i in n:
				var ang := float(i) * 2.399
				var rad := 0.55 + 0.22 * float(i % 3)
				var h2 := 5.0 + 1.6 * sin(float(i) * 1.7)
				var bp := Vector3(pos.x + cos(ang) * rad, 0.0, pos.z + sin(ang) * rad)
				_cylinder(parent, bp + Vector3(0, h2 * 0.5, 0), 0.07, h2, stalkm, false, "Bamboo")
				_sphere(parent, bp + Vector3(0, h2, 0), 0.55, leafm, "BambooLeaf")
		"well":
			var stone := _mat(pal, "stone", 0.95)
			var wood := _mat(pal, "wood", 0.9)
			_cylinder(parent, Vector3(pos.x, 0.45, pos.z), 0.95, 0.9, stone, true, "WellRing")
			for sx in [-1.0, 1.0]:
				_cylinder(parent, Vector3(pos.x + sx * 0.75, 1.5, pos.z), 0.07, 2.2, wood, false, "WellPost")
			_prism(parent, Vector3(pos.x, 2.75, pos.z), Vector3(2.2, 0.6, 1.8), _mat(pal, "roof", 0.85), 0.0, "WellRoof")
		"sign":
			var wood := _mat(pal, "wood_dark", 0.9)
			var h3 := float(p.get("height", 3.0))
			_cylinder(parent, Vector3(pos.x, h3 * 0.5, pos.z), 0.09, h3, wood, true, "SignPost")
			var text := str(p.get("text", ""))
			if text != "":
				_label(parent, Vector3(pos.x, h3 - 0.5, pos.z), text, Color(0.95, 0.9, 0.72), 64, 0.005, yaw)
		"boat":
			var hull := _mat(pal, "wood", 0.9)
			_box(parent, Vector3(pos.x, -0.25, pos.z), Vector3(3.4, 0.5, 1.2), hull, false, yaw, "Hull")
			_prism(parent, Vector3(pos.x + 1.9, -0.2, pos.z), Vector3(0.8, 0.55, 1.2), hull, yaw, "Prow")
			_sphere(parent, Vector3(pos.x - 1.2, 0.35, pos.z), 0.18,
				MatCache.emissive(_col(pal, "lantern", "#ffb457"), 2.2), "BoatLantern")
		"crate":
			_box(parent, Vector3(pos.x, 0.42, pos.z), Vector3(0.85, 0.85, 0.85),
				_mat(pal, "wood", 0.9), true, yaw, "Crate")
		"barrel":
			_cylinder(parent, Vector3(pos.x, 0.5, pos.z), 0.42, 1.0,
				_mat(pal, "wood_dark", 0.9), true, "Barrel")
		"desk":
			var wood := _mat(pal, "wood", 0.88)
			_box(parent, Vector3(pos.x, 0.82, pos.z), Vector3(1.9, 0.12, 0.95), wood, true, yaw, "DeskTop")
			for sx in [-1.0, 1.0]:
				_box(parent, Vector3(pos.x + sx * 0.8, 0.4, pos.z), Vector3(0.12, 0.8, 0.8), wood, false, yaw, "DeskLeg")
			_sphere(parent, Vector3(pos.x, 1.15, pos.z), 0.16,
				MatCache.emissive(_col(pal, "lantern", "#ffb457"), 2.0), "DeskLamp")
			_light(parent, Vector3(pos.x, 1.35, pos.z), _col(pal, "lantern", "#ffb457"), 1.5, 6.0)
		"ramp":
			var size := _v3(p.get("size", [2.8, 0.24, 2.4]))
			_ramp(parent, pos, size, float(p.get("rise_deg", 20.0)), yaw,
				_mat(pal, "wood", 0.9), "PropRamp")


# ================================================================ 桥

static func _bridge(parent: Node3D, b: Dictionary, pal: Dictionary) -> void:
	var a := _v2(b.get("from", [0, -20]))
	var c := _v2(b.get("to", [0, -40]))
	var width := float(b.get("width", 6.0))
	var arch := float(b.get("arch", 2.0))
	var segs := maxi(4, int(b.get("segments", 10)))
	var rail_h := float(b.get("railing_height", 1.0))
	var d := c - a
	var length := d.length()
	if length <= 0.01:
		return
	var yaw := _yaw_from_dir(d)
	var dir := d / length
	var perp := Vector2(-dir.y, dir.x)
	var deck_mat := _mat(pal, "stone", 0.55)
	var rail_mat := _mat(pal, "wood_dark", 0.9)
	var seg_len := length / float(segs)
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var tm := (t0 + t1) * 0.5
		var y_mid := arch * sin(PI * tm)
		var mid := Vector2(lerpf(a.x, c.x, tm), lerpf(a.y, c.y, tm))
		# 桥面盒体随拱线切角倾斜，避免出现「台阶感」
		var slope := atan2(arch * PI * cos(PI * tm), length)
		var deck := _box(parent, Vector3(mid.x, y_mid - 0.15, mid.y), Vector3(seg_len + 0.16, 0.34, width), deck_mat, true, yaw, "BridgeDeck")
		if deck is Node3D:
			(deck as Node3D).rotate_object_local(Vector3(0, 0, 1), slope)
		for s: float in [-1.0, 1.0]:
			var rp := mid + perp * ((width * 0.5 - 0.12) * s)
			_box(parent, Vector3(rp.x, y_mid + rail_h * 0.5, rp.y), Vector3(seg_len + 0.16, rail_h, 0.16), rail_mat, false, yaw, "BridgeRail")
	# 桥头与桥心灯柱
	var rows := int(b.get("lantern_rows", 2))
	var lamp := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 1.9)
	var pole := _mat(pal, "wood_dark", 0.9)
	for t: float in [0.06, 0.5, 0.94]:
		var mid2 := Vector2(lerpf(a.x, c.x, t), lerpf(a.y, c.y, t))
		var yl := arch * sin(PI * t)
		for s: float in [-1.0, 1.0]:
			var pp := mid2 + perp * ((width * 0.5 - 0.2) * s)
			_cylinder(parent, Vector3(pp.x, yl + 1.1, pp.y), 0.07, 2.2, pole, false, "BridgePost")
			_sphere(parent, Vector3(pp.x, yl + 2.3, pp.y), 0.28, lamp, "BridgeLantern")
			_light(parent, Vector3(pp.x, yl + 2.3, pp.y), _col(pal, "lantern", "#ffb457"), 2.2, 9.0)
	# 桥面彩灯串
	for i in range(rows):
		var t2 := 0.2 + 0.3 * float(i)
		var mid3 := Vector2(lerpf(a.x, c.x, t2), lerpf(a.y, c.y, t2))
		var yr := arch * sin(PI * t2)
		for k in 5:
			var f := float(k) / 4.0 - 0.5
			var q := mid3 + perp * (f * (width - 0.8))
			_sphere(parent, Vector3(q.x, yr + 2.05, q.y), 0.17,
				MatCache.emissive(_col(pal, "lantern_cold", "#9fd2ff"), 1.5), "BridgeString")


# ================================================================ NPC / 交互 / 触发器

static func _npc(actors: Node3D, n: Dictionary) -> void:
	var inst := NPC_SCENE.instantiate()
	inst.set("npc_id", str(n.get("id", "")))
	var p := _v3(n.get("pos", [0, 0, 0]))
	inst.position = Vector3(p.x, p.y, p.z)
	inst.rotation.y = deg_to_rad(float(n.get("yaw_deg", 0.0)))
	actors.add_child(inst)

static func _interactable(actors: Node3D, it: Dictionary) -> void:
	var kind := str(it.get("kind", "clue"))
	var p := _v3(it.get("pos", [0, 0, 0]))
	# 已完成的拾取点不再生成（重进地图时保持一致）
	if kind == "pickup" and str(it.get("flag", "")) != "" and GameState.has_flag(str(it.get("flag", ""))):
		return
	var node: Node3D = null
	match kind:
		"clue":
			node = CLUE_SCENE.instantiate()
			node.set("dialogue_id", str(it.get("dialogue", "")))
			node.set("prompt_text", str(it.get("prompt", "调查")))
			node.set("clue_id", "" if bool(it.get("no_clue", false)) else str(it.get("id", "")))
			var req: Array = it.get("required", [])
			node.set("required_flags", PackedStringArray(req))
		"pickup":
			node = PICKUP_SCENE.instantiate()
			node.set("item_id", str(it.get("item", "")))
			node.set("count", int(it.get("count", 1)))
			node.set("flag_on_take", str(it.get("flag", "")))
			node.set("display_label", str(it.get("label", "")))
			node.set("prompt_text", str(it.get("prompt", "拾取")))
			node.set("required_flags", PackedStringArray(it.get("required", [])))
		"door":
			node = DOOR_SCENE.instantiate()
			node.set("dialogue_open", str(it.get("dialogue_open", "")))
			node.set("dialogue_locked", str(it.get("dialogue_locked", "")))
			node.set("prompt_text", str(it.get("prompt", "查看")))
	if node == null:
		return
	node.name = str(it.get("id", kind))
	node.position = Vector3(p.x, p.y, p.z)
	node.rotation.y = deg_to_rad(float(it.get("yaw_deg", 0.0)))
	actors.add_child(node)

static func _trigger(actors: Node3D, t: Dictionary) -> void:
	var inst := TRIGGER_SCENE.instantiate()
	inst.set("dialogue_id", str(t.get("dialogue", "")))
	var p := _v3(t.get("pos", [0, 0, 0]))
	inst.set("radius", float(t.get("radius", 6.0)))
	inst.set("required_flags", PackedStringArray(t.get("required", [])))
	inst.set("forbidden_flags", PackedStringArray(t.get("forbidden", [])))
	inst.position = Vector3(p.x, p.y, p.z)
	actors.add_child(inst)


# ================================================================ 工具

static func _arr(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []

static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO

static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if a is Array and a.size() == 2:
		return Vector3(float(a[0]), 0.0, float(a[1]))
	return Vector3.ZERO

## 让「局部 +X 轴」对齐世界方向 d 的 yaw（度）。
static func _yaw_from_dir(d: Vector2) -> float:
	if d.length() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(-d.y, d.x))

static func _front_dir(yaw_deg: float) -> Vector3:
	var r := deg_to_rad(yaw_deg)
	return Vector3(sin(r), 0.0, cos(r))

## Label3D 的正面是 +Z；让它朝向 world_dir。
static func _label_yaw(world_dir: Vector3) -> float:
	return rad_to_deg(atan2(world_dir.x, world_dir.z))
