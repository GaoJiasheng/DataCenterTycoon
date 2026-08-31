# 26 · 法务合规与资产来源台账（Codex 执行文档）

> 生成于 2026-08-30。方向已由项目所有者确认，作为本批次的**唯一执行依据**。基线 `6901bd5`（build 11 已上传 TestFlight，25 号已关闭）。
> **定性：合规修复 + 证据留存，零玩法改动。** 不改任何经济数值与随机流；20 种子模拟输出与基线逐字一致（19.3 天中位、23.67×）。

## 0. 背景：四个正在出货的缺陷

审计当前 build 11 的合规面，发现的不是文书缺失，而是**实际缺陷**：

| # | 缺陷 | 证据 |
|---|---|---|
| 1 | 设置页「隐私政策 / 服务条款 / 支持」三个入口**在真机上全部失效** | `LEGAL_DOCUMENTS` 指向 `res://docs/public/*.html`，而 `export_presets.cfg` 的 `exclude_filter` 含 `docs/*`；在 129 MB pck 中 grep 这三个文件命中 **0** 次 |
| 2 | 出货代码含**编造的联系邮箱** | `ui/main_view.gd:2518` 硬编码 `support@datacentertycoon.app`；且该域名用了未定的 P01 产品名 |
| 3 | **OFL 字体许可证未随包发行** | 字体在 `assets/fonts/` 随包，但 `include_filter=""`，`.txt` 非 Godot 资源不会被导出；pck 中 grep OFL 命中 **0** 次。OFL 要求许可证副本随字体分发 |
| 4 | **无任何 Godot 引擎归属** | Godot 为 MIT，要求保留版权声明；引擎另内嵌 FreeType/zlib 等第三方组件。全库搜不到归属信息 |

缺陷 1 是发布阻断级——Apple 审核员会点隐私链接。

## 1. 关键技术判断（先读，决定 J1 怎么做）

**不要只把 html 塞进包就算修好。** iOS 上 `ProjectSettings.globalize_path("res://…")` 得到的是 `.pck` 内部路径，不是真实文件，`OS.shell_open("file://…")` 仍然打不开。因此：

- **正解：应用内渲染法务文本**（Godot 场景内可滚动阅读），不依赖文件系统、不依赖网络、不依赖尚未确定的托管 URL；
- 托管的 privacy/support URL 仍然是**所有者交付项**（ASC 必填），两者不冲突：应用内可读 + ASC 填托管链接。

## 2. 工作项

### J1 · 法务文档应用内可达（阻断级，最高优先级）

- 法务正文改为**随包资源**并在应用内渲染：新增 `ui/legal_view.gd`（全屏可滚动阅读页，走现有 `panel_main` 与排版体系），设置页三个入口改为打开该页而非 `OS.shell_open`。
- 正文来源保持单一：从 `docs/public/*.tmpl` 体系渲染出的正文，同时生成一份**随包的纯文本/资源副本**（放在 `assets/legal/` 或等价的未被 `exclude_filter` 排除的路径），由 `tools/fill_release_identity.py` 一并产出，避免出现第二份需要手工同步的正文。
- 三份文档：隐私政策、服务条款、支持说明。支持页的联系方式来自 `release_identity`，**占位期显示占位提示，不显示任何编造地址**。
- 保留 `docs/public/*.html` 作为托管用交付物（给 GitHub Pages 之类），但**运行时不再依赖它**。

**验收**：新增单测断言三个 `LEGAL_DOCUMENTS` 目标在运行时**真实可加载**（`ResourceLoader.exists` 或等价，而不是只判字符串非空）；`visual_smoke` 新增双语状态 `legal_view`（滚动到中段，验证长文排版与换行）；导出后在 pck 中 grep 得到三份正文（把这条做成 `check_release` 的硬断言，防再犯）。

### J2 · 清除硬编码联系方式

