# 21 · 温度补丁：值班日志、客户拟人化、机房猫（Codex 执行文档）

> 生成于 2026-08-15。方向已由项目所有者确认，作为本批次改造的**唯一执行依据**。
> 前置阅读：[00_decisions.md](00_decisions.md)、[20_gameplay_depth_and_economy.md](20_gameplay_depth_and_economy.md)（B1–B7 已全部落地）。本文代码位置已与 `11c428a`（build 8 准备态）逐一核对。
> **本批次定性：纯表现层。** 三个工作项共享一条铁律——**不改变任何数值结果**：不修改 `data/economy.json` / `racks` / `buildings` / `events` / `inquiries` / `meta_progression` 的任何数值字段（允许新增纯表现字段与新数据表），不触碰 `tools/simulate_economy.py`，20 种子模拟输出与当前基线完全一致。

## 0. 背景

18–20 号把经济学做扎实了：闭环成立、节奏在窗、门禁 207 项。剩下的短板不在系统而在**温度**——离线结算是一张冷账单、关系等级是一根无名进度条、园区没有生命迹象。本批次三个工作项分别修这三处，互相成就（日志里写猫、客户角色出现在日志里），合起来改变游戏的「性格」而不动它的「账本」。

## 1. 决策变更（先做：更新 00_decisions.md，新增「表现与叙事」小节）

| 条目 | 变更 |
|---|---|
| D50（新增） | **值班日志**：离线结算以「值班日志」叙事呈现，2–4 条按事件生成的日志行 + 原有账单数字。叙事只是包装：金额、事件、可领取项与权威结算完全一致且始终可见 |
| D51（新增） | **客户拟人化**：四类客户各配 2–3 位署名角色（人设），出现在询价卡、合约面板、关系升级时刻与值班日志。人设是纯表现层：关系、收入、条件判定全部沿用现有系统，不因角色不同而不同 |
| D52（新增） | **机房猫**：园区常驻的非经济环境生物。互动只产出动画、触觉与一次性典藏发现（「园区生活」组），**不产出任何可重复获取的货币**；教程期间不出现 |

## 2. 工作项

### C1 · 值班日志（离线结算叙事化）

**机制定义**

- 离线结算弹窗顶部新增「值班日志」区：2–4 条叙事行，从本次离线报告实际发生的事里生成，按优先级选取：银行接管 > 时代解锁 > 稀有行情 > 询价到达 > 故障与自愈 > 合约续约/免费改签 > 自动退役/老化 > 收入与流水（兜底，必有）。
- 每条日志 = 一个双语模板 + 报告数据占位符（机房名、客户名/人设名、金额、数量）。同类事件多发时聚合为一条（「3 台机柜在夜里自愈了」），不逐条刷屏。
- 每类事件准备 **3–5 个模板变体**避免复读；变体选择用**临时 RNG，种子取自报告内容哈希**——同一份报告永远生成同样的日志（可测试），且**不消耗任何持久化随机流**（行情、故障、询价序列逐位不变）。
- 无离线事件的短离线（不足 material 门槛，见 `_offline_report_is_material`，ui/main_view.gd:4656）维持现状不弹窗。原有账单区、金币堆、领取按钮、广告位一律保留原样，日志区加在其上方。
- C2/C3 联动：涉及客户的行写人设名（「周矿姐的单子跑完了一整夜」）；离线期间猫的存在可作兜底行的点缀（「猫在 2 号机房顶上睡了一晚」，仅当 C3 已落地且存档里猫已解锁）。

**数据改动**

- 新增 `data/duty_log.json`：`{"schema_version":1,"entries":{"<事件类型>":{"priority":N,"aggregate":true,"templates":["DUTY_LOG_FAULT_1","DUTY_LOG_FAULT_2",...]}}}`。模板值是本地化 key，正文进 `localization/ui.csv`（中英各配；注意 check_assets 的 GDScript 字面量扫描纪律——所有中文只进 csv）。
- `tools/validate_data.py`：校验每个事件类型 ≥3 个模板、所有 key 在 ui.csv 存在、占位符数量中英一致。

**代码改动**

- 新增 `ui/duty_log.gd`（静态工具类）：`static func compose(report: Dictionary, data: Dictionary, game_state: Dictionary) -> Array[Dictionary]`，输出 `[{text, icon_asset}]`。纯函数、不读写全局状态，方便单测。
- `ui/main_view.gd:_show_offline_dialog`（3934 行）：弹窗顶部插入日志区（每行 icon + 文本，最多 4 行，超长省略）。
- 离线大事记（报告 `events/faults/contracts/inquiries/aging/takeovers` 各数组）已含所需数据，**不改 `core/game.gd` 的报告结构**；若个别事件缺少展示字段（如机房名），在 compose 内查 `game_state` 补全，不反向污染报告。

