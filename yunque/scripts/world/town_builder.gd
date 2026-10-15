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
const LIGHT_BUDGET_MAX := 30
## 全局灯光能量缩放：夜景验收要求「蓝灰环境光 + 暖灯」，避免灯笼过曝、暗部丢细节。
const LIGHT_ENERGY_SCALE := 0.75
static var _lights_left := LIGHT_BUDGET_MAX

static func reset_budget() -> void:
	_lights_left = LIGHT_BUDGET_MAX


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

	return {"lights_used": LIGHT_BUDGET_MAX - _lights_left}


# ================================================================ 基础几何

static func _col(pal: Dictionary, key: String, fallback := "#888888") -> Color:
	return Color(str(pal.get(key, fallback)))

## 调色板键 → 真实 PBR 贴图集（ambientCG CC0）。[贴图集名, 世界平铺尺度（越小越密）]
## 没有映射的键继续用纯色，保证灰盒与正式资产可以逐块替换、互不影响。
const TEX_ROOT := "res://assets/processed/textures/"
const TEX_MAP := {
	"roof": ["RoofingTiles013A", 0.5],
	"roof_dark": ["RoofingTiles013A", 0.5],
	"wall": ["PavingStones151", 0.28],
	"stone": ["PavingStones151", 0.28],
	"stone_dark": ["PavingStones151", 0.28],
	"wood": ["Planks037A", 0.42],
	"wood_dark": ["Planks037A", 0.42],
	"cloth_red": ["Fabric085", 0.85],
	"cloth_gold": ["Fabric085", 0.85],
	"cloth_green": ["Fabric085", 0.85],
}

static var _mat_cache: Dictionary = {}

## 取材质：调色板键有贴图集时返回「贴图 + 该键颜色作色调」，否则回退纯色。
## tint_override 用于需要压暗/变体的场合（如墙帽、湿石街）。
static func _mat(pal: Dictionary, key: String, roughness := 0.85, tint_override := Color(0, 0, 0, 0)) -> Material:
	var color := _col(pal, key)
	if tint_override.a > 0.0:
		color = tint_override
	if not TEX_MAP.has(key):
		return MatCache.solid(color, roughness)
	var entry: Array = TEX_MAP[key]
	var set_name := str(entry[0])
	var world_scale := float(entry[1])
	var ck := "%s|%s|%.2f|%.2f" % [set_name, color.to_html(true), world_scale, roughness]
	if _mat_cache.has(ck):
		return _mat_cache[ck]
	var base := TEX_ROOT + set_name + "/" + set_name + "_1K-JPG_"
	var m := MatCache.textured(base + "Color.jpg", base + "NormalGL.jpg",
		base + "Roughness.jpg", base + "AmbientOcclusion.jpg", world_scale, color, roughness)
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

static func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	if _lights_left <= 0:
		return
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy * LIGHT_ENERGY_SCALE
	l.omni_range = range_m
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


# ================================================================ 地面与道路

static func _terrain(parent: Node3D, t: Dictionary, pal: Dictionary) -> void:
	var pos := _v3(t.get("pos", [0, 0, 0]))
	var size := _v3(t.get("size", [10, 1, 10]))
	_box(parent, pos, size, _mat(pal, str(t.get("mat", "stone")), 0.95, _col(pal, str(t.get("mat", "stone")), "#6f6a62").darkened(0.18)), true, 0.0, "Terrain")

static func _street(parent: Node3D, s: Dictionary, pal: Dictionary) -> void:
	var kind := str(s.get("kind", "street"))
	# 湿石街：低粗糙度 + SSR，让灯笼在石面上留下反射（参考图的核心视觉手段）
	var street_key := str(s.get("mat", "stone"))
	var wet_mat := _mat(pal, street_key, 0.42, _col(pal, street_key).darkened(0.18))
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

