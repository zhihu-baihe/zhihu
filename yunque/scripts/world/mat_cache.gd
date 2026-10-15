class_name MatCache
extends RefCounted
## 灰盒材质缓存：按「颜色 + 参数」复用 StandardMaterial3D，避免每块砖都新建材质。

static var _cache: Dictionary = {}

static func _key(color: Color, a: float, b: float, c: float) -> String:
	return "%s|%.2f|%.2f|%.2f" % [color.to_html(true), a, b, c]

static func solid(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var k := _key(color, roughness, metallic, 0.0)
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[k] = m
	return m

## 自发光材质：灯笼、灯窗、水面反光点。
static func emissive(color: Color, energy := 2.4, roughness := 0.5) -> StandardMaterial3D:
	var k := "E" + _key(color, energy, roughness, 0.0)
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = roughness
	_cache[k] = m
	return m

static func water(color: Color) -> StandardMaterial3D:
	var k := "W" + color.to_html(true)
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.45
	m.roughness = 0.08
	m.emission_enabled = true
	m.emission = color.lightened(0.25)
	m.emission_energy_multiplier = 0.35
	_cache[k] = m
	return m

static func clear() -> void:
	_cache.clear()

## 真实 PBR 贴图材质：**世界三平面映射（triplanar）**，程序化盒体不需要逐件 UV，
## 大墙与小箱按世界尺度平铺同一张图，尺寸自动正确。
## 贴图来源：ambientCG（CC0），已按 05_美术标准 §7 放在 assets/processed/textures/。
static func textured(color_path: String, normal_path: String, rough_path: String,
		ao_path: String, world_scale: float, tint: Color,
		roughness := 1.0, alpha := 1.0) -> StandardMaterial3D:
	var k := "T|%s|%.3f|%s|%.2f|%.2f" % [color_path, world_scale, tint.to_html(true), roughness, alpha]
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	var ct: Texture2D = load(color_path)
	if ct != null:
		m.albedo_texture = ct
	var nt: Texture2D = load(normal_path)
	if nt != null:
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 1.0
	var rt: Texture2D = load(rough_path)
	if rt != null:
		m.roughness_texture = rt
	var at: Texture2D = load(ao_path)
	if at != null:
		m.ao_enabled = true
		m.ao_texture = at
	var tinted := tint
	if alpha < 1.0:
		tinted.a = alpha
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tinted
	m.roughness = roughness
	m.metallic = 0.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(world_scale, world_scale, world_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[k] = m
	return m
