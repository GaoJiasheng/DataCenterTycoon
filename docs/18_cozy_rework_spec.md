# 18 · 「轻松化」玩法改造实施规格（Codex 执行文档）

> 生成于 2026-08-08。本文档由项目所有者（GaoJiasheng）确认方向后编写，作为本批次改造的**唯一执行依据**。
> 执行者请先读 [00_decisions.md](00_decisions.md) 与 [01_game_design.md](01_game_design.md)；本文引用的所有代码位置已与 `main` 分支（bce9697）逐一核对。

## 0. 背景与设计原则

产品目标重新校准为：**好玩、易玩、简单、放松、无压力**的 IDC 建设经营游戏。

现状诊断：游戏骨架是放置（离线推进、计时器），但五个压力系统按活跃策略游戏调参——实时行情结算、硬破产清档、报废罚款、故障产出归零、限时续约窗口。合在一起的体验是「离开游戏 = 事情在变坏」，与放松目标冲突。现有代码里的两个补丁（离线寿命冻结 99.9%、欠费计时离线暂停）正是这个冲突的证据。

本批次的统一原则（后续所有设计争议以此裁决）：

> **玩家不在的时候，世界只能变好或变慢，不能变坏；玩家上线时看到的应该是收获和机会，而不是账单和惩罚。**

本批次共 5 个工作项（A1–A5）+ 1 个回归项（A6）。每项独立成节，含机制定义、数据改动、代码改动、UI/文案、存档迁移、验收标准。

---

## 1. 决策变更（先做：更新 00_decisions.md）

以下变更已获所有者批准，执行时**第一步**先把 00_decisions.md 改掉，避免与旧决策打架：

| 条目 | 变更 |
|---|---|
| D20 | **改写**：破产不再是 Game Over。现金流断裂进入「欠费」预警后，若持续未清偿则触发「银行接管」：自动变卖资产抵债，盘面延续，永不清档。原「重开新档」表述删除 |
| D22（新增） | 合约**签约锁价**：机房收入按签约时刻锁定的行情倍率结算，实时行情只影响新签/改签 |
| D23（新增） | 放松原则入档：离线期间任何系统不得让玩家资产或收入变得比离线前更糟（老化推进属于正常损耗，不在此列，且已有离线冻结/自动退役兜底） |
| D24（新增） | 故障为「降效事件」而非「停产事件」，且超时自动修复；玩家干预只是加速 |
| 「明确不做」 | 追加一条：「限时决策窗口（所有需要玩家拍板的事项必须等玩家上线，不设现实时间倒计时）」 |

---

## 2. 工作项

### A1 · 签约锁价（最高优先级）

**机制定义**

- 签约（含改签、自动续约）时，将该客户**当时**的行情倍率写入合约：`锁定倍率 = 时代基线 × 当前生效事件倍率`（**不含**每日噪声，避免玩家反复重开 app 刷 ±5%）。
- 合约期内收入一律用锁定倍率结算，实时行情不再影响已签合约。
- 机柜的 `market_sensitivity` 公式保留，只是作用对象换成锁定值：`有效倍率 = 1 + (锁定倍率 - 1) × sensitivity`。
- 合约到期：**无缝自动续约**，按续约时刻的行情重新锁价（防止 ×3.5 大单永久锁定），同时授予该机房一次「免费改签」资格（见 A5）。
- 提前改签仍收 25% 毁约费（现值不变）——锁了差价想跳船要付钱，这是仅存的、也是唯一需要的策略摩擦。

**数据改动**

- 无新数据文件字段；锁定值存进存档中的 datacenter dict：`locked_market_multiplier: float`。

**代码改动**

