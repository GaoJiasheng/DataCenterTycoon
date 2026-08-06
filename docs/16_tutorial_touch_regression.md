# 16 · 新手教程触摸通关回归

> 生成于 2026-08-06。触发：build 2 上线后，所有者报告「新手教程还是会有非常多的错误」。
> **本轮的方法论转折**：此前所有 harness（`flow_audit` / `midgame_audit` / `visual_smoke`）都用 `main.call("_show_rack_picker", ...)` 之类**直接调用内部方法**来推进流程。这正是它们全绿而真机走不通的原因——**它们从未验证「点下去会不会有反应」**。
> 新增 `tests/tutorial_playthrough.tscn`：只允许在聚光灯自己给出的 target 上**注入真实触摸事件**，必须靠点击走完全部 8 步。任何一步点不动即失败。

---

## 1. 关于模拟器

所有者要求用本地模拟器回归。实测**不可行**，原因已定位到具体位：

Godot 4.7 iOS 导出模板的 `DataCenterTycoon.xcframework/ios-arm64_x86_64-simulator/libgodot.a` 的 Info.plist 声称支持 `arm64 + x86_64`，但 `lipo -info` 显示实际是 **Non-fat x86_64 单架构**。因此：

- 用 arm64 构建 → `Undefined symbols for architecture arm64: _main`；
- 改用 `-arch x86_64` → **构建成功**，但安装到 iOS 26 模拟器被拒：`Failed to find matching arch`（新版模拟器只接受 arm64）。

两端不可能对上，除非自行编译 Godot iOS 模板（数小时）。改用**桌面窗口 + 合成触摸**取得等价甚至更强的证据：同一套 UI 代码与输入路由，且可重复、可入 CI、能精确定位卡点。

---

## 2. 本轮发现并修复的缺陷（全部为「点了没反应」类）

| # | 缺陷 | 根因 | 影响 |
|---|---|---|---|
| **T1** | 弹层替换时新弹层「消失」 | 选机柜会先 `_dismiss_action_sheet`（0.2s 退场动画）再开确认弹层。两者并存期间新弹层与旧弹层**重名**，Godot 静默把新节点改名 → 所有 `find_child("ActionSheetOverlay")` 只能找到**正在退场的旧弹层** | 教学把聚光灯钉在旧弹层的选项位置，确认按钮不在高亮内；flow_audit 的同名断言一并失准 |
| **T2** | 教学步骤与抽屉 tab 不同步 | `cooling` 步要求安装风冷，但上一步 `contract` 把详情界面留在「签订合约」tab，冷却插槽根本不在屏幕上；目标解析找不到 `Cooler_*` 又拿不到世界建筑矩形，于是**静默降级为 dormant** | 玩家看到「先安装风冷设备」，却没有任何高亮，也找不到入口——**教程在此彻底断链** |
| **T3** | 引导 action 持有已释放控件 | 目标 action 闭包捕获裸控件引用；页面/抽屉在解析与点击之间重建后，Godot 报 `Lambda capture at index 0 was freed` 并传 null，`is_instance_valid` 挡住崩溃但**动作静默不执行** | 玩家点高亮区域，什么都不发生 |

修法：
- **T1**：`_animate_sheet_dismiss` 一旦标记 `dismissing` 就**立即让出名字**（改名 `Dismissed*`），新弹层因而始终能拿到规范名字；`_topmost_action_sheet()` 另取最新且未退场的弹层，确认弹层的 `Choice_confirm` 优先于按 focus 的映射。
- **T2**：新增 `TUTORIAL_DRAWER_TABS` 映射，解析目标前把详情界面切到该步所需的 tab。
- **T3**：改为按**节点名在点击时重新查找**，UI 重建后依然命中；同时导出 `target_node` 便于诊断。

---

## 3. 通关实测（触摸驱动，8/8 步）

```
welcome    → 点主 CTA → 选 T0 卡片 → 开工
power      → 点建筑 → 抽屉 → 供电插槽 → 变压器T1        等待 300s
first_rack → 机柜插槽 → 计算机柜 → 确认$300              等待 120s
contract   → 合约 tab → 互联网厂商
cooling    → 自动切回机柜 tab → 冷却插槽 → 风冷T1        等待 300s
buy_plot   → 世界待售地块
retire     → 休眠角标，机房老化到 60% 后唤醒（约 14 游戏小时）
standard   → 建标准机房 → 教程完成
```

`PLAYTHROUGH: PASS`。

### 3.1 节奏观测（非缺陷，供决策）

触摸通关记录到三处**真实等待**：供电 300s、机柜 120s、冷却 300s，合计 **12 分钟**现实时间。所有者此前已拍板教学期 T0 建设 300s→30s（15 号文档 FT4），但**附件与机柜的安装时长未纳入该决策**。若希望首日节奏紧凑，建议同样为教学期设置缩短值；否则新玩家在前 8 步里要静等 12 分钟。**此项需所有者拍板，未擅自改动数值。**

---

## 4. 门禁

