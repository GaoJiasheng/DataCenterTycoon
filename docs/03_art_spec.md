# 03 · 美术规格与素材清单（AI 生成用）

> 本文档面向「把美术外包给 AI 生成模型」的工作流。每个素材给出：文件名、尺寸、用途、状态变体、完整英文 prompt。
> **prompt 用英文**（生成模型对英文理解最好），其余说明用中文。
> 交付验收标准见 §9，不达标必须重生成。

## 1. 全局风格规范（Style Bible）

| 维度 | 规范 |
|---|---|
| 总体风格 | 休闲农场手游质感（Hay Day 一类）：圆润造型、明快饱和色、柔和手绘渐变、轻微 AO 阴影、亲切愉快 |
| 视角 | 3/4 俯视（约 30° 俯角），**所有建筑/物件统一此视角**；不用严格等轴测（isometric），要更柔和的透视感 |
| 光照 | 统一暖阳光，光源方向**左上**，投影为柔和的椭圆形接触阴影（阴影透明度 ~35%） |
| 描边 | 无硬描边；靠色彩明度对比塑形（Hay Day 式），暗部略偏紫、亮部略偏黄 |
| 禁止 | 像素风、写实照片风、纯 3D 渲染感、任何画面内文字/字母/数字、水印 |
| 输出 | 单物体素材：PNG、完全透明背景、主体居中、四周留 5% 空白；场景/背景：PNG 或 JPG 不透明 |
| 分辨率 | 按清单标注生成（均为 @2x 逻辑尺寸；Godot 内再缩放）。生成模型若只支持 1024/2048 方图，按方图生成后裁切 |

### 1.1 调色板（所有 prompt 中引用这些色值）

| 名称 | HEX | 用途 |
|---|---|---|
| Sky Blue（主色） | `#3AA7F0` | 品牌主色、机房主体、UI 主按钮 |
| Deep Navy | `#2B3A55` | 未通电状态、夜色、描影 |
| Grass Green | `#7BC94C` | 地面草地、确认/成功 |
| Sunny Yellow | `#FFC93C` | 金币、高亮、灯光 |
| Warm Orange | `#FF8A3D` | 建设/工地、次级按钮 |
| Alert Red | `#FF5A5A` | 故障、警告、破产 |
| Tech Purple | `#9B6BF3` | GPU 相关、钻石、稀有感 |
| Ice Cyan | `#9FE8FF` | 冷却特效、液冷 |
| Cream White | `#FFF6E8` | UI 面板底色、云朵 |
| Earth Brown | `#B07B4F` | 泥土地块、木质围栏 |

### 1.2 STYLE CORE（每条 prompt 的公共前缀）

生成任何素材时，将下面这段放在 prompt 最前面（后文以 `[STYLE]` 指代）：

```
Casual mobile farm-game art style (like Hay Day): soft rounded shapes, bright
saturated hand-painted colors, smooth gradients, gentle ambient occlusion, cute
and friendly mood, 3/4 top-down view at roughly 30 degrees, warm sunlight from
the top-left, soft elliptical contact shadow under the object, no outlines,
no text, no letters, no numbers, no watermark, no logo. Single object centered
on a fully transparent background with 5% margin. High detail, crisp silhouette,
mobile game asset quality.
```

统一负面提示（支持 negative prompt 的模型使用，后文以 `[NEG]` 指代）：

```
pixel art, photorealistic, 3D render, realistic photo, text, letters, numbers,
watermark, signature, blurry, dark, horror, gritty, isometric grid lines,
harsh black outlines, background scenery, human faces with realistic skin
```

### 1.3 命名与目录

```
assets/art/
  buildings/   机房本体（各等级 × 各状态）
  attachments/ 供电、冷却外挂件
  racks/       机柜（机型 × 状态）
  map/         地块、地面、装饰
  fx/          特效序列帧
  characters/  导师角色
  customers/   客户阵营徽章
  ui/          图标、面板、按钮
  store/       App icon、商店素材
```
文件名全小写下划线：`{类别}_{名称}_{状态}.png`，如 `dc_t1_active.png`。

## 2. 建筑：机房本体（buildings/）

尺寸：T0/T1 为 **768×768**，T2 为 **1024×1024**，T3 为 **1280×1280**（体量递增在地图上要一眼可辨）。
每个等级需要 6 个状态变体。**同一等级的所有状态必须由同一张基础图改绘/重绘，保持轮廓一致**（生成时先出 `active` 态，再用 img2img/编辑模式做其余状态）。

