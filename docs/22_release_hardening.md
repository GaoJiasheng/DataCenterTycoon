# 22 · 发布前打磨与工程加固（Codex 执行文档）

> 生成于 2026-08-15。方向已由项目所有者确认，作为本批次改造的**唯一执行依据**。
> 前置阅读：[00_decisions.md](00_decisions.md)、[20_gameplay_depth_and_economy.md](20_gameplay_depth_and_economy.md)、[21_warmth_patch.md](21_warmth_patch.md)。代码位置已与 `b597966`（build 9 上传态）核对。
> **本批次定性：零新功能。** 不新增任何玩法系统与决策条目；不修改任何经济数值字段（E6 只产报告）；20 种子模拟输出与当前基线完全一致（19.3 天中位、23.67× 净值比等具体数字逐字不变）。目标是把「桌面全绿」推进到「真机可信 + 发布可复现」。

## 0. 背景

18–21 号之后系统与温度都齐了，但存在三类欠账：**① 所有验证都发生在桌面单一画幅**（真机内存、缩小采样、异形屏从未被看过）；**② 发布与 CI 有手工断点**（TestFlight 管线靠考古、三个最能抓问题的门禁不在 CI）；**③ 若干 review 记录在案的小修与承诺未兑现的数值报告**。本批次逐项清账。

## 1. 工作项

### E1 · 纹理导入优化（真机内存与缩小采样，最高优先级）

**现状（已实测）**：全部 180 张美术 `compress/mode=0`（无损）且 `mipmaps/generate=false`。后果：每张 1024² 在显存中为 4MB 未压缩 RGBA；世界层建筑从 1024 缩至 ~300px 渲染无 mipmap，移动端有闪烁与带宽浪费。

**机制**

- 资产分两类处理，分类清单写进 `tools/import_assets.py`（它已是导入管线的唯一入口）：
  - **世界/场景大图**（建筑、地面、装饰、车辆、FX、meta 插画、人设、猫、猫片、商店大图）：`compress/mode=2`（VRAM Compressed，iOS 落 ASTC）+ `mipmaps/generate=true`；
  - **UI 图标与九宫格**（`ic_*`、`btn_*`、`panel_*`、`progress_*`、`dialog_*` 等小图与拉伸图）：维持无损、无 mipmap（ASTC 会糊小图标与切片边缘）。
- 色键透明边缘是风险点：ASTC 在硬边透明处可能出彩边。逐类抽 3 张代表资产 400% 放大对比留档。
- `tools/check_assets.py` 增加导入设置校验：两类资产的 compress/mipmap 设置与分类清单一致，防止后续新资产回退。

**验收**

1. 双语 `visual_smoke` 各 47 态重跑全绿，并对「世界主屏、棋盘、商店、典藏、人设卡」五态做前后像素对比留档（`docs/ui_review/22_texture_*`），肉眼无可见退化；边缘抽查图入档。
2. `performance_smoke` 不回退；报告压缩前后 pck 体积与估算显存占用差（写进本文验收记录）。
3. `check_assets --strict` 含新导入校验全绿。

### E2 · 多画幅探针与阻断级适配（异形屏从未被验证）

**现状**：`tests/visual_smoke.gd` 固定 `PREVIEW_SIZE = 990×2151`（8 行），SE 级小屏、6.7" 与 4:3 大画幅在 `aspect=keep` 下的表现从未捕获。

**机制**

- `visual_smoke` 支持 `--profile=se|standard|ipad` 参数：SE 级 750×1334、现行 990×2151（默认）、大画幅 1024×1366。SE 与大画幅档各捕获**关键 8 态**（地图、棋盘、行情+询价、科技、商店、离线日志、教程聚光灯、抽屉），不必全 47 态。参数名 `ipad` 作为稳定测试接口保留。
- 断言范围（**只修阻断级**）：内容不被裁切、letterbox 区域以主题色填充（不得露黑边或穿帮纹理）、触控目标 ≥44pt、安全区不压 HUD。D54 收窄发布范围后，此档继续作为 iPhone 兼容模式与通用大画幅布局哨兵，不承担 iPad 原生发布责任。
- 发现的阻断级问题随批修复；纯观感问题记录到本文验收记录留作后续，不在本批展开。

