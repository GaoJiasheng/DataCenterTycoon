# 23 · 弱资产重做与 build 10 发船（Codex 执行文档）

> 生成于 2026-08-28。方向已由项目所有者确认，作为本批次的**唯一执行依据**。
> 前置阅读：[22_release_hardening.md](22_release_hardening.md) 与 [22_content_audit.md](22_content_audit.md) §2（五张弱资产的问题描述与重生成 prompt 已备好，本文不重复）。基线：`32af9cb`（22 号验收修复已入）。
> **定性：美术替换 + 运维发船，零玩法改动。** 不改任何数值字段、不动随机流；20 种子模拟输出与基线逐字一致（19.3 天中位、23.67×）。

## 1. 工作项

### F1 · 先推送，补上 CI 远端证据

1. `git push origin main`（当前 10 个本地 commit）。
2. 等 GitHub Actions 完整跑一次（含 22 号新增的 tutorial_playthrough / main 分支 campaign / performance --ci / 六档视觉矩阵）。
3. 把 run 链接填进 22 号验收记录那格未勾选的「远端 CI 证据」，勾掉它，单独提交。CI 若红，先修再继续——**红着不许进 F2**。

### F2 · 五张弱资产重做（prompt 以 22_content_audit §2 为准）

按顺序做，一张一验，全部走 `art-renders work/ → final/ → assets/art/` 管线 + `import_assets.py`，英文 prompt 全文入 `final_prompt_record.md`，E1 的导入分类由 `check_assets` 自动约束（fx_*/plot_* 归 vram_scene，panel/dialog 归 lossless_ui）。

| 序 | 资产 | 额外纪律（prompt 之外必须遵守的） |
|---|---|---|
| 1 | `fx_glow_ring` | 13 号 FX 自毁与 ≤100u 预算不变；替换后跑 `performance_smoke` 确认粒子/节点仍零残留 |
| 2 | `fx_confetti_set` | 同上；时代号外双喷彩屑的锚点与尺寸参数不动，只换贴图 |
| 3 | `plot_forsale` | **先确认地图实际渲染的是哪个资产**——`park_map.gd` 存在 `plot_pad_sale` 优先、`plot_forsale` 回退的链路，重做玩家真正看到的那张；两张都在则保持链路语义不变 |
| 4 | `panel_main` | 九宫格是 08/09 号的重灾区：新图必须**逐边实测边框厚度**（PIL 量法沿用 08 号），与 `ThemeMaker` 现有 texture_margin/content_margin 对齐；对不齐就改 margin 并全量视觉回归，绝不允许文字压框回归 |
| 5 | `dialog_bubble` | 教程气泡已是「动态尾巴」系统（`a90067e` 重构）：先读现行 callout 代码消费哪些切片，按现行运行时契约交付无尾主体 + 分离尾巴件；不改 callout 逻辑 |

**每张的验收**：涉及该资产的双语视觉状态前后对照入 `docs/ui_review/23_asset_refresh/`（fx 两张对 era_unlock/庆祝态、plot 对地图空场态、panel 对任一系统页、bubble 对教程聚光灯态）；`check_assets --strict` 全绿；替换不引入任何 .gd/.json 玩法改动。

**全部完成后**：双语 standard 49 态 + SE/iPad 各 8 态全绿；`test_runner` / `flow_audit` / `midgame_audit` / `tutorial_playthrough` / `full_campaign` / `performance_smoke` 全绿；模拟器零漂移。

### F3 · build 10 发 TestFlight

1. F2 全绿并提交后，`git push origin main`，确认 CI 绿。
2. 用 22 号的正式管线发船：`tools/release_ios.sh --bump --upload`（bump 后 build 号应为 10；export_presets 改动纳入提交）。
3. 上传成功记录（`UPLOAD SUCCEEDED` 日志摘录 + xcarchive 归档到 `builds/archives/`）写进本文验收记录；`release_checklist.md` 同步。
4. 若 ASC 报重复 build 号，按脚本提示再 `--bump`，如实记录原因。

## 2. 明确不做

- 只重做点名的五张；不顺手重做其他资产、不调整任何布局/配色/文案。
- 不动 FX 参数、九宫格 margin 语义之外的任何 UI 代码；dialog_bubble 不改 callout 逻辑。
- 商店截图、隐私链接、Instruments、StoreKit sandbox 仍属外部交付，不在本批。

## 3. 给执行者的注意事项

