# 《云阙行：九灯照夜》开发文档索引

> 本目录存放**工程侧**文档：路线图、实现方案、开发日志、设计文档映射。
> 源设计资料（策划案原文）在 `_参考源文档/` 与 `../云阙行_设计资料包_v1.0/`。

## 一句话现状

**M1 / M2（存档）/ 美术第一批均已落地**：Godot 4.7.2 工程可跑墨邑古城·百花千灯会——第三人称探索、9 个区域、10 名 NPC 的阶段化对白、3 条主线线索、1 条完整支线、任务日志/交互提示/存档系统全部可用。
视觉侧已离开灰盒：建筑是**程序化中式木构**（举折屋面/翼角起翘/正脊/檐下椽头/檐柱/额枋/格子窗/石台基），角色是**程序化人形**（含行走与待机动画），音效由脚本**程序化合成**（环境音三层 + 脚步 + UI + 事件提示）。战斗/迷宫/BOSS/装备在后续里程碑。

## 里程碑状态

| 里程碑 | 内容 | 状态 |
|---|---|---|
| **M1** | 工程骨架 + 墨邑城镇（探索/交互/对白/线索/支线/任务日志） | ✅ 已完成（自检 42/42） |
| **M2a** | 存档系统（自动 + 3 手动槽位、版本号、派生旗标重算） | ✅ 已完成 |
| **M7a** | 建筑真实结构（程序化中式木构，替代盒子 + 贴图） | ✅ 已完成 |
| **M7b** | 真实 PBR 材质（ambientCG CC0 × 7 套 + 世界三平面映射） | ✅ 已完成 |
| **M7c** | 角色建模 + 动画（程序化人形 + walk/idle） | ✅ 已完成（第一版） |
| **M7d** | 音效（程序化合成 19 个 + 环境音三层） | ✅ 已完成 |
| **M2b** | 旧灯坊迷宫 + 阿禾救援线 | 待开始 |
| M3 | 行动条战斗系统 + 教学战 + 普通敌人 AI | 待开始 |
| M4 | 百面灯魇四阶段 BOSS + 失败重试 | 待开始 |
| M5 | 装备/锻造/材料经济 + 姜阿棠技能树 | 待开始 |
| M6 | 序章《借灯下山》（落灯观 + 砺剑镇 + 吞风蜃犬） | 待开始 |
| M7e | 美术精修（瓦当滴水/斗拱/脊饰/铺面柜台/角色手指与面部） | 待开始 |
| M8 | 序章→第一章完整闭环 + 存档兼容与回归测试 | 待开始 |

## 文档索引

| 文件 | 内容 |
|---|---|
| `01_开发路线图_ROADMAP.md` | 里程碑拆解、验收标准、风险清单（P0/P1） |
| `02_M1_墨邑花灯节_实现方案.md` | M1 的目标、区域落地表、系统架构、数据结构、验证结果 |
| `03_开发日志.md` | 按日期记录每次实质改动与缺陷修复 |
| `04_设计文档到Godot映射.md` | UE5 设计文档 → Godot 的命名/结构对照，工程约定 |
| `05_美术标准_ArtBible.md` | 美术标准：色彩/光照/材质/模块化规则/命名规范/性能预算/**角色与动画标准**/**音效标准** |
| `06_墨邑古城_美术实施方案.md` | 墨邑首个美术任务（A—H 格式）：场景用途、地标、参数、资产清单、验收 |
| `07_角色动画与音效方案.md` | 角色建模 / 动画 / 音效的技术方案、调参指南、已知局限 |
| `资源台账.md` | 全部资产登记（来源 / 授权 / noai / 用在哪里）+ 中式资产候选 |
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
| 截图 | `... --path E:/MyGame/yunque --resolution 1600x900 -- --screenshot=E:/MyGame/yunque/shots/x.png --shot-view=<机位>`，机位见下表 |
| 音效重生成 | `python tools/gen_sfx.py`（在 `yunque/` 下执行；纯标准库，无需虚拟环境） |

### 截图机位（`--shot-view=`）

