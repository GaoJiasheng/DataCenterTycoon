# 视听资源接入报告

日期：2026-08-12

## 接入结果

- 美术：159/159 已从 `art-renders/visual/final/` 接入到 `assets/art/`，含公司成长系统七件正式渲染。
- 音频：23/23 已从 `art-renders/audio/final/` 原样复制到 `assets/audio/`。
- Godot 4.7 导入与运行时加载：159 张 `Texture2D`、23 个 `AudioStream` 全部成功。
- `app_icon` 和 `splash_bg` 已启用；iOS 导出仍由发布门禁要求正式签名参数。

## 运行时接入

- 园区：草地、地块、建筑全状态、树木、灌木和电塔；俯视道路素材已交付但不在等距世界中混用。
- 机房：室内背景、九宫格机架、供电、冷却和客户徽章。
- UI：货币与导航图标、导师姿态、商店商品图、时代图标，以及路线图/园区定位/客户组合/行情复盘/董事会/典藏/传承纪念正式美术。
- 特效：施工扬尘、故障火花、市场天气/行情、金币、时代彩纸与破产烟雾。
- 音频：主界面/行情/危机音乐和全部 13 个玩法音效。

## 验收

- `python3 tools/check_assets.py --strict --audio`：通过。
- `godot --headless --path . tests/test_runner.tscn`：162 passed，0 failed。
- 双语 `visual_smoke`：各 41 个 990×2151 iPhone 17 比例状态通过实际 Metal 渲染、截图、文字边界、字体对比与 44pt 触控目标审计。
- `python3 tools/validate_data.py`：12 张数据表、本地化与 159 个美术 ID 通过。
- `python3 tools/simulate_economy.py`：三种 30 天策略 × 20 种子均存活。

## 接入时修正

- 将无缝道路的运行时契约修正为不透明，与权威美术规格和交付 manifest 一致。
- 将 Godot 4.7 不支持的 Button `icon_max_width` 属性改为主题常量。
- 修正桌面多屏坐标被误算成 iOS 安全区的问题。
- 将地图自定义绘制背景改为稳定的 `ColorRect + TextureRect` 层。
- 将竖版机房室内图改为九宫格实际背景，而非窄幅预览。
- 增加音频统一停止接口，确保自动化测试退出时无 playback 泄漏。
