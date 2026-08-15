# 20 · 中期可玩性与经济闭环收口（Codex 执行文档）

> 生成于 2026-08-14。方向已由项目所有者确认，作为本批次改造的**唯一执行依据**。
> 执行者先读 [00_decisions.md](00_decisions.md)、[18_cozy_rework_spec.md](18_cozy_rework_spec.md)、[19_meta_progression_rework.md](19_meta_progression_rework.md)；本文引用的代码位置已与 2026-08-14 工作区（build 4 准备态，含 19 号改动）逐一核对。**执行前先确认 19 号改动已提交**，避免基线漂移。

## 0. 背景：要解决的四个问题

18 号（轻松化）与 19 号（公司成长闭环）之后，系统层是完整的。17 号全程模拟 + 30 天 20 种子数值复盘定位出四个残留问题：

| # | 问题 | 证据 |
|---|---|---|
| P1 | **中期决策密度低**：时代 2 → 转生约 90 游戏月，玩家每月只有「修-填-续」三件事，没有新决定 | 17 号 §2 逐月推演 |
| P2 | **3×3 棋盘无布局决策**：冷却盖哪行就往哪行塞最好的柜子，一眼最优解，D01 承诺的「轻布局」没有兑现 | 棋盘规则走读 |
| P3 | **后期现金无去处**：地价改幂函数后只占收入 ~1.5%，网络拉满、地全买后现金只能堆着等转生；转生公式是对数的，财富翻倍只多 +0.045 倍率 | 全程模拟结束闲置 $6.3M；活跃型 30 日净值 $17.3M |
| P4 | **跨局节奏不增长**：转生 100% 带走净值（D19，不动），第二局开局即可重建帝国，但 20 座 T3 过 2 条建设队列仍是 ~5 个现实天——钱在跨局复利，时间不复利 | `base_queue_capacity: 2`，dc_t3 build 43200s |

另有一个**待归因数值信号**：19 号复跑后活跃型净值 $1.03M → $17.27M（17 倍），而新乘数明面只有 +10~15%。最可能来源是「免费改签 + 签约锁价」的完美复利（每次续约精准锁进最优事件倍率）。方向正确（活跃应当赢），量级需归因，且本批次要加稀有大事件，必须先立锁价封顶规则。

优化思路一句话：**给中期加「拉动式目标」（询价单），给棋盘加一条真决策（成组），给锁价决策加长尾（稀有行情，带封顶），给后期现金和跨局节奏一个共同出口（工程部扩编）**。四项互相咬合，全部不碰「明确不做」清单。

## 1. 决策变更（先做：更新 00_decisions.md）

| 条目 | 变更 |
|---|---|
| D35（新增） | **询价单**：具体客户带条件来单，接单即按现有合约系统签约并附加溢价与签约金。询价**永不过期**、不设现实倒计时，只在被接受或婉拒后补位（「限时决策窗口不做」红线的正面表述） |
| D36（新增） | **成组加成**：机房棋盘整行/整列同类型机柜构成「成组」，成员机柜收入 +10%；一台机柜最多享受一次成组加成，不叠加 |
| D37（新增） | **稀有行情与锁价封顶**：低权重稀有事件入池；战略约（12 月）签约/续约锁价时事件部分封顶（首版总倍率上限 2.5），灵活/标准约不封顶。稀有事件点亮典藏 |
| D38（新增） | **工程部扩编**：建设队列容量作为科技逐级购买（2→3→4→5）；与网络/维修队一致，**转生后重置、每局重购**——跨局带走的财富由此转化为下一局的速度 |

## 2. 工作项

### B1 · 询价单（最高优先级，对应 P1）

**机制定义**

- 行情页新增「询价」区，最多 **3 张**未处理询价并列。每张询价 = 一位具体客户 + 一组条件 + 一组条款。
- 生成：`tutorial.completed == true` 且 `total_datacenters_built ≥ 2` 后启用。空位存在且 `now ≥ next_arrival_at` 时补一张：从模板池按（时代、网络等级、关系等级）过滤后加权抽取；抽取用**独立随机流**（同故障流的做法，不得扰动行情序列）。`next_arrival_at = now + (6 ± 2) 游戏月`。
- **没有倒计时**。询价一直等玩家；婉拒后该槽位 2 游戏月冷却再补新。离线期间正常到达并填满空位（到达是馈赠，符合 D23）。
- 接单：玩家选择一座满足条件的运营中机房 → 走 `sign_contract` 现有路径签约，附加：
  - `locked_market_multiplier = contract_market_multiplier(customer) × premium`（premium 由模板定义，范围 ×1.15–×1.35；若期限为战略约，仍受 B3 封顶约束）；
  - 签约金 = 该机房**签后预估月收入 × bonus_months**（模板定义 0.5–1.5；用 `contract_forecast` 的 projected 值，自适应时代无需调参表）；
  - 关系加成：额外累计 `bonus_service_seconds`（模板定义，如 21600 = 3 游戏月的关系进度）。
