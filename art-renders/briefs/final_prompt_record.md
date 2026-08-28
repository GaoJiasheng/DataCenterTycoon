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

## §10 批次⑦ · 品牌面生成提示

品牌面以既有 `app_icon.png` 为风格参考，由内置 `imagegen` 重绘；生成原稿替换
`visual/work/app_icon_source_v2.png` 与 `visual/work/splash_bg_source_v1.png`，再经
`build_final_visuals.py --only store/...` 标准化为 App Store 规格。

### App Icon

```text
Edit this into a premium iOS game app icon for Data Center Tycoon. Keep the same charming blue-and-cream cartoon data-center building design language and warm glowing gold windows, but simplify radically to ONE single compact blue data-center building centered and filling roughly 68% of the square. Place it on a clean sky-blue background with only a subtle soft grass base and warm halo. Add a bold thick rounded cream-and-gold border frame inset from the square edge, with an inner deep-blue keyline, designed to remain readable at 60px. Use strong silhouette, large simple shapes, clean hand-painted 3D mobile-game rendering, top-left warm light, high contrast. No coin, no extra buildings, no trees, no clouds, no text, no letters, no logos, no tiny details, no transparency, no mockup, no device frame. Square 1:1 icon composition; artwork must fill the entire square to all edges.
```

首稿四角出现黑色外露区，未接入；二次编辑保持主体不变，将奶油金圆框内缩约 3.5%，四角补为完整不透明的深天蓝品牌底色。最终 1024² 成品四角 RGB 均为蓝色，无透明或黑角。

#### 2026-08-14 · iOS 圆角适配重设计

旧稿把厚金色圆角框直接烘焙进源图，经过 iOS 系统圆角遮罩后形成双重边框。新版改为无边框、无预制圆角的全幅场景：主体缩入中央安全区，外侧仅保留可裁切的天空和草地。

```text
Use case: logo-brand
Asset type: production iOS mobile game App Store icon, 1024×1024 source artwork
Primary request: completely redesign the icon as one instantly readable charming compact blue data-center building, with a glowing amber server core and a small deliberate stack of polished gold coins at the front-right base. Full-bleed environment, no frame.
Scene/backdrop: sky-blue to deep-cyan atmospheric background above a small lush grass base; simple crop-safe corners.
Style/medium: top-tier polished rounded 3D casual mobile-game render, tactile painted materials, crisp silhouette, restrained detail.
Composition/framing: centered three-quarter isometric building occupying about 68–72% of the canvas; all meaningful detail inside the central 70% safe area; readable at 60px.
Constraints: opaque square source; no baked rounded corners; no border, inner frame, yellow outline, text, logo, watermark, badge, shield or corner hardware. iOS supplies the only rounded-square mask.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-2f6b936f-3d52-4e11-a5e5-33808ad46631.png`
- 可复建源图：`visual/work/app_icon_source_v2.png`
- 正式成品：`visual/final/store/app_icon.png`
- 运行时与 iOS 导出资源：`../assets/art/store/app_icon.png`

### 启动屏

```text
Create a minimalist portrait mobile game launch-screen artwork derived from this exact Data Center Tycoon app-icon design. Tall 9:16 composition. Use a perfectly clean, nearly solid grass-green background (#8FBF5A visual target) with only a very subtle lighter radial glow behind the center. Place one small centered blue data-center building emblem, matching the reference building's blue, cream, and warm-gold windows, occupying about 32% of the canvas width and positioned slightly above vertical center. No landscape, no sky, no clouds, no paths, no trees, no coins, no extra buildings, no text, no letters, no wordmark, no gradient bands, no noise, no transparency, no device mockup. Quiet premium loading screen with generous empty green breathing room; full-bleed portrait artwork.
```

Godot `boot_splash/bg_color` 同步为 `#8FBF5A`，避免载入前后边缘闪过旧的深蓝底色。

## 2026-08-12 · 建造完成扬尘重绘

使用内置 `imagegen`，以 `visual/final/buildings/dc_t1_active.png` 和旧效果实机截图作为风格/问题参考。首稿仍有较高的团状烟尘，人工审片未接入；第二稿按下列提示生成，经绿色键控去背并裁成 1024×512 宽幅透明贴图，替换 `fx_dust_puff`：

