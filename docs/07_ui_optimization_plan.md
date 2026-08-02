# 07 · UI/UX 深度诊断与优化 Plan（对标一线手游标准）

> 生成于 2026-08-02。初始诊断依据为 18 张 402×874 截图；玩法优化接入后回归集已扩为 21 张，追加续约、停机与机柜选购/加速状态。
> 对标基准：Hay Day / Township / Clash of Clans（世界交互与 FTUE）、Royal Match（反馈与动效）、Egg, Inc. / Idle Miner Tycoon（放置类信息呈现与营收位）。
> **本文是外包执行文档**：每个工作包（WP）含任务清单（精确到文件与函数）、验收标准和测试要求，Codex 可直接按 WP 顺序落地。§8 是执行约束，必读。

---

## 1. 总诊断：三个根因

当前 UI 完成度是「功能全部可达」，但与一线产品的差距不在功能，而在三个根因上：

**根因 A：视觉语言断裂 —— 美术资产闲置。**
世界层是明快的卡通 2.5D（草地、蓝色机房、树木），但所有 UI 面板/按钮是深海军蓝 `StyleBoxFlat` + 1px 描边 + 纯色填充，观感是「开发者调试面板」。而 `assets/art/ui/` 里**已经交付**了成套的卡通 UI 九宫格：`panel_main`、`panel_dark`、`btn_primary/secondary/warning/danger/disabled/ad`、`dialog_bubble`、`progress_frame/progress_fill`。`theme_factory.gd` 里的 `texture_box()` / `art_button_box()` 工具函数存在但几乎无调用方。一线游戏的 chrome 与世界是同一美术宇宙；本作只需把已有资产接上。

**根因 B：核心决策信息不可见 —— 玩法在 UI 上「盲玩」。**
本作的布局谜题（D12：GPU 摆角格吃双冷却交叉覆盖）、供电预算、客户适配系数、换约收益对比，**全部没有任何可视化**。机柜页是 9 个文字按钮；合约页只有 ×1.02 倍率数字；玩家做每个决策时都拿不到决策所需的信息。一线模拟经营的铁律：**任何花钱按钮旁边必须能看到「按下去会发生什么」**（收益差、覆盖范围、前后对比）。

**根因 C：反馈闭环缺失 —— 赚钱没有「感觉」。**
收入每秒静默累积，现金标签直接跳数字；建成、签约、退役这些高光时刻只有 toast + 音效；到期/故障没有世界层的可点提示动线。已有的 juice（按钮缩放、少量 fx_coin）方向对但密度和编排远低于标准。一线标准：**数字滚动、金币飞向钱包、目标控件脉冲、事件驱动的世界气泡**，每个正反馈都要经过「世界 → HUD」的视觉动线。

另有一个**架构级体验缺陷**（必须最先修）：`_refresh()` 每次全量重建当前页面，而 `advance_time` 每秒 emit `state_changed("tick")` → 打开任何页面时整页每 ~1 秒重建一次，**ScrollContainer 滚动位置被重置**、按钮按压状态丢失、GC 抖动。这是玩家「说不出哪里不对但就是廉价」的最大单一来源。

---

## 2. 逐屏诊断（截图证据 → 问题 → 对标做法）

### 2.1 主地图（map / campus_dense / map_built）

| # | 问题 | 证据 | 一线做法 |
|---|---|---|---|
| M1 | 世界无收入反馈：建筑不冒钱、现金不滚动、无任何「正在赚钱」的表达 | map_built：运营中机房与空地毫无区别感 | Hay Day：作物/机器头顶随时有状态气泡；Idle Miner：金币粒子沿动线飞向余额 |
| M2 | 左右两个圆形按钮语义不明：左=扳手图标（建设队列）、右=网络节点图标（运营中心），无文字标签 | map.png 底部 | CoC/Township：圆形入口按钮下方都有小字标签，图标语义直白（商店=购物车） |
| M3 | 公司 chip 显示「T1」，与机房等级 T0–T3 术语撞车（实际含义是时代 1） | 左上角 | 用时代图标 + 「时代 1」或专属名词，T 系列保留给建筑 |
| M4 | 地块无地面基座、无园区肌理，建筑像贴在草地上；待售地块价签浮在半空 | campus_dense | Township：每个可建区块有明确地垫/围栏；价签锚定在地块上 |
| M5 | 建设中只有静态「建造」气泡，无倒计时环/进度表达（park_map 有每秒文字倒计时，但无进度视觉） | map_built | CoC：工地有进度条+剩余时间+可点加速 |
| M6 | 新手引导是白色横幅，无指向目标的手指/聚光灯/输入限制 | map.png 底部横幅 | 全行业标准：暗幕挖洞 + 手指动画 + 只允许点目标 |

### 2.2 机房详情（dc_context / dc_racks / dc_infrastructure / dc_contracts）

| # | 问题 | 证据 | 一线做法 |
|---|---|---|---|
| D1 | **3×3 网格是 9 个文字按钮，冷却覆盖/供电预算完全不可见**——核心谜题盲玩 | dc_racks：绿色「空机位」按钮阵 | 见 §WP3 的完整重设计：棋盘化 + 覆盖叠加层 + 电力条 |
| D2 | 关闭按钮是高饱和红 ✕，红色=危险色被用于中性操作，且每张 sheet/页面都如此 | 所有截图右上角 | 中性深色圆 + 白 ✕；红色只留给拆除/重置 |
| D3 | 情境抽屉 → 机房详情 → 三段 tab，层级偏深且「机房详情」按钮与三个任务按钮功能重叠 | dc_context | 保留抽屉但抽屉即详情（见 WP3），砍掉中间跳转 |
| D4 | 寿命 0% 和 $0/月 两个 chip 长得像按钮（带边框胶囊）但不可点 | dc_racks 顶部 | 信息 chip 与按钮在形状/颜色上必须可区分 |
| D5 | 合约页锁定客户显示「×0.00」，像«这客户不给钱»而不是«未解锁»；无解锁条件、无适配系数、无预估收益对比 | dc_contracts | 锁定卡：🔒+「时代 2 解锁」；可选卡：适配三图标 + «签约后 $X/月 (+22%)» |
| D6 | 基础设施页四个冷却位按钮只写方位英文首字大写（North…），与网格行列的空间关系靠想象 | dc_infrastructure | 冷却位应画在网格四边的空间位置上（WP3 合并解决） |

