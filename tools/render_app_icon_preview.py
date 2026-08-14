#!/usr/bin/env python3
"""Render the exact App Store source through an iOS-like rounded icon mask."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "art" / "store" / "app_icon.png"
OUTPUT = ROOT / "docs" / "ui_review" / "app_icon_v2_ios_preview.png"


def add_icon(canvas: Image.Image, source: Image.Image, box: tuple[int, int, int]) -> None:
    x, y, size = box
    icon = source.resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=round(size * 0.225), fill=255
    )
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", canvas.size, 0)
    shadow_mask.paste(mask, (x, y + max(8, size // 30)))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(max(8, size // 24)))
    shadow.putalpha(shadow_mask.point(lambda value: round(value * 0.55)))
    canvas.alpha_composite(shadow)
    canvas.paste(icon, (x, y), mask)


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    if source.size != (1024, 1024):
        raise SystemExit(f"expected 1024x1024 app icon, got {source.size}")
    canvas = Image.new("RGBA", (1400, 800), "#111925")
    add_icon(canvas, source, (70, 70, 660))
    add_icon(canvas, source, (850, 130, 300))
    add_icon(canvas, source, (1210, 220, 120))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT, format="PNG", optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