```text
Create one standalone premium mobile-game VFX sprite for a DATA CENTER BUILDING CONSTRUCTION COMPLETION reveal, matching the attached polished 2.5D isometric tycoon rendering. This replaces the bulky dust cloud visible in the second reference. Make an extremely LOW, THIN, GROUND-HUGGING dust skirt that sweeps outward horizontally along the building plinth. Maximum visible dust height must be less than 15% of the total sprite width. The entire central 45% of the sprite must remain empty/transparent so the building and its entrance are unobscured. Use wispy warm beige powder trails close to the ground, a few tiny concrete chips traveling outward, and sparse warm golden glints; no large round puffs and no dense opaque cluster. Natural irregular asymmetry with polished painterly volume and crisp game-ready edges. Absolutely NO mushroom cloud, NO explosion, NO fire, NO smoke column, NO billowing vertical cloud, NO perfect circle, NO ring, NO halo, NO radial line art, NO neon magenta/red, NO text, NO UI, NO building, NO ground plane, NO rectangular shadow. Wide horizontal composition centered with generous empty margins. Consistent light from upper left. Render against a perfectly flat solid chroma green #00FF00 background, no green spill on the effect. Square 1024x1024 image.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-1d764c03-3900-477a-8d4e-b267b6cca67a.png`
- 可复建键控源图：`visual/work/fx_dust_puff_chroma_v2.png`
- 美术交付：`visual/final/fx/fx_dust_puff.png`
- 运行时资源：`../assets/art/fx/fx_dust_puff.png`
- 实机比例前后对比：`../docs/ui_review/compare_construction_fx.png`

## 2026-08-12 · 公司成长系统正式渲染

以下七件均使用内置 `imagegen` 生成 1024² 源稿，采用相同的生产约束：premium polished 2.5D casual mobile-game render；chunky rounded blue, cream and warm-gold materials；upper-left warm light；单一清晰主体且安全留白；纯 `#ff00ff` 色键背景；no text, letters, numbers, logo, watermark, UI frame, wireframe, flat vector, geometric placeholder or rough prototype。色键源稿位于 `visual/work/meta/`，透明成品位于 `visual/final/meta/`。

### `company_roadmap`

```text
Create exactly one premium 2.5D mobile tycoon milestone icon: a charming miniature blue-and-cream data-center campus connected by a gently rising golden road with three substantial gold milestone monuments, ending at a radiant blue-and-gold company crest. Tactile hand-painted volume, rounded architectural forms, warm windows, readable at small size, no floating line diagram.
```

### `campus_strategy`

```text
Create exactly one premium 2.5D campus strategy centerpiece: a compact isometric blue-and-cream technology campus model on a landscaped plinth, surrounded by four distinct sculpted specialization emblems for hosting, cloud, AI compute and diversification. Each emblem must be a fully rendered object with depth and material, not a line icon or geometric placeholder.
```

### `customer_portfolio`

```text
Create exactly one premium 2.5D customer portfolio object: an elegant blue leather contract folio opened around four different chunky enamel-and-gold client seals representing internet, mining, cloud and AI compute, with one cream ribbon and one gold clasp. All symbols are physical rendered badges, no text and no flat UI cards.
```

### `market_review`

```text
Create exactly one premium 2.5D market decision review trophy: a small blue data-center building beside a rolled cream market ledger, a substantial gold magnifying glass, and two polished blue/gold price tokens. Express thoughtful review and comparison through objects only; no chart lines, text, numbers, panels or placeholder geometry.
```

### `board_specialties`

```text
Create exactly one premium 2.5D board strategy centerpiece: a luxurious rounded blue-and-cream executive table with three substantial sculpted departmental crests—construction hammer, operations console, and business contract—set into gold mounts, plus a central laurel-topped data-center miniature. No letters, flat icons, wireframes or UI panels.
```

### `company_collection`

```text
Create exactly one premium 2.5D company collection cabinet: a polished royal-blue archive cabinet opened to reveal carefully arranged miniature data-center, server rack, client seal, market medal and legacy trophy collectibles, with cream shelves and warm gold fittings. Museum-quality tactile objects; no text labels, grids, outline drawings or placeholder blocks.
```

