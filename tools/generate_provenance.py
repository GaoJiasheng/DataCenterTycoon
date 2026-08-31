#!/usr/bin/env python3
"""Generate the evidence-first asset provenance ledger.

This script deliberately preserves unknowns as ``待确认``.  It only promotes a
date or source statement to confirmed when a repository record says so.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/26_provenance.md"
PROMPT_RECORD = "../art-renders/briefs/final_prompt_record.md"
AUDIO_SPEC = "../art-renders/briefs/audio_spec.md"
AUDIO_RENDERER = "../art-renders/briefs/render_audio_assets.py"

CONFIRMED_ART_DATES = {
    "app_icon": "2026-08-14",
    "fx_dust_puff": "2026-08-12",
    "fx_glow_ring": "2026-08-28",
    "fx_confetti_set": "2026-08-28",
    "plot_pad_sale": "2026-08-28",
    "panel_main": "2026-08-28",
    "dialog_bubble": "2026-08-28",
    "company_roadmap": "2026-08-12",
    "campus_strategy": "2026-08-12",
    "customer_portfolio": "2026-08-12",
    "market_review": "2026-08-12",
    "board_specialties": "2026-08-12",
    "company_collection": "2026-08-12",
    "legacy_memorial": "2026-08-12",
    "persona_internet_lin_ce": "2026-08-15",
    "persona_internet_tang_man": "2026-08-15",
    "persona_internet_chen_lu": "2026-08-15",
    "persona_cloud_su_qing": "2026-08-15",
    "persona_cloud_zhou_yunzhou": "2026-08-15",
    "persona_cloud_xu_an": "2026-08-15",
    "persona_gpu_gu_xing": "2026-08-15",
    "persona_gpu_ye_zhixing": "2026-08-15",
    "persona_mining_zhou_lan": "2026-08-15",
    "persona_mining_lu_sen": "2026-08-15",
    "cat_sleep": "2026-08-15",
    "cat_walk_a": "2026-08-15",
    "cat_walk_b": "2026-08-15",
    "cat_sit": "2026-08-15",
    "cat_roll": "2026-08-15",
    "cat_sunglasses": "2026-08-15",
    "collection_cat_nap": "2026-08-15",
    "collection_cat_parade": "2026-08-15",
    "collection_cat_watch": "2026-08-15",
    "collection_cat_festival": "2026-08-15",
    "fx_cat_heart": "2026-08-15",
}

FONT_RECORDS = (
    {
        "id": "Baloo2-Variable.ttf",
        "path": "assets/fonts/Baloo2-Variable.ttf",
        "version": "待确认（仓库没有保存上游版本号）",
        "upstream": "待确认（仓库没有保存下载 URL 或上游母版 SHA-256）",
        "license": "SIL OFL 1.1；全文 `assets/fonts/OFL-Baloo2.txt` 随包",
    },
    {
        "id": "ResourceHanRoundedCN-Medium.otf",
        "path": "assets/fonts/ResourceHanRoundedCN-Medium.otf",
        "version": "Resource Han Rounded CN v1.910；由 CFF2 可变母版静态化/子集化",
        "upstream": "发行包 `4ad7b141...5df09`；母版 `ee3f276c...eb1e`（全文见 `assets/fonts/README.md`）",
        "license": "SIL OFL 1.1；全文 `assets/fonts/OFL-ResourceHanRounded.txt` 随包",
    },
    {
        "id": "ResourceHanRoundedCN-Bold.otf",
        "path": "assets/fonts/ResourceHanRoundedCN-Bold.otf",
        "version": "Resource Han Rounded CN v1.910；由 CFF2 可变母版静态化/子集化",
        "upstream": "发行包 `4ad7b141...5df09`；母版 `ee3f276c...eb1e`（全文见 `assets/fonts/README.md`）",
        "license": "SIL OFL 1.1；全文 `assets/fonts/OFL-ResourceHanRounded.txt` 随包",
    },
    {
        "id": "ResourceHanRoundedCN-Heavy.otf",
        "path": "assets/fonts/ResourceHanRoundedCN-Heavy.otf",
        "version": "Resource Han Rounded CN v1.910；由 CFF2 可变母版静态化/子集化",
        "upstream": "发行包 `4ad7b141...5df09`；母版 `ee3f276c...eb1e`（全文见 `assets/fonts/README.md`）",
        "license": "SIL OFL 1.1；全文 `assets/fonts/OFL-ResourceHanRounded.txt` 随包",
    },
    {
        "id": "OFL-Baloo2.txt",
        "path": "assets/fonts/OFL-Baloo2.txt",
        "version": "SIL Open Font License 1.1",
        "upstream": "待确认（仓库没有保存 Baloo 2 上游母版记录）",
        "license": "许可证正文；与 `Baloo2-Variable.ttf` 成对发行",
    },
    {
        "id": "OFL-ResourceHanRounded.txt",
        "path": "assets/fonts/OFL-ResourceHanRounded.txt",
        "version": "SIL Open Font License 1.1",
        "upstream": "Resource Han Rounded CN v1.910；上游记录见 `assets/fonts/README.md`",
        "license": "许可证正文；与三个 Resource Han Rounded 运行时子集成对发行",
    },
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def first_repository_date(relative_path: str) -> str:
    result = subprocess.run(
        ["git", "log", "--diff-filter=A", "--follow", "--format=%as", "--", relative_path],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    dates = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return dates[-1] if dates else "无提交记录"


def art_items() -> list[dict]:
    manifest = json.loads((ROOT / "assets/art/manifest.json").read_text(encoding="utf-8"))
    items = []
    for group in manifest.get("groups", []):
        for asset_id in group.get("ids", []):
            items.append(
                {
                    "id": asset_id,
                    "path": f"assets/art/{group['directory']}/{asset_id}.png",
                    "alpha": bool(group.get("alpha", True)),
                    "directory": group["directory"],
                }
            )
    return sorted(items, key=lambda item: item["id"])


def audio_items() -> list[dict]:
    manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8"))
    return [
        {"id": cue_id, "path": spec["path"].removeprefix("res://")}
        for cue_id, spec in sorted(manifest.get("items", {}).items())
    ]


def art_date(item: dict) -> str:
    if item["id"] in CONFIRMED_ART_DATES:
        return CONFIRMED_ART_DATES[item["id"]] + "（prompt 记录明示）"
    clue = first_repository_date(item["path"])
    return f"待确认（线索：仓库首次记录 {clue}，不等同生成日）"


def art_postprocess(item: dict) -> str:
    if item["alpha"]:
        return "有；色键去背、1px matte/去溢色、缩放与透明/体积 QA（具体人工修图待确认）"
    return "有；构建脚本规格化与尺寸/体积 QA（具体人工修图待确认）"


def render() -> str:
    arts = art_items()
    audio = audio_items()
    lines = [
        "# 26 · 资产来源与授权证据台账",
        "",
        "> 这是一份证据台账，不是法律意见。记录以仓库中的 prompt、生成脚本、清单、许可证正文和校验值为准；证据不足处一律标为「待确认」，不得把线索当成结论。",
        "",
        "## 1. 覆盖范围与证据口径",
        "",
        f"- 本页逐项覆盖 **{len(arts)} 张美术、{len(audio)} 个音频、{len(FONT_RECORDS)} 个字体交付物**，ID 与运行时 manifest 一一对应。",
        f"- 美术 prompt 与已知生成记录的单一证据源：[final_prompt_record.md]({PROMPT_RECORD})；manifest 只证明运行时交付关系，不证明生成日期或权利归属。",
        f"- 音频事实源：[audio_spec.md]({AUDIO_SPEC}) 与 [render_audio_assets.py]({AUDIO_RENDERER})；脚本声明为项目内确定性合成且未用第三方 samples、loops 或 preset recordings，但权利主体与署名策略仍需所有者确认。",
        "- 字体运行时文件和许可证正文 SHA-256 直接按当前仓库计算；Resource Han Rounded 的上游发行包与母版 SHA-256 引用 `assets/fonts/README.md` 已审计记录。",
        "- 「仓库首次记录」只是一条待查线索，绝不等同于生成日、取得日或授权生效日。",
        "",
        "## 2. 美术（180/180）",
        "",
        "| 类型 | 资产 ID | 运行时文件 | 生成日期 | 模型/服务 | prompt 记录 | 人工/本地后期 | 商用权归属结论 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for item in arts:
        lines.append(
            "| art | `{id}` | `{path}` | {date} | 内置 `imagegen`；底层生成模型与服务主体待确认 | "
            "[统一记录]({prompt}) | {post} | 待确认；需核对生成时适用的 imagegen 服务条款、账号/订阅主体与生成日 |".format(
                id=item["id"],
                path=item["path"],
                date=art_date(item),
                prompt=PROMPT_RECORD,
                post=art_postprocess(item),
            )
        )

    lines.extend(
        [
            "",
            "## 3. 音频（23/23）",
            "",
            "| 类型 | cue ID | 运行时文件 | 生成日期 | 来源 | 授权类型与出处 | 是否需要署名 |",
            "|---|---|---|---|---|---|---|",
        ]
    )
    for item in audio:
        clue = first_repository_date(item["path"])
        lines.append(
            f"| audio | `{item['id']}` | `{item['path']}` | 待确认（线索：合成 RNG 种子 `20260802`；仓库首次记录 {clue}） | "
            f"项目内本地确定性合成；[规格]({AUDIO_SPEC}) / [生成脚本]({AUDIO_RENDERER}) 明示无第三方 samples、loops、preset recordings | "
            "待确认；仓库证据支持“无第三方采样”，但没有保存权利主体确认或外部授权链接 | 待确认；由所有者/律师确认作者、权利主体与署名策略 |"
        )

    lines.extend(
        [
            "",
            "## 4. 字体交付物（6/6）",
            "",
            "| 类型 | 交付物 ID | 文件 | 版本/构建 | 上游校验记录 | 当前文件 SHA-256 | 许可证 |",
            "|---|---|---|---|---|---|---|",
        ]
    )
    for item in FONT_RECORDS:
        lines.append(
            f"| font | `{item['id']}` | `{item['path']}` | {item['version']} | {item['upstream']} | "
            f"`{sha256(ROOT / item['path'])}` | {item['license']} |"
        )

    art_ids = "、".join(f"`{item['id']}`" for item in arts)
    audio_ids = "、".join(f"`{item['id']}`" for item in audio)
    lines.extend(
        [
            "",
            "## 5. 待确认汇总",
            "",
            "以下事项在取得原始账号记录、下载记录、适用条款快照或所有者书面确认前不得改写成肯定结论：",
            "",
            f"1. **美术服务与商用权（180 项）**：需要确认内置 imagegen 的底层模型/服务名称、每次生成时适用的服务条款版本、账号与订阅主体、输出物商用权归属。受影响 ID：{art_ids}。",
            f"2. **美术生成日期**：表中由 prompt 记录明示日期的项目可直接追溯；其余只保留仓库首次记录日作为线索，仍需查原始生成任务记录。",
            f"3. **音频权利主体与署名（23 项）**：生成脚本与规格能证明当前仓库没有记录第三方采样，但不能替代所有者对作者、雇佣/委托关系、权利主体和署名策略的确认。受影响 ID：{audio_ids}。",
            "4. **Baloo 2 上游母版**：当前只有运行时字体与 OFL 正文，缺上游下载 URL、版本号和母版 SHA-256。线索：`assets/fonts/Baloo2-Variable.ttf` 与 `assets/fonts/OFL-Baloo2.txt`。",
            "5. **法务复核**：SIL OFL 1.1 正文已随包且文件成对校验；是否还需商店页或其他位置披露、AI 输出在目标发行法域的保护与排他性，交由律师确认。",
            "",
            "## 6. 自动校验",
            "",
            "`python3 tools/check_provenance.py` 会把本页的 art/audio/font 行与运行时 manifest 和六个字体交付物逐项对齐，检查重复、遗漏、幽灵条目与空白的待确认声明；`tools/validate_data.py` 也会调用同一校验。",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    OUTPUT.write_text(render(), encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
