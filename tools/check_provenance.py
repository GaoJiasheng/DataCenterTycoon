#!/usr/bin/env python3
"""Verify that the provenance ledger exactly covers shipped asset manifests."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/26_provenance.md"
FONT_IDS = {
    "Baloo2-Variable.ttf",
    "ResourceHanRoundedCN-Medium.otf",
    "ResourceHanRoundedCN-Bold.otf",
    "ResourceHanRoundedCN-Heavy.otf",
    "OFL-Baloo2.txt",
    "OFL-ResourceHanRounded.txt",
}
ROW = re.compile(r"^\| (art|audio|font) \| `([^`]+)` \|")


def expected_ids() -> dict[str, set[str]]:
    art_manifest = json.loads((ROOT / "assets/art/manifest.json").read_text(encoding="utf-8"))
    art = {
        asset_id
        for group in art_manifest.get("groups", [])
        for asset_id in group.get("ids", [])
    } | set(art_manifest.get("items", {}))
    audio_manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8"))
    return {
        "art": art,
        "audio": set(audio_manifest.get("items", {})),
        "font": set(FONT_IDS),
    }


def validate() -> list[str]:
    failures = []
    if not LEDGER.is_file():
        return ["provenance ledger missing: docs/26_provenance.md"]
    text = LEDGER.read_text(encoding="utf-8")
    found: dict[str, list[str]] = {"art": [], "audio": [], "font": []}
    for line in text.splitlines():
        match = ROW.match(line)
        if match:
            found[match.group(1)].append(match.group(2))
    expected = expected_ids()
    for kind in ("art", "audio", "font"):
        duplicates = sorted(asset_id for asset_id, count in Counter(found[kind]).items() if count > 1)
        if duplicates:
            failures.append(f"provenance/{kind}: duplicate IDs {duplicates}")
        actual = set(found[kind])
        missing = sorted(expected[kind] - actual)
        extra = sorted(actual - expected[kind])
        if missing:
            failures.append(f"provenance/{kind}: missing IDs {missing}")
        if extra:
            failures.append(f"provenance/{kind}: unknown IDs {extra}")
    if "## 5. 待确认汇总" not in text:
        failures.append("provenance: missing standalone 待确认 summary")
    if text.count("待确认") < 180 + 23:
        failures.append("provenance: uncertain art/audio evidence was silently promoted to fact")
    return failures


def main() -> int:
    failures = validate()
    if failures:
        for failure in failures:
            print("ERROR:", failure)
        return 1
    expected = expected_ids()
    print(
        "PROVENANCE: exact coverage "
        + ", ".join(f"{kind}={len(expected[kind])}" for kind in ("art", "audio", "font"))
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
