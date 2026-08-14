#!/usr/bin/env python3
"""Static validation for configuration, localization, and asset contracts."""

import csv
import json
import math
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
        if event.get("rare", False) and float(event.get("weight", 0)) > 2:
            ERRORS.append(f"events/{event_id}: rare event weight must be at most 2")
        multipliers = list(event.get("customer_multipliers", {}).values()) + list(event.get("purchase_multipliers", {}).values())
        if "all_customer_multiplier" in event:
            multipliers.append(event["all_customer_multiplier"])
        if any(float(multiplier) <= 0 or float(multiplier) > 6 for multiplier in multipliers):
            ERRORS.append(f"events/{event_id}: event multipliers must be within (0, 6]")
    store = DATA["store"]["items"]
    if set(store) != {"noads", "offline24", "gems_s", "gems_m", "gems_l", "pack_starter", "pack_builder", "pack_tycoon"}:
        ERRORS.append("store SKU set differs from monetization document")
    contracts = DATA["economy"].get("contracts", {})
    if "renewal_window_seconds" in contracts:
        ERRORS.append("economy/contracts: timed renewal windows are forbidden")
    for field in ("duration_seconds", "breach_fee_monthly_income_ratio", "minimum_breach_fee"):
        if float(contracts.get(field, 0)) <= 0:
            ERRORS.append(f"economy/contracts: {field} must be positive")
    if float(contracts.get("strategic_lock_cap", 0)) < 1.5:
        ERRORS.append("economy/contracts: strategic_lock_cap must be at least 1.5")
    faults = DATA["economy"].get("faults", {})
    fault_multiplier = float(faults.get("faulted_income_multiplier", 0))
    if not 0 < fault_multiplier < 1:
        ERRORS.append("economy/faults: faulted_income_multiplier must be between zero and one")
    if float(faults.get("auto_repair_seconds", 0)) <= 0:
        ERRORS.append("economy/faults: auto_repair_seconds must be positive")
    if DATA["achievements"]["items"].get("repair_ten", {}).get("metric") != "faults_repaired_manual":
        ERRORS.append("achievements/repair_ten: automatic repairs must not count toward the manual repair achievement")
    bankruptcy = DATA["economy"].get("bankruptcy", {})
    if "game_over_after_online_seconds" in bankruptcy:
        ERRORS.append("economy/bankruptcy: game-over deadlines are forbidden")
    for field, expected in (("takeover_after_online_seconds", 21600), ("takeover_value_ratio", 0.7), ("relief_cash_floor", 5000)):
        if not math.isclose(float(bankruptcy.get(field, -1)), expected):
            ERRORS.append(f"economy/bankruptcy: {field} must equal {expected}")
    aging = DATA["economy"].get("aging", {})
    if "demolition_cost_ratio" in aging:
        ERRORS.append("economy/aging: demolition penalties are forbidden")
    for field, expected in (("ruin_building_scrap_ratio", 0.05), ("ruin_attachment_scrap_ratio", 0.1), ("auto_retire_progress", 0.95)):
        if not math.isclose(float(aging.get(field, -1)), expected):
            ERRORS.append(f"economy/aging: {field} must equal {expected}")
    if float(aging.get("retirement_building_refund_ratio", 0)) <= 0:
        ERRORS.append("economy/aging: retirement building recovery must stay positive")
    if float(aging.get("attachment_refund_ratio", 0)) < float(aging.get("ruin_attachment_scrap_ratio", 0)):
        ERRORS.append("economy/aging: normal attachment recovery cannot trail ruin scrap")
    if float(aging.get("rack_refund_ratio", 0)) < 0.5:
        ERRORS.append("economy/aging: normal rack recovery cannot trail the 50% ruin scrap rule")
    layout = DATA["economy"].get("layout", {})
    if int(layout.get("set_size", 0)) != 3:
        ERRORS.append("economy/layout: set_size must remain three for the 3x3 rack board")
    if not 1.0 <= float(layout.get("set_bonus_multiplier", 0)) <= 1.25:
        ERRORS.append("economy/layout: set_bonus_multiplier must stay within 1.00–1.25")
    auto_retirement = DATA["technology"].get("upgrades", {}).get("auto_retirement", {}).get("levels", {}).get("1", {})
    if float(auto_retirement.get("cost", 0)) != 15000 or int(auto_retirement.get("unlock_era", 0)) != 2:
        ERRORS.append("technology/auto_retirement: expected one Era 2 level costing 15000")
    campuses = DATA["economy"].get("campuses", {})
    campus_types = campuses.get("types", {})
    campus_sequence = campuses.get("sequence", [])
    if campus_sequence != ["type_1", "type_2"] or not campuses.get("repeat_last", False):
        ERRORS.append("economy/campuses: expected type_1 → type_2 with repeat_last for unlimited expansion")
    expected_campuses = {"type_1": (6, 1.0), "type_2": (8, 1.08)}
    for type_id in campus_sequence:
        definition = campus_types.get(type_id, {})
        capacity = int(definition.get("capacity", 0))
        premium = float(definition.get("land_price_multiplier", 0))
        if capacity < 4 or capacity > 10 or capacity % 2 != 0:
            ERRORS.append(f"economy/campuses/{type_id}: capacity must be an even 4–10 slots")
        if premium < 1.0 or premium > 1.15:
            ERRORS.append(f"economy/campuses/{type_id}: land premium must stay within 0–15%")
        expected_capacity, expected_premium = expected_campuses[type_id]
        if capacity != expected_capacity or not math.isclose(premium, expected_premium):
            ERRORS.append(f"economy/campuses/{type_id}: expected {expected_capacity} slots at {expected_premium:.2f}×")
    land = DATA["economy"].get("land", {})
    if "growth_factor" in land:
        ERRORS.append("economy/land: unbounded geometric growth_factor is forbidden for a hundred-center park")
    if not math.isclose(float(land.get("growth_step", 0)), 0.55) or not math.isclose(float(land.get("growth_exponent", 0)), 1.5):
        ERRORS.append("economy/land: expected the bounded 0.55-step / 1.50-exponent power curve")
    meta = DATA.get("meta_progression", {})
    durations = meta.get("contract_durations", {})
    if set(durations) != {"flexible", "standard", "strategic"}:
        ERRORS.append("meta_progression/contract_durations: expected flexible, standard, and strategic")
    expected_terms = {"flexible": (3, 0.97), "standard": (6, 1.0), "strategic": (12, 1.04)}
    for duration_id, (months, multiplier) in expected_terms.items():
        item = durations.get(duration_id, {})
        if int(item.get("months", 0)) != months or not math.isclose(float(item.get("income_multiplier", 0)), multiplier):
            ERRORS.append(f"meta_progression/contract_durations/{duration_id}: expected {months} months at {multiplier:.2f}x")
    relationship_levels = meta.get("relationships", {}).get("levels", [])
    if len(relationship_levels) != 4 or any(float(level.get("income_multiplier", 0)) < 1.0 for level in relationship_levels):
        ERRORS.append("meta_progression/relationships: expected four non-punitive relationship levels")
    specialties = meta.get("campus_specializations", {})
    if set(specialties) != {"hosting", "cloud", "ai_compute", "diversified"}:
        ERRORS.append("meta_progression/campus_specializations: expected four defined campus strategies")
    if any(not 1.0 <= float(item.get("income_multiplier", 0)) <= 1.08 for item in specialties.values()):
        ERRORS.append("meta_progression/campus_specializations: multipliers must remain in the 1.00–1.08 comfort band")
    board = meta.get("board_specialties", {})
    if int(board.get("max_rank", 0)) != 5 or set(board.get("items", {})) != {"construction", "operations", "business"}:
        ERRORS.append("meta_progression/board_specialties: expected three five-rank permanent specialties")


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
    for upgrade_id, upgrade in DATA["technology"]["upgrades"].items():
        for field in ("name_key", "description_key"):
            if upgrade.get(field) not in keys:
                ERRORS.append(f"technology/{upgrade_id}: localization key {upgrade.get(field)} missing")
    for type_id, definition in DATA["economy"].get("campuses", {}).get("types", {}).items():
        if definition.get("name_key") not in keys:
            ERRORS.append(f"economy/campuses/{type_id}: localization key {definition.get('name_key')} missing")
    meta = DATA.get("meta_progression", {})
    for item_id, item in meta.get("roadmap", {}).get("items", {}).items():
        for field in ("name_key", "description_key"):
            if item.get(field) not in keys:
                ERRORS.append(f"meta_progression/roadmap/{item_id}: localization key {item.get(field)} missing")
    for item_id, item in meta.get("campus_specializations", {}).items():
        for field in ("name_key", "description_key"):
            if item.get(field) not in keys:
                ERRORS.append(f"meta_progression/campus_specializations/{item_id}: localization key {item.get(field)} missing")
    for item_id, item in meta.get("contract_durations", {}).items():
        for field in ("name_key", "description_key"):
            if item.get(field) not in keys:
                ERRORS.append(f"meta_progression/contract_durations/{item_id}: localization key {item.get(field)} missing")
    for level in meta.get("relationships", {}).get("levels", []):
        if level.get("name_key") not in keys:
            ERRORS.append(f"meta_progression/relationships: localization key {level.get('name_key')} missing")
    for item_id, item in meta.get("board_specialties", {}).get("items", {}).items():
        for field in ("name_key", "description_key"):
            if item.get(field) not in keys:
                ERRORS.append(f"meta_progression/board_specialties/{item_id}: localization key {item.get(field)} missing")
    for group_id, group in meta.get("collection", {}).get("groups", {}).items():
        if group.get("name_key") not in keys:
            ERRORS.append(f"meta_progression/collection/{group_id}: localization key {group.get('name_key')} missing")


