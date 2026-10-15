# 设计文档 → Godot 映射与工程约定

> 源设计文档以 UE5（Unreal Engine 5.8）为目标编写，本工程按用户 brief 改为 **Godot 4.7.2 + GDScript**。
> 本文记录「设计概念 → Godot 落地物」的对照，以及必须长期遵守的工程约定。
> **设计内容（剧情、人物、数值、区域、任务、BOSS 阶段）一字不改，只换实现载体。**

---

## 1. 载体对照

| UE5 设计文档概念 | Godot 实现 | 备注 |
|---|---|---|
| Level `L_CH01_MoyiCity` | 场景 `scenes/world/moyi_town.tscn` + 数据 `data/map_moyi.json` | 布局是数据，不是手写节点树 |
| Level Sequence（开场演出） | `TriggerZone` 触发 + `DialogueRunner` 多说话人台词串 | 过场对白支持逐行指定说话方 |
| DataTable `DT_Dialogue_MAP01` | `data/dialogue.json` | 字段对照见 §2 |
| DataTable `DT_Items` | `data/items.json` | |
| `DT_CharacterGrowth` | `data/characters.json` | 按等级档位存表 + 公式说明 |
| `DA_Quest_Q_CH01_...` | `data/quests.json` | 阶段用 `complete_on_flags` 表达 |
| `DT_Interactables_MAP01` | `data/map_moyi.json` 的 `interactables` 段 | 交互点/拾取/门用 `kind` 区分 |
| `DT_NPCSchedule_MAP01` | `map_moyi.json` 的 `npcs` 段（站位/朝向） | 时段字段已预留，M2 接四时段 |
| `BP_Interactable` | `scripts/interaction/interactable.gd`（`class_name Interactable`） | 组 `interactable` + 距离判定 |
| `BP_EvidenceInteractable` | `clue_point.gd` | 播对白 → 给线索 → 自身熄灭 |
| `BP_NPCDialogueComponent` | `dialogue_runner.gd`（autoload） | 优先级选择器 |
| `BP_QuestManager` | `game_state.gd`（autoload） | 旗标驱动、阶段实时重算 |
| `BP_WorldStateController_Moyi` | `town_world.gd` + `map_moyi.json.environment` | 环境/灯光/雾状态 |
| `BP_StoryDirector` | `trigger_zone.gd` + 对白节点 `effects` | 事件驱动，不逐帧轮询 |
| `FSaveGameData` | M2 的 `SaveManager`（序列化 `GameState` 六个字典 + 位置） | 设计文档「必须保存」清单逐项对上 |
| `DA_Boss_Baomian_Phases` | M4 的 `data/boss_baomian.json` | 四阶段阈值只在行动结算后判定 |

---

## 2. 对白字段对照

| 设计文档字段（§25 / MAP-01 §9） | Godot 字段 | 说明 |
|---|---|---|
| `DialogueID` | `id` | 沿用设计文档命名（`MOYI_*`、`PRO_*`） |
| `NPCID` | `npc` | 引用 `dialogue.json.npcs` 的键 |
| `Priority` | `priority` | 数值越大越优先 |
| `RequiredFlags` | `required` | 全部满足 |
| `ForbiddenFlags` | `forbidden` | 全部不满足 |
| `TimeSlice` / `TimeBand` | `time_band` | M1 只用 `any`；M2 接四时段 |
| `PlayOnce` | `play_once` | 播过即写入 `seen_dialogues` |
| `LineText` / `SubtitleText` | `lines[].text` | 改为数组，支持多说话人过场 |
| （新增） | `lines[].speaker` | 逐行说话方；旁白用「（……）」包裹 |
| （新增） | `effects` | 播完结算：置旗标/给线索/给物品/启任务/入队 |

**ID 命名沿用设计文档，不另造一套**：`MSQ_*`（主线旗标）、`CLUE_*`（证据）、`SQ01_*`（支线）、`MY-T0x`（墨邑区域）、`CH01_0x0_*`（章节阶段）。

---

## 3. 工程约定（长期遵守）

