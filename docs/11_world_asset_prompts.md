# 11 · 世界重构六件素材生成记录

生成日期：2026-08-03  
生成方式：Codex 内置 `imagegen`，六件素材分别独立调用；统一使用纯色 `#ff00ff` 键色背景，再以官方 `remove_chroma_key.py` 做 soft matte、despill 与 1px edge contract，最后规格化到目标 RGBA 画布。运行时交付目录为 `assets/art/map/`，可追溯源交付保存在 `art-renders/visual/final/map/`。

## 1. `plot_pad_std`

源生成图：`/Users/gavin/.codex/generated_images/019fc671-ef29-7782-89a6-adbb5a9a55a5/exec-83f6af11-d28b-4371-a3a2-726e5b042159.png`

```text
Use case: stylized-concept
Asset type: standalone transparent game-world map plot-pad sprite
Input images: Image 1 is a style and isometric-perspective reference for the existing pad; Images 2 and 3 are style, camera, material, and lighting references from the same game. They are NOT edit targets. Generate a brand-new independent asset; do not reproduce or include any building.
Primary request: plot_pad_std, a standard isometric 3/4 top-down concrete plot pad for a polished cartoon tech-campus management game.
Scene/backdrop: perfectly flat, completely uniform solid #ff00ff chroma-key background for removal. No background shadow, gradient, texture, floor, reflection, or lighting variation.
Subject: one centered square tech-campus construction pad viewed at the same approximately 30-degree camera as the reference buildings. Light warm-gray poured concrete surface, restrained beveled rim, rounded corners, subtle expansion joints dividing the usable surface into four large panels, and exactly four short compact corner posts. The pad should read as a clean universal foundation for the small T0/T1 buildings.
Style/medium: premium stylized 3D mobile-game sprite, matching the reference set's clean rounded geometry, warm cream highlights, restrained hand-painted material texture, crisp silhouette and polished production quality.
Composition/framing: centered, generous even padding, entire pad visible, symmetric diamond footprint, no cropping, consistent isometric axes. The usable upper surface should dominate the sprite, with posts kept short so buildings can sit on it.
Lighting/mood: soft light from upper-left; subtle self-contained ambient occlusion and lower-right edge shading on the pad only; no cast shadow on the chroma background.
Color palette: warm light gray concrete, soft beige highlights, subtle cool-gray seams; do not use #ff00ff or any magenta/pink in the subject.
Constraints: no building, no flags, no signs, no fencing, no road, no grass, no soil, no rubble, no props, no text, no logos, no watermark. Exactly one pad. Crisp separated edges suitable for chroma-key extraction.
```

## 2. `plot_pad_large`

源生成图：`/Users/gavin/.codex/generated_images/019fc671-ef29-7782-89a6-adbb5a9a55a5/exec-288bc889-a4c2-492c-a906-c9c074e97194.png`

```text
Use case: stylized-concept
Asset type: standalone transparent game-world map plot-pad sprite
Input images: Image 1 is a style and isometric-perspective reference for the existing pad; Images 2 and 3 are style, camera, scale-family, material, and lighting references from the same game. They are NOT edit targets. Generate a brand-new independent asset; do not reproduce or include any building.
Primary request: plot_pad_large, the larger-capacity member of the same isometric tech-campus plot-pad family, purpose-built to carry wide T2/T3 data-center buildings. It must be visibly broader and more substantial than the standard pad, with more usable floor area and detail density—not a simple scaled copy.
Scene/backdrop: perfectly flat, completely uniform solid #ff00ff chroma-key background for removal. No background shadow, gradient, texture, floor, reflection, or lighting variation.
Subject: one centered large rectangular-to-square isometric 3/4 top-down concrete tech-campus foundation at the same approximately 30-degree camera as the reference buildings. Broad light warm-gray poured-concrete deck, restrained wider beveled perimeter rim, rounded corners, subtle expansion joints dividing the much larger usable surface into a clean 3-by-3 construction-panel rhythm, and exactly four short compact corner posts. Add only subtle edge fasteners and seams to communicate heavier load capacity; keep the center open for a building.
Style/medium: premium stylized 3D mobile-game sprite, matching the reference set's clean rounded geometry, warm cream highlights, restrained hand-painted concrete texture, crisp silhouette, and polished production quality.
Composition/framing: centered, generous even padding, entire pad visible, stable symmetric isometric diamond footprint, no cropping, same isometric axes as the standard family. Larger physical platform proportions and denser joint grid should clearly distinguish it from plot_pad_std; posts remain short.
Lighting/mood: soft light from upper-left; subtle self-contained ambient occlusion and lower-right edge shading on the pad only; no cast shadow on the chroma background.
Color palette: warm light gray concrete, soft beige highlights, subtle cool-gray seams; do not use #ff00ff or any magenta/pink in the subject.
Constraints: no building, no flags, no signs, no fencing, no road, no grass, no soil, no rubble, no props, no text, no logos, no watermark. Exactly one large pad. Crisp separated edges suitable for chroma-key extraction.
```