**验收**：三档 profile 双语全绿进 CI（SE/大画幅档跑 8 态）；阻断级问题清零并附前后截图。

### E3 · 发布管线脚本化

**现状**：TestFlight 管线（Godot 导出 → pbxproj 签名补丁 → archive → exportArchive → altool 上传）散落在历史会话里，已被人工考古两次。

**机制**

- 新增 `tools/release_ios.sh`：`--bump`（export_presets 版本号 +1 并提示提交）、默认走完整链（导出 → 补丁 `CODE_SIGN_STYLE = "Manual"→"Automatic"`、`CODE_SIGN_IDENTITY→"Apple Development"` → archive → codesign verify → export ipa）、`--upload` 才执行 altool、`--dry-run` 到 ipa 为止。云签名参数（API key AMDBKB83K9 / issuer / team D33974QQTD）做成脚本头部变量。
- 失败分支给人话提示：ASC 重复 build 号（`ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE`）→ 提示 `--bump` 后重来。
- xcarchive 归档到 `builds/archives/`，README 与 `docs/release_checklist.md` 更新为「只用脚本发布」。

**验收**：`--dry-run` 全链跑通产出可 verify 的 ipa（不上传）；脚本有 `-e` 级错误处理；文档同步。

### E4 · CI 缺口

**现状**：`.github/workflows/ci.yml` 只跑 test_runner / flow / midgame / 双语视觉。`tutorial_playthrough`、`full_campaign`、`performance_smoke`——历史上抓过最多真问题的三个门禁——不在 CI。

**机制**：三者入 CI（xvfb 方式同现有视觉任务）。`full_campaign` 仅 main 分支触发；`performance_smoke` 在 CI 用 `--ci` 参数：保留泄漏/节点/粒子清零断言，帧时长阈值放宽为非阻断警告（虚拟机帧时长无参考意义）。E2 的三档视觉探针一并入 CI。

**验收**：CI 全绿一次完整跑通记录；main 分支跑 campaign 的证据链接写进验收记录。

### E5 · 一致性三小修（review 记录在案）

1. `core/game.gd:1806`（旧档迁移补锁价）改走 `_locked_rate_for(customer_id, str(dc.get("contract_duration_id","standard")))`，与四条正式路径同源；补一条迁移单测（含活跃事件时迁移值等于折算值）。
2. `tests/visual_smoke.gd` 截帧撞上 1.2s 数字滚动动画（离线弹窗大数字曾被抓在中途）：涉及金额动画的状态等动画完成再截，或测试模式下动画时长归零——选一种，保证截图数字确定性。
3. `.translation` 二进制重导入噪声：`tools/check_release.py` 增加「从 ui.csv 重编译对比当前 .translation 内容一致」的校验，并在 README 写明工作区脏了直接 `git checkout localization/`。

**验收**：三项各有对应单测/门禁改动，全量回归绿。

### E6 · 数值收尾报告（**只产报告，不改任何正式数值**）

1. **T2 维护费重扫**：B7 承诺的折算基线重扫，[900, 1150] 六档 × 20 种子，约束与结论格式沿用 `balance_runs/archive/t2_maintenance_sweep_pre_b7.csv`，输出新 CSV + balance_report 一段结论，等所有者拍板。
2. **扩编 L4 探针**：构造转生 ≥1 且现金充足的场景，证明 $10M 档可购、容量 5 生效、模拟器策略在该场景会购买——这是目前唯一零覆盖的商品。
3. **钻石经济源汇表**：按时代分段统计三策略 30 天的钻石获取（时代/路线图/典藏/成就）与消耗（加速/即修），产出源汇表进 balance_report，不调值。