## 远景塔：层叠方塔 + 出檐，河对岸山中的地标剪影
static func _pagoda(parent: Node3D, p: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(p.get("pos", [0, 0]))
	var tiers := maxi(1, int(p.get("tiers", 3)))
	var base := float(p.get("base", 6.0))
	var tier_h := float(p.get("height", 4.0))
	var wall_mat := MatCache.solid(_col(pal, str(p.get("wall_mat", "wood_dark")), "#4f3a27"), 0.9)
	var roof_mat := MatCache.solid(_col(pal, str(p.get("mat", "roof_dark")), "#333c46"), 0.85)
	var y := 0.0
	for i in tiers:
		var scale_f := 1.0 - 0.18 * float(i)
		var w := base * scale_f
		_box(parent, Vector3(pos.x, y + tier_h * 0.4, pos.y), Vector3(w, tier_h * 0.8, w), wall_mat, false, 0.0, "PagodaTier")
		_prism(parent, Vector3(pos.x, y + tier_h * 0.9, pos.y), Vector3(w * 1.5, tier_h * 0.42, w * 1.5), roof_mat, 0.0, "PagodaRoof")
		y += tier_h * 0.85
	_prism(parent, Vector3(pos.x, y + tier_h * 0.35, pos.y), Vector3(base * 0.5, tier_h * 0.8, base * 0.5), roof_mat, 0.0, "PagodaSpire")

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
	var roof_col := _col(pal, "roof", "#46525e")
	var roof_mat := _mat(pal, "roof", 0.8)
	for s in [-1.0, 1.0]:
		var tp := Vector3(pos.x + off * s, tsize.y * 0.5, pos.y)
		_box(parent, tp, tsize, wall_mat, true, 0.0, "GateTower")
		_prism(parent, tp + Vector3(0, tsize.y * 0.5 + 0.7, 0), Vector3(tsize.x + 1.6, 1.4, tsize.z + 1.6),
			roof_mat, 0.0, "GateRoof")
		_light(parent, tp + Vector3(0, 1.4, 2.6), _col(pal, "lantern", "#ffb457"), 2.0, 10.0)
	_sphere(parent, Vector3(pos.x, 0, pos.y) + Vector3(0, 0, 0), 0.01, MatCache.solid(Color.BLACK, 1.0), "Noop")
	_box(parent, Vector3(pos.x, beam_y, pos.y), Vector3(off * 2 + 2.0, 1.3, tsize.z * 0.8),
		roof_mat, false, 0.0, "GateBeam")
	_box(parent, Vector3(pos.x, beam_y + 1.35, pos.y), Vector3(off * 2 + 3.0, 1.5, tsize.z * 0.95),
		_mat(pal, "roof", 0.8, roof_col.darkened(0.2)), false, 0.0, "GateRoofTop")
	var plaque := str(g.get("plaque", "城门"))
	_label(parent, Vector3(pos.x, beam_y + 0.2, pos.y - tsize.z * 0.45), plaque,
		Color(0.98, 0.9, 0.66), 96, 0.007, 180.0)


# ================================================================ 建筑

static func _building(parent: Node3D, b: Dictionary, pal: Dictionary) -> void:
	var pos := _v2(b.get("pos", [0, 0]))
	var fp := _v2(b.get("footprint", [10, 8]))
	var h := float(b.get("height", 3.4))
	var yaw := float(b.get("yaw_deg", 90.0))
	var wall_key := str(b.get("wall_mat", "wall"))
	var roof_key := str(b.get("roof_mat", "roof"))
	var wall_mat := _mat(pal, wall_key, 0.9)
	var roof_col := _col(pal, roof_key)
	var roof_mat := _mat(pal, roof_key, 0.82)
	var wood_mat := _mat(pal, "wood", 0.85)
	var th := 0.35

	# 石砌墙基（不碰撞，避免门槛卡住玩家）
	_box(parent, Vector3(pos.x, 0.09, pos.y), Vector3(fp.x + 0.7, 0.18, fp.y + 0.7),
		_mat(pal, "stone_dark", 0.95), false, 0.0, "Base")

	# 四面墙
	_box(parent, Vector3(pos.x, h * 0.5, pos.y - fp.y * 0.5), Vector3(fp.x, h, th), wall_mat, true, 0.0, "WallN")
	_box(parent, Vector3(pos.x, h * 0.5, pos.y + fp.y * 0.5), Vector3(fp.x, h, th), wall_mat, true, 0.0, "WallS")
	var front := _front_dir(yaw)
	var east_side := absf(front.x) > 0.5
	var door_w := 1.8
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

	# 悬山顶（PrismMesh：三角截面沿 Z 拉伸；脊线沿 Z 或旋转 90°）
	var roof_h := clampf(h * 0.42, 1.0, 2.0)
	if east_side:
		_prism(parent, Vector3(pos.x, h + roof_h * 0.5, pos.y), Vector3(fp.y + 1.0, roof_h, fp.x + 1.0),
			roof_mat, 90.0, "Roof")
	else:
		_prism(parent, Vector3(pos.x, h + roof_h * 0.5, pos.y), Vector3(fp.x + 1.0, roof_h, fp.y + 1.0),
			roof_mat, 0.0, "Roof")

	# 立面细节：木梁 + 暖灯窗（灰盒阶段也要能读出「这里住着人」）
	var win_mat := MatCache.emissive(_col(pal, "lantern", "#ffb457"), 1.4, 0.6)
	var span := (fp.y if east_side else fp.x) - 2.2
	var n_win := maxi(2, int(span / 2.6))
	for i in n_win:
		var t := 0.0 if n_win <= 1 else float(i) / float(n_win - 1)
		var along := lerpf(-span * 0.5, span * 0.5, t)
		if absf(along) < 1.5:
			continue  # 避开正中的门洞
		if east_side:
			_box(parent, Vector3(pos.x + signf(front.x) * (fp.x * 0.5 + 0.06), h * 0.62, pos.y + along),
				Vector3(0.09, 0.8, 1.0), win_mat, false, 0.0, "Window")
		else:
			_box(parent, Vector3(pos.x + along, h * 0.62, pos.y + signf(front.z) * (fp.y * 0.5 + 0.06)),
				Vector3(1.0, 0.8, 0.09), win_mat, false, 0.0, "Window")
	# 上下木梁
	if east_side:
		for yy: float in [0.45, h - 0.25]:
			_box(parent, Vector3(pos.x + signf(front.x) * (fp.x * 0.5 + 0.03), yy, pos.y),
				Vector3(0.14, 0.22, fp.y), wood_mat, false, 0.0, "Beam")
	else:
		for yy: float in [0.45, h - 0.25]:
			_box(parent, Vector3(pos.x, yy, pos.y + signf(front.z) * (fp.y * 0.5 + 0.03)),
				Vector3(fp.x, 0.22, 0.14), wood_mat, false, 0.0, "Beam")

	# 招牌
	var sign_text := str(b.get("sign", ""))
	if sign_text != "":
		var front_half := (fp.x if absf(front.x) > 0.5 else fp.y) * 0.5
		var sp := Vector3(pos.x, 0, pos.y) + front * (front_half + 0.16) + Vector3(0, h * 0.66, 0)
		_box(parent, sp, Vector3(2.6, 0.7, 0.1) if absf(front.x) > 0.5 else Vector3(0.1, 0.7, 2.6),
			wood_mat, false, yaw, "Sign")
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
	var roof_col := _col(pal, "roof", "#46525e")
	var roof := _mat(pal, "roof", 0.8)
	var cloth := _mat(pal, str(s.get("curtain", "cloth_red")), 0.95)

	_box(parent, Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x, h, size.y), wood, true, 0.0, "StageDeck")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(parent, Vector3(pos.x + sx * (size.x * 0.5 - 0.6), h + 2.3, pos.y + sz * (size.y * 0.5 - 0.6)),
				0.16, 4.6, wood_dark, true, "Pillar")
	_box(parent, Vector3(pos.x, h + 5.0, pos.y), Vector3(size.x + 1.4, 0.35, size.y + 1.4), roof, false, 0.0, "StageRoof")
	_prism(parent, Vector3(pos.x, h + 5.7, pos.y), Vector3(size.x + 1.8, 1.2, size.y + 1.8), _mat(pal, "roof", 0.8, roof_col.darkened(0.15)), 0.0, "StageRoofTop")
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
	_light(parent, Vector3(pos.x, 1.95, pos.y), _col(pal, "lantern", "#ffb457"), 1.7, 7.0)


