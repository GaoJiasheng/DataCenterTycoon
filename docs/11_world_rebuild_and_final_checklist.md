# 11 · 世界空间系统重构与终检清单

> 生成于 2026-08-03，基于 10 号计划全批次执行后的 30 态截图逐屏复查 + 关键区域放大取证。
> **总判断（直说）**：单体资产这轮基本到位了——建筑组、图标（ic_cash 级别的质量）、棋盘、系统页、面板都已达标或接近达标。整体仍然「不像一线」的原因不再是资产质量，而是三件事：
> ① **世界主屏没有空间系统**——路、地块、装饰互相不对齐，建筑是「摆上去的」不是「种在园区里的」；世界主屏是玩家 80% 时间看的屏幕，它拉低了一切；
> ② **三处标记为完成但实测未修的项**（假完成）；
> ③ 若干素材细节（草地色带、图标在小尺寸下不可读、影子方向不一）。
> 本轮聚焦收敛这三件事，不铺新面。

---

## 1. 实测不达标清单（F 系列，全部有截图证据）

| # | 级别 | 问题 | 证据 | 修法摘要 |
|---|---|---|---|---|
| F1 | **P0·假完成** | 主 CTA「购买下一块地·$775」文字是**灰蓝色填充**，不是纯白（10 号文档 §9 记录 R2 已完成，实测未修） | z_cta3 放大图：文字填充 ≈ #aab6c4 | 排查 `primary_action_button` 专属路径：`_refresh_primary_action` 里的 `apply_button_color` 之后是否有 `font_color` 覆盖；用视觉门禁的对比断言真正覆盖这颗按钮（当前断言疑似漏掉了它） |
| F2 | **P0** | 路网是一条垂直灰胶带：正交俯视贴图 vs 3/4 等距建筑视角打架；路不连接任何建筑入口、不对齐地块 | campus_dense | 见 §2 世界重构 |
| F3 | **P0** | 无统一地块系统：dense 视图里建筑各坐各的白色异形底座，地块边界不可见，「买地」的空间逻辑无法被看见 | campus_dense vs map_built（后者 T0 有独立水泥垫，前者全无） | 见 §2 |
| F4 | P1 | 草地 tile 有明显对角色带（平铺后成规律条纹）；边缘雾/暗角覆盖过强，整屏像隔了脏玻璃 | campus_dense / map_built 全图 | tile 重生成（prompt 明确 no directional stripes / no vignette）；`world_edge_fog` alpha 降至 0.25 且只贴四角，去掉全屏暗角 |
| F5 | P1 | 待售地块是农场木栅栏风，与科技园区违和 | map_built | 素材重做 `plot_pad_sale`：混凝土空地 + 蓝白围挡 + 出售立牌（见 §2 清单） |
| F6 | P1 | 建筑烘焙影子方向不一致（T0 影子偏左下、T1 偏右下） | campus_dense 左上两座对比 | 重生成时统一附加 "light from upper-left, shadow falls to lower-right"；只需重生成方向错误的档（核对后列清单） |
| F7 | P1 | 棋盘安装中机柜的倒计时黑胶囊被格子裁掉一半（1m39s 只露一半） | dc_board 中上格 | 倒计时移到格子下缘外 8u 或缩为格内顶部细条+右上角时间文字；`clip_contents` 保持 |
| F8 | P1 | 计算机柜贴图深色，在格子深底上依旧看不清（09-A7 未执行或不足） | dc_board 左上格 | 重生成 `rack_compute_*`：navy 换为亮银白机身 + 蓝色 LED 面板 |
| F9 | P1 | 图标小尺寸可读性：`ic_power` 徽章上是「闪电插在篮子里」，44u 下读不出；HUD 时代图标（蓝盒）语义弱 | z_badge 放大图 / HUD 左上 | `ic_power` 重生成为纯粗闪电（gold bolt, no container）；`ic_era1-3` 重生成为「奖章框内数字 I/II/III + 时代元素」 |
| F10 | P1 | 底部圆钮标签是彩色小字（建设=橙、运营=蓝）压在世界上 | campus_dense 底部 | 标签统一白字 + ink 描边 3 + 20u |
| F11 | P0·流程 | 本轮英文 30 态未复跑 | — | 全部修复后 zh/en 双跑，恢复双语门禁纪律 |

