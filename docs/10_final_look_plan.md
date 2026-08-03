# 10 · 最终观感冲刺（Final Look Plan）

> 生成于 2026-08-03。前置：09 号审计清单已基本执行完毕（哑光按钮 A1、统一建筑 A2、放置预判分级、离线语义、时代演出奖励等均验收通过，30 态双语回归绿）。
> 本文档是 UI 冲刺的**最后一个大阶段**：目标不再是「修问题」，而是把整体观感推到可以放进 App Store 截图的水平。所有者已授权：美术、音乐、材质、色调全部可改，以最终结果为准。
> 结构：§1 上轮遗留尾巴（先清掉）→ §2–§7 六大升级块 → §8 执行顺序。约束沿用 07§8。

---

## 1. 上轮遗留尾巴（R 系列，P0，半天内清完）

| # | 问题 | 证据 | 修法 |
|---|---|---|---|
| R1 | **新药丸按钮九宫格边距未重测**：端帽被切出叶状波浪凸起、底部有拉伸的阴影缝 | contract_comparison / offline / store 所有绿色价格钮两端 | 新 btn_* 素材几何与旧版不同：用 08 轮的测量脚本重测（alpha bbox + 圆角半径），更新 `art_button_box` 的 region/texture_margin；预计帽弧 ~64px、底棱 ~10px |
| R2 | CTA 文字发灰（银灰感，不是纯白） | z_confirm 放大图 | 排查 `art_button_box` 是否有 modulate/tint 残留；文字必须纯白 #FFFFFF + ink 描边 4；hover/pressed 的整体 tint 只准作用于纹理不准作用于文字 |
| R3 | 左下圆形按钮的下方标签被屏幕底缘裁切 | campus_dense 底部 | 标签纳入安全区计算：`WorldActions` 容器高度 +24u，或标签改到按钮上方 |
| R4 | 「最划算」徽章文字被截断 | store 550 档 | 徽章宽度按文字 min_size 自适应；双语验证（"BEST VALUE" 更长） |
| R5 | 英文 30 态复跑 | — | R1–R4 完成后 `--locale=en` 全绿 |

---

## 2. W · 世界地面与园区肌理（观感提升最大的一块）

**现状**：统一建筑落地后，世界仍是「亮绿草地上摆模型」——草地 tile 单调、无路网、无园区设施，空旷处大片纯草。

**目标**：世界读作「一个正在生长的科技园区」。

### 资产（英文 prompt，走既有管线）