### 2.3 行情页（market）

| # | 问题 | 证据 |
|---|---|---|
| K1 | 图表空白时渲染裸网格线，无空态文案/无坐标轴标签/无图例/无「现在」标记 | market.png 上半 |
| K2 | 「行情」标题与「当前行情平稳」副标在一屏出现 3 次（页头/卡头/底部状态卡） | market.png |
| K3 | **字形缺失**：「当前行情平稳」的「稳」渲染成 tofu 方块（SystemFont 回退链在部分字重下丢字形） | market.png 页头副标与底部状态卡 |
| K4 | 客户卡只有当前倍率，无涨跌方向、无 24h 变化、无迷你走势 | market.png 中部 |
| K5 | 事件卡无剩余时间进度条、无受影响客户标识、无「去调仓」动线 | （事件态未截到，代码 `_event_card` 只有三行文本） |

### 2.4 其他页面

| # | 问题 | 证据 |
|---|---|---|
| O1 | 运营中心 2×2 卡片右侧的蓝色状态点被 HBox 拉伸成竖条（`status_dot` 未锁 size_flags） | operations.png 每张卡右侧 |
| O2 | 商店无分区（特惠/钻石/权益混排）、无价值锚点（+X% 加送、最划算标签）、无已拥有态区分度 | store.png |
| O3 | 科技页时代进度是普通进度条，看不到「下个时代解锁什么」（内容动机缺失）；转生按钮锁定态只有一行灰字 | tech.png |
| O4 | 时代切换「全屏演出」实际是一个普通对话框（云图标+文字+绿按钮），与设计承诺的«新闻头条式演出»差距大 | era_unlock.png |
| O5 | 设置页缺隐私政策/服务条款/版本号/客服邮箱（App Store 过审与合规刚需） | settings.png |
| O6 | 底部 sheet 有拖拽把手视觉但不可拖拽关闭（假 affordance）；sheet 关闭无退出动画（queue_free 瞬移消失） | 代码 `_create_world_sheet` / `_dismiss_world_sheet` |
| O7 | `_build_map_page()` / `_plot_card()` 是不可达的旧代码路径（active_page=="map" 提前 return），维护噪音 | 代码 493–567 行 |

---

## 3. 设计系统 2.0（WP1 的规范基准）

### 3.1 设计令牌（写入 `ui/theme_factory.gd` 顶部常量区）

```gdscript
# 语义色（在现有 COLORS 基础上收敛使用场景）
SEMANTIC := {
    "primary":   COLORS.green,    # 唯一主 CTA 色：花钱建造/确认
    "action":    COLORS.sky,      # 次级操作/导航
    "premium":   COLORS.purple,   # 钻石/广告/IAP
    "warning":   COLORS.orange,   # 需要注意（老化、队列满、预告）
    "danger":    COLORS.red,      # 仅限：拆除、重置、破产、故障
    "success":   COLORS.green,
    "locked":    Color("8a97a8"), # 锁定/禁用统一灰
}
# 字号阶梯（Godot units，2u = 1pt）
TYPE_SCALE := { "display": 44, "title": 36, "heading": 28, "body": 24, "caption": 20, "micro": 18 }
# 间距 & 圆角
SPACE := [4, 8, 12, 16, 24, 32]      # 只允许这 6 档
RADIUS := { "chip": 14, "button": 18, "card": 22, "sheet": 28 }
# 触控
TOUCH_MIN := 88.0   # 44pt，保持现有测试门禁
```

### 3.2 字体（修 K3，必做）

- 弃用 `SystemFont` 回退链。打包两枚 OFL 字体进 `assets/fonts/`：
  - 拉丁/数字：**Baloo 2**（圆润卡通，与 Hay Day 质感一致）或 Nunito ExtraBold；
  - 中文：**Noto Sans SC**（Medium + Bold 两档）。
- 用 `FontVariation` 建 fallback 链（Baloo 2 → Noto Sans SC），在 `ThemeFactory.create()` 设为 default font。数字场景（现金/倍率）另建 `font_numeric`，开 `tabular figures`（等宽数字，避免滚动时抖动）。
- 所有 Label 默认加 1px 深色 outline（`font_outline_color = COLORS.ink, outline_size = 3`）用于世界层之上的文本；页面内文本不加。封装为 `ThemeFactory.world_text(label)`。

### 3.3 组件规范（全部落在 theme_factory + 新文件 `ui/widgets.gd`）

| 组件 | 规范 |
|---|---|
| 面板 | 页面工作面 = `panel_dark` 九宫格；浅色对话/引导 = `panel_main`；`texture_box()` 已有，补 `region/margins` 调参。资产缺失时回退现 flat 样式（保留现有回退纪律） |
| 按钮 | 一律走 `art_button_box()` 九宫格：primary=`btn_primary`、secondary=`btn_secondary`、warning=`btn_warning`、danger=`btn_danger`、disabled=`btn_disabled`、广告位=`btn_ad`（带播放角标）。文字白色 + ink 描边 2px。删除 `apply_button_color` 的裸色路径（保留为资产缺失回退） |
| 关闭按钮 | 统一组件 `widgets.close_button()`：72×72 深色半透明圆（`Color(0,0,0,0.35)`）+ 白 ✕，右上角，**不用红色**（修 D2） |
| 信息 chip | 无边框、填充 `Color(0,0,0,0.25)`、圆角 14、icon+text，**明确不可点样式**（修 D4） |
| 进度条 | 全局替换为 `progress_frame` + `progress_fill` 九宫格；加 `widgets.timer_bar(complete_at, duration)`：进度 + 剩余时间文本 + 到点脉冲 |
| 徽标 | `widgets.badge(count)`：红圆白字，挂任意按钮右上角（现 queue_badge 逻辑抽出复用） |
| 圆形入口按钮 | `widgets.round_entry(icon, label_key)`：图标 + 下方 18u 标签（修 M2），徽标插槽 |

