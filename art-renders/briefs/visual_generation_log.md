# 视觉生成记录

## 风格锚：`dc_t1_active`

- 状态：已由项目所有者确认，并作为当前 146 件视觉素材的风格锚
- 当前候选：`../visual/work/dc_t1_active_v1.png`
- 输出规格：768×768，RGBA PNG，548,292 bytes
- 主体 alpha 边界：`(38, 143)–(729, 664)`
- 四角 alpha：全部为 0
- 128 px 缩略检查：剪影、门、圆窗、屋顶双 HVAC 均可辨认
- 生成模式：内置 `imagegen`，先生成主体，再精确编辑为绿色色键背景，随后本地移除色键并完成标准化后处理

### 最终生成提示

```text
Use case: stylized-concept
Asset type: premium production-ready mobile game building asset; style anchor for the entire game
Primary request: Create dc_t1_active, a charming single-story standard data-center building rendered as a richly finished hand-painted casual mobile-game asset. This must look like final top-tier game art, not a wireframe, not a blockout, not primitive geometric clip-art, and not a flat vector placeholder.
Scene/backdrop: perfectly flat uniform solid chroma-key background for later background removal; no scenery, horizon, floor plane, gradients, texture, reflections, or lighting variation in the background. Keep the building fully separated from the background with generous padding.
Subject: a compact single-story high-tech barn-like data center. Rounded sky-blue (#3AA7F0) painted metal wall panels with visible hand-painted material variation, cream-white (#FFF6E8) trim, a gently softened flat roof, two cute but believable rooftop HVAC boxes with detailed vents and fasteners, a row of round porthole windows revealing layered server racks and tiny green/blue indicator lights, one small entrance door beneath a tiny awning, organized cable trays and conduit along one wall, a neat concrete foundation slab. Fully powered and lively: windows glow warm sunny-yellow (#FFC93C), subtle warm light halo close to the windows, crisp readable silhouette.
Style/medium: elite casual farm-management mobile-game illustration; soft rounded forms, bright saturated hand-painted colors, smooth painterly gradients, detailed material rendering, gentle ambient occlusion, charming and friendly, tactile painted metal and glass, polished production asset quality. No hard outlines. Avoid a sterile pure-CGI look.
Composition/framing: single building centered, 3/4 top-down view at roughly 30 degrees with soft perspective rather than strict isometric; front and right side readable; no cropped roof equipment, slab, or edges.
Lighting/mood: warm cheerful sunlight from the top-left; highlights slightly warm yellow, shaded planes subtly purple-blue.
Color palette: sky blue #3AA7F0, cream white #FFF6E8, sunny yellow #FFC93C, deep navy #2B3A55 for deepest accents; tiny green and blue server LEDs only.
Materials/textures: carefully painted metal panels, slightly glossy glass, rubber HVAC details, brushed cable trays, subtle panel seams and tiny fasteners; high micro-detail without visual noise.
Constraints: no text, no letters, no numbers, no watermark, no logo; exactly one building; consistent top-left light; friendly proportions; strong silhouette at 128 px.
Avoid: pixel art, photorealistic photo, gritty realism, dystopian cyberpunk, horror, military bunker, factory smokestacks, generic rectangular box, simple geometry, flat vector art, low-poly render, harsh black outlines, strict isometric grid, background scenery, roads, people, vehicles, legible symbols, brand marks, excessive bloom, blur, noise.
```

### 迭代记录

1. 洋红色键首稿：主体美术质量通过，但软遮罩误伤蓝色墙面；拒绝。
2. 洋红硬遮罩：保住主体，但接触阴影出现洋红污染；拒绝。
3. 精确编辑为绿色色键并移除原阴影：主体保持一致，背景更适合蓝色主体。
4. 硬遮罩 + 边缘去色 + 一像素 matte 收缩：消除绿色边缘。
5. 添加符合 Style Bible 的中性深蓝柔和椭圆接触阴影，并缩放到精确 768×768 透明画布。

### 验收结论

- 透明背景：通过
- 视角约 30°、同屏可读：通过
- 左上暖光：通过
- 零文字/字母/数字/水印：通过
- 指定主色与暖窗光：通过
- 128 px 缩小可读：通过
- 尺寸与单文件大小：通过
- 全项目风格锚：通过；最终文件已写入 `visual/final/buildings/dc_t1_active.png`

## §10 批次③：园区环境层

- 生成工具：内置 `imagegen`，9 个独立生成调用。
- 新增：1 张无缝草地、2 张道路、5 个园区道具、1 张边缘雾，共 9 件；视觉总数 134→143。
- 透明处理：5 个道具用技能随附 `remove_chroma_key.py` 去色键；道路按绿色优势值生成软 alpha，只保留混凝土主体，避免与权威草地形成方形拼缝；边缘雾以亮度转换为 alpha。
- 可复现构建：`finish_final_look_world.py` + `build_final_visuals.py`；最终自动 QA 143/143。
- 人工审片：`docs/ui_review/10_batch3_world_assets_contact.png`、`docs/ui_review/10_batch3_compare_en_map.png`。

## §10 批次④：统一图标系统

- 生成工具：内置 `imagegen`，30 个独立生成调用；每次均附带 `dc_t1_active` 作为材质、光源和项目配色参考。
- 全量替换原 27 枚图标，并补齐运行时已有引用 `ic_operations`、`ic_pointer_hand` 与公共 `ic_server`，视觉总数 143→146；UI 分类 38→41。
- 所有图标统一 512×512、6px 等效深海军蓝外轮廓、左上暖光、蓝白金主色和 48px 可读体量；`ic_network` 人工确认严格 3 节点 / 3 连线。
- 洋红色键由技能脚本移除，再以 `finish_transparent_asset.py` 统一安全边距；紫色 `ic_diamond` 使用更窄的硬阈值，避免软遮罩误伤宝石主体；`ic_server` 使用扩大的 70→180 软阈值，alpha 分布审计由异常的 48.60% 全画布半透明恢复为 0.61% 正常抗锯齿边缘。
- 可复现构建与技术 QA：`build_final_visuals.py` 146/146；运行时导入 146/146、零缺失。
- 人工审片：`docs/ui_review/10_batch4_icons_48px_contact.png`、`docs/ui_review/10_batch4_icons_full_contact.png`。
