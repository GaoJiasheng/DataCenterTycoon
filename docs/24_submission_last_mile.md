# 24 · 上架最后一公里（Codex 执行文档）

> 生成于 2026-08-29。方向已由项目所有者确认，作为本批次的**唯一执行依据**。
> 基线：`720072b`（build 10 已上传 TestFlight，06–23 号全部关闭）。
> **定性：交付材料与覆盖收尾，零玩法改动。** 不改任何数值字段、不动随机流；20 种子模拟输出与基线逐字一致（19.3 天中位、23.67×）。

## 0. 背景

游戏侧已经没有欠账：243 项逻辑、六档视觉矩阵、全程战役、百机房性能、CI 全绿、build 10 在 TestFlight。**唯一亮红灯的是两个发布门禁**：

```
check_app_store_assets  → 缺 20 张商店截图（2 语言 × 2 设备 × 5 屏）
check_release           → 上述截图 + 4 个占位符文件 + IAP 插件描述符
```

其中截图是**纯工程活**，现在就能做；占位符里混着「只有所有者能给的值」和「可以先做好的填充机制」，本批次做机制、不填值。

## 1. 红线（最重要，先读）

**禁止编造任何以下内容**：产品名、隐私邮箱、支持邮箱、隐私政策 URL、支持 URL、生效日期、广告商名称、任何 Apple 账号相关值。这些是所有者的真实身份信息，凭空造一个填进去比留占位符危险得多——它会静默通过门禁然后进入 App Store 审核。

占位符只能保持占位。本批次交付的是「等所有者给值后一条命令填完」的机制，不是值本身。

## 2. 工作项

### G1 · 商店截图管线（最高优先级，解锁 `check_app_store_assets`）

**目标**：产出 `docs/store/screenshots/{en,zh_CN}/{iphone_69,ipad_13}/0{1..5}_*.png` 共 20 张，通过 `python3 tools/check_app_store_assets.py`。

**尺寸契约**（`tools/check_app_store_assets.py:17` 已锁定，不要改校验器）：
- `iphone_69`：1320×2868（取 Apple 三档中的最高档，与工程设计基线一致）
- `ipad_13`：2048×2732
- 同组五张必须同尺寸；PNG 不得带 alpha 通道。

**技术难点与解法**：当前 `visual_smoke` 用 `get_viewport().get_texture().get_image()`，尺寸受操作系统窗口上限约束，2868/2732 高度在多数显示器上开不出来。**解法：新增独立的截图工具 `tests/store_shots.gd/.tscn`，把 `main.tscn` 挂进一个 `SubViewport`**，SubViewport 尺寸直接设为目标分辨率、与 OS 窗口无关，再从 `SubViewport.get_texture().get_image()` 取图。不要用「小尺寸渲染 + 放大」——Apple 对模糊截图会打回，且这是自欺欺人。

**五屏构图**（`docs/store/README.md` 已定义语义，按它执行）：

| 文件 | 内容要求 |
|---|---|
| `01_park.png` | 多机房园区全景：≥5 座不同 tier 的运营机房、路网与装饰完整、HUD 有像样的现金/时代，最好有猫入镜 |
| `02_datacenter.png` | 机房抽屉：3×3 满槽、成组加成光效与 +10% 徽标可见、供电条与冷却覆盖清楚 |
| `03_market.png` | 行情页：曲线有丰富历史（≥1 个已生效事件 + 1 条预告）、询价区两张带人设头像的卡 |
| `04_technology.png` | 科技页：三时代路线图（前两个已完成）、网络与维修队有等级、工程部扩编条目可见 |
| `05_prestige.png` | 后期规模 + 上市重组卡：进度 ≥20/20、品牌倍率预估、保留/清算清单 |

