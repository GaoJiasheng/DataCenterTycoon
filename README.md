# DataCenterTycoon（暂定名）

一款以「数据中心建设与运营」为题材的竖屏放置经营手游。
玩家像种菜一样：买地 → 建机房 → 上架机器 → 接客户合约赚钱 → 机房老化退役 → 用赚到的钱建更多更好的机房。

竖屏界面在 Godot 中使用 804×1748 设备无关设计画布；桌面交互预览固定为 iPhone 17 Pro Max 物理分辨率 1320×2868 的一半（660×1434），自动审片截图再放大 50% 至 990×2151，均使用 `aspect=keep`。交互控件遵循至少 44pt 的触控热区，并为 Dynamic Island 与 Home Indicator 预留安全区。

- 引擎：Godot 4（沿用 zombie-fire 的 Godot + iOS 发行经验）
- 平台：iOS App Store（竖屏，多尺寸兼容）
- 市场：中英双语，面向中国大陆以外的所有区域
- 商业化：激励视频广告 + 去广告 IAP + 钻石/礼包
- 美术：卡通 2.5D（Hay Day 质感），全部素材由 AI 生成模型产出，prompt 见美术规格文档

## 文档索引（按阅读顺序）

| 文档 | 内容 | 读者 |
|---|---|---|
| [docs/00_decisions.md](docs/00_decisions.md) | 已锁定的设计决策与待定项（跨 session 的唯一事实来源） | 所有人，**先读这个** |
| [docs/01_game_design.md](docs/01_game_design.md) | 核心玩法：三层循环、机房/网格/供电冷却、客户与行情、老化退役、转生、银行接管 | 策划/程序 |
| [docs/02_economy.md](docs/02_economy.md) | 时间换算、全部数值表与公式、平衡目标、调平方法 | 策划/程序 |
| [docs/03_art_spec.md](docs/03_art_spec.md) | 全局美术风格规范 + 全量素材清单（每个素材含尺寸/状态/英文生成 prompt） | 美术外包/生成模型 |
| [docs/04_tech_plan.md](docs/04_tech_plan.md) | Godot 工程结构、数据 schema、存档与离线结算、里程碑、风险 | 程序 |
| [docs/05_monetization_store.md](docs/05_monetization_store.md) | 广告位、IAP SKU、定价、商店文案（中英）、上架清单 | 商务/程序 |
| [docs/06_gameplay_optimization_proposal.md](docs/06_gameplay_optimization_proposal.md) | 行情敏感度、网络大单、续约、独立上架、停机与多种子调平的实施记录 | 策划/程序 |
| [docs/18_cozy_rework_spec.md](docs/18_cozy_rework_spec.md) | 「轻松化」改造实施规格：签约锁价、银行接管、退役收割、故障软化、免费改签（已落地） | 策划/程序 |
| [docs/19_meta_progression_rework.md](docs/19_meta_progression_rework.md) | 公司路线、园区定位、客户关系/合约期限、行情复盘、董事会与企业典藏（已落地） | 策划/程序/美术 |
| [docs/20_gameplay_depth_and_economy.md](docs/20_gameplay_depth_and_economy.md) | 中期询价、棋盘成组、稀有行情、期限折算锁价、工程部扩编与经济归因（已落地） | 策划/程序 |
| [docs/21_warmth_patch.md](docs/21_warmth_patch.md) | 值班日志、客户拟人化与机房猫的纯表现温度补丁（已落地） | 策划/程序/美术 |
| [docs/22_release_hardening.md](docs/22_release_hardening.md) | 发布前纹理、多画幅、发布脚本、CI、存档健壮性与内容一致性加固 | 程序/发行/QA |

## 当前状态

- [x] M0–M4：工程底座、完整经营循环、地图扩张、长线系统、转生、引导与成就
- [x] iPhone 17 基准的双语竖屏 UI：世界优先园区、极简 HUD、动态主操作、情境抽屉、安全区和触觉接口
- [x] 正式美术 180 项、音频 23 项完整接入；地图、机房、导航、商店、事件特效、客户人设、机房猫、公司元进度和三套音乐均走运行时接口
- [x] StoreKit provider、交易幂等、限购、恢复购买和激励视频原生桥接口
- [x] 轻松向经营闭环：合同期内已知行情精确折算锁价、自动续约与永久免费改签、故障 40% 降效/4 小时自愈、残料回收/95% 自动退役、银行接管/重整托底
- [x] 中期深度闭环：永久询价单、棋盘同类成组、3 条稀有行情与战略约 ×2.5 封顶、2→5 工程部扩编
- [x] 表现温度层：权威离线账单驱动的值班日志、10 位共享数值的人设角色、教程外一只无重复货币产出的园区猫与 4 张猫片典藏
- [x] 243 项 Godot 回归测试、双语各 49 状态竖屏视觉与排版审计、SE/标准/iPad 多画幅探针、断言化 FTUE/中期流程审计、30 天三策略 × 20 种子模拟、iOS 可复现发布脚本与 App Store 自动门禁
- [ ] 外部交付：P01 正式名称、P04 广告 SDK、Apple 账号/证书与 App Store Connect 录入