- 提前毁约走现有 25% 毁约费，无额外惩罚。
- 首版模板 **8 条**，覆盖四类客户与三档条件强度，示例（执行者按此风格补全，数值进 `data/inquiries.json`）：
  - `gpu_surge`（gpu_company，era≥2）：条件 `{"rack_kind":"gpu","rack_count":4}`，战略约，premium 1.30，bonus_months 1.0；
  - `cloud_frame`（cloud，era≥2）：条件 `{"unique_rack_kinds":3}`，标准约，premium 1.20，bonus_months 0.8；
  - `mining_rush`（mining）：条件 `{"rack_kind":"gpu","rack_count":2}`，灵活约，premium 1.35，bonus_months 0.5；
  - `internet_anchor`（internet）：条件 `{"relationship_level":2}`，战略约，premium 1.15，bonus_months 1.2。

**数据改动**

- 新增 `data/inquiries.json`：`{"schema_version":1,"settings":{"max_open":3,"arrival_months_min":4,"arrival_months_max":8,"decline_cooldown_months":2,"min_datacenters_built":2},"templates":{...}}`；模板字段 `customer_id / requirements / duration_id / premium / bonus_months / bonus_service_seconds / weight / unlock_era / minimum_network_level / name_key / description_key`。
- `data/meta_progression.json` roadmap 增加一项 `first_inquiry`（metric `inquiries_accepted`，target 1，reward_gems 5）。

**代码改动**

- 新增 `gameplay/inquiry_system.gd`（仿 `market_system.gd` 的挂载方式）：`ensure_state` / `process(now)` / `roll_inquiry` / `evaluate_requirements(dc)` / `accept` / `decline`。条件求值**复用** `game_rules.gd` 园区定位已有的 `rack_kind+rack_count / unique_rack_kinds` 求值逻辑（19 号引入），新增 `network_level / relationship_level / specialization` 三种判定。
- `core/game.gd`：状态新增 `state["inquiries"] = {"open": [], "next_arrival_at": 0.0, "cooldowns": {}}`（`_ensure_state_shape` 补齐旧档）；`_process_due` 挂 `inquiry.process`；公开 `accept_inquiry(inquiry_id, datacenter_id)` / `decline_inquiry(inquiry_id)`；`stats` 增加 `inquiries_accepted`。
- **`_next_boundary_after`（离线分段结算）必须纳入 `next_arrival_at`**——18 号 §5.2 的教训，新增计时 key 不同步会静默错帐。
- `tools/validate_data.py`：校验模板字段完整、premium ∈ [1.0, 1.5]、duration_id 存在、customer 存在。
- `tools/simulate_economy.py`：活跃型在决策点评估询价（条件已满足或 ≤1 次机柜调整可满足即接）；挂机型只接「当前已满足条件」的询价。

**UI / 文案**

- 行情页询价卡：客户图标 + 条件清单（对玩家最优可选机房实时 ✓/✗）+ 条款（溢价、期限、签约金预估）+「接单」（弹机房选择，不满足条件的机房置灰并写明缺什么）/「婉拒」。
- 14 号待办中心增加「新询价」行，深链行情页。
- 全部新 key 中英双语，走 `localization/` 现有流程。

**验收标准**

1. 单测（`tests/test_runner.gd` 新增一组）：
   - 同 seed 生成序列确定；行情事件序列与 18 号基线**逐位一致**（独立随机流证明）；
   - 条件求值五种判定各覆盖正反例；
   - 接单后 `locked_market_multiplier` 等于无噪声行情 × premium；签约金入账等于 forecast × bonus_months（±1 取整）；关系秒数增加 bonus 值；
   - 婉拒后槽位冷却 2 游戏月内不补，冷却后补位；
   - **推进 400 游戏月，未处理询价仍在**（永不过期）；
   - 离线 `advance_time(offline=true)` 跨过到达点：询价出现且进离线大事记。
2. `full_campaign`：模拟玩家全程至少接 1 单，接单后该机房收入含溢价（与权威公式一致断言）。
3. 模拟器（20 种子）：活跃型 30 日接单 ≥ 3；**询价合约收入占活跃型总收入 ≤ 35%**（调味不喧宾，超限收紧 premium/到达频率）；挂机型不因忽略询价出现负增长月份。
4. `visual_smoke` 新增双语状态：`inquiry_board`（3 张并列含一张条件未满足）、`inquiry_accept_sheet`。
5. `flow_audit` / `tutorial_playthrough` 不变绿变红：FTUE 期间询价区不出现。