1. **内容与代码分离**：任何剧情文本、数值、区域布局新增，只能进 `data/*.json`；脚本里不出现具体数值与台词。
2. **状态只存在于 `GameState`**：不允许把任务/线索/物品状态挂在场景节点上（否则存档与切图必然漏状态）。节点只负责「表现 + 触发」。
3. **不硬编码阶段顺序**：任务推进由 `complete_on_flags` 声明式表达，读档/跳阶段才不会错位。
4. **不软锁**：任何主线关键节点都要有兜底路径（例：暗门 = 罗班主确认 **或** 线索齐全）。
5. **脚本严格类型**：Godot 4.7 默认把 `INFERRED_DECLARATION` 当错误——从 Dictionary/Variant 取的值必须显式标注类型（`var x: Array = d.get(...)`），循环变量在元素为 Variant 时显式标注（`for i: float in [...]`）。
6. **改完必跑验证**：`--headless --quit-after 200`（冒烟）+ `res://tests/test_data_integrity.tscn`（数据与流程）。两者都干净才算完成。
7. **新数据要过校验**：`GameData._validate()` 会交叉检查所有对白/NPC/物品/任务/线索/交互点引用；新增内容只要引用写错，自检就会报出来。
8. **地图尺寸与坐标**：+x 向东、+z 向南，单位米，1 单位 = 1 米；玩家身高约 1.7 米（地面 y=0）。
9. **性能预算**：灰盒阶段动态灯 ≤ 30 盏；新增灯源要通过 `LIGHT_BUDGET_MAX` 或改用自发光材质。
10. **不擅自升级引擎**：工程固定在 4.7.2；升级前必须先在分支上跑冒烟 + 自检 + 截图复核。

---

## 4. 与设计文档的差异说明（需要用户在策划侧知情的三处）

1. **引擎变更**：设计资料写 UE5.8，本工程按 brief 用 Godot 4.7.2。设计文档中的「UE5 实现建议」章节仅作参考，实际落地物见本文 §1。
2. **一处基线冲突（沿用 MAP-01 §0 的结论）**：设计曾提到「裴渡可观察红绳」，但裴渡到酆都才加入。本工程按 MAP-01 的处理——墨邑 BOSS 的红绳提示由环境调查、姜阿棠「照妖面」与三条线索承担，不让裴渡提前入场。
3. **过场表现降级**：M1 中「阿禾追纸轿进旧巷」由触发区 + 多说话人文本叙述完成，阿禾本人不会真的跑动消失。M2 接上 NPC 日程与演出后再补实际动画。

---

## 5. UI 落地（依据 ui规范/CHAR-UI-02 v0.4）

**设计文档的方向是「清爽单机仙侠」**：温润纸白 + 青灰墨色 + 少量朱砂；细线分区、面板圆角 0—3px、无持续发光、无厚重金框、不做战力总分与稀有度色。v0.4 明确废除了 v0.3 的「深蓝黑底 + 金边 + 发光卡片」方向——**不要按「仙剑4 的深蓝金框」直接复刻**，只取它的信息分层与克制原则（文档 §8 已声明）。

| 设计文档（UMG） | Godot 实现 | 说明 |
|---|---|---|
| `WBP_DialogueQuest` | `scenes/ui/dialogue_box.tscn` + `scripts/ui/dialogue_box.gd` | 底部单层对白框：朱砂小标记 + 说话人 + 打字机正文 + 继续提示；旁白转次级墨色 |
| 场景内轻量任务提示 | `scenes/ui/hud.tscn`（QuestHint） | 左上只保留一条主线提示 + 线索计数，不铺满屏幕 |
| 完整任务日志 | `scripts/ui/menu_panel.gd` 的「任务日志」页 | **Tab 键打开**，非常驻（v0.4 §UI-07 要求） |
| `WBP_Inventory` | `menu_panel.gd` 的「物品」页 | 按消耗品/关键/任务/材料分类，数量与说明 |
| `WBP_CharacterStatus` | `menu_panel.gd` 的「角色状态」页 | 姓名/定位/等级 + 气血·灵息条 + 八项战斗属性；不做战力总分 |
| `WBP_CharacterDetails` / `WBP_Equipment` / `WBP_Skills` | 待做（M5 装备与技能树） | 属性来源分层、换装预览只算差值 |
| `WBP_BattleHUD` | 待做（M3 战斗） | 敌方名称/阶段/血条在上，指令菜单在底边 |
| 视觉 Token | `scripts/ui/ui_theme.gd` | 常量与 `UI_StyleTokens.csv` 一一对应，全项目只定义一次 |
| 字体 | `UITheme.serif()` / `sans()`（SystemFont） | 标题宋体系、正文黑体系；发布前换成随包 OFL 字体（见 05 §10） |

**实现约定**：UI 只读 `GameState`/`GameData` 的快照，不自行计算属性；打开完整界面时置 `GameState.ui_blocked = true`，由玩家控制器与交互器让位（UI 不直接操纵角色节点）。
