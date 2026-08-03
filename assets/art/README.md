# 正式美术资源接口

运行时只从本目录读取正式资源。`manifest.json` 是程序与美术交付之间的稳定契约，当前完整列出 146 个资源 ID、目录、尺寸、透明通道要求和大小上限。

集成流程：

1. 美术 Session 将通过验收的成品放在 `art-renders/visual/final/`，文件名必须与 manifest 的资源 ID 一致。
2. 运行 `python3 tools/import_assets.py --visual`，脚本按文件名递归查找并复制到本目录的目标分类；`splash_bg.png` 到位后会自动启用项目启动图。
3. 运行 `python3 tools/check_assets.py --strict`；所有项目通过后再启动 Godot 导入。
4. 游戏通过 `AssetCatalog.texture(asset_id)` 获取纹理。任何资源缺失时自动使用程序化占位 UI，不会阻止工程启动。

不要在玩法代码里直接写 PNG 路径，也不要修改 `art-renders/` 中的候选稿。
