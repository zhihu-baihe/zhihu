extends CanvasLayer
class_name MenuPanel
## 完整界面（按 CHAR-UI-02 v0.4）：任务日志 / 物品 / 角色状态 三页，按键主动打开，不常驻。
## 打开方式：Tab 键；关闭：Tab 或 Esc。键盘 ↑↓ 或 ←→ 切页，鼠标点击也可。
## 数据来源：GameState（旗标/线索/物品/队伍）+ GameData（定义表），UI 不自行计算数值。

enum Page { QUEST, ITEMS, CHARACTER, SAVE }

@onready var paper: ColorRect = $Paper
@onready var nav_box: VBoxContainer = $Root/HBox/Nav
@onready var page_title: Label = $Root/HBox/Content/PageTitle
@onready var body: VBoxContainer = $Root/HBox/Content/Scroll/Body
@onready var footer: Label = $Root/Footer

var page: int = Page.QUEST
var _theme: Theme

func _ready() -> void:
	_theme = UITheme.build()
	UITheme.apply(self, _theme)
	visible = false
	nav_box.get_node("NavQuest").pressed.connect(func(): _set_page(Page.QUEST))
	nav_box.get_node("NavItems").pressed.connect(func(): _set_page(Page.ITEMS))
	nav_box.get_node("NavChar").pressed.connect(func(): _set_page(Page.CHARACTER))
	nav_box.get_node("NavSave").pressed.connect(func(): _set_page(Page.SAVE))
	footer.text = "Tab / Esc 关闭　·　↑ ↓ 或 ← → 切换页面"
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", UITheme.INK_SUB)

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	GameState.ui_blocked = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()

func close() -> void:
	visible = false
	GameState.ui_blocked = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	# 关闭状态下也要能接收打开键，所以先判 toggle 再判 visible
	if event.is_action_pressed("toggle_menu"):
		get_viewport().set_input_as_handled()
		toggle()
		return
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_set_page((page + 1) % 4)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_set_page((page + 3) % 4)

func _set_page(p: int) -> void:
	page = p
	_refresh()

func _refresh() -> void:
	_update_nav()
	for c in body.get_children():
		c.queue_free()
	match page:
		Page.QUEST:
			_build_quests()
		Page.ITEMS:
			_build_items()
		Page.CHARACTER:
			_build_characters()
		Page.SAVE:
			_build_saves()

func _update_nav() -> void:
	var names := ["任务日志", "物品", "角色状态", "存档"]
	var keys := ["NavQuest", "NavItems", "NavChar", "NavSave"]
	for i in keys.size():
		var b: Button = nav_box.get_node(keys[i])
		b.text = ("▍ " if i == page else "　") + names[i]
		b.add_theme_color_override("font_color", UITheme.ACCENT_TEAL if i == page else UITheme.INK_MAIN)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT


# ---------------------------------------------------------------- 任务日志

func _build_quests() -> void:
	page_title.text = "任务日志"
	var quests := GameState.active_quests()
	if quests.is_empty():
		_add_para("暂无进行中的任务。", true)
	for q in quests:
		var st: Dictionary = q
		var head := "%s　（%d / %d）" % [str(st.get("title", "")), int(st.get("stage_index", 0)) + 1, int(st.get("stage_count", 0))]
		_add_heading(head)
		_add_para("当前目标：" + str(st.get("objective", "")), false)
		if bool(st.get("complete", false)):
			_add_para("本章阶段已全部完成。", true)
	_add_hairline()
	_add_heading("线索 %d / %d" % [GameState.clue_count(), GameState.clue_total()])
	if GameState.clue_count() == 0:
		_add_para("尚未取得线索。可去纸扎铺、灯籍小房与千灯桥查看。", true)
	else:
		for cid in GameState.clues.keys():
			var e := GameData.clue_entry(str(cid))
			_add_para("· %s：%s" % [str(e.get("name", cid)), str(e.get("journal", ""))], false)
	_add_hairline()
	var got: Array = []
	for iid in GameState.items.keys():
		got.append("%s ×%d" % [GameData.item_name(str(iid)), int(GameState.items[iid])])
	_add_heading("随身物品")
	_add_para("　".join(got) if got.size() > 0 else "（空）", true)


# ---------------------------------------------------------------- 物品

func _build_items() -> void:
	page_title.text = "物品"
	var groups := {
		"消耗品": "consumable", "关键物品": "key", "任务物品": "quest", "材料": "material",
	}
	var any := false
	for label in groups:
		var kind := str(groups[label])
		var rows: Array = []
		for iid in GameState.items.keys():
			var def := GameData.item(str(iid))
			if str(def.get("type", "")) != kind:
				continue
			rows.append({"id": str(iid), "n": int(GameState.items[iid]), "def": def})
		if rows.is_empty():
			continue
		any = true
		_add_heading(label)
		for r in rows:
			_add_para("· %s ×%d" % [str(r["def"].get("name", r["id"])), int(r["n"])], false)
			_add_para("　　" + str(r["def"].get("desc", "")), true)
	if not any:
		_add_para("背包是空的。", true)
	_add_hairline()
	_add_para("提示：材料与关键物品不会出现在战斗道具栏；消耗品可在战斗中使用。", true)


# ---------------------------------------------------------------- 角色状态

func _build_characters() -> void:
	page_title.text = "角色状态"
	var ids: Array = GameState.party.duplicate()
	if ids.is_empty():
		ids = ["SCN_ShenZhaoye"]
	for cid in ids:
		var id := str(cid)
		var lv := int(GameState.party_levels.get(id, 1))
		var st := GameData.character(id)
		var stats := _stats_for(id, lv)
		_add_heading("%s　%s　Lv%d" % [str(st.get("display_name", id)), str(st.get("role", "")), lv])
		var hp := int(stats.get("HP", 0))
		var mp := int(stats.get("MP", 0))
		_add_bar_row("气血", hp, hp, UITheme.ACCENT_CINNABAR)
		_add_bar_row("灵息", mp, mp, UITheme.ACCENT_BLUE)
		_add_stat_grid(stats)
		_add_hairline()
	_add_para("数值为首版拟定值（设计文档 CH01 §33），装备加成另行计算；不做战力总分。", true)