## 3. `plot_pad_sale`

源生成图：`/Users/gavin/.codex/generated_images/019fc672-787b-7251-b7ce-cc0b58389fdc/exec-f40d69ad-8fcd-4602-b8c1-2626ac724304.png`

```text
Use case: stylized-concept
Asset type: production-ready isometric mobile game map sprite for Data Center Tycoon, plot_pad_sale
Primary request: Create one shallow warm-gray isometric concrete empty plot pad in exactly the same polished friendly 3D mobile-game family as the reference plot and building assets. Add exactly two short blue-and-white striped modern technology-park safety barrier segments and one upright sale sign. The sale sign must use a clear gold coin plus price-tag pictogram only, with no letters, numbers, pseudo-text, or unreadable glyphs.
Input images: plot_owned.png is the primary shape, concrete material, 2:1 isometric perspective, edge treatment, and framing reference; plot_forsale.png is only a reference for the semantic idea of a sale plot but its agricultural dirt, wooden fence, and wooden sign must not be copied; ground_tile_grass.png supplies the campus grass color family; ground_path_cross.png supplies the light warm-gray campus pavement palette; dc_t1_active.png supplies the blue, cream, gold, stylized 3D rendering language.
Scene/backdrop: a perfectly flat, fully uniform solid #ff00ff chroma-key background for background removal, with no floor plane and no background lighting variation.
Subject: a compact square concrete development pad viewed in 2:1 isometric projection. The concrete is pale warm gray with subtle clean slab seams and a low rounded curb. Two modest blue-and-white striped technology-park barrier segments sit along two rear/side edges without enclosing the plot. One freestanding modern metal sale sign faces the viewer, displaying only a crisp embossed gold coin and price-tag icon.
Style/medium: high-end casual mobile tycoon game sprite, polished stylized 3D render, soft bevels, clean readable silhouette, materials and detail density matching the references.
Composition/framing: centered single isolated object, entire plot and all accessories visible, generous 8–10% padding, square canvas, 2:1 isometric axes, no cropping. Object footprint and camera angle should closely match plot_owned.png.
Lighting/mood: soft warm key light from upper left; subtle soft attached/contact shadow falling toward lower right, confined to the object footprint and never changing the chroma-key background.
Color palette: warm gray concrete, cream curb, saturated but tasteful tech blue and white stripes, restrained gold sale icon. The subject must contain no magenta or near-magenta hues.
Materials/textures: lightly textured concrete slabs, painted metal barriers, brushed metal signpost, enamel gold pictogram; crisp anti-aliased contours.
Text: none.
Constraints: exactly one concrete plot, exactly two blue-white barrier segments, exactly one sale sign with only a gold coin/price-tag pictogram; perfectly uniform #ff00ff outside the isolated subject; all background pixels one color; keep the subject opaque and fully separated from the background.
Avoid: farmland, soil, furrows, crops, rustic themes, wood fences, wood posts, wood signs, red flags, construction cones, people, vehicles, buildings, additional props, letters, digits, words, logos, watermarks, pseudo-text, magenta in the subject, gradients or texture in the chroma-key background, cast shadow extending into the chroma-key field, screen-horizontal or screen-vertical perspective.
```

## 4. `road_iso_a`

源生成图：`/Users/gavin/.codex/generated_images/019fc673-1718-7950-b5d6-2f60697ab888/exec-82b788cf-001c-4820-90eb-a2504e08d5b4.png`