### 3.4 动效与反馈规范（全局对照表，WP2 实现基建）

| 事件 | 视觉 | 时长/缓动 | 音效 cue | 触觉 (ms) |
|---|---|---|---|---|
| 按钮按压 | scale 1→0.96→1（已有 `_wire_button_motion`，保留） | 80ms out / 140ms TRANS_BACK | `sfx_tap`（新增 cue，无则静默） | 8 |
| 现金变动 | 数字滚动插值（不跳变） | 0.4s，大额（>10× 月收入）1.2s | 大额时 `sfx_coin_tick` | — |
| 收入到账（周期性） | 金币粒子 3–5 枚从机房飞向现金 chip，chip scale 1→1.06→1 | 飞行 0.6s TRANS_QUAD_IN，错峰 40ms | `sfx_coin` 轻量 | — |
| 建成/签约/退役回款 | 金币飞行 8 枚 + 目标建筑 squash（y 0.9→1.05→1）+ `fx_confetti_set`（建成限定） | 0.8s | 既有 `sfx_build_complete` 等 | 16 |
| Sheet 进场 | y +64→0 + fade 已有 | 0.28s QUART_OUT | — | — |
| Sheet 退场（新增） | y 0→+64 + fade，动画完再 free | 0.20s QUAD_IN | — | — |
| 页面切换 | 已有 fade+slide 保留 | 0.18/0.26s | — | — |
| 故障发生 | 世界层机房弹红色 ⚠ 气泡（scale 0→1 TRANS_BACK）+ HUD 徽标 +1 | 0.3s | 既有 `sfx_fault` | 24 |
| 时代解锁 | 全屏演出（见 WP6） | 2.5s 可跳过 | `sfx_era` | 32 |
| 通用禁止 | 任何 UI 元素不允许无动画瞬移出现/消失（toast、sheet、气泡全覆盖） | — | — | — |

触觉统一走现有 `_haptic()`；新增档位常量 `HAPTIC_LIGHT=8 / MEDIUM=16 / HEAVY=24 / SUCCESS=32`，替换散落的裸数字。

---

## 4. 工作包详述

> 顺序即依赖顺序。WP0/WP1 是地基，先行合并；WP2–WP6 可并行拆给多人/多 session；WP7 收口。

---

### WP0 · 体验缺陷修复（预计 1 人日）

**任务**

1. **修全量重建 jank（最高优先级）**
   - `ui/main_view.gd::_refresh()`：拆成 `_refresh_hud()`（每 tick 都跑：现金/钻石/新闻/徽标/主操作按钮）与 `_refresh_page()`（仅在需要时跑）。
   - `_on_state_changed(reason)` 按 reason 分流：`"tick"`/`"offline_advance"` 只置 HUD 脏标记；玩家动作 reason（现有 `_commit_action` 的枚举）才置页面脏标记。
   - 页面重建时保存/恢复滚动：`_wrap_scroll()` 给 ScrollContainer 命名 `PageScroll`，重建前记录 `scroll_vertical` 到 `_page_scroll_cache[active_page]`，重建后 `call_deferred` 恢复。
   - 机房详情页等含实时数字的页面：给页面挂 `set_meta("live_update", Callable)`，`_refresh_hud()` 顺带调用，只更新文本不重建节点。
2. **锁定客户不显示 ×0.00**：`_build_contract_management()` / `_customer_market_card()`——`era_baseline` 为 0 或未解锁时显示 `ic_lock` + `tr("UNLOCK_AT_ERA") % 2` / `tr("UNLOCK_AT_NETWORK") % "100G"`（修 D5/K4 一部分）。
3. **行情图空态**：`ui/market_chart.gd::set_series()` 数据点 < 2 时绘制空态：`ic_market_up` 淡显 + `tr("MARKET_NO_HISTORY")`，不画裸网格。
4. **运营中心状态点拉伸**：`_operation_module_card()` 的 `status_dot` 加 `size_flags_vertical = Control.SIZE_SHRINK_CENTER`（修 O1）。
5. **Sheet 退出动画 + 可拖拽关闭**：`_create_world_sheet()` / `_present_action_sheet()` 返回结构里带 `dismiss()`（播放 §3.4 退场动画后 free）；所有 `overlay.queue_free()` 调用点改为 `dismiss()`。把手区域接 `gui_input`：竖向拖拽 > 90u 或速度阈值即 dismiss，拖拽中 sheet 跟手（clamp 0~120u）+ 松手回弹（修 O6）。
6. **关闭按钮中性化**：新组件替换所有红 ✕（修 D2；组件本体属 WP1，此处先把颜色改成 `Color("263d59")` 即可）。
7. **术语修正**：`_refresh()` 中 `company_label.text` 改为 `tr("ERA_SHORT") % era_id`（新 key「时代 %d」/「Era %d」），tooltip 保留全名（修 M3）。
8. **删除死代码**：`_build_map_page()`、`_plot_card()` 及其引用（修 O7）。
9. **圆形按钮加标签**：任务/运营两个圆按钮下方加 18u 标签（`NAV_BUILD` / `OPERATIONS_SHORT`），运营图标从 `ic_network` 换成 `ic_tech` 之外新增语义（用 `ic_wrench` 不妥；暂用 `ic_shop`? 不妥——**新增资产 `ic_operations`（写字板+齿轮）**，缺失回退 `ic_network`）（修 M2）。

**验收**

- 打开商店页滚动到底，静置 10 秒（跨 ≥5 个收入 tick）：滚动位置不动、无整页闪烁（肉眼 + `Performance.get_monitor(OBJECT_NODE_COUNT)` 在页面静置期波动 ≤ ±2）。
- 全部 21 个 visual_smoke 状态通过；锁定客户卡不显示 `×0.00`，统一显示「未解锁」。
- 每张 sheet 均可：点 ✕ 关、点暗幕关、下拽关，三路都有退场动画。

---

### WP1 · 设计系统 2.0 落地（预计 2 人日）

**任务**

