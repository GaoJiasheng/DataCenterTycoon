# 22 · 内容一致性审计

> 覆盖 2026-08-28 的中英双语标准画幅全量回归。当前视觉套件已经增长到每种语言 49 态，因此本次实际审查范围高于 22 号规格写定的 47 态。

## 1. 英文术语统一表

| 中文概念 | 统一英文 | 使用规则 |
|---|---|---|
| 机房 | data center | 两个词；仅在正式命名的 `Facility Archive` 中保留 facility |
| 园区 | campus | 不与 park 混用；Park 只作为主导航页名称 |
| 时代 | Era | 带编号或专名时首字母大写，如 Era 2 / Cloud Era |
| 合约期限 | contract term | duration 仅用于内部字段；玩家文案统一用 term |
| 游戏月 | game month | 所有合约时长明确是游戏内时间，不裸写 month |
| 锁价 | locked rate | 回顾已签价格时可用 signed rate；不使用 lock price |
| 客户 | client / customer segment | 人物、合约与关系用 client；行情大类用 customer segment |
| 询价单 | client inquiry / optional offer | 首次出现用 client inquiry，列表辅助文案可用 optional offer |
| 工程部扩编 | Engineering Department / build slot | 部门名固定；扩容结果写 build slot，不写 lane/bay 混称 |
| 公司传承 | company legacy | 与普通 restart/rebuild 区分，始终指永久成长结算 |
| 月收入 | income · $%s/mo | 紧凑卡片用 `/mo`，完整句使用 `per game month` |

本轮逐条复核了 `localization/ui.csv` 的 644 个英文条目，只修改 EN 列。主要修复为：合同月明确标注 game month、company legacy 术语收口、并列项补标点、询价与值班日志去除 `offer(s)` / `room(s)` 机器式复数、以及将 `Company Memorial` 等非母语表达改为自然英文。key 与 zh_CN 列均未改动。

## 2. 49 态弱资产横评

- [中文 49 态总览](ui_review/22_asset_audit_zh_CN_contact.png)
- [英文 49 态总览](ui_review/22_asset_audit_en_contact.png)

下列仅是下一轮美术候选，不在发布加固批次内重生成或替换。

| 排名 | 资产 | 跨屏问题 | 重生成 prompt 草稿 |
|---:|---|---|---|
| 1 | `fx_glow_ring` | 高饱和洋红/黄霓虹圆环与蓝金工业园区完全脱节，且正是“几何线圈”观感的主要来源；缩小时仍抢过建筑主体。 | `Transparent-background isometric mobile-game celebration aura for a cozy blue-and-gold data-center tycoon; layered volumetric electrical bloom and tiny warm sparks rising from the machine, irregular organic energy falloff, no circles, no rings, no neon magenta, no text, no border, premium rendered 3D illustration, readable at 128 px.` |
| 2 | `fx_confetti_set` | 彩色圆点、圆角条和星形像三消通用素材；和机房硬件的体积、材质、光向没有关系。 | `Transparent premium isometric reward burst made from miniature gold server badges, blue data packets, tiny brass bolts and soft paper flecks; coherent top-left lighting, restrained blue/gold/ivory palette, varied depth and natural trajectories, no primitive circles, no candy shapes, no text, no frame.` |
| 3 | `plot_forsale` | 木栅栏+耕地语言像农场游戏，和混凝土底盘、道路、机房建筑不属于同一园区；在地图空场时尤其明显。 | `Transparent isometric undeveloped parcel for a modern data-center campus, matching the existing blue/gold industrial buildings: compacted gravel and pale concrete survey corners, subtle conduit stubs, small blue construction marker, same camera and shadow direction as dc_t1, clean silhouette, no farm soil, no wooden fence, no text.` |
| 4 | `panel_main` | 高亮青色粗边和四颗螺钉在长页面重复出现时压过内容层级；内部深蓝页面与外框的玩具塑料质感不一致。 | `Seamless nine-slice mobile-game page frame for a premium cozy data-center management game; dark navy anodized panel with restrained brushed-metal blue edge, subtle warm-gold fastener details only at corners, low-glare bevel, quiet center, generous safe slicing area, no text, no oversized cyan glow, transparent exterior.` |
| 5 | `dialog_bubble` | 固定左侧尾巴无法适配不同目标，厚亮蓝塑料边在连续教程中重复感强；与精确指向目标的布局逻辑冲突。 | `Modular tutorial speech bubble kit on transparent background: one tail-free ivory rounded bubble plus separate centered/down-left/down-right pointer tails, premium soft enamel and restrained blue trim, consistent top-left light, large calm reading surface, no character, no text, no fixed pointer, nine-slice safe margins.` |

## 3. 音频相对响度

使用源文件峰值加 `manifest.json volume_db` 得到运行时有效峰值；音乐、导航、货币、结果反馈、施工操作和里程碑分别成组，不把独立的低声夜间环境音硬拉进短促 SFX 组。

| 组别 | cue | 调整前增益 | 调整后增益 | 调整后有效峰值范围 |
|---|---|---:|---:|---:|
| 货币 | `sfx_cash` | -5 dB | -10 dB | -12.5 至 -15.1 dB（含 `coin_tick`，差 2.6 dB） |
| 施工/告警 | `sfx_fault` | -3 dB | -5 dB | -5.0 至 -6.3 dB（差 1.3 dB） |
| 里程碑 | `sfx_era` | -16 dB | -6 dB | -5.0 至 -7.0 dB（差 2.0 dB） |
| 里程碑 | `sfx_prestige` | -2 dB | -5 dB | 同上 |
| 里程碑 | `sfx_bankrupt` | -3 dB | -5 dB | 同上 |

其余分组复核结果：三首音乐有效峰值差 2.3 dB；tap/sheet 导航差 2.3 dB；success/error 反馈差 1.4 dB。所有同类组均 ≤3 dB。`sfx_night_amb` 保持 -21.2 dB 的环境底噪角色，不与一次性提示声竞争。

## 4. 色觉兜底

逐项核对棋盘和待办中心，颜色都只是第二通道：

- 棋盘可放置、过热、缺电、成组分别使用 `ic_check`、`ic_heat`、`ic_power`、`ic_market_up`；锁定格使用锁布资产，故障格使用扳手状态标识。
- 待办中心故障、续约、退役、行情分别使用扳手、合约卷轴、退役箱、上升行情板；即使去色仍能按轮廓和标题区分。
- 世界待办角标保留数字计数，进入列表后再由上述独立图形说明状态；不存在只靠红/绿/橙判断的阻断操作。

本轮未发现需要补图形的漏项，因此没有为了色觉审计改动现有配色或玩法。
