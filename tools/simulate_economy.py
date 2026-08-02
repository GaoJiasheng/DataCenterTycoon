#!/usr/bin/env python3
"""Thirty-day seeded balance simulation driven by the game's JSON tables."""

import argparse
import csv
import json
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/balance_runs"


def load(name):
    return json.loads((ROOT / "data" / f"{name}.json").read_text(encoding="utf-8"))


ECONOMY = load("economy")
BUILDINGS = load("buildings")["items"]
RACKS = load("racks")["items"]
ATTACHMENTS = load("attachments")["items"]
CUSTOMERS = load("customers")["items"]
EVENTS = load("events")["items"]
ERAS = load("eras")["items"]
MONTH = ECONOMY["time"]["real_seconds_per_game_month"]
YEAR = ECONOMY["time"]["real_seconds_per_game_year"]
DAY = 86400
STEP = ECONOMY["time"]["real_seconds_per_game_day"]


LOADOUTS = {
    "dc_t0": (["rack_compute_t1"] * 2, "power_t1", ["cool_air_t1"]),
    "dc_t1": (["rack_compute_t1"] * 4 + ["rack_storage_t1"] * 2, "power_t2", ["cool_air_t1"] * 2),
    "dc_t2": (["rack_compute_t2"] * 3 + ["rack_storage_t2"] * 2 + ["rack_gpu_t1"], "power_t2", ["cool_air_t2"] * 3),
    "dc_t3": (["rack_gpu_t2"] * 3 + ["rack_storage_t2"] * 5 + ["rack_compute_t2"], "power_t3", ["cool_liquid_t2"] * 4),
}


@dataclass
class Datacenter:
    building_id: str
    built_at: float
    ready_at: float
    racks: list
    customer: str = "internet"
    faulted: set = field(default_factory=set)

    @property
    def ready(self):
        return self.ready_at <= Simulator.now