**验收**：三份报告落档；模拟器基线数字零漂移（本批铁律的硬证明）。

### E7 · 健壮性用例（存档三链路）

1. **损坏恢复**：`core/save_manager.gd` 已有 3 份轮转备份（BACKUP_COUNT=3, `load_save` 逐份回退）——但无自动化用例。补：主档截断/写垃圾 → 从最近备份恢复、备份全坏 → 全新开局不崩、恢复路径给玩家 toast。
2. **时钟回拨**：`_settle_wall_gap` 有实现无专测。补：wall time 回拨 24h → 收入不为负、`highest_wall_time` 单调、离线报告不产生负值行。
3. **跨版本升级链**：把 v1/v2 存档真实样本存为 `tests/fixtures/save_v*.json`，断言升级到当前版本后账号资产（钻石/权益/典藏/品牌）无损、进入游戏全部门禁级不变量成立。

**验收**：三组用例入 `test_runner`，总数增长写进验收记录。

### E8 · 现有系统的首次引导补全

询价、成组、扩编都晚于教程定稿，FTUE 不教。用**现有** `tutorial.dismissed_messages` 一次性提示机制（core/game.gd:1875）补三条 first-encounter 提示：首次成组形成（棋盘 toast「同类整行 +10%」）、首次队列满且现金足够扩编（提示科技页）、首张询价到达已有待办中心行——确认其首次出现带一次性说明气泡即可。不加新机制、不加红点系统。

**验收**：三条提示各只出现一次、跨存档重置正确；FTUE 审计不回退；双语。

### E9 · 内容三连（报告为主，小修随批）

1. **弱资产横评**：47 态双语截图全铺开横向审查，产出「最不协调资产 Top 5」名单 + 每张问题描述与重生成 prompt 草稿（报告，不重生成，等所有者点名）。
2. **英文文案校对**：`ui.csv` EN 列全量过一遍——母语级流畅度、术语一致性（era/term/lock 等译名统一表）、长度不破版；改动即提交（这是文案修订不是新功能）。改后跑英文 `visual_smoke` 与字体门禁。
3. **音频与色觉**：`assets/audio/manifest.json` 的 `volume_db` 做一轮相对响度平衡（同类 sfx 峰值差 ≤3dB，结论入档）；棋盘/待办的红绿橙状态逐个确认有图形差异兜底（已有 ✓/⚠/⚡，查漏），缺的补图形不改配色。

**验收**：横评报告落档；EN 全量 diff 可 review；音频调整表 + 色觉查漏结论入档。

## 2. 实施顺序与批次

```
批次 1：E1 纹理导入            （独立、收益最大，先行）
批次 2：E2 多画幅探针 + 阻断修复
批次 3：E3 发布脚本 + E4 CI    （基建一并）
批次 4：E5 一致性三小修 + E7 健壮性用例
批次 5：E8 首次引导 + E9 内容三连
批次 6：E6 数值报告 + 全量回归 + 文档同步 + 验收记录
```

每批次 `test_runner` 保持绿，批次间独立提交。

## 3. 明确不做

- 不加任何新系统、新决策条目、新收集组、新商品；不改任何经济数值（E6 报告除外，且报告不落值）。
- 不做大画幅理想化布局（D54：1.0 不承担 iPad 原生发布责任，兼容模式只守阻断级）。
- 不做需要真机或所有者账号的项：Instruments 60fps 实测、StoreKit sandbox 全流程、商店截图/元数据/隐私链接（继续留在 release_checklist 外部交付清单）。
- 不动随机流、锁价、离线结算的任何行为。

## 4. 给执行者的注意事项

