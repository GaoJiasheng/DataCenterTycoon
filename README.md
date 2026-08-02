# DataCenterTycoon（暂定名）

一款以「数据中心建设与运营」为题材的竖屏放置经营手游。
玩家像种菜一样：买地 → 建机房 → 上架机器 → 接客户合约赚钱 → 机房老化退役 → 用赚到的钱建更多更好的机房。

竖屏界面以 6.3 英寸 iPhone 17 的 402×874 pt 为标准尺寸，在 Godot 中使用 804×1748 设计画布；交互控件遵循至少 44pt 的触控热区，并为 Dynamic Island 与 Home Indicator 预留安全区。

- 引擎：Godot 4（沿用 zombie-fire 的 Godot + iOS 发行经验）
- 平台：iOS App Store（竖屏，多尺寸兼容）
- 市场：中英双语，面向中国大陆以外的所有区域
- 商业化：激励视频广告 + 去广告 IAP + 钻石/礼包
- 美术：卡通 2.5D（Hay Day 质感），全部素材由 AI 生成模型产出，prompt 见美术规格文档

## 文档索引（按阅读顺序）

| 文档 | 内容 | 读者 |
|---|---|---|
| [docs/00_decisions.md](docs/00_decisions.md) | 已锁定的设计决策与待定项（跨 session 的唯一事实来源） | 所有人，**先读这个** |
| [docs/01_game_design.md](docs/01_game_design.md) | 核心玩法：三层循环、机房/网格/供电冷却、客户与行情、老化退役、转生、破产 | 策划/程序 |
| [docs/02_economy.md](docs/02_economy.md) | 时间换算、全部数值表与公式、平衡目标、调平方法 | 策划/程序 |
| [docs/03_art_spec.md](docs/03_art_spec.md) | 全局美术风格规范 + 全量素材清单（每个素材含尺寸/状态/英文生成 prompt） | 美术外包/生成模型 |
| [docs/04_tech_plan.md](docs/04_tech_plan.md) | Godot 工程结构、数据 schema、存档与离线结算、里程碑、风险 | 程序 |
| [docs/05_monetization_store.md](docs/05_monetization_store.md) | 广告位、IAP SKU、定价、商店文案（中英）、上架清单 | 商务/程序 |
| [docs/06_gameplay_optimization_proposal.md](docs/06_gameplay_optimization_proposal.md) | 行情敏感度、网络大单、续约、独立上架、停机与多种子调平的实施记录 | 策划/程序 |

## 当前状态

- [x] M0–M4：工程底座、完整经营循环、地图扩张、长线系统、转生、引导与成就
- [x] iPhone 17 基准的双语竖屏 UI：世界优先园区、极简 HUD、动态主操作、情境抽屉、安全区和触觉接口
- [x] 正式美术 134 项、音频 16 项完整接入；地图、机房、导航、商店、事件特效和三套音乐均走运行时接口
- [x] StoreKit provider、交易幂等、限购、恢复购买和激励视频原生桥接口
- [x] 80 项 Godot 回归测试、21 状态竖屏视觉与排版审计、30 天三策略 × 20 种子模拟、iOS 导出与 App Store 自动门禁
- [ ] 外部交付：P01 正式名称、P04 广告 SDK、Apple 账号/证书、商店截图和 TestFlight

运行时已经使用正式视听资源；资源接口仍保留缺失回退，因此单张素材损坏或暂时移除不会阻止玩法逻辑启动。

## 开发与验收

使用 Godot 4.7 stable 打开仓库根目录，或直接运行：

```sh
godot --path .
godot --headless --path . tests/test_runner.tscn
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=en
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=zh_CN
godot --disable-vsync --max-fps 240 --path . tests/performance_smoke.tscn
python3 tools/validate_data.py
python3 tools/simulate_economy.py
```

资源重做或更新后执行：

```sh
python3 tools/import_assets.py --visual --audio
python3 tools/check_assets.py --strict --audio
python3 tools/check_app_store_assets.py
python3 tools/check_release.py
```

实现说明见 [docs/architecture.md](docs/architecture.md)，数值结果见 [docs/balance_report.md](docs/balance_report.md)，外部交付项见 [docs/release_checklist.md](docs/release_checklist.md)。

## 给下一个 session / 模型的说明

1. 一切设计争议以 `docs/00_decisions.md` 为准；它记录了与项目所有者（GaoJiasheng）逐条确认过的决策。
2. 数值表（`docs/02_economy.md`）与 `data/*.json` 是首版基线；修改后必须重跑模拟器，不要凭感觉改。
3. 美术 prompt 刻意用英文书写（生成模型对英文理解更好），文档其余部分用中文。
4. 不要扩充已被明确砍掉的系统（见 00_decisions「明确不做」一节）。