- `gameplay/market_system.gd:customer_multiplier`（79 行）：加参数 `include_noise: bool = true`；`include_noise = false` 时跳过 `market.noise` 乘项。行情页曲线与 `snapshot_history` 继续用含噪声值。
- `core/game.gd:sign_contract`（271 行）：写入 `dc["locked_market_multiplier"] = market.customer_multiplier(customer_id, state, data, false)`。
- `core/game.gd:_process_contract_renewals`（769 行）：自动续约时同样重新锁价（配合 A5 一起重写，见 A5）。
- `gameplay/game_rules.gd:datacenter_income_per_month`（102 行）：第 134 行 `raw_market_multiplier` 改为优先读 `datacenter.get("locked_market_multiplier")`，缺失时回退到现有 `market_multiplier.call(customer_id)`（保证未迁移存档与既有测试不崩）。`market_multiplier` 参数保留。
- `tools/simulate_economy.py`：同步锁价逻辑（签约/续约时快照倍率，结算用快照）。「活跃型」策略从「随时追涨」改为「续约/免费改签时挑当前倍率最高的可解锁客户」。

**UI / 文案**

- 机房详情合约面板显示锁定价徽标（如「签约价 ×1.8」），与行情页当前价并列，让「现在改签划不划算」一眼可见。
- 行情页定位从「盯盘」改为「签约参谋」：曲线保留，事件预告文案强调「即将到来的签约机会」。
- 双语文案走 `localization/` 现有流程，新增 key 中英各配。

**存档迁移**

- `core/game.gd:_ensure_state_shape`（1167 行）：对有 `customer_id` 但无 `locked_market_multiplier` 的机房，按载入时刻的无噪声行情补写。

**验收**

- 单测：签约后手动注入一条 ×3.0 事件，机房月收入不变；改签后收入按新锁定值变化；到期自动续约后锁定值等于续约时刻无噪声行情。
- 模拟器：挖矿 ×0.2「矿难」生效期间，持有挖矿合约的挂机型玩家收入曲线不下跌（直到自动续约点）。

### A2 · 软破产：银行接管替代 Game Over

**机制定义**

- 「欠费」状态与救济广告全部保留（`arrears` 产出减半、离线暂停计时、每天 3 次广告救急）。
- 欠费在线累计满时限（沿用现值 21600 秒）后，不再 Game Over，触发**银行接管**：
  1. 按 `built_at` 从老到新，逐座变卖运营中机房：入账 = `retirement_value × takeover_value_ratio`（首版 0.7，接管折价是「疼」的来源）；
  2. 变卖所得优先冲抵欠款，直到欠款清零；剩余入现金，未变卖的机房保留；
  3. 若全部机房变卖后仍不足清偿：坏账核销（debt 清零），状态回 `normal`；
  4. 核销后若现金 < 标准机房价（$5,000）：发放一次性「重整贷款」补足到 $5,000（纯赠予，不计负债），保证永远不存在死档；
  5. 地块、时代、网络等级、科技、钻石全部保留。
- `game_over` 状态从可达状态中移除（枚举可保留以兼容旧存档读取，读到即视为 `normal` 并触发一次迁移提示）。

**数据改动**

- `data/economy.json` `bankruptcy` 节：
  - `game_over_after_online_seconds` 改名 `takeover_after_online_seconds`（值不变 21600）；
  - 新增 `takeover_value_ratio: 0.7`、`relief_cash_floor: 5000`。

**代码改动**

- `core/game.gd:_check_bankruptcy`（853 行）→ 改写为 `_process_bank_takeover`，按上述机制执行；产出 report/EventBus 通知（新信号或复用 `bankruptcy_state_changed` 加 `"takeover"` 状态值）。
- `core/game.gd:_process`（34 行）与 `advance_time`（75 行）中 `game_over` 短路判断删除。
- `SaveManager.archive_game_over` 调用移除；`start_new_company`（521 行）保留为设置页里的「主动重开」功能（玩家自愿行为，不是失败惩罚）。
- `tools/simulate_economy.py`：`game_over` 分支改为接管逻辑，统计口径从「破产率」改为「接管率」「被变卖机房数」。

**UI / 文案**

