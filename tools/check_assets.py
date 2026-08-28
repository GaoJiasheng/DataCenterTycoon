#!/usr/bin/env python3
"""Validate delivered visual and audio assets without third-party packages."""

import argparse
import csv
import json
import re
import struct
import sys
from pathlib import Path

from import_assets import visual_import_profile

ROOT = Path(__file__).resolve().parents[1]
ART_MANIFEST = ROOT / "assets/art/manifest.json"
AUDIO_MANIFEST = ROOT / "assets/audio/manifest.json"
FONT_FILES = {
    "Baloo 2 variable": ROOT / "assets/fonts/Baloo2-Variable.ttf",
    "Resource Han Rounded CN Medium": ROOT / "assets/fonts/ResourceHanRoundedCN-Medium.otf",
    "Resource Han Rounded CN Bold": ROOT / "assets/fonts/ResourceHanRoundedCN-Bold.otf",
    "Resource Han Rounded CN Heavy": ROOT / "assets/fonts/ResourceHanRoundedCN-Heavy.otf",
    "Baloo 2 OFL": ROOT / "assets/fonts/OFL-Baloo2.txt",
    "Resource Han Rounded OFL": ROOT / "assets/fonts/OFL-ResourceHanRounded.txt",
}
RHR_FONT_FILES = tuple(
    ROOT / "assets/fonts" / f"ResourceHanRoundedCN-{weight}.otf"
    for weight in ("Medium", "Bold", "Heavy")
)
LOCALIZATION = ROOT / "localization/ui.csv"
EXPECTED_ART_COUNT = 180


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
    if len(items) != EXPECTED_ART_COUNT:
        failures.append(
            f"manifest contains {len(items)} assets; expected {EXPECTED_ART_COUNT}"
        )
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


