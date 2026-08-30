# 04 · 技术方案与里程碑

## 1. 技术栈

| 项 | 选型 | 说明 |
|---|---|---|
| 引擎 | Godot 4.x（与 zombie-fire 同版本线） | 复用所有者已验证的 iOS 导出管线、隐私清单（PrivacyInfo.xcprivacy）经验 |
| 语言 | GDScript | 单人/小团队效率优先 |
| 目标平台 | iOS 15+，竖屏，1.0 iPhone-only | 基准逻辑分辨率 1080×1920，`canvas_items` 拉伸 + `expand` 适配刘海屏；iPad 仅以 iPhone 兼容模式运行，不作为发布目标 |
| 存档 | 本地 JSON（`user://save_v{N}.json`）+ 版本号迁移函数 | 纯单机；写入用「临时文件+原子改名」防半写损坏；保留最近 3 份轮换备份 |
| 广告 | AdMob（Godot iOS 社区插件，P04 待最终确认） | 只用激励视频，不做横幅/插屏（体验优先，见 05 文档） |
| IAP | Apple StoreKit（Godot iOS 内购插件） | 消耗型（钻石/礼包）+ 非消耗型（去广告、离线上限） |
| 本地化 | Godot 内置 `Translation`（CSV/PO），`zh_CN` 简中 + `en` 英文 | 画面素材零文字（美术规范已保证），只需翻 UI 字符串 |

## 2. 工程结构

```
project.godot
main.tscn / main.gd            # 入口：加载存档 → 离线结算 → 进主地图
core/
  game_clock.gd                # 真实时间→游戏时间换算；时间回拨防护（Autoload）
  economy.gd                   # 收入 tick、维护费、破产状态机（Autoload）
  save_manager.gd              # 原子写、版本迁移、备份轮换（Autoload）
  event_bus.gd                 # 全局信号总线（Autoload）
  offline_settler.gd           # 离线结算：推进老化/建设/合约/行情并生成「大事记」
gameplay/
  map/                         # 主地图场景、地块、滚动缩放相机
  datacenter/                  # 机房详情场景：3×3 网格、外挂槽、合约面板
  market/                      # 行情系统、事件抽取器、价格曲线
  construction/                # 建设队列与计时器
  prestige.gd / bankruptcy.gd
data/                          # ★ 全部数值配置，与 02_economy.md 一一对应
  buildings.json  racks.json  attachments.json
  customers.json  events.json  eras.json  economy.json
ui/                            # 五个一级页面 + 通用组件（9-slice 主题、弹窗、引导）
assets/art/                    # 按 03_art_spec §1.3 目录
tools/
  simulate_economy.py          # 调平模拟器（02_economy §10），CI 可跑
  check_assets.py              # 素材清单/尺寸/命名校验（对照 03_art_spec）
ios/                           # 导出模板、PrivacyInfo.xcprivacy（参考 zombie-fire）
```