1. 按 §3.1–3.3 重写 `ui/theme_factory.gd`：令牌常量、字体装载（新目录 `assets/fonts/`，OFL license 文件一并入库）、九宫格样式接线、组件工厂迁入新文件 `ui/widgets.gd`（`close_button/chip/badge/timer_bar/round_entry/section_header/empty_state`）。
2. `main_view.gd` 全量替换调用点：`_button()`→语义化 `widgets.button(text, on_press, "primary"|"secondary"|"warning"|"danger"|"ad")`；`_card()`→`panel_dark` 纹理；对话/引导→`panel_main`+`dialog_bubble`。
3. 数字标签统一 `font_numeric`；现金/钻石 chip 换 `resource_panel` 纹理化版本（保持浅色底以便识别，可用 `panel_main` 裁切）。
4. HUD 资源 chip 右端加 `+` 角标（点击去商店，现 gem chip 已可点，补视觉 affordance；cash chip 的 `+` 进商店现金礼包区）。
5. 字体回归：`tools/check_assets.py` 增加 fonts 目录存在性校验；visual_smoke 增加断言：渲染一个含「稳/障/购/罄」等此前缺字风险字符的隐藏 Label，截图后像素非空校验（简化实现：`TextServer` 查询 glyph index ≠ 0）。

**验收**

- 14+ 状态截图对比：所有按钮/面板均为纹理九宫格（人工验收 1 次）；删除资产文件后回退 flat 样式且测试仍绿（回退纪律不破坏）。
- 全部文本无 tofu；中英双语各跑一遍 visual_smoke（`--locale` 参数化，加到 WP7）。

---

### WP2 · 世界反馈与 Juice 基建（预计 2 人日）

**任务**

1. **现金滚动**：`_refresh_hud()` 中现金/钻石标签不直接赋值，走 `widgets.animate_number(label, from, to, duration)`（Tween method 插值 + `Game.format_number`）。
2. **金币飞行系统**：新文件 `ui/fx_layer.gd`（挂 main_view 顶层，z_index 95）：`fly_coins(world_pos: Vector2, target: Control, count: int)`，用 `fx_coin` 贴图，§3.4 参数；到达时目标 chip 脉冲。接线点：
   - 周期收入：每 30s（避免刷屏）从收入最高的运营机房位置飞 3 枚；
   - `construction_completed` / `datacenter_retired` / 合约签订 / 离线收益领取 / 成就奖励：按 §3.4 满编 8 枚。
   - park_map 暴露 `world_position_of(target_id) -> Vector2`（现 `focus_target` 已能定位，抽出坐标查询）。
3. **建设倒计时环**：park_map 建设中地块的状态气泡升级为 `timer_bar` 迷你版（进度弧/条 + 剩余时间），完成瞬间 `fx_dust_puff` + 建筑 squash 落成动画（scale y 0→1.06→1，0.5s TRANS_BACK）。
4. **世界告警气泡动线**：故障/未通电/过热/可退役/合约到期，气泡样式统一为 `world_badge` + 对应 icon（`ic_wrench` 红 / `ic_power` 橙 / `ic_heat` 橙 / `ic_retire` 黄 / `ic_contract` 蓝）。**点击气泡直达处理界面**（故障→该机柜 action sheet；未通电→附件安装 sheet；到期→合约 tab），不再要求玩家自行导航（修 2.2-D3 的深层级问题）。
5. **HUD 徽标接线**：任务按钮徽标已有；运营按钮加徽标 = 活跃行情事件数 + 可负担的科技升级数；主操作按钮在「买地可负担」时轻微呼吸脉冲（scale 1↔1.02，2s 循环，仅当现金 ≥ 价格）。
6. **触觉档位化**：`HAPTIC_*` 常量替换 `_commit_action` 里的裸 24，按 §3.4 表分配。

**验收**

- 录屏检查：建成一座机房从倒计时结束到金币入账，动线完整（尘雾→squash→金币→现金滚动→徽标更新），全程无跳变。
- 点击世界层故障气泡 ≤ 2 步完成派修（现状 5 步）。
- visual_smoke 新增状态 `world_alerts`：构造故障+未通电+到期三气泡同屏，断言三个气泡节点存在且在视口内。

---

### WP3 · 机房详情重做：把谜题画出来（预计 3 人日，本计划核心）

**目标**：把「9 个文字按钮」变成**diegetic 机房棋盘**，冷却覆盖、供电预算、槽位状态全部可视化；情境抽屉直接承载完整管理（砍掉中间层）。

**布局规范（804×1748 画布）**

```
┌────────────────────────────────┐
│ 抽屉头：建筑图 88 + 名称/状态 + 寿命条 + ✕ │  ← 寿命条=progress_frame，老化段变橙、衰退段变红
│ chips：$X/月 ↑ · 客户名 · 合约剩余      │
├────────────────────────────────┤
│         [北冷却位 ◇]                │
│   ┌──┬──┬──┐                  │  ← 棋盘：dc_interior_bg 铺底，
│ [西◇]│··│··│··│[东◇]             │    格子 176×176，间距 8
│   ├──┼──┼──┤                  │  ← 冷却位=可点插槽，空=虚线框+雪花icon，
│   │··│··│··│                  │    装了=冷却器贴图，其行/列铺淡蓝覆盖层
│   └──┴──┴──┘                  │
│         [南冷却位 ◇]                │
│ ⚡ 供电 ▓▓▓▓▓░░ 12/20  [变压器 T2 ▸]  │  ← 电力条：分段=每台机柜耗电，超容段闪红
├────────────────────────────────┤
│ [签约/换约 CTA（情境化文案）]           │
└────────────────────────────────┘
```

**任务**

