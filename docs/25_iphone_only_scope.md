# 25 · 收窄为 iPhone-only 发布（Codex 执行文档）

> 生成于 2026-08-30。**所有者已拍板**：1.0 收窄为 iPhone-only 发布。基线 `1ff29c9`（24 号已全部关闭，build 10 在 TestFlight）。
> **定性：发布范围收窄 + 一致性收尾，零玩法改动。** 不改任何经济数值与随机流；20 种子模拟输出与基线逐字一致（19.3 天中位、23.67×）。

## 0. 背景与依据

24 号交付的 iPad 商店截图实测 **38.6% 的画面宽度是纯色信箱**（内容仅占 61.4%），观感等同「手机截图贴在深色底上」。本作是竖屏挂机游戏，D02 原本只承诺「iPad 可用即可」，为这 10 张不体面的截图承担 iPad 发布责任不划算。

所有者决定：**1.0 只面向 iPhone 发布**。iPhone-only 应用在 iPad 上仍以兼容模式运行，玩家不会被挡在门外，但 App Store 不再要求 iPad 截图、也不再按 iPad 体验评审。

## 1. 决策变更（先做）

`00_decisions.md`：

| 条目 | 变更 |
|---|---|
| D02 | **修订**：平台表述从「iPhone 全系为主，iPad 可用即可」改为「**1.0 仅 iPhone**；iPad 以 iPhone 兼容模式运行，不作为发布目标、不承担 iPad 布局与截图责任」 |
| D54（新增） | **发布设备范围**：`targeted_device_family` 锁为 iPhone。若将来要恢复通用包，必须同时恢复 iPad 商店截图组与 iPad 发布责任，不得只改导出目标 |

## 2. 工作项

### H1 · 导出目标

- `export_presets.cfg:264`：`application/targeted_device_family=2` → `0`（Godot 枚举 `0=iPhone / 1=iPad / 2=Universal`）。
- `ios/README.md` 的「iPhone/iPad 通用」基线描述更新为 iPhone-only。
- **重要且必须写进验收记录**：build 10 已作为通用包上传 ASC。改配置**不会**改变线上已有 build 的设备支持，只有**下一个 build** 才生效。本批次**不发新 build**——发船时机由所有者决定。

### H2 · 商店交付收窄

- `tools/check_app_store_assets.py`：`SCREENSHOT_GROUPS` **整组移除** `ipad_13`（不是放宽尺寸，是不再要求）。
- 删除 `docs/store/screenshots/{en,zh_CN}/ipad_13/` 共 10 张，`README_review.md` 移除对应两节。
- `docs/store/README.md`：目录契约、尺寸段落、以及「工程导出为 iPhone/iPad 通用包，因此 iPad 截图也是发布必需项」这句依据全部改写。
- `tests/store_shots.gd` 的 `--device=ipad_13` 分支**保留**（零成本，将来若恢复通用包可立即重生成），但 README「开发与验收」的四条命令收敛为 iPhone 两条，并注明 iPad 档为可选、非发布必需。

### H3 · 覆盖处理（**本批次最容易做错的一条**）

`visual_smoke --profile=ipad`（1024×1366）与 CI 里对应的两个 job **一律保留**。

理由：iPhone-only 不等于「iPad 上不会被打开」——兼容模式仍会渲染；且这个大画幅探针历史上是布局回归的有效哨兵。**为了配合一个营销范围决策去删测试覆盖是错的。** 只把它的语义从「发布阻断的 iPad 档」重述为「大画幅布局回归」，写进 `22_release_hardening.md` §E2 的记录旁与 README 说明。

### H4 · 其余文档一致性

- `docs/04_tech_plan.md`「适配刘海屏与 iPad」一句更新；
- `docs/release_checklist.md`：设备烟测清单里的 iPad 项、商店素材里的 iPad 截图项按新范围改写（iPad 兼容模式抽查可保留为可选项，但不再是发布阻断）；
- `README.md` 当前状态与门禁数量同步。

## 3. 验收