**构图纪律**：
- 必须是**真实游戏画面**（README 明令不接受概念图）：用一份精心构造的存档夹具驱动，而不是把 UI 摆出来假装。
- 画面里不得出现测试痕迹：调试文本、`feedback_dc` 这类夹具 id、$0 的空盘、未解锁的问号占位铺满屏。
- 中英两版必须是**同一份存档、同一构图**，只切语言——不能中文版丰满英文版空。
- iPad 3:4 在 `aspect=keep` 下必然有上下信箱：信箱区用主题色（沿用 22 号 E2 的 `#122438` 结论），**不要为了填满而改 stretch 模式**。若信箱比例大到让截图不体面，在验收记录里如实说明并给出建议（例如导出改为 iPhone-only 从而免除 iPad 截图），交所有者决定，不要自行改导出目标。

**验收**
1. `python3 tools/check_app_store_assets.py` 通过（20 张齐、尺寸正确、组内一致、无 alpha）。
2. 20 张全部贴进 `docs/store/screenshots/README_review.md` 缩略图索引，便于所有者一次过目。
3. 截图脚本可复跑：`godot --path . tests/store_shots.tscn -- --locale=zh_CN --device=iphone_69` 形式，写进 README「开发与验收」。
4. 不改任何游戏代码；若为构图需要给存档夹具加辅助函数，只能加在 `tests/` 下。

### G2 · 发布身份集中化（让 `check_release` 只差账号值）

**现状**：`REPLACE_WITH_PRODUCT_NAME`、`REPLACE_WITH_PRIVACY_EMAIL`、`REPLACE_WITH_SUPPORT_EMAIL`、生效日期、广告商名散落在 `docs/public/privacy.html`、`docs/public/support.html`、`docs/store/metadata/{en,zh_CN}.md` 四个文件里，等所有者给值时要手工改四处、易漏。

**机制**
- 新增 `data/release_identity.json`，字段：`product_name / privacy_email / support_email / privacy_url / support_url / effective_date / ad_providers[]`。**全部初始值保持 `REPLACE_WITH_*` 占位**（红线：不许填真值或假值）。
- 四个交付文件改为模板（`.tmpl`）+ 生成产物；新增 `tools/fill_release_identity.py` 一条命令渲染全部。
- `tools/check_release.py` 的占位符检查改为：**先校验 `release_identity.json` 无占位符残留，再校验渲染产物与模板一致**（即产物没有被手工改脏）。语义等价于现在的检查，但把「四处手工」变成「一处填值 + 一条命令」。
- README 与 `release_checklist.md` 写明这条流程。

**验收**：所有者给值后 `python3 tools/fill_release_identity.py && python3 tools/check_release.py` 应只剩「IAP 插件描述符」与截图两项（截图由 G1 解决）；本批次交付时 `check_release` 仍应因占位符而红——**这是正确结果，不许为了变绿而填值**。

### G3 · 商店文案补全（不含产品名）

`docs/store/metadata/{en,zh_CN}.md` 目前只有名称/副标题/关键词/一段简介。补齐 App Store Connect 实际要填的其余字段，中英各一份，**产品名继续留占位**：

- **推广文本**（Promotional Text，≤170 字符）
- **完整描述**：结构化重写现有简介——开篇钩子、核心循环三句、特色列表（离线收益/签约锁价/园区定位/公司传承/无强制日常）、结尾召唤。中文版独立写作，不逐字直译。
- **更新说明**（What's New，首版）
- **审核备注**：四个激励视频入口的位置、恢复购买按钮位置、八个 SKU 的沙盒验证步骤——现有 metadata 末尾那句要求已写明，把它展开成审核员能照做的步骤。
- **年龄分级问卷答案草稿**：逐题给出建议答案与依据（本作无暴力/无真实赌博；含内购与可选广告），标注「待所有者确认」。

**验收**：两份 metadata 齐全可直接粘贴进 ASC；`check_release` 仍只因产品名占位而红；文案长度符合 ASC 上限（描述 4000 字符、推广 170、关键词 100）。

### G4 · 闪测根因（技术债）

