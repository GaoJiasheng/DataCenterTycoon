# 运行时架构与接入契约

## 启动链路

`project.godot` 将数据、时钟、存档、资源、音频、商业化和游戏状态注册为 Autoload。启动时按以下顺序完成：加载并校验 JSON → 读取主档或三份备份 → 补齐旧存档字段 → 恢复带种子的行情状态 → 应用语言与音频设置 → 检测时间回拨 → 分段结算离线状态 → 加载竖屏主界面。

正式图片和音频已经通过 manifest 接入主场景；同时保留缺失资源的程序化回退。原生 SDK 不存在时编辑器使用商业化 mock，因此仓库仍可独立运行和测试。

## 分层

| 层 | 主要文件 | 职责 |
|---|---|---|
| 配置 | `data/*.json`、`localization/ui.csv` | 唯一数值源、双语文本、商品定义与第三方归属清单 |
| 纯规则 | `gameplay/game_rules.gd` | 地价、供电顺序、四边冷却、收入、老化、残值、净值 |
| 状态系统 | `core/game.gd`、`gameplay/market_system.gd` | 所有可变游戏状态、快进、建设、合约、故障、维护、时代、转生、破产 |
| 持久化 | `core/save_manager.gd`、`core/game_clock.gd` | 临时文件原子改名、三备份、迁移、Game Over 留档、回拨防护 |
| 表现 | `ui/main_view.gd`、`ui/legal_view.gd`、`ui/theme_factory.gd`、`ui/widgets.gd`、`ui/fx_layer.gd`、`ui/datacenter_board.gd`、`ui/tutorial_overlay.gd`、`ui/market_chart.gd`、`ui/sparkline.gd`、`gameplay/map/park_map.gd` | 紧凑工业园区、应用内法务/许可阅读、正式九宫格 UI 套件、悬浮 HUD、状态驱动局部刷新、金币/数字反馈、机房空间棋盘、聚光灯引导、行情可视化、危机与高光演出 |
| 外部适配 | `core/asset_catalog.gd`、`core/audio_service.gd`、`core/monetization_service.gd` | 通过稳定 ID 隔离美术、音频、StoreKit 和激励视频 SDK |

跨系统通知只经 `EventBus` 发送。UI 不自行实现收入、供电或冷却规则；合约预估通过复制机房字典后调用 `Rules.datacenter_income_per_month()`，自动测试要求它与签约后的权威值完全一致。

根 UI 使用 804×1748 设备无关设计画布；桌面交互预览固定为 iPhone 17 Pro Max 物理分辨率 1320×2868 的一半（660×1434），自动审片截图使用 990×2151（桌面预览的 150%），均以 `aspect=keep` 等比缩放。产品采用四层复杂度：持久化 `ParkMap` 世界层、七项以内的 HUD/动态主操作层、对象情境抽屉层，以及保留园区为背景的高不透明运营工作台层。园区每 6 个 slot 分成一个 2×3 呈现组；已有地块和待购地共同填满双列，只有当前组落单时末项才居中。每个完整行严格共用 Y 基线与固定 X 锚点，行间道路只占中轴交叉节点；切换条一次只激活一个园区的世界节点，集团总览以可滚动列表承担无限扩张后的定位，并且不改变任何机房模拟数据。所有素材先按非透明内容裁切，再吸附到统一地面锚点。地图只为价格与倒计时保留短文本，其余状态收为可点击对象角标。沿 2:1 等距轴移动的风迹、树木摆动、建筑呼吸、供电光环和实时施工倒计时只属于表现层，不改变模拟规则。

`state_changed("tick"|"offline_advance"|"settings_changed")` 只进入 `_refresh_hud()` 和节点上注册的 `live_update`；其余玩家动作才触发 `_refresh_page()`。设置开关在原位更新，避免释放触控中的按钮或重置整页滚动。页面重建前后由 `PageScroll` 缓存恢复滚动位置。机房抽屉直接嵌 `DatacenterBoard`，将供电、冷却与机柜合并为空间决策，独立深层只保留合约。字体固定为仓库内 Baloo 2 → Resource Han Rounded CN 的 Medium/Bold/Heavy 子集 fallback，按钮/面板优先使用交付九宫格，缺失资产时才回退 flat style。

## 存档模型

当前 `save_version=3`，主档仍为 `user://save_v1.json`。v2 会把旧存档中占用全局队列的机柜工程迁移为机房内 `install_complete_at` 计时，并为既有机柜补齐 `enabled=true`；v3 为旧合约补齐期限/锁价字段，并加入永久元进度。核心字段包括：

