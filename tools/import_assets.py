#!/usr/bin/env python3
"""Copy approved final assets into runtime directories using the manifests."""

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def copy_jobs(jobs, dry_run):
    copied = 0
    missing = []
    for asset_id, source, target in jobs:
        if source is None:
            missing.append(asset_id)
            continue
        print(f"{source.relative_to(ROOT)} -> {target.relative_to(ROOT)}")
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        copied += 1
    return copied, missing


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
    if args.visual:
        copied, missing = copy_jobs(visual_jobs(), args.dry_run)
        total_copied += copied
        all_missing.extend(missing)
        if not args.dry_run and (ROOT / "assets/art/store/splash_bg.png").is_file():
            enable_runtime_splash()
    if args.audio:
        copied, missing = copy_jobs(audio_jobs(), args.dry_run)
        total_copied += copied
        all_missing.extend(missing)
    print(f"Copied {total_copied}; missing {len(all_missing)}")
    if all_missing:
        print("Not yet delivered:", ", ".join(all_missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