状态后缀与通用改绘说明：

| 状态 | 后缀 | 改绘要点（附加到 prompt 末尾） |
|---|---|---|
| 建设中 | `_construction` | `under construction: bare steel frame and scaffolding, orange safety cones, a small yellow crane, wooden crates, sandy ground, no lights` |
| 通电运行 | `_active` | `fully powered and lively: windows glowing warm yellow (#FFC93C), tiny blinking green and blue server lights visible through windows, subtle light halo` |
| 未通电 | `_dark` | `unpowered and dormant: entire building desaturated to dark navy-gray (#2B3A55), windows dark, no glow, slightly gloomy but still cute` |
| 老化 | `_aged` | `aged and worn: faded paint, a few brown rust stains (#B07B4F) on walls, one cracked panel, small weeds at the base, lights still on but dimmer` |
| 衰退 | `_decayed` | `heavily deteriorated: large rust patches, cracked walls, a flickering broken light, thin gray smoke wisp from the roof vent, sagging cables` |
| 废墟 | `_ruin` | `abandoned ruin: collapsed roof section, boarded windows, debris and rubble around the base, completely dark, tiny plants growing through cracks` |

### 2.1 dc_t0（集装箱机房）— 6 状态

```
[STYLE] A small cute shipping-container data center: one sky-blue (#3AA7F0)
cargo container with rounded corners sitting on a concrete slab, a small
ventilation grille on the side, a single stubby antenna on top, one cable
conduit running to the ground. Compact, humble, starter-building feeling.
[状态改绘句] [NEG]
```

### 2.2 dc_t1（标准机房）— 6 状态

```
[STYLE] A small single-story data center building: sky-blue (#3AA7F0) metal
walls with cream-white (#FFF6E8) trim, flat roof with two cute rooftop HVAC
boxes, a row of round porthole windows showing server racks inside, a small
entrance door with a tiny awning, cable trays along one wall. Friendly
tech-shed personality, like a high-tech barn.
[状态改绘句] [NEG]
```

### 2.3 dc_t2（大型机房）— 6 状态

```
[STYLE] A medium two-story data center campus building: main hall with
sky-blue (#3AA7F0) panels and a glass lobby strip, cream-white (#FFF6E8)
accents, rooftop with four HVAC units and a satellite dish, an external
cable bridge, small hedges at the entrance. Confident mid-game upgrade
feeling, noticeably larger and more polished than a small server shed.
[状态改绘句] [NEG]
```

### 2.4 dc_t3（超大规模机房）— 6 状态

```
[STYLE] A grand hyperscale data center: long sleek hall with a gently curved
roof, sky-blue (#3AA7F0) and tech-purple (#9B6BF3) accent stripes, rows of
glowing porthole windows, a tall communications mast with a blinking beacon,
two cooling towers at the back emitting tiny white steam puffs, landscaped
surroundings with solar panels. Impressive end-game flagship feeling, still
cute and rounded, never militaristic.
[状态改绘句] [NEG]
```

## 3. 外挂件（attachments/）

尺寸统一 **512×512**。

### 3.1 供电单元 — 3 等级 × 2 状态（`_active` / `_idle`）

| 文件 | prompt 主体描述 |
|---|---|
| `power_t1` | `[STYLE] A cute small electric transformer box: warm-orange (#FF8A3D) metal cabinet on a tiny concrete base, one ceramic insulator on top, a single power cable coiling to the ground, a small lightning-bolt shaped vent (abstract shape, not a symbol). [状态] [NEG]` |
| `power_t2` | `[STYLE] A cute compact electrical substation: two orange (#FF8A3D) transformer cabinets connected by pipes, small lattice frame with three ceramic insulators, thick cables, low safety fence around the base. [状态] [NEG]` |
| `power_t3` | `[STYLE] A cute high-voltage power station: tall lattice pylon-like structure with large ceramic insulators, three big orange (#FF8A3D) transformer tanks with cooling fins, bundled heavy cables, sturdy concrete base. Powerful but friendly. [状态] [NEG]` |

状态改绘句：
- `_active`: `energized: insulators glowing sunny-yellow (#FFC93C), tiny electric sparkle dots around the top, cables slightly glowing`
- `_idle`: `switched off: no glow, colors slightly desaturated`