### B2 · 成组加成（对应 P2）

**机制定义**

- 棋盘行 `[0,1,2] [3,4,5] [6,7,8]`、列 `[0,3,6] [1,4,7] [2,5,8]`。一条线上 3 台**同 kind、已通电、非 installing** 的机柜构成「成组」，成员收入 ×1.10。
- 一台机柜最多享受一次加成（同时处于成组行和成组列也只乘一次）。
- `faulted` 机柜**保留成组成员资格**（轻松向：故障不连坐邻居），其自身收入照常乘故障 0.4 再乘成组 1.10。
- 断电、停用、installing 破坏成组。dc_t0（槽位 0/1/3/4）与 dc_t1（0–5，仅行可成组）天然限制成组从 T1 的「行」开始出现，不影响教程。

**数据改动**

- `data/economy.json` 新增节 `"layout": {"set_bonus_multiplier": 1.10, "set_size": 3}`；`validate_data.py` 锁定 multiplier ∈ [1.0, 1.25]。

**代码改动**

- `gameplay/game_rules.gd:datacenter_income_per_month`（168 行）：主循环前基于 `powered_slots` 与机柜 kind 预计算 `set_member: Array[bool]`，循环内对成员乘 `set_bonus_multiplier`。抽出 `static func set_bonus_slots(datacenter, racks_table, attachments_table) -> Array[bool]` 供 UI 复用，保证**棋盘显示与权威收入同源**。
- `contract_forecast` 无需改动（走同一权威函数）。

**UI / 文案**

- `ui/datacenter_board.gd`：成组线绘制连接光效 + 线端「+10%」徽标；机柜安装预判（现有 ✓/⚠/⚡ 分级）增加「将成组」提示档。
- 机房抽屉收入行 tooltip 列出成组贡献。双语 key。

**验收标准**

1. 单测：整行成组 +10%；整列成组 +10%；行列交叉不叠加（收入恰为 ×1.10 单次）；拔掉一台后组内其余立即失去加成；installing/断电/停用破坏组、faulted 不破坏组；`set_bonus_slots` 与收入函数对同一状态返回一致成员集。
2. 模拟器：参考配置更新为按行同类混排（每座 ≥2 kind 约束保留）；重跑后「不出现单一机柜最优解」探针仍通过；云厂商多样性 ×1.15 与成组可同时取得（3 行 3 kind 配置探针）。
3. `visual_smoke` 新增双语状态：`dc_board_set_bonus`（一行成组发光 + 预判提示可见）。
4. `midgame_audit`：棋盘断言扩展——成组光效存在时，抽屉月收入数字与权威公式相等。

### B3 · 稀有行情 + 战略约锁价封顶（对应 P1 长尾与 17× 信号的护栏）

**机制定义**

- `data/events.json` 新增 3 条稀有事件（`weight: 1`，现有池总权重约 ~120，即单次抽取 ~1% 级）：
  - `sovereign_ai`：gpu_company ×5.0，1 游戏月，`minimum_era: 3`；
  - `compute_famine`：`all_customer_multiplier: 1.8`，2 游戏月，`minimum_era: 2`；
  - `compliance_archive`：storage 相关客户 ×3.0（internet/cloud 的存储适配放大由机柜 sensitivity 自然衰减），3 游戏月，`minimum_era: 2`。
  - 三条均加 `"rare": true`。
- **锁价封顶**：签约或自动续约为**战略约（12 月）**时，`locked_market_multiplier = min(rate, strategic_lock_cap)`，首版 `strategic_lock_cap: 2.5`（进 `data/economy.json` `contracts` 节）。灵活/标准约不封顶——想吃满 ×5 就得接受 1–6 月后按新行情重锁。询价单（B1）走 `sign_contract`，自动继承此规则。
- 稀有事件开始：专属横幅样式（现有 `MarketEventBanner` 加稀有配色）、典藏 `market_history` 组正常点亮（events source 已覆盖，无需新钩子）、行情页事件卡加「稀有」角标。

**数据改动**

- 如上。`validate_data.py`：`rare` 事件 weight ≤ 2；`strategic_lock_cap ≥ 1.5`；事件倍率 ≤ 6。

**代码改动**

- `core/game.gd:sign_contract`（282 行）与 `_process_contract_renewals`（1050 行）：锁价赋值处按 `contract_duration_id == "strategic"` 施加 clamp（两处共用一个私有函数 `_locked_rate_for(customer_id, duration_id)`）。
- `ui/main_view.gd` 合约面板：战略约在封顶生效时显示「锁价上限 ×2.5」说明，避免玩家以为亏了。

**验收标准**

