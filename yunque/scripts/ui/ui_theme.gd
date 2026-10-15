class_name UITheme
extends RefCounted
## 清爽单机仙侠 UI 主题（依据 设计资料包 / ui规范 / CHAR-UI-02 v0.4）
## 颜色 Token 与 UI_StyleTokens.csv 完全一致；全项目只在此处定义一次。
## 原则（v0.4）：温润纸白 + 青灰墨色 + 少量朱砂；细线分区；无发光、无厚金框、无稀有度色。

const INK_MAIN := Color("#263b43")        # 主文字/标题
const INK_SUB := Color("#697d80")         # 次级文字
const PAPER_BG := Color("#f3f0e7")        # 页面底色
const PAPER_PANEL := Color("#faf8f1")     # 内容面板
const PAPER_SELECTED := Color("#e8eee8")  # 选中项
const LINE := Color("#bcc7c1")            # 分隔线
const ACCENT_TEAL := Color("#557d83")     # 主交互色
const ACCENT_BLUE := Color("#6e8f9b")     # 灵息/信息
const ACCENT_CINNABAR := Color("#b95f50") # 朱砂：HP/剧情重点
const ACCENT_WOOD := Color("#b39a68")     # 器物点缀
const MUTED_GREEN := Color("#7f987e")     # 五灵木系

const SAFE_MARGIN := 56
const ROW_GAP := 10

## 标题用宋体/仿宋，正文用黑体系（v0.4 §4）。使用系统字体，零下载；
## 正式发布前按 05_美术标准 §10 换成随包 OFL 字体（Noto Serif/Sans CJK SC）。
static func serif() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", "SimSun", "Microsoft YaHei"])
	f.allow_system_fallback = true
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f

static func sans() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Noto Sans CJK SC", "Source Han Sans SC", "Microsoft YaHei", "PingFang SC", "SimHei", "Arial"])
	f.allow_system_fallback = true
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 20

	# ---------- Label ----------
	t.set_color("font_color", "Label", INK_MAIN)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("outline_size", "Label", 0)

	# ---------- 文字样式变体 ----------
	_variation_label(t, "TitleLabel", serif(), 30, INK_MAIN)
	_variation_label(t, "PageTitleLabel", serif(), 34, INK_MAIN)
	_variation_label(t, "SubLabel", sans(), 17, INK_SUB)
	_variation_label(t, "HintLabel", sans(), 15, INK_SUB)
	_variation_label(t, "CinnabarLabel", sans(), 18, ACCENT_CINNABAR)
	_variation_label(t, "TealLabel", sans(), 18, ACCENT_TEAL)
	_variation_label(t, "LampLabel", serif(), 26, INK_MAIN)  # 场景内提示（对白框名字等）

	# ---------- 面板 ----------
	t.set_stylebox("panel", "PanelContainer", panel(PAPER_PANEL, LINE, 2, 18))
	t.set_stylebox("panel", "Panel", panel(PAPER_PANEL, LINE, 2, 14))
	t.set_stylebox("panel", "PopupPanel", panel(PAPER_PANEL, LINE, 2, 14))
	t.set_stylebox("background", "ProgressBar", panel(PAPER_SELECTED, LINE, 1, 0))

	# ---------- 按钮（文字优先，不用胶囊；焦点只用浅底/底线） ----------
	var normal := panel(PAPER_PANEL, LINE, 2, 12)
	normal.bg_color = Color(PAPER_PANEL.r, PAPER_PANEL.g, PAPER_PANEL.b, 0.0)
	normal.border_width_bottom = 0
	var hover := panel(PAPER_SELECTED, LINE, 2, 12)
	var pressed := panel(PAPER_SELECTED, ACCENT_TEAL, 2, 12)
	var focus := panel(Color(PAPER_SELECTED.r, PAPER_SELECTED.g, PAPER_SELECTED.b, 0.7), LINE, 2, 12)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, INK_MAIN)
		t.set_color("font_hover_color", cls, ACCENT_TEAL)
		t.set_color("font_pressed_color", cls, ACCENT_TEAL)
		t.set_color("font_focus_color", cls, INK_MAIN)
		t.set_font("font", cls, sans())
		t.set_font_size("font_size", cls, 22)

	# ---------- 导航按钮（左侧文字导航 + 细底线表示当前页） ----------
	t.set_font("font", "NavButton", sans())
	t.set_font_size("font_size", "NavButton", 22)

	# ---------- 滚动容器 ----------
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# ---------- 血条 / 灵息条（颜色只作辅助，数值同时以文字给出） ----------
	_variation_progress(t, "HPBar", ACCENT_CINNABAR)
	_variation_progress(t, "MPBar", ACCENT_BLUE)
	_variation_progress(t, "ExpBar", ACCENT_TEAL)

	return t

static func _variation_label(t: Theme, name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)

static func _variation_progress(t: Theme, name: String, fill: Color) -> void:
	t.set_type_variation(name, "ProgressBar")
	var bg := panel(Color(LINE.r, LINE.g, LINE.b, 0.35), Color(0, 0, 0, 0), 1, 0)
	var fg := panel(fill, Color(0, 0, 0, 0), 1, 0)
	t.set_stylebox("background", name, bg)
	t.set_stylebox("fill", name, fg)
	t.set_font("font", name, sans())
	t.set_font_size("font_size", name, 14)
	t.set_color("font_color", name, PAPER_BG)

static func panel(bg: Color, border: Color, radius := 2, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var bgc := bg
	bgc.a = 0.94 if bg.a >= 1.0 else bg.a
	s.bg_color = bgc
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s

## 细线（用于分区）：1px 实色
static func hairline(vertical := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = LINE
	if vertical:
		s.content_margin_left = 0
		s.content_margin_right = 1
		s.expand_margin_right = 1
	else:
		s.content_margin_top = 1
	return s

## 把主题应用到整棵子树的所有 Control（CanvasLayer 不继承主题，需要显式下发）
static func apply(root: Node, th: Theme) -> void:
	if root is Control:
		(root as Control).theme = th
	for c in root.get_children():
		apply(c, th)