### 3.2 冷却单元 — 4 种 × 2 状态（`_active` / `_idle`）

| 文件 | prompt 主体描述 |
|---|---|
| `cool_air_t1` | `[STYLE] A cute air-cooling unit: white-and-ice-cyan (#9FE8FF) box fan unit with one large round fan grille facing forward, small vents on the sides, rubber feet. Like a friendly giant desk fan in an industrial casing. [状态] [NEG]` |
| `cool_air_t2` | `[STYLE] A cute double air-cooling unit: two large round fan grilles side by side in an ice-cyan (#9FE8FF) and white casing, top exhaust louvers, slightly bigger and beefier than a single-fan unit. [状态] [NEG]` |
| `cool_liquid_t1` | `[STYLE] A cute liquid-cooling unit: compact chiller cabinet in white with ice-cyan (#9FE8FF) coolant pipes looping on the outside, a small round pressure gauge (blank dial, no numbers), frost sparkles on the pipe joints, a tiny coolant tank on the side. [状态] [NEG]` |
| `cool_liquid_t2` | `[STYLE] A cute advanced liquid-cooling tower: taller chiller with three transparent coolant pipes glowing ice-cyan (#9FE8FF), visible bubbling coolant inside the pipes, frost crystals on top edges, tech-purple (#9B6BF3) accent trim. Premium end-game cooling feeling. [状态] [NEG]` |

状态改绘句：
- 风冷 `_active`: `running: fan blades blurred in motion, faint light-blue wind streaks curling out of the grille`
- 液冷 `_active`: `running: pipes glowing brighter, small ice crystals and tiny snowflake sparkles floating above, faint cold mist at the base`
- `_idle`: `switched off: no motion blur, no glow, no mist`

## 4. 机柜（racks/）

尺寸 **512×512**。机房详情页 3×3 网格中使用，也用于商店列表。
6 种机柜 × 4 状态 + 2 个通用格子素材。

通用格子素材：

| 文件 | prompt |
|---|---|
| `slot_empty` | `[STYLE] An empty server rack floor slot: a light-gray rounded square floor tile with four small mounting bolt holes at the corners and a subtle dashed inner border painted on the tile (paint marking, not UI), viewed from 3/4 top-down. Very simple and flat. [NEG]` |
| `slot_locked` | `[STYLE] A locked server rack slot: the same light-gray floor tile covered by a cute canvas dust cover sheet in cream-white (#FFF6E8) draped like cloth, tied with a small rope, a tiny padlock resting on top. [NEG]` |

机柜主体 prompt：

| 文件 | prompt 主体描述 |
|---|---|
| `rack_compute_t1` | `[STYLE] A cute compute server rack cabinet: sky-blue (#3AA7F0) rounded rack cabinet, front face full of horizontal server blades with tiny green LED dots, small handles on each blade, ventilation slits on the side. Tidy and dependable personality. [状态] [NEG]` |
| `rack_storage_t1` | `[STYLE] A cute storage server rack cabinet: grass-green (#7BC94C) rounded rack cabinet, front face showing rows of small square disk drive bays with tiny amber LED dots, one slightly ajar drawer revealing disk shapes. Chunky and calm personality. [状态] [NEG]` |
| `rack_gpu_t1` | `[STYLE] A cute GPU server rack cabinet: tech-purple (#9B6BF3) rounded rack cabinet with three large glowing vents on the front, visible chunky graphics-card-like modules with tiny fans, subtle purple glow seeping from the vents. Powerful and flashy personality. [状态] [NEG]` |
| `rack_compute_t2` | 同 compute_t1 基础上追加：`upgraded premium version: taller, darker blue body with sunny-yellow (#FFC93C) accent stripes, denser blades, brighter LEDs` |
| `rack_storage_t2` | 同 storage_t1 基础上追加：`upgraded premium version: taller, deeper green with cream accents, double-width disk bays, brighter amber LEDs` |
| `rack_gpu_t2` | 同 gpu_t1 基础上追加：`upgraded premium version: taller, black-purple body with glowing purple coolant tubes on the front, intense purple glow, small heat fins on top` |

状态改绘句（每种机柜 4 状态）：