| 机位 | 画面 |
|---|---|
| `player`（默认） | 第三人称跟随视角（主街） |
| `town` | 城镇俯瞰 |
| `bridge` | 千灯桥 + 城门 |
| `roof` | 建筑斜俯近景（屋面曲率 / 正脊翘头 / 檐下椽头 / 石台基） |
| `facade` | 建筑正立面（格子窗 / 檐柱 / 额枋 / 门洞 / 招牌） |
| `char` | 主角特写（比例 / 配色 / 待机 / 佩剑） |
| `npc` | NPC 特写（站在该 NPC 正前方拍） |
| `walk` | 步态冻结帧（`_phase=1.30`，用于复核走姿） |
| `menu` / `menu_save` / `dialogue` | 菜单 / 存档页 / 对白界面 |

## 远端仓库

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/zhihu-baihe/zhihu`（公开，`main` 分支） |
| 首次推送 | 2026-10-15，7 个提交 / 292 个文件（含完整设计资料包） |
| 网络前提 | 直连 github.com 时通时不通；**失败就走 v2rayN SOCKS 代理** |
| 推送命令 | `git push https://x-access-token:<TOKEN>@github.com/zhihu-baihe/zhihu.git main:main`（代理已写在仓库本地配置里） |

> **大包提示**：仓库已配置 `http.postBuffer=5242880`（约 5MB）。不要调大——超过该值时 git 会改用整包上传，长连接容易被重置（`curl 55 Send failure` / `HTTP 408`）。小 postBuffer 会强制分块传输，实测可稳定推送 90MB+ 的提交；偶发失败直接重试即可（第二次通常就过）。

## 在新机器上继续开发

> 仓库里**已经包含**工程代码、数据、贴图、音频、开发文档与源设计资料包。
> 克隆之后只有一件事需要本机单独准备：**Godot 引擎**。

| 步 | 操作 |
|---|---|
| 1 | 装 Godot **4.7.2 stable 标准版**（非 .NET）：`github.com/godotengine/godot/releases/tag/4.7.2-stable` → 下载 `Godot_v4.7.2-stable_win64.exe.zip`，解压到 `<仓库根>/tools/Godot/` |
| 2 | `git clone https://github.com/zhihu-baihe/zhihu.git E:/MyGame`（路径可换，注意**用纯 ASCII 路径**） |
| 3 | 用 Godot 打开 `E:/MyGame/yunque/project.godot`（首次自动导入，约 1 分钟） |
| 4 | 数据自检：`--headless --path E:/MyGame/yunque res://tests/test_data_integrity.tscn` → 期望 **42/42 通过** |
| 5 | 冒烟：`--headless --path E:/MyGame/yunque --quit-after 200` → 期望 **0 错误 0 警告** |
| 6 | 编辑器里 F5 直接运行 |

**不需要重新下载**：贴图（`yunque/assets/processed/textures/`）、音频（`yunque/assets/processed/audio/`）、设计资料包。
**需要本机具备**：Godot 4.7.2；若要改音效则还需 Python 3.8+（`gen_sfx.py` 只用标准库，不必装依赖）。

**不在仓库里的东西**（各自机器的本地产物，克隆后会自动重建）：

| 路径 | 原因 |
|---|---|
| `tools/` | Godot 引擎二进制（约 82 MB，与平台绑定，不入库） |
| `yunque/.godot/` | Godot 导入缓存，首次打开自动重建 |
| `.workbuddy/` | 本地工作区记忆（不进版本库） |

> **两个最容易漏的步骤**：
> 1. **新增带 `class_name` 的脚本后要跑一次 `--headless --import`**，否则无头运行会报 `Identifier "X" not declared`。
> 2. **改了音效参数后要重跑 `cd yunque && python tools/gen_sfx.py`**，再让 Godot 重新导入 WAV。

## 目录结构（工程侧）

```
E:/MyGame/
├── yunque/                      Godot 工程
│   ├── project.godot            工程配置（autoload / 输入映射 / 渲染）
│   ├── data/                    数据层（JSON，全部内容数据在这里）
│   ├── scripts/                 GDScript（autoload / actors / interaction / world / ui）
│   ├── scenes/                  main / world / actors / props / ui
│   ├── tools/gen_sfx.py         音效合成脚本（音频的唯一源头，改音色改这里）
│   ├── assets/source/           原始下载档（只读，不覆盖）
│   ├── assets/processed/        唯一被场景引用的可用档（textures / audio）
│   ├── tests/                   数据与流程自检
│   └── shots/                   实机截图（开发期视觉验证，不进构建）
├── tools/Godot/                 引擎（不入库，新机器需自行下载）
├── 开发文档/                     ← 本目录
└── 云阙行_设计资料包_v1.0/       源设计资料（勿改）
```
