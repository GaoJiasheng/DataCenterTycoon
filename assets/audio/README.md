# 正式音频资源接口

`manifest.json` 定义所有稳定 cue ID。音频 Session 将最终文件放在 `art-renders/audio/final/`，确认后运行 `python3 tools/import_assets.py --audio` 复制到本目录。

- 音乐使用 OGG，必须可循环且首尾无爆音。
- 短音效使用 WAV；峰值不超过 -1 dBFS。
- 文件缺失时 `AudioService` 静默跳过，不影响游戏逻辑或自动测试。
- 玩法代码只调用 `AudioService.play_music(cue_id)` / `play_sfx(cue_id)`，不得引用文件路径。
