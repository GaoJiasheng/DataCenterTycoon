#!/usr/bin/env python3
"""Compose two same-size UI review screenshots into a labeled comparison."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--title", default="UI REVIEW")
    args = parser.parse_args()

    before = Image.open(args.before).convert("RGB")
    after = Image.open(args.after).convert("RGB")
    if before.size != after.size:
        raise SystemExit(f"size mismatch: before={before.size}, after={after.size}")

    gutter = 24
    header = 76
    width, height = before.size
    canvas = Image.new("RGB", (width * 2 + gutter * 3, height + header), "#122438")
    canvas.paste(before, (gutter, header))
    canvas.paste(after, (width + gutter * 2, header))

    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=22)
    draw.text((gutter, 22), f"{args.title}  ·  BEFORE", fill="#fff6e8", font=font)
    draw.text((width + gutter * 2, 22), "AFTER", fill="#fff6e8", font=font)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, optimize=True)
    print(f"Wrote {args.output} size={canvas.size}")


if __name__ == "__main__":
    main()
