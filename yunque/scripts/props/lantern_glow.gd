class_name LanternGlow
extends OmniLight3D
## 灯笼动态光的极轻微呼吸。
##
## 目的只有一个：让一排灯笼「活着」，不再是 47 个完全同步的死灯球。
## 幅度刻意做得很小（默认 ±3%）—— 大了就变成舞台频闪，灯笼街不该闪。
##
## 两个实现约束（都是踩过的坑）：
##   * 用 `_process` 逐帧算，**不要用 Tween**：Tween 会让 `_tweens` 持有引用，
##     退出时报 `ObjectDB instances were leaked`（见开发日志缺陷 #11）。
##   * 每盏灯自带 period / phase，所以整条街不会同频共振；
##     同一行的相位偏移由 TownBuilder 生成时给定。

## 呼吸的基准能量（由生成器写入，已含亮度抖动的量化档位）。
var base_energy := 1.0
## 呼吸幅度：0.03 = ±3%。
var breathe_amp := 0.03
## 呼吸周期（秒）。每盏灯各自不同，避免整街同步。
var period := 4.5
## 初相位（弧度）。
var phase := 0.0

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	light_energy = base_energy * (1.0 + breathe_amp * sin(TAU * _t / period + phase))