| 状态 | 后缀 | 改绘句 |
|---|---|---|
| 运行 | `_active` | `powered on: all LEDs lit and cheerful, soft glow` |
| 断电 | `_dark` | `unpowered: desaturated to dark navy-gray (#2B3A55), all LEDs off` |
| 故障 | `_fault` | `malfunctioning: a thin gray smoke wisp rising from the top, one panel popped open at an angle, LEDs turned alert-red (#FF5A5A), tiny orange spark dots` |
| 安装中 | `_installing` | `being installed: cabinet wrapped in cardboard packaging half-removed, packing straps, a small wrench and screws lying on the floor tile` |

## 5. 地图与装饰（map/）

| 文件 | 尺寸 | prompt |
|---|---|---|
| `ground_tile` | 1024×1024，**无缝平铺** | `[STYLE] Seamless tileable grass ground texture for a casual farm game: fresh grass-green (#7BC94C) lawn with subtle hand-painted tufts, occasional tiny daisies and small dirt speckles, very low contrast so buildings pop on top. Top-down view, perfectly seamless edges. Opaque, no shadow. [NEG]` |
| `plot_forsale` | 768×768 | `[STYLE] An empty land plot for sale: a rounded rectangle of earth-brown (#B07B4F) tilled soil with a low wooden stake fence on two sides, a cute blank wooden signpost standing at the front corner (blank sign face, no text), a few pebbles and grass tufts. [NEG]` |
| `plot_owned` | 768×768 | `[STYLE] A purchased empty land plot: a rounded rectangle of neatly flattened light-gray gravel and concrete foundation pad, corner survey stakes with tiny red flags, clean and ready for construction. [NEG]` |
| `deco_road` | 512×512 无缝 | `[STYLE] Seamless tileable light-gray paved path texture: smooth rounded concrete pavement with subtle panel seams and a few hand-painted wear marks. Top-down, seamless. [NEG]` |
| `deco_tree` | 384×384 | `[STYLE] A cute round fluffy tree: bright green rounded canopy in two shades of green, short brown trunk, three tiny red fruits. Classic casual-game tree. [NEG]` |
| `deco_bush` | 256×256 | `[STYLE] A small cute rounded bush in two shades of grass-green (#7BC94C) with tiny yellow flowers. [NEG]` |
| `deco_pylon` | 512×512 | `[STYLE] A cute miniature electricity pylon: small friendly lattice tower in warm gray with orange (#FF8A3D) top caps, two drooping power lines ending off-frame, rounded proportions. [NEG]` |
| `dc_interior_bg` | 1536×2048（竖屏机房详情页背景，不透明） | `[STYLE] Interior background of a cute data center room viewed from 3/4 top-down: light cool-gray raised floor with subtle square panel seams forming an open center area (empty, this is where a 3x3 grid UI will be drawn on top), cream-white (#FFF6E8) walls with sky-blue (#3AA7F0) trim, cable trays along the top wall, soft ceiling light pools, a glass door on one side. Calm, spacious, uncluttered center. Opaque image. [NEG]` |

## 6. 特效（fx/）— 序列帧或单帧+程序动画

优先做法：生成**单帧**素材，动画用 Godot 粒子/补间实现（省素材、效果更活）。以下均为单帧元素图，透明背景。

| 文件 | 尺寸 | prompt |
|---|---|---|
| `fx_wind_streak` | 256×256 | `[STYLE] A single stylized wind swirl streak: one elegant curling wind line in translucent light-blue-white gradient, comma shape, cartoon airflow. [NEG]` |
| `fx_snowflake` | 128×128 | `[STYLE] A single cute six-pointed snowflake sparkle in ice-cyan (#9FE8FF) with a soft white glow core. Simple and readable at small size. [NEG]` |
| `fx_frost_patch` | 256×256 | `[STYLE] A patch of cartoon frost crystals: cluster of small translucent ice-cyan (#9FE8FF) crystal shards with white sparkle dots, flat-ish so it can sit on pipe surfaces. [NEG]` |
| `fx_smoke_puff` | 256×256 | `[STYLE] A single soft cartoon smoke puff: rounded fluffy gray cloud blob with lighter top and darker bottom, semi-transparent edges. [NEG]` |
| `fx_spark` | 128×128 | `[STYLE] A single cartoon electric spark: small four-pointed star burst in sunny-yellow (#FFC93C) core with orange (#FF8A3D) tips, slight glow. [NEG]` |
| `fx_coin` | 192×192 | `[STYLE] A single shiny gold coin, front view, sunny-yellow (#FFC93C) with a simple abstract server-rack embossed shape in the center (abstract geometric emboss, not text), thick cartoon rim, star glint. [NEG]` |
| `fx_glow_ring` | 512×512 | `[STYLE] A soft radial glow ring: warm yellow-white translucent halo ring fading to transparent, for highlighting buildings at night. [NEG]` |
| `fx_confetti_set` | 512×512 | `[STYLE] A scattered set of about 20 cartoon confetti pieces in sky-blue, sunny-yellow, orange, purple and green: small rounded rectangles, circles and stars on transparent background, spread apart so pieces can be cropped individually. [NEG]` |
| `fx_dust_puff` | 256×256 | `[STYLE] A single cartoon construction dust puff: sandy beige fluffy cloud blob with tiny debris specks, semi-transparent edges. [NEG]` |

