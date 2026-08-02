# 09 · 全量 UI 审计与整改清单（含素材重做）

> 生成于 2026-08-03。方法：最终 PASS 版本（30 态视觉回归 + 103 逻辑测试全绿）的全部截图逐屏人工审查 + 关键区域放大取证。
> 定位：08 号文档的几何/排版层问题已修复完毕；本文档是**逐屏细节整改 + 素材重做**的执行清单，是上线前 UI 侧的最后一轮系统性打磨。
> 执行约束沿用 07§8（不动玩法层、每步过门禁、双语文案、资产回退）与 08§2 五条铁律。素材重做走 `art-renders → tools/import_assets.py` 既有管线，prompt 按 03_art_spec 规范用英文书写。

---

## 1. 全局性问题（G 系列，优先修——一处修复全局收益）

### G1 · 光泽主 CTA 的文字可读性（本轮最高优先级，出现 ≥5 处）

「建造机房」「购买下一块地·$775」「确认·预计$257/月」「领取救急金」「领取」——所有 btn_primary 光泽药丸上的文字都难读。两个叠加原因：

1. **调用点把金额段染成黄色**（如「·$775」黄字压亮绿高光）。整改：光泽按钮文字**一律单色白 + 28u 粗体 + 4px ink 描边**，金额并入同一样式，禁止分段染色。排查所有 `_button`/`Widgets.button` 调用点中含 `$`、`·` 的 primary 文本。
2. **素材高光带太亮太宽**（btn_primary 顶部 40% 是接近纯白的黄绿色）。→ 素材重做 A1。素材到位前的代码级缓解：`art_button_box` 给文字加 `shadow_color=ink, shadow_offset=(0,2)`，并把 `modulate_color` 压到 `Color(0.92,0.92,0.92)` 降低整体亮度。

### G2 · 飞行金币定位/生命周期 bug

- `map_built` 态：一堆金币悬浮在建筑上方约 120u 的空草地上（起点世界坐标换算错误，`world_position_of` 返回的应是建筑中心而非包围盒上方）；
- `market_empty` 态：两枚金币残留在行情页面板中间（页面切换时 FxLayer 未清空在途金币）。

整改：`fx_layer.gd` 增加 `clear()`，`_navigate`/页面重建时调用；`park_map.world_position_of` 锚定建筑贴图中心偏上 30u；金币飞行目标为 HUD 现金 chip（当前疑似飞向错误坐标后停滞）。

### G3 · 「可负担」状态无高亮

科技页「升级 100G 接入·$8.0K」在现金 $39.2K 时仍是灰蓝按钮。放置类惯例:买得起的升级按钮 = 绿色 + 轻微呼吸脉冲，买不起 = 灰蓝 + 显示差额。整改点：科技页两个升级钮、建筑选卡、附件/机柜选购项，统一走一个 `affordable_style(button, cost)` 辅助（`ui/widgets.gd`）。

### G4 · 底部圆形入口按钮的标签不可读

任务/运营两个 96u 圆钮内部塞了 ~14u 的文字标签，完全看不清。整改：标签移出按钮，放按钮正下方独立 Label（18u、白字 ink 描边 3），圆钮内只留图标 48u；徽标保持右上角。

### G5 · FTUE 暗幕与指针档次

- 暗幕 0.55 在明亮草地上对比不足 → 提到 **0.62**；
- 程序化箭头（白方块+黄三角）能用但简陋 → 正式资产 `ic_pointer_hand`（A4），素材到位前把箭头改为圆角胶囊柄 + 平滑三角头并加 6u ink 描边（Polygon2D 抗锯齿开）。

### G6 · 英文回归缺失

本轮 30 态只跑了 zh_CN。英文文案普遍更长（如 "Buy Next Plot · $775"），溢出风险高。整改：`--locale=en` 跑一遍 30 态，修掉所有英文态断言失败与省略号溢出，此后 CI 双语各跑一次。

