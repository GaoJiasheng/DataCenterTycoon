#!/usr/bin/env python3
"""Static validation for configuration, localization, and asset contracts."""

import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = {}
ERRORS = []
ART_IDS = set()


def load_data():
    for path in sorted((ROOT / "data").glob("*.json")):
        try:
            DATA[path.stem] = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            ERRORS.append(f"{path.name}: {error}")


def validate_references():
    eras = DATA["eras"]["items"]
    for table in ("buildings", "racks", "attachments"):
        for item_id, item in DATA[table]["items"].items():
            if str(item.get("unlock_era", 1)) not in eras:
                ERRORS.append(f"{table}/{item_id}: missing unlock era")
    customers = DATA["customers"]["items"]
    for event_id, event in DATA["events"]["items"].items():
        for customer_id in event.get("customer_multipliers", {}):
            if customer_id not in customers:
                ERRORS.append(f"events/{event_id}: missing customer {customer_id}")
    store = DATA["store"]["items"]
    if set(store) != {"noads", "offline24", "gems_s", "gems_m", "gems_l", "pack_starter", "pack_builder", "pack_tycoon"}:
        ERRORS.append("store SKU set differs from monetization document")


def validate_localization():
    with (ROOT / "localization/ui.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    keys = {row["keys"] for row in rows}
    if len(keys) != len(rows):
        ERRORS.append("localization contains duplicate keys")
    for table_name, key_fields in {
        "buildings": ("name_key",), "racks": ("name_key",), "attachments": ("name_key",),
        "customers": ("name_key",), "events": ("name_key", "description_key"), "eras": ("name_key",),
        "achievements": ("name_key",), "store": ("name_key", "description_key"),
    }.items():
        for item_id, item in DATA[table_name]["items"].items():
            for field in key_fields:
                if field in item and item[field] not in keys:
                    ERRORS.append(f"{table_name}/{item_id}: localization key {item[field]} missing")
    for index, step in enumerate(DATA["tutorial"]["steps"]):
        if step.get("message_key") not in keys:
            ERRORS.append(f"tutorial/{index}: localization key {step.get('message_key')} missing")
    for level_id, level in DATA["technology"]["network"].items():
        if level.get("name_key") not in keys:
            ERRORS.append(f"technology/network/{level_id}: localization key missing")
    repair = DATA["technology"]["upgrades"]["repair_team"]
    for field in ("name_key", "description_key"):
        if repair.get(field) not in keys:
            ERRORS.append(f"technology/repair_team: localization key {repair.get(field)} missing")


def validate_manifest():
    global ART_IDS
    manifest = json.loads((ROOT / "assets/art/manifest.json").read_text(encoding="utf-8"))
    ids = [asset_id for group in manifest["groups"] for asset_id in group["ids"]]
    ART_IDS = set(ids) | set(manifest.get("items", {}))
    if len(ids) != 146:
        ERRORS.append(f"art manifest has {len(ids)} IDs, expected 146")
    if len(ids) != len(set(ids)):
        ERRORS.append("art manifest contains duplicate IDs")


def validate_asset_references():
    expected = {
        "ground_tile", "ground_tile_grass", "ground_path_straight", "ground_path_cross",
        "prop_flagpole", "prop_lamp", "prop_bush_row", "prop_parking", "prop_transformer_yard", "world_edge_fog",
        "plot_forsale", "plot_owned", "dc_interior_bg", "slot_empty", "slot_locked",
        "ic_operations", "ic_pointer_hand", "ic_server",
        "guide_normal", "guide_happy", "guide_worried", "guide_alert", "guide_thinking",
    }
    for item in DATA["buildings"]["items"].values():
        expected.update(item["asset_prefix"] + suffix for suffix in ("_construction", "_active", "_dark", "_aged", "_decayed", "_ruin"))
    for item in DATA["racks"]["items"].values():
        expected.update(item["asset_prefix"] + suffix for suffix in ("_active", "_dark", "_fault", "_installing"))
    for item in DATA["attachments"]["items"].values():
        expected.update(item["asset_prefix"] + suffix for suffix in ("_active", "_idle"))
    for table in ("customers", "eras", "store"):
        expected.update(item["asset_id"] for item in DATA[table]["items"].values())
    for asset_id in sorted(expected - ART_IDS):
        ERRORS.append(f"runtime art reference missing from manifest: {asset_id}")


def validate_audio_manifest():
    manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8"))
    cues = set(manifest.get("items", {}))
    if len(cues) != 16:
        ERRORS.append(f"audio manifest has {len(cues)} cues, expected 16")
    pattern = re.compile(r'AudioService\.play_(?:music|sfx)\("([^"]+)"')
    referenced = set()
    for path in ROOT.rglob("*.gd"):
        referenced.update(pattern.findall(path.read_text(encoding="utf-8")))
    for cue_id in sorted(referenced - cues):
        ERRORS.append(f"runtime audio reference missing from manifest: {cue_id}")


def main():
    load_data()
    if not ERRORS:
        validate_references()
        validate_localization()
        validate_manifest()
        validate_asset_references()
        validate_audio_manifest()
    if ERRORS:
        for error in ERRORS:
            print("ERROR:", error)
        return 1
    print(f"Validated {len(DATA)} data tables, localization, and 146 art IDs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
