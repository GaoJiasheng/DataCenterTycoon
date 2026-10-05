#!/usr/bin/env python3
"""Generate release-hardening balance reports without changing production data."""

import csv
import json
import sys
from collections import defaultdict

import simulate_economy as balance


SEED = 20260802
SEED_COUNT = 20
STRATEGIES = ("idle", "active", "aggressive")
ACHIEVEMENTS = balance.load("achievements")["items"]


class AuditSimulator(balance.Simulator):
    """Read-only instrumentation for source/sink reporting."""

    def __init__(self, strategy, seed):
        self.metric_eras = {}
        self.metric_counts = defaultdict(int)
        self.rare_locks = set()
        self.completed_centers = []
        self.completed_center_timeline = []
        self.completions_by_day = defaultdict(int)
        self.earned_roadmap_days = {}
        self.earned_achievement_days = {}
        self.progress_receipts = []
        self.discovered = {"buildings": {}, "racks": {}, "attachments": {}, "customers": {}, "events": {}}
        self.first_inquiry_era = 0
        self.manual_repairs_by_era = defaultdict(int)
        self.retirements_by_era = defaultdict(int)
        super().__init__(strategy, seed)

    def _discover(self, source, item_id):
        if item_id and item_id not in self.discovered[source]:
            self.discovered[source][item_id] = self.era

    def update_market(self):
        super().update_market()
        for event_id, _end in self.events:
            self._discover("events", event_id)

    def sign_customer(self, dc, customer, duration_id="standard", premium=1.0, force=False):
        changed = dc.customer != customer or force
        free_switch = dc.free_switch_available and bool(dc.customer)
        super().sign_customer(dc, customer, duration_id, premium, force)
        self._discover("customers", customer)
        if changed:
            self.metric_counts["contracts_signed"] += 1
            self.metric_counts["strategic_contracts_signed"] += dc.contract_duration_id == "strategic"
            self.metric_counts["free_switches_used"] += free_switch
            rare = [event_id for event_id, end in self.events if end > balance.Simulator.now and balance.EVENTS[event_id].get("rare")]
            self.metric_counts["rare_events_locked"] += bool(rare)
            self.rare_locks.update(rare)
            self.observe_progress()

    def sign_inquiry(self, dc, template):
        super().sign_inquiry(dc, template)
        if self.first_inquiry_era == 0:
            self.first_inquiry_era = self.era

    def try_expand(self):
        before = self.total_built
        expanded = super().try_expand()
        if not expanded or self.total_built == before:
            return expanded
        dc = self.dcs[-1]
        self._discover("buildings", dc.building_id)
        for rack_id in dc.racks:
            self._discover("racks", rack_id)
        _racks, power_id, cooler_ids = balance.LOADOUTS[dc.building_id]
        self._discover("attachments", power_id)
        for cooler_id in cooler_ids:
            self._discover("attachments", cooler_id)
        return expanded

    def player_session(self):
        before = {id(dc): set(dc.faulted) for dc in self.dcs}
        super().player_session()
        repaired = sum(len(before.get(id(dc), set()) - set(dc.faulted)) for dc in self.dcs)
        self.manual_repairs_by_era[self.era] += repaired
        self.observe_progress()

    def process_auto_retirements(self):
        before = len(self.dcs)
        super().process_auto_retirements()
        self.retirements_by_era[self.era] += max(0, before - len(self.dcs))

    def retire_old(self):
        before = len(self.dcs)
        super().retire_old()
        self.retirements_by_era[self.era] += max(0, before - len(self.dcs))


    def observe_progress(self):
        for dc in self.dcs:
            if not dc.ready:
                continue
            if not any(previous is dc for previous in self.completed_centers):
                self.completed_centers.append(dc)
                self.completed_center_timeline.append({"at": balance.Simulator.now, "building_id": dc.building_id})
                if dc.building_id in ("dc_t2", "dc_t3"):
                    self.metric_counts["datacenters_built_t" + dc.building_id[-1]] += 1
                day = int(dc.built_at // balance.STEP)
                self.completions_by_day[day] += 1
                self.metric_counts["max_datacenters_built_in_one_day"] = max(self.metric_counts["max_datacenters_built_in_one_day"], self.completions_by_day[day])
                self.metric_counts["liquid_cooling_installed"] += sum(cooler.startswith("cool_liquid_") for cooler in balance.LOADOUTS[dc.building_id][2])
            lines = ((0,1,2),(3,4,5),(6,7,8),(0,3,6),(1,4,7),(2,5,8))
            groups = sum(all(slot < len(dc.racks) and dc.racks[slot] for slot in line) and len({balance.RACKS[dc.racks[slot]]["kind"] for slot in line}) == 1 for line in lines)
            self.metric_counts["max_set_groups_in_one_datacenter"] = max(self.metric_counts["max_set_groups_in_one_datacenter"], groups)
        self.metric_counts["distinct_rare_events_locked"] = len(self.rare_locks)
        self.metric_counts["all_customers_familiar"] = int(all(self.relationship_level(customer) >= 1 for customer in balance.CUSTOMERS))
        self.metric_counts["total_datacenters_built"] = len(self.completed_centers)
        self.metric_counts["era"] = self.era
        self.metric_counts["network_level"] = self.network
        self.metric_counts["inquiries_accepted"] = self.inquiries_accepted
        self.metric_counts["unique_customers_served"] = len(self.discovered["customers"])
        self.metric_counts["faults_repaired_manual"] = sum(self.manual_repairs_by_era.values())
        self.metric_counts["datacenters_retired"] = sum(self.retirements_by_era.values())
        for source, table in ((self.earned_roadmap_days, balance.META["roadmap"]["items"]), (self.earned_achievement_days, ACHIEVEMENTS)):
            for item_id, item in table.items():
                if item_id not in source and self.metric_counts[item["metric"]] >= item["target"]:
                    source[item_id] = balance.Simulator.now / balance.DAY
                    self.metric_eras[item_id] = self.era
                    self.progress_receipts.append({"category": "roadmap" if source is self.earned_roadmap_days else "achievement", "id": item_id, "day": balance.Simulator.now / balance.DAY, "metrics": dict(self.metric_counts)})


def milestone_era(sim, field_index, target):
    for point in sim.curve:
        if point[field_index] >= target:
            return int(point[4])
    return 0


def add_reward(rows, era, column, reward):
    if era in (1, 2, 3) and reward:
        rows[era][column] += reward


def collection_completion_era(sim, group_id):
    group = balance.META["collection"]["groups"][group_id]
    eras = []
    for source in group.get("sources", []):
        expected = set(balance.load(source)["items"])
        observed = sim.discovered[source]
        if not expected.issubset(observed):
            return 0
        eras.extend(observed[item_id] for item_id in expected)
    # The report-only simulator has no cat interactions or cross-run legacy,
    # so authored item lists cannot complete during a fresh 30-day company.
    if group.get("items"):
        return 0
    return max(eras, default=0)


def diamond_rows(sim):
    rows = {era: defaultdict(float) for era in (1, 2, 3)}
    achievements = balance.load("achievements")["items"]
    roadmap = balance.META["roadmap"]["items"]

    # Automatic era rewards.
    for era in (2, 3):
        if sim.era >= era:
            add_reward(rows, era, "era_auto", balance.ERAS[str(era)]["reward_gems"])

    # Automatic achievements represented by the same observed milestones.
    achievement_eras = {
        "first_contract": min(sim.discovered["customers"].values(), default=0),
        "five_datacenters": milestone_era(sim, 7, 5),
        "twenty_datacenters": milestone_era(sim, 7, 20),
        "era_two": 2 if sim.era >= 2 else 0,
        "era_three": 3 if sim.era >= 3 else 0,
    }
    repaired = 0
    for era in (1, 2, 3):
        repaired += sim.manual_repairs_by_era[era]
        if repaired >= 10 and not achievement_eras.get("repair_ten"):
            achievement_eras["repair_ten"] = era
    retired = 0
    for era in (1, 2, 3):
        retired += sim.retirements_by_era[era]
        if retired >= 5 and not achievement_eras.get("retire_five"):
            achievement_eras["retire_five"] = era
    for item_id in achievements:
        if item_id not in achievement_eras:
            achievement_eras[item_id] = sim.metric_eras.get(item_id, 0)
    for item_id, era in achievement_eras.items():
        add_reward(rows, era, "achievement_auto", achievements[item_id]["reward_gems"])

    # Roadmap and collection rewards require an explicit claim in the game;
    # report them as claimable, not as already credited.
    roadmap_eras = {
        "first_facility": milestone_era(sim, 7, 1),
        "campus_operator": milestone_era(sim, 7, 6),
        "cloud_transition": 2 if sim.era >= 2 else 0,
        "client_portfolio": max(sim.discovered["customers"].values()) if len(sim.discovered["customers"]) >= 4 else 0,
        "global_network": 3 if sim.network >= 4 else 0,
        "first_inquiry": sim.first_inquiry_era,
    }
    for item_id in roadmap:
        if item_id not in roadmap_eras:
            roadmap_eras[item_id] = sim.metric_eras.get(item_id, 0)
    for item_id, era in roadmap_eras.items():
        add_reward(rows, era, "roadmap_claimable", roadmap[item_id]["reward_gems"])
    for group_id in ("facilities", "clients", "market_history", "campus_life", "legacy"):
        era = collection_completion_era(sim, group_id)
        reward = balance.META["collection"]["groups"][group_id]["reward_gems"]
        add_reward(rows, era, "collection_claimable", reward)

    # Existing reference strategies spend cash only. Zero is an observed
    # result, not an assumption about live-player behavior.
    for era in rows:
        rows[era]["speedup_spend_observed"] = 0
        rows[era]["instant_repair_spend_observed"] = 0
    return rows


def write_t2_report():
    return balance.run_t2_maintenance_probe(SEED, SEED_COUNT)


def write_l4_report():
    level = balance.TECHNOLOGY["upgrades"]["construction_bays"]["levels"]["4"]
    sim = balance.Simulator("active", SEED, prestige_count=1)
    balance.Simulator.now = 0.0
    sim.era = 3
    sim.construction_bays = 3
    sim.cash = float(level["cost"]) * 1.15 + 1.0
    for index in range(4):
        sim.dcs.append(balance.Datacenter("dc_t3", 0.0, 3600.0 + index, list(balance.LOADOUTS["dc_t3"][0])))
    before = sim.cash
    sim.maybe_purchase_construction_bays()
    purchased = sim.construction_bays == 4
    capacity = sim.queue_capacity()
    path = balance.OUT / "engineering_l4_probe.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["authored_cost", "minimum_prestige", "runtime_exact_cost_test", "strategy_start_cash", "full_queue", "strategy_purchased", "result_capacity", "cash_spent"])
        writer.writerow([level["cost"], level["minimum_prestige"], "tests/test_runner.gd::_run_construction_bays_tests", f"{before:.2f}", 4, purchased, capacity, f"{before - sim.cash:.2f}"])
    assert purchased and capacity == 5 and before - sim.cash == level["cost"]
    return purchased, capacity


def write_diamond_report():
    totals = {strategy: {era: defaultdict(float) for era in (1, 2, 3)} for strategy in STRATEGIES}
    for strategy_index, strategy in enumerate(STRATEGIES):
        for run in range(SEED_COUNT):
            sim = AuditSimulator(strategy, SEED + run * 101 + strategy_index).run(30)
            rows = diamond_rows(sim)
            for era, values in rows.items():
                for key, value in values.items():
                    totals[strategy][era][key] += value / SEED_COUNT
    fields = ["strategy", "era", "era_auto", "achievement_auto", "roadmap_claimable", "collection_claimable", "speedup_spend_observed", "instant_repair_spend_observed", "net_if_claimed"]
    path = balance.OUT / "diamond_sources_sinks_30d.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for strategy in STRATEGIES:
            for era in (1, 2, 3):
                values = totals[strategy][era]
                source = sum(values[key] for key in ("era_auto", "achievement_auto", "roadmap_claimable", "collection_claimable"))
                spend = values["speedup_spend_observed"] + values["instant_repair_spend_observed"]
                writer.writerow({
                    "strategy": strategy,
                    "era": era,
                    **{key: f"{values[key]:.2f}" for key in fields[2:-1]},
                    "net_if_claimed": f"{source - spend:.2f}",
                })
    return totals


def main():
    balance.OUT.mkdir(parents=True, exist_ok=True)
    t2_rows = write_t2_report()
    purchased, capacity = write_l4_report()
    write_diamond_report()
    print(f"PASS: T2 post-B7 sweep wrote {len(t2_rows)} candidates x {SEED_COUNT} seeds")
    print(f"PASS: Engineering L4 strategy purchase={purchased} capacity={capacity}")
    print(f"PASS: diamond source/sink report wrote {len(STRATEGIES)} strategies x 3 eras x {SEED_COUNT} seeds")
    return 0


if __name__ == "__main__":
    if "--density-probe" in sys.argv or "--density-builds" in sys.argv:
        replay = AuditSimulator("active", SEED + 1).run(30)
        print(json.dumps(replay.completed_center_timeline if "--density-builds" in sys.argv else replay.progress_receipts))
    else:
        raise SystemExit(main())
