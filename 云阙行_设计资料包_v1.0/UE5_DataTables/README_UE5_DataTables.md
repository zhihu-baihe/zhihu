# CH01 UE5 DataTable 模板 v0.2

这些 CSV/JSON 是与《CH01_序章第一章_剧情战斗装备开发稿_v0.2》配套的首版数据原型。数值均为试玩初值，不能视作最终平衡。

## 文件
- `DT_Skills.csv`：首章角色技能与状态标签。
- `DT_Enemies.csv`：普通敌人、精英与两个首领属性。
- `DT_Encounters.csv`：遭遇组成、地图 ID 与逃跑规则。
- `DT_Equipment.csv`：武器、衣装、护符、饰品及属性加成。
- `DT_Recipes.csv`：固定配方、解锁条件与消耗。
- `DT_LootEntries.csv`：掉落条目；`Name` 是唯一 EntryID，`LootTableID` 将多条条目组织成一张掉落表。
- `DT_BossPhases.csv`：两场首领的阶段阈值、行动池和场景状态。
- `DT_CharacterGrowth.csv`：沈照野 Lv1—10、姜阿棠 Lv5—10 的示例成长行。
- `DT_StatusEffects.csv`：首章用到的状态时长、首领转化与叠加规则。
- `DT_Passives.csv`：装备被动的事件触发与效果数据。
- `DT_Items.csv`：材料、消耗品与剧情关键物品定义。
- `DT_QuestRewards.csv`：一次性任务经验、铜钱与固定奖励。
- `QuestFlags_and_SaveRequirements.json`：任务状态标记与存档最低字段。

## 导入注意
1. 在 UE5 中先建立相应的 `UStruct`，字段名与类型应与 CSV 表头一致；第一列 `Name` 是 DataTable RowName。
2. `ActionTags`、`ActionPool`、`MaterialCosts` 等复合字段最好在最终结构中改为 GameplayTag 数组或独立关联表。这里为便于第一轮阅读而使用分号分隔字符串。
3. `DT_LootEntries.csv` 的 `Name` 已生成唯一 EntryID；使用 `LootTableID` 聚合行。
4. 不要在角色蓝图里硬编码装备被动。用 PassiveID 触发对应的事件处理器；每个“每场战斗一次”的被动都要在战斗开始时重置状态。
5. 首领阶段只在行动结算结束后检查 HP 阈值，防止一次多段技能跨过多个阈值时连续切阶段。

## 关键默认规则
- 行动槽阈值 1000；每秒增加 SPD；等待模式选指令时暂停，可选流动模式以 25% 速度继续。
- 物理伤害使用 ATK/DEF，术法使用 MATK/RES，倍率与伤害公式在总档基线中定义。
- 首领控制抗性高，普通控制转为削韧／延后，禁止无限控制。
- 核心首领材料 Guaranteed=true 且 OncePerQuest=true，不允许刷 BOSS 解锁剧情武器。