1. 单测：注入 ×5.0 事件——灵活/标准约锁 5.0（×sensitivity 后生效），战略约锁 2.5；自动续约同规则；已存在的战略约旧档载入不追溯改锁价。
2. 模拟器：稀有事件 20 种子出现频率与权重份额一致（±50% 容差）；启用稀有事件后**活跃/挂机 30 日净值比不高于现基线 25×**，第 7 天收入比仍在 40–60%；挂机型仍 0 接管。
3. `visual_smoke`：`rare_event_banner` 双语状态（稀有横幅 + 行情页稀有卡同屏）。
4. 典藏页三条稀有事件未遇见时以问号形式占位（现有 collection 未发现态样式复用）。

### B4 · 工程部扩编（对应 P3 + P4）

**机制定义**

- 新科技「工程部扩编」：建设队列容量 2 → 3 → 4 → 5，逐级购买，无建设周期：
  | 级 | 容量 | 价格 | 门槛 |
  |---|---|---|---|
  | 2 | 3 | $250,000 | 时代 2 |
  | 3 | 4 | $1,500,000 | 时代 3 |
  | 4 | 5 | $10,000,000 | 转生 ≥ 1 |
- 与网络/维修队一致：**转生后重置**。设计意图：跨局带走的现金在新局开场买回扩编 = 财富转化为速度，第二局真的更快（P4 收口）；后期盈余有持续去处（P3 收口）。
- 钻石加速与广告加速不变——扩编加车道，钻石加速单个工程，互补。

**数据改动**

- `data/technology.json` `upgrades` 新增 `construction_bays`：结构仿 `repair_team`，levels `"2"/"3"/"4"` 含 `cost / queue_capacity / unlock_era`，级 4 用 `minimum_prestige: 1`。
- `validate_data.py`：容量单调递增、价格单调递增、字段齐全。

**代码改动**

- `core/game.gd:_queue_has_capacity`（1330 行）：容量 = `max(base_queue_capacity, 已购级的 queue_capacity)`。
- 新增 `purchase_construction_bays()`（仿 `upgrade_repair_team`）；`is_unlocked` 扩展支持 `minimum_prestige`（读 `stats.prestige_count`），其余调用方语义不变。
- `tools/simulate_economy.py`：活跃型现金充裕（> 价格 × 2 且队列满载）时购买扩编。

**UI / 文案**

- 科技页新增条目（仿维修队行）；HUD 队列徽标与建设抽屉显示 `n/容量`；队列满时的失败 toast 文案提示可扩编。双语。

**验收标准**

1. 单测：级 2 后同时 3 项工程可入队、第 4 项拒绝；时代/转生门槛各自拦截；转生后容量回 2 且可重购；`minimum_prestige` 不影响现有条目解锁判断。
2. 模拟器：**活跃型 20 座中位时间保持在第 14–21 天窗口内**（若跌破 14，按「级 2 价格上调」为第一旋钮重调，不改队列容量本身）；购买扩编的种子在购买后 5 日内建成速率提升可测。
3. `full_campaign`：模拟玩家在时代 2 现金充足时购买扩编，断言队列并发 3 生效；转生后断言容量重置。
4. `visual_smoke`：科技页含扩编条目的双语状态（并入现有 tech 页状态即可，不必新增独立状态）。

### B5 · 数值探针与全量回归（最后做，铁律）

1. **17× 归因探针**（写进 `simulate_economy.py`，结论回写 `balance_report.md`）：
   - 对照组 A：活跃型正常（免费改签锁最优）；对照组 B：活跃型改签只锁时代基线（禁用事件择时）。同 20 种子对比 30 日净值，报告「事件择时复利」贡献占比；
   - 叠加 B3 封顶后的组 A′，报告封顶对该占比的压缩量。**本探针只产报告，不自动改数值**——结论给所有者拍板。
2. **T2 维护费试调**：$1,150 → 在 [900, 1150] 扫描，约束：挂机 0 接管、0 欠费月不变；激进接管率 30–60% 不变；目标：活跃型时代 2 段（第 7–17 天）净值斜率改善 ≥ 5%。达不到就维持 $1,150，写明结论。
3. **全量门禁**：README「开发与验收」全部命令 + 本文新增用例；`test_runner` 预计 162 → 190+；`visual_smoke` 双语各 41 → 45 态左右；`flow_audit` / `midgame_audit` / `tutorial_playthrough` / `full_campaign` / `performance_smoke` 全绿。
4. **文档同步**：`00_decisions.md`（§1 表）、`01_game_design.md`（§6 行情与询价、§4 棋盘成组、§7/§13）、`02_economy.md`（新数值表：询价、成组、封顶、扩编）、README 当前状态。文档与 `data/*.json` 数值必须一致。
5. 曲线与 CSV 存 `docs/balance_runs/`；本文档末尾补「验收记录」段，逐项附证据（沿用 08–15 号格式）。

## 3. 实施顺序与批次