## 7. 角色与客户徽章

### 7.1 导师角色「老高」（characters/）— 5 姿态

尺寸 **768×1024**（半身立绘，透明背景），用于引导对话框。基础形象 prompt：

```
[STYLE] Character bust illustration for dialogue box: a cheerful middle-aged
male data-center engineer mascot, round friendly face, thick eyebrows, short
black hair, wearing a sunny-yellow (#FFC93C) hard hat and a sky-blue (#3AA7F0)
work vest over a cream shirt, holding a tablet. Big expressive cartoon eyes,
warm smile, stylized proportions with a slightly big head (casual-game mascot
ratio, about 3 heads tall for the bust). Front 3/4 angle facing right.
[姿态] [NEG]
```

| 文件 | 姿态改绘句 |
|---|---|
| `guide_normal` | `pose: friendly open-palm welcome gesture, warm smile` |
| `guide_happy` | `pose: both fists raised in celebration, beaming grin, eyes squeezed happily` |
| `guide_worried` | `pose: scratching the back of his head, sweat drop on temple, worried frown, looking at his tablet` |
| `guide_alert` | `pose: pointing forward urgently with one hand, alarmed wide eyes, mouth open mid-shout` |
| `guide_thinking` | `pose: one hand on chin, eyes looking up thoughtfully, small tilt of the head` |

> 全部 5 姿态必须同一形象。做法：先生成 `guide_normal` 定稿，其余 4 张用该图作参考图（img2img / character reference）生成。

### 7.2 客户阵营徽章（customers/）— 4 枚

尺寸 **384×384**，圆形徽章构图，用于合约面板与行情页。**必须是抽象图形，避免影射真实公司。**

| 文件 | prompt |
|---|---|
| `client_internet` | `[STYLE] A round badge icon for an internet company faction: glossy circular badge with sky-blue (#3AA7F0) rim, inside a cute abstract globe made of rounded meridian lines with a small orange chat-bubble shape orbiting it. Flat-ish icon style, slight bevel, no text. [NEG]` |
| `client_mining` | `[STYLE] A round badge icon for a crypto-mining faction: glossy circular badge with sunny-yellow (#FFC93C) rim, inside a cute faceted gold hexagonal crystal coin with a tiny pickaxe crossed behind it, sparkle glints. No text, no real cryptocurrency logos. [NEG]` |
| `client_cloud` | `[STYLE] A round badge icon for a cloud-computing company faction: glossy circular badge with cream-white rim, inside a fluffy rounded white cloud with a small upward arrow made of three rounded segments beneath it, sky-blue background. No text. [NEG]` |
| `client_gpu` | `[STYLE] A round badge icon for an AI/GPU company faction: glossy circular badge with tech-purple (#9B6BF3) rim, inside a cute abstract chip: rounded square with small legs on four sides and a glowing purple spark-star at its center. No text, no real brand references. [NEG]` |

## 8. UI 套件（ui/）

> UI 是生成模型的弱项。策略：**面板/按钮生成后做 9-slice 切片**，图标逐个单独生成。所有 UI 素材禁止内嵌文字，文字一律由游戏字体渲染。

### 8.1 面板与按钮（9-slice）

