#!/usr/bin/env python3
"""Copy approved final assets into runtime directories using the manifests."""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Runtime texture policy.  Keep this classification here because this script is
# the single entry point for production art.  check_assets.py imports the same
# function, so a copied asset cannot silently fall back to Godot's defaults.
VISUAL_IMPORT_PROFILES = {
    "lossless_ui": {
        "directories": frozenset({"ui", "customers"}),
        "compress_mode": 0,
        "mipmaps": False,
    },
    "vram_scene": {
        "directories": frozenset({
            "attachments",
            "buildings",
            "cats",
            "characters",
            "fx",
            "map",
            "meta",
            "personas",
            "racks",
            "store",
        }),
        "compress_mode": 2,
        "mipmaps": True,
    },
}


def visual_import_profile(target):
    """Return the authored Godot texture profile for a runtime art target."""
    directory = target.parent.name
    matches = [
        (profile_name, profile)
        for profile_name, profile in VISUAL_IMPORT_PROFILES.items()
        if directory in profile["directories"]
    ]
    if len(matches) != 1:
        raise RuntimeError(f"visual import profile is ambiguous or missing for {target}")
    return matches[0]


def configure_visual_import(target):
    """Update a tracked Godot .import sidecar without replacing its UID/path."""
    profile_name, profile = visual_import_profile(target)
    sidecar = target.with_suffix(target.suffix + ".import")
    if not sidecar.is_file():
        raise RuntimeError(
            f"missing {sidecar.relative_to(ROOT)}; import once in Godot, then rerun this script"
        )
    text = sidecar.read_text(encoding="utf-8")
    replacements = {
        r"(?m)^compress/mode=\d+$": f'compress/mode={profile["compress_mode"]}',
        r"(?m)^mipmaps/generate=(?:true|false)$": (
            "mipmaps/generate=true" if profile["mipmaps"] else "mipmaps/generate=false"
        ),
    }
    for pattern, replacement in replacements.items():
        text, count = re.subn(pattern, replacement, text, count=1)
        if count != 1:
            raise RuntimeError(f"malformed texture import setting in {sidecar.relative_to(ROOT)}")
    sidecar.write_text(text, encoding="utf-8")
    return profile_name


def enable_runtime_splash():
    project = ROOT / "project.godot"
    text = project.read_text(encoding="utf-8")
    current = 'boot_splash/image=""'
    final = 'boot_splash/image="res://assets/art/store/splash_bg.png"'
    if final not in text:
        if current not in text:
            raise RuntimeError("project.godot boot splash setting is missing")
        project.write_text(text.replace(current, final, 1), encoding="utf-8")


def unique_source(source_root, filename):
    matches = list(source_root.rglob(filename))
    if len(matches) > 1:
        raise RuntimeError(f"multiple final files named {filename}: {matches}")
    return matches[0] if matches else None


def visual_jobs():
    manifest = json.loads((ROOT / "assets/art/manifest.json").read_text(encoding="utf-8"))
    source_root = ROOT / manifest["source_delivery_root"]
    for group in manifest.get("groups", []):
        for asset_id in group["ids"]:
            source = unique_source(source_root, f"{asset_id}.png")
            yield asset_id, source, ROOT / "assets/art" / group["directory"] / f"{asset_id}.png"


def audio_jobs():
    manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8"))
    source_root = ROOT / manifest["source_delivery_root"]
    for cue_id, spec in manifest["items"].items():
        target = ROOT / spec["path"].replace("res://", "")
        source = unique_source(source_root, target.name)
        yield cue_id, source, target


def copy_jobs(jobs, dry_run, configure_visual=False):
    copied = 0
    missing = []
    profile_counts = {}
    for asset_id, source, target in jobs:
        if source is None:
            missing.append(asset_id)
            continue
        print(f"{source.relative_to(ROOT)} -> {target.relative_to(ROOT)}")
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            if configure_visual:
                profile_name = configure_visual_import(target)
                profile_counts[profile_name] = profile_counts.get(profile_name, 0) + 1
        copied += 1
    return copied, missing, profile_counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--audio", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.visual and not args.audio:
        parser.error("select --visual and/or --audio")
    total_copied = 0
    all_missing = []
    all_profiles = {}
    if args.visual:
        copied, missing, profiles = copy_jobs(visual_jobs(), args.dry_run, configure_visual=True)
        total_copied += copied
        all_missing.extend(missing)
        all_profiles.update(profiles)
        if not args.dry_run and (ROOT / "assets/art/store/splash_bg.png").is_file():
            enable_runtime_splash()
    if args.audio:
        copied, missing, _profiles = copy_jobs(audio_jobs(), args.dry_run)
        total_copied += copied
        all_missing.extend(missing)
    print(f"Copied {total_copied}; missing {len(all_missing)}")
    if all_profiles:
        print("Visual import profiles: " + ", ".join(
            f"{profile}={count}" for profile, count in sorted(all_profiles.items())
        ))
    if all_missing:
        print("Not yet delivered:", ", ".join(all_missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