```
批次 1：§1 决策文档更新
批次 2：B3 稀有行情 + 锁价封顶      （最小、且是 B1 的前置护栏）
批次 3：B2 成组加成                 （独立，权威公式一处改动）
批次 4：B1 询价单                   （最大项；依赖 B3 的封顶规则已就位）
批次 5：B4 工程部扩编               （独立）
批次 6：B5 探针 + 全量回归 + 文档同步
```

每批次内：先 `data/*.json` 与规则层，再同步 `simulate_economy.py` / `validate_data.py`，再补测试，最后 UI 与本地化。每批次结束 `test_runner` 保持绿色，批次间独立提交。

## 4. 明确不做（本批次范围外）

- 询价单**不做**现实时间倒计时、不做拒单惩罚、不做每日刷新（红线：限时决策窗口）。
- 不做批量建设/配置蓝图（D34 维持暂缓）；扩编只加队列容量，不加「一键建造」。
- 不动转生 100% 净值携带（D19）、时间换算（D21）、老化曲线、地价公式（19 号已定）。
- 不恢复实时行情结算；不给稀有事件做保底/必出机制。
- 00_decisions「明确不做」清单全部维持。

## 5. 给执行者的注意事项

1. **随机流纪律**：询价抽取、稀有事件都走既有加权池或独立流；改动后必须用「同 seed 行情序列与基线逐位一致」的断言证明没有扰动老玩家的行情重放。
2. **`_next_boundary_after` 是离线结算的心脏**：B1 的 `next_arrival_at` 必须纳入分段边界，并为「离线跨过到达点」单独写用例（18 号 §5.2 教训）。
3. 成组加成只在 `datacenter_income_per_month` 一处生效，UI 一律通过 `set_bonus_slots` 读同源结果——禁止在 UI 层重算一份逻辑（15 号「假完成」教训：显示与权威不同源迟早穿帮）。
4. 所有新增文案中英齐全，跑双语 `visual_smoke` 确认排版；询价卡与稀有横幅注意中文长词换行。
5. 询价金额展示用 `Game.format_number`；签约金基于 forecast，UI 展示值与入账值必须同一次计算（防止行情 tick 造成显示/入账不一致）。
6. `full_campaign` 是本批次的总闸：改完后模拟玩家应当自然地接单、成组、买扩编、撞见（注入的）稀有事件并被封顶——四个特性都要在一局跑通的语境下被断言，而不是只有孤立单测。

## 6. 验收记录（2026-08-15）

### 批次与提交边界

- [x] 19 号既有工作区先作为 `5c9b414 feat: polish progression, interaction feedback, and iOS branding` 完整提交，随后 `test_runner` 绿色。
- [x] 批次 1：`c66d6e3 docs: lock midgame economy decisions`，D35–D38 已进入 00 号决策表。
- [x] 批次 2：`dc1d54f feat: add rare market events and strategic lock cap`。
- [x] 批次 3：`6ada1df feat: add authoritative rack set bonuses`。
- [x] 批次 4：`17c91e8 feat: add persistent client inquiries`。
- [x] 批次 5：`e694bf9 feat: add construction queue expansion`。
- [x] 批次 6：B5 探针、同局总闸、文档同步和完整回归保持为独立最终提交。

### B1 · 询价单

- [x] 8 个模板、最多 3 张、4–8 游戏月到达、2 月婉拒冷却均由 `data/inquiries.json` 驱动；无过期字段、无每日刷新和现实倒计时。
- [x] 行情、故障、询价三条随机流隔离；单测逐位比较同 seed 行情序列，确认询价没有扰动行情重放。
- [x] 五类条件各有正反例；接单的锁价、forecast 签约金、关系秒数和战略封顶均按权威路径断言。
- [x] 400 游戏月永久保留、离线跨 `next_arrival_at` 分段到达、婉拒冷却补位均通过。
- [x] 双语 `inquiry_board` / `inquiry_accept_sheet` 视觉态通过；FTUE 期间不会提前出现。
- [x] 20 种子活跃型每局 56–63 单；询价可归因收入 0.4%（目标 ≤35%）；挂机忽略询价时累计收入保持单调。

### B2 · 成组加成

- [x] 行、列、交叉不叠加、拔柜、安装中、停机、断电与 faulted 资格全部由单测覆盖；权威收入只在 `datacenter_income_per_month` 一处乘 ×1.10。
- [x] UI 直接读取 `set_bonus_slots`；`midgame_audit` 同时断言光效、徽标与抽屉收入和权威结果一致。
- [x] 模拟器参考配置保持每座至少 2 kind，并验证三行三 kind 的云厂商配置可同时取得 ×1.15 多样性与 ×1.10 成组。
- [x] 双语 `dc_board_set_bonus` 视觉态通过。