```text
Use case: stylized-concept
Asset type: production-ready isometric mobile game environment road sprite, independent single asset
Input images: Images 1–4 are style, palette, material, camera-angle, and isometric-perspective references only; generate a new asset, do not edit or copy any reference.
Primary request: Create road_iso_a, a single shallow warm light-gray concrete technology-campus driveway that follows the first axis of a strict 2:1 isometric grid. On screen it enters from the lower-left edge direction and rises diagonally toward the upper-right edge direction (↗), at the shallow 2:1 isometric angle, never horizontal and never vertical.
Subject: one clean continuous straight driveway segment only; gently rounded concrete curbs; sparse subtle joints and restrained surface grain; a narrow soft green grass-color transition hugging both long sides; both end caps naturally feather and fade into grass so repeated world-grid placement feels integrated.
Style/medium: polished stylized 3D mobile tycoon game sprite; same friendly premium rendering family as the references; warm ivory-gray concrete, refined rounded bevels, low visual noise, strong readable silhouette at phone scale.
Composition/framing: one centered elongated road strip, aligned exactly lower-left to upper-right on the canvas, consistent strict 2:1 isometric projection under the same 30-degree camera as the reference plot and building; generous clear padding; no cropped curb.
Lighting/mood: soft upper-left key light; subtle lower-right baked edge/contact shading contained entirely inside the sprite silhouette; bright welcoming technology campus.
Scene/backdrop: perfectly flat, completely uniform solid #ff00ff chroma-key background for local removal.
Color palette: warm pale concrete, muted stone-gray seams, restrained fresh grass greens; absolutely no magenta in the subject.
Materials/textures: clean concrete with extremely subtle wear, rounded curb stone, only a thin grass fringe; no asphalt.
Constraints: exactly one straight road on the A isometric axis; preserve precise 2:1 isometric geometry; all four canvas corners and all outside area must remain pure #ff00ff; crisp antialiased silhouette; generous padding; no background shadow, gradient, texture, reflection, floor plane, or lighting variation; no text, watermark, logo, vehicle, character, sign, building, prop, intersection, junction, zebra crossing, lane marking, screen-horizontal road, or screen-vertical road.
Avoid: orthographic top-down view; 45-degree diagonal; crossroad; T-junction; multiple tiles; rectangular horizontal pavement; busy grass clumps; photorealism; blue cast; neon; magenta fringe.
```

## 5. `road_iso_b`

源生成图：`/Users/gavin/.codex/generated_images/019fc673-1718-7950-b5d6-2f60697ab888/exec-a31586f3-7e55-4550-9f67-d2b50466a79a.png`

```text
Use case: stylized-concept
Asset type: production-ready isometric mobile game environment road sprite, independent single asset
Input images: Images 1–4 are style, palette, material, camera-angle, and isometric-perspective references only; Image 5 is the newly generated sibling asset road_iso_a and must be matched as the exact same road kit family. Generate a new complementary asset, do not edit or combine the inputs.
Primary request: Create road_iso_b, the complementary straight segment to road_iso_a. It is the same shallow warm light-gray concrete technology-campus driveway but follows the second axis of a strict 2:1 isometric grid. On screen it enters from the upper-left edge direction and descends diagonally toward the lower-right edge direction (↘), at the shallow 2:1 isometric angle, never horizontal and never vertical.
Subject: one clean continuous straight driveway segment only; same width, curb profile, joint cadence, surface grain, grass fringe thickness, and end treatment as road_iso_a; gently rounded concrete curbs; narrow soft green grass-color transition hugging both long sides; both end caps naturally feather and fade into grass.
Style/medium: polished stylized 3D mobile tycoon game sprite; exact same friendly premium rendering family as road_iso_a and the references; warm ivory-gray concrete, refined rounded bevels, low visual noise, strong readable silhouette at phone scale.
Composition/framing: one centered elongated road strip, aligned exactly upper-left to lower-right on the canvas, strict mirrored complementary 2:1 isometric axis under the same 30-degree camera as road_iso_a, the reference plot, and the building; generous clear padding; no cropped curb.
Lighting/mood: same soft upper-left key light as road_iso_a; subtle lower-right baked edge/contact shading contained entirely inside the sprite silhouette; bright welcoming technology campus.
Scene/backdrop: perfectly flat, completely uniform solid #ff00ff chroma-key background for local removal.
Color palette: warm pale concrete, muted stone-gray seams, restrained fresh grass greens; absolutely no magenta in the subject.
Materials/textures: clean concrete with extremely subtle wear, rounded curb stone, only a thin grass fringe; no asphalt.
Constraints: exactly one straight road on the B isometric axis; preserve precise 2:1 isometric geometry; match road_iso_a scale and styling; all four canvas corners and all outside area must remain pure #ff00ff; crisp antialiased silhouette; generous padding; no background shadow, gradient, texture, reflection, floor plane, or lighting variation; no text, watermark, logo, vehicle, character, sign, building, prop, intersection, junction, zebra crossing, lane marking, screen-horizontal road, or screen-vertical road.
Avoid: orthographic top-down view; 45-degree diagonal; crossroad; T-junction; multiple tiles; rectangular horizontal pavement; busy grass clumps; photorealism; blue cast; neon; magenta fringe.
```