---

## 2. 世界空间系统重构（本轮核心工程）

**原则：世界上所有东西都锚定在同一个等距地块网格上。** 不是加更多装饰，而是给已有元素立规矩。

### 2.1 网格与地垫

1. `park_map` 定义显式网格：地块槽位按固定间距排布（列距 = pad 宽 + 40u 车道，行距同理），每个槽位一块**统一地垫**；
2. 地垫素材（新，等距 3/4 与建筑同视角）：
   - `plot_pad_std`（768²）：浅灰混凝土方形地垫，圆角，四角矮桩，与建筑基座同色系——所有 T0/T1 坐它；
   - `plot_pad_large`（1024²）：同款放大——T2/T3 坐它；
   - `plot_pad_sale`（768²）：同款地垫 + 蓝白条纹围挡两段 + 立式「出售」牌（替换农场木牌，修 F5）；
   - Prompt 模板：Isometric 3/4 top-down concrete plot pad for a cartoon tech-campus game, light warm gray with subtle expansion joints, rounded corners, four short corner posts, same 30° camera as the building set, light from upper-left, soft shadow lower-right, transparent background.
3. 建筑贴图居中坐在地垫上（建筑自带的小基座与地垫叠加是可接受的，验证不穿帮即可）。

### 2.2 路网

1. 重做路素材为**等距角度**（与建筑同 30°）：`road_iso_a`（↗ 走向）、`road_iso_b`（↘ 走向）、`road_iso_cross`；浅暖灰、圆角边、两侧草色过渡；
2. 路只铺在**网格车道**（相邻地垫之间的 40u 间隔带），跟随地垫网格自动连接；扔掉现在的垂直贯穿条（修 F2）；
3. 车道尽头自然淡出（路段素材两端自带草色渐变）。

### 2.3 装饰锚点

1. 每块地垫四角外侧定义 4 个 deco 锚位；按地块 index 种子放 0–2 个（旗杆/路灯/灌木排）；
2. `deco_pylon`（变电站组，质量很好）改为**锚定**在已装供电的机房地垫右后锚位——它是供电的世界表达，不再悬浮在地块之间；
3. 树/灌木只出现在网格外围的「园区绿化带」，不进车道。

**验收**：campus_dense 重拍——所有建筑坐在统一地垫上、路沿车道连接、无悬浮装饰；把截图旋转 45° 看，网格秩序一眼可辨。存 `docs/ui_review/` 前后对比。

---

## 3. 修复细则（F1/F7–F10）

- **F1**：先写断言再修——视觉门禁把 `PrimaryWorldAction` 单独点名断言（font_color 必须纯白）；然后顺着 `_refresh_primary_action` 找覆盖源（怀疑 `_set_button_asset` 或早期遗留的 `add_theme_color_override`）。修完后 z_cta3 同位置重拍确认。
- **F7**：`datacenter_board._add_slots` 安装中分支：timer 改为格内顶部 6u 进度细条 + 右上 18u 时间文字（白+描边），不再用黑胶囊。
- **F8/F9**：素材重生成三件（rack_compute 亮化、ic_power 纯闪电、ic_era1-3 奖章化），走管线接入；F9 完成前 HUD 时代 chip 可临时用「时代 N」纯文字。
- **F10**：`round_entry` 标签样式统一 `world_text`（白+ink 描边 3）。

---

## 4. 色调微调（配合 F4）

1. `world_edge_fog`：alpha 0.5–0.65 → **0.25**，只保留四角 1/4 圆区域，中央完全无覆盖；
2. 若仍有「脏」感，去掉 fog 层改为仅在夜晚档启用；
3. 草地 v2 tile prompt：Seamless tileable cartoon lawn texture, uniform yellow-green, fine hand-painted grass strokes in random directions (NO directional stripes, NO vignette, NO large patterns), tiny clover accents at 3% density, flat even lighting, reads calm at 25% zoom.