### B3 · 稀有行情与战略锁价封顶

- [x] 三条稀有事件均为 `weight: 1`；20,000 次确定性抽取观测 3.14%，作者权重份额 3.26%，位于 ±50% 容差。
- [x] 注入 ×5 行情后，灵活/标准约完整锁价，战略签约与续约均封顶 ×2.5；旧存档锁价不追溯裁切。
- [x] 稀有横幅、行情卡和典藏未发现态通过双语视觉回归。
- [ ] **总量硬闸未通过**：正式 20 种子活跃/挂机 30 日净值比 210.79×（目标 ≤25×）。A/B/A′ 证据见 [depth_attribution.csv](balance_runs/depth_attribution.csv)：事件择时复利贡献 99.8%；正式 ×2.5 战略封顶使 A→A′ 绝对净值下降 29.9%，但该贡献占比仍为 99.8%（只压缩 0.1%）。按 B5“探针只产报告、不自动改值”约束，本批次没有私自改变已定锁价边界，等待所有者拍板。
- [x] 第 7 天挂机/活跃收入比 43%（目标 40–60%）；挂机 0 接管、0 欠费月。

### B4 · 工程部扩编

- [x] 2→3→4→5 容量、时代 2/3 与转生门槛、逐级价格、转生重置及重购均有单测；`minimum_prestige` 不影响旧科技。
- [x] 20/20 活跃种子购买扩编，所有队列从未越过权威容量；购买点前后 5 日启动数 597→600，吞吐改善可测。
- [x] 科技页、HUD `n/容量`、队列页和满队列提示双语 45 态通过。
- [ ] **20 座节奏硬闸未通过**：中位第 11.0 天（目标 14–21 天）。首笔扩编发生在第 16.8 天、累计第 54 次建设，已经晚于 20 座，因此规格建议的“上调级 2 价格”无法影响该硬闸；根因仍是前置行情复利，不做无效调参。

### B5 · 探针、总闸与文档

- [x] A/B/A′ 20 种子归因数据已写入 [depth_attribution.csv](balance_runs/depth_attribution.csv)，结论同步 [balance_report.md](balance_report.md)。
- [x] T2 $900–$1,150 六档旧基线结果已归档为 [t2_maintenance_sweep_pre_b7.csv](balance_runs/archive/t2_maintenance_sweep_pre_b7.csv)。它基于 B7 前的瞬时锁价规则，现仅作历史归因且不再支持 $1,100 候选结论；正式值始终为 $1,150。
- [x] `full_campaign` 在同一新档中于第 3 月自然接单，第 111 月形成 5 槽成组；随后在同局注入稀有行情，断言标准约高于封顶且战略约恰为 ×2.5；同局购买工程部并真实并发 3 项，上市重组后容量回 2。最终 24 座、时代 3、净值 $9.06M，整局通过。
- [x] `test_runner` 200/200；`flow_audit`、修正为包含询价的 `midgame_audit`、`tutorial_playthrough`、`full_campaign`、`performance_smoke` 全绿。百机房性能平均 6.32 ms、p95 6.67 ms、粒子残留 0。
- [x] 英文/中文 `visual_smoke` 各 45/45，画幅 990×2151；`validate_data` 通过 13 张数据表、159 个美术 ID 与本地化校验。
- [x] 01 号文档补成组/询价/稀有封顶/扩编闭环；02 号补 19 事件、收入公式与全部数值表；README 更新当前能力与门禁数量。
- [x] 资源合同额外复核：159/159 美术、23/23 音频、6/6 字体通过。App Store 双语 iPhone/iPad 商店截图仍是 README 已列的外部交付项，不属于本批次运行时门禁。

## 7. 增补批次 B7（2026-08-15 所有者拍板）：期限折算锁价与节奏回调

> 背景：§6 两个未过硬闸的根因由归因探针钉死——活跃型净值的 99.8% 来自「免费改签时把瞬时行情锁进整个合同期」的复利（A 组 $3.76 亿 vs B 组 $63 万），战略封顶只压 0.07 个百分点。20 种子原型实验（期限折算规则）：净值比 228× → 5.7×、第 7 天收入比 56%、20 座中位 11.0 → 23.5 天、激进接管率 55% → 0%。所有者已拍板采纳折算规则；本节是执行规格。

### B7.1 · 期限折算锁价（结构修复）

**机制定义**

- 锁价不再取签约瞬间的行情，而是**合同期内已知行情的时间加权平均**（仍不含每日噪声）：

  ```
  locked = (1/T) × ∫₀ᵀ rate(t₀+τ) dτ
  rate(t) = 当前时代基线 × Π(在 t 时刻仍生效的事件倍率)
  ```

  其中 T = 合同期秒数；「仍生效」按 `market.active[].end_at` 判定；**只计已生效事件，不计 previews**（规则对玩家表述为「按已生效事件折算」，预告事件留给玩家做签约时机决策）；时代基线取签约时刻值、整个积分期恒定（时代变更只影响新锁）。
