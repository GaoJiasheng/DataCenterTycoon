#!/usr/bin/env python3
"""Build a labeled checkerboard contact sheet for transparent asset review."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("names", nargs="+")
    return parser.parse_args()


def checker(size: tuple[int, int], step: int = 20) -> Image.Image:
    image = Image.new("RGBA", size, "#DCE6EE")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2:
                draw.rectangle((x, y, x + step - 1, y + step - 1), fill="#F7FAFC")
    return image


def main() -> None:
    args = parse_args()
    columns = 5
    rows = (len(args.names) + columns - 1) // columns
    cell_width, cell_height = 300, 330
    sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height), "#2B3A55")
    font = ImageFont.load_default(size=18)

    for index, name in enumerate(args.names):
        x0 = (index % columns) * cell_width
        y0 = (index // columns) * cell_height
        cell = checker((cell_width - 16, cell_height - 50))
        asset = Image.open(args.dir / f"{name}.png").convert("RGBA")
        asset.thumbnail((cell_width - 42, cell_height - 76), Image.Resampling.LANCZOS)
        ax = (cell.width - asset.width) // 2
        ay = (cell.height - asset.height) // 2
        cell.alpha_composite(asset, (ax, ay))
        sheet.alpha_composite(cell, (x0 + 8, y0 + 8))
        draw = ImageDraw.Draw(sheet)
        label_box = draw.textbbox((0, 0), name, font=font)
        label_width = label_box[2] - label_box[0]
        draw.text(
            (x0 + (cell_width - label_width) // 2, y0 + cell_height - 34),
            name,
            fill="#FFF6E8",
            font=font,
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(args.out, format="PNG", optimize=True)
    print(f"Wrote {args.out} {sheet.size}")


if __name__ == "__main__":
    main()