- 删除 `ui/main_view.gd:2518` 的 `support@datacentertycoon.app`，支持行改为读 `release_identity.support_email`；占位期显示本地化的「即将公布」而非任何地址。
- `docs/public/terms.html` 补齐模板化（`terms.html.tmpl` + 纳入 `fill_release_identity.py`），其中硬编码的 `Data Center Tycoon` 改为 `product_name` 占位——P01 未定，正文里不得先行认领任何产品名。
- `check_release.py` 增加扫描：`ui/`、`core/`、`gameplay/`、`data/`、`localization/` 中**不得出现邮箱字面量或非 Apple/Godot 官方域名**（白名单 example/REPLACE_WITH/godotengine.org/apple.com）。这条门禁是防止同类问题再次混入的关键。

### J3 · 应用内「第三方与许可」页

设置页新增入口，内容全部来自数据而非硬编码：

- **Godot 引擎**：用 `Engine.get_license_text()` 与 `Engine.get_copyright_info()` 输出引擎与其内嵌第三方组件（FreeType、zlib 等）的完整版权与许可（执行前先在 Godot 4.7 验证这两个 API 的返回结构）；
- **字体**：Baloo 2 与 Resource Han Rounded 的 OFL 全文，正文随包（解决缺陷 3——OFL 的分发要求由「随包 + 应用内可读」满足）；
- **音频与美术**：来自 J4 台账的归属条目。

数据源新增 `data/attributions.json`（条目：`name / kind / source / license / license_text_path / notes`），由 `tools/validate_data.py` 校验字段完整、许可证正文路径存在且随包。

**验收**：`visual_smoke` 新增双语 `attributions_view` 状态；单测断言 Godot 许可文本非空且 OFL 两份正文可加载；`check_assets --strict` 校验字体与其许可证成对存在。

### J4 · 资产来源台账（趁记忆还在，这是给未来的自己留证据）

新增 `docs/26_provenance.md`，逐项登记**全部 180 张美术、23 个音频、6 个字体**：

- 美术：生成日期、**使用的生成模型/服务名称**、prompt 记录位置（`final_prompt_record.md` 已有全文，引用即可）、是否有人工后期、**该服务条款下输出物的商用权归属结论**；
- 音频：来源（生成 / 素材库 / 自制）、授权类型与出处链接、是否需要署名；
- 字体：SIL OFL 1.1、版本、上游校验值（22 号已有 SHA-256 审计过的母版记录，引用即可）。

**红线（与 24 号 §1 同级）**：**任何一项来源不确定时，写「待确认」并列出待查线索，禁止推测或编造授权结论。** 一条编造的授权记录比空白危险得多——它会让人误以为已经查清。台账的价值在于诚实，不在于填满。

**验收**：台账覆盖 180/23/6 全部条目且与 `check_assets` 的清单逐项对齐（写个校验脚本或在 `validate_data.py` 里加一条，防止将来加资产忘记登记）；"待确认"项单独汇总成一节，供所有者按图索骥。

### J5 · 仓库许可与版权声明

- 根目录新增 `LICENSE`：**专有 / All Rights Reserved**（明确保留一切权利，说明第三方组件许可见 `data/attributions.json` 与应用内归属页）。这不是开源许可——是把权利边界写清楚。
- `README.md` 顶部加版权行；`project.godot` 的 `config/description` 视情况补版权署名。
- **不要**给每个源文件加版权头（收益低、噪音大、diff 污染）；仓库级声明足够。

### J6 · 律师咨询清单（只整理材料，不给法律意见）

新增 `docs/26_counsel_brief.md`：把项目事实整理成可以直接拿去咨询的材料——AI 生成美术、Godot MIT 引擎、SIL OFL 字体、双语、含 IAP 与可选激励广告、发行区域为中国大陆以外、iPhone-only、个人开发者主体待定。逐条列出待咨询问题：

- 商标检索与注册（P01 定名的法律基础；App Store 已存在同名应用）；
- 著作权登记是否值得办、以什么主体；
- 个人 vs 公司主体发行的责任与税务差异；
- EULA/ToS 的可执行性与管辖条款；
- **AI 生成内容的可版权性与排他性**（各法域仍在演进，直接关系到美术资产能否被保护）。

