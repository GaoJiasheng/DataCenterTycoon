# 22 号 E1 纹理导入审计

审计日期：2026-08-28  
对照基线：`b597966` 上传态留下的 iOS PCK 与本批改动前 `visual_smoke` 截图  
运行环境：Godot 4.7，macOS 桌面渲染；iOS 导出产物包含 ETC2/ASTC 平台纹理

## 分类结果

| 分类 | 目录 | 数量 | 导入设置 |
|---|---|---:|---|
| `lossless_ui` | `ui/`、`customers/` | 45 | Lossless，无 mipmap |
| `vram_scene` | `attachments/`、`buildings/`、`cats/`、`characters/`、`fx/`、`map/`、`meta/`、`personas/`、`racks/`、`store/` | 135 | VRAM compressed，mipmap |

分类与导入值由 `tools/import_assets.py` 单点声明；`tools/check_assets.py` 读取同一规则并校验 180 张正式资产的 `.png.import`，防止重新导入后静默回退。

## 400% 硬边抽查

下列文件均为左侧改前、右侧改后，采用最近邻放大 400%。

- [世界建筑透明边缘](22_texture_edges/vram_building_400pct_before_after.png)
- [机柜与室内底板边缘](22_texture_edges/vram_rack_400pct_before_after.png)
- [客户人设透明边缘](22_texture_edges/vram_persona_400pct_before_after.png)
- [HUD 图标（无损基准）](22_texture_edges/lossless_hud_icon_400pct_before_after.png)
- [九宫格金属边角（无损基准）](22_texture_edges/lossless_panel_corner_400pct_before_after.png)
- [商店图标（无损基准）](22_texture_edges/lossless_store_icon_400pct_before_after.png)

结论：三类 VRAM 样本的透明边缘、暖色描边和高反差细节没有出现肉眼可见的紫边/绿边；无损 UI 样本保持一致。五个完整状态的中英文前后图保存在：

- `docs/ui_review/22_texture_before/{zh_CN,en}/`
- `docs/ui_review/22_texture_after/{zh_CN,en}/`
- `docs/ui_review/22_texture_compare/`

## 包体、显存与性能

| 指标 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| iOS PCK | 78,479,308 B | 128,359,856 B | +49,880,548 B（+63.56%） |
| 纹理 GPU 占用估算 | 383,082,496 B | 159,675,733 B | -223,406,763 B（-58.32%） |
| 100 机房 p95 | 8.76 ms | 8.27 ms | -0.49 ms |
| 100 机房节点泄漏 | 0 | 0 | 不变 |

GPU 占用估算按改前 RGBA8、改后 VRAM 纹理 8 bpp 加完整 mip 链，保留无损 UI 为 RGBA8 计算。PCK 增长不是回归误报：PNG/无损流在磁盘上压缩率很高，而平台 VRAM 纹理为了降低真机解码与采样成本会占用更多安装包空间。本批按发布规范优先解决真机显存与缩小采样；包体变化被保留为显式发布取舍，不伪报为缩包。

## 门禁结果

- `check_assets --strict --audio`：180/180 正式美术，45 lossless + 135 VRAM，PASS。
- 双语 `visual_smoke`：中文 47/47、英文 47/47，PASS。
- `performance_smoke`：平均 6.49 ms、p90 7.71 ms、p95 8.27 ms；粒子、猫特效与节点均回收到 0，PASS。
- 直接真机 ASTC 采样属于本批明确列出的外部交付，未伪报；本地审计覆盖 iOS 导入产物生成、运行时解码后画面与 400% 硬边对照。