---

## 2. 逐屏问题清单（U 系列）

> 按截图状态逐条列出。「修法」精确到文件/函数。P0=必修，P1=应修，P2=可选增强。

### U1 · map / map_built（世界主屏）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | CTA 金额黄字（G1） | 见 G1 |
| P0 | 金币堆悬空（G2） | 见 G2 |
| P0 | 圆钮标签不可读（G4） | 见 G4 |
| P1 | 建成机房（dark 态）在草地上无接地投影，像浮空 | park_map 给每座建筑底部绘制程序化椭圆阴影（`Color(0,0,0,0.18)`，宽=贴图宽×0.72，压扁 0.32），素材不用改 |
| P2 | 运营中的机房无「正在赚钱」表达 | 每 30s 金币动线已有（G2 修复后生效）；另加烟囱式 LED 闪烁 modulate 循环 |

### U2 · campus_dense（多机房园区）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | **建筑视角混乱**：T0 是 3/4 等距、T1 是俯视扁平、T2 正视两层楼、T3 圆筒仓；三座 T2/T3 几乎一样造成重复感；接地阴影有无不一 | 素材重做 A2（本文档最大的素材项） |
| P1 | 已建成地块看不到地垫（空地才有水泥基座） | park_map：所有已购地块统一先画基座，建筑坐在基座上（基座贴图已有，代码层调整绘制顺序） |
| P1 | 建筑几乎贴着排，无间距韵律 | park_map 布局常量：列间距 +24u、行间距 +32u |

### U3 · world_alerts（世界告警）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 告警角标是静态深底圆，可点性弱 | 角标加 scale 1↔1.08 呼吸（1.2s）+ 白描边 2u |
| P1 | 建筑无接地投影（同 U1） | 同 U1 |

### U4 · ftue_spotlight

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 暗幕对比不足、CTA 文字难读（G1/G5） | 见 G1/G5 |
| P1 | 箭头风格简陋（G5） | 见 G5 |

### U5 · dc_context（世界抽屉）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 未通电时「签订合约」按钮呈禁用样但无原因 | 点击 toast「先安装变压器」；按钮副文案加一行 20u 提示 |
| P2 | 空机位与锁定格首见区分度靠猜 | 空格中心加 40u 半透明「+」icon |

### U6 · dc_board（机柜棋盘）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 安装中机柜无倒计时（只有橙色高亮），且橙色 glow 溢出到相邻格 | 格内加迷你 `timer_bar`（宽=格宽-16）；glow 改为格内 4u 内描边，删除外发光 |
| P0 | 北侧冷却插槽 icon 出现「蓝盒+雪花」两图标叠绘 | 排查 `datacenter_board._add_coolers`：已装冷却器时应只画冷却器贴图，空位只画雪花；疑似两分支都执行 |
| P1 | 计算机柜 T1 贴图黑色，在深色格底上几乎看不清 | 素材重做 A7（机柜提亮）；短期代码缓解：格底提亮为 `Color("18293c")` |

### U7 · dc_board_overheat

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | **过热火焰特效喷到相邻格甚至棋盘外**，像整排着火 | 过热表达改为：该格底色转橙（alpha 0.35）+ 右上 40u 热icon + 格内 4u 橙描边；火焰贴图如保留必须 `clip_contents` 在本格内且缩到 0.6 格宽（A8） |

### U8 · dc_board_placing（放置预判）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 九格几乎全部同样的橙 ⚠（锁定/占用/过热未分级），预判失去意义；徽章 56u 过大且居中遮挡格子内容 | 分级重做：可放=绿✓ / 会过热=橙🌡 / 电力不足=红⚡ / 占用与锁定=不显示徽章只降饱和；徽章缩到 40u、右上角贴角 |