`tests/tutorial_playthrough.tscn` 应纳入 CI，与既有门禁并列。它是唯一能拦住「引导指向的东西点不动」这类缺陷的测试。

```
python3 tools/validate_data.py
python3 tools/check_assets.py --strict --audio
godot --headless --path . tests/test_runner.tscn
godot --headless --path . tests/flow_audit.tscn
godot --headless --path . tests/midgame_audit.tscn
godot --disable-vsync --max-fps 60 --path . tests/tutorial_playthrough.tscn   # 需窗口以路由输入
```

本轮全部通过：数据 11 表 / 资产 152+6+23 / 逻辑 103 / flow / midgame / **touch playthrough**。

---

## 5. 追加缺陷 T4 · 教学步骤与其依赖对象脱节（2026-08-06，所有者实测）

所有者在桌面窗口截到：教练气泡说「施工中 · 剩 0s。建成后安装变压器。」，但世界上**没有任何工地或建筑**，三块地垫全空，气泡也没有指向任何目标。

### 现场存档

`save_v1.json` 实测：

```
tutorial.step      = 1        (供电步)
construction_queue = []       ← 队列为空
plot_1.status      = empty    ← 没有机房
sim_seconds        = 298549   ≈ 3.45 游戏天
```

机房早已因老化消失（T0 寿命仅 1 游戏天），而教学仍停在依赖它的那一步。

### 根因

`_resolve_tutorial_target()` 的 waiting 分支只判断「有没有机房」，**不判断「是不是真的在建」**：

```gdscript
var dc_id := _tutorial_datacenter_id()
if dc_id.is_empty():
    return {... "source": "construction_wait", "mode": "waiting"}   # 无条件
```

而 `_tutorial_waiting_copy()` 在队列里找不到施工项时 `remaining` 保持 0.0，仍然无条件套用「施工中 · 剩 %s」文案 —— 于是「剩 0s」。三种完全不同的状态（正在建 / 已老化消失 / 从未建成）被压进同一个分支，后两种就此**永久卡死且文案撒谎**。

### 修复

- 新增 `_tutorial_site_under_construction()`：只有队列中真有 datacenter 项、或有地块处于 `building` 状态时才算在建；
- 目标解析区分三态：**在建** → waiting（文案属实）；**不存在** → 指向主 CTA 的可点「重建」引导，文案「机房不在了，先重新建一座。」；**连 CTA 都不可用** → 非阻塞气泡；
- `_set_tutorial_chrome_visibility` 在 rebuild 场景放行主 CTA（该 focus 平时会隐藏它）。

### 门禁

`tutorial_playthrough` 增加 `_verify_orphaned_step_recovers()`：直接构造所有者那个存档形态（step=1、空队列、无机房），断言 ① 文案不得声称施工中 ② 目标来源为 `rebuild` ③ 可点。

同时更新 `test_runner` 中一条旧断言 —— 它原本要求「目标缺失时退化为非阻塞气泡」，正是这次卡死的行为。改为要求路由回重建。

全量门禁：`test_runner` 103/103（连跑两次）、`flow_audit`、`midgame_audit`、`visual_smoke` zh/en 各 31/31、`tutorial_playthrough` 全部通过。

---

## 6. 教学期时长收敛（2026-08-06，所有者拍板）

§3.1 测得的 12 分钟静等已按所有者决定一并缩短。沿用 15 号文档 FT4 为 `dc_t0` 建立的模式，把覆盖值扩展到教学实际走到的三件安装物：

| 物件 | 正常时长 | 教学期 |
|---|---:|---:|
| 集装箱机房 `dc_t0` | 300s | 30s（既有） |
| 变压器 `power_t1` | 300s | **20s** |
| 计算机柜 `rack_compute_t1` | 120s | **20s** |
| 风冷 `cool_air_t1` | 300s | **20s** |

首日总等待 **12 分钟 → 90 秒**，落在放置类「90 秒内点亮第一座机房」的节奏区间内。

### 作用域与防泄漏

新增 `Game._tutorial_duration(entry, override_key, fallback)`：教学完成后一律返回原值，且**只有教学实际引导的那几个 id 带覆盖字段**——玩家在教学期购买 T2 变电站等更高阶物件不会获得加速。

`tutorial_playthrough` 增加 `_verify_shortened_timings_are_tutorial_only()`：断言 ① 出厂 `install_seconds` 仍为 300/300/120 未被改写；② 覆盖值必须小于正常值；③ `completed=true` 时权威接口交还完整时长、`false` 时用缩短值。这防止缩短值日后悄悄泄漏进正常玩法、改写经济模型赖以平衡的节奏。

### 回归

`simulate_economy` 三策略 30 天曲线与调平前一致（idle 4 座 / active 12 座 era3 / aggressive 12 座，破产率 0%，两条既有 TUNE 提示不变，见 `balance_report.md`）；`test_runner` 103/103；`flow_audit`、`midgame_audit`、`check_assets` 全绿；`tutorial_playthrough` 实测三处等待各 20s。
