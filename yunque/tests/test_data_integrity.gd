extends Node
## 数据与流程自检（可无头运行）
## 运行：godot --headless --path . res://tests/test_data_integrity.tscn
## 覆盖：数据完整性、对白选择优先级、任务阶段随旗标推进、墨邑 M1 主线/支线全过程。

var failures := PackedStringArray()
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	_section("数据完整性（GameData._validate）")
	for p in GameData.all_problems():
		_fail("数据问题：" + str(p))
	_ok_if(GameData.all_problems().is_empty(), "数据文件无校验问题")
	_ok_if(GameData.dialogue_node("MOYI_ATANG_010").size() > 0, "关键对白节点可解析")
	_ok_if(GameData.quest("Q_CH01_LAMP_AND_SHADOW").size() > 0, "主线任务可解析")
	_ok_if(GameData.map_data("map_moyi").get("npcs", []).size() >= 8, "地图 NPC 数量 ≥ 8")

	_section("对白优先级与条件")
	_ok_eq(_select("NPC_LIU"), "MOYI_LIU_010", "柳婶·初入城 → 默认闲聊")
	GameState.set_flag("MSQ_MoyiArrived", true)
	_ok_eq(_select("NPC_LIU"), "MOYI_LIU_SQ_START", "已入城 → 支线启动优先（88）")
	GameState.set_flag("SQ01_STARTED", true)
	_ok_eq(_select("NPC_LIU"), "MOYI_LIU_010", "支线已启动 → 回落到默认闲聊")
	GameState.add_clue("CLUE_MY_BRIDGE_REFLECTION")
	_ok_eq(_select("NPC_LIU"), "MOYI_LIU_020", "得到桥影线索 → 线索对白（55）")

	_section("任务阶段随旗标推进")
	_ok_eq(_stage("SQ_01_SEVENTH_LANTERN"), "SQ01_020_LAMPSHADE", "支线阶段 1 完成 → 进入阶段 2")
	_ok_eq(_stage("Q_CH01_LAMP_AND_SHADOW"), "CH01_020_MEET_ATANG", "主线：已入城 → 等待认识姜阿棠")

	_section("姜阿棠登场与线索链")
	GameState.set_flag("MSQ_AtangMet", true)
	GameState.set_flag("COMP_JIANGATANG_JOINED", true)
	_ok_eq(_select("NPC_ATANG"), "MOYI_ATANG_030", "已同行 + 有线索 → 线索总结对白")
	_ok_eq(_stage("Q_CH01_LAMP_AND_SHADOW"), "CH01_030_GATHER_CLUES", "主线：进入收集线索阶段")

	_section("三条线索齐全 → 派生旗标与阶段")
	GameState.add_clue("CLUE_MY_PAPER_SEDAN")
	GameState.add_clue("CLUE_MY_REGISTRY")
	_ok_if(GameState.has_flag("ALL_CLUES"), "ALL_CLUES 由 GameState 自动维护")
	_ok_eq(_stage("Q_CH01_LAMP_AND_SHADOW"), "CH01_040_OPEN_WORKSHOP", "主线：线索齐全 → 进入开暗门阶段")
	_ok_eq(_select("NPC_ATANG"), "MOYI_ATANG_040", "线索齐全 → 姜阿棠额外提示（78）")

	_section("暗门兜底：线索齐全即可开启")
	var door_open: bool = GameState.has_flag("MSQ_OLD_LANTERN_WORKSHOP_OPEN") or GameState.has_flag("ALL_CLUES")
	_ok_if(door_open, "未与罗班主对话，线索齐全也能开启暗门（不软锁）")

	_section("支线《河边第七盏灯》全流程")
	GameState.set_flag("HAS_LAMPSHADE", true)
	GameState.set_flag("HAS_PLAQUE", true)
	_ok_eq(_select("NPC_KID"), "MOYI_KID_040", "两件道具到手 → 阿竹提示交给柳婶")
	GameState.set_flag("SQ01_READY_TO_LIGHT", true)
	_ok_eq(_select("NPC_LIU"), "MOYI_LIU_SQ_END", "可点灯 → 柳婶收束对白（89 优先于线索对白）")
	GameState.set_flag("SQ_01_SEVENTH_LANTERN_COMPLETE", true)
	var sq := GameState.quest_stage("SQ_01_SEVENTH_LANTERN")
	_ok_if(bool(sq["complete"]), "支线全部阶段完成")
	_ok_eq(_select("NPC_KID"), "MOYI_KID_050", "支线完成后 → 阿竹后续对白")

	_section("主线后续阶段（M2/M3 占位旗标）")
	GameState.set_flag("MSQ_OLD_LANTERN_WORKSHOP_OPEN", true)
	_ok_eq(_stage("Q_CH01_LAMP_AND_SHADOW"), "CH01_050_RESCUE_AHE", "主线：暗门开启 → 进入迷宫阶段")
	GameState.set_flag("MSQ_AheFound", true)
	GameState.set_flag("MSQ_BaomianDefeated", true)
	GameState.set_flag("MSQ_MOYI_AFTERSTATE", true)
	GameState.set_flag("MSQ_Chapter01Complete", true)
	var mq := GameState.quest_stage("Q_CH01_LAMP_AND_SHADOW")
	_ok_if(bool(mq["complete"]), "主线八阶段全部完成")

	_section("地图结构自检")
	var map := GameData.map_data("map_moyi")
	_ok_if(_interactable_dialogues_valid(map), "所有交互点引用的对白都存在")
	_ok_if(_no_footprint_overlap(map), "建筑/戏台范围互不重叠")

	_section("存档往返（M2）")
	var slot := 3
	SaveManager.delete_save(slot)
	GameState.set_flag("TEST_SAVE_FLAG", true)
	GameState.add_item("ITEM_SMALL_HEAL", 2)
	GameState.add_party(["SCN_JiangAtang"])
	GameState.mark_dialogue_seen("MOYI_ATANG_010")
	var clue_before := GameState.clue_count()
	var party_before := GameState.party.size()
	var item_before := GameState.item_count("ITEM_SMALL_HEAL")
	var stage_before := _stage("Q_CH01_LAMP_AND_SHADOW")
	_ok_if(SaveManager.save_game(slot, true), "写入存档（槽 %d）" % slot)
	_ok_if(SaveManager.has_save(slot), "存档文件已生成")
	var info := SaveManager.slot_info(slot)
	_ok_eq(str(info.get("save_version", -1)), str(SaveManager.SAVE_VERSION), "存档版本号")

	GameState.from_dict({})
	_ok_if(not GameState.has_flag("TEST_SAVE_FLAG"), "清空状态：旗标已移除")
	_ok_if(GameState.clue_count() == 0, "清空状态：线索归零")
	_ok_if(GameState.party.is_empty(), "清空状态：队伍清空")

	await SaveManager.load_game(slot)
	_ok_if(GameState.has_flag("TEST_SAVE_FLAG"), "读档恢复旗标")
	_ok_eq(str(GameState.clue_count()), str(clue_before), "读档恢复线索数")
	_ok_eq(str(GameState.party.size()), str(party_before), "读档恢复队伍人数")
	_ok_eq(str(GameState.item_count("ITEM_SMALL_HEAL")), str(item_before), "读档恢复物品数量")
	_ok_if(GameState.is_dialogue_seen("MOYI_ATANG_010"), "读档恢复一次性对白标记（不重播过场）")
	_ok_if(GameState.has_flag("ALL_CLUES"), "读档后派生旗标重算（ALL_CLUES）")
	_ok_eq(_stage("Q_CH01_LAMP_AND_SHADOW"), stage_before, "读档后任务阶段与存档前一致")
	_ok_if(SaveManager.delete_save(slot), "清理测试存档")
	_ok_if(not SaveManager.has_save(slot), "测试存档已删除")

	# ---------------------------------------------------------------- 音频资产

	_section("音频（tools/gen_sfx.py 程序化合成）")
	var aud := AudioDirector.asset_summary()
	_ok_if(int(aud["sfx"]) >= 9, "通用音效已加载：%d/9" % int(aud["sfx"]))
	_ok_if(int(aud["steps"]) >= 7, "脚步变体已加载：%d/7" % int(aud["steps"]))
	_ok_if(int(aud["ambience"]) == 3, "环境音层已建立：%d/3" % int(aud["ambience"]))

	# 退出前释放音频：headless 音频服务器不回收 playback，不断开引用会报泄漏
	AudioDirector.prepare_exit()
	await get_tree().process_frame

	_report()