### U9 · rack_picker（机柜选购）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 选项无机柜缩略图 | 每项左侧加 64u 机柜 icon（`rack.asset_prefix + "_active"`） |
| P1 | 「均衡收益/收益稳定」文字下有绿色下划线状残留 | 排查 `_rack_market_label` 是否用了 BBCode/underline；改纯 Label |

### U10 · contract_comparison

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 确认按钮文字（G1） | 见 G1 |

### U11 · operations —— ✅ 达标，无整改项

### U12 · construction_queue

| 优先级 | 问题 | 修法 |
|---|---|---|
| P2 | 进度为 0 时进度条全空 | 最小填充 3%；右侧加百分比文字 |
| P2 | 广告按钮双行 20u 偏小 | 改单行「看广告 -30m（0/2）」24u |

### U13 · rack_install_actions / rack_pause_actions

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 状态副标（已停机/安装中）无状态色；按钮无主次 | 副标着状态色（停机=灰、故障=红、安装=橙）；首选操作（恢复运行/派修）用 primary 样式 |

### U14 · market_empty / market_active / market_rich

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 空态面板上残留飞行金币（G2） | 见 G2 |
| P1 | 活跃事件卡沉在页面底部，首屏看不到 | 「正在发生」区移到图表卡正下方、客户走势之上 |
| P2 | 空数据时走势卡无 sparkline 区域留白 | 显示灰色「—」占位线 |

### U15 · tech（科技/时代路线图）

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 可负担升级不高亮（G3） | 见 G3 |
| P1 | 「云计算时代」节点文字换行挤压 | 节点卡加宽至 118u 或字号降到 18；两行内必须完整显示 |
| P2 | 时代三 icon 风格不统一、托管时代辨识弱 | 素材重做 A6（可选） |

### U16 · achievements

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 无进度显示（如 3/10），全锁定态无差别 | 卡片加进度条或「x/y」数字（数据源 `achievement.metric` 现值） |
| P2 | 「5 钻石」纯文字 | 前置 24u 钻石 icon |

### U17 · store

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 购买钮文字（G1） | 见 G1 |
| P1 | 「US$1.99」白字灰底按钮与「最划算」绿光泽钮混排，层级颠倒（非最划算档反而更朴素合理，但两种购买钮样式不统一） | 统一：所有价格钮=绿 primary；「最划算」用丝带徽章区分而非按钮样式 |

### U18 · settings

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 法律三行看不出可点（无 chevron/下划线），行距不均 | 每行右侧加「›」20u；统一行高 88u + 1px 分隔线 |

### U19 · arrears

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | 「领取救急金」按钮文字（G1） | 见 G1 |

### U20 · offline_reward

| 优先级 | 问题 | 修法 |
|---|---|---|
| P0 | **数值语义冲突**：大数字 $10.0K，文案「赚了 $12.8K」——玩家会以为少发钱 | 若 10.0K 是离线上限内到账、12.8K 是全额：文案改「离线全额 $12.8K，8 小时上限内到账 $10.0K（升级可扩至 24h）」并顺势变成扩容 IAP 的入口；若同值则修 bug |
| P0 | 「领取」按钮文字（G1） | 见 G1 |

### U21 · era_unlock

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 标题「云计算时代 来临！」多余空格 | 修 `ERA_ARRIVE` 文案 key（双语核对） |
| P1 | 「100 钻石」纯文字，奖励感弱 | 钻石 icon 40u + 紫色圆角色块包裹 + 数字滚动 |
| P2 | 报纸底无纹理 | 素材 A5 `newspaper_bg` |

### U22 · game_over

| 优先级 | 问题 | 修法 |
|---|---|---|
| P1 | 「公司破产」28u 太轻；「重新创业」暗红底文字对比不足 | 标题 44u display 粗体；按钮改 danger 红底白字 28u 描边 4 |
| P2 | 无「熄灯」演出（静态弹窗） | park_map 依次 modulate 变暗（间隔 0.15s）后再弹结算，08§4.8 原规范 |

