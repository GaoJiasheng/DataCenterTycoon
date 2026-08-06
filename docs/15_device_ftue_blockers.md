# 15 · 真机 FTUE 阻断级缺陷与修复方案

> 生成于 2026-08-04。触发：所有者在 TestFlight build 1.0.0(1) 上实测，新手引导**无法完成**。
> 取证方法：① 所有者真机截图（供电选择步、机柜选择步）；② 桌面 `tests/flow_audit.tscn` 逐帧复现——`s1_power_picker_sheet` 与真机截图**像素级一致**，证明是共享代码路径缺陷而非设备差异；③ 打包字体 cmap 静态分析（自研脚本，见 §2.3）。
> 模拟器验证未采用：Godot release 导出模板的 `ios-arm64_x86_64-simulator` slice 缺 `_main` 符号（导出模板限制），改用桌面复现 + 静态分析取得同等强度证据。
> **本文档全部为 P0 阻断项，优先级高于 14 号中期循环打磨。**

---

## 1. 核心结论

两个独立缺陷叠加，使新手引导在**第 2 步（安装变压器）就断链**：

| # | 缺陷 | 性质 | 后果 |
|---|---|---|---|
| **D1** | 教学聚光灯没有「弹层选项」这一阶段的目标解析 | 共享代码，桌面同样复现 | 引导指向空白/已消费的控件，玩家无从下手；机柜步形成**点击死循环** |
| **D2** | 打包字体缺 `⚡ ♨ ❄ 🔒 📈 ⚠` 字形 | **真机专属**（桌面有系统 fallback 掩盖） | 所有图标化数值退化成裸数字，如「⚡2 ♨2 $90/月」→「2  2  $90/月」，信息不可读 |

---

## 2. 根因分析（逐条实锤）

### 2.1 D1-a · 目标解析缺第三阶段

13 号文档确立了两段式目标（世界建筑 → 抽屉控件），但**弹层（ActionSheet）里的选项按钮从来没有成为过目标**。

`ui/main_view.gd::_resolve_tutorial_target()` 的 `install_power` 分支只有一句：

```gdscript
"install_power": control = _visible_control_named("PowerSlot")
```

抽屉里的 `PowerSlot` 被玩家点击后，选择弹层滑出并覆盖它——但解析器**仍然返回 PowerSlot 的矩形**。

### 2.2 D1-b · 可见性判断不含遮挡

`_visible_control_named()` 用 `control.is_visible_in_tree()` 作为唯一判据。被更高 z 层完全遮住的控件，这个判据依然为 `true`：

```gdscript
func _visible_control_named(node_name: String) -> Control:
	for node: Node in find_children(node_name, "", true, false):
		var control := node as Control
		if control != null and control.is_visible_in_tree():   # ← 无遮挡感知
			return control
	return null
```

叠加 z 层关系，后果被放大：

| 层 | z_index |
|---|---:|
| ActionSheetOverlay | 90 |
| **TutorialSpotlight** | **98** |

教学暗幕画在弹层**之上**，而「洞」开在被遮住的抽屉控件位置 → **整个弹层被压暗，唯一的亮区却是一块无关区域**。这正是真机截图 1 与桌面 `s1_power_picker_sheet` 的画面。

> 注：`_present_action_sheet` 里确实有 `call_deferred("_refresh_tutorial")`，所以**不是没刷新**，而是刷新后解析出的仍是同一个错误目标。修复必须落在解析逻辑，加刷新时机无效。

### 2.3 D1-c · 机柜步的点击死循环（最致命）

真机截图 2：聚光灯高亮 `RackSlot0`，而该槽位在弹层上方**仍然可见可点**。玩家按引导点击 → 再次调用 `_show_rack_picker` → 又叠一层弹层 → 目标不变 → **无限循环**。这就是「完全无法测试」的直接机制。

### 2.4 D2 · 字体字形缺失（真机专属）

打包字体的 cmap 覆盖实测：