1. 新文件 `ui/datacenter_board.gd`（Control）：输入 `datacenter_id`，渲染上图。数据全部来自现有纯函数，**禁止自算**：`Rules.powered_slots` / `Rules.cooling_at` / `Rules.rack_runtime_status` / `GameRules.COOLER_EDGES`。
   - 格子状态视觉：空=`slot_empty`；锁=`slot_locked`（防尘布）；装机=机柜贴图（现有 `_active/_dark/_fault/_installing` 后缀规则）+ 状态角标；安装中=贴图半透明 + 迷你 timer_bar；停机=去饱和 + ⏸。
   - **冷却覆盖层**：每个已装冷却位，对其覆盖的 3 格绘制半透明蓝色渐变（`fx_frost_patch` 平铺，alpha 0.25）；格内机柜过热时该格转橙红 + `ic_heat` 角标。双覆盖角格 alpha 叠到 0.4——玩家一眼看懂「角格更冷」。
   - **电力条**：`progress_frame` 底 + 分段填充（每段=一台机柜耗电占比，按槽序着色）；总量>容量时超出段红色闪烁（0.6s 循环），并在对应格子显示 ⚡✕ 角标——供电贪心顺序从此可见（修 B5-1 的 UI 侧）。
2. **放置决策辅助**：点空格 → 机柜选择 sheet（现 `_show_rack_picker` 升级）：每个机柜项显示 成本/耗电/发热/基础产出 四格数据；选中预览时**棋盘实时高亮**：该格受冷量 ≥ 发热 → 绿勾，不足 → 橙 ⚠ +「此位置会过热」，电力不足 → 红 ⚡「需升级变压器」。确认才扣款。
3. **冷却位交互**：点四边插槽 → 附件 sheet（`_show_attachment_picker` 升级：显示制冷量/覆盖行列示意 3 格图），安装后覆盖层 tween 展开（scaleX 0→1，0.3s）+ `fx_snowflake` 粒子一次。
4. **抽屉整合**：`_show_datacenter_context()` 直接嵌 `datacenter_board`（sheet 高度升至 ~1100），三段 tab 简化为棋盘（含基础设施）+ 合约两 tab；删掉「机房详情」独立页与 `_open_datacenter_detail` 的 `racks/infrastructure` 分支（合约 tab 见 WP4）。低端机顾虑：棋盘节点数 ≤ 60，无每帧重建（状态驱动更新）。
5. 长按机柜格 → 数据 tooltip chip（产出/耗电/发热/受冷/故障率倍数），松手消失。

**验收**

- 构造「GPU 柜放中心格过热、移到角格正常」用例：不看任何数字，仅凭覆盖层颜色即可判断应放哪格（人工验收）。
- 放置预览状态下，9 格全部有 ✓/⚠/⚡ 三态之一。
- visual_smoke 替换 `dc_racks/dc_infrastructure` 为 `dc_board`、`dc_board_overheat`（构造过热态）、`dc_board_placing`（预览态）三状态，断言覆盖层节点数=已装冷却数×3、电力条存在。
- 回归 `tests/test_runner.gd`：玩法优化后 80 项全绿。

---

### WP4 · 决策信息化：合约 / 行情 / 科技（预计 2.5 人日）

**合约 tab（modifying `_build_contract_management`）**

1. 客户卡升级（2 列网格保留）：图标 + 名称 + 当前倍率与涨跌箭头（对比昨日 noise 前值，`market.history` 最后两点）+ **适配行**（compute/storage/gpu 三迷你图标 × 系数，高亮该机房实装机柜占比最高的机型）+ **预估月收入**：调用 `Rules.datacenter_income_per_month` 的假想值（复制 dc dict 改 `customer_id` 后调用——纯函数无副作用）。当前签约客户卡加「服务中」丝带角标。
2. 点卡 → 确认 sheet：`当前 $X/月 → 签约后 $Y/月（±Z%）`，毁约费/免费窗口状态（`renewal_window_end_at` 已在实现中）、合约期说明；确认按钮文案带金额。锁定卡点击 → toast 解锁条件。

**行情页（modifying `_build_market_page` + `market_chart.gd`）**

3. 图表：加图例 chips（四客户色点+名，点击 toggle 序列显隐）、Y 轴三条参考线标签（×0.5/×1.0/×2.0/×3.0 取数据范围）、右缘「现在」竖线；活跃事件在时间轴上画淡色区间条。页头/卡头去重（保留页头，图表卡不再重复标题）（修 K2）。
4. 客户卡加 7 日迷你 sparkline（直接取 history 尾段，Line2D 24 点降采样）。
5. 事件卡重做：`widgets.timer_bar` 显示剩余时长；受影响客户 icon chips + 倍率徽章（×3.0 绿 / ×0.2 红）；预告卡加「⏰ Xh 后开始」+ CTA「查看我的机房」→ 跳合约管理。事件开始/结束时（`market_event_started/ended` 已接）世界层 toast 升级为顶部横幅推入（0.3s 下滑，4s 停留，可点进行情页）。

**科技页（modifying `_build_tech_page`）**

6. 时代卡改**路线图**：横向三节点（ic_era1/2/3），当前节点高亮+进度环，下一节点下方列 3–4 个解锁物 icon（从 `buildings/racks/customers/attachments` 表按 `unlock_era` 过滤，取前 4 个 icon + 「等 N 项」）——让玩家知道在为什么攒钱（修 O3）。
7. 转生卡：锁定态显示进度 `已建成 X/20 座`（`total_datacenters_built`）+ 进度条；解锁态显示**预估品牌倍率**（按 02_economy §8 公式用当前净值在 UI 侧算，只读）与保留/清算清单，确认走两段确认（第二段输入滑条或长按 1.2s 确认，防误触）。

**验收**

- 合约确认 sheet 中出现前后收入对比且数值与签约后实际月收入一致（test_runner 加断言：构造机房，UI 预估函数 vs 改 customer 后的 `datacenter_monthly_income` 相等）。
- 行情页在 0 数据 / 2 天数据 / 满 2 年数据三种构造下渲染正确（visual_smoke 三状态：`market_empty/market_active/market_rich`，用 `snapshot_history` 预填充）。
- 科技页人工验收：3 秒内能答出「下个时代解锁什么」。

---

### WP5 · FTUE 聚光灯引导（预计 2 人日）

**任务**