**红线**：本文件**只陈述事实与列出问题，不写任何结论性法律判断**。文件开头明确标注「本文不构成法律意见」。

## 3. 实施顺序

```
批次 1：J1 法务文档应用内可达 + J2 清除硬编码   （阻断级，一并做）
批次 2：J3 第三方与许可页
批次 3：J4 资产来源台账
批次 4：J5 仓库许可 + J6 咨询清单
批次 5：全量回归 + 文档同步 + 验收记录
```

每批次 `test_runner` 保持绿，批次间独立提交。

## 4. 明确不做

- **不写任何法律结论**（J6 只列问题）；不替所有者决定主体、名称、管辖。
- **不编造**任何联系方式、URL、产品名、授权结论（24 号 §1 红线继续适用，且本批次把它扩展成门禁）。
- 不改玩法、数值、随机流、导出目标；不发新 build（发船时机由所有者定）。
- 不给源文件逐个加版权头。

## 5. 给执行者的注意事项

1. J1 先做**最小验证**：确认导出后 pck 里确实能取到法务正文、且应用内页面能渲染，再铺开三份文档与双语排版。别重蹈「文件在仓库里就以为在包里」的覆辙——这正是缺陷 1 的成因。
2. J2 的门禁扫描要覆盖 `.gd` 与 `.json` 与 `ui.csv`；白名单写死、可解释，不要用宽松正则放水。
3. J3 的 Godot 许可 API 返回结构以 4.7 实测为准，不要照抄旧版本文档；引擎内嵌组件清单必须完整输出，不能只写一句 "Powered by Godot"。
4. J4 遇到查不清来源的资产，**停下来标「待确认」**，不要为了台账好看而推测。这条比完成度重要。
5. 全批次收尾重跑 README「开发与验收」全部命令 + 20 种子零漂移证明；验收记录格式沿用 20–25 号，并明确写出 `check_release` 的预期红灯形态（7 个占位 + IAP 插件，本批次不应改变这个清单）。

## 6. 验收记录（2026-08-31）

### 批次与提交边界

- [x] 批次 1：`89c9350 fix: render legal documents in app`（J1 + J2）。
- [x] 批次 2：`0ad616a feat: add in-app attribution notices`（J3；含设置开关原位刷新修复，避免触控中释放页面）。
- [x] 批次 3：`88f8e43 docs: add complete asset provenance ledger`（J4）。
- [x] 批次 4：`ce1edc0 docs: define proprietary rights and counsel brief`（J5 + J6）。
- [x] 批次 5：全量回归、文档同步与本验收记录为独立最终提交。

### J1 · 应用内法务可达 / J2 · 身份单一来源

- [x] `ui/legal_view.gd` 以内建全屏滚动页读取 `assets/legal/privacy.txt`、`terms.txt`、`support.txt`；设置页不再调用 `OS.shell_open(file://...)`，运行时不依赖网络、托管 URL 或 pck 内部伪文件路径。
- [x] `fill_release_identity.py` 从三份 HTML template 同步生成托管 HTML 与随包纯文本；`terms.html.tmpl` 的产品名也只读 `product_name`。占位期产品名/邮箱显示“即将公布 / Coming soon”，代码内编造邮箱已删除。
- [x] 单测逐份执行 `FileAccess.open` 并读取非空正文；`check_release` 临时导出 PCK 后逐份检索正文标记，三份均命中。源代码身份扫描覆盖 `ui/ core/ gameplay/ data/ localization/`，未发现邮箱字面量或非白名单域名。

### J3 · 第三方与许可

- [x] 在 Godot 4.7 实测 `Engine.get_license_text()` 返回完整字符串，`Engine.get_copyright_info()` 返回 102 项 `Array[Dictionary]`；应用内归属页逐项展示组件名、文件范围、版权与许可，不以一句 Powered by Godot 代替。
- [x] `data/attributions.json` 已纳入 `validate_data`；Godot、两套字体、美术与音频均有结构化来源条目。两份 OFL 全文随 PCK、可在应用内打开，`check_assets --strict` 强制四个字体文件与对应许可证成对。
- [x] 设置页四个法务入口均使用 44pt 以上释放触发按钮和全屏滚动；`settings_changed` 不再重建并释放触控中的页面，单测验证从开关起手的滑动与原地点击可以区分。