---

## 5. 执行顺序

| 批次 | 内容 | 预估 |
|---|---|---:|
| ① | F1 断言+修复、F7、F10（纯代码，半天见效） | 0.5d |
| ② | §2 世界重构代码侧（网格/车道/锚点，先用现有素材占位跑通） | 1.5d |
| ③ | §2 素材六件 + F4 草地 v2 + F5 sale pad + F6 影子统一重生成 → 接入 | 1d 接入（生成并行） |
| ④ | F8/F9 三件小素材接入 + §4 fog 调整 | 0.5d |
| ⑤ | zh/en 双 30 态回归（F11）+ campus_dense/map_built 前后对比图 + 真机过一遍 | 0.5d |

**验收纪律升级（针对本轮出现的假完成）**：每个 F 编号关闭时必须附「同位置放大截图」贴在本文档 §6 验收记录里，文字性的「已完成」不再作数。

## 6. 验收记录（执行方填写，逐项附图）

### 批次① · 代码重灾项

- [x] **F1 · 主 CTA 中文填充恢复纯白。** 新增 `PrimaryWorldAction` 专属断言：按钮五种交互态必须为纯白，外层必须使用 4u ink 描边；同时点名检查 `PrimaryWorldActionText` 的描边层与 `PrimaryWorldActionTextFill` 的纯白填充层。断言先在旧实现上按预期失败（`campus_dense`），修复后简中 30 态通过。以下两图均取 `campus_dense` 的 `(x=155, y=1815, w=680, h=220)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F1 修复前，同位置放大](ui_review/11_f1_before_zh_zoom.png) | ![F1 修复后，同位置放大](ui_review/11_f1_after_zh_zoom.png) |

- [x] **F7 · 棋盘安装倒计时不再裁剪。** 底部黑胶囊改为格内顶部 12u 进度细条 + 右上 18u 白字时间；新增结构断言，要求计时容器完全落在 `RackSlot` 内、进度条高度不超过 14u、时间右对齐且至少 3u ink 描边。以下两图均取 `dc_board` 的 `(x=125, y=790, w=740, h=650)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F7 修复前，同位置放大](ui_review/11_f7_before_zh_zoom.png) | ![F7 修复后，同位置放大](ui_review/11_f7_after_zh_zoom.png) |

- [x] **F10 · 世界底部入口标签统一。** 建设/运营标签统一为 20u、900 字重、纯白填充、3u ink 外描边；新增双标签点名断言，禁止再次回到小号彩色字。以下两图均取 `campus_dense` 的 `(x=0, y=1620, w=990, h=430)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F10 修复前，同位置放大](ui_review/11_f10_before_zh_zoom.png) | ![F10 修复后，同位置放大](ui_review/11_f10_after_zh_zoom.png) |

### 批次② · 世界网格代码骨架（未提前关闭 F2/F3/F5）

- [x] 地块、建筑与待售地统一通过显式 `grid_slot` 排布：地块宽 344u、车道 40u、相邻槽位位移固定为 384×192（2:1 等距轴），删除奇数末项居中的破格路径。
- [x] 车道按相邻槽位自动生成六条连续连接，并以 `lane_axis=a|b` 锁定两条等距方向；visual smoke 要求 6 links / 2 axes / 7 unique slots，单元测试同时锁定坐标公式。
- [x] 四个地块角锚点落库；普通装饰每地块最多 0–2 个，供电塔只绑定已安装供电的机房后侧锚点；树与灌木只留在园区外围。
- [x] 此批严格使用既有 `plot_owned` / `ground_path_straight` 作为占位验证空间系统。旧道路仍为旋转后的正交贴图、待售地仍是农场素材，因此 **F2/F3/F5 暂不勾选关闭**，避免再次出现假完成。

  | 状态 | `campus_dense` 全图 | `map_built` 全图 |
  |---|---|---|
  | 改造前 | ![批次② 前 campus_dense](ui_review/11_batch2_before_zh_campus_dense.png) | ![批次② 前 map_built](ui_review/11_batch2_before_zh_map_built.png) |
  | 现有素材网格骨架 | ![批次② 后 campus_dense](ui_review/11_batch2_after_zh_campus_dense.png) | ![批次② 后 map_built](ui_review/11_batch2_after_zh_map_built.png) |

### 批次③ · 六件世界素材接入

- [x] **F2 · 道路透视与建筑统一。** `road_iso_a` / `road_iso_b` 已接入六段车道，运行时不再旋转正交贴图；每段必须以 `using_iso_asset=true` 通过视觉门禁，旧 `ground_path_straight` 只保留为缺失资产回退。`road_iso_cross` 已进入 manifest 与 import 管线，当前连续折线图没有真实交叉点，因此不伪造无出口路口。以下两图均取 `campus_dense` 的 `(x=75, y=280, w=840, h=1180)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F2 修复前，同位置放大](ui_review/11_f2_before_zh_zoom.png) | ![F2 修复后，同位置放大](ui_review/11_f2_after_zh_zoom.png) |