---

## 3. 素材重做清单（A 系列，英文 prompt 按 03_art_spec 风格规范）

| # | 资产 | 优先级 | 说明 |
|---|---|---|---|
| A1 | `btn_primary/secondary/warning/danger/ad/disabled`（6 张 512×256） | **P0** | 高光带压暗收窄；文字区留纯色面 |
| A2 | 建筑全套 `dc_t0..t3 × 6 状态`（24 张） | **P0**（工程量最大） | 统一 3/4 等距视角、统一底座与投影、拉开造型差异 |
| A4 | `ic_pointer_hand`（512²） | P1 | FTUE 手指 |
| A5 | `newspaper_bg`（1024²） | P2 | 时代演出报纸底 |
| A6 | `ic_era1/2/3`（512²×3） | P2 | 统一风格 |
| A7 | `rack_compute_t1/t2` 提亮重生成 | P1 | 深底可见性 |
| A8 | `fx_flame_cell`（256²，格内小火苗） | P2 | 替代溢出火焰 |

**A1 prompt（六张同模板换色）：**
> Mobile game UI button, nine-slice friendly rounded pill, 512x256, cartoon casual style matching Hay Day. Matte {COLOR} surface with soft top-to-bottom gradient (top only 12% lighter than base — NO bright glossy highlight band), subtle 3px darker rim, 14px darker bottom bevel for depth. Center area must be a clean flat color field suitable for white text overlay. Rounded end caps with 70px radius. Transparent background, no text, no icons.
> COLOR: primary=fresh grass green #6fbf44 / secondary=sky blue #3a9de0 / warning=warm orange #f08a3c / danger=soft red #e25555 / ad=violet #8f63e8 / disabled=blue-gray #55677c

**A2 prompt 模板（24 张，`{TIER_DESC}`/`{STATE_DESC}` 逐张替换）：**
> Isometric 3/4 top-down view (30° elevation, facing lower-left, consistent across the whole set), single cartoon data center building for a mobile tycoon game, Hay Day-like rounded shapes and saturated colors, main color blue. {TIER_DESC}. {STATE_DESC}. Sitting on a light concrete foundation slab with a soft elliptical ground shadow baked at the base. Crisp silhouette, transparent background, centered, fills 85% of canvas.
> TIER_DESC — t0: "small shipping-container server room with a rooftop antenna" / t1: "single-story server hall with three cooling vents and a glass door" / t2: "two-story data center with a rooftop AC array and logo plate" / t3: "hyperscale campus block with twin cooling towers and cable trays"
> STATE_DESC — construction: scaffolding + crane / active: warm window glow, subtle LED strip / dark: unlit gray-blue, no glow / aged: rust streaks, faded paint / decayed: cracked walls, dark smoke stains / ruin: collapsed roof, debris
> 尺寸沿用 manifest（t0/t1=768²、t2=1024²、t3=1280²）。**验收：四个 tier 并排摆放时视角、地基、影子完全一致，且轮廓差异一眼可辨。**

**A4 prompt：**
> Cartoon hand cursor with pointing index finger, 3/4 view angled down-left, chunky rounded style, warm skin tone with blue sleeve cuff, thick dark navy outline, soft drop shadow, 512x512, transparent background, reads clearly at 96px.

素材未交付期间一律保留现有程序化回退；A1/A2 交付后跑 `tools/import_assets.py --visual` + `check_assets.py --strict` + 全量视觉回归。

---

## 4. 执行顺序与验收

| 批次 | 内容 | 预估 |
|---|---|---:|
| ① | G1–G5 全局修复 + U 表全部 P0（代码侧） | 1.5d |
| ② | U 表 P1 全量 | 1.5d |
| ③ | G6 英文 30 态回归修复 | 0.5d |
| ④ | A1 按钮素材重做 → 接入 → 回归 | 0.5d（生成）+0.5d |
| ⑤ | A2 建筑素材重做 → 接入 → 回归（可与①②并行生成） | 1d 接入 |
| ⑥ | P2 择机；真机双语人工过一遍全部 30 态 | 0.5d |