**验收标准**

1. 单测：同一份报告两次 compose 输出逐字一致（内容哈希种子）；优先级排序正确；聚合行数量正确；compose 前后行情/故障/询价三条随机流状态逐位不变；空报告返回仅含兜底收入行。
2. `midgame_audit`：M9 离线弹窗深链断言不回退；新增断言——日志区显示的收入金额与权威结算相等（同源数字，禁止 UI 层重算）。
3. `visual_smoke` 新增双语状态 `duty_log_dialog`（含 4 行日志 + 账单 + 领取按钮同屏，验证排版与长文案换行）。
4. `full_campaign`：离线返回段断言日志区存在且行数 ∈ [1,4]。

### C2 · 客户拟人化（人设层）

**机制定义**

- 四类客户各 2–3 位署名角色，共 **10 位**（互联网 3 / 云厂商 3 / GPU 2 / 挖矿 2），每位含：名字、头像、台词库（询价到达 / 接单致谢 / 婉拒回应 / 关系升级 / 高关系闲谈各 ≥2 条）。
- **绑定规则（零随机流消耗）**：询价的人设 = `hash(inquiry_id + template_id)` 对该客户人设数取模——确定、可测、不动 20 号锁死的询价序列。同一机房的在约客户显示「当前对接人」= 最近一次签约询价的人设，非询价合约取该客户 0 号人设。
- 关系升级时刻：`_accrue_customer_relationships`（core/game.gd:974）检测等级跨越，新增 EventBus 信号 `relationship_level_changed(customer_id, level_index)`（event_bus.gd 追加）；在线时弹人设 toast（头像 + 台词 + 新等级名），离线时不弹、汇入 C1 日志。
- 人设是纯皮肤：**同一客户的所有人设共享关系值、条件判定、收益**，D51 红线。

**数据改动**

- 新增 `data/personas.json`：`{"schema_version":1,"items":{"persona_id":{"customer_id","name_key","asset_id","lines":{"inquiry":[...],"accept":[...],"decline":[...],"level_up":[...],"chat":[...]}}}}`；台词值为本地化 key。
- `validate_data.py`：每客户 ≥2 人设、每类台词 ≥2 条、asset_id 在 manifest 中存在、key 双语齐全。

**美术交付（沿用 19 号 §4 管线与风格约束）**

- 10 张 1024² 透明人设半身像：premium 2.5D casual mobile-game render、圆润蓝/奶油/金、上左暖光、单一主体、无文字水印、`#ff00ff` 色键。人物设定各具行业特征（矿场老板娘安全帽 + 金链、云厂商采购总监西装 + 平板、AI 创业青年连帽衫 + 眼圈等），英文 prompt 全文记录进 `art-renders/briefs/final_prompt_record.md`。
- 原稿 `art-renders/visual/work/personas/`，成品 `final/personas/`，运行时 `assets/art/personas/`，manifest 同步。

**UI / 文案**

- 询价卡：客户图标替换为人设头像 + 名字，条款下加一行该人设的询价台词。
- 合约面板（机房抽屉）：关系 ≥「熟悉」时显示对接人头像与名字；点头像弹一条 chat 台词（纯趣味，无功能）。
- 关系升级 toast：头像 + 「[名字] 现在把你当[等级名]了」+ 台词。
- 全部双语；中文人名注意字体子集覆盖（跑 `check_assets --strict`）。

**验收标准**

1. 单测：同一 inquiry_id 的人设绑定恒定；绑定计算不改变询价模板序列（同 seed 前后逐位对比）；关系跨级恰好触发一次信号、同帧多跨级只发最高级；台词 key 全部可解析。
2. `visual_smoke` 新增双语状态 `inquiry_persona_card`（含头像 + 台词的询价卡）与合约面板对接人入镜（并入现有 `contract_terms` 状态即可）。
3. `flow_audit` / `tutorial_playthrough` 不回退：FTUE 期间无人设元素（询价区本就不出现）。
4. 20 种子模拟输出与基线完全一致（本项零数值改动的硬证明）。

### C3 · 机房猫（园区生命层）

**机制定义**

- 首个非教学机房建成后，猫入驻园区（世界层常驻精灵，教程期与 FTUE 聚光灯期间隐藏）。状态机三态：**睡觉**（机房顶，权重最高）、**踱步**（沿现有装饰带/道路，避开 40u 车道——见 park_map.gd:717 的 prop 布线纪律）、**坐望**。状态切换用**临时 RNG（不入存档、不碰持久流）**。
- 点击互动：打滚/伸懒腰动画 + 轻触觉 + 偶尔一个爱心粒子。**无货币产出**。互动冷却内重复点击只播短动画。
- 「猫片」发现：特定情境首次互动解锁典藏（新组「园区生活」）：`cat_nap`（睡觉时）、`cat_parade`（踱步时）、`cat_watch`（坐望时）、`cat_festival`（任一稀有行情生效期间，猫戴墨镜变体）。各奖励一次性少量钻石（沿用典藏组一次性补领规则，D33）。
- 多园区时猫只在当前聚焦园区出现（省性能、也符合「一只猫」的人设）。

