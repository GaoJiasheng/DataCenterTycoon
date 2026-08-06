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