| 文件 | 尺寸 | prompt |
|---|---|---|
| `panel_main` | 1024×1024 | `[STYLE] A mobile game UI panel: rounded rectangle card in cream-white (#FFF6E8) with a thick soft sky-blue (#3AA7F0) border frame, subtle inner drop shadow, tiny rivet dots in the four corners, plain empty center area. Clean, symmetric, suitable for 9-slice scaling. [NEG]` |
| `panel_dark` | 1024×1024 | 同上，改：`deep-navy (#2B3A55) semi-opaque panel with ice-cyan thin border, for market charts` |
| `btn_primary` | 512×256 | `[STYLE] A mobile game button: horizontal rounded pill button in bright grass-green (#7BC94C) with darker green bottom edge (thick 3D bottom lip), glossy top highlight, plain center. Symmetric, 9-slice friendly. [NEG]` |
| `btn_secondary` | 512×256 | 同上，改 `sky-blue (#3AA7F0)` |
| `btn_warning` | 512×256 | 同上，改 `warm-orange (#FF8A3D)` |
| `btn_danger` | 512×256 | 同上，改 `alert-red (#FF5A5A)` |
| `btn_disabled` | 512×256 | 同上，改 `flat desaturated gray, no gloss` |
| `btn_ad` | 512×256 | 同上，改 `tech-purple (#9B6BF3) with a subtle sparkle sheen` （激励视频专用色） |
| `progress_frame` | 512×128 | `[STYLE] A mobile game progress bar frame: horizontal rounded capsule trough in dark navy (#2B3A55) with cream rim, empty inside. 9-slice friendly. [NEG]` |
| `progress_fill` | 512×128 | `[STYLE] A progress bar fill: horizontal rounded capsule in glossy sunny-yellow (#FFC93C) to orange gradient with a moving-shine highlight band. [NEG]` |
| `dialog_bubble` | 1024×512 | `[STYLE] A speech dialogue panel: wide rounded rectangle in cream-white with soft blue border and a small tail pointing to the bottom-left, comic style, plain center. [NEG]` |

### 8.2 图标（统一 256×256，圆润扁平+微立体，构图撑满 80% 画幅）

图标公共前缀（`[ICON]`）：
```
[STYLE] A single mobile game UI icon, chunky rounded flat style with subtle
top-light bevel, bold silhouette readable at 48 pixels, centered.
```

| 文件 | 主体描述 |
|---|---|
| `ic_cash` | `[ICON] a stack of three gold coins (#FFC93C) with a small banknote behind` |
| `ic_diamond` | `[ICON] a glossy faceted diamond gem in tech-purple (#9B6BF3) with white glints` |
| `ic_power` | `[ICON] a bold lightning bolt in sunny-yellow (#FFC93C) with orange rim` |
| `ic_cooling` | `[ICON] a six-pointed snowflake in ice-cyan (#9FE8FF) on a small round light-blue base` |
| `ic_heat` | `[ICON] three wavy rising heat lines in orange-red gradient` |
| `ic_wrench` | `[ICON] a chunky crossed wrench and screwdriver in warm gray with orange handles` |
| `ic_warning` | `[ICON] a rounded triangle warning sign in sunny-yellow with an exclamation mark shape (abstract thick bar and dot)` |
| `ic_clock` | `[ICON] a cute round alarm clock in sky-blue with cream face, blank face without numbers` |
| `ic_contract` | `[ICON] a rolled paper scroll with a red wax seal ribbon` |
| `ic_market_up` | `[ICON] a rising zigzag arrow chart line in grass-green on a tiny dark chart panel` |
| `ic_market_down` | `[ICON] a falling zigzag arrow chart line in alert-red on a tiny dark chart panel` |
| `ic_build` | `[ICON] a chunky hammer crossing a small building silhouette, orange and blue` |
| `ic_tech` | `[ICON] a rounded gear with a small glowing chip square in its center, blue and purple` |
| `ic_shop` | `[ICON] a cute market stall canopy with red-white stripes over a small basket` |
| `ic_settings` | `[ICON] a single chunky rounded gear in warm gray` |
| `ic_network` | `[ICON] three rounded nodes connected by two thick lines forming a triangle network, sky-blue nodes with a glowing center node` |
| `ic_play_ad` | `[ICON] a rounded video play button triangle in white inside a tech-purple (#9B6BF3) rounded square with a tiny sparkle` |
| `ic_retire` | `[ICON] a cute recycling arrows loop in grass-green embracing a small gray server rack silhouette` |
| `ic_speedup` | `[ICON] a rounded rocket with orange flame trail tilted upward` |
| `ic_lock` | `[ICON] a chunky golden padlock with a keyhole` |
| `ic_check` | `[ICON] a fat rounded checkmark in grass-green` |
| `ic_close` | `[ICON] a fat rounded X cross in alert-red` |
| `ic_era1` | `[ICON] a single cute server tower with an antenna, warm gray and blue (era: colocation)` |
| `ic_era2` | `[ICON] a fluffy cloud with three tiny server racks tucked inside it (era: cloud)` |
| `ic_era3` | `[ICON] a glowing chip with a small neural-network star pattern inside, purple glow (era: AI)` |
| `ic_prestige` | `[ICON] a golden upward arrow bursting through a laurel wreath with sparkle stars` |
| `ic_bankrupt` | `[ICON] a cracked piggy bank in gray-blue with a single falling coin` |