**数据改动**

- `data/meta_progression.json` `collection.groups` 新增 `campus_life`（`reward_gems: 5`，items 列出四张猫片，`name_key/asset_id` 齐全）。**只新增组，不改既有组**。
- 新增 `data/campus_cat.json`：状态权重、切换间隔、互动冷却、解锁条件（`standard_built == true` 或 `total_datacenters_built ≥ 2`，与教程互斥）。

**美术交付**

- 猫本体 4 姿态（睡/走两帧/坐/打滚）+ 墨镜变体 1 张 + 猫片插画 4 张，规格同上（透明、色键、英文 prompt 入档）。走 `import_assets.py` 管线，manifest 同步。

**代码改动**

- 新增 `gameplay/map/campus_cat.gd`（Node2D，挂在 `park_map` 世界层）：状态机、移动、点击热区（≥44pt 但**只覆盖猫本体**，`mouse_filter` 不得遮挡地块/建筑点击——15 号输入路由教训）；typed 严格模式（项目开启 untyped_declaration 警告）。
- `gameplay/map/park_map.gd`：挂载/卸载与园区切换联动；FTUE 期间 `visible = false`（读 tutorial 状态，同现有新闻条做法 main_view.gd:2045 一带）。
- 猫片发现走 `Game._collection_item_discovered("campus_life", item_id)`（core/game.gd:533）现有 API，不新加发现通路。

**验收标准**

1. 单测：解锁条件正反例；四张猫片各自的情境判定（含稀有事件期变体）；重复互动不重复发现；发现走既有典藏 API 且奖励一次性。
2. `performance_smoke`：百机房场景加猫后 p95 仍 < 16.67ms、节点/粒子零泄漏（猫的动画粒子遵守 13 号 FX 自毁纪律）。
3. `flow_audit` / `tutorial_playthrough`：教程全程猫不可见、不可点，聚光灯唯一可点目标断言不回退。
4. `visual_smoke` 新增双语状态 `campus_cat`（踱步态入镜 + 典藏页园区生活组含未发现问号占位）。
5. 输入回归（`midgame_audit` 扩一条）：猫与建筑重叠站位时，点建筑必须开抽屉而不是撸猫。

## 3. 实施顺序与批次

```
批次 1：§1 决策文档更新（新增「表现与叙事」小节 D50–D52）
批次 2：C1 值班日志          （独立，最先见效）
批次 3：C2 客户拟人化        （含 10 张人设美术）
批次 4：C3 机房猫            （含猫美术；C1 的猫日志行此时回填打开）
批次 5：全量回归 + 文档同步（01 号补「表现与叙事」节、README、本文验收记录）
```

每批次结束 `test_runner` 保持绿色，批次间独立提交。美术生成失败或风格不达标时，先用现有回退纪律占位（AssetCatalog 缺失回退），**不得阻塞逻辑合入**，但最终验收前必须补齐正式资产。

## 4. 明确不做（本批次范围外）

- 不做人设专属数值差异（专属折扣、专属条件）——那是 D51 红线的反面。
- 不做猫的养成/喂食/皮肤商店；不做第二只猫；不做任何以互动频率为条件的奖励（变相日常任务）。
- 不做日志的历史存档页（只展示本次离线；历史属于 19 号纪念册的职责边界）。
- 不改离线收益上限、结算公式、领取与广告位逻辑。
- 00_decisions「明确不做」清单全部维持；无倒计时、无日常任务红线继续适用。

## 5. 给执行者的注意事项

1. **随机流纪律是本批次的第一验收项**：三个工作项全部只允许临时 RNG（内容哈希种子或不入存档的本地 RNG）。每项都要有「同 seed 持久流前后逐位一致」的断言，做法沿用 20 号 B1 的基线对比测试。
2. **数值零改动的硬证明**：批次 5 重跑 `python3 tools/simulate_economy.py --seed-count 20`，全部 PASS 行与当前基线完全一致（包括 19.3 天中位与 23.67× 净值比的具体数字）。任何数字漂移都说明改了不该改的东西。
3. 所有中文文案只进 `localization/ui.csv`（check_assets 会扫 .gd 字面量）；人名、台词跑双语 `visual_smoke` 与字体子集门禁，台词避开生僻字。
4. 猫的点击热区与世界输入路由是 15 号踩过的坑：用 `push_input` 路径实测（`tutorial_playthrough` 的触摸注入手法），不要只靠单元层断言。
5. 值班日志的金额展示复用 `Game.format_number` 与权威结算同一份数据，禁止在 compose 里重新求和——13/15 号「显示与权威不同源」教训的适用场景。
6. 人设台词写作基调：具体、克制、有行业味，不玩梗过度；每条 ≤30 汉字避免换行灾难。英文台词独立写作（不逐字直译），长度同约束。