- 欠费警告文案从「破产倒计时」改为「银行催收中：再不清偿将变卖最老的机房」；告急音乐保留但降低侵略性（音频资源不换，仅确认不循环轰炸）。
- 原 Game Over 全屏演出改为「接管结算页」：列出被变卖的机房、抵债金额、剩余资产，按钮是「重新出发」（关闭弹窗继续玩）。grep `game_over` 定位 UI 场景（`ui/` 目录）逐一改造。

**存档迁移**

- `_ensure_state_shape`：`bankruptcy.status == "game_over"` 的旧档 → 执行一次接管流程后置 `normal`。

**验收**

- 单测：构造欠费满时限的状态，断言按最老机房先卖、债清即停、坏账核销、贷款补足 $5,000 各分支。
- 模拟器：激进型 30 天接管率允许 30%–60%（对应原「欠费惊魂」验收），但**任何策略 30 天末净值必须为正且仍在增长**；不存在任何 seed 出现死档。

### A3 · 退役 = 收割（去掉报废惩罚 + 自动退役科技）

**机制定义**

- 取消清拆费。报废（ruin）不再是罚款事件，而是「收成打折」：清理废墟免费，且返还**残料回收**金。
- 残料回收 = `建设成本 × 5% + 外挂件成本 × 10% + 机柜成本 × 50%`（机柜比率沿用现有 `rack_refund_ratio`）。约束：对任意寿命进度 p ∈ [0.6, 1.0)，**正常退役总回收必须严格大于报废残料总回收**（用数值表逐档验证，防止「故意拖到报废」成为最优）。
- 新增全局科技「自动退役」（时代 2 解锁，$15,000，无建设周期）：购买后，任何机房寿命进度达到 95% 时自动退役入账，**离线也生效**（这是入账事件，符合 D23）。未购买者维持现有 99.9% 离线冻结逻辑。

**数据改动**

- `data/economy.json` `aging` 节：`demolition_cost_ratio` 删除；新增 `ruin_building_scrap_ratio: 0.05`、`ruin_attachment_scrap_ratio: 0.1`、`auto_retire_progress: 0.95`。
- `data/technology.json`：`upgrades` 下新增 `auto_retirement`（单级：`cost: 15000`、`unlock_era: 2`），结构仿照现有 `repair_team`。

**代码改动**

- `gameplay/game_rules.gd:demolition_cost`（180 行）→ 改为 `ruin_scrap_value(datacenter, data)`，按上式计算（注意 ruin 时机柜仍在 `racks` 数组里，直接遍历回收）。
- `core/game.gd:demolish_ruin`（351 行）：不再 `_spend_cash`，改为入账残料金；成功 payload 从 `{cost}` 改为 `{refund}`。
- `core/game.gd:_process_aging`（793 行）：进入循环前查科技；已购「自动退役」且 `progress >= auto_retire_progress` 的机房，无论 online/offline 直接走退役入账（复用 `retire_datacenter` 的内部逻辑，绕过 `_has_jobs_for_datacenter` 时先取消该机房在装任务并按原价退款），并写入 report `aging` 与离线大事记。未购科技的 offline 分支维持 99.9% 冻结。
- `core/game.gd:upgrade_repair_team`（381 行）旁边新增 `purchase_auto_retirement()`。
- `tools/simulate_economy.py` 与 `tools/validate_data.py` 同步新字段与新科技。

**UI / 文案**

- 废墟点击文案从「支付清拆费」改为「清理残料，回收 $X」。
- 科技页加「自动退役」条目；机房寿命条在已购科技时显示「95% 自动退役」刻度线。

**验收**

- 单测：报废 → 清理入账残料；p=0.94 时正常退役回收 > 残料回收；自动退役在 offline `advance_time` 中正确入账并出现在大事记。

### A4 · 故障软化：降效 + 自动修复

**机制定义**

- 故障机柜产出不再归零，改为 ×0.4（`faulted_income_multiplier`）。
- 故障发生时同时排一个**自动修复**时点：4 现实小时后免费自动修好（视觉：工程师小人慢悠悠自己来了）。派修（付费加速）、广告立修、钻石立修全部保留，定位变为「加速回满」——商业化位不减。
- `repairing` 状态（已派修等待中）产出维持 0 不变（在拆机检修，合理且给付费加速留出价值差）。