- 实现为分段常函数的精确积分：切点 = 各生效事件 `end_at` 落在 `(t₀, t₀+T)` 内的时刻，逐段求积后加权平均。不允许采样近似。
- 溢价与封顶的次序不变：`locked = clamp_strategic(prorated × premium)`——先折算、再乘询价溢价、战略约最后过 ×2.5 封顶。
- 直接后果（这是设计目的，写进 01 号文档）：1 月期 ×5 稀有事件，灵活约（3 月）折算 ≈ ×2.3，标准约（6 月）≈ ×1.67，战略约摊薄到几乎无感——**吃爆发签短约，求安稳签长约**，三档期限从「数值差异」变成「真决策」。
- 已生效合约**不追溯**：旧档载入、以及本批次上线时既有的锁价一律保持原值，到期续约才按新规则重锁（与 B3 旧档处理一致）。

**决策文档**

- 改写 `00_decisions.md` D22 为：「合约签约锁价：锁定值为**合同期内已知行情的时间加权平均**（不含噪声、只计已生效事件）；实时行情只影响新签与改签。战略约锁价保留 ×2.5 封顶作为双保险」。D37 注解同步。

**代码改动**

- `gameplay/market_system.gd`：新增 `func locked_customer_multiplier(customer_id, game_state, data, term_seconds: float) -> float`（分段积分，复用 `customer_multiplier` 的事件乘法逻辑；`include_noise` 永远为 false）。
- `core/game.gd:_locked_rate_for`（140 行附近）：改为调用上述函数，`term_seconds = _contract_duration_seconds(duration_id)`。**此函数是签约 / 自动续约 / forecast / 询价报价四条路径的唯一汇合点**，除它之外不得出现第二处锁价计算。
- `contract_market_multiplier`（瞬时无噪声值）保留，仅用于行情页「当前价」展示与决策复盘对照。
- `tools/simulate_economy.py`：`locked_rate` 的正式模式改为折算公式（与运行时逐段一致）；保留 `era_baseline` 与旧瞬时模式作为归因探针的对照组。

**UI / 文案**

- 合约确认单与机房合约面板：锁价徽标数值即折算值；当折算期内有事件时补一行说明（如「按事件剩余 2 个月折算」），双语 key。行情页「签约参谋」副标题同步改为折算表述。
- 决策复盘（19 号）记录的锁价即折算值，对照逻辑不变。

**验收标准**

1. 单测：注入剩余 1 月的 ×5 事件——灵活/标准/战略三档锁价分别等于手算分段积分值（战略再过封顶）；两个事件交叠时切点正确；无事件时折算 = 时代基线；premium→封顶次序正确；自动续约按续约时刻重折算；旧档锁价载入不变；同 seed 行情事件序列与本批次前逐位一致（锁价改动不得触碰事件随机流）。
2. `full_campaign`：注入事件后在同局分别签灵活与标准约，断言灵活锁价 > 标准锁价（期限决策被真实兑现）。
3. 模拟器 20 种子（正式配置）：活跃/挂机 30 日净值比 ≤ 25×；第 7 天收入比 40–60%；挂机 0 接管、0 欠费月；全员 30 天末净值为正、无死档；稀有事件频率探针不变；询价收入占比 ≤ 35%。

### B7.2 · 节奏回调（把 20 座中位拉回 14–21 天）

原型实验里 23.5 天的部分原因是参考策略保守（全程 6 月标准约）。按以下顺序处理，**每动一步重跑 20 种子，达标即停**：

1. **先改参考策略再动数值**：活跃型在「生效事件对目标客户倍率 ≥ 1.5」期间改签灵活约、事件平淡期回标准/战略约——这是折算规则下的意图玩法，参考策略必须先代表它（预期此步已能显著回拉）；
2. 扩编级 2 价格 $250,000 → $180,000（让吞吐提速在首局第 15 天前后可达）；
3. 询价模板 premium 整体 +0.05；
4. T2 维护费（已验证对 20 座中位无效，仅当斜率类指标需要时才动，且维持 §6 的约束集）。

激进压力样本按新规则重定义：接管压力来源从「追涨爆仓」改为「薄现金过度扩张 + 不派修 + 长在线会话」，压力搜索只允许调策略参数，不得改正式经济数值；新目标带定为**接管率 20–50%**，且维持「30 天末净值为正、无死档」不变。

**验收标准**

1. 活跃 20 座中位回到 14–21 天；第 1 天 2–3 座与第 7 天 6–10 座门禁不回退。
2. 激进接管率落入 20–50% 新带；挂机/活跃全部原有门禁不回退。
3. 调了哪个旋钮、为什么停在那里，写进 `balance_report.md`；`02_economy.md` 数值表同步。