设计原则：
- **数值全部进 data/*.json**，代码零魔法数字；模拟器与游戏读同一份 JSON——这是「文档↔数据↔模拟器」三方一致的基础。
- 所有系统通过 `event_bus` 解耦（如 `rack_fault_occurred`、`market_event_started`、`dc_entered_aging`）。

## 3. 关键实现要点

### 3.1 时间与离线结算
- `game_clock` 只信任「上次存档时间戳 + 单调递增校验」；检测回拨则冻结至追平（02_economy §1）。
- 离线结算是**事件驱动的快进**，不是逐 tick 模拟：把离线区间内的确定性事件（建设完成、合约到期、进入老化期、行情事件起止）排成时间线，分段计算收入积分；随机故障用泊松期望采样补发。上限外时间只推进状态不计收入。
- 输出「离线大事记」列表给回归弹窗（01_game_design §10 的规则：不强制报废、破产计时暂停）。

### 3.2 3×3 网格与冷却覆盖
- 机房 = `DCState`（资源类）：`tier, built_at, customer, racks[9], coolers[4], power_unit`。
- 冷却覆盖是纯函数：`cooling_at(cell) = Σ coolers[edge].power for edge covering cell`；过热判定在 economy tick 与 UI 中共用同一函数，避免显示与结算不一致。
- 供电视觉（D11）：机房场景根据 `powered` 状态整体切换调色（暗灰 shader / 点亮贴图 + 灯光节点），是必须优先做出的核心反馈。

### 3.3 行情事件
- 事件抽取用「加权抽签 + 时代过滤 + 预告队列」；行情曲线每游戏天记一个点，环形缓冲存 2 游戏年（730 点）。
- 所有随机数走带种子的 `RandomNumberGenerator` 并入存档，保证离线结算可复现、防「重开 app 刷事件」。

### 3.4 破产与转生
- 均为显式状态机（`NORMAL → ARREARS → GAME_OVER`；`prestige()` 为一次性原子操作：清算→写入现金→重置盘面→写入倍率→立即强制存档）。
- Game Over 后旧档移入 `save_gameover_{ts}.json` 留档（玩家情感资产），新档重开。

## 4. 里程碑

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| M0 工程底座 | 工程搭建、Autoload 骨架、存档/时钟/离线结算、data JSON 装载 | 占位方块跑通：关 app 1 小时回来收益正确、时间回拨被冻结 |
| M1 单机房循环 | 3×3 网格、机柜上架、供电/冷却/过热、故障派修、互联网+挖矿合约收入 | 用占位图完整玩 30 分钟不出错；供电点亮/暗灰切换生效 |
| M2 地图扩张 | 主地图滚动、买地、建设队列、多机房、维护费与欠费/破产 | 建 5 座机房、故意破产一次流程完整 |
| M3 长线系统 | 老化/退役/报废、行情事件+预告+曲线、时代 1→2→3、网络等级 | 模拟器三策略 30 天曲线达到 02_economy §10 目标 |
| M4 转生+新手引导 | 上市重组、引导流程（01 §12）、成就 | 新玩家首日无卡点走完引导（内部试玩 3 人） |
| M5 美术整合 | 按 03_art_spec 全量替换占位图、特效、音效/BGM | `check_assets.py` 全绿；§9 验收通过 |
| M6 商业化 | AdMob 激励视频 3 个位、StoreKit IAP、去广告、离线上限扩容 | 沙盒环境全 SKU 购买/恢复购买通过 |
| M7 上架 | 本地化终检、App Store 素材、隐私标签、TestFlight → 提审 | 提审通过（区域排除中国大陆，见 05 文档） |

## 5. 风险清单

| 风险 | 等级 | 缓解 |
|---|---|---|
| Godot iOS 广告插件质量参差（历史上 AdMob 插件随 Godot 版本破损） | **高** | M0 时即做一个只含插件的空工程真机验证；备选方案：只上 IAP 先发布，广告 1.1 再加 |
| 数值失衡（放置游戏最常见死因） | 高 | 模拟器先行（M3 验收硬门槛）；软启动期埋点看破产率/留存 |
| AI 生成素材风格漂移 | 中 | 03_art_spec §10 风格锚 + 参考图工作流；`check_assets.py` 卡命名尺寸 |
| 同名竞品（App Store 已有 Data Center Tycoon） | 中 | 上架前定名查重（00_decisions P01） |
| 离线结算与在线 tick 结果不一致 | 中 | 两条路径共用同一套纯函数计算模块 + 单元测试对拍 |

## 6. 复用 zombie-fire 的资产

- iOS 导出配置流程、`PrivacyInfo.xcprivacy` 模板、App Store 资产检查脚本思路（`check_app_store_assets.py`）、发布字符串检查（`check_release_strings.py`）、存档备份/恢复 UI 模式。
- 注意：只复用**方法**，代码按本工程结构重写，不直接拷贝依赖。