func _add_bar_row(label: String, value: int, max_value: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lb := Label.new()
	lb.text = label
	lb.custom_minimum_size = Vector2(70, 0)
	lb.add_theme_color_override("font_color", UITheme.INK_SUB)
	lb.add_theme_font_size_override("font_size", 18)
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, max_value)
	bar.value = value
	bar.custom_minimum_size = Vector2(240, 16)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UITheme.LINE.r, UITheme.LINE.g, UITheme.LINE.b, 0.35)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	var val := Label.new()
	val.text = str(value)
	val.add_theme_font_size_override("font_size", 18)
	row.add_child(lb)
	row.add_child(bar)
	row.add_child(val)
	body.add_child(row)

func _add_stat_grid(stats: Dictionary) -> void:
	var keys := ["ATK", "MATK", "DEF", "RES", "SPD", "ACC", "EVA", "POISE"]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for k in keys:
		var cell := Label.new()
		cell.text = "%s　%d" % [_stat_name(k), int(stats.get(k, 0))]
		cell.add_theme_font_size_override("font_size", 18)
		grid.add_child(cell)
	body.add_child(grid)

func _stat_name(k: String) -> String:
	match k:
		"ATK": return "攻击"
		"MATK": return "术力"
		"DEF": return "防御"
		"RES": return "灵御"
		"SPD": return "速度"
		"ACC": return "命中"
		"EVA": return "闪避"
		"POISE": return "韧性"
	return k

func _stats_for(character_id: String, level: int) -> Dictionary:
	var table: Dictionary = GameData.character(character_id).get("table", {})
	var best_lv := -1
	var best: Dictionary = {}
	for k in table.keys():
		var lv := int(k)
		if lv <= level and lv > best_lv:
			best_lv = lv
			best = table[k]
	if best.is_empty() and not table.is_empty():
		best = table[table.keys()[0]]
	return best


# ---------------------------------------------------------------- 存档

func _build_saves() -> void:
	page_title.text = "存档"
	_add_para("自动存档：任务阶段推进时、以及退出游戏前各写一次（只保留最近一条）。手动槽位随时可存。", true)
	_add_hairline()
	_add_save_row(SaveManager.AUTOSAVE_SLOT)
	for s in SaveManager.MANUAL_SLOTS:
		_add_save_row(int(s))
	_add_hairline()
	_add_para("存档内容：任务阶段与旗标、三条线索、物品与数量、队伍、已播一次性对白标记、时段、地图与玩家位置。", true)
	_add_para("读档后：已完成的一次性过场不会重播，已取得的线索与暗门状态保持不变（设计方案 §21 兜底规则）。", true)

func _add_save_row(slot: int) -> void:
	var is_auto := slot == SaveManager.AUTOSAVE_SLOT
	var info := SaveManager.slot_info(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lb := Label.new()
	lb.custom_minimum_size = Vector2(620, 0)
	lb.add_theme_font_size_override("font_size", 18)
	if info.is_empty():
		lb.text = "%s　（空）" % SaveManager.slot_label(slot)
		lb.add_theme_color_override("font_color", UITheme.INK_SUB)
	elif bool(info.get("broken", false)):
		lb.text = "%s　（存档损坏或版本不符）" % SaveManager.slot_label(slot)
		lb.add_theme_color_override("font_color", UITheme.ACCENT_CINNABAR)
	else:
		lb.text = "%s　%s　%s　线索 %d　队伍 %d" % [
			SaveManager.slot_label(slot), str(info.get("saved_at", "")),
			str(info.get("scene_name", "")), int(info.get("clue_count", 0)), int(info.get("party_size", 0))]
	row.add_child(lb)

	if not is_auto:
		var bs := Button.new()
		bs.text = "保存"
		bs.pressed.connect(func(): _do_save(slot))
		row.add_child(bs)
	var bl := Button.new()
	bl.text = "读取"
	bl.disabled = info.is_empty() or bool(info.get("broken", false))
	bl.pressed.connect(func(): _do_load(slot))
	row.add_child(bl)
	if not is_auto:
		var bd := Button.new()
		bd.text = "删除"
		bd.disabled = info.is_empty()
		bd.pressed.connect(func(): _do_delete(slot))
		row.add_child(bd)
	body.add_child(row)

func _do_save(slot: int) -> void:
	SaveManager.save_game(slot)
	_refresh()

func _do_load(slot: int) -> void:
	close()
	await SaveManager.load_game(slot)

func _do_delete(slot: int) -> void:
	SaveManager.delete_save(slot)
	_refresh()


# ---------------------------------------------------------------- 构件

func _add_heading(text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", UITheme.serif())
	lb.add_theme_font_size_override("font_size", 24)
	lb.add_theme_color_override("font_color", UITheme.INK_MAIN)
	body.add_child(lb)

func _add_para(text: String, sub: bool) -> void:
	var lb := Label.new()
	lb.text = text
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.add_theme_font_size_override("font_size", 18 if not sub else 17)
	lb.add_theme_color_override("font_color", UITheme.INK_SUB if sub else UITheme.INK_MAIN)
	body.add_child(lb)

func _add_hairline() -> void:
	var line := ColorRect.new()
	line.color = UITheme.LINE
	line.custom_minimum_size = Vector2(0, 1)
	body.add_child(line)
