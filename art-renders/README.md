# Data Center Tycoon · 视听资产工作区

本目录是美术与音频生成 session 的独立交付区，避免与并行开发中的游戏代码和正式资源目录冲突。

## 目录约定

- `visual/work/`：视觉生成源稿、候选稿和待验收版本
- `visual/final/`：146 件已通过规格与技术 QA 的视觉成品
- `visual/review/`：全量、分类与 48px 图标联系表
- `audio/work/`：音乐与音效工程中间产物
- `audio/final/`：16 个与 Godot 运行时清单对齐的音频成品
- `audio/review/`：音乐频谱联系表
- `briefs/`：生成提示、资产清单、质量报告与版本记录

正式游戏资源目录 `assets/art/` 和代码目录不由本 session 修改。经项目所有者确认后，再由负责集成的 session 将 `final/` 资产接入工程。

## 权威规格

- `docs/00_decisions.md`
- `docs/01_game_design.md`
- `docs/03_art_spec.md`
- `docs/04_tech_plan.md`

所有视觉成品符合 `docs/03_art_spec.md` 第 9 节验收标准。风格锚 `dc_t1_active` 已由项目所有者确认；全部后续素材以该图作为 imagegen 参考图独立生成。

## 当前交付状态

- 视觉：146/146；建筑 24、外挂 14、机柜 26、地图 17、特效 9、角色 5、客户徽章 4、UI 41、商店 6。
- 音频：16/16；3 首原创循环音乐、13 个原创交互/玩法音效。
- 视觉自动 QA：精确尺寸、PNG 模式、透明四角、单文件不超过 1.5MB，146/146 通过。
- 音频自动 QA：48kHz、双声道、音乐 Vorbis 循环边界、音效 24-bit PCM，16/16 通过。
- Godot 导入 dry-run：视觉 146/146、音频 16/16，零缺失。

## 关键索引

- 全量视觉总览：`visual/review/all_assets_contact.png`
- 48px 图标检查：`visual/review/ui_icons_48px_contact.png`
- 视觉清单：`briefs/visual_asset_manifest.json`
- 视觉 QA：`briefs/visual_delivery_report.md`、`briefs/visual_qa_report.json`
- 音频规格：`briefs/audio_spec.md`
- 音频 QA：`briefs/audio_qa_report.md`、`briefs/audio_qa_report.json`
- 视觉生成记录：`briefs/visual_generation_log.md`、`briefs/final_prompt_record.md`

## 可复现命令

```bash
python3 -B art-renders/briefs/build_final_visuals.py
python3 -B art-renders/briefs/make_final_review_sheets.py
python3 -B art-renders/briefs/render_audio_assets.py
python3 -B art-renders/briefs/qa_audio_assets.py
python3 -B tools/import_assets.py --visual --audio --dry-run
```
