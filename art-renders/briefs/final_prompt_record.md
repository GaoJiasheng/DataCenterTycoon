# 全量视觉生成提示记录

## 生成方式与输出

全部游戏视觉素材均使用内置 `imagegen` 逐件生成，不使用程序几何图形替代。除首张风格锚外，每次生成均携带已确认的 `visual/work/dc_t1_active_v1.png` 作为风格参考；角色四个变体另携带 `guide_normal` 作为角色一致性参考。同一建筑、外挂和机柜的状态变体使用已定稿 active 图作为结构参考。

每件源图和最终输出的唯一对应关系、精确尺寸、透明要求、阴影策略与采用修订版本见 `visual_asset_manifest.json`。最终输出根目录为 `../visual/final/`。

## 公共最终提示

```text
Match the attached Data Center Tycoon style anchor: premium hand-painted casual
farm-management mobile-game production art, rich tactile painted materials,
rounded friendly silhouettes, saturated but controlled project palette, gentle
ambient occlusion, warm upper-left key light, subtly purple-blue shade planes,
crisp small-size readability, no hard black outlines. Generate exactly one
complete centered asset with generous clear margin. Spatial assets use a soft
3/4 top-down view at roughly 30 degrees. This must be final polished game art,
never a wireframe, blockout, primitive geometric placeholder, flat vector icon,
low-poly render, sterile CGI, gritty realism, horror, or cyberpunk scene.
Absolutely no text, letters, numbers, brand marks, real-world logos, signature,
watermark, unrelated objects, cropped edges, or background scenery. Transparent
assets are generated on a perfectly flat solid chroma-key field with no cast
shadow; opaque background art is full-bleed.
```

## 类别提示模板

- 建筑：以各级 active 主体为结构基准；`construction` 保留完整基础和脚手架，`dark` 关闭窗灯与 LED，`aged` 加入克制旧化，`decayed` 加入明显锈迹/故障烟与植被侵入，`ruin` 表现停运破败但保留可辨剪影。
- 供电/冷却外挂：保持约 30° 俯视和左上暖光；active 强化电光、气流或液冷辉光，idle 完整保留结构但关闭动态能量表现。
- 机柜：计算蓝、存储绿、GPU 紫；active、dark、fault、installing 四态保持同类机柜主体比例，安装态以纸箱、绑带和保护包装体现。
- 地图：草地与道路为无缝平铺；地块、树、灌木和电塔独立生成；机房内景为竖屏全幅、中央留出大面积可摆放机柜的清洁地面。
- 特效：风痕、雪花、霜斑、烟、火花、金币、光环、五色纸屑和尘团均为单帧元素；半透明边缘在本地软遮罩中恢复。
- 角色：中年工程师“老高”，黄色安全帽、蓝色工作马甲、奶油衬衫和无字平板；normal、happy、worried、alert、thinking 五种姿态保持同一五官与服装。
- 客户徽章：互联网为蓝色地球与橙色聊天气泡，挖掘为金色晶体与镐，云计算为白云与三段上行箭头，GPU 为紫色抽象芯片；全部避免真实品牌。
- UI：面板和按钮为可触摸的手绘 9-slice 元件，中心无字；30 枚图标逐枚生成，单主体、粗圆轮廓、48px 可读，不使用代码绘制的线框图形。
- 商店：应用图标与启动图为不透明全幅插画；三档礼包按木箱、宝箱、金色金库逐级强化价值感；去广告徽章使用蓝色轻盈曲带而非负面红斜杠。

## 最终返修决策

- `dc_t2_active`：采用完整电缆桥与 4 台屋顶 HVAC 的修订版。
- `power_t1_active`：采用洋红色键修订版，避免黄色电光边缘被绿色污染。
- `cool_liquid_t2_active/idle`：采用严格 3 个主冷却缸的 v2 修订版。
- `ic_network`：采用 v3，严格 3 个节点与 3 条连线，无多余中心节点。

## 后处理

色键背景先由 imagegen 技能随附的 `remove_chroma_key.py` 移除，再由 `finish_transparent_asset.py` 做一像素 matte 收缩、局部中值去色溢、精确画布缩放和按类别控制的接触阴影。最终构建与尺寸/透明/体积 QA 由 `build_final_visuals.py` 复现。

## §10 批次③ · 园区环境生成提示

以下 9 件素材均由内置 `imagegen` 独立生成，源稿保存于 `visual/work/final_look_10/`，成品保存于 `visual/final/map/`。

### 草地

```text
Use case: stylized-concept. Asset type: seamless tileable game texture for a premium mobile idle/tycoon game. A seamless square cartoon grass texture for a growing technology campus: soft yellow-green grass using #8fbf5a as the base, subtle diagonal mowing stripes, sparse tiny clover patches and restrained short grass blades. Polished chunky 3D-cartoon mobile-game texture with warm friendly farm-game charm, evenly distributed micro-detail, no central focal point, soft diffuse daytime light, very low contrast so buildings remain the focus. All four edges must tile seamlessly. No objects, paths, stones, flowers, shadows, text, logos, border, vignette, gradient, watermark, or high-contrast patches.
```

### 道路（straight / cross 分别生成）

```text
Use case: stylized-concept. Asset type: game environment path tile. A light-gray concrete pedestrian path for a cartoon technology campus, with cream-light-gray concrete, rounded grass-blended shoulders and restrained expansion joints. Polished chunky 3D-cartoon mobile-game art matching cream foundations and blue data-center buildings, soft diffuse top light, low contrast, no perspective vanishing point. Straight: path reaches exact left/right edges through center. Cross: equal-width paths reach the center of all four edges in a perfectly symmetrical junction. Square tile; no buildings, props, signs, people, text, logos, border, vignette, or watermark.
```