每批次独立提交；门禁 = `validate_data.py` + test_runner + 双语 visual_smoke 全绿。批次①完成后必须出 map / dc_board_placing / store 三屏前后对比图存 `docs/ui_review/`。

**最终验收标准（所有者亲测）**：桌面自适应窗口过一遍全部页面——① 没有任何一处文字难读或被遮挡；② 每屏 3 秒内能找到「现在该点什么」；③ 世界层建筑风格统一、有接地感；④ 金币动线从建筑到钱包完整可见。

---

## 5. 执行验收记录

### 批次① · G1–G5 + P0 代码侧（2026-08-03）

- [x] G1：主 CTA 统一为单行白字、28u 粗体、4px ink 描边与 2u 字影；A1 到位前将旧按钮素材整体压暗至 0.92。
- [x] G2：页面导航清理在途金币；起点改为建筑贴图中心上偏 30u，终点固定到 `CashResource`。
- [x] G3：新增 `Widgets.affordable_style(button, cost)`；科技升级、建筑选卡、附件与机柜选购统一显示可负担呼吸态/不足差额态。
- [x] G4：任务与运营入口的标签移出圆钮，圆钮仅保留图标与右上角徽标。
- [x] G5：暗幕提高至 0.62；程序化指针改为抗锯齿胶囊柄 + 三角头 + 6u ink 双层轮廓。
- [x] U6/U7/U8：补机柜格内倒计时、冷却器单分支绘制、过热格内收束，以及绿/橙/红/隐藏四类放置预判。
- [x] U10/U14/U15/U17/U19：通过 G1–G3 的统一契约关闭对应 P0。
- [x] U20：移除滚动大数字旁重复的终值金额，改为已结算时长与上限说明，避免动画中出现“少发钱”的语义错觉。
- [ ] U2/A2：属于素材批次⑤，保留现有回退，待 24 张同视角建筑状态图交付后关闭。

门禁：`validate_data.py` 通过；`test_runner` 103/103；`visual_smoke` zh_CN 30/30、en 30/30。

三屏对比：

- `docs/ui_review/09_batch1_compare_{en,zh_CN}_map.png`
- `docs/ui_review/09_batch1_compare_{en,zh_CN}_dc_board_placing.png`
- `docs/ui_review/09_batch1_compare_{en,zh_CN}_store.png`

### 批次② · U 系列 P1 全量（2026-08-03）

- [x] U1/U2/U3：建筑统一增加地块基座与 0.18 椭圆投影，园区列距 +24u、行距 +32u；世界告警增加 1↔1.08 呼吸和 2u 白描边。
- [x] U4/U5/U6：保留 G5 高质量程序化指针回退；未通电合约入口增加原因提示与 toast；机柜格底提亮至 `#18293c`。
- [x] U9/U13：机柜选项增加 64u 实物缩略图；安装/停机/故障副标使用语义色，恢复运行与派修成为首选主操作。
- [x] U14/U15/U16：活动卡移至图表正下方；时代节点以 170u + 18u 双行完整显示；九张成就卡全部增加当前值/目标值与进度条。
- [x] U17/U18：商店价格按钮统一 primary，最划算改为独立丝带；法律三行统一 88u、1px 分隔与右侧 chevron。
- [x] U21/U22：时代标题去除中文多余空格，钻石奖励改为图标色块与滚动数字；破产标题使用 display 粗体，重开按钮升级为 28u/4px 高对比 danger。

门禁：`validate_data.py` 通过；`test_runner` 103/103；`visual_smoke` zh_CN 30/30、en 30/30。P1 对应视觉断言已加入 `tests/visual_smoke.gd`，后续回归不再只依赖人工目测。