1. 美术生成不达标就重roll，不许降级合入——这五张全是「观感短板」名单，换上去必须明显更协调，拿不准就在前后对照里并排给出并停下等所有者裁决。
2. `panel_main` 影响几乎每个系统页，是本批唯一的高爆改动：margin 实测数据（每边像素厚度）写进验收记录，全量 49 态跑两个 locale，重点看长文案页（设置、典藏、商店）。
3. 发船前后各跑一次 `git status` 确认工作区全净；上传用的 IPA 备份到桌面，命名沿用 `DataCenterTycoon-1.0.0-build10.ipa`。
4. 本文验收记录格式沿用 20/21/22 号，逐项附证据。

## 4. 验收记录（2026-08-28）

### F1 · 远端 CI 证据

- [x] 基线后的 10 个本地提交已推送到 `origin/main`。
- [x] 22 号新增门禁在 GitHub Actions 完整跑通：[CI run 33180099937](https://github.com/GaoJiasheng/DataCenterTycoon/actions/runs/33180099937)。该 run 覆盖 243 项逻辑、flow/midgame/tutorial/full campaign、performance `--ci`、standard/SE/iPad 中英视觉矩阵。
- [x] 远端运行中暴露的跨 runner 设置拖动、显式预览尺寸、询价 fixture 漂移和棋盘换页竞态均先修至绿色；22 号验收记录的远端证据格已单独提交（`d68b0da`）。

### F2 · 五张弱资产

- [x] 五张资产严格按 `fx_glow_ring → fx_confetti_set → plot → panel_main → dialog_bubble` 顺序逐张生成、验图、导入；完整 prompt 与 ImageGen 源路径见 [最终 prompt 记录](../art-renders/briefs/final_prompt_record.md)。
- [x] 地图实际消费链路经 `park_map.gd` 核实后替换 `plot_pad_sale`，保留 `plot_forsale` 缺失回退，未改链路语义。
- [x] `panel_main` PIL 中心扫描：旧上/下/左/右为 `100/102/96/102px`，新图为 `96/102/92/93px`。现有 0.5 倍纹理 + 52u 切片折算为源图 104px，四边与角件均完整落入切片；56u 内容留白继续清出边框，因此 margin 无需改变。中英离线页、时代页未出现文字压框。
- [x] `dialog_bubble` 运行时契约核实为：教程主体使用双层扁平组件，三层动态 `Polygon2D` 尾巴按目标中心放置；PNG 是未被现行教程消费的九宫格回退。新图仅含无尾主体，旧固定左尾已去除；新上/下/左/右边框实测 `57/56/50/49px`，回退接口切片校准为 `52/58/52/58`、内容留白为 `60/66/60/66`，未改 callout 逻辑。
- [x] 原图及中英运行态前后证据集中在 [23_asset_refresh](ui_review/23_asset_refresh/README.md)；生成中淘汰了闭合圆环、假棋盘透明和深底失读稿，未把不达标结果降级合入。
- [x] `python3 tools/check_assets.py --strict --audio`：180/180 美术、23/23 音频通过；FX/地图为 `vram_scene`，UI 九宫格为 `lossless_ui`。
- [x] `test_runner` 243/243、`flow_audit`、`midgame_audit`、`tutorial_playthrough`、`full_campaign` 全绿；整局仍在同一局断言询价、成组、扩编与稀有锁价封顶。
- [x] `python3 tools/simulate_economy.py` 输出 SHA-256 为 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`，与 22 号基线逐字一致；20 座中位 19.3 天、活跃/挂机净值比 23.67×，正式经济零漂移。
- [x] `python3 tools/report_release_economy.py` 完整复跑：T2 六档 × 20 种子、工程部 L4、钻石三策略 × 三时代 × 20 种子均通过；三份 CSV 与基线字节一致，未产生数值报告漂移。
- [x] standard 中英 49 态、SE 中英各 8 态、iPad 中英各 8 态全部通过；外部高负载退出后重新取样，未把受干扰的截帧当作证据。
- [x] `performance_smoke` 在无外部探针竞争时重跑通过：平均 `6.95ms`、p90 `11.02ms`、p95 `15.46ms`；峰值 30 粒子归零、猫特效 `1→0`、节点增量 0。
- [x] F2 已提交为 `e1111d4` 并推送到 `origin/main`；远端完整门禁 [Project gates #33190809456](https://github.com/GaoJiasheng/DataCenterTycoon/actions/runs/33190809456) 全绿后才进入 F3。

### 已知外部发布交付（不在本批范围）

- `check_app_store_assets.py` 仍报告缺失 iPhone/iPad 中英商店截图；`check_release.py` 另报告隐私/支持 URL、P04 与 StoreKit 插件占位。这些项目在本文 §2 明确属于外部交付，本批没有伪造或越权补齐。

### F3 · build 10

- [x] F2 已推送且远端 CI 全绿，满足执行 `tools/release_ios.sh --bump --upload` 的前置硬闸。
- [ ] build 10 正式归档、上传与 IPA 桌面备份待执行。
