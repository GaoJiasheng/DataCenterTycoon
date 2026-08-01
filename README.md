# DataCenterTycoon（暂定名）

一款以「数据中心建设与运营」为题材的竖屏放置经营手游。
玩家像种菜一样：买地 → 建机房 → 上架机器 → 接客户合约赚钱 → 机房老化退役 → 用赚到的钱建更多更好的机房。

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

## 当前状态

- [x] 设计方案完成（本次提交）
- [ ] M0：Godot 工程搭建 + 存档/时间引擎
- [ ] M1：单机房核心循环可玩
- [ ] 后续里程碑见 [docs/04_tech_plan.md](docs/04_tech_plan.md)

## 给下一个 session / 模型的说明

1. 一切设计争议以 `docs/00_decisions.md` 为准；它记录了与项目所有者（GaoJiasheng）逐条确认过的决策。
2. 数值表（`docs/02_economy.md`）是首版估值，实现后必须用文档中描述的模拟器脚本调平，不要凭感觉改。
3. 美术 prompt 刻意用英文书写（生成模型对英文理解更好），文档其余部分用中文。
4. 不要扩充已被明确砍掉的系统（见 00_decisions「明确不做」一节）。