**数据改动**

- `data/economy.json` `faults` 节新增：`faulted_income_multiplier: 0.4`、`auto_repair_seconds: 14400`。

**代码改动**

- `core/game.gd:_process_repairs_and_faults`（744 行）：置 `faulted` 时写 `installed["auto_repair_at"] = now + auto_repair_seconds`；循环中检查 `auto_repair_at <= now` 则调 `_complete_repair`（免费路径，`faults_repaired` 统计口径拆分为手动/自动两个字段）。
- `core/game.gd:_next_boundary_after`（595 行）：608 行的 key 列表加入 `"auto_repair_at"`（离线分段结算的边界必须包含它，否则离线自动修复时间点结算不准）。
- `gameplay/game_rules.gd:datacenter_income_per_month`：126 行 `status != "active"` 的 continue 改为：`faulted` 状态不跳过，产出乘 `faulted_income_multiplier`；`installing`/`repairing` 仍跳过。`powered_slots` 无需改（故障柜本就占用供电）。
- `dispatch_repair` / `instant_repair_with_gems` / `_complete_repair`：完成时清理 `auto_repair_at`。
- `tools/simulate_economy.py`：同步降效与自动修复。

**UI / 文案**

- 故障角标与冒烟特效保留；机柜浮层文案从「已停止产出」改为「效率降低，工程师将在 X 后自动修复」。

**验收**

- 单测:故障柜收入 = 正常 ×0.4;不干预 4 小时后自动恢复;离线跨越自动修复点时,修复前后两段收入分别按 0.4 和 1.0 结算。
- 模拟器:挂机型(从不手动修)30 天曲线相对当前基线的降幅 < 8%。

### A5 · 续约窗口「等人」：免费改签资格

**机制定义**

- 删除「到期后 2 现实小时免费窗口」。新规则：
  1. 合约到期瞬间**无缝自动续约**（重新锁价，见 A1），收入不中断；
  2. 同时给该机房记一枚「免费改签」资格（`free_switch_available: true`），**不过期**，玩家下次为该机房签任何新客户时消耗，改签免毁约费；
  3. 资格不叠加（布尔值即可，多次续约不累积成多张券）。
- 玩家体验：上线看到「3 座机房已自动续约，各有一次免费改签」，什么时候处理都行；不处理也只是维持现状，绝不变坏。

**数据改动**

- `data/economy.json` `contracts` 节：删除 `renewal_window_seconds`；其余不变。

**代码改动**

- `core/game.gd:_process_contract_renewals`（769 行）：整段重写——到期即 `contract_end_at += duration`、重新锁价、`dc["free_switch_available"] = true`，发 report + `EventBus.contract_renewal_opened`（信号语义改为「已自动续约、可免费改签」，或换新信号名并全局替换监听方）。
- `core/game.gd:contract_switch_fee`（291 行）：295 行的窗口判断改为 `if bool(dc.get("free_switch_available", false)): return 0.0`。
- `core/game.gd:sign_contract`：签约成功时 `dc.erase("free_switch_available")`；285 行的 `dc.erase("renewal_window_end_at")` 及所有 `renewal_window_end_at` 引用（含 `_next_boundary_after` 613 行 key 列表）全部清除。
- `tools/simulate_economy.py`：`renewal_window_end_at` 逻辑（52、259、279 行附近）换成资格制。

**UI / 文案**

- 机房卡片与抽屉：有免费改签资格的机房显示绿色「可免费改签」徽标；离线大事记条目改为「已按 ×N 自动续约，改签免费」。

**存档迁移**

- `_ensure_state_shape`：存在 `renewal_window_end_at` 的旧档 → erase 该 key；若原窗口在载入时仍未过期，补 `free_switch_available = true`。

**验收**