## 6. 验收记录（2026-08-15）

### 批次与提交边界

- [x] 批次 1：`9fef299 docs: lock warmth and narrative decisions`，D50–D52 已进入 00 号「表现与叙事」小节。
- [x] 批次 2：`9a623b2 feat: add deterministic offline duty logs`。
- [x] 批次 3：`da5b666 feat: personify customer relationships`。
- [x] 批次 4：`1a02cf9 feat: bring a cat to the campus`。
- [x] 批次 5：全量回归、字体与资源合同同步、01/README/本文验收记录保持为独立最终提交。

### C1 · 值班日志

- [x] `data/duty_log.json` 为每类事件提供至少 3 条双语模板；`DutyLog.compose` 只读离线报告与存档展示字段，按优先级聚合为 2–4 行，收入兜底直接使用报告的权威金额，没有在 UI 重新求和。
- [x] 单测证明相同报告逐字一致、优先级与收入保底正确；compose 前后行情、询价与故障持久随机状态逐位不变。
- [x] `midgame_audit` 断言日志收入与同一份离线报告一致；`full_campaign` 的真实离线回归继续完成领取、深链与转生长线流程。

### C2 · 客户拟人化

- [x] `data/personas.json` 落地互联网 3、云厂商 3、GPU 2、挖矿 2 共 10 位角色；每位五类语境各至少 2 条中英独立台词，角色不含任何专属经济字段。
- [x] 询价人设由 `hash(inquiry_id + template_id)` 稳定绑定且零持久随机流消耗；合约对接人与关系升级复用同一客户关系，跨多级时只发一次最高等级信号。
- [x] 10 张 1024² 正式透明半身像已按 19 号美术管线进入 work/final/runtime，询价卡、合约面板与关系升级反馈均使用正式资产；FTUE 审计全程不出现人设元素。

### C3 · 机房猫

- [x] 当前园区只挂载一只猫，睡觉/踱步/坐望状态和稀有行情墨镜变体均由临时随机源驱动；教程期隐藏且不可点，互动不产生现金或可重复钻石。
- [x] 四种情境分别发现 `cat_nap`、`cat_parade`、`cat_watch`、`cat_festival`；重复互动不重复发现，既有典藏 API 只在整组首次完成时发放一次 5 钻石。
- [x] 猫本体 6 态、4 张猫片与爱心特效共 11 张正式透明素材已接入；点击热区只覆盖本体，`midgame_audit` 以真实 `push_input` 证明猫与建筑重叠时点击仍打开建筑抽屉。

### 零漂移与全量门禁

- [x] `python3 tools/simulate_economy.py --seed-count 20` 输出与批次前基线逐字节一致；两份文件 SHA-256 均为 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`，活跃 20 座中位仍为 19.3 天，活跃/挂机 30 日净值比仍为 23.67×。
- [x] `test_runner` 224/224；`flow_audit`、`midgame_audit`、真实触摸 `tutorial_playthrough` 与 `full_campaign` 全绿。长战役在同一局跑通询价、5 槽成组、稀有行情战略封顶、3 路工程队、离线回归与上市重组，最终第 113 月、24 座、时代 3、净值 $1.02M。
- [x] `visual_smoke` 中文/英文各 47 个 iPhone 17 竖屏状态通过，含 `duty_log_dialog`、`inquiry_persona_card`、`campus_cat` 三个新增状态，输出 990×2151。
- [x] `performance_smoke` 百机房 + 单猫 + 30 金币粒子：平均 6.46ms、p90 8.34ms、p95 9.51ms；猫爱心特效 1→0、剩余粒子 0、节点差 0。
- [x] `validate_data` 通过 16 张数据表、本地化与 180 个美术 ID；`check_assets --strict --audio` 通过 180/180 美术、6/6 字体、23/23 音频。新增人名用字已从审计过 SHA-256 的 Resource Han Rounded v1.910 母版重新子集化。
- [x] 正式资源管线 `import_assets.py --visual --audio` 完整复制 203 项且无缺失；本批次没有使用几何占位或缺失回退交付。
- [ ] `check_app_store_assets` / `check_release` 仍被仓库既有外部发布资料阻塞：中英 iPhone/iPad 商店截图、隐私/支持页正式链接和 iOS IAP 插件描述符尚未交付。它们不影响本批次运行时、模拟器与 TestFlight 工程逻辑，继续归入 README 的外部交付清单，不伪报为通过。
