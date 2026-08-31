#!/usr/bin/env python3
"""Fail a release candidate while required owner inputs or artifacts are missing."""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fill_release_identity import IDENTITY_PATH, RUNTIME_LEGAL_TARGETS, TARGETS, load_identity, rendered_outputs

ROOT = Path(__file__).resolve().parents[1]
ERRORS = []
SOURCE_LITERAL_ROOTS = ("ui", "core", "gameplay", "data", "localization")
EMAIL_LITERAL = re.compile(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", re.IGNORECASE)
DOMAIN_LITERAL = re.compile(r"(?<![A-Z0-9_.-])(?:[A-Z0-9-]+\.)+(?:COM|ORG|NET|APP|IO|DEV|CN|CO|ME)(?![A-Z0-9_.-])", re.IGNORECASE)
ALLOWED_DOMAINS = ("apple.com", "godotengine.org", "example.com")


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


def check_release_identity():
    identity_path = require(IDENTITY_PATH.relative_to(ROOT))
    for template_name, output_name in TARGETS.items():
        require(template_name)
        require(output_name)
    if not identity_path.is_file():
        return
    try:
        identity = load_identity(identity_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        ERRORS.append(f"data/release_identity.json is invalid: {error}")
        return
    for field, value in identity.items():
        values = value if isinstance(value, list) else [value]
        if any("REPLACE_WITH_" in str(item) for item in values):
            ERRORS.append(f"data/release_identity.json field {field} still needs the owner-provided value")
    try:
        expected_outputs = rendered_outputs(identity)
    except (OSError, ValueError) as error:
        ERRORS.append(f"release identity templates cannot render: {error}")
        return
    for output, expected in expected_outputs.items():
        if output.is_file() and output.read_text(encoding="utf-8") != expected:
            ERRORS.append(f"{output.relative_to(ROOT)} differs from its release identity template; run python3 tools/fill_release_identity.py")


def check_source_literals():
    for root_name in SOURCE_LITERAL_ROOTS:
        root = ROOT / root_name
        paths = [root / "ui.csv"] if root_name == "localization" else sorted(root.rglob("*.gd")) + sorted(root.rglob("*.json"))
        for path in paths:
            if not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for match in list(EMAIL_LITERAL.finditer(text)) + list(DOMAIN_LITERAL.finditer(text)):
                literal = match.group(0)
                lowered = literal.lower()
                if "replace_with_" in lowered or any(lowered == domain or lowered.endswith("." + domain) for domain in ALLOWED_DOMAINS):
                    continue
                ERRORS.append(f"{path.relative_to(ROOT)} contains unapproved contact/domain literal {literal}")


def check_packaged_legal(godot):
    with tempfile.TemporaryDirectory(prefix="dct_release_legal_") as temp_dir:
        pack_path = Path(temp_dir) / "release_legal.pck"
        export = subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "--export-pack", "iOS Release Candidate", str(pack_path)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if export.returncode or not pack_path.is_file():
            ERRORS.append("cannot export a release pack to verify bundled legal text")
            return
        payload = pack_path.read_bytes()
        expected_outputs = rendered_outputs()
        for output_name in RUNTIME_LEGAL_TARGETS.values():
            output = ROOT / output_name
            expected = expected_outputs.get(output, "")
            marker = next((line for line in expected.splitlines() if len(line.encode("utf-8")) >= 24), "")
            if not marker or marker.encode("utf-8") not in payload:
                ERRORS.append(f"release pck does not contain readable legal body {output_name}")


def metadata_section(text, heading):
    match = re.search(rf"^## {re.escape(heading)}\s*$\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    return match.group(1).strip() if match else ""


def check_metadata_contract(path, labels):
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    subtitle_match = re.search(rf"^- {re.escape(labels['subtitle'])}[:：]\s*`([^`]*)`", text, re.MULTILINE)
    keywords_match = re.search(rf"^- {re.escape(labels['keywords'])}[:：]\s*`([^`]*)`", text, re.MULTILINE)
    promotional = metadata_section(text, labels["promotional"])
    description = metadata_section(text, labels["description"])
    for field, value, limit in (
        ("subtitle", subtitle_match.group(1) if subtitle_match else "", 30),
        ("keywords", keywords_match.group(1) if keywords_match else "", 100),
        ("promotional text", promotional, 170),
        ("description", description, 4000),
    ):
        if not value:
            ERRORS.append(f"{path.relative_to(ROOT)} is missing {field}")
        elif len(value) > limit:
            ERRORS.append(f"{path.relative_to(ROOT)} {field} is {len(value)} characters; App Store limit is {limit}")
    for heading in (labels["whats_new"], labels["review"], labels["age"]):
        if not metadata_section(text, heading):
            ERRORS.append(f"{path.relative_to(ROOT)} is missing section {heading}")


def main():
    check_release_identity()
    check_source_literals()
    check_metadata_contract(
        ROOT / "docs/store/metadata/en.md",
        {"subtitle": "Subtitle", "keywords": "Keywords", "promotional": "Promotional Text", "description": "Description", "whats_new": "What's New", "review": "App Review Notes", "age": "Age Rating Draft — Owner Confirmation Required"},
    )
    check_metadata_contract(
        ROOT / "docs/store/metadata/zh_CN.md",
        {"subtitle": "副标题", "keywords": "关键词", "promotional": "推广文本", "description": "完整描述", "whats_new": "更新说明", "review": "审核备注", "age": "年龄分级答案草稿——待所有者确认"},
    )
    for path in (
        "project.godot",
        "export_presets.cfg",
        "ios/PrivacyInfo.xcprivacy",
    ):
        check_placeholders(require(path))
    store = json.loads((ROOT / "data/store.json").read_text(encoding="utf-8"))["items"]
    if len(store) != 8:
        ERRORS.append("expected eight IAP products")
    if not list((ROOT / "ios/plugins").rglob("*.gdip")):
        ERRORS.append("missing enabled iOS plugin descriptors under ios/plugins (StoreKit/IAP required)")
    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    for token in ('name="iOS Release Candidate"', 'export_path="builds/ios/DataCenterTycoon.zip"', 'application/min_ios_version="15.0"', "application/targeted_device_family=0"):
        if token not in preset:
            ERRORS.append(f"iOS export preset missing {token}")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    for token in ('config/icon="res://assets/art/store/app_icon_desktop.png"', 'boot_splash/image="res://assets/art/store/splash_bg.png"'):
        if token not in project:
            ERRORS.append(f"project.godot missing release visual setting {token}")
    for token in ('icons/icon_1024x1024="res://assets/art/store/app_icon.png"',):
        if token not in preset:
            ERRORS.append(f"iOS export preset missing opaque App Store icon setting {token}")
    godot = shutil.which("godot")
    if godot is None:
        ERRORS.append("Godot is required to verify compiled translations")
    else:
        translations = subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "--log-file", str(Path(tempfile.gettempdir()) / "dct_check_release_translations.log"), "--script", str(ROOT / "tools/check_translations.gd")],
            cwd=ROOT,
        )
        if translations.returncode:
            ERRORS.append("compiled .translation resources do not match localization/ui.csv")
        check_packaged_legal(godot)
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