| 字体 | 缺失字形 |
|---|---|
| ResourceHanRoundedCN-Medium/Bold/Heavy | `⚡ ♨ ❄ 🔒 📈 ⚠` |
| Baloo2-Variable | `⚡ ♨ ❄ 🔒 ✓ 📈 ⚠` |

- **桌面为何正常**：macOS CoreText 自动回退到系统符号/emoji 字体，把问题掩盖了；
- **iOS 为何失效**：包内字体是唯一来源，无回退 → 渲染为空白；
- **门禁为何没拦住**：12 号文档建立的 tofu 断言只校验 `localization/ui.csv` 的字符覆盖，而这些符号是**代码里硬编码的字符串字面量**：

```
ui/main_view.gd:2232   "%s · $%s\n⚡ %s   ♨ %s   $ %s/%s\n%s"
ui/main_view.gd:2696   "⚡ %s"  /  "❄ %s · ▦ 3"
ui/datacenter_board.gd:510  "%s\n⚡%s  ♨%s  ❄%s  $%s"
ui/datacenter_board.gd:92/340  "⚡" / "♨"
ui/main_view.gd:1250/1447  "🔒 %s" / "🔒" / "✓"
```

---

## 3. 修复方案

### 3.1 F1 · 目标解析升级为三阶段（P0）

**现有基础设施可直接复用**：弹层选项按钮已有稳定命名 `Choice_<id>`（`_present_action_sheet` 第 2822 行），无需新增命名层。

在 `_resolve_tutorial_target()` **最前面**插入弹层优先分支：

```gdscript
# 弹层是最顶层的交互面。它一旦打开，教学目标必须落在它内部，
# 否则暗幕会盖住玩家唯一能操作的区域。
var sheet := find_child("ActionSheetOverlay", true, false) as CanvasItem
if sheet != null and sheet.is_visible_in_tree():
    var preferred := {
        "install_power":    "Choice_power_t1",
        "rack_slot_0":      "Choice_rack_compute_t1",
        "install_cooler":   "Choice_cool_air_t1",
    }.get(focus, "") as String
    var option := sheet.find_child(preferred, true, false) as Control if not preferred.is_empty() else null
    if option == null:
        option = _first_enabled_choice(sheet)      # 兜底：弹层内第一个可用选项
    if option != null:
        return {"rect": option.get_global_rect(), "action": ..., "source": "sheet_option", "mode": "actionable"}
    return {"rect": Rect2(), "action": Callable(), "source": "sheet_unmapped", "mode": "dormant"}
    # 未映射的弹层：退化为纯气泡，绝不把洞留在弹层外
```

同时给 `_visible_control_named()` 增加遮挡判据：控件矩形若被任一可见的、z 更高的全屏 overlay 覆盖，视为不可见。

### 3.2 F2 · 教学期弹层背后的目标不可点（P0，消灭死循环）

`context == "drawer"` 且弹层打开时，弹层的 `ColorRect` 遮罩已经 `MOUSE_FILTER_STOP`——**但棋盘槽位位于弹层上方区域，未被遮罩覆盖**。修法二选一（推荐①）：

① 教学期弹层打开时，给抽屉/棋盘设 `mouse_filter = IGNORE`（弹层关闭后恢复）；
② 弹层遮罩改为全屏铺满（当前只铺弹层自身高度）。

### 3.3 F3 · 暗幕不得压暗当前交互面（P0）

弹层打开时，暗幕四片的外边界收缩到**弹层顶边**，即只压暗弹层以外的世界/抽屉区域；弹层本身保持原亮度，洞开在选项按钮上。

实现：`TutorialOverlay._layout_mask()` 增加 `clip_top` 参数，由 `main_view` 在 `source == "sheet_option"` 时传入弹层顶边 y。

### 3.4 F4 · 符号全部改为美术图标（P0，根治 D2）

`assets/art/ui/` 中**已有全部所需图标**：`ic_power` / `ic_heat` / `ic_cooling` / `ic_lock` / `ic_market_up` / `ic_warning` / `ic_check`。

