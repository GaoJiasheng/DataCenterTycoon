#!/usr/bin/env python3
"""Build static packaged Resource Han Rounded CN OTF UI subsets.

The full upstream variable master is a build input, not a runtime asset. The
script first subsets its glyph repertoire, then pins Medium/Bold/Heavy at full
rounding and downgrades CFF2 to three deterministic static CFF OTF files.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import shutil
import string
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCALIZATION = ROOT / "localization/ui.csv"
DEFAULT_OUTPUT = ROOT / "assets/fonts"
UPSTREAM_URL = (
    "https://github.com/CyanoHao/Resource-Han-Rounded/releases/download/"
    "v1.910/RHR-CFF2-CN-1.910.7z"
)
UPSTREAM_ARCHIVE_SHA256 = "4ad7b141535a1f11831287b0a6f71ddcec8daa92dc1d82c59892068f8ae5df09"
SOURCE_FILENAME = "ResourceHanRoundedCN-VF.otf"
SOURCE_SHA256 = "ee3f276c9f9ee77c726d4e9c88350a3de73fb297633c54d510971ee636dceb1e"
COMMON_HAN_BUFFER_SIZE = 3500
FONT_SPECS = {
    "Medium": {
        "filename": "ResourceHanRoundedCN-Medium.otf",
        "weight": 500,
    },
    "Bold": {
        "filename": "ResourceHanRoundedCN-Bold.otf",
        "weight": 700,
    },
    "Heavy": {
        "filename": "ResourceHanRoundedCN-Heavy.otf",
        "weight": 900,
    },
}


def localization_characters(path: Path) -> set[str]:
    characters: set[str] = set()
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.reader(handle):
            for field in row:
                characters.update(field)
    return characters


def common_han_characters(limit: int = COMMON_HAN_BUFFER_SIZE) -> list[str]:
    """Return the first-level GB2312 common-Han repertoire in code order."""

    characters: list[str] = []
    for lead in range(0xB0, 0xD8):
        for trail in range(0xA1, 0xFF):
            try:
                character = bytes((lead, trail)).decode("gb2312")
            except UnicodeDecodeError:
                continue
            if len(character) == 1 and "\u4e00" <= character <= "\u9fff":
                characters.append(character)
                if len(characters) == limit:
                    return characters
    raise RuntimeError(f"GB2312 yielded only {len(characters)} common Han characters")


def build_character_set(localization: Path) -> str:
    characters = localization_characters(localization)
    characters.update(chr(codepoint) for codepoint in range(0x20, 0x7F))
    characters.update(string.digits)
    characters.update(common_han_characters())
    # Stable extras used by formatted runtime values even when a translation
    # happens not to exercise them yet.
    characters.update(" ¥￥€£¢°℃‰±×÷·•…—–→←↑↓✓稳障购罄")
    characters.discard("\r")
    characters.discard("\n")
    characters.discard("\t")
    return "".join(sorted(characters, key=ord))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def subset_variable_font(executable: str, source: Path, output: Path, text_file: Path) -> None:
    command = [
        executable,
        str(source),
        f"--output-file={output}",
        f"--text-file={text_file}",
        "--layout-features=",
        "--glyph-names",
        "--symbol-cmap",
        "--legacy-cmap",
        "--notdef-glyph",
        "--notdef-outline",
        "--recommended-glyphs",
        "--name-IDs=*",
        "--name-languages=*",
        "--name-legacy",
        # The UI fallback renders horizontal CJK text only. Dropping the source's
        # variable GPOS/GSUB/GDEF tables avoids a known inconsistent-glyph-order
        # failure during static CFF2 instancing and removes unused vertical data.
        "--drop-tables+=DSIG,GPOS,GSUB,GDEF",
    ]
    subprocess.run(command, check=True)


def instantiate_font(executable: str, source: Path, output: Path, weight: int) -> None:
    command = [
        executable,
        "varLib.instancer",
        str(source),
        f"wght={weight}",
        "ROND=100",
        "--static",
        "--downgrade-cff2",
        "--update-name-table",
        "--no-recalc-timestamp",
        "--output",
        str(output),
    ]
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Subset Resource Han Rounded CN for the localized game UI",
        epilog=f"Official source: {UPSTREAM_URL}",
    )
    parser.add_argument("--source", type=Path, required=True, help=f"extracted upstream {SOURCE_FILENAME}")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--localization", type=Path, default=DEFAULT_LOCALIZATION)
    parser.add_argument("--pyftsubset", default="pyftsubset", help="pyftsubset executable name or absolute path")
    parser.add_argument("--fonttools", default="fonttools", help="fonttools executable name or absolute path")
    parser.add_argument("--skip-source-hash", action="store_true", help="allow a different upstream build")
    args = parser.parse_args()

    executable = shutil.which(args.pyftsubset) if not Path(args.pyftsubset).is_file() else str(Path(args.pyftsubset).resolve())
    fonttools_executable = shutil.which(args.fonttools) if not Path(args.fonttools).is_file() else str(Path(args.fonttools).resolve())
    if executable is None:
        parser.error("pyftsubset was not found; install FontTools with `python3 -m pip install fonttools`")
    if fonttools_executable is None:
        parser.error("fonttools was not found; install FontTools with `python3 -m pip install fonttools`")
    if not args.localization.is_file():
        parser.error(f"localization CSV does not exist: {args.localization}")

    if not args.source.is_file():
        parser.error(f"missing {args.source}; extract {SOURCE_FILENAME} from {UPSTREAM_URL}")
    if not args.skip_source_hash and sha256(args.source) != SOURCE_SHA256:
        parser.error(f"{args.source.name} does not match the audited v1.910 CN OTF master")

    characters = build_character_set(args.localization)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="dct-font-subset-") as temporary_directory:
        temporary_root = Path(temporary_directory)
        character_file = temporary_root / "characters.txt"
        variable_subset = temporary_root / "ResourceHanRoundedCN-SubsetVF.otf"
        character_file.write_text(characters, encoding="utf-8")
        subset_variable_font(executable, args.source, variable_subset, character_file)
        for weight_name, spec in FONT_SPECS.items():
            output = args.output_dir / spec["filename"]
            instantiate_font(fonttools_executable, variable_subset, output, int(spec["weight"]))
            print(f"{weight_name}: {args.source.stat().st_size:,} -> {output.stat().st_size:,} bytes")
    print(f"Subset repertoire: {len(characters):,} Unicode characters (including {COMMON_HAN_BUFFER_SIZE:,} common Han buffer glyphs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
