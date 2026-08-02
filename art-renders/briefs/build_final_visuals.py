#!/usr/bin/env python3
"""Build the complete, isolated final visual-asset delivery.

Sources remain in ``visual/work``.  This script removes chroma keys with the
official imagegen helper, normalizes dimensions and margins, preserves opaque
full-bleed art, and writes a machine-readable manifest plus a QA summary.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import struct
import subprocess

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "visual" / "work"
FINAL = ROOT / "visual" / "final"
ALPHA_WORK = WORK / "_alpha_final"
REMOVE_KEY = Path("/Users/gavin/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py")
FINISH = ROOT / "briefs" / "finish_transparent_asset.py"
LIMIT_BYTES = 1_500_000


@dataclass(frozen=True)
class Asset:
    category: str
    name: str
    source: str
    width: int
    height: int
    transparent: bool = True
    shadow: bool = False
    margin: float = 0.05
    matte: str = "hard"

    @property
    def output(self) -> Path:
        return FINAL / self.category / f"{self.name}.png"


def build_manifest() -> list[Asset]:
    assets: list[Asset] = []

    # 24 buildings: four tiers, six lifecycle states.
    for tier, size in ((0, 768), (1, 768), (2, 1024), (3, 1280)):
        for state in ("active", "construction", "dark", "aged", "decayed", "ruin"):
            revision = "v2" if tier == 1 and state == "active" else "v1"
            assets.append(Asset("buildings", f"dc_t{tier}_{state}", f"dc_t{tier}_{state}_chroma_{revision}.png", size, size, shadow=True, margin=0.035))

    # 14 power/cooling attachments.
    for tier in (1, 2, 3):
        for state in ("active", "idle"):
            revision = "v2" if tier == 1 and state == "active" else "v1"
            assets.append(Asset("attachments", f"power_t{tier}_{state}", f"power_t{tier}_{state}_chroma_{revision}.png", 512, 512, shadow=True))
    for tier in (1, 2):
        for state in ("active", "idle"):
            assets.append(Asset("attachments", f"cool_air_t{tier}_{state}", f"cool_air_t{tier}_{state}_chroma_v1.png", 512, 512, shadow=True))
    for tier in (1, 2):
        for state in ("active", "idle"):
            revision = "v2" if tier == 2 else "v1"
            assets.append(Asset("attachments", f"cool_liquid_t{tier}_{state}", f"cool_liquid_t{tier}_{state}_chroma_{revision}.png", 512, 512, shadow=True))

    # 26 rack/slot assets.
    assets.extend([
        Asset("racks", "slot_empty", "slot_empty_chroma_v1.png", 512, 512, shadow=True, margin=0.06),
        Asset("racks", "slot_locked", "slot_locked_chroma_v1.png", 512, 512, shadow=True, margin=0.06),
    ])
    for family in ("compute", "storage", "gpu"):
        for tier in (1, 2):
            for state in ("active", "dark", "fault", "installing"):
                name = f"rack_{family}_t{tier}_{state}"
                assets.append(Asset("racks", name, f"{name}_chroma_v1.png", 512, 512, shadow=True, margin=0.06))

    # 8 map assets.
    assets.extend([
        Asset("map", "ground_tile", "ground_tile_source_v1.png", 1024, 1024, transparent=False, margin=0),
        Asset("map", "plot_forsale", "plot_forsale_source_v1.png", 768, 768, shadow=False, margin=0.03),
        Asset("map", "plot_owned", "plot_owned_source_v1.png", 768, 768, shadow=False, margin=0.03),
        Asset("map", "deco_road", "deco_road_source_v1.png", 512, 512, transparent=False, margin=0),
        Asset("map", "deco_tree", "deco_tree_chroma_v1.png", 384, 384, shadow=True, margin=0.06),
        Asset("map", "deco_bush", "deco_bush_source_v1.png", 256, 256, shadow=True, margin=0.06),
        Asset("map", "deco_pylon", "deco_pylon_source_v1.png", 512, 512, shadow=True, margin=0.06),
        Asset("map", "dc_interior_bg", "dc_interior_bg_source_v1.png", 1536, 2048, transparent=False, margin=0),
    ])

    # 9 effects; soft mattes retain wispy translucency where it is safe.
    fx = [
        ("fx_wind_streak", 256, "soft"),
        ("fx_snowflake", 128, "hard"),
        ("fx_frost_patch", 256, "soft"),
        ("fx_smoke_puff", 256, "soft"),
        ("fx_spark", 128, "soft"),
        ("fx_coin", 192, "hard"),
        ("fx_glow_ring", 512, "hard_feather"),
        ("fx_confetti_set", 512, "hard_feather"),
        ("fx_dust_puff", 256, "soft"),
    ]
    for name, size, matte in fx:
        assets.append(Asset("fx", name, f"{name}_source_v1.png", size, size, shadow=False, margin=0.02, matte=matte))

    # 5 dialogue poses.
    for pose in ("normal", "happy", "worried", "alert", "thinking"):
        assets.append(Asset("characters", f"guide_{pose}", f"guide_{pose}_chroma_v1.png", 768, 1024, shadow=False, margin=0.03))

    # 4 client badges.
    assets.extend([
        Asset("customers", "client_internet", "client_internet_source_v1.png", 384, 384, margin=0.04),
        Asset("customers", "client_mining", "client_mining_source_v1.png", 384, 384, margin=0.04),
        Asset("customers", "client_cloud", "client_cloud_chroma_v1.png", 384, 384, margin=0.04),
        Asset("customers", "client_gpu", "client_gpu_source_v1.png", 384, 384, margin=0.04),
    ])

    # 11 9-slice/UI components.
    components = [
        ("panel_main", 1024, 1024), ("panel_dark", 1024, 1024),
        ("btn_primary", 512, 256), ("btn_secondary", 512, 256),
        ("btn_warning", 512, 256), ("btn_danger", 512, 256),
        ("btn_disabled", 512, 256), ("btn_ad", 512, 256),
        ("progress_frame", 512, 128), ("progress_fill", 512, 128),
        ("dialog_bubble", 1024, 512),
    ]
    for name, width, height in components:
        assets.append(Asset("ui", name, f"{name}_source_v1.png", width, height, shadow=False, margin=0.02))

    # 27 standalone UI icons.  Network v3 is the accepted exact-three-node revision.
    icons = (
        "cash diamond power cooling heat wrench warning clock contract market_up market_down "
        "build tech shop settings network play_ad retire speedup lock check close era1 era2 era3 prestige bankrupt"
    ).split()
    for icon in icons:
        revision = "v3" if icon == "network" else "v1"
        assets.append(Asset("ui", f"ic_{icon}", f"ic_{icon}_source_{revision}.png", 256, 256, shadow=False, margin=0.06))

    # 6 store/marketing assets.
    assets.extend([
        Asset("store", "app_icon", "app_icon_source_v1.png", 1024, 1024, transparent=False, margin=0),
        Asset("store", "splash_bg", "splash_bg_source_v1.png", 1536, 2732, transparent=False, margin=0),
        Asset("store", "pack_starter", "pack_starter_source_v1.png", 512, 512, shadow=True, margin=0.04),
        Asset("store", "pack_builder", "pack_builder_source_v1.png", 512, 512, shadow=True, margin=0.04),
        Asset("store", "pack_tycoon", "pack_tycoon_source_v1.png", 512, 512, shadow=True, margin=0.04),
        Asset("store", "noads_badge", "noads_badge_source_v1.png", 512, 512, shadow=False, margin=0.04),
    ])

    assert len(assets) == 134, f"expected 134 assets, got {len(assets)}"
    assert len({(a.category, a.name) for a in assets}) == len(assets)
    return assets


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def chroma_to_alpha(asset: Asset) -> Path:
    source = WORK / asset.source
    alpha = ALPHA_WORK / asset.category / f"{asset.name}_alpha.png"
    alpha.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "python3", str(REMOVE_KEY), "--input", str(source), "--out", str(alpha),
        "--auto-key", "border", "--tolerance", "20", "--force",
    ]
    if asset.matte == "soft":
        command.extend(["--soft-matte", "--transparent-threshold", "10", "--opaque-threshold", "82", "--despill"])
    elif asset.matte == "hard_feather":
        command.extend(["--edge-feather", "0.45", "--despill"])
    else:
        command.append("--despill")
    run(command)
    return alpha


def finish_transparent(asset: Asset, alpha: Path) -> None:
    command = [
        "python3", str(FINISH), "--input", str(alpha), "--out", str(asset.output),
        "--width", str(asset.width), "--height", str(asset.height),
        "--margin", str(asset.margin),
    ]
    if not asset.shadow:
        command.append("--no-shadow")
    run(command)


def finish_opaque(asset: Asset) -> None:
    source = Image.open(WORK / asset.source).convert("RGB")
    # Full-bleed cover crop.  Splash-screen subject placement was generated with
    # a quiet upper third, so centered 9:16 cropping keeps the intended layout.
    output = ImageOps.fit(
        source,
        (asset.width, asset.height),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    asset.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(asset.output, format="PNG", optimize=True, compress_level=9)


def reduce_truecolor_complexity(path: Path, transparent: bool) -> None:
    if path.stat().st_size <= LIMIT_BYTES:
        return
    source = Image.open(path).convert("RGBA" if transparent else "RGB")
    for colors in (256, 192, 160, 128, 96, 64):
        if transparent:
            reduced = source.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
        else:
            # Dither-free palette reduction preserves the painted shapes while
            # avoiding high-frequency noise that compresses poorly in PNG.
            reduced = source.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        reduced.save(path, format="PNG", optimize=True, compress_level=9)
        if path.stat().st_size <= LIMIT_BYTES:
            return


def png_color_type(path: Path) -> int:
    data = path.read_bytes()[:29]
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return -1
    _width, _height, _depth, color_type = struct.unpack(">IIBB", data[16:26])
    return color_type


def qa_asset(asset: Asset) -> dict[str, object]:
    image = Image.open(asset.output)
    alpha = image.getchannel("A") if "A" in image.getbands() else None
    corners = []
    if alpha is not None:
        corners = [alpha.getpixel((0, 0)), alpha.getpixel((asset.width - 1, 0)), alpha.getpixel((0, asset.height - 1)), alpha.getpixel((asset.width - 1, asset.height - 1))]
    return {
        "category": asset.category,
        "name": asset.name,
        "source": asset.source,
        "output": str(asset.output.relative_to(ROOT)),
        "expected_size": [asset.width, asset.height],
        "actual_size": list(image.size),
        "mode": image.mode,
        "png_color_type": png_color_type(asset.output),
        "transparent_required": asset.transparent,
        "alpha_bbox": list(alpha.getbbox()) if alpha and alpha.getbbox() else None,
        "corner_alpha": corners,
        "bytes": asset.output.stat().st_size,
        "pass": image.size == (asset.width, asset.height)
        and asset.output.stat().st_size <= LIMIT_BYTES
        and ((asset.transparent and alpha is not None and corners == [0, 0, 0, 0]) or (not asset.transparent and alpha is None)),
    }


def write_reports(assets: list[Asset], qa: list[dict[str, object]]) -> None:
    manifest_path = ROOT / "briefs" / "visual_asset_manifest.json"
    manifest_path.write_text(json.dumps([asdict(a) | {"output": str(a.output.relative_to(ROOT))} for a in assets], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    qa_path = ROOT / "briefs" / "visual_qa_report.json"
    qa_path.write_text(json.dumps(qa, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    failures = [item for item in qa if not item["pass"]]
    category_counts: dict[str, int] = {}
    for asset in assets:
        category_counts[asset.category] = category_counts.get(asset.category, 0) + 1
    lines = [
        "# 全量视觉素材交付报告", "",
        f"- 总数：{len(assets)}", f"- 自动 QA 通过：{len(qa) - len(failures)}", f"- 自动 QA 失败：{len(failures)}",
        "- 交付目录：`../visual/final/`", "- 源图目录：`../visual/work/`", "",
        "## 分类数量", "",
    ]
    lines.extend(f"- `{category}`：{count}" for category, count in sorted(category_counts.items()))
    lines.extend(["", "## 自动检查", "", "检查精确尺寸、PNG 模式、透明资产四角 alpha、全文件 1.5MB 上限。视觉语义、统一风格与缩略可读性另以联系表人工审片。", ""])
    if failures:
        lines.extend(["## 未通过项", ""] + [f"- `{item['output']}`" for item in failures] + [""])
    (ROOT / "briefs" / "visual_delivery_report.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qa-only", action="store_true")
    parser.add_argument("--only", help="rebuild one asset as category/name")
    args = parser.parse_args()
    assets = build_manifest()
    missing = [str(WORK / asset.source) for asset in assets if not (WORK / asset.source).exists()]
    if missing:
        raise SystemExit("missing source files:\n" + "\n".join(missing))

    if not args.qa_only:
        selected = assets
        if args.only:
            selected = [asset for asset in assets if f"{asset.category}/{asset.name}" == args.only]
            if not selected:
                raise SystemExit(f"unknown asset: {args.only}")
        for index, asset in enumerate(selected, 1):
            print(f"[{index:03d}/{len(assets)}] {asset.category}/{asset.name}", flush=True)
            if asset.transparent:
                finish_transparent(asset, chroma_to_alpha(asset))
            else:
                finish_opaque(asset)
            reduce_truecolor_complexity(asset.output, asset.transparent)

    qa = [qa_asset(asset) for asset in assets]
    write_reports(assets, qa)
    failures = [item for item in qa if not item["pass"]]
    print(f"QA: {len(qa) - len(failures)}/{len(qa)} passed")
    if failures:
        for item in failures:
            print(f"FAIL {item['output']} size={item['actual_size']} bytes={item['bytes']} corners={item['corner_alpha']}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
