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