class Simulator:
    now = 0.0

    def __init__(self, strategy, seed):
        self.strategy = strategy
        self.rng = random.Random(seed)
        self.cash = float(ECONOMY["starting"]["cash"])
        self.revenue = 0.0
        self.era = 1
        self.network = 1
        self.dcs = []
        self.plots = 1
        self.total_built = 0
        self.maintenance_at = MONTH
        self.events = []
        self.next_event = MONTH
        self.arrears = 0
        self.debt = 0.0
        self.missed_maintenance = 0
        self.bankrupt = False
        self.ended_at = 0.0
        self.minimum_cash = self.cash
        self.minimum_maintenance_coverage = math.inf
        self.curve = []
        self.sessions_per_day = 2 if strategy == "idle" else 6
        self.next_session = 0.0

    def run(self, days):
        Simulator.now = 0.0
        while Simulator.now < days * DAY and not self.bankrupt:
            self.update_market()
            self.accrue()
            self.roll_faults()
            if Simulator.now >= self.maintenance_at:
                self.pay_maintenance()
                self.maintenance_at += MONTH
            if Simulator.now >= self.next_session:
                self.player_session()
                self.next_session += DAY / self.sessions_per_day
            self.unlock_era()
            self.minimum_cash = min(self.minimum_cash, self.cash)
            maintenance = sum(BUILDINGS[dc.building_id]["maintenance_per_month"] for dc in self.dcs if dc.ready)
            if maintenance > 0:
                self.minimum_maintenance_coverage = min(self.minimum_maintenance_coverage, self.cash / maintenance)
            if int(Simulator.now) % DAY < STEP:
                self.record()
            Simulator.now += STEP
        self.record()
        self.ended_at = Simulator.now
        return self

    def update_market(self):
        self.events = [event for event in self.events if event[1] > Simulator.now]
        if Simulator.now < self.next_event or len(self.events) >= 2:
            return
        choices = [(key, value) for key, value in EVENTS.items() if value["minimum_era"] <= self.era]
        total = sum(item[1]["weight"] for item in choices)
        roll = self.rng.random() * total
        selected = choices[-1]
        for choice in choices:
            roll -= choice[1]["weight"]
            if roll <= 0:
                selected = choice
                break
        self.events.append((selected[0], Simulator.now + selected[1]["duration_months"] * MONTH))
        self.next_event = Simulator.now + self.rng.uniform(1, 3) * MONTH

    def market_multiplier(self, customer):
        result = CUSTOMERS[customer]["era_baseline"].get(str(self.era), 0)
        for event_id, _end in self.events:
            event = EVENTS[event_id]
            result *= event.get("all_customer_multiplier", 1)
            result *= event.get("customer_multipliers", {}).get(customer, 1)
        return result

    def dc_monthly_income(self, dc):
        if not dc.ready or Simulator.now - dc.built_at >= BUILDINGS[dc.building_id]["lifespan_seconds"]:
            return 0
        customer = CUSTOMERS[dc.customer]
        subtotal = 0
        kinds = set()
        for index, rack_id in enumerate(dc.racks):
            if index in dc.faulted:
                continue
            rack = RACKS[rack_id]
            kinds.add(rack["kind"])
            subtotal += rack["income_per_month"] * customer["fit"][rack["kind"]]
        if len(kinds) >= customer.get("diversity_required_kinds", 999):
            subtotal *= customer.get("diversity_multiplier", 1)
        age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
        if age <= 0.6:
            efficiency = 1
        elif age <= 0.9:
            efficiency = 1 - (age - 0.6)
        else:
            efficiency = 0.7 - (age - 0.9) * 3
        network = load("technology")["network"][str(self.network)]["income_multiplier"]
        return subtotal * max(0, efficiency) * self.market_multiplier(dc.customer) * network * BUILDINGS[dc.building_id]["structure_multiplier"]

    def accrue(self):
        income = sum(self.dc_monthly_income(dc) for dc in self.dcs) * STEP / MONTH
        self.cash += income
        self.revenue += income
        if self.debt > 0 and self.cash >= self.debt:
            self.cash -= self.debt
            self.debt = 0.0
            self.missed_maintenance = 0

    def roll_faults(self):
        base = ECONOMY["faults"]["base_rate_per_game_month"] * STEP / MONTH
        for dc in self.dcs:
            if not dc.ready:
                continue
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            age_factor = 6 if age > 0.9 else (3 if age > 0.6 else 1)
            for index in range(len(dc.racks)):
                if index not in dc.faulted and self.rng.random() < base * age_factor:
                    dc.faulted.add(index)

    def pay_maintenance(self):
        amount = sum(BUILDINGS[dc.building_id]["maintenance_per_month"] for dc in self.dcs if dc.ready)
        total_due = amount + self.debt
        if self.cash >= total_due:
            self.cash -= total_due
            self.debt = 0.0
            self.missed_maintenance = 0
        else:
            self.debt = total_due - self.cash
            self.arrears += 1
            self.cash = 0
            self.missed_maintenance += 1
            if self.missed_maintenance >= 3:
                self.bankrupt = True

    def player_session(self):
        for dc in self.dcs:
            for index in list(dc.faulted):
                cost = math.ceil(RACKS[dc.racks[index]]["cost"] * ECONOMY["faults"]["repair_cost_ratio"])
                if self.cash >= cost:
                    self.cash -= cost
                    dc.faulted.remove(index)
        if self.strategy == "active":
            for dc in self.dcs:
                available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                self.switch_to_best_customer(dc, available)
        elif self.strategy == "aggressive":
            for dc in self.dcs:
                self.switch_to_best_customer(dc, ("internet", "mining"))
        self.retire_old()
        attempts = 6 if self.strategy == "aggressive" else 1
        for _ in range(attempts):
            if not self.try_expand():
                break

    def switch_to_best_customer(self, dc, available):
        choice = max(available, key=lambda customer: self.market_multiplier(customer) * sum(RACKS[r]["income_per_month"] * CUSTOMERS[customer]["fit"][RACKS[r]["kind"]] for r in dc.racks))
        if choice == dc.customer:
            return
        fee = max(ECONOMY["contracts"]["minimum_breach_fee"], self.dc_monthly_income(dc) * ECONOMY["contracts"]["breach_fee_monthly_income_ratio"])
        if self.cash >= fee:
            self.cash -= fee
            dc.customer = choice

    def retire_old(self):
        survivors = []
        for dc in self.dcs:
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            threshold = 0.7 if self.strategy == "idle" else (0.85 if self.strategy == "active" else 1.0)
            if age < threshold:
                survivors.append(dc)
                continue
            building = BUILDINGS[dc.building_id]
            if age < 1:
                self.cash += building["cost"] * 0.4 * (1 - age)
            else:
                demolition = building["cost"] * ECONOMY["aging"]["demolition_cost_ratio"]
                self.cash -= min(self.cash, demolition)
        self.dcs = survivors

    def try_expand(self):
        reserve = {"idle": 1.8, "active": 1.25, "aggressive": 1.0}[self.strategy]
        if not self.dcs:
            reserve = 1.0
        candidates = ["dc_t0"] if self.total_built == 0 else (["dc_t3", "dc_t2", "dc_t1"] if self.era >= 3 else (["dc_t2", "dc_t1"] if self.era >= 2 else ["dc_t1"]))
        for building_id in candidates:
            racks, power, coolers = LOADOUTS[building_id]
            needs_land = len(self.dcs) >= self.plots
            next_plot = self.plots + 1
            land = round(ECONOMY["land"]["base_price"] * ECONOMY["land"]["growth_factor"] ** (next_plot - 1)) if needs_land else 0
            package = BUILDINGS[building_id]["cost"] + ATTACHMENTS[power]["cost"] + sum(ATTACHMENTS[c]["cost"] for c in coolers) + sum(RACKS[r]["cost"] for r in racks) + land
            if self.cash < package * reserve:
                continue
            self.cash -= package
            self.total_built += 1
            if needs_land:
                self.plots += 1
            ready_at = Simulator.now + BUILDINGS[building_id]["build_seconds"]
            self.dcs.append(Datacenter(building_id, ready_at, ready_at, list(racks)))
            return True
        return False

    def unlock_era(self):
        for era in (2, 3):
            if self.era < era and self.revenue >= ERAS[str(era)]["revenue_required"]:
                self.era = era
                if era == 2 and self.cash >= load("technology")["network"]["2"]["cost"]:
                    self.cash -= load("technology")["network"]["2"]["cost"]
                    self.network = 2

    def net_worth(self, at=None):
        now = Simulator.now if at is None else at
        return self.cash + sum(BUILDINGS[dc.building_id]["cost"] * max(0, 1 - (now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]) * 0.4 for dc in self.dcs)

    def record(self):
        day = Simulator.now / DAY
        if self.curve and abs(self.curve[-1][0] - day) < 0.5:
            return
        self.curve.append((day, self.net_worth(), self.cash, len(self.dcs), self.era, self.revenue, self.arrears))