def texture_import_settings(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("compress/mode="):
            values["compress_mode"] = int(line.split("=", 1)[1])
        elif line.startswith("mipmaps/generate="):
            values["mipmaps"] = line.split("=", 1)[1] == "true"
    return values


def validate_art_import_settings():
    failures = []
    profile_counts = {}
    for asset_id, spec in sorted(expanded_art_items().items()):
        target = Path(spec["path"])
        profile_name, profile = visual_import_profile(target)
        profile_counts[profile_name] = profile_counts.get(profile_name, 0) + 1
        sidecar = target.with_suffix(target.suffix + ".import")
        if not sidecar.is_file():
            failures.append(f"{asset_id}: missing tracked texture import sidecar")
            continue
        settings = texture_import_settings(sidecar)
        expected = {
            "compress_mode": profile["compress_mode"],
            "mipmaps": profile["mipmaps"],
        }
        if settings != expected:
            failures.append(
                f"{asset_id}: import settings {settings}, expected {expected} ({profile_name})"
            )
    print("TEXTURE IMPORTS: " + ", ".join(
        f"{profile}={count}" for profile, count in sorted(profile_counts.items())
    ))
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
    required_characters = localization_characters(LOCALIZATION)
    # Player-visible text is not only ui.csv. Symbols hardcoded in GDScript
    # string literals shipped with no glyph coverage and rendered blank on
    # device while macOS quietly substituted a system font on the desktop.
    required_characters |= script_literal_characters()
    for path in RHR_FONT_FILES:
        if not path.is_file() or path.stat().st_size == 0:
            continue
        try:
            codepoints = sfnt_codepoints(path)
        except (ValueError, struct.error) as error:
            failures.append(f"{path.name}: cannot read cmap ({error})")
            continue
        missing = sorted(required_characters - codepoints)
        if missing:
            preview = "".join(chr(codepoint) for codepoint in missing[:24])
            failures.append(f"{path.name}: missing {len(missing)} player-visible characters ({preview})")
    print(f"FONTS: {len(FONT_FILES) - sum(1 for label, path in FONT_FILES.items() if not path.exists() or path.stat().st_size == 0)}/{len(FONT_FILES)} present; Resource Han Rounded coverage checked against ui.csv + GDScript literals")
    return failures


def script_literal_characters():
    """Non-ASCII characters that appear in GDScript string literals."""
    characters = set()
    literal = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
    for path in sorted((ROOT / "ui").rglob("*.gd")) + sorted((ROOT / "gameplay").rglob("*.gd")) + sorted((ROOT / "core").rglob("*.gd")):
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            for match in literal.finditer(line):
                characters.update(ord(character) for character in match.group(1) if ord(character) > 0x7F)
    return characters


def localization_characters(path):
    characters = set()
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.reader(handle):
            for field in row:
                characters.update(ord(character) for character in field if ord(character) >= 0x20)
    return characters


def sfnt_codepoints(path):
    payload = path.read_bytes()
    if len(payload) < 12:
        raise ValueError("truncated sfnt header")
    table_count = struct.unpack_from(">H", payload, 4)[0]
    cmap_offset = None
    for index in range(table_count):
        record = 12 + index * 16
        if record + 16 > len(payload):
            raise ValueError("truncated table directory")
        tag, _, offset, length = struct.unpack_from(">4sIII", payload, record)
        if tag == b"cmap":
            if offset + length > len(payload):
                raise ValueError("cmap exceeds file bounds")
            cmap_offset = offset
            break
    if cmap_offset is None:
        raise ValueError("font has no cmap table")
    subtable_count = struct.unpack_from(">H", payload, cmap_offset + 2)[0]
    codepoints = set()
    for index in range(subtable_count):
        record = cmap_offset + 4 + index * 8
        platform, encoding, relative_offset = struct.unpack_from(">HHI", payload, record)
        if platform != 0 and not (platform == 3 and encoding in (1, 10)):
            continue
        subtable = cmap_offset + relative_offset
        if subtable + 2 > len(payload):
            continue
        format_id = struct.unpack_from(">H", payload, subtable)[0]
        if format_id == 4:
            codepoints.update(cmap_format_4_codepoints(payload, subtable))
        elif format_id == 12:
            codepoints.update(cmap_format_12_codepoints(payload, subtable))
    if not codepoints:
        raise ValueError("font has no supported Unicode cmap")
    return codepoints


def cmap_format_4_codepoints(payload, offset):
    length = struct.unpack_from(">H", payload, offset + 2)[0]
    end = offset + length
    if end > len(payload):
        raise ValueError("truncated cmap format 4")
    segment_count = struct.unpack_from(">H", payload, offset + 6)[0] // 2
    end_codes = offset + 14
    start_codes = end_codes + segment_count * 2 + 2
    deltas = start_codes + segment_count * 2
    range_offsets = deltas + segment_count * 2
    codepoints = set()
    for index in range(segment_count):
        last = struct.unpack_from(">H", payload, end_codes + index * 2)[0]
        first = struct.unpack_from(">H", payload, start_codes + index * 2)[0]
        delta = struct.unpack_from(">h", payload, deltas + index * 2)[0]
        range_offset_address = range_offsets + index * 2
        range_offset = struct.unpack_from(">H", payload, range_offset_address)[0]
        for codepoint in range(first, last + 1):
            if codepoint == 0xFFFF:
                continue
            if range_offset == 0:
                glyph = (codepoint + delta) & 0xFFFF
            else:
                glyph_address = range_offset_address + range_offset + (codepoint - first) * 2
                if glyph_address + 2 > end:
                    continue
                glyph = struct.unpack_from(">H", payload, glyph_address)[0]
                if glyph:
                    glyph = (glyph + delta) & 0xFFFF
            if glyph:
                codepoints.add(codepoint)
    return codepoints


def cmap_format_12_codepoints(payload, offset):
    length = struct.unpack_from(">I", payload, offset + 4)[0]
    end = offset + length
    if end > len(payload):
        raise ValueError("truncated cmap format 12")
    group_count = struct.unpack_from(">I", payload, offset + 12)[0]
    codepoints = set()
    for index in range(group_count):
        first, last, first_glyph = struct.unpack_from(">III", payload, offset + 16 + index * 12)
        if first_glyph == 0:
            first += 1
        codepoints.update(range(first, last + 1))
    return codepoints


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="fail when expected files are missing")
    parser.add_argument("--audio", action="store_true", help="also require and validate audio")
    args = parser.parse_args()
    failures = validate_art(args.strict)
    failures.extend(validate_art_import_settings())
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