# ================================================================ 灯笼

static func _lantern_row(parent: Node3D, r: Dictionary, pal: Dictionary) -> void:
	var a := _v2(r.get("from", [0, 0]))
	var b := _v2(r.get("to", [0, 0]))
	var count := int(r.get("count", 5))
	var height := float(r.get("height", 3.6))
	var light_every := maxi(1, int(r.get("light_every", 2)))
	var off := _v2(r.get("offset", [0, 0]))
	var warm := str(r.get("mat", "lantern"))
	var lmat := MatCache.emissive(_col(pal, warm, "#ffb457"), 1.7)
	var pmat := _mat(pal, "wood_dark", 0.9)
	var lcolor := _col(pal, warm, "#ffb457")
	for i in count:
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		var p := Vector3(lerpf(a.x, b.x, t) + off.x, 0.0, lerpf(a.y, b.y, t) + off.y)
		_cylinder(parent, p + Vector3(0, height * 0.5, 0), 0.07, height, pmat, false, "LanternPole")
		_box(parent, p + Vector3(0, height, 0), Vector3(1.0, 0.08, 0.08), pmat, false, 0.0, "LanternArm")
		var lp := p + Vector3(0.35, height - 0.34, 0)
		if i % 2 == 0:
			_sphere(parent, lp, 0.3, lmat, "Lantern", false)
		else:
			_cylinder(parent, lp, 0.27, 0.58, lmat, false, "LanternCyl")
		_cylinder(parent, lp + Vector3(0, 0.34, 0), 0.06, 0.16, lmat, false, "LanternCap")
		if i % light_every == 0:
			_light(parent, lp, lcolor, 1.9, 8.5)


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