| 位置 | 现状 | 改法 |
|---|---|---|
| 弹层选项（供电/冷却/机柜） | Button.text 内嵌 `⚡♨❄▦` | 选项内容改为结构化布局：`HBox[ 商品图 64 ‖ VBox[ 名称·价格 ‖ HBox[ic_power 24 + 数值, ic_heat 24 + 数值, 价格] ] ]`；Button 只作容器，`text` 置空 |
| 棋盘格 tooltip / 预判徽章 | `⚡` `♨` 文本 | `TextureRect` + `ic_power` / `ic_heat` |
| 锁定态 `🔒` | 文本前缀 | `ic_lock` 图标 |
| `✓` | 文本 | `ic_check` 图标 |
| `×`（关闭按钮） | 文本 | **保留**——U+00D7 三枚字体均覆盖，安全 |

顺带关闭 14 号文档 §2.3 的 M3/M9（选项缺代价说明、数值无标签）：数值旁补单位文案（「容量 8」「耗电 2 · 发热 2」），不再让裸数字孤立成行。

### 3.5 F5 · 气泡避让扩展到弹层标题（P1）

真机截图 1 中气泡盖住了弹层的「安装」标题。`_position_callout()` 的避让集合从「目标控件矩形」扩展为「目标矩形 ∪ 当前弹层标题区」。

---

## 4. 门禁（防回归，本轮必须同步落地）

上一轮 30 态视觉 + 17 态流程门禁**全绿**却漏掉了这两个阻断级缺陷，说明门禁有两处结构性缺口：

### G1 · 聚光灯必须落在最顶层交互面内

`tests/flow_audit.gd` 对每个 actionable 步骤增加断言：

```
若存在可见 ActionSheetOverlay：
  - 聚光灯 rect 必须完全落在弹层矩形内；
  - 且 rect 必须与某个 Choice_* 按钮相交；
  - 且暗幕不得覆盖弹层区域（采样弹层中心像素亮度 ≥ 未遮挡基准的 90%）。
否则（无弹层）：维持现有「与目标控件/世界建筑相交」断言。
```

并在流程中**补齐弹层态的步骤覆盖**：当前 `flow_audit` 打开 picker 后只断言了金币行为（`_assert_sheet_reward_uses_hud_pulse`），从未断言教学目标——这是漏检的直接原因。

### G2 · 字形覆盖必须包含代码字面量

`tools/check_assets.py` 的字体校验从「ui.csv 字符集」扩展为「ui.csv ∪ 全部 `.gd` 字符串字面量中的非 ASCII 字符」。任一字符未被三枚打包字体共同覆盖即失败。

> 附：本次使用的 cmap 静态分析可直接固化为该校验的实现（无需 fontTools 依赖，纯 struct 解析 format 4/12 子表）。

### G3 · 教学期不可存在「引导指向却不可达/可重复触发」的控件

flow_audit 增加：弹层打开时，聚光灯目标以外的、上一阶段的目标控件必须 `mouse_filter == IGNORE` 或被遮罩覆盖。

---

## 5. 执行顺序

| 批次 | 内容 | 预估 |
|---|---|---:|
| ① | F1 三阶段解析 + F2 死循环 + G1 断言（**先写断言让它红，再修**） | 0.5d |
| ② | F4 符号图标化（全部 5 处）+ G2 字形门禁 | 0.5d |
| ③ | F3 暗幕收缩 + F5 气泡避让 + G3 断言 | 0.5d |
| ④ | 全量回归（双语 30 态 + flow 17 态 + midgame 12 态 + 103 逻辑）→ 重新打包 build 2 → TestFlight | 0.5d |

**验收标准（真机，所有者亲测）**：TestFlight 新装，从开屏连续完成全部 8 步新手引导，无一步需要猜测点哪；所有数值旁的图标正常显示；无死循环、无被压暗的操作面。

## 6. 验收记录（执行方填写，逐项附真机截图）

（待填）

---

## 6. 验收记录（2026-08-04，Claude 执行）

### 6.1 复现与门禁（先红后修）

新增 `_assert_sheet_spotlight` / `_assert_no_repeat_open_loop` 后，`flow_audit` 在修复前**红 8 条**，与真机现象逐条对应：