1. 新文件 `ui/tutorial_overlay.gd`：全屏 CanvasItem（z_index 98）：
   - **暗幕挖洞**：`draw_rect` 全屏 `Color(0,0,0,0.55)` + 目标控件区域按圆角矩形挖洞（用 `CanvasItemMaterial` blend 或四矩形拼接法）；洞缘白色描边脉冲（alpha 0.4↔0.8，1.2s）。
   - **手指指针**：新资产 `ic_pointer_hand`（缺失回退：`guide_normal` 缩小版）；在目标中心上方 40u 处，上下浮动动画（±12u，0.8s SINE 循环）。
   - **输入门控**：`_gui_input` 拦截所有点击，仅目标 rect 内的事件放行（`push_input` 转发）；暗幕点击播放洞缘抖动提示。
   - **教练气泡**：`dialog_bubble` 纹理 + 老高立绘（guide_* five poses，按步骤映射现有 `guide_assets` 数组）+ 文案，自动锚定在洞的上/下方（避让）。
2. 目标解析表（`tutorial.json` 的 `focus` → 控件/世界对象）：

| focus | 目标 |
|---|---|
| build_dc_t0 | 主操作按钮（若 building picker 已开 → T0 卡片） |
| install_power | 棋盘供电插槽（WP3 后）→ sheet 中 power_t1 项 |
| rack_slot_0 | 棋盘 slot 0 → sheet 中计算柜 T1 项 |
| contract_internet | 合约 tab → 互联网客户卡 |
| install_cooler | 任一空冷却位 → 风冷 T1 项 |
| buy_plot | 世界待售地块价签（park_map 提供 rect） |
| retire_dc | 机房抽屉寿命条旁退役按钮 |
| build_dc_t1 | 空地 → building picker T1 卡片 |

   - park_map / main_view 暴露 `tutorial_target_rect(focus) -> Rect2`（找不到时返回零 Rect → overlay 退化为纯气泡模式，不挡输入——**永不因引导卡死玩家**）。
3. 步骤完成庆祝：`fx_confetti_set` 小喷发 + `sfx_tap` 上扬变调 +（第 1/4/7 步）金币奖励飞行（复用 WP2）。
4. 引导期间隐藏：新闻条、运营按钮、任务按钮（减噪，Supercell 惯例只留必要控件）。
5. 替换现有 `tutorial_panel` 横幅逻辑（`_refresh_tutorial` / `_position_tutorial_callout` 删除）。

**验收**

- 新档全程 8 步只用「点亮的那个控件」可完成；任意步骤杀进程重启后引导恢复到当前步且目标正确。
- 引导第 2 步（供电）完成瞬间：机房从暗到亮 + 灯光音效 + 金币飞（第一个 aha moment 的完整编排，人工录屏验收）。
- visual_smoke 新状态 `ftue_spotlight`（第 0 步）：断言暗幕存在、洞 rect 与主操作按钮相交、手指节点可见。

---

### WP6 · 高光演出与营收位（预计 1.5 人日）

1. **时代切换演出**（替换 `_show_era_overlay`）：全屏报纸头版风——白色纸张纹理（`panel_main` 放大）快速旋入（rotate -8°→0, scale 1.4→1, 0.5s BACK_OUT）+ 大标题「云计算时代来临！」+ 时代 icon + 三行解锁摘要（复用 WP4 路线图数据）+ 钻石奖励计数滚动；背景 `fx_confetti_set` 双喷发；2.5s 后出现确认按钮，可提前点击跳过（修 O4）。
2. **离线收益弹窗升级**（`_show_offline_dialog`）：收益数字 1.2s 滚动 + 金币堆图；「看广告 ×2」用 `btn_ad` 大按钮置顶（放置类最高价值广告位应有最高视觉权重）；大事记列表 icon 化（⚠ 故障 N 台 / 📰 事件 / 🏚 进入老化）。
3. **欠费/破产**：欠费期间 HUD 顶部常驻红色横幅（债务额 + 剩余抢救时间 timer_bar + 「看广告领救急金」CTA）+ 屏幕四缘 6u 红色 vignette 呼吸；Game Over 改全屏演出：机房群逐一熄灯（park_map 建筑 modulate 依次变暗，间隔 0.15s）→ 统计卡（存活天数/总收入/建成数/最高净值，数字滚动）→「重新创业」。
4. **商店 merchandising**（`_build_store_page`）：分区标题（限时特惠 / 钻石 / 永久权益）；钻石包卡加「+X% 加送”角标与单价锚点（$/💎），550 档标「最划算」丝带；已拥有权益卡整卡置灰 + ✓；底部合规行：恢复购买 / 隐私政策 / 服务条款（`OS.shell_open` 占位 URL，release_checklist 已有外部交付项）（修 O2/O5 商店侧）。
5. **设置页合规**（`_build_settings_page`）：加 隐私政策 / 服务条款 / 客服邮箱 / 版本号（`ProjectSettings.get_setting("application/config/version")`）四行（修 O5）。

**验收**：era/game_over/offline 三演出录屏人工验收；visual_smoke 更新 `era_unlock/game_over` 断言 + 新增 `store` 分区断言（三个 section 标题存在）；`check_release.py` 不回归。

---

### WP7 · 测试与门禁收口（预计 1 人日）

1. visual_smoke 状态表更新为约 24 态（上述新增全部入列），中英双语各跑一遍（进程参数 `--locale=en|zh_CN`，CI 两次调用）。
2. 新断言库：无 `×0.00`；无 tofu（glyph index 校验）；scroll 恢复（构造滚动→触发 tick→断言 scroll_vertical 不变）；触控 88u 门禁保留。
3. `docs/ios_ui_redesign.md` 与 `docs/architecture.md` 表现层段落同步更新（引用本文编号）。
4. 真机烟雾：iPhone 12 与 17 各一轮，60fps 定量检查（Xcode Instruments，园区 6 机房 + 金币飞行并发时不掉帧；掉帧则粒子降档：金币 ≤ 5、覆盖层改静态贴图）。

---

## 5. 新增本地化 key（追加到 `localization/ui.csv`，双语一次给齐）