- 单测:到期后收入无缝衔接(无零收入间隙);免费改签一次后费用恢复 25%;资格跨离线、跨存档读写保持。
- flow_audit / full_campaign:README 提到 full_campaign 会断言「续约窗口」,相关断言改为断言自动续约通知与免费改签徽标。

### A6 · 回归与调平（最后做，铁律）

1. 全量跑 README「开发与验收」列出的所有门禁：`test_runner`（103 项起，本批次新增用例后应更多）、`flow_audit`、`midgame_audit`、`tutorial_playthrough`、`full_campaign`、双语 `visual_smoke`、`performance_smoke`、`validate_data.py`、`simulate_economy.py`。
2. `simulate_economy.py` 默认 20 种子 × 3 策略 × 30 天，新验收目标（**替换** 02_economy §10 中与破产相关的旧条目）：
   - 挂机型：30 天内 0 次银行接管、0 次收入为负的月份；相对活跃型差距仍在 40%–60% 区间；
   - 活跃型：第 1 天 2–3 座机房、第 14–21 天完成首次转生、四类客户签约时长占比均 ≥ 10%（原验收保留）；
   - 激进型：接管率 30%–60%，30 天末净值为正且持续增长；
   - 全体：不出现「永远只买某一种机柜」的最优解；不出现任何死档。
3. 曲线截图存 `docs/balance_runs/`，结论回写 `docs/balance_report.md`。若达不到目标，可调的旋钮（按优先级）：`takeover_value_ratio`、`faulted_income_multiplier`、`auto_repair_seconds`、维护费表；**不得**通过恢复实时行情结算或加回惩罚来凑数。
4. 文档同步：`00_decisions.md`（§1 的表）、`01_game_design.md` §4.4/§4.5/§6/§9/§10、`02_economy.md` §5.3/§5.6/§9/§10、README「当前状态」。文档与 `data/*.json` 数值必须一致。

---

## 3. 实施顺序与批次

```
批次 1：§1 决策文档更新
批次 2：A1 签约锁价 + A5 免费改签   （两者都动 _process_contract_renewals，必须同批实现）
批次 3：A4 故障软化                 （独立，改动面小）
批次 4：A3 退役收割 + 自动退役科技
批次 5：A2 银行接管                 （依赖 A3 的 retirement_value 语义确认后做）
批次 6：A6 全量回归 + 调平 + 文档同步
```

每批次内：先改 `data/*.json` 与 `game_rules.gd`/`game.gd`/`market_system.gd`，再同步 `simulate_economy.py` 与 `validate_data.py`，再补测试，最后过 UI 与本地化。每批次结束跑一次 `test_runner` 保持绿色，批次间可独立提交。

## 4. 明确不做（本批次范围外）

- 「订单板 / 询价单」系统（具体客户带条件来单）：方向已认可，但属于新系统，另立提案再做，本批次**不要**实现。
- 00_decisions「明确不做」清单里的所有项（PUE、电价调度、冗余设备、拓扑等）维持不做。
- 不动时间换算（D21）、老化曲线形状、转生公式、地价公式。
- 不删任何商业化位：四个广告位与全部 IAP 保持可用，只是触发语境从「救火」变成「加速」。

## 5. 给执行者的注意事项

1. `market_sensitivity`（06 号文档 P0-1）与锁价叠加后，存储柜「稳」的定位由锁价承担了大半；若模拟器显示存储柜被严格支配，优先微调 `customers.json` 的 fit 值，不要动 sensitivity 机制。
2. `_next_boundary_after` 是离线分段结算的心脏，A4/A5 增删计时 key 时务必同步，否则离线结算会静默出错——现有 `full_campaign` 测试会抓到一部分，但请为新 key 单独写离线跨界用例。
3. 所有新增玩家可见文案必须中英双语齐全，走 `localization/` 现有流程，并跑双语 `visual_smoke` 确认排版。
4. 教程（`data/tutorial.json`）流程覆盖签约与退役：改动后完整跑 `tutorial_playthrough` 与 `flow_audit`，教程文案里若提到旧规则（清拆费、续约窗口）一并更新。
