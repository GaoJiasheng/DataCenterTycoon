#!/usr/bin/env python3
"""Create final review sheets for the complete visual delivery."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FINAL = ROOT / "visual" / "final"
REVIEW = ROOT / "visual" / "review"
MANIFEST = ROOT / "briefs" / "visual_asset_manifest.json"


def checker(size: tuple[int, int], step: int = 16) -> Image.Image:
    out = Image.new("RGBA", size, "#DCE6EE")
    draw = ImageDraw.Draw(out)
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2:
                draw.rectangle((x, y, min(x + step - 1, size[0] - 1), min(y + step - 1, size[1] - 1)), fill="#F7FAFC")
    return out


def draw_sheet(items: list[dict], out: Path, title: str, columns: int = 6, cell: tuple[int, int] = (240, 270), icon_size: int | None = None) -> None:
    font = ImageFont.load_default(size=15)
    title_font = ImageFont.load_default(size=24)
    rows = (len(items) + columns - 1) // columns
    header = 56
    sheet = Image.new("RGB", (columns * cell[0], header + rows * cell[1]), "#2B3A55")
    draw = ImageDraw.Draw(sheet)
    draw.text((18, 15), title, fill="#FFF6E8", font=title_font)
    for index, item in enumerate(items):
        x0 = (index % columns) * cell[0]
        y0 = header + (index // columns) * cell[1]
        preview = checker((cell[0] - 12, cell[1] - 42))
        asset = Image.open(ROOT / item["output"]).convert("RGBA")
        if icon_size:
            asset.thumbnail((icon_size, icon_size), Image.Resampling.LANCZOS)
        else:
            asset.thumbnail((cell[0] - 34, cell[1] - 64), Image.Resampling.LANCZOS)
        px = (preview.width - asset.width) // 2
        py = (preview.height - asset.height) // 2
        preview.alpha_composite(asset, (px, py))
        sheet.paste(preview.convert("RGB"), (x0 + 6, y0 + 4))
        label = item["name"]
        bounds = draw.textbbox((0, 0), label, font=font)
        draw.text((x0 + max(5, (cell[0] - (bounds[2] - bounds[0])) // 2), y0 + cell[1] - 31), label, fill="#FFF6E8", font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, format="PNG", optimize=True)
    print(f"Wrote {out} {sheet.size}")


def main() -> None:
    items = json.loads(MANIFEST.read_text(encoding="utf-8"))
    order = ["buildings", "attachments", "racks", "map", "fx", "characters", "customers", "ui", "store"]
    for category in order:
        category_items = [item for item in items if item["category"] == category]
        draw_sheet(category_items, REVIEW / f"{category}_contact.png", f"{category.upper()} · {len(category_items)} assets")
    draw_sheet(items, REVIEW / "all_assets_contact.png", f"DATA CENTER TYCOON · COMPLETE VISUAL DELIVERY · {len(items)} ASSETS", columns=8, cell=(210, 235))
    icon_items = [item for item in items if item["category"] == "ui" and item["name"].startswith("ic_")]
    draw_sheet(icon_items, REVIEW / "ui_icons_48px_contact.png", "UI ICONS · ACTUAL 48px READABILITY CHECK", columns=9, cell=(120, 135), icon_size=48)


if __name__ == "__main__":
    main()