### 园区道具（flagpole / lamp / bush row / parking / transformer yard 分别生成）

```text
Use case: stylized-concept. Asset type: isometric game environment prop. Exactly one premium technology-campus prop: [a slim flagpole with sky-blue pennant and cream-gold base / a compact navy campus lamp with warm gold light / three neat rounded ornamental bushes with cream edging stones / a tiny clean parking bay with two blue-cream EVs / a fenced yard with two navy-cream transformers]. Polished chunky rounded 3D-cartoon mobile-game art in the same visual family as the cream-and-blue data-center buildings, consistent 30-degree isometric view facing lower-left, blue-cream-gold accents, crisp silhouette at 64px, generous padding, soft top light and restrained baked elliptical contact shadow. Perfectly flat solid #ff00ff chroma-key background with no gradient, texture, floor plane, reflections, or lighting variation. Do not use #ff00ff in the subject. No scenery, people, text, logo, border, or watermark.
```

### 边缘雾

```text
Use case: stylized-concept. Asset type: game environment edge-fog mask texture. A clean wide soft radial edge haze mask: pure black center fading smoothly toward pale warm ivory #fff4d8 at outer edges and corners. Extremely smooth low-frequency airbrush gradient, wide 2:1 landscape, central 55 percent pure black and clear, corners slightly strongest. No objects, clouds, wisps, noise, texture, banding, border line, vignette ring, text, logo, or watermark; smooth enough to convert luminance into alpha.
```

## §10 批次④ · 统一图标系统生成提示

以下 30 枚图标均由内置 `imagegen` 独立生成，并携带
`visual/final/buildings/dc_t1_active.png` 作为项目材质与配色参考。源稿、去色键中间稿与最终标准化稿分别保存于
`visual/work/final_look_icons/*_chroma.png`、`*_alpha.png`、`*_final.png`，成品保存于
`visual/final/ui/ic_*.png`。

### 公共提示

```text
Use case: stylized-concept
Asset type: production game UI icon for a premium mobile idle/tycoon game
Primary request: create exactly one {ICON_SUBJECT}
Style/medium: chunky rounded hand-painted 3D cartoon icon; same friendly tactile material language and blue-cream-gold palette as the attached Data Center Tycoon building style reference; thick consistent dark-navy outline equivalent to 6px at 512px; soft warm top-left light; slight front-facing 3/4 tilt; polished top-tier casual mobile-game quality
Composition/framing: single centered subject, balanced visual mass, generous even padding, completely inside frame, instantly readable at 48px
Scene/backdrop: perfectly flat uniform solid #ff00ff chroma-key field for local background removal; no floor plane, gradient, texture, reflections, or lighting variation in the background
Constraints: do not use #ff00ff anywhere in the subject; no cast shadow outside the icon silhouette; no scenery, UI panel, container tile, text, letters, numbers, real logo, border, signature, or watermark
Avoid: thin lines, flat vector art, emoji style, clip art, photorealism, gritty cyberpunk, excessive tiny detail, asymmetrical padding, cropping
```

### 逐件主体映射

- 高频资源：`ic_cash` 三枚金币与折叠蓝色钞票；`ic_diamond` 紫色切面宝石；`ic_build` 蓝白羊角锤；`ic_market_up` 深蓝行情板、蓝色上行线与金箭头；`ic_tech` 金齿轮与三条蓝色电路线；`ic_shop` 蓝白店面与条纹雨棚；`ic_settings` 奶油齿轮、蓝色轮毂与金色紧固件；`ic_contract` 奶油卷轴、蓝丝带与金印章；`ic_power` 金色闪电插入蓝色插头；`ic_cooling` 蓝色涡轮风扇与奶油边框。
- 系统资源：`ic_wrench` 蓝钢活动扳手；`ic_heat` 深蓝格栅与三道橙色热浪；`ic_lock` 蓝色挂锁；`ic_check` 绿色奖章上的奶油勾；`ic_close` 珊瑚奖章上的奶油叉；`ic_clock` 蓝边奶油闹钟；`ic_network` 严格三个蓝节点与三条金线；`ic_prestige` 金月桂与蓝星；`ic_retire` 奶油安全帽、蓝色门与向外金箭头；`ic_warning` 金三角警示牌；`ic_speedup` 蓝色秒表与双奶油快进箭头；`ic_play_ad` 蓝屏、奶油播放符号与无字金票券。
- 世界与状态资源：`ic_era1` 集装箱机房；`ic_era2` 双窗双冷却器中型机房；`ic_era3` 一对连通高层塔楼；`ic_operations` 三表盘深蓝控制台；`ic_pointer_hand` 蓝袖口奶油手套指针；`ic_market_down` 深蓝行情板、蓝色下行线与珊瑚箭头；`ic_bankrupt` 裂开的蓝白钱包与坠落金币；`ic_server` 立式蓝色服务器机柜。

### 后处理与验收

- 通用图标使用技能随附 `remove_chroma_key.py --key-color '#ff00ff' --soft-matte --transparent-threshold 18 --opaque-threshold 80 --edge-feather 0.6 --edge-contract 1 --spill-cleanup`；紫色宝石为保护主体紫色，单独使用硬阈值 `--tolerance 14`。`ic_server` 源图的键色场在 `#ef0cd6` 周围轻微漂移，单独使用 `transparent=70 / opaque=180` 的宽软阈值，消除浅色底可见的全画布半透明 veil。
- `finish_transparent_asset.py --size 512 --margin 0.045 --no-shadow` 统一画布、体量和安全边距；`build_final_visuals.py` 复现全部成品。
- 30 枚缩至 48px 的人工检查联系表：`docs/ui_review/10_batch4_icons_48px_contact.png`；全尺寸联系表：`docs/ui_review/10_batch4_icons_full_contact.png`。