def validate_manifest():
    global ART_IDS
    manifest = json.loads((ROOT / "assets/art/manifest.json").read_text(encoding="utf-8"))
    ids = [asset_id for group in manifest["groups"] for asset_id in group["ids"]]
    ART_IDS = set(ids) | set(manifest.get("items", {}))
    if len(ids) != 159:
        ERRORS.append(f"art manifest has {len(ids)} IDs, expected 159")
    if len(ids) != len(set(ids)):
        ERRORS.append("art manifest contains duplicate IDs")


def validate_asset_references():
    expected = {
        "ground_tile", "ground_tile_grass", "ground_path_straight", "ground_path_cross",
        "prop_flagpole", "prop_lamp", "prop_bush_row", "prop_parking", "prop_transformer_yard", "world_edge_fog",
        "plot_forsale", "plot_owned", "plot_pad_std", "plot_pad_large", "plot_pad_sale",
        "road_iso_a", "road_iso_b", "road_iso_cross", "dc_interior_bg", "slot_empty", "slot_locked",
        "ic_operations", "ic_pointer_hand", "ic_server",
        "guide_normal", "guide_happy", "guide_worried", "guide_alert", "guide_thinking",
        "company_roadmap", "campus_strategy", "customer_portfolio", "market_review",
        "board_specialties", "company_collection", "legacy_memorial",
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
    if len(cues) != 23:
        ERRORS.append(f"audio manifest has {len(cues)} cues, expected 23")
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
    print(f"Validated {len(DATA)} data tables, localization, and {len(ART_IDS)} art IDs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