### 8.3 商店与营销素材（store/）

| 文件 | 尺寸 | prompt |
|---|---|---|
| `app_icon` | 1024×1024（不透明，无圆角——Apple 自动加） | `[STYLE] Mobile game app icon, square full-bleed composition: one cute sky-blue (#3AA7F0) data center building with glowing warm windows at dusk, a big shiny gold coin leaning against it, grass and two tiny trees at the base, soft gradient sky from light blue to warm orange behind, subtle sparkles. Bold, readable at small size, centered hero composition, no text anywhere. [NEG]` |
| `splash_bg` | 1536×2732（竖屏，不透明） | `[STYLE] Vertical splash screen background: a cheerful hillside landscape with a winding light path, several cute data centers of different sizes glowing warmly, tiny pylons and trees, big fluffy clouds, soft morning sky. Empty area in the upper third for a logo to be composited later. No text. [NEG]` |
| `pack_starter` | 512×512 | `[STYLE] An IAP pack illustration: a small open wooden crate overflowing with gold coins and three purple diamonds, a tiny blue server rack peeking out, one sparkle. [NEG]` |
| `pack_builder` | 512×512 | `[STYLE] An IAP pack illustration: a medium treasure chest with coins, diamonds, a golden wrench and a rolled blueprint, more sparkles. [NEG]` |
| `pack_tycoon` | 512×512 | `[STYLE] An IAP pack illustration: a grand golden vault door slightly open with an avalanche of coins, a big diamond cluster and a tiny golden data center trophy, rich glow. [NEG]` |
| `noads_badge` | 512×512 | `[STYLE] A remove-ads product icon: a tech-purple rounded square with a crossed-out video play triangle behind a happy sun, clean and positive (avoid negative red slash cliché — use a soft 'free and clear' feeling). [NEG]` |

> App Store 截图（6.7"/6.5"/5.5"）用实机截图 + 上方文案条模板制作，不在本清单内；模板底图可复用 `splash_bg` 裁切。

## 9. 交付验收标准（每张图逐条检查）

1. 透明背景类素材：背景 100% 透明，无白边/灰晕（检查 alpha 通道边缘）。
2. 视角一致：所有建筑/物件为 3/4 俯视约 30°，同类素材摆在一起无违和。
3. 光照一致：光源左上；影子为柔和椭圆接触阴影。
4. **画面内零文字**：任何字母、数字、真实 logo 出现即拒收（含仪表盘刻度数字）。
5. 状态变体轮廓一致：同一建筑的 6 状态叠图对比，轮廓偏移 < 5%。
6. 色彩符合调色板：主体颜色与指定 HEX 目视一致（允许明度渐变）。
7. 缩小可读：图标缩到 48px、建筑缩到 128px 后剪影仍可辨认。
8. 风格统一测试：随机抽 6 张不同类别素材拼在同一屏，应像同一个游戏。
9. 命名与尺寸精确匹配本清单；PNG-24；单文件 ≤ 1.5MB。

## 10. 生成工作流建议

1. **先定风格锚**：用 §2.2 的 `dc_t1_active` prompt 反复生成直到项目所有者点头，该图作为全项目的风格参考图（style reference）。
2. 之后所有素材生成时携带该参考图（支持 style/character reference 的模型），保证全局统一。
3. 状态变体一律用「定稿图 + img2img/局部重绘」产出，不要从零生成。
4. 每批产出先过 §9 验收，再入库 `assets/art/`；被替换的旧版移入 `assets/art/_archive/`。
5. 素材总量：建筑 24 + 外挂 14 + 机柜 26 + 地图 8 + 特效 9 + 角色 5 + 徽章 4 + UI 38 + 商店 6 ≈ **134 张**。按每张平均 3 次重roll估算生成预算。