## 6. `road_iso_cross`

源生成图：`/Users/gavin/.codex/generated_images/019fc672-787b-7251-b7ce-cc0b58389fdc/exec-5f3daca6-0f83-41de-89c9-0b3d1ee98391.png`

```text
Use case: stylized-concept
Asset type: production-ready isometric mobile game map tile sprite for Data Center Tycoon, road_iso_cross
Primary request: Create one seamless-looking four-way technology-campus road intersection that runs ONLY along the two 2:1 isometric map axes (upper-left to lower-right and upper-right to lower-left), forming a centered isometric X/diamond-axis crossing. It must never read as a screen-vertical plus screen-horizontal road.
Input images: ground_tile_grass.png is the exact grass hue, texture density, and painted mobile-game style reference; ground_path_cross.png is only the warm-gray pavement and rounded curb material reference but its orthographic screen-horizontal/screen-vertical plus layout must not be copied; plot_owned.png establishes the 2:1 isometric axes, warm concrete, beveled curb, and light/shadow direction; dc_t1_active.png establishes the polished friendly 3D tech-campus rendering language; plot_forsale.png is a secondary style-scale reference only.
Scene/backdrop: a perfectly flat, fully uniform solid #ff00ff chroma-key background outside the isolated tile footprint, with no floor plane and no background lighting variation.
Subject: a centered four-way crossing of pale warm-gray technology-park vehicle lanes. Four arms extend diagonally toward the four corners following a precise 2:1 isometric diamond grid: vectors approximately (2,-1), (2,1), (-2,-1), (-2,1). The intersection center is a shallow isometric diamond. Add smooth low rounded cream-gray curbs. Include only narrow, sparse transition wedges of campus grass along both sides of the lanes, using the same yellow-green family and texture density as ground_tile_grass.png.
Style/medium: high-end casual mobile tycoon map sprite, polished stylized 3D render, soft bevels, clean readable silhouette and surface detail matching the reference assets.
Composition/framing: centered single isolated crossing, square canvas, symmetric four-arm X composition, each road arm reaches near its corresponding corner but stays within generous 6–8% padding. Camera is a true 2:1 isometric projection consistent with plot_owned.png. Entire tile visible, no cropping.
Lighting/mood: soft warm key light from upper left, restrained soft dimensional shading toward lower right, no detached cast shadow in the chroma-key field.
Color palette: pale warm-gray concrete, cream-gray curb, reference yellow-green grass. The subject must contain no magenta or near-magenta hues.
Materials/textures: clean lightly textured paved campus lanes, subtle believable slab joints aligned with the isometric axes, smooth rounded curbs, sparse finely painted grass edge; no asphalt blacktop.
Text: none.
Constraints: exactly one four-way isometric crossing; roads only on the two diagonal 2:1 axes; intersection must look like an isometric X, never a screen-aligned +; uniform #ff00ff outside the isolated tile; all background pixels one color; opaque subject fully separated from background.
Avoid: screen-horizontal roads, screen-vertical roads, orthographic plus-sign road, 90-degree top-down grid, zebra crossings, crosswalks, lane arrows, center lines, traffic markings, text, letters, numbers, signs, vehicles, people, buildings, lamps, trees, rocks, excess grass, farm styling, logos, watermarks, pseudo-text, magenta in the subject, gradients or texture in the chroma-key background.
```

## QA 摘要

| 素材 | 尺寸 | 模式 | 四角 Alpha | 可见洋红残余 |
|---|---:|---|---:|---:|
| `plot_pad_std` | 768×768 | RGBA | 0 | 0 px |
| `plot_pad_large` | 1024×1024 | RGBA | 0 | 0 px |
| `plot_pad_sale` | 768×768 | RGBA | 0 | 0 px |
| `road_iso_a` | 1024×1024 | RGBA | 0 | 0 px |
| `road_iso_b` | 1024×1024 | RGBA | 0 | 0 px |
| `road_iso_cross` | 1024×1024 | RGBA | 0 | 0 px |

道路主轴复核：`road_iso_a=-31.19°`、`road_iso_b=+30.74°`；最终 `python3 tools/check_assets.py --strict` 验证 152/152 资产全部通过。