`rejected operations stay visible above sheets and rapid retries restart friendly feedback` 在重负载批跑中约 1/6 概率失败，独立运行 19 连绿。`720072b` 已把复合断言拆段并在失败时打印当时 toast 的 visible/text。

**任务**：在负载下复现（例如与视觉门禁并行跑 test_runner，或人为拉高 CPU），读诊断输出定位是哪个 toast 顶掉了 `REASON_NOT_ENOUGH_CASH`——嫌疑源见 `_show_toast` 的调用方（成就 `TOAST_ACHIEVEMENT`、施工完成、合约续约、存档恢复通知）。定位后按真实性质修：若是产品缺陷（例如成就 toast 抢占错误反馈）就修产品；若确为测试自身与后台信号竞速，就让夹具隔离该信号源，**不许放宽断言了事**。

**验收**：根因写进验收记录；修复后连跑 20 轮 `test_runner` 全绿；若 20 轮未复现，如实记录「未复现」并保留诊断，不伪称已修。

### G5 · 二周目覆盖（最后一个已知覆盖缺口）

`full_campaign` 走到第一次上市重组就结束。D19/D29 承诺的跨局价值（财富转速度、董事会永久点、公司纪念册）**从未被端到端验证过**。

**任务**：在 `tests/full_campaign.gd` 现有转生之后续跑 30 游戏月的「第二局」，断言：
- 转生带回的现金可立即重购工程部扩编，且队列容量真的恢复到购买档；
- 董事会点数可分配、其加成在权威收入公式中生效（与 `datacenter_income_per_month` 对账）；
- 公司纪念册/典藏保留了第一局记录，路线图已领取项不重复给奖；
- 第二局达成 20 座所需月数**短于**第一局（跨局节奏真的增长了——这是 D38 的立项理由，值得有个断言守住）；
- 全程无死档、无负值、无不可退出界面。

**验收**：`full_campaign` 仍绿且新增断言全部有效（故意破坏其一应当变红）；运行时长增加写进验收记录；模拟器基线零漂移。

## 3. 实施顺序

```
批次 1：G1 商店截图管线      （最大项、唯一解锁提交的硬通货）
批次 2：G2 发布身份集中化 + G3 商店文案
批次 3：G4 闪测根因
批次 4：G5 二周目覆盖
批次 5：全量回归 + 文档同步 + 验收记录
```

每批次 `test_runner` 保持绿，批次间独立提交。

## 4. 明确不做

- **不填任何真实身份值**（见 §1 红线）；不为了让门禁变绿而伪造数据。
- 不装 StoreKit/广告 SDK 插件（需要外部二进制与所有者账号，留在 `ios/README.md` 的所有者步骤里）。
- 不改导出目标（iPhone-only 与否是所有者决定）、不改 `stretch/aspect`、不改任何经济数值与随机流。
- 不做真机 Instruments、StoreKit sandbox、ASC 录入——外部交付照旧。

## 5. 给执行者的注意事项

1. G1 的 SubViewport 路线要先做一个最小验证（能否在 2048×2732 下取到完整非空图）再铺开五屏构图，避免走到最后发现取图受限。
2. 截图夹具要「像玩过的存档」而不是「摆拍」：机房年龄有差异、现金不是整数、行情有历史、待办有真实计数——这些细节决定截图可信度。
3. G2 改模板时注意 `check_release` 里已有的 `TRANSLATION_CHECK`（从 ui.csv 重编译比对）不要被影响。
4. G4 若定位到是成就 toast 抢占，那是**产品缺陷**——玩家在队列满的瞬间正好解锁成就，会看不到失败原因；按产品缺陷修（错误反馈优先级高于庆祝反馈）。
5. G5 的「第二局更快」断言要留够容差（行情随机会影响绝对月数），用中位或给一个宽松上界，避免造出新的闪测。
6. 验收记录格式沿用 20–23 号，逐项附证据；本批次结束时 `check_app_store_assets` 应变绿，`check_release` 应**仍红且只红在占位符与 IAP 插件**——把这个预期结果明确写进验收记录。