| ID | 规格 | Prompt 要点 |
|---|---|---|
| `ground_tile_grass` | 1024², 可平铺 | Seamless tileable cartoon grass texture, soft yellow-green (#8fbf5a base), subtle mowing stripes and tiny clover patches, low contrast so buildings pop, Hay Day style, no objects |
| `ground_path_straight` / `ground_path_cross` | 512² ×2 | Cartoon light-gray concrete campus path tile, isometric top-down, rounded edges with grass blending at borders, subtle expansion joints, matches building foundation color |
| `prop_flagpole` / `prop_lamp` / `prop_bush_row` / `prop_parking` / `prop_transformer_yard` | 512² ×5 | Small cartoon campus props, same isometric angle as the building set (30° facing lower-left), blue-cream-gold palette accents, baked elliptical ground shadow, transparent background |
| `world_edge_fog` | 1024×512 | Soft radial gradient from transparent center to pale warm haze, for map edges |

### 代码接入（`gameplay/map/park_map.gd`）

1. 地面：`ground_tile_grass` 平铺替换现草地；缺失回退现状。
2. 路网：相邻已购地块之间自动铺 `ground_path_straight`，交叉处 `ground_path_cross`——只做正交连接，无寻路逻辑（地块本就是网格排布）。
3. Props：每块已购地块按 index 伪随机（用地块 index 做种子，禁 `randi`）在四角空位摆 0–2 个 prop；待售区之外的远景撒 `prop_bush_row`。
4. 边缘：视口边缘叠 `world_edge_fog`（modulate 呼吸 alpha 0.5↔0.65）。

**验收**：campus_dense 状态截图中，园区有路网连接、至少 4 种 prop 出现、草地不再是均匀纯色；世界层节点数增幅 ≤ 60，滚动无掉帧。

---

## 3. C · 全局色调统一（Color Grading）

**现状**：三套色互相打架——草地高饱和黄绿、UI 面板深海军蓝、建筑奶白+宝蓝。整体「生、艳、散」。

**方案**（全部代码级，零素材）：

1. **世界层 CanvasModulate**：`Color(1.0, 0.97, 0.90)` 轻暖滤镜，草地饱和度视觉性降低、与建筑奶白呼应；
2. **昼夜氛围（轻量）**：按现实时间段在三档间插值——白天 (1.0,0.97,0.90) / 黄昏 (1.0,0.88,0.78) / 夜晚 (0.72,0.78,0.95)+建筑窗光 modulate 提亮 1.3——放置游戏的「回来看看」质感来源，实现只是一个插值函数；
3. **UI 面板色统一**：所有深蓝底收敛到两个值——工作面 `#122438`、分组块 `rgba(0,0,0,0.22)`；清查 main_view 中散落的 `#0c1c2c/#091827/#18293c/#243b55` 等 8+ 个手写深蓝，全部换成 `ThemeMaker.SURFACE`/`SURFACE_GROUP` 两个新常量；
4. **强调色收敛**：全局只允许 主蓝 sky / 金黄 yellow / 草绿 green + 语义色（红橙紫仅按语义出现）。清查现 UI 中的青色 cyan 大量用于副标——统一换成 `Color("9fb8cc")`（低饱和蓝灰，退到辅助层级，不与主蓝抢戏）。

**验收**：map 与任意系统页并排截图，色彩像同一款游戏；夜晚档人工截图确认氛围成立。

---

## 4. I · 图标系统重做（统一 30 枚 ic_*）

**现状**：图标风格混杂——有的扁平、有的伪 3D、有的带白底块（如 ic_market_up 绿色圆角块），描边粗细不一。

**方案**：全套重生成，统一规格：

> Prompt 模板：Game UI icon of {SUBJECT}, chunky rounded 3D cartoon style, {MAIN_COLOR} with warm gold accents, thick dark-navy outline (consistent 6px), soft top light, slight front-facing 3/4 tilt, centered on transparent background, 512x512, reads clearly at 48px, Hay Day-like.

| 批 | 图标 | SUBJECT 示例 |
|---|---|---|
| 1（高频） | ic_cash / ic_diamond / ic_build / ic_market_up / ic_tech / ic_shop / ic_settings / ic_contract / ic_power / ic_cooling | coin stack / faceted purple gem / claw hammer / rising line chart on tiny board / gear with circuit traces / striped awning shop front / … |
| 2 | ic_wrench / ic_heat / ic_lock / ic_check / ic_close / ic_clock / ic_network / ic_prestige / ic_retire / ic_warning / ic_speedup / ic_play_ad / ic_era1-3 / ic_operations / ic_pointer_hand / ic_server | … |

- 交付后 `import_assets.py --visual` 接入，零代码；
- **验收**：operations 四卡、HUD、底部圆钮同屏时图标像一套字体：同描边、同光源、同体量。

---

## 5. L · 生命感动效（世界会呼吸）

| # | 动效 | 实现 | 预估 |
|---|---|---|---|
| L1 | 通电建筑窗光脉动：active 建筑 modulate 在 1.0↔1.06 缓慢呼吸（相位按地块 index 错开） | park_map `_process` 现有 ambient 循环里加一条 | 0.5h |
| L2 | 通电瞬间演出：供电安装完成 → 该建筑从 dark 贴图 crossfade 到 active（0.6s）+ `fx_glow_ring` 扩散 + 灯光音效——教学第一个 aha moment 的完整编排 | park_map + EventBus attachment 完成事件 | 2h |
| L3 | 建成落地：脚手架贴图淡出 → 建筑从 scale 0.9 弹入（TRANS_BACK）+ `fx_dust_puff` ×3 | 已有部分，补 crossfade | 1h |
| L4 | 金币动线终验：修复后的 `fly_coins` 从建筑屋顶飞 HUD 钱包全程可见（G2 回归确认，加一条 smoke 断言：飞行结束后 FxLayer 子节点数为 0） | fx_layer | 1h |
| L5 | 相机呼吸：闲置 8s 后相机极缓慢地漂移放大 2%（任意输入立即复位）——商店页般的「橱窗感」 | park_map camera | 1h |
| L6 | 页面切换统一化验证：所有 sheet/页面进出走 §08 动效表，无瞬移出现（人工过一遍） | — | 0.5h |

---

## 6. S · 音频套件（16 cues → 完整声景）

**新增 UI 音效（生成交付 `art-renders/audio/final/`，manifest 增 8 个 cue）：**

| cue | 描述（生成提示） |
|---|---|
| sfx_tap | soft wooden tick, 60ms, warm |
| sfx_sheet_open / sfx_sheet_close | quick airy whoosh up / down, 200ms |
| sfx_coin_tick | tiny bright coin chime, for number roll loops |
| sfx_success_chime | two-note marimba rise, 400ms |
| sfx_error_thud | muted low thump, 150ms |
| sfx_unlock_fanfare | short brass + glockenspiel flourish, 1.2s（时代/成就共用） |
| sfx_night_amb | distant cricket loop, -18dB（夜晚档底噪，C2 联动） |

**接线**：`Widgets.wire_button_motion` 统一挂 sfx_tap；sheet 创建/dismiss 挂开合；`animate_number` 大额滚动挂 coin_tick 循环；成功/失败 toast 分别挂 chime/thud。全部经 AudioService，缺失静默。

**音乐**：现有三套循环保留；欠费状态切紧张变奏已有则验证淡入淡出（2s crossfade，不许硬切）。

---

## 7. B · 品牌面（上架前置，顺手做掉）

| 项 | 说明 |
|---|---|
| App Icon 1024² | Prompt：App icon, single cartoon blue data-center building with glowing gold windows on grass, thick rounded border frame, sky-blue background, bold and readable at 60px, no text, Hay Day-like charm |
| 启动屏 | 纯色 `#8fbf5a` + 居中 logo 字标（P01 定名后补字标，先用建筑 icon） |
| 商店截图模板 | 按所有者最终预览约定，30 态桌面截图统一为 iPhone 17 Pro Max 物理分辨率 1320×2868 的一半（660×1434）；选 6 张（园区/棋盘/行情/时代演出/离线/商店）加文案条即可——留给上架阶段，本轮只确保这 6 屏无瑕疵 |

---

## 8. 执行顺序与预算

| 批次 | 内容 | 预估 |
|---|---|---:|
| ① | R1–R5 尾巴清零（含英文回归） | 0.5d |
| ② | C 色调统一（面板色收敛 + CanvasModulate + 昼夜三档） | 1d |
| ③ | W 世界地面与 props（素材生成并行；接入+回归） | 1.5d |
| ④ | I 图标全套重做（生成并行；接入零代码） | 0.5d 接入 |
| ⑤ | L 生命感动效 L1–L6 | 1d |
| ⑥ | S 音频套件接线 | 0.5d |
| ⑦ | B 品牌面 + 六屏无瑕疵终检 + 真机双语过全量 | 0.5d |
| 合计 | | **5.5d** + 素材生成 |

规则照旧：每批次独立提交、双语 30 态 + 103 逻辑测试全绿、素材缺失回退不 crash；批次②③完成后各出一张 map 前后对比图存 `docs/ui_review/`。

**本阶段完成的定义**：任取 map / dc_board / market / store / era_unlock / offline 六屏放进 App Store 截图模板，不需要任何解释就像一款成熟的商业放置游戏——这也是所有者的最终验收动作。

---

## 9. 执行验收记录

### 2026-08-03 · 批次①（R1–R5）

- [x] R1：按 A1 成品 alpha bbox `x=19..494 / y=41..207` 重测端帽与底棱；九宫格改为 `region=(16,36,480,180)`、切片 `74/12/74/22`，短 CTA 不再出现叶状端帽和拉伸底缝。
- [x] R2：glossy CTA 的 normal / hover / pressed / focus / hover-pressed 字色全部锁定纯白，保持 4u ink 描边；视觉门禁逐状态检查。
- [x] R3：`WorldActions` 高度增加 24u，左右圆钮标签移到按钮上方并加入 4u 视口安全区断言。
- [x] R4：`BestValueRibbon` 按本地化 Label 的 minimum size + 24u 自适应，单行不裁剪；中英双语门禁覆盖。
- [x] R5：英文 30/30 与简中 30/30 Metal 实渲染回归通过；`test_runner` 103/103，数据 11 表 / 双语 / 134 art IDs 通过。
- [x] 按所有者最终约定，桌面预览与自动截图统一为 660×1434（iPhone 17 Pro Max 物理分辨率的一半）；原 440×956 与误用的 402×874 批次截图作废。

### 2026-08-03 · 批次②（C · 全局色调统一）

- [x] 园区层增加按本地时间连续插值的白天 / 黄昏 / 夜晚三档色调；色值严格为 `DAY(1,0.97,0.90)`、`EVENING(1,0.88,0.78)`、`NIGHT(0.72,0.78,0.95)`，只调制 ParkMap，不污染 HUD。
- [x] 夜间 active 建筑亮度提升到 1.30；视觉回归支持 `--preview-hour`，23:00 人工截图存档。
- [x] UI 深色工作面收敛为 `ThemeMaker.SURFACE #122438`，内部分组收敛为 `SURFACE_GROUP rgba(0,0,0,0.22)`；辅助青色降为 `TEXT_SECONDARY #9fb8cc`。
- [x] map 前后对比与夜间图已按批次①/②对应提交真实回放，重新存为 `docs/ui_review/10_batch2_*_en_map.png`；三张原图均为修正后的 660×1434。
- [x] `test_runner` 103/103；英文 30/30、简中 30/30 Metal 实渲染回归通过；数据门禁通过。

### 2026-08-03 · 批次③（W · 世界地面与园区肌理）

- [x] 内置 `imagegen` 生成并交付 9 件世界素材：无缝草地 1、正交道路 2、园区道具 5、边缘雾 1；manifest 134→143，构建与技术 QA 143/143。
- [x] `ParkMap` 优先平铺 `ground_tile_grass`，缺失时回退原 `ground_tile`；道路与道具素材缺失均静默跳过，不影响玩法。
- [x] 已购地块按现有两列网格生成确定性正交路网；道具只以 plot index 决定 0–2 件，禁用随机数；dense 状态至少出现 4 种道具。
- [x] 道路草色区转为软 alpha，只保留混凝土与边缘，消除缩放后方形拼贴；边缘雾固定在视口层并以 0.50↔0.65 缓慢呼吸。
- [x] 新增 dense-campus 门禁：路段、交叉口、道具种类、环境节点预算 ≤60、雾层 alpha 范围；`test_runner` 103/103，数据与资产门禁通过。
- [x] 英文 30/30、简中 30/30 Metal 实渲染回归通过；所有输出截图精确 660×1434。
- [x] 同尺寸真实基线与结果已存 `docs/ui_review/10_batch3_before_en_map.png`、`10_batch3_after_en_map.png`、`10_batch3_compare_en_map.png`；资产联系表为 `10_batch3_world_assets_contact.png`。

### 2026-08-03 · 批次④（I · 统一图标系统）

- [x] 内置 `imagegen` 独立重绘全套 30 枚 `ic_*`，统一为蓝白金手绘 3D 材质、6px 等效深海军蓝轮廓、左上暖光与 48px 可读体量；每次生成均携带项目建筑风格锚。
- [x] 原有 27 枚图标全量替换，并补齐 `ic_operations`、`ic_pointer_hand`、`ic_server`；manifest 143→146，UI 分类 38→41。
- [x] 全部源稿、透明中间稿和最终标准化稿保留在 `art-renders/visual/work/final_look_icons/`，构建脚本可重复生成；正式成品同步到 `art-renders/visual/final/ui/` 与 `assets/art/ui/`。
- [x] `ic_network` 严格保留 3 节点 / 3 连线；紫色宝石单独采用硬色键阈值，避免主体被软遮罩误伤；服务器图标消除键色漂移导致的半透明方框（partial alpha 48.60%→0.61%）；资产技术 QA 146/146。
- [x] 48px 与全尺寸联系表存为 `docs/ui_review/10_batch4_icons_48px_contact.png`、`10_batch4_icons_full_contact.png`。
- [x] `test_runner` 103/103；英文 30/30、简中 30/30 Metal 实渲染回归通过；30 态输出全部精确为 660×1434。
- [x] 人工放大检查 HUD、FTUE、运营、科技与商店；归档真实运行截图 `10_batch4_en_operations.png`、`10_batch4_en_tech.png`、`10_batch4_en_store.png`、`10_batch4_zh_ftue_spotlight.png`，无白底、裁边、文字互压或图标体量漂移。
