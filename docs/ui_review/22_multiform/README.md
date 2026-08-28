# 22 号 E2 多画幅探针

## 画幅契约

| Profile | 输出尺寸 | 内容缩放 | 双语截图数 | 结果 |
|---|---:|---:|---:|---|
| `se` | 750×1334 | 0.763× | 8 + 8 | PASS |
| `standard`（默认） | 990×2151 | 1.230× | 49 + 49 | PASS |
| `ipad` | 1024×1366 | 0.781× | 8 + 8 | PASS |

命令接口为 `visual_smoke.tscn -- --locale=zh_CN|en --profile=se|standard|ipad`。`standard` 保留完整状态；SE 与 iPad 仅保留地图、教程聚光灯、长抽屉、机房棋盘、行情+询价、科技、商店和值班日志八个发布阻断态。

原脚本把状态数写死成 47；本批改为按实际落盘计数，当前完整集合为 49 态。没有删除原有状态或放宽断言。

## 阻断级检查

- `window/stretch/aspect="keep"` 与 `canvas_items` 均未改动。
- Godot 在 keep 模式下只回传中间内容视口；探针先验证真实内容尺寸，再以项目清屏色复原完整设备画幅。
- 项目清屏色锁定为主题 `#122438`，SE/iPad 左右 pillarbox 六点取样必须匹配，黑边或世界纹理穿帮会直接失败。
- 所有可见按钮继续满足逻辑触控基线，并按各 profile 的真实缩放额外断言物理尺寸不低于 44pt。最紧档的 64u toggle 仍为 48.8px。
- HUD、页面、长抽屉、棋盘及离线弹窗均通过既有裁切、叠印、内容压缩、按钮字色和安全区断言；本轮未发现需要改变页面结构的阻断级问题。

## 审片索引

每张 contact sheet 的顺序为：地图、教程聚光灯、长抽屉、棋盘、行情+询价、科技、商店、值班日志。

- [SE 中文八态](se_zh_CN_contact.png)
- [SE 英文八态](se_en_contact.png)
- [iPad 中文八态](ipad_zh_CN_contact.png)
- [iPad 英文八态](ipad_en_contact.png)

单态原图位于 `se/{zh_CN,en}/` 与 `ipad/{zh_CN,en}/`。由于本批之前不存在 SE/iPad 捕获能力，不能诚实提供伪造的“改前设备截图”；可比的标准档基线保存在 `docs/ui_review/22_texture_before/`。本批唯一呈现修复是把清屏色从近似深蓝精确统一到主题深蓝，未改 UI 结构。