运行时已经使用正式视听资源；资源接口仍保留缺失回退，因此单张素材损坏或暂时移除不会阻止玩法逻辑启动。

## 开发与验收

使用 Godot 4.7 stable 打开仓库根目录，或直接运行：

```sh
godot --path .
godot --headless --path . tests/test_runner.tscn
godot --headless --path . tests/flow_audit.tscn
godot --headless --path . tests/midgame_audit.tscn
godot --disable-vsync --max-fps 200 --path . tests/tutorial_playthrough.tscn
godot --disable-vsync --max-fps 200 --path . tests/full_campaign.tscn
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=en
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=zh_CN
godot --fixed-fps 60 --path . tests/store_shots.tscn -- --locale=en --device=iphone_69
godot --fixed-fps 60 --path . tests/store_shots.tscn -- --locale=zh_CN --device=ipad_13
godot --disable-vsync --max-fps 240 --path . tests/performance_smoke.tscn
python3 tools/validate_data.py
python3 tools/simulate_economy.py
python3 tools/report_release_economy.py
```

`tests/flow_audit.tscn` 从全新存档走完整 FTUE，逐步断言场景上下文、唯一可点目标、聚光灯交集、抽屉实时数据、特效生命周期与休眠/唤醒状态，并确认教程期客户人设与机房猫不可见、不可点；非 headless 运行时同时输出 `/tmp/dct_flow_*.png`。GitHub Actions 会执行数据校验、243 项逻辑、流程/战役/性能门禁，以及双语 49 态与 SE/标准/iPad 三档渲染回归。性能门禁另以 100 座机房验证 13 页园区切分、单页可见集、统一建筑朝向、单猫状态机及其爱心特效清理。

`tests/tutorial_playthrough.tscn` 只用触摸走完新手教程；`tests/full_campaign.tscn` 接着往下打——从全新存档按"月"推进，边玩边刷新真实 UI，一路走到时代 2、时代 3 和第一次上市重组，断言故障降效/修复、期限折算锁价（同局灵活约 > 标准约）/自动续约/免费改签、退役收割、银行接管兼容、询价/成组/扩编、离线结算、页面切换与顶部信息带不互相遮挡，输出 `/tmp/dct_camp_*.png`。审计记录见 [docs/17_full_campaign_audit.md](docs/17_full_campaign_audit.md)。

`tests/store_shots.tscn` 用同一份后期存档夹具和真实 `main.tscn` 生成 App Store 截图。它在目标像素尺寸的 `SubViewport` 中原生渲染，不依赖桌面窗口高度，也不会把小图放大。分别对 `en/zh_CN` 与 `iphone_69/ipad_13` 四种组合运行即可复现全部 20 张交付图。

资源重做或更新后执行：

```sh
python3 tools/import_assets.py --visual --audio
python3 tools/check_assets.py --strict --audio
python3 tools/check_app_store_assets.py
python3 tools/check_release.py
```

iOS 归档、签名、IPA 校验和 TestFlight 上传只允许走统一脚本，禁止再从 Organizer 手工拼接发布步骤：

```sh
tools/release_ios.sh --dry-run
tools/release_ios.sh --bump --upload
```

`--dry-run` 会完整产出并验签 IPA，但绝不上传；`--bump` 会递增并保留 `export_presets.cfg` 的 build 号，发布提交必须包含该改动。归档保存在 `builds/archives/`。

Godot 重新导入 CSV 后可能只产生 `.translation` 二进制噪声；`tools/check_release.py` 会从 `ui.csv` 内存重编译并逐条对照当前资源。若确认没有文案修改而工作区仍变脏，直接执行 `git checkout -- localization/` 恢复，不要提交无意义二进制差异。

实现说明见 [docs/architecture.md](docs/architecture.md)，数值结果见 [docs/balance_report.md](docs/balance_report.md)，外部交付项见 [docs/release_checklist.md](docs/release_checklist.md)。

## 给下一个 session / 模型的说明

1. 一切设计争议以 `docs/00_decisions.md` 为准；它记录了与项目所有者（GaoJiasheng）逐条确认过的决策。
2. 数值表（`docs/02_economy.md`）与 `data/*.json` 是首版基线；修改后必须重跑模拟器，不要凭感觉改。
3. 美术 prompt 刻意用英文书写（生成模型对英文理解更好），文档其余部分用中文。
4. 不要扩充已被明确砍掉的系统（见 00_decisions「明确不做」一节）。
