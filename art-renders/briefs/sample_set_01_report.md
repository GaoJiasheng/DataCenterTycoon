# 样稿批次 01 · 十图质量报告

## 结果

本批次使用内置 `imagegen`，以 `visual/work/dc_t1_active_v1.png` 为风格参考图，逐项独立生成。生成源稿先使用绿色或洋红色键背景，再在本地完成背景移除、边缘收缩、局部中值去色溢、精确尺寸缩放和统一接触阴影。

最终评审目录：`../visual/work/sample_set_01_v3/`

| 文件 | 规格 | 生成结果 |
|---|---:|---|
| `dc_t0_active.png` | 768×768 | 通过 |
| `dc_t2_active.png` | 1024×1024 | 通过；电缆桥完整、屋顶 HVAC 为 4 台 |
| `power_t1_active_v2.png` | 512×512 | 通过；二次改用洋红色键消除黄色辉光周围的绿色污染 |
| `cool_air_t1_active.png` | 512×512 | 通过 |
| `rack_compute_t1_active.png` | 512×512 | 通过 |
| `rack_storage_t1_active.png` | 512×512 | 通过 |
| `rack_gpu_t1_active.png` | 512×512 | 通过 |
| `deco_tree.png` | 384×384 | 通过 |
| `guide_normal.png` | 768×1024 | 通过；手部、五官、平板均完整 |
| `client_cloud.png` | 384×384 | 通过；48px 识别结构清晰 |

全部文件均为 RGBA PNG，四角 alpha 为 0，单文件小于 1.5MB。

## 公共生成提示

```text
Use case: stylized-concept
Asset type: premium production-ready mobile game asset
Input images: Image 1 is the project style reference only; generate a new subject while matching its rendering language, palette treatment, soft perspective, and top-left light.
Style/medium: elite casual farm-management game illustration: soft rounded shapes, bright saturated hand-painted color, rich tactile detail, smooth painterly gradients, gentle ambient occlusion, crisp silhouette, no hard outlines. Final top-tier production art, never a wireframe, blockout, primitive geometry, flat vector placeholder, or low-poly render.
Composition/framing: exactly one isolated asset, centered, generous padding, no crop; use 3/4 top-down at roughly 30 degrees when the asset is spatial.
Lighting/mood: warm cheerful sunlight from top-left, warm highlights and subtly purple-blue shaded planes.
Scene/backdrop: perfectly flat uniform chroma-key background for removal; no scenery, floor plane, gradient, texture, reflection, cast shadow, contact shadow, or lighting variation; do not use the key color on the subject.
Constraints: no text, letters, numbers, watermark, signature, logo, or unrelated objects.
Avoid: pixel art, photorealistic photo, pure sterile CGI, gritty realism, horror, dystopian cyberpunk, harsh outlines, strict isometric grid, simple geometry, blur, noise.
```

## 各资产主体提示

- `dc_t0_active`：小型蓝色圆角集装箱机房，保留波纹板、通风格栅、短天线、接地线槽和暖光服务门；体量与复杂度明显低于风格锚。
- `dc_t2_active`：蓝白两层大型机房，玻璃中庭、完整短电缆桥与支撑、卫星天线、两丛绿篱、4 台屋顶 HVAC、暖光服务器窗；完整主体必须处于画布内。
- `power_t1_active`：橙色一级变压器柜、陶瓷绝缘子、粗电缆和混凝土底座；黄色通电辉光与少量火花点。
- `cool_air_t1_active`：白色与冰青色单风扇冷却单元，细致护网、旋转扇叶、侧面管件、橡胶脚和少量冰青气流。
- `rack_compute_t1_active`：蓝色计算机柜，密集横向服务器刀片、把手、侧通风口和青蓝指示灯。
- `rack_storage_t1_active`：绿色存储机柜，整齐磁盘仓、琥珀指示灯和一只半拉开的磁盘抽屉。
- `rack_gpu_t1_active`：紫色 GPU 机柜，三层可见 GPU 模组、散热风扇、热鳍片与受控紫光。
- `deco_tree`：短棕色树干、丰富的两层绿色手绘叶簇以及恰好 3 枚红果，拒绝简单球形树冠。
- `guide_normal`：中年工程师“老高”半身像，黄色安全帽、蓝色工作马甲、无字平板与张开手掌的欢迎动作；手部和五官必须完整。
- `client_cloud`：奶油色圆形徽章、蓝色内场、白色圆润云朵及由 3 个圆角段组成的抽象上行箭头；不得影射真实品牌。

## 返修记录

1. `dc_t2_active` 初稿电缆桥被裁切，拒绝。
2. 第二稿构图完整但只有 3 台 HVAC，拒绝。
3. 最终稿对屋顶进行精确编辑，改为 4 台 HVAC，其他结构保持不变。
4. `power_t1_active` 初稿黄色辉光与绿色色键混色，透明化后出现绿色边缘，拒绝。
5. 将供电单元背景精确改为洋红色键后重新抠图，绿色污染消失，保存为 `power_t1_active_v2.png`。