- [x] **F3 · 标准/大型统一地垫落地。** T0/T1 强制使用 `plot_pad_std`，T2/T3 强制使用独立比例的 `plot_pad_large`；地垫先按 alpha used-rect 裁切再等比装入，保证四角、承载面和建筑基脚都可见。视觉门禁点名要求 dense 状态同时出现两种生产地垫，禁止回退到旧 `plot_owned`。以下两图均取 `campus_dense` 的 `(x=75, y=300, w=840, h=980)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F3 修复前，同位置放大](ui_review/11_f3_before_zh_zoom.png) | ![F3 修复后，同位置放大](ui_review/11_f3_after_zh_zoom.png) |

- [x] **F5 · 待售地块改为科技园语义。** `plot_pad_sale` 使用暖灰混凝土、两段蓝白围挡与金币/价签图形立牌，彻底移除农田、木栅栏和木牌；资产缺失时仍可回退旧素材。以下两图均取 `map_built` 的 `(x=430, y=720, w=510, h=620)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F5 修复前，同位置放大](ui_review/11_f5_before_zh_zoom.png) | ![F5 修复后，同位置放大](ui_review/11_f5_after_zh_zoom.png) |

- [x] 六件素材均通过正式 `import_assets.py --visual` 管线进入 `assets/art/map/`；manifest 从 146 扩展至 152，尺寸、RGBA、透明边界和残余洋红均通过严格资产检查。完整生成 prompt、源图与交付路径见 [11_world_asset_prompts.md](11_world_asset_prompts.md)。
- [x] **F4 · 草地平铺与世界雾完成收敛。** 草地 v2 使用随机方向细草笔触与约 3% 小型三叶草，通过 48px 对边 cosine blend 后左右/上下边界像素误差均为 0；调色板压缩后 1024² 成品 775,855 bytes。`world_edge_fog` 呼吸范围从 0.50–0.65 降至 0.225–0.275，中央保持透明，并由视觉门禁锁定。以下两图均取 `campus_dense` 的 `(x=0, y=180, w=990, h=620)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F4 修复前，同位置放大](ui_review/11_f4_before_zh_zoom.png) | ![F4 修复后，同位置放大](ui_review/11_f4_after_zh_zoom.png) |

  | 批次③完整运行态 | `campus_dense` | `map_built` |
  |---|---|---|
  | 生产素材接入后 | ![批次③ campus_dense](ui_review/11_batch3_after_zh_campus_dense.png) | ![批次③ map_built](ui_review/11_batch3_after_zh_map_built.png) |

### 批次④ · 光影与小尺寸识别收敛

- [x] **F6 · 建筑光影方向统一复核。** 对 T0–T3 的 active / dark / aged / decayed / installing / scaffold 共 24 件运行态建筑 PNG 做 Alpha 连通域审计，24/24 均不存在可分离的第二块地面投影；原截图里被判断为“反向影子”的区域实际来自旧地垫、旧道路与建筑自带基脚混合。统一标准/大型地垫后，所有建筑均保持左上受光、右下自阴影，地面接触关系由同一套地垫承载，因此无需破坏已经统一的建筑套装重生单档。以下两图均取 `campus_dense` 的 `(x=85, y=270, w=820, h=540)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F6 修复前，同位置放大](ui_review/11_f6_before_zh_zoom.png) | ![F6 修复后，同位置放大](ui_review/11_f6_after_zh_zoom.png) |