### J4 · 来源台账

- [x] `docs/26_provenance.md` 逐项登记 180 张美术、23 个音频 cue、4 个字体文件与 2 份许可证正文；每张美术均含日期证据、服务/模型、prompt、后期与商用权栏，每个音频均含来源/授权/署名栏，每个字体交付物含版本、上游记录和当前 SHA-256。
- [x] 证据未覆盖的 imagegen 底层模型/服务主体与适用条款、音频权利主体/署名、Baloo 2 上游版本/母版均明确标为“待确认”并在独立章节汇总，没有推测授权结论。
- [x] `tools/check_provenance.py` 与 `validate_data.py` 同源比对 manifest：实际输出 `PROVENANCE: exact coverage art=180, audio=23, font=6`；漏登、重复、幽灵 ID 或把不确定项静默写成事实都会使门禁失败。

### J5 · 仓库许可 / J6 · 律师材料

- [x] 根目录 `LICENSE` 声明项目特有材料为专有、All Rights Reserved，并明确第三方组件继续受各自许可证约束；未把仓库改成开源项目，也未给源文件批量加版权头。
- [x] README 顶部同步仓库级权利声明。`docs/26_counsel_brief.md` 首行标注“不构成法律意见”，只列项目、发行、AI 美术、确定性合成音频、Godot/OFL、IAP/广告等事实和 17 个待咨询问题，没有替所有者选择主体、名称、管辖或给法律结论。

### 全量回归、零漂移与预期红灯

- [x] `test_runner` 249/249，最终连续三轮全绿；欠费 HUD 夹具已改为现金低于债务的真实欠费态，消除后台合法清偿与 UI 断言竞跑且未放宽断言。`flow_audit`、`midgame_audit`、真实触摸 `tutorial_playthrough` 与二周目 `full_campaign` 全绿。长战役首局第 111 月达 20 座，二局第 11 月达 21 座并续跑至第 30 月 59 座。
- [x] `visual_smoke` 中英标准档各 51 态，新增 `legal_view` / `attributions_view` 均实际渲染；SE 与大画幅中英各 8 态继续全绿。商店截图中英各五屏按 1320×2868 原生离屏复现，`check_app_store_assets` 通过 10 张 iPhone 图。
- [x] `performance_smoke` 百机房：13 页、当前页 6 对象，average `7.82ms`、p90 `10.51ms`、p95 `10.69ms`；30 粒子、猫爱心与节点增量全部归零。
- [x] `report_release_economy.py`：T2 六档 × 20 种子、工程部 L4 与钻石三策略 × 三时代 × 20 种子三份只读报告全绿，没有改正式经济值。
- [x] `simulate_economy.py --seed-count 20 --no-write` 输出 SHA-256 为 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`，与基线逐字一致；活跃 20 座中位仍为 19.3 天，活跃/挂机 30 日净值比仍为 23.67×，第 7 天挂机收入比 45%，挂机 0 接管/0 欠费月。
- [x] `validate_data` 通过 18 张数据表；`check_assets --strict --audio` 通过 180 美术 / 6 字体交付物 / 23 音频，纹理分类仍为 45 无损 UI + 135 VRAM 场景图；`check_provenance` 精确覆盖 180/23/6。
- [ ] `check_release` **按设计仍红且只红**：`product_name`、`privacy_email`、`support_email`、`privacy_url`、`support_url`、`effective_date`、`ad_providers` 七个所有者占位值，以及缺少 StoreKit/IAP `.gdip`。PCK 法务/OFL、翻译、图标与 10 张商店截图均已通过；本批次没有伪造任何值来消灯。
- [ ] 托管隐私/支持 URL、最终身份值、IAP 插件、律师意见、真机/ASC 操作仍是外部交付。本批次不发新 build，不把桌面验证冒充线上或法律审查。