### B7.3 · 随批小修（本 review 发现）

1. `data/inquiries.json` `mining_rush.unlock_era` 1 → 2（GPU 机柜时代 2 才解锁，时代 1 收到该卡永远无法满足条件）。
2. `core/game.gd:sign_contract`：手动改签时对称清除 `inquiry_contract_id / inquiry_template_id / inquiry_premium`（目前只有自动续约路径清除）。
3. 询价签约金计入 `total_revenue` 的现状**保留**（加速时代解锁的量级 ~0.4%，可接受），在 02 号文档注明即可。

### B7.4 · 收尾

- T2 维护费本批次维持 $1,150；§6 的扫描数据基于旧锁价基线，作废归档，若 B7.2 第 4 步需要则按新基线重扫。
- 全量门禁重跑（README 清单 + 本文全部新增用例）；文档同步 00/01/02/README；本节末尾补验收记录，格式沿用 §6。

### §7 验收记录（2026-08-15）

#### B7.1 · 期限折算锁价

- [x] `MarketSystem.locked_customer_multiplier` 对签约时已生效事件的结束切点做分段常函数精确积分；预告、日噪声和尚未开始事件不入账，没有采样近似。
- [x] `Game._locked_rate_for` 是签约、续约、forecast 与询价报价的唯一锁价计算点；计算次序为折算 → 询价溢价 → 战略约 ×2.5 封顶，既有合约不追溯。
- [x] 单测覆盖剩余 1 月 ×5 事件的三档手算值、双事件交叠、无事件时代基线、溢价后封顶、续约重折算、旧锁价保留，以及同 seed 行情序列逐位一致；`test_runner` 207/207。
- [x] `full_campaign` 在同一局注入事件并断言灵活约折算锁价高于标准约，同时跑通询价、成组、扩编和战略约封顶，最终于第 110 月达到 20 座并通过。
- [x] 合约确认、现有合约和行情参谋展示同源折算值与事件剩余时间；中英文各 45 个 iPhone 17 竖屏状态通过裁剪、叠印与内容压缩断言。

#### B7.2 · 节奏回调

- [x] 严格按顺序复跑 20 种子：先把事件期参考行为切为灵活约（20 座中位 23.6 天），再将工程部 L2 价格 $250,000→$180,000（23.6 天），再将 8 张询价溢价整体 +0.05（23.9 天）。三个正式旋钮后只校准活跃参考策略的现金缓冲 2.3→1.8 个建设包，最终第 20 座中位 19.3 天，因此停止且未执行 T2 调整。
- [x] 最终第 1 天 2–3 座、第 7 天 6–10 座；第 7 天挂机/活跃收入比 45%；30 日活跃/挂机净值比 23.67×；询价收入占 2.5%，全部进入目标带。
- [x] 挂机 0 接管、0 欠费月；策略参数重定义后的激进压力样本接管率 25%，落在 20–50% 新目标带；全部 60 个样本 30 天末净值为正，压力样本均保有至少 $5,000 重整恢复底线。
- [x] T2 维护费保持 $1,150；旧瞬时锁价扫描已归档为 [t2_maintenance_sweep_pre_b7.csv](balance_runs/archive/t2_maintenance_sweep_pre_b7.csv)，没有按失效基线改正式数值。

#### B7.3 · 随批小修

- [x] `mining_rush` 解锁时代改为 2，数据校验与单测均锁定该门槛。
- [x] 手动改签对称清除 `inquiry_contract_id`、`inquiry_template_id`、`inquiry_premium`；询价接单仍在签约后正确写回三项元数据，正反路径均有回归。
- [x] 询价签约金继续计入 `total_revenue`；最终归因占活跃总收入 2.5%，规则已同步到 02 号文档。

#### 全量门禁与提交

- [x] `python3 tools/validate_data.py`：13 张数据表、本地化与 159 个美术 ID 全部通过。
- [x] `python3 tools/simulate_economy.py --seed-count 20`：三策略 × 20 种子及全部总量硬闸通过。
- [x] `godot --headless --path . tests/test_runner.tscn`：207 passed，0 failed。
- [x] `flow_audit`、`midgame_audit`、`tutorial_playthrough`、`full_campaign`、`performance_smoke` 全绿；性能门禁平均 6.85 ms、P95 9.28 ms、峰值粒子 30、残留 0。
- [x] `visual_smoke` 英文/中文各 45 态通过，输出尺寸 990×2151。
- [x] 独立提交：`d46bd76`（B7.1）、`2440a4a`（B7.2）、`107e06d`（B7.3）；本提交只收口归档、README 与验收记录。