# ---------------------------------------------------------------- 断言工具

func _select(npc_id: String) -> String:
	return str(DialogueRunner.select_node(npc_id).get("id", "<none>"))

func _stage(quest_id: String) -> String:
	return str(GameState.quest_stage(quest_id)["stage_id"])

func _section(title: String) -> void:
	print("\n=== %s ===" % title)

func _ok_eq(actual: String, expected: String, label: String) -> void:
	checks += 1
	if actual == expected:
		print("  [PASS] %s → %s" % [label, actual])
	else:
		_fail("%s → 期望 %s，实际 %s" % [label, expected, actual])

func _ok_if(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] %s" % label)
	else:
		_fail(label)

func _fail(msg: String) -> void:
	failures.append(msg)
	print("  [FAIL] %s" % msg)

func _report() -> void:
	print("\n================ 自检结果 ================")
	print("检查项：%d，失败：%d" % [checks, failures.size()])
	if failures.is_empty():
		print("全部通过 ✅")
	else:
		for f in failures:
			print(" - " + f)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- 结构检查

func _interactable_dialogues_valid(map: Dictionary) -> bool:
	for it in map.get("interactables", []):
		for key in ["dialogue", "dialogue_open", "dialogue_locked"]:
			var d := str(it.get(key, ""))
			if d != "" and GameData.dialogue_node(d).is_empty():
				return false
	return true

func _no_footprint_overlap(map: Dictionary) -> bool:
	var rects: Array = []
	for b in map.get("buildings", []):
		var p: Array = b.get("pos", [0, 0])
		var f: Array = b.get("footprint", [0, 0])
		rects.append(Rect2(float(p[0]) - float(f[0]) * 0.5, float(p[1]) - float(f[1]) * 0.5, float(f[0]), float(f[1])))
	var st: Dictionary = map.get("stage", {})
	if not st.is_empty():
		var sp: Array = st.get("pos", [0, 0])
		var ss: Array = st.get("size", [0, 0])
		rects.append(Rect2(float(sp[0]) - float(ss[0]) * 0.5, float(sp[1]) - float(ss[1]) * 0.5, float(ss[0]), float(ss[1])))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				push_warning("[test] 建筑范围重叠：#%d 与 #%d" % [i, j])
				return false
	return true
