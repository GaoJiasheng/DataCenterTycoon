# 23 号弱资产刷新视觉验收

本目录按资产保存基线 `32af9cb` 与本批成品的原图、中文运行态、英文运行态。所有成品均按 `work/ → final/ → assets/art/` 导入；`check_assets --strict` 校验了 FX/地图使用 `vram_scene`，UI 九宫格使用 `lossless_ui`。

## 1. `fx_glow_ring`

- [旧原图](fx_glow_ring/before/asset.png) / [新原图](fx_glow_ring/after/asset.png)
- 中文：[旧庆祝态](fx_glow_ring/before/zh_CN_construction_complete_fx.png) / [新庆祝态](fx_glow_ring/after/zh_CN_construction_complete_fx.png)
- 英文：[旧庆祝态](fx_glow_ring/before/en_construction_complete_fx.png) / [新庆祝态](fx_glow_ring/after/en_construction_complete_fx.png)
- 淘汰记录：首轮仍是闭合霓虹圆环；次轮把棋盘格烘进 RGB。最终稿是真透明、低矮、非闭合的蓝金体积雾与暖金火花。
- 说明：当前施工完成态使用 `fx_dust_puff`，没有直接实例化 `fx_glow_ring`；运行态图证明替换未破坏庆祝流程，视觉差异以原图对照为权威证据。

## 2. `fx_confetti_set`

- [旧原图](fx_confetti_set/before/asset.png) / [新原图](fx_confetti_set/after/asset.png)
- 中文：[旧时代庆祝](fx_confetti_set/before/zh_CN_era_unlock.png) / [新时代庆祝](fx_confetti_set/after/zh_CN_era_unlock.png)
- 英文：[旧时代庆祝](fx_confetti_set/before/en_era_unlock.png) / [新时代庆祝](fx_confetti_set/after/en_era_unlock.png)
- 新稿把通用彩色圆点、糖果条和星形替换为立体金色服务器徽章、蓝色数据包、黄铜螺栓与纸屑，开放中心不遮挡奖励正文。

## 3. `plot_pad_sale`

- [旧原图](plot_pad_sale/before/asset.png) / [新原图](plot_pad_sale/after/asset.png)
- 中文：[旧地图空场](plot_pad_sale/before/zh_CN_map.png) / [新地图空场](plot_pad_sale/after/zh_CN_map.png)
- 英文：[旧地图空场](plot_pad_sale/before/en_map.png) / [新地图空场](plot_pad_sale/after/en_map.png)
- `park_map.gd` 的真实链路优先读取 `plot_pad_sale`，只在缺失时回退 `plot_forsale`；本批因此替换玩家实际看到的 `plot_pad_sale`，未改变回退语义。
- 新稿使用数据中心园区的混凝土底盘、碎石边、蓝白护栏、预埋线缆和小型安全标识，不再出现农场木栅栏语言。

## 4. `panel_main`

- [旧原图](panel_main/before/asset.png) / [新原图](panel_main/after/asset.png)
- 中文：[旧时代页](panel_main/before/zh_CN_era_unlock.png) / [新时代页](panel_main/after/zh_CN_era_unlock.png)；[旧离线页](panel_main/before/zh_CN_offline_reward.png) / [新离线页](panel_main/after/zh_CN_offline_reward.png)
- 英文：[旧时代页](panel_main/before/en_era_unlock.png) / [新时代页](panel_main/after/en_era_unlock.png)；[旧离线页](panel_main/before/en_offline_reward.png) / [新离线页](panel_main/after/en_offline_reward.png)
- PIL 中心扫描实测旧图装饰厚度：上 100 / 下 102 / 左 96 / 右 102px；新图：上 96 / 下 102 / 左 92 / 右 93px。
- `ThemeFactory.art_panel` 以 0.5 倍纹理显示，现有 52u 切片等于源图 104px，完整包住新图四边装饰和角件；内容留白 56u 继续大于可见边框，因此无需改 margin。
- 拒绝记录：一稿烘入棋盘格；二稿虽透明但把中心改成深蓝，会令现有深色正文失读。最终稿保留低眩光米白阅读面，只把玩具感青色粗框收敛为深蓝阳极氧化金属与暖金角件。

## 5. `dialog_bubble`

- [旧原图](dialog_bubble/before/asset.png) / [新原图](dialog_bubble/after/asset.png)
- 中文：[旧教程态](dialog_bubble/before/zh_CN_ftue_spotlight.png) / [新教程态](dialog_bubble/after/zh_CN_ftue_spotlight.png)
- 英文：[旧教程态](dialog_bubble/before/en_ftue_spotlight.png) / [新教程态](dialog_bubble/after/en_ftue_spotlight.png)
- 现行 `TutorialOverlay` 已使用无拉伸的双层主体和三层动态 `Polygon2D` 尾巴；PNG 只保留九宫格回退接口。新图因此只交付无尾主体，未把任何左/中/右指针烘进位图，也未改 callout 定位逻辑。
- PIL 实测旧图装饰厚度：上 57 / 下 126（含固定左尾）/ 左 54 / 右 56px；新图：上 57 / 下 56 / 左 50 / 右 49px。回退接口切片同步校准为 52/58/52/58，内容留白为 60/66/60/66。
- 教程运行态在替换前后应保持相同，这是动态 callout 不消费该回退位图的契约证明；资产本身的固定尾巴消除以原图对照为准。
