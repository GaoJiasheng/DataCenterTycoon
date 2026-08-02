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
- UI：面板和按钮为可触摸的手绘 9-slice 元件，中心无字；27 枚图标逐枚生成，单主体、粗圆轮廓、48px 可读，不使用代码绘制的线框图形。
- 商店：应用图标与启动图为不透明全幅插画；三档礼包按木箱、宝箱、金色金库逐级强化价值感；去广告徽章使用蓝色轻盈曲带而非负面红斜杠。

## 最终返修决策

- `dc_t2_active`：采用完整电缆桥与 4 台屋顶 HVAC 的修订版。
- `power_t1_active`：采用洋红色键修订版，避免黄色电光边缘被绿色污染。
- `cool_liquid_t2_active/idle`：采用严格 3 个主冷却缸的 v2 修订版。
- `ic_network`：采用 v3，严格 3 个节点与 3 条连线，无多余中心节点。

## 后处理

色键背景先由 imagegen 技能随附的 `remove_chroma_key.py` 移除，再由 `finish_transparent_asset.py` 做一像素 matte 收缩、局部中值去色溢、精确画布缩放和按类别控制的接触阴影。最终构建与尺寸/透明/体积 QA 由 `build_final_visuals.py` 复现。