1. E1 是本批最大风险源：ASTC 转换必须逐类抽查透明硬边，视觉对比留档先于合入；宁可把某类资产留在无损清单，也不接受可见退化。
2. E2 的 letterbox 填充注意 `stretch/aspect="keep"` 下视口外区域由窗口清屏色决定——用主题色而不是改 stretch 模式（15 号踩过 stretch 的坑，不要动 `expand/keep` 的既有结论）。
3. E5-1 迁移改动要用「含活跃事件的旧档」写正反例——迁移时刻的折算值与瞬时值不同才是这条修复的意义。
4. E8 的一次性提示走 `dismissed_messages` 既有语义，禁止新建持久化 key；提示文案双语、≤30 汉字。
5. E9-2 英文校对**只改 EN 列**，key 与 zh 列一律不动；术语统一表先立后改，diff 按 key 排序方便 review。
6. 全批次收尾必须重跑 README「开发与验收」全部命令 + 20 种子模拟零漂移证明，验收记录格式沿用 20/21 号。

## 5. 验收记录（2026-08-28）

### 批次与提交边界

- [x] 批次 1：`145fdb9 perf: optimize production texture imports`。
- [x] 批次 2：`da51877 test: add multi-aspect visual probes`。
- [x] 批次 3：`700503e build: script iOS release and complete CI gates`。
- [x] 批次 4：`7fd4d2f fix: harden save recovery and release consistency`。
- [x] 批次 5：`6c4527a polish: clarify first encounters and release content`。
- [x] 批次 6：E6 三份报告、全量回归、README / release checklist / 本节验收记录保留为独立最终提交。

### E1 · 纹理导入

- [x] 180 张正式美术按运行职责固定分类：45 张 UI 图标/九宫格保持无损无 mipmap，135 张世界、角色、场景与大图使用 VRAM 压缩 + mipmap；分类表由 `import_assets.py` 唯一维护，`check_assets --strict` 会阻止导入设置回退。
- [x] 世界建筑、机柜室内、人设、HUD、九宫格与商店六类 400% 边缘对照均已留档在 [E1 审计](ui_review/22_texture_audit.md)；中英世界主屏、棋盘、商店、典藏、人设卡前后对照无可见彩边或文字退化。
- [x] iOS PCK 78,479,308 B → 128,359,856 B（+63.56%，平台纹理换安装体积）；估算 GPU 纹理由 383,082,496 B → 159,675,733 B（-58.32%）；百机房 p95 8.76 ms → 8.27 ms。真机 ASTC 仍按范围边界留给 Instruments，不伪报。

### E2 · 多画幅

- [x] `visual_smoke --profile=se|standard|ipad` 分别锁定 750×1334、990×2151、1024×1366；SE 与大画幅中英各 8 个关键态、标准中英各 49 态全部通过。`ipad` 仅是保留的 profile 名；D54 生效后，该档语义为兼容模式与大画幅布局回归，不是 iPad 发布目标。证据与限制见 [多画幅审计](ui_review/22_multiform/README.md)。
- [x] `stretch/aspect="keep"` 未改；letterbox 清屏色统一为主题深蓝。没有发现裁切、黑边穿帮或小于 44pt 的阻断问题，未借机重做大画幅原生布局。

### E3 / E4 · 发布与 CI

