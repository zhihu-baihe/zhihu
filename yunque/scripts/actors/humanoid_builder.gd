class_name HumanoidBuilder
extends RefCounted
## 按配色与体型参数，用代码组装一个完整人形（玩家与 NPC 共用）。
##
## 身高按 1.72 m 设计：脚底 y=0，胯 0.90，肩 1.42，头顶 ≈1.70，发髻顶 ≈1.80。
## 所有部件都是基础网格（圆柱/球/盒），通过 HumanoidRig 的关节层级驱动，
## 不依赖任何外部模型或动画文件 —— 这是零预算条件下唯一可复现的做法。

const RIG := preload("res://scripts/actors/humanoid_rig.gd")

const DEFAULT_SKIN := "#c8a184"
const DEFAULT_HAIR := "#241f1c"
const DEFAULT_BOOT := "#2f2a26"

## cfg 支持：robe / trim / skin / hair / boot（Color）、weapon（bool）、phase_offset（float）
static func build(model_root: Node3D, cfg: Dictionary, nm := "Rig") -> HumanoidRig:
	var rig := RIG.new() as HumanoidRig
	rig.name = nm
	model_root.add_child(rig)
	rig.phase_offset = float(cfg.get("phase_offset", randf() * TAU))

	var robe: Color = cfg.get("robe", Color("#55688a"))
	var trim: Color = cfg.get("trim", Color("#c9a24a"))
	var skin: Color = cfg.get("skin", Color(DEFAULT_SKIN))
	var hair: Color = cfg.get("hair", Color(DEFAULT_HAIR))
	var boot: Color = cfg.get("boot", Color(DEFAULT_BOOT))

	var m_robe := MatCache.cloth(robe)
	var m_robe_dark := MatCache.cloth(robe.darkened(0.24))
	var m_trim := MatCache.cloth(trim, 0.07, 0.7)
	var m_skin := MatCache.cloth(skin, 0.03, 0.8)
	var m_hair := MatCache.solid(hair, 0.72)
	var m_boot := MatCache.solid(boot, 0.9)
	var m_metal := MatCache.solid(Color("#8b8f96"), 0.35, 0.75)

	# ---------------------------------------------------------------- 骨盆
	var hip := _joint(rig, "Hip", Vector3(0, 0.90, 0))
	# 袍摆：略外扩的直筒（中式长衫不是喇叭裙），下摆留够空间让腿摆动时不穿出去
	_mesh(hip, "Skirt", _cyl(0.235, 0.335, 0.50), m_robe_dark, Vector3(0, -0.24, 0))
	_mesh(hip, "Belt", _cyl(0.238, 0.238, 0.095), m_trim, Vector3(0, 0.03, 0))
	if bool(cfg.get("weapon", false)):
		# 佩剑：整体挂在一个关节上，绕 Z 斜挂在身侧
		var wp := _joint(hip, "Weapon", Vector3(0.205, -0.06, 0.015))
		wp.rotation = Vector3(0.0, 0.0, -0.34)
		_mesh(wp, "Sheath", _box(Vector3(0.058, 0.78, 0.115)), m_hair, Vector3(0, 0.05, 0))
		_mesh(wp, "Guard", _box(Vector3(0.135, 0.035, 0.135)), m_trim, Vector3(0, 0.42, 0))
		_mesh(wp, "Hilt", _box(Vector3(0.05, 0.22, 0.1)), m_metal, Vector3(0, 0.53, 0))

	# ---------------------------------------------------------------- 躯干
	var spine := _joint(hip, "Spine", Vector3(0, 0.06, 0))
	_mesh(spine, "Torso", _cyl(0.185, 0.218, 0.55), m_robe, Vector3(0, 0.22, 0))
	# 斜襟：从中线斜向右肩压过去的一道缘边，中式交领的辨识点
	_mesh(spine, "LapelA", _box(Vector3(0.30, 0.035, 0.045)), m_trim,
		Vector3(-0.02, 0.375, -0.163)).rotation = Vector3(0, 0, 0.42)
	_mesh(spine, "LapelB", _box(Vector3(0.235, 0.035, 0.045)), m_trim,
		Vector3(0.155, 0.395, -0.10)).rotation = Vector3(0, 0.85, 0.30)
	_mesh(spine, "Collar", _cyl(0.115, 0.155, 0.11), m_trim, Vector3(0, 0.475, 0))

	# ---------------------------------------------------------------- 头
	var neck := _joint(spine, "Neck", Vector3(0, 0.50, 0))
	_mesh(neck, "NeckMesh", _cyl(0.055, 0.062, 0.09), m_skin, Vector3(0, 0.045, 0))
	var head := _mesh(neck, "Head", _sph(0.105), m_skin, Vector3(0, 0.135, 0))
	head.scale = Vector3(0.94, 1.06, 0.98)
	# 发：后脑包住，前面留出脸
	var hair_back := _mesh(neck, "HairBack", _sph(0.109), m_hair, Vector3(0, 0.148, 0.026))
	hair_back.scale = Vector3(0.96, 1.05, 0.98)
	_mesh(neck, "HairBand", _cyl(0.113, 0.113, 0.048), m_trim, Vector3(0, 0.188, 0.012))
	_mesh(neck, "HairBun", _sph(0.053), m_hair, Vector3(0, 0.232, 0.05))
	_mesh(neck, "HairPin", _box(Vector3(0.19, 0.016, 0.016)), m_trim, Vector3(0, 0.232, 0.05))

	# ---------------------------------------------------------------- 手臂
	for side: float in [1.0, -1.0]:
		var left := side > 0.0
		var sh := _joint(spine, "ShoulderL" if left else "ShoulderR",
			Vector3(0.208 * side, 0.46, 0))
		_mesh(sh, "UpperArm", _cyl(0.051, 0.045, 0.27), m_robe, Vector3(0, -0.135, 0))
		var el := _joint(sh, "ElbowL" if left else "ElbowR", Vector3(0, -0.27, 0))
		_mesh(el, "ForeArm", _cyl(0.045, 0.038, 0.26), m_robe, Vector3(0, -0.13, 0))
		_mesh(el, "Cuff", _cyl(0.055, 0.055, 0.07), m_trim, Vector3(0, -0.235, 0))
		_mesh(el, "Hand", _sph(0.047), m_skin, Vector3(0, -0.30, 0))

	# ---------------------------------------------------------------- 腿
	for side: float in [1.0, -1.0]:
		var left := side > 0.0
		var hp := _joint(hip, "HipL" if left else "HipR", Vector3(0.095 * side, 0, 0))
		_mesh(hp, "Thigh", _cyl(0.079, 0.062, 0.42), m_robe, Vector3(0, -0.21, 0))
		var kn := _joint(hp, "KneeL" if left else "KneeR", Vector3(0, -0.42, 0))
		_mesh(kn, "Shin", _cyl(0.062, 0.048, 0.44), m_robe, Vector3(0, -0.22, 0))
		_mesh(kn, "Boot", _box(Vector3(0.115, 0.09, 0.235)), m_boot, Vector3(0, -0.435, -0.035))

	rig.bind()
	return rig


# ================================================================ 构件工具

static func _joint(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n

static func _mesh(parent: Node3D, nm: String, mesh: Mesh, mat: Material,
		pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _cyl(top_r: float, bot_r: float, h: float, seg := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m

static func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m

static func _box(sz: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = sz
	return m