```
F1 power     must retarget to a sheet option        ← D1-a 目标解析缺第三阶段
F3 power     dim pane 0/1/3 cover the sheet (48/33/13%)  ← D1-b z 层遮挡
F1 first_rack must retarget to a sheet option
G1 first_rack target=(196,850,144,144) sheet=(32,1016,740,708)  ← 目标完全在弹层之外
F3 first_rack dim pane 1 covers the sheet (100%)    ← 整个弹层被压黑
```

### 6.2 已关闭项

| # | 修法 | 验证 |
|---|---|---|
| F1 | `_resolve_tutorial_target()` 前置弹层分支，映射 `install_power→Choice_power_t1` 等；未映射弹层退化为纯气泡而非把洞留在弹层外 | flow_audit 断言 `target_source == "sheet_option"` |
| F2 | 死循环根因修正为「教学 overlay 在 z=98 用陈旧 action 反复触发」（弹层遮罩本就全屏 STOP，无需额外禁点）；F1 修好后 action 变为点击选项按钮，循环自然消失 | `_assert_no_repeat_open_loop` 断言弹层数不增 |
| F3 | 暗幕下边界收缩至弹层顶边；目标位于弹层内时整块弹层不参与压暗 | 断言各遮罩与弹层交叠 ≤ 2% |
| F4 | 数据行改中文标签（容量/耗电/发热/受冷/制冷/覆盖 N 格），放置预判徽章改 `ic_power`/`ic_heat`/`ic_check` 图标，`🔒`→文案，离线大事记前缀符号移除，`‹›−◆●⚠💎` 全部替换 | 见 §6.3 |
| F5 | 目标位于弹层内时，气泡以整个弹层为避让体，落在弹层上方 | 断言气泡不与 `SheetHeading` 相交 |
| G1 | 弹层态聚光灯三重断言（落在弹层内 / 命中 Choice / 暗幕不覆盖弹层） | 已入 `flow_audit` |
| G2 | `check_assets.py` 字形校验扩展到 **GDScript 字符串字面量**（原先只查 ui.csv） | 立刻抓出 8 个漏网字符 |

### 6.3 G2 附带发现（本轮新增第三个真机缺陷）

新门禁上线后立刻抓到 **「总」字不在打包字体内** ——`园区总览`（ui.csv:10）在真机上会显示为「园区□览」。

根因：`tools/subset_fonts.py` 的 `COMMON_HAN_BUFFER_SIZE = 3500` **截断了 GB2312 一级区**（实为 3,755 字），「总」(D7DC) 位于被砍掉的尾部；同时打包字体与当前 ui.csv 已不同步。

修复：缓冲区改为 3,755（完整一级区）并从上游母版重新子集化——归档 SHA-256 `4ad7b141…` 与母版 SHA-256 `ee3f276c…` 均与 `assets/fonts/README.md` 记录的审计值一致。产物 3,882 字符 / 每枚约 1.81MB（较前 +0.1MB）。

### 6.4 时序缺陷（实现过程中发现并修复）

- 弹层高度在 `_finalize_action_sheet_layout` 中才定案，而教学解析先于它执行 → 记录 `settled_rect` 供暗幕使用；
- 弹层有 64u 滑入动画，动画中途解析会让聚光灯低 64u、横跨两个选项 → 改为在动画 `chain()` 回调中重解析。

### 6.5 全量门禁

```
validate_data          11 表 / 双语 / 152 art IDs
check_assets --strict  152 art / 6 font（ui.csv + GDScript 字面量全覆盖）/ 23 audio
test_runner            103 passed, 0 failed
flow_audit             PASS（含新增 G1/G3 断言）
midgame_audit          PASS
visual_smoke zh_CN     31/31
visual_smoke en        31/31
```

**未做**：F4 中「选项行改为图标+数值的结构化布局」降级为「中文单位标签」。标签方案同样根治了字形缺失，且直接关闭了 14 号文档 M3「数值无标签」的可读性问题，布局重构风险为零；图标化留待后续打磨轮次。