```
ERA_SHORT, OPERATIONS_SHORT, UNLOCK_AT_ERA, UNLOCK_AT_NETWORK, MARKET_NO_HISTORY,
CONTRACT_PROJECTED, CONTRACT_CURRENT_BADGE, CONTRACT_CONFIRM_DELTA, CONTRACT_IN_SERVICE,
BOARD_POWER_USAGE, BOARD_OVERHEAT_HINT, BOARD_NEED_POWER, BOARD_PLACE_OK,
EVENT_STARTS_IN, EVENT_CHECK_MY_DC, ERA_NEXT_UNLOCKS, PRESTIGE_PROGRESS, PRESTIGE_EST_GAIN,
STORE_SECTION_DEALS, STORE_SECTION_GEMS, STORE_SECTION_PERKS, STORE_BEST_VALUE, STORE_BONUS_PCT,
SETTINGS_PRIVACY, SETTINGS_TERMS, SETTINGS_SUPPORT, SETTINGS_VERSION,
ARREARS_BANNER, GAME_OVER_RESTART, TUTORIAL_TAP_HINT
```

## 6. 新增资产（走既有 `art-renders → import_assets.py` 管线，均有程序化回退）

| ID | 规格 | 用途 | 回退 |
|---|---|---|---|
| ic_operations | 512², 写字板+齿轮 | 运营入口（修 M2） | ic_network |
| ic_pointer_hand | 512², 卡通手指 | FTUE | guide_normal 缩小 |
| plot_base | 768², 等距地垫/围栏 | 地块基座（修 M4） | 无（保持现状） |
| newspaper_bg | 1024², 报纸头版底 | 时代演出 | panel_main |
| ribbon_banner | 512×256, 标题丝带 | 卡片角标/最划算 | 纯色 chip |
| 字体 ×2 | Baloo 2 + Noto Sans SC (OFL) | 全局 | SystemFont 链 |

## 7. 里程碑与工作量汇总

| WP | 内容 | 预估 | 依赖 |
|---|---|---:|---|
| WP0 | 缺陷修复（jank/空态/术语/sheet） | 1d | — |
| WP1 | 设计系统 2.0 + 字体 | 2d | WP0 |
| WP2 | 世界反馈与 juice 基建 | 2d | WP1 |
| WP3 | 机房棋盘重做 | 3d | WP1 |
| WP4 | 合约/行情/科技信息化 | 2.5d | WP1（与 WP3 并行可） |
| WP5 | FTUE 聚光灯 | 2d | WP3（目标解析依赖棋盘） |
| WP6 | 高光演出 + 营收位 + 合规 | 1.5d | WP1 |
| WP7 | 测试收口 + 真机 | 1d | 全部 |
| 合计 | | **15d** | |

## 8. Codex 执行约束（必读）

1. **不许改玩法层**：`core/*.gd`、`gameplay/game_rules.gd`、`gameplay/market_system.gd`、`data/*.json` 一律只读（另一 session 正在其上工作；本计划所有数据展示均通过现有只读接口获得；确需新只读 helper 时在 UI 文件内实现，不进 core）。
2. **每个 WP 一个独立提交/PR**，提交前跑齐门禁：`python3 tools/validate_data.py`、`godot --headless --path . --scene res://tests/test_runner.tscn`、`godot --path . tests/visual_smoke.tscn`，全绿才算完成；WP 内新增断言随该 WP 提交。
3. **资产纪律**：只经 `AssetCatalog.texture(id)` 取图；新增 ID 先进 `assets/art/manifest.json` 与 §6 表；任何资产缺失必须有程序化回退且不 crash（现有铁律）。
4. **文案纪律**：所有玩家可见字符串走 `tr()` + `ui.csv` 双语；禁止硬编码中文/英文。
5. **布局纪律**：触控目标 ≥ 88u；只用 §3.1 的间距/字号/圆角档位；安全区行为不动（`_safe_area_margins`）。
6. **风险红线**：WP3 合并的抽屉不得超过一层 modal（棋盘 sheet 之上只允许 action sheet 一层）；FTUE 任何情况下不得锁死输入（目标缺失即退化）。
7. 与 `docs/06_gameplay_optimization_proposal.md`（玩法侧提案）并行不悖：本计划 WP4 的续约窗口/停机开关等 UI 已按该提案的接口（`renewal_window_end_at`、`set_rack_enabled`、`market_sensitivity`）对接，若玩法侧未合并则相应 UI 元素按现状降级显示。

---

## 9. 验收记录 · 2026-08-02 首轮执行复查

> 复查方法：重跑 `tests/visual_smoke.tscn`（22 态全绿）逐张比对 + 代码走读。结论：**首轮只完成计划的一小部分**（玩法接口 UI 化 + 世界层小改进 + 测试扩容），WP0–WP6 的主体未执行。下一轮按 §9.3 顺序补齐。

### 9.1 已完成（保留，不返工）

- 空地地垫 + 角旗 + 「+」气泡、待售地木牌（M4 部分修复）；
- 机房 ⚡ 未通电告警角标（WP2-4 雏形）；
- 合约 tab：锁定客户显示「未解锁」、续约窗口倒计时、「免费换约」标签（D5 部分修复）；
- 机柜格内景底图 + 状态文案（已停机/安装中）、机柜选购显示行情敏感度；
- visual_smoke 扩至 22 态（含 campus_mixed / rack_picker / rack_install_actions / rack_pause_actions）。

### 9.2 未完成清单（本表逐项对照后方可关闭）