- [x] **F8 · 计算机柜从深蓝黑块改为亮银白机身。** T1/T2 的 active 与 dark 四个实际显示分支全部重生并接入；active 使用银白/暖象牙机身、炭黑托盘与青蓝 LED，dark 只关闭 LED 并轻微降亮，不再把整个外壳染成 navy。视觉门禁逐件锁定亮色中性像素占比，Godot 强制重导入后再以运行态截图验收。以下两图均取 `dc_board` 的 `(x=230, y=830, w=380, h=330)`：

  | 修复前 | 修复后 |
  |---|---|
  | ![F8 修复前，同位置放大](ui_review/11_f8_before_zh_zoom.png) | ![F8 修复后，同位置放大](ui_review/11_f8_after_zh_zoom.png) |

- [x] **F9 · 电力与时代图标重建。** `ic_power` 删除篮子/插座容器，只保留占画布主体的粗金色闪电；`ic_era1-3` 改为同一套深蓝珐琅、金边与巨大 I/II/III 的圆形奖章，HUD 44u 和科技路线卡均可一眼识别。视觉门禁锁定闪电的金色占比与细长轮廓，并锁定奖章的 navy 底、亮色字面和外接框。电力图以下两图均取 `map_built` 的 `(x=245, y=670, w=260, h=260)`；时代图以下两图均取科技页缩放至 990×2151 后的 `(x=135, y=780, w=720, h=360)`：

  | 电力修复前 | 电力修复后 |
  |---|---|
  | ![F9 电力修复前，同位置放大](ui_review/11_f9_power_before_zh_zoom.png) | ![F9 电力修复后，同位置放大](ui_review/11_f9_power_after_zh_zoom.png) |

  | 时代修复前 | 时代修复后 |
  |---|---|
  | ![F9 时代修复前，同位置放大](ui_review/11_f9_era_before_zoom.png) | ![F9 时代修复后，同位置放大](ui_review/11_f9_era_after_zoom.png) |

- [x] **附带修复 · 世界深度排序不得穿透系统页。** 网格重构后的地块曾直接把世界 Y 像素值写入 `z_index`，使南侧地块越过页面框；现在背景固定在 -4096、整个世界排序带固定在 -2048，地块改用与 Y 同序但封顶 1024 的 slot 排序，HUD/页面/弹层恒定处于上层。视觉门禁在每个非地图状态逐块校验世界有效 Z 必须小于 0，机房与科技页不再被世界地块盖住。

完整生成 prompt、源图、透明化过程与运行交付路径见 [11_world_asset_prompts.md](11_world_asset_prompts.md)。

### 批次⑤ · 双语终检

- [x] **F11 · 双语 30 态恢复全绿。** Godot Metal 实渲染在 990×2151（iPhone 17 Pro Max 物理分辨率的 75%）下完成简中 30/30 与英文 30/30；每态均执行裁剪、兄弟文本叠印、内容压缩、按钮字色、触控区、F1/F7/F8/F9/F10 专属断言和世界/系统页深度契约。功能回归 `103 passed / 0 failed`，数据门禁通过 11 表 / 双语 / 152 art IDs，资产门禁通过 152 art / 4 fonts / 23 audio。以下两图均取 `campus_dense` 的 `(x=70, y=270, w=850, h=1400)`，用于复核同一运行态在双语下的世界构图一致性：

  | 简中终检 | 英文终检 |
  |---|---|
  | ![F11 简中终检，同位置放大](ui_review/11_f11_zh_campus_dense_zoom.png) | ![F11 英文终检，同位置放大](ui_review/11_f11_en_campus_dense_zoom.png) |

至此 F1–F11 均已用运行态证据关闭；未修改 `core/*.gd`、`gameplay/game_rules.gd`、`gameplay/market_system.gd` 或 `data/*.json` 的玩法与数值逻辑。
