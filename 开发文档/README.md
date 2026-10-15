# 《云阙行：九灯照夜》开发文档索引

> 本目录存放**工程侧**文档：路线图、实现方案、开发日志、设计文档映射。
> 源设计资料（策划案原文）在 `_参考源文档/` 与 `../云阙行_设计资料包_v1.0/`。

## 一句话现状

**M1 已完成并验证**：Godot 4.7.2 工程落地，墨邑古城·百花千灯会灰盒可跑——第三人称探索、9 个区域、10 名 NPC 的阶段化对白、3 条主线线索、1 条完整支线、任务日志与交互提示全部可用；战斗/存档/迷宫/正式美术在后续里程碑。

## 里程碑状态

| 里程碑 | 内容 | 状态 |
|---|---|---|
| **M1** | 工程骨架 + 墨邑城镇灰盒（探索/交互/对白/线索/支线/任务日志） | ✅ 已完成（自检 24/24） |
| M2 | 旧灯坊迷宫 + 存档系统 + 阿禾救援线 | 待开始 |
| M3 | 行动条战斗系统 + 教学战 + 普通敌人 AI | 待开始 |
| M4 | 百面灯魇四阶段 BOSS + 失败重试 | 待开始 |
| M5 | 装备/锻造/材料经济 + 姜阿棠技能树 | 待开始 |
| M6 | 序章《借灯下山》（落灯观 + 砺剑镇 + 吞风蜃犬） | 待开始 |
| M7 | 美术 pass：模块化建筑替换灰盒 + 材质/光照/环境音 | 待开始 |
| M8 | 序章→第一章完整闭环 + 存档兼容与回归测试 | 待开始 |

## 文档索引

| 文件 | 内容 |
|---|---|
| `01_开发路线图_ROADMAP.md` | 里程碑拆解、验收标准、风险清单（P0/P1） |
| `02_M1_墨邑花灯节_实现方案.md` | M1 的目标、区域落地表、系统架构、数据结构、验证结果 |
| `03_开发日志.md` | 按日期记录每次实质改动与缺陷修复 |
| `04_设计文档到Godot映射.md` | UE5 设计文档 → Godot 的命名/结构对照，工程约定 |
| `_参考源文档/` | 从设计资料包中抽出的关键文档（MAP-01 地图设计、布局原型图） |

## 工程与环境

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2** stable（标准版，非 .NET；纯 GDScript） |
| 引擎位置 | `E:/MyGame/tools/Godot/Godot_v4.7.2-stable_win64_console.exe` |
| 工程根 | `E:/MyGame/yunque/` |
| 渲染 | Forward+（Vulkan），1600×900 |
| 运行 | `Godot_v4.7.2-stable_win64_console.exe --path E:/MyGame/yunque` |
| 数据自检 | `... --headless --path E:/MyGame/yunque res://tests/test_data_integrity.tscn` |
| 冒烟测试 | `... --headless --path E:/MyGame/yunque --quit-after 200` |
| 截图 | `... --path E:/MyGame/yunque --resolution 1600x900 -- --screenshot=E:/MyGame/yunque/shots/x.png --shot-view=town\|bridge\|player\|menu\|dialogue` |

## 远端仓库

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/zhihu-baihe/zhihu`（公开，`main` 分支） |
| 首次推送 | 2026-10-15，7 个提交 / 292 个文件（含完整设计资料包） |
| 网络前提 | 本机直连 github.com 不通，必须走 v2rayN SOCKS 代理 |
| 推送命令 | `git -c http.proxy=socks5h://127.0.0.1:10808 push https://x-access-token:<TOKEN>@github.com/zhihu-baihe/zhihu.git main:main` |

> **大包提示**：仓库已配置 `http.postBuffer=5242880`（约 5MB）。不要调大——超过该值时 git 会改用整包上传，而代理会重置长连接（`curl 55 Send failure`）。小 postBuffer 会强制分块传输，实测可稳定推送 90MB+ 的提交。

## 目录结构（工程侧）

```
E:/MyGame/
├── yunque/                      Godot 工程
│   ├── project.godot            工程配置（autoload / 输入映射 / 渲染）
│   ├── data/                    数据层（JSON，全部内容数据在这里）
│   ├── scripts/                 GDScript（autoload / actors / interaction / world / ui）
│   ├── scenes/                  main / world / actors / props / ui
│   ├── tests/                   数据与流程自检
│   └── shots/                   实机截图（开发期视觉验证）
├── 开发文档/                     ← 本目录
└── 云阙行_设计资料包_v1.0/       源设计资料（勿改）
```
