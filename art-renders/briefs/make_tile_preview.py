#!/usr/bin/env python3
"""Create a repeated texture preview to expose seams."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--tile-size", type=int, default=256)
    parser.add_argument("--grid", type=int, default=3)
    args = parser.parse_args()

    tile = Image.open(args.input).convert("RGB")
    tile = tile.resize((args.tile_size, args.tile_size), Image.Resampling.LANCZOS)
    preview = Image.new(
        "RGB", (args.tile_size * args.grid, args.tile_size * args.grid)
    )
    for y in range(args.grid):
        for x in range(args.grid):
            preview.paste(tile, (x * args.tile_size, y * args.tile_size))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.out, format="PNG", optimize=True)
    print(f"Wrote {args.out} {preview.size}")


if __name__ == "__main__":
    main()