1. `python3 tools/check_app_store_assets.py`：只校验中英 × `iphone_69` 共 **10 张**并通过。
2. `python3 tools/check_release.py`：**仍红且只红在 7 个所有者占位值 + IAP `.gdip` 描述符**——本批次不得让这份清单多出或少掉任何一条。
3. `export_presets.cfg` 的 `targeted_device_family=0` 有单独证据（贴出该行）。
4. 全量门禁绿：`test_runner` 243/243、`flow_audit`、`midgame_audit`、`tutorial_playthrough`、`full_campaign`（含二周目）、`performance_smoke`、双语标准 49 态、**SE 与 iPad 各 8 态仍在且仍绿**。
5. `python3 tools/simulate_economy.py --seed-count 20` 输出零漂移（19.3 天中位、23.67×）。
6. 验收记录写明「设备支持需下一个 build 才生效」，格式沿用 20–24 号。

## 4. 明确不做

- **不删任何测试覆盖**（尤其 iPad 视觉探针与其 CI job）。
- 不改 `stretch/aspect`、不改任何 UI 布局、不改经济数值与随机流。
- 不填任何所有者身份值（24 号 §1 红线继续适用）。
- 不发新 build、不动 TestFlight。

## 5. 验收记录（2026-08-30）

### 决策与导出范围

- [x] `00_decisions.md` 已修订 D02：1.0 仅面向 iPhone，iPad 只以 iPhone 兼容模式运行，不作为发布目标，也不承担 iPad 原生布局与截图责任；新增 D54 锁定恢复通用包时必须同步恢复 iPad 截图组与发布责任。
- [x] `export_presets.cfg:264` 实际证据为 `application/targeted_device_family=0`；`ios/README.md` 与 `04_tech_plan.md` 已同步 iPhone-only 发布基线。
- [x] **build 10 已作为 Universal 通用包上传 App Store Connect。** 本次修改导出配置不会改变线上已有 build 的设备支持，只有下一个 build 才会生效；本批次没有递增 build、没有归档、没有上传，也没有改动 TestFlight。

### 商店交付与大画幅覆盖

- [x] `check_app_store_assets.py` 的 `SCREENSHOT_GROUPS` 已整组移除 `ipad_13`，不是放宽尺寸；中英两个 `ipad_13/` 目录共 10 张旧交付图已删除，审片索引同步收敛为 10 张 iPhone 图。
- [x] `python3 tools/check_app_store_assets.py` 实际输出：`Validated opaque app icon and 10 localized iPhone screenshots.`；两种语言各五张均通过尺寸、组内一致性、PNG 有效性与无 alpha 校验。
- [x] `tests/store_shots.gd` 的 `--device=ipad_13` 分支仍保留，README 正式复现命令已收敛为中英两个 iPhone 命令，并明确 iPad 档只作可选兼容抽查。
- [x] `visual_smoke --profile=ipad` 没有删除；CI 的中英两个 1024×1366 job 仍在，只把名称与文档语义改为“大画幅布局回归”。SE 与大画幅中英各 8 态、标准中英各 49 态实际复跑全部通过。

### 发布门禁与一致性

- [x] `check_release.py` 已把导出断言同步为 `targeted_device_family=0`，翻译资源逐条对照、17 张数据表、180 个美术 ID 与 10 张 iPhone 截图均通过；实际阻断清单恰好只剩 7 个所有者占位字段（`product_name / privacy_email / support_email / privacy_url / support_url / effective_date / ad_providers`）与缺少 StoreKit/IAP `.gdip` 描述符，没有多项或少项。
- [x] `test_runner` 最终 `243 passed, 0 failed`；`flow_audit`、`midgame_audit`、真实触摸 `tutorial_playthrough` 均通过。`full_campaign` 含二周目通过：首局第 108 月达 20 座，二局第 11 月达 21 座并续跑至第 30 月 59 座。
- [x] 百机房性能独占复测通过：13 个园区页、当前页 6 对象、统一朝向与单猫状态机正常，average `7.35ms`、p90 `9.55ms`、p95 `12.02ms`；30 粒子、猫特效与节点增量均归零。
- [x] `validate_data`、`check_assets --strict --audio` 与 `report_release_economy.py` 全绿：17 表、180/180 美术、6/6 字体、23/23 音频；T2 六档、工程部 L4 与钻石源汇三份只读报告通过，未落任何正式数值。
- [x] `python3 tools/simulate_economy.py --seed-count 20 --no-write | shasum -a 256` 输出 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`，与 `1ff29c9` 基线逐字一致；活跃 20 座中位 19.3 天、活跃/挂机 30 日净值比 23.67×，证明本批零玩法、零经济、零随机漂移。
