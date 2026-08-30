#!/usr/bin/env python3
"""Validate the deterministic App Store delivery contract for the iOS build."""

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT_NAMES = (
    "01_park.png",
    "02_datacenter.png",
    "03_market.png",
    "04_technology.png",
    "05_prestige.png",
)
SCREENSHOT_GROUPS = {
    "iphone_69": {(1260, 2736), (1290, 2796), (1320, 2868)},
}
LOCALES = ("en", "zh_CN")


def png_info(path):
    payload = path.read_bytes()
    header = payload[:26]
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG")
    width, height = struct.unpack(">II", header[16:24])
    color_type = header[25]
    has_transparency = color_type in (4, 6)
    offset = 8
    while offset + 12 <= len(payload):
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        chunk_type = payload[offset + 4:offset + 8]
        if chunk_type == b"tRNS":
            has_transparency = True
        offset += 12 + length
        if chunk_type == b"IEND":
            break
    return width, height, has_transparency


def validate_png(path, accepted_sizes, failures, label):
    if not path.is_file():
        failures.append(f"missing {path.relative_to(ROOT)}")
        return None
    try:
        width, height, has_transparency = png_info(path)
    except ValueError as error:
        failures.append(f"{label}: {error}")
        return None
    if (width, height) not in accepted_sizes:
        expected = " or ".join(f"{w}x{h}" for w, h in sorted(accepted_sizes))
        failures.append(f"{label}: {width}x{height}; expected {expected}")
    if has_transparency:
        failures.append(f"{label}: alpha channel is not accepted by App Store Connect")
    return width, height


def main():
    failures = []
    icon = ROOT / "assets/art/store/app_icon.png"
    validate_png(icon, {(1024, 1024)}, failures, "app icon")

    for locale in LOCALES:
        for group, sizes in SCREENSHOT_GROUPS.items():
            directory = ROOT / "docs/store/screenshots" / locale / group
            group_size = None
            for filename in SCREENSHOT_NAMES:
                path = directory / filename
                actual = validate_png(path, sizes, failures, f"{locale}/{group}/{filename}")
                if actual is not None and group_size is None:
                    group_size = actual
                elif actual is not None and actual != group_size:
                    failures.append(f"{locale}/{group}: all five screenshots must use one consistent size")

    if failures:
        print("App Store asset gate blocked:")
        for failure in failures:
            print("-", failure)
        return 1
    print("Validated opaque app icon and 10 localized iPhone screenshots.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
