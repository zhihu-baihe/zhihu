extends Node
## AudioDirector：全局音频调度。
##
## 音频资产全部由 tools/gen_sfx.py 程序化合成（零预算、零外部依赖、改参数即可重现），
## 输出在 assets/processed/audio/。本脚本只负责加载、循环设置与播放调度，
## 不含任何音频数据本身。

const AUDIO_ROOT := "res://assets/processed/audio/"

const SFX_NAMES := [
	"ui_click", "ui_hover", "ui_open", "ui_close",
	"pickup", "clue", "dialogue_blip", "bell_far", "lantern_chime",
]
const STEPS_STONE := ["step_stone_1", "step_stone_2", "step_stone_3", "step_stone_4"]
const STEPS_WOOD := ["step_wood_1", "step_wood_2", "step_wood_3"]

## 环境音三层默认增益（dB）。地图可以用 map["ambience"] 覆盖。
const AMB_DEFAULT := {
	"night": -14.0,
	"water": -20.0,
	"crickets": -25.0,
}

const POOL_SIZE := 6

var _bank: Dictionary = {}
var _step_bank: Dictionary = {"stone": [], "wood": []}
var _pool: Array = []
var _pool_idx := 0
var _amb: Dictionary = {}
var _amb_target: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _step_accum := 0.0
var _last_step_name := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_load_bank()
	_build_pool()
	_build_ambience()

## 环境音增益用逐帧插值逼近目标值，而不是 Tween：
## Tween 需要持有引用才能中断，会在退出时留下 ObjectDB 泄漏。
func _process(delta: float) -> void:
	for key in _amb.keys():
		var p := _amb[key] as AudioStreamPlayer
		var target := float(_amb_target.get(key, -80.0))
		if absf(p.volume_db - target) > 0.05:
			p.volume_db = move_toward(p.volume_db, target, delta * 22.0)

## 退出时显式停止并断开循环流：
## AudioServer 会持有正在播放的 playback 引用，不主动停会留下 ObjectDB 泄漏。
func _exit_tree() -> void:
	for p in _amb.values():
		var ap := p as AudioStreamPlayer
		ap.stop()
		ap.stream = null
	_amb.clear()
	_amb_target.clear()
	for p2 in _pool:
		var sp := p2 as AudioStreamPlayer
		sp.stop()
		sp.stream = null
	_pool.clear()
	_bank.clear()
	(_step_bank["stone"] as Array).clear()
	(_step_bank["wood"] as Array).clear()

# ---------------------------------------------------------------- 加载

func _load_bank() -> void:
	for n in SFX_NAMES:
		var s := load(AUDIO_ROOT + n + ".wav")
		if s != null:
			_bank[n] = s
	for n in STEPS_STONE:
		var s2 := load(AUDIO_ROOT + n + ".wav")
		if s2 != null:
			(_step_bank["stone"] as Array).append(s2)
	for n in STEPS_WOOD:
		var s3 := load(AUDIO_ROOT + n + ".wav")
		if s3 != null:
			(_step_bank["wood"] as Array).append(s3)

## 环境音需要无缝循环：导入的 WAV 默认不循环，这里复制一份并打开循环点。
func _load_looped(n: String) -> AudioStream:
	var s := load(AUDIO_ROOT + n + ".wav")
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var ch := 2 if w.stereo else 1
		w.loop_end = int(w.data.size() / (2 * ch))
		return w
	return s

func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

func _build_ambience() -> void:
	for key in AMB_DEFAULT.keys():
		var stream := _load_looped("amb_" + str(key))
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Amb_" + str(key)
		p.stream = stream
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		p.play()
		_amb[key] = p

# ---------------------------------------------------------------- 自检接口

## 供 res://tests/test_data_integrity.tscn 使用：音频资产的加载概况。
func asset_summary() -> Dictionary:
	return {
		"sfx": _bank.size(),
		"steps": (_step_bank["stone"] as Array).size() + (_step_bank["wood"] as Array).size(),
		"ambience": _amb.size(),
	}

# ---------------------------------------------------------------- 播放接口

## UI / 通用音效（非定位）。
func play_sfx(n: String, volume_db := 0.0, pitch_var := 0.0) -> void:
	if not _bank.has(n):
		return
	var p := _pool[_pool_idx] as AudioStreamPlayer
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = _bank[n]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + (_rng.randf_range(-pitch_var, pitch_var) if pitch_var > 0.0 else 0.0)
	p.play()

func play_ui(n: String, volume_db := -6.0) -> void:
	play_sfx(n, volume_db)

## 脚步：按地面类型取随机变体，避免连续两步完全一样。
func play_step(speed := 3.0, surface := "stone") -> void:
	var arr: Array = _step_bank.get(surface, _step_bank["stone"])
	if arr.is_empty():
		return
	var s = arr[_rng.randi_range(0, arr.size() - 1)]
	if arr.size() > 1:
		# 避免连续重复同一个变体
		var guard := 0
		while str(s.resource_path).ends_with(_last_step_name) and guard < 4:
			s = arr[_rng.randi_range(0, arr.size() - 1)]
			guard += 1
		_last_step_name = str(s.resource_path).get_file()
	var p := _pool[_pool_idx] as AudioStreamPlayer
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = -13.0 + clampf((speed - 3.4) * 1.2, -3.0, 3.0)
	p.pitch_scale = _rng.randf_range(0.94, 1.07)
	p.play()

## 由 PlayerController 每帧调用：按行走距离累计触发脚步。
func tick_footsteps(speed: float, delta: float, grounded: bool, surface := "stone") -> void:
	if not grounded or speed < 0.6:
		_step_accum = 0.55   # 停下后下一步不必等满一个步幅
		return
	_step_accum += speed * delta
	var stride := 0.72 if speed < 4.6 else 0.95
	if _step_accum >= stride:
		_step_accum = 0.0
		play_step(speed, surface)

# ---------------------------------------------------------------- 环境音

## 进入一张地图：按地图配置淡入环境音层。map["ambience"] 可覆盖默认增益。
func enter_world(map: Dictionary) -> void:
	var mix: Dictionary = map.get("ambience", {})
	for key in _amb.keys():
		_amb_target[key] = float(mix.get(key, AMB_DEFAULT.get(key, -80.0)))

func leave_world() -> void:
	for key in _amb.keys():
		_amb_target[key] = -80.0

func set_ambience_level(key: String, db: float) -> void:
	if _amb.has(key):
		_amb_target[key] = db

## 立即停止所有正在播放的声音。
func silence_all() -> void:
	for p in _pool:
		(p as AudioStreamPlayer).stop()
	for p2 in _amb.values():
		(p2 as AudioStreamPlayer).stop()

## 测试场景退出前调用：停止播放并断开全部流引用。
## headless 使用 Dummy 音频驱动、不推进混音，playback 不会被自然回收，
## 不断开引用就会在退出时报 ObjectDB 泄漏（真实运行时不存在这个问题）。
func prepare_exit() -> void:
	silence_all()
	for p in _pool:
		(p as AudioStreamPlayer).stream = null
	for p2 in _amb.values():
		(p2 as AudioStreamPlayer).stream = null
	_bank.clear()
	(_step_bank["stone"] as Array).clear()
	(_step_bank["wood"] as Array).clear()

## 一次性远钟（剧情用，可由外部触发）。
func play_far_bell(volume_db := -10.0) -> void:
	play_sfx("bell_far", volume_db)