| 计划项 | 状态 | 复查证据 |
|---|---|---|
| WP0-1 tick 整页重建 / 滚动重置 | ✅ 2026-08-02 | tick/offline 仅刷新 HUD/实时控件；玩家动作才重建页面；`PageScroll` 缓存恢复。自动测试以非零 240u 滚动跨 tick 验证节点 ID、位置与节点数均不变。 |
| WP0-2 锁定客户 ×0.00 | ✅ 2026-08-02 | 合约与行情页均改为时代/网络解锁条件；visual_smoke 同时扫描 Button 与 Label，禁止 `0.00`。 |
| WP0-3 行情图空态 | ✅ 2026-08-02 | 少于 2 个数据点时显示市场图标与本地化空态，不再绘制裸网格。 |
| WP0-4 运营中心状态点拉伸 | ✅ 2026-08-02 | 横纵 size flags 均锁为 `SIZE_SHRINK_CENTER`，Metal 截图确认为圆点。 |
| WP0-5 Sheet 退场动画 + 拖拽关闭 | ✅ 2026-08-02 | 世界/操作 Sheet 统一 0.2s 退场后释放；支持暗幕、关闭键、≥88u 把手下拽三路退出，回归测试覆盖输入路由与延迟释放。 |
| WP0-6 关闭按钮中性化 | ✅ 2026-08-02 | 移除红色 `ic_close`，统一深色按钮 + 白色 ×；危险色只留给破坏性操作。 |
| WP0-7 「T1」时代术语 | ✅ 2026-08-02 | HUD 使用本地化 `ERA_SHORT`（时代/Era）。 |
| WP0-8 死代码清理 | ✅ 2026-08-02 | 删除 `_build_map_page`、`_plot_card` 及失去调用方的 `_start_building`。 |
| WP0-9 圆形按钮标签/换图标 | ✅ 2026-08-02 | 建设/运营入口增加世界文字标签；`ic_operations` 缺失时按资产纪律回退 `ic_network`。 |
| WP1 字体打包 | ✅ 2026-08-02 | Baloo 2 + Noto Sans SC 可变字体及两份 OFL 已入库；全局 FontVariation 回退链与等宽数字字体启用；自动断言覆盖「稳/障/购/罄」。 |
| WP1 九宫格资产接入 / widgets.gd | ✅ 2026-08-02 | `panel_main/panel_dark/btn_*/dialog_bubble/progress_*` 已接入主题；新增统一组件工厂，按钮按语义角色选皮肤；HUD 资源条补 `+` 商店入口并保留 flat 回退。 |
| WP2 金币飞行 / 数字滚动 / 倒计时环 | ✅ 2026-08-02 | 新增独立 `FxLayer`：3/5/8 枚金币沿二次曲线飞向钱包并脉冲，粒子上限/释放有自动回归；现金/钻石 0.4–1.2s 等宽数字滚动；建设气泡补进度条、落成 dust+squash；故障/断电/过热/续约/退役世界告警支持直达。运营徽标、可负担 CTA 呼吸与四档触觉已接线。 |
| WP3 机房棋盘（冷却覆盖/电力条/放置预判） | ✅ 2026-08-02 | 新 `DatacenterBoard` 将 3×3 机柜、四边冷却槽与变压器合成空间棋盘；每台冷却器严格生成 3 格 frost 覆盖，双覆盖自然叠色；过热/故障/断电角标与分段式供电表可见。机柜选择补成本/耗电/发热/基础产出/玩家化行情特质，确认前 9 格均显示 ✓/⚠/⚡/占用态；长按显示运行 tooltip。情境抽屉已直接嵌棋盘并简化为棋盘/合约两层信息架构；自动验收覆盖“GPU 角格安全、中心过热”和 ≤60 节点预算。 |
| WP4 行情图例/坐标/事件卡、科技路线图、签约收益对比 | ✅ 2026-08-02 | 合约卡显示倍率趋势、C/S/G 适配、服务中状态与权威规则预估，确认 sheet 给出签前/签后/涨跌/违约费/合约期；行情页去重并加入四序列可点图例、参考线、现在标记、事件区间、24 点 sparkline、受影响客户倍率、计时条和直达合约 CTA，事件开始/结束均推入可点击横幅；科技页改为三时代路线图与下一时代解锁预览，转生卡补 X/20、经济公式倍率预估、保留/清算清单及 1.2s 长按二次确认。自动验收覆盖 UI 预估=权威收入公式、28 态 Metal 渲染和三档行情历史。 |
| WP5 FTUE 聚光灯 | ✅ 2026-08-02 | 旧横幅已由 `TutorialOverlay` 替换：四矩形静态暗幕挖洞、白色脉冲洞缘、手势浮动、`dialog_bubble` + 老高姿态、错误区域抖动与目标输入门控。8 类 focus 可解析主 CTA、建筑卡、棋盘供电/机位/制冷槽、客户卡、待售地、退役按钮；目标缺失时隐藏暗幕并切为 `MOUSE_FILTER_IGNORE` 纯气泡，保证永不锁死。步骤推进接 confetti/触觉/关键步金币；引导中隐藏新闻/任务/运营入口。自动验收覆盖目标相交与缺失目标降级，Metal 25 态通过。 |
| WP6 时代演出 / 商店分区 / 设置合规项 | ✅ 2026-08-02 | 时代升级替换为 `panel_main` 报纸头版旋入演出，含时代标题、三项解锁摘要、1.2s 钻石滚动、背景双喷彩屑与延迟/跳过确认；离线收益改为专用结算卡、金币堆、收益滚动、图标大事记与 `btn_ad` ×2 主营收位；欠费改为常驻债务/抢救倒计时/广告 CTA 横幅和红色呼吸 vignette，破产加入园区逐栋熄灯、四项统计卡与重启演出；商店按特惠/钻石/永久权益分区，补加送、单价、550 最划算、已拥有态及合规底栏；设置补隐私/条款/支持/版本，并新增本地双语服务条款。103 项核心测试与 30 态 Metal 视觉门禁通过。 |

### 9.3 首轮引入的新问题（随下一轮一并修）

1. ✅ **术语暴露**：已改为「随行情波动 / 均衡收益 / 收益稳定」三档玩家语言；原百分比仅保留在运行数据层。
2. ✅ **机柜选购信息不足**：选项与二次确认均显示成本、耗电、发热、基础产出，并联动棋盘预判。
3. **中文文案冻结令**：字体打包（WP1）完成前，禁止再新增含生僻/非常用汉字的 UI 文案——每条新文案都可能产生新 tofu。

### 9.4 下一轮执行顺序（严格按序）

```
① WP0 全部剩余项（含 9.2 表中 ⚠️/❌ 的 WP0 行）
② 字体打包 + WP1 设计系统（视觉杠杆最大的一步）
③ WP2 juice 基建
④ WP3 机房棋盘
⑤ WP5 FTUE 聚光灯
⑥ WP4 + WP6 + WP7 收尾
```

每步完成后重跑 22 态 visual_smoke 并对照 9.2 表逐项打钩；②完成时必须附一张 map + dc_racks + store 的前后对比截图供所有者确认方向。