### `legacy_memorial`

```text
Create exactly one premium 2.5D legacy memorial world prop: a dignified blue-and-cream stone monument on an isometric landscaped base, topped with a gold laurel and a miniature glowing data-center building, accompanied by a small blue pennant and neatly trimmed flowers. It must look like a permanent celebratory campus landmark, not a UI badge, simple geometric plinth or line-art icon.
```

ImageGen 原图依次为：

- `company_roadmap`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-05f49013-9607-45cd-9f50-aad31d6b0ef8.png`
- `campus_strategy`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-9c789964-b1b0-4280-b00f-811c4d37dfa2.png`
- `customer_portfolio`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-cf609068-8751-4742-924c-fdf02accef4e.png`
- `market_review`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-6e698b5f-c3ee-4dbb-a80c-ff78f20a0bbb.png`
- `board_specialties`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-dc3169eb-562a-4da0-86d3-4b963c3b9ba7.png`
- `company_collection`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-bdf14f40-04d0-4253-95df-c8bbfaf1651e.png`
- `legacy_memorial`: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-47a6a8a4-9605-4117-8405-26eae0f4bc16.png`

## 2026-08-15 · 客户人设半身像

十张正式人设立绘均使用内置 `imagegen` 独立生成。公共约束如下，人物描述逐张附在其后：

```text
Square 1024x1024 production character portrait for a premium polished casual mobile management game. Exactly one waist-up Chinese character, centered with safe margins, rounded high-end 2.5D painterly render, expressive friendly face, coherent royal-blue cream and warm-gold palette, warm upper-left studio lighting, subtle material texture, crisp silhouette. No text, no letters, no numbers, no logo, no watermark, no UI panel, no frame, no border, no wireframe, no geometric placeholder. Isolated on transparent background if supported; otherwise use a perfectly flat pure #ff00ff chroma-key background with no shadows or objects touching the background.
```

- `persona_internet_lin_ce`: Calm male internet SRE, early 30s, short tidy black hair, navy tech jacket and cream shirt, gold network-pin, blue tablet. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-34173e62-48f5-4c99-a2ea-d99364e575a0.png`
- `persona_internet_tang_man`: Energetic female consumer-app release manager, late 20s, dark bob, blue cardigan and cream blouse, gold smartwatch, rollout clipboard. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-a8ca449c-47d4-4d31-b141-3383dd090c38.png`
- `persona_internet_chen_lu`: Thoughtful male edge-network architect, late 30s, glasses, rolled cream shirt and blue utility vest, fiber spool, map tablet. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-c6c120a6-86ef-4480-ab36-2d20292d98ae.png`
- `persona_cloud_su_qing`: Composed female cloud procurement director, early 30s, tied-back black hair, tailored navy suit and cream blouse, blue contract tablet, gold cloud lapel pin. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-4aa1e80f-fa7b-4065-b6cc-34a278158fea.png`
- `persona_cloud_zhou_yunzhou`: Experienced male cloud capacity planner, 40s, short black hair with gray, cream knit and navy jacket, rolled data-center plans and gold ruler. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-11d3bfd9-df5a-4cbc-ae10-d24b33c38580.png`
- `persona_cloud_xu_an`: Bright female cloud migration coordinator, late 20s, round glasses and ponytail, blue technical hoodie and cream utility vest, three backup drives on a gold keychain. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-060ec8a8-2665-467e-ad59-4dd081ebea6e.png`
- `persona_gpu_gu_xing`: Ambitious young male AI startup founder, late 20s, tousled black hair and tired eye circles, blue hoodie and cream jacket, gold GPU module and dark-blue laptop. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-8512fff7-ba86-48f6-8c9f-3d6768a6466a.png`
- `persona_gpu_ye_zhixing`: Assured female machine-learning research lead, mid 30s, shoulder-length black hair, cream laboratory jacket and navy top, blue checkpoint tablet and gold stylus. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-21a0ee47-f29d-47aa-9200-7200594ffcfe.png`
- `persona_mining_zhou_lan`: Confident female cryptocurrency mining operations leader, early 40s, blue safety helmet, royal-blue work jacket and cream shirt, gold energy meter and chain-status clipboard. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-53bfdef3-79b1-4525-ba75-9d03c2ed05bc.png`
- `persona_mining_lu_sen`: Seasoned male mining operations manager, early 50s, salt-and-pepper hair and beard, navy field vest and cream shirt, thermos and folded blue market sheet. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-52e5ace7-bde6-4c4f-97d1-0bc15ddfe65b.png`

## 2026-08-15 · Campus cat warmth set

Shared production direction: one coherent orange tabby with cream muzzle/chest/paws, a blue leather collar and tiny gold server tag; premium polished 2.5D casual mobile tycoon rendering, isometric three-quarter view, warm upper-left light, readable silhouette, transparent background, and no text, watermark, UI frame, rings, badges, line art, or geometric placeholders.

- `cat_sleep`: Cat curled asleep with tail wrapped naturally. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-617fc9b1-ea63-4e56-bd34-0cec44cc3d20.png`
- `cat_walk_a`: Screen-right walk cycle, front-left paw forward. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-679ad332-2962-4cec-ac1f-b6680532c5db.png`
- `cat_walk_b`: Complementary screen-right gait frame. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-5693ac91-30b0-4492-a7d8-c46706bd0284.png`
- `cat_sit`: Upright, curious sitting pose with tail curled at paws. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-02ddffd2-d2ee-452e-85f5-2a3df43ec25d.png`
- `cat_roll`: Joyful back-roll and stretch interaction pose. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-71613220-5ae2-447e-81a6-982d3e589dd2.png`
- `cat_sunglasses`: Rare-market sitting variant with blue-and-gold sunglasses. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-c4caad55-0bf1-4dc1-9213-2ba59e116d9e.png`
- `collection_cat_nap`: Cat sleeping on a warm data-center rooftop vent. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-b6a331db-9d5b-4ba9-a684-87d08dda89da.png`
- `collection_cat_parade`: Cat walking down a landscaped campus path. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-7a3f13d8-2be4-4bad-a86b-33380527e5f9.png`
- `collection_cat_watch`: Cat watching the lit campus at twilight. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-3b8cbfc1-cadf-4490-ad7b-bc4e2c9a55d7.png`
- `collection_cat_festival`: Sunglasses cat celebrating a rare market with tasteful campus decorations. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-1d637ca8-48d0-4b23-81a7-16535824c727.png`
- `fx_cat_heart`: One warm coral painterly heart with tiny gold sparkles, transparent particle sprite. Source: `/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-c49ff4d9-5b81-4285-8293-fc8ea44a1edc.png`

## 2026-08-28 · 23 号弱资产重做

### `fx_glow_ring`

```text
A standalone transparent RGBA VFX sprite, 512x512 square, for a premium cozy isometric data-center tycoon. Show a low wide asymmetrical celebration bloom made of three OPEN wisps of soft electric-blue volumetric mist, small warm-gold glow pockets, and a restrained handful of tiny rising brass sparks. It sits behind and under a machine, so keep the center calm and the silhouette low. Absolutely no closed loop, no circle, no ring, no halo, no donut, no spiral, no geometric outline, no vertical laser beam, no magenta, no rainbow, no text, no border, no building, no ground plane. Premium rendered 3D game art, coherent top-left light, restrained blue/gold/ivory palette, organic falloff, readable but subtle at 128 px. REQUIRE genuine transparent alpha outside the effect. Do not draw a checkerboard, white background, black background, or any background pattern.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-0ba8b80e-9ef4-4703-8251-aa7b2f1f76ba.png`
- 管线源图：`visual/work/23_asset_refresh/fx/fx_glow_ring_source.png`
- 正式交付：`visual/final/fx/fx_glow_ring.png`

### `fx_confetti_set`

```text
Transparent premium isometric reward burst made from miniature gold server badges, blue data packets, tiny brass bolts and soft paper flecks; coherent top-left lighting, restrained blue/gold/ivory palette, varied depth and natural trajectories, no primitive circles, no candy shapes, no text, no frame. Asset type: standalone transparent RGBA celebration particle sprite for a premium cozy data-center mobile tycoon, 512x512 square composition, readable at 128 px. Each piece must be a small tactile rendered object with material and volume, arranged as an open upward burst with a calm center so it does not cover the building. Genuine transparent alpha only; do not draw a checkerboard or background pattern.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-cc0f3597-f929-4977-8c6c-894336767dd8.png`
- 管线源图：`visual/work/23_asset_refresh/fx/fx_confetti_set_source.png`
- 正式交付：`visual/final/fx/fx_confetti_set.png`

### `plot_pad_sale`

```text
Transparent isometric undeveloped parcel for a modern data-center campus, matching the existing blue/gold industrial buildings: compacted gravel and pale concrete survey corners, subtle conduit stubs, small blue construction marker, same camera and shadow direction as dc_t1, clean silhouette, no farm soil, no wooden fence, no text. Asset type: production-ready sale plot pad for a premium cozy mobile tycoon, 768x768 square, exact centered diamond/isometric footprint, coherent top-left light, warm cream concrete with restrained royal-blue and brass details, readable at map scale. Keep the construction marker small and off the main build footprint. Genuine transparent alpha outside the parcel; no checkerboard, no frame, no UI price tag, no characters.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-6cffdce1-67a4-42b3-bc80-0bbe0f481162.png`
- 管线源图：`visual/work/23_asset_refresh/map/plot_pad_sale_source.png`
- 正式交付：`visual/final/map/plot_pad_sale.png`
- 运行时选择：`park_map.gd` 优先读取 `plot_pad_sale`，因此按真实消费链路替换该资产，保留 `plot_forsale` 回退语义。

### `panel_main`

```text
Create a production replacement for this exact light-content nine-slice UI asset, preserving its semantic contract: dark ink text will be rendered over the center, so the reading surface MUST remain warm low-glare ivory. Seamless nine-slice mobile-game page frame for a premium cozy data-center management game: restrained dark navy anodized outer frame, thin brushed-metal desaturated blue edge, subtle warm-gold fastener details only at corners, quiet warm-ivory center, generous safe slicing area, no text, no oversized cyan glow, transparent exterior. Perfectly front-facing flat orthographic 1024x1024 rounded square, exact centered symmetric geometry, four straight edges with identical thickness, matching corners, no perspective, no tilt. The central 75% must be nearly uniform matte ivory with extremely subtle paper grain and no vignette, so long dark text remains crisp. No ornaments except four small corner fasteners, no interior divider, no extra linework. Genuine RGBA alpha-zero transparency outside the rounded frame; do not draw a checkerboard, white/gray background, scene, canvas or visible backdrop.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-0a8138be-ffd3-4e87-b7b2-af0609feb2c5.png`
- 管线源图：`visual/work/23_asset_refresh/ui/panel_main_source.png`
- 正式交付：`visual/final/ui/panel_main.png`

### `dialog_bubble`

```text
Create the production tail-free BODY asset from this modular tutorial speech bubble kit prompt: Modular tutorial speech bubble kit on transparent background: one tail-free ivory rounded bubble plus separate centered/down-left/down-right pointer tails, premium soft enamel and restrained blue trim, consistent top-left light, large calm reading surface, no character, no text, no fixed pointer, nine-slice safe margins. Runtime contract for this file: the final 1024x512 canvas must contain ONLY the tail-free rounded rectangular bubble body; the centered/down-left/down-right pointer tails are already separate dynamic runtime pieces and must NOT be baked into this bitmap. Perfectly front-facing flat orthographic body, generous uniform quiet ivory reading surface, thin desaturated steel-blue enamel trim, subtle low-glare bevel, identical left/right and top/bottom corner geometry, no perspective, no bright cyan plastic, no screws, no icon, no shadow outside silhouette. Genuine alpha-zero transparent exterior; no checkerboard or visible background. Safe uninterrupted edge strips for nine-slice scaling.
```

- ImageGen 原图：`/Users/gavin/.codex/generated_images/019fbe5f-c128-7711-b816-3e32148cf91a/exec-d4005a54-223b-48ef-8812-f22eea776126.png`
- 管线源图：`visual/work/23_asset_refresh/ui/dialog_bubble_source.png`
- 正式交付：`visual/final/ui/dialog_bubble.png`
- 运行时契约：教程主体和三层动态尾巴继续由 `TutorialOverlay` 分离绘制；本图只提供无尾九宫格回退主体。