- [x] `tools/release_ios.sh` 串起 Godot 导出、签名补丁、archive、codesign、IPA 导出/复验，支持 `--bump` / `--upload` / `--dry-run` 与重复 build 号人话提示。最终 build 9 干跑完整通过且未上传；脚本会删除未使用权限的空 Info.plist 说明，归档日志不再产生麦克风空说明警告。
- [x] CI 已加入 `tutorial_playthrough`、仅 main 的 `full_campaign`、`performance_smoke --ci` 及中英三画幅；其中 `--profile=ipad` 两个 job 保留为大画幅布局回归。性能 CI 只放宽帧时长为警告，粒子/节点泄漏仍为硬失败。
- [x] 远端 GitHub Actions 全量门禁已在 main 完整跑通：[Project gates #33180099937](https://github.com/GaoJiasheng/DataCenterTycoon/actions/runs/33180099937)。该 run 含 main 专属 `full_campaign`、243 项逻辑、完整触控教学、百机房性能及 SE/standard/iPad 中英全部视觉探针。

### E5 / E7 · 一致性与健壮性

- [x] 旧档合约迁移走 `_locked_rate_for`，含活跃事件的正反例证明迁移采用期限折算而非瞬时报价；已生效合约仍不追溯。
- [x] 视觉截图会等待金额滚动结束；`check_release` 会从 `ui.csv` 重编译并逐条核对 `.translation`，当前语义对照通过。
- [x] 主档截断可从最近轮转备份恢复并显示双语提示，全部备份损坏则安全新开；24 小时时钟回拨不产生负收入且单调防线不下降；v1/v2 fixture 升级后钻石、权益、典藏与品牌无损。

### E8 / E9 · 首遇与内容一致性

- [x] 询价、成组、可负担扩编三条 first-encounter 复用 `tutorial.dismissed_messages`，每条只出现一次，新公司按现有教程状态重置；FTUE 不提前展示。
- [x] `localization/ui.csv` 的 644 个英文条目已全量复核，统一术语表、37 个既有 EN 修订及双语 49 态结果记录在 [内容审计](22_content_audit.md)；既有 key 与中文列未改。
- [x] 音乐和同类 SFX 有效峰值差均 ≤3 dB；棋盘与待办红/绿/橙状态都有独立图形轮廓，不只靠颜色。最不协调资产 Top 5 与重生成 prompt 已入同一报告，本批没有越权重做美术。

### E6 · 只读数值报告

- [x] [T2 当前折算基线重扫](balance_runs/t2_maintenance_sweep.csv)：六档 × 20 种子 × 三策略全部通过挂机 0/0 与激进 25% 压力带；$900 对活跃斜率只改善 2.4%，正式 $1,150 不变。
- [x] [工程部 L4 探针](balance_runs/engineering_l4_probe.csv)：运行时以 $10M 正式价格可购；模拟器在转生 1、时代 3、4/4 满队列和既有 15% 现金缓冲下确实购买，容量变为 5。
- [x] [钻石 30 天源汇](balance_runs/diamond_sources_sinks_30d.csv)：按三策略/三时代/20 种子区分自动来源与可领取来源；参考策略观测加速与即修消耗均为 0，此为消费行为覆盖缺口，不据此调值。结论已回写 `balance_report.md`。

### 最终门禁与范围边界

- [x] `test_runner` 243/243；`flow_audit`、`midgame_audit`、真实触摸 `tutorial_playthrough`、`full_campaign` 全绿。长战役第 118 月达到 20 座并同局通过询价、5 槽成组、期限决策、稀有战略封顶与 3 路扩编，最终 23 座、时代 3、净值 $1.70M 后完成重组。
- [x] 最终 `performance_smoke`：平均 6.63 ms、p90 6.95 ms、p95 7.01 ms；30 粒子、猫特效与节点均回收到 0。
- [x] `validate_data` 通过 16 表、本地化与 180 art IDs；`check_assets --strict --audio` 通过 180 美术、6 字体、23 音频；双语标准 49 态与 SE/iPad 各 8 态全绿。
- [x] 20 种子默认模拟输出 SHA-256 仍为 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`，活跃 20 座中位 19.3 天、活跃/挂机净值比 23.67×，证明全批正式经济零漂移。
- [ ] `check_app_store_assets` / `check_release` 仍被本批明确排除的外部交付阻塞：中英 iPhone/iPad 商店截图、隐私/支持正式链接和 iOS IAP 插件描述符尚未交付；真机 Instruments 与 StoreKit sandbox 也未伪报完成。详细清单见 [release checklist](release_checklist.md)。
