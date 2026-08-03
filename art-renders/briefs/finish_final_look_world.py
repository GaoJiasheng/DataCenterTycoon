#!/usr/bin/env python3
"""Finish the generated §10 world textures at their runtime contracts."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "visual" / "work" / "final_look_10"
WORLD_REBUILD_WORK = ROOT / "visual" / "work" / "final_look_11"
FINAL = ROOT / "visual" / "final" / "map"


def center_crop_ratio(image: Image.Image, ratio: float) -> Image.Image:
    width, height = image.size
    current = width / height
    if current > ratio:
        target = round(height * ratio)
        left = (width - target) // 2
        return image.crop((left, 0, left + target, height))
    target = round(width / ratio)
    top = (height - target) // 2
    return image.crop((0, top, width, top + target))


def blend_opposite_edges(image: Image.Image, band: int) -> Image.Image:
    """Make opposite edges pixel-identical with a cosine falloff into the tile."""
    result = image.convert("RGB")
    source = result.copy()
    src = source.load()
    dst = result.load()
    width, height = result.size
    for distance in range(band):
        strength = 0.5 * (1.0 + math.cos(math.pi * distance / band))
        left = distance
        right = width - 1 - distance
        for y in range(height):
            a, b = src[left, y], src[right, y]
            average = tuple(round((a[channel] + b[channel]) * 0.5) for channel in range(3))
            dst[left, y] = tuple(round(a[channel] * (1.0 - strength) + average[channel] * strength) for channel in range(3))
            dst[right, y] = tuple(round(b[channel] * (1.0 - strength) + average[channel] * strength) for channel in range(3))
    source = result.copy()
    src = source.load()
    dst = result.load()
    for distance in range(band):
        strength = 0.5 * (1.0 + math.cos(math.pi * distance / band))
        top = distance
        bottom = height - 1 - distance
        for x in range(width):
            a, b = src[x, top], src[x, bottom]
            average = tuple(round((a[channel] + b[channel]) * 0.5) for channel in range(3))
            dst[x, top] = tuple(round(a[channel] * (1.0 - strength) + average[channel] * strength) for channel in range(3))
            dst[x, bottom] = tuple(round(b[channel] * (1.0 - strength) + average[channel] * strength) for channel in range(3))
    return result


def finish_grass() -> None:
    grass_v2 = WORLD_REBUILD_WORK / "ground_tile_grass_v2_source.png"
    grass_source = grass_v2 if grass_v2.is_file() else WORK / "ground_tile_grass_source.png"
    source = Image.open(grass_source).convert("RGB")
    source = center_crop_ratio(source, 1.0).resize((1024, 1024), Image.Resampling.LANCZOS)
    source = blend_opposite_edges(source, 48)
    # A restrained palette is invisible at runtime scale and keeps the full
    # seamless tile below the repository's 1.5 MB mobile-texture budget.
    source = source.quantize(colors=64, method=Image.Quantize.MEDIANCUT)
    source.save(FINAL / "ground_tile_grass.png", optimize=True)


def finish_paths() -> None:
    for asset_id in ("ground_path_straight", "ground_path_cross"):
        source = Image.open(WORK / f"{asset_id}_source.png").convert("RGB")
        source = center_crop_ratio(source, 1.0).resize((512, 512), Image.Resampling.LANCZOS)
        # The generator supplies grass to describe the intended shoulders, but
        # the live campus has its own seamless turf. Key green-dominant pixels
        # into a soft alpha matte so paths blend into that canonical ground
        # instead of exposing square grass blocks after scaling and rotation.
        alpha = Image.new("L", source.size)
        source_pixels = source.load()
        alpha_pixels = alpha.load()
        for y in range(source.height):
            for x in range(source.width):
                red, green, blue = source_pixels[x, y]
                green_dominance = green - (red + blue) * 0.5
                opacity = round(255.0 * (42.0 - green_dominance) / 30.0)
                alpha_pixels[x, y] = max(0, min(255, opacity))
        alpha = alpha.filter(ImageFilter.GaussianBlur(radius=1.25))
        result = source.convert("RGBA")
        result.putalpha(alpha)
        result.save(FINAL / f"{asset_id}.png", optimize=True)


def finish_fog() -> None:
    source = Image.open(WORK / "world_edge_fog_source.png").convert("RGB")
    source = center_crop_ratio(source, 2.0).resize((1024, 512), Image.Resampling.LANCZOS)
    luminance = ImageOps.grayscale(source)
    low, high = luminance.getextrema()
    span = max(1, high - low)
    alpha = luminance.point(lambda value: max(0, min(255, round((value - low) * 255 / span))))
    fog = Image.new("RGBA", source.size, (255, 244, 216, 0))
    fog.putalpha(alpha)
    fog.save(FINAL / "world_edge_fog.png", optimize=True)


def main() -> None:
    FINAL.mkdir(parents=True, exist_ok=True)
    finish_grass()
    finish_paths()
    finish_fog()
    generated = [
        FINAL / "ground_tile_grass.png",
        FINAL / "ground_path_straight.png",
        FINAL / "ground_path_cross.png",
        FINAL / "world_edge_fog.png",
    ]
    for path in generated:
        image = Image.open(path)
        print(f"Wrote {path.relative_to(ROOT)} size={image.size} mode={image.mode}")


if __name__ == "__main__":
    main()
