#!/usr/bin/env python3
"""Fail a release candidate while required owner inputs or artifacts are missing."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS = []


def require(path):
    target = ROOT / path
    if not target.is_file():
        ERRORS.append(f"missing {path}")
    return target


def check_placeholders(path):
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    for token in ("REPLACE_WITH_", "com.example.", "to be set before release", "will be inserted after P04"):
        if token in text:
            ERRORS.append(f"{path.relative_to(ROOT)} contains release placeholder {token}")


def main():
    for path in (
        "project.godot",
        "export_presets.cfg",
        "ios/PrivacyInfo.xcprivacy",
        "docs/public/privacy.html",
        "docs/public/terms.html",
        "docs/public/support.html",
        "docs/store/metadata/en.md",
        "docs/store/metadata/zh_CN.md",
    ):
        check_placeholders(require(path))
    store = json.loads((ROOT / "data/store.json").read_text(encoding="utf-8"))["items"]
    if len(store) != 8:
        ERRORS.append("expected eight IAP products")
    if not list((ROOT / "ios/plugins").rglob("*.gdip")):
        ERRORS.append("missing enabled iOS plugin descriptors under ios/plugins (StoreKit/IAP required)")
    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    for token in ('name="iOS Release Candidate"', 'export_path="builds/ios/DataCenterTycoon.zip"', 'application/min_ios_version="15.0"', "application/targeted_device_family=2"):
        if token not in preset:
            ERRORS.append(f"iOS export preset missing {token}")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    for token in ('config/icon="res://assets/art/store/app_icon.png"', 'boot_splash/image="res://assets/art/store/splash_bg.png"'):
        if token not in project:
            ERRORS.append(f"project.godot missing release visual setting {token}")
    godot = shutil.which("godot")
    if godot is None:
        ERRORS.append("Godot is required to verify compiled translations")
    else:
        translations = subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "--script", str(ROOT / "tools/check_translations.gd")],
            cwd=ROOT,
        )
        if translations.returncode:
            ERRORS.append("compiled .translation resources do not match localization/ui.csv")
    validation = subprocess.run([sys.executable, str(ROOT / "tools/validate_data.py")], cwd=ROOT)
    if validation.returncode:
        ERRORS.append("data validation failed")
    store_assets = subprocess.run([sys.executable, str(ROOT / "tools/check_app_store_assets.py")], cwd=ROOT)
    if store_assets.returncode:
        ERRORS.append("App Store asset validation failed")
    if ERRORS:
        print("Release gate blocked:")
        for error in ERRORS:
            print("-", error)
        return 1
    print("Release configuration gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