def write_csv(results):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, sim in results.items():
        with (OUT / f"{name}.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["real_day", "net_worth", "cash", "datacenters", "era", "total_revenue", "arrears_count"])
            writer.writerows(sim.curve)


def write_svg(results):
    width, height, pad = 1200, 680, 80
    maximum = max(point[1] for sim in results.values() for point in sim.curve) or 1
    colors = {"idle": "#3aa7f0", "active": "#7bc94c", "aggressive": "#ff8a3d"}
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">', '<rect width="100%" height="100%" fill="#16263d"/>']
    for index in range(6):
        y = pad + (height - pad * 2) * index / 5
        lines.append(f'<line x1="{pad}" y1="{y:.1f}" x2="{width-pad}" y2="{y:.1f}" stroke="#ffffff" opacity="0.1"/>')
    for name, sim in results.items():
        points = []
        for day, worth, *_ in sim.curve:
            x = pad + day / 30 * (width - pad * 2)
            y = height - pad - worth / maximum * (height - pad * 2)
            points.append(f"{x:.1f},{y:.1f}")
        lines.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{colors[name]}" stroke-width="6"/>')
    lines.append('</svg>')
    (OUT / "net_worth_30d.svg").write_text("\n".join(lines), encoding="utf-8")


def point_at(sim, day):
    return min(sim.curve, key=lambda point: abs(point[0] - day))


def print_acceptance(results):
    active_day_1 = point_at(results["active"], 1)
    active_day_7 = point_at(results["active"], 7)
    idle_day_7 = point_at(results["idle"], 7)
    idle_ratio = idle_day_7[5] / active_day_7[5] if active_day_7[5] else 0
    checks = (
        (2 <= active_day_1[3] <= 3 and active_day_1[2] > 0, "day 1 active player has 2–3 data centers and positive cash"),
        (6 <= active_day_7[3] <= 10 and active_day_7[4] >= 2, "day 7 active player has 6–10 data centers and reaches era 2"),
        (0.4 <= idle_ratio <= 0.6, f"day 7 idle revenue is {idle_ratio:.0%} of active revenue"),
        (not any(sim.bankrupt for sim in results.values()), "all three deterministic strategies survive 30 days"),
    )
    for passed, description in checks:
        print(f"{'PASS' if passed else 'TUNE'}: {description}")
    aggressive = results["aggressive"]
    coverage = aggressive.minimum_maintenance_coverage
    print(f"{'PASS' if aggressive.arrears else 'TUNE'}: aggressive arrears={aggressive.arrears}; minimum maintenance coverage={coverage:.2f}x")
    diversified = all(len({RACKS[rack]["kind"] for rack in loadout[0]}) >= 2 for key, loadout in LOADOUTS.items() if key != "dc_t0")
    print(f"{'PASS' if diversified else 'TUNE'}: every post-tutorial reference loadout uses at least two rack kinds")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260802)
    args = parser.parse_args()
    results = {name: Simulator(name, args.seed + index).run(args.days) for index, name in enumerate(("idle", "active", "aggressive"))}
    write_csv(results)
    write_svg(results)
    for name, sim in results.items():
        print(f"{name:10s} day={sim.ended_at / DAY:.0f} dc={len(sim.dcs):2d} era={sim.era} revenue=${sim.revenue:,.0f} net=${sim.net_worth(sim.ended_at):,.0f} min_cash=${sim.minimum_cash:,.0f} arrears={sim.arrears} bankrupt={sim.bankrupt}")
    print_acceptance(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