- `player`：现金、钻石、总收入、时代、网络、品牌倍率和累计建设数；
- `plots`：地块与嵌套机房，机房包含 9 个机柜格、独立机柜安装计时/停机状态、供电、四边冷却、客户、续约窗口、寿命与状态；
- `construction_queue`：最多两个机房/附件/网络工程及广告加速次数；机柜不占该队列；
- `market`：事件、预告、每日噪声、两年行情环形历史与随机状态；
- `bankruptcy`：正常/欠费/Game Over、债务和仅在线累计的抢救时限；
- `entitlements`、`purchases`、`processed_transactions`：非消耗权益、限购次数和 StoreKit 交易幂等表；
- `meta`：路线图领取、企业典藏发现/领取、园区定位、客户服务时长、行情决策、董事会点数、历代公司复盘与传承标记；
- `inventory`、`technology`、`achievements`、`tutorial`、`settings`、`stats`。

新增字段必须同时加入 `_new_state()` 与 `_ensure_state_shape()`；破坏性 schema 变化必须提升 `SaveManager.SAVE_VERSION` 并在 `migrate()` 中逐版本处理。

## 时间与离线语义

游戏月为 7200 现实秒、游戏年为 86400 现实秒。`Game.advance_time()` 在建设、机柜安装、维修、故障、合约到期/续约窗口、维护和行情边界处分段积分，不逐秒遍历；测试覆盖 90 个现实日的一次性快进。

基础离线收入上限 8 小时，`offline24` 权益提升到 24 小时。上限后的时间继续推进建设、合约、行情与老化，但不计收入或维护费；离线不累计破产倒计时。达到寿命的机房离线冻结在 99.9%，回到在线状态后才变为废墟。

## 视听交付接口

- 美术：`assets/art/manifest.json` 当前固定 180 个 ID；成品源目录为 `art-renders/visual/final/`。新增系统同样必须先交付正式渲染素材，不允许线框、几何图形或文字块充当原型占位。
- 音频：`assets/audio/manifest.json` 固定 23 个 cue；成品源目录为 `art-renders/audio/final/`。标准按钮、Sheet、数字滚动、结果 toast、解锁演出与夜间环境层统一经 `AudioService` 调用，缺失 cue 静默跳过；页面/危机音乐使用 2 秒淡出淡入切换。
- 导入：`python3 tools/import_assets.py --visual --audio`。
- 许可与来源：运行时归属数据在 `data/attributions.json`；180/23/6 逐项证据台账在 `docs/26_provenance.md`，由 `tools/check_provenance.py` 与 `validate_data.py` 防漏登。
- 验收：`python3 tools/check_assets.py --strict --audio` 与 `python3 tools/check_provenance.py`。

玩法只允许调用 `AssetCatalog.texture(asset_id)`、`AudioService.play_music(cue_id)` 和 `AudioService.play_sfx(cue_id)`，不得引用交付目录或正式文件路径。

## 商业化边界

玩法只调用 `Monetization`。iOS IAP provider 对接 Godot `InAppStore`，购买请求有并发锁，消耗品按交易号幂等发货，非消耗品可恢复，限购礼包在发起购买前即被阻断重复购买。

激励视频原生侧只需提供：

```text
bool show_rewarded(String placement)
signal rewarded_completed(placement: String, earned: bool)
```

桥接单例名固定为 `DataCenterAdsBridge`。只有 SDK 的用户实际获得奖励回调可以发送 `earned=true`。placement 前缀为 `offline_double`、`repair:`、`construction:`、`rack_install:`、`arrears_rescue`；`noads` 权益保留相同频控但直接发奖。

## 验证入口

```sh
python3 tools/validate_data.py
godot --headless --path . --scene res://tests/test_runner.tscn
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=en
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=zh_CN
godot --disable-vsync --max-fps 240 --path . tests/performance_smoke.tscn
python3 tools/simulate_economy.py
python3 tools/check_assets.py --strict --audio
python3 tools/check_provenance.py
python3 tools/check_app_store_assets.py
python3 tools/check_release.py
```

核心规则、双语 51 态视觉、应用内法务/许可阅读和桌面 Metal 性能门禁无外部依赖。App Store 截图、原生 SDK、签名与所有者账号值齐备前，发行门禁会有意失败并逐项列出缺口。
