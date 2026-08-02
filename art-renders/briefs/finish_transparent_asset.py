#!/usr/bin/env python3
"""Finish a chroma-keyed RGBA game asset for review.

The script removes a one-pixel matte fringe, fits the visible subject into an
exact square canvas, and adds the neutral soft contact shadow required by the
project style bible. It never overwrites the source image.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--size", type=int, help="square output size")
    parser.add_argument("--width", type=int, help="non-square output width")
    parser.add_argument("--height", type=int, help="non-square output height")
    parser.add_argument("--margin", type=float, default=0.05)
    parser.add_argument("--no-shadow", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.size:
        canvas_width = canvas_height = args.size
    elif args.width and args.height:
        canvas_width, canvas_height = args.width, args.height
    else:
        raise SystemExit("provide --size or both --width and --height")
    source = Image.open(args.input).convert("RGBA")
    rgb = source.convert("RGB")
    alpha = source.getchannel("A")

    # Contract the hard chroma matte by one source pixel, then replace the new
    # one-pixel subject boundary with a local median. This removes either green
    # or magenta key spill without touching interior green LEDs or purple art.
    contracted = alpha.filter(ImageFilter.MinFilter(3))
    inner = contracted.filter(ImageFilter.MinFilter(3))
    boundary = Image.new("L", source.size)
    boundary.putdata(
        [max(0, outer - inside) for outer, inside in zip(contracted.getdata(), inner.getdata())]
    )
    median_rgb = rgb.filter(ImageFilter.MedianFilter(5))
    cleaned_pixels = [
        median if is_boundary else original
        for original, median, is_boundary in zip(
            rgb.getdata(), median_rgb.getdata(), boundary.getdata()
        )
    ]
    cleaned_rgb = Image.new("RGB", source.size)
    cleaned_rgb.putdata(cleaned_pixels)
    cleaned = cleaned_rgb.convert("RGBA")
    cleaned.putalpha(contracted)

    bbox = contracted.getbbox()
    if bbox is None:
        raise SystemExit("input contains no visible subject after matte cleanup")
    subject = cleaned.crop(bbox)

    usable_width = round(canvas_width * (1.0 - 2.0 * args.margin))
    usable_height = round(canvas_height * (1.0 - 2.0 * args.margin))
    scale = min(usable_width / subject.width, usable_height / subject.height)
    target = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(target, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 0))
    x = (canvas_width - subject.width) // 2
    y = (canvas_height - subject.height) // 2

    if not args.no_shadow:
        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(shadow)
        shadow_width = round(subject.width * 0.75)
        shadow_height = max(8, round(subject.height * 0.07))
        center_x = canvas_width // 2
        center_y = y + subject.height - round(subject.height * 0.08)
        draw.ellipse(
            (
                center_x - shadow_width // 2,
                center_y - shadow_height // 2,
                center_x + shadow_width // 2,
                center_y + shadow_height // 2,
            ),
            fill=(43, 58, 85, 90),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(max(3, min(canvas.size) / 80)))
        canvas = Image.alpha_composite(canvas, shadow)

    canvas.alpha_composite(subject, (x, y))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.out, format="PNG", optimize=True)
    print(
        f"Wrote {args.out} size={canvas.size} subject={subject.size} "
        f"bbox={canvas.getchannel('A').getbbox()}"
    )


if __name__ == "__main__":
    main()
