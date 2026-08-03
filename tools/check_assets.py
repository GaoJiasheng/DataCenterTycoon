#!/usr/bin/env python3
"""Validate delivered visual and audio assets without third-party packages."""

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART_MANIFEST = ROOT / "assets/art/manifest.json"
AUDIO_MANIFEST = ROOT / "assets/audio/manifest.json"
FONT_FILES = {
    "Baloo 2 variable": ROOT / "assets/fonts/Baloo2-Variable.ttf",
    "Noto Sans SC variable": ROOT / "assets/fonts/NotoSansSC-Variable.ttf",
    "Baloo 2 OFL": ROOT / "assets/fonts/OFL-Baloo2.txt",
    "Noto Sans SC OFL": ROOT / "assets/fonts/OFL-NotoSansSC.txt",
}


def expanded_art_items():
    manifest = json.loads(ART_MANIFEST.read_text(encoding="utf-8"))
    items = dict(manifest.get("items", {}))
    for group in manifest.get("groups", []):
        for asset_id in group["ids"]:
            items[asset_id] = {
                "path": ROOT / "assets/art" / group["directory"] / f"{asset_id}.png",
                "size": tuple(group["size"]),
                "alpha": group.get("alpha", True),
                "max_bytes": group.get("max_bytes", 1572864),
            }
    return items


def png_info(path):
    payload = path.read_bytes()
    header = payload[:26]
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG header")
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


def validate_art(strict):
    failures = []
    missing = []
    items = expanded_art_items()
    if len(items) != 152:
        failures.append(f"manifest contains {len(items)} assets; expected 152")
    for asset_id, spec in sorted(items.items()):
        path = Path(spec["path"])
        if not path.exists():
            missing.append(asset_id)
            continue
        try:
            width, height, has_transparency = png_info(path)
        except ValueError as error:
            failures.append(f"{asset_id}: {error}")
            continue
        if (width, height) != tuple(spec["size"]):
            failures.append(f"{asset_id}: {width}x{height}, expected {spec['size'][0]}x{spec['size'][1]}")
        if spec["alpha"] and not has_transparency:
            failures.append(f"{asset_id}: PNG has no alpha channel or transparency chunk")
        if path.stat().st_size > spec["max_bytes"]:
            failures.append(f"{asset_id}: {path.stat().st_size} bytes exceeds {spec['max_bytes']}")
    if missing:
        print(f"ART: {len(items) - len(missing)}/{len(items)} present; {len(missing)} missing")
        if strict:
            failures.append("missing art: " + ", ".join(missing))
    else:
        print(f"ART: all {len(items)} files present")
    return failures


def validate_audio(strict):
    manifest = json.loads(AUDIO_MANIFEST.read_text(encoding="utf-8"))
    missing = []
    failures = []
    for cue_id, spec in manifest.get("items", {}).items():
        path = ROOT / spec["path"].replace("res://", "")
        if not path.exists():
            missing.append(cue_id)
        elif path.stat().st_size == 0:
            failures.append(f"{cue_id}: empty file")
    print(f"AUDIO: {len(manifest['items']) - len(missing)}/{len(manifest['items'])} present; {len(missing)} missing")
    if strict and missing:
        failures.append("missing audio: " + ", ".join(missing))
    return failures


def validate_fonts():
    failures = []
    for label, path in FONT_FILES.items():
        if not path.exists():
            failures.append(f"{label}: missing {path.relative_to(ROOT)}")
        elif path.stat().st_size == 0:
            failures.append(f"{label}: empty file")
    print(f"FONTS: {len(FONT_FILES) - len(failures)}/{len(FONT_FILES)} present")
    return failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="fail when expected files are missing")
    parser.add_argument("--audio", action="store_true", help="also require and validate audio")
    args = parser.parse_args()
    failures = validate_art(args.strict)
    failures.extend(validate_fonts())
    if args.audio:
        failures.extend(validate_audio(args.strict))
    if failures:
        for failure in failures:
            print("ERROR:", failure)
        return 1
    print("Asset contract is valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
