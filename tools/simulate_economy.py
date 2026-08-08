#!/usr/bin/env python3
"""Thirty-day seeded balance simulation driven by the game's JSON tables."""

import argparse
import csv
import json
import math
import random
import statistics
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
TECHNOLOGY = load("technology")
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
    customer: str = ""
    faulted: dict = field(default_factory=dict)
    contract_end_at: float = 0.0
    locked_market_multiplier: float = 1.0
    free_switch_available: bool = False

    @property
    def ready(self):
        return self.ready_at <= Simulator.now


class Simulator:
    now = 0.0

    def __init__(self, strategy, seed, cozy_faults=True):
        self.strategy = strategy
        self.cozy_faults = cozy_faults
        self.market_rng = random.Random(seed)
        self.fault_rng = random.Random(seed ^ 0x5F3759DF)
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
        self.arrears_online_seconds = 0.0
        self.bankrupt = False
        self.ended_at = 0.0
        self.minimum_cash = self.cash
        self.minimum_maintenance_coverage = math.inf
        self.curve = []
        self.customer_seconds = {customer: 0.0 for customer in CUSTOMERS}
        self.prestige_ready_at = None
        self.sessions_per_day = 2 if strategy == "idle" else 6
        self.next_session = 0.0

    def run(self, days):
        Simulator.now = 0.0
        while Simulator.now < days * DAY and not self.bankrupt:
            self.update_market()
            self.update_contracts()
            self.complete_auto_repairs()
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
        blocked_customers = set()
        if not ECONOMY["market"].get("allow_same_customer_event_stack", False):
            for event_id, _end in self.events:
                blocked_customers.update(EVENTS[event_id].get("customer_multipliers", {}))
        choices = [
            (key, value)
            for key, value in EVENTS.items()
            if value["minimum_era"] <= self.era
            and value.get("minimum_network_level", 1) <= self.network
            and not blocked_customers.intersection(value.get("customer_multipliers", {}))
        ]
        total = sum(item[1]["weight"] for item in choices)
        roll = self.market_rng.random() * total
        selected = choices[-1]
        for choice in choices:
            roll -= choice[1]["weight"]
            if roll <= 0:
                selected = choice
                break
        self.events.append((selected[0], Simulator.now + selected[1]["duration_months"] * MONTH))
        self.next_event = Simulator.now + self.market_rng.uniform(1, 3) * MONTH

    def market_multiplier(self, customer):
        result = CUSTOMERS[customer]["era_baseline"].get(str(self.era), 0)
        for event_id, _end in self.events:
            event = EVENTS[event_id]
            result *= event.get("all_customer_multiplier", 1)
            result *= event.get("customer_multipliers", {}).get(customer, 1)
        return result

    def dc_monthly_income(self, dc):
        if not dc.ready or not dc.customer or Simulator.now - dc.built_at >= BUILDINGS[dc.building_id]["lifespan_seconds"]:
            return 0
        customer = CUSTOMERS[dc.customer]
        subtotal = 0
        kinds = set()
        raw_market = dc.locked_market_multiplier
        for index, rack_id in enumerate(dc.racks):
            fault_multiplier = (ECONOMY["faults"]["faulted_income_multiplier"] if self.cozy_faults else 0.0) if index in dc.faulted else 1.0
            rack = RACKS[rack_id]
            kinds.add(rack["kind"])
            sensitivity = rack.get("market_sensitivity", 1.0)
            effective_market = max(0, 1 + (raw_market - 1) * sensitivity)
            subtotal += rack["income_per_month"] * customer["fit"][rack["kind"]] * effective_market * fault_multiplier
        if len(kinds) >= customer.get("diversity_required_kinds", 999):
            subtotal *= customer.get("diversity_multiplier", 1)
        age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
        if age <= 0.6:
            efficiency = 1
        elif age <= 0.9:
            efficiency = 1 - (age - 0.6)
        else:
            efficiency = 0.7 - (age - 0.9) * 3
        network = TECHNOLOGY["network"][str(self.network)]["income_multiplier"]
        return subtotal * max(0, efficiency) * network * BUILDINGS[dc.building_id]["structure_multiplier"]

    def accrue(self):
        income = sum(self.dc_monthly_income(dc) for dc in self.dcs) * STEP / MONTH
        for dc in self.dcs:
            if dc.ready and dc.customer and Simulator.now - dc.built_at < BUILDINGS[dc.building_id]["lifespan_seconds"]:
                self.customer_seconds[dc.customer] += STEP
        self.cash += income
        self.revenue += income
        if self.debt > 0 and self.cash >= self.debt:
            self.cash -= self.debt
            self.debt = 0.0
            self.missed_maintenance = 0
            self.arrears_online_seconds = 0.0

    def roll_faults(self):
        base = ECONOMY["faults"]["base_rate_per_game_month"] * STEP / MONTH
        for dc in self.dcs:
            if not dc.ready:
                continue
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            age_factor = 6 if age > 0.9 else (3 if age > 0.6 else 1)
            for index in range(len(dc.racks)):
                if index not in dc.faulted and self.fault_rng.random() < base * age_factor:
                    dc.faulted[index] = Simulator.now + ECONOMY["faults"]["auto_repair_seconds"] if self.cozy_faults else math.inf

    def complete_auto_repairs(self):
        if not self.cozy_faults:
            return
        for dc in self.dcs:
            for index, repair_at in list(dc.faulted.items()):
                if Simulator.now >= repair_at:
                    del dc.faulted[index]

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

    def player_session(self):
        if self.debt > 0:
            self.arrears_online_seconds += 300.0
            if self.arrears_online_seconds >= ECONOMY["bankruptcy"]["game_over_after_online_seconds"]:
                self.bankrupt = True
                return
        if not self.cozy_faults or self.strategy != "idle":
            for dc in self.dcs:
                for index in list(dc.faulted):
                    cost = math.ceil(RACKS[dc.racks[index]]["cost"] * ECONOMY["faults"]["repair_cost_ratio"])
                    if self.cash >= cost:
                        self.cash -= cost
                        del dc.faulted[index]
        if self.strategy == "active":
            for dc in self.dcs:
                if not dc.ready or (dc.customer and not dc.free_switch_available):
                    continue
                available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                self.switch_to_best_customer(dc, available)
        elif self.strategy == "aggressive":
            for dc in self.dcs:
                if not dc.ready:
                    continue
                self.switch_to_best_customer(dc, ("internet", "mining"))
        else:
            for dc in self.dcs:
                if dc.ready and not dc.customer:
                    self.sign_customer(dc, "internet")
        self.retire_old()
        self.maybe_upgrade_network()
        attempts = 6 if self.strategy == "aggressive" else 1
        for _ in range(attempts):
            if not self.try_expand():
                break

    def switch_to_best_customer(self, dc, available):
        values = {
            customer: sum(
                RACKS[r]["income_per_month"]
                * CUSTOMERS[customer]["fit"][RACKS[r]["kind"]]
                * max(0, 1 + (self.market_multiplier(customer) - 1) * RACKS[r].get("market_sensitivity", 1.0))
                for r in dc.racks
            )
            for customer in available
        }
        best_value = max(values.values())
        viable = [customer for customer in available if values[customer] >= best_value * 0.50]
        contracted = {customer: sum(1 for item in self.dcs if item.customer == customer) for customer in available}
        free_switch = dc.free_switch_available
        if not dc.customer or free_switch:
            portfolio_candidates = [customer for customer in available if values[customer] >= best_value * 0.35]
            total_seconds = sum(self.customer_seconds[customer] for customer in available) or 1.0
            choice = min(
                portfolio_candidates,
                key=lambda customer: (self.customer_seconds[customer] / total_seconds, contracted[customer], -values[customer]),
            )
        else:
            choice = max(viable, key=lambda customer: (-(contracted[customer]), values[customer]))
        if choice == dc.customer:
            return
        fee = 0 if not dc.customer or free_switch else max(ECONOMY["contracts"]["minimum_breach_fee"], self.dc_monthly_income(dc) * ECONOMY["contracts"]["breach_fee_monthly_income_ratio"])
        if self.cash >= fee:
            self.cash -= fee
            self.sign_customer(dc, choice)

    def sign_customer(self, dc, customer):
        if dc.customer == customer:
            return
        dc.customer = customer
        dc.locked_market_multiplier = self.market_multiplier(customer)
        dc.contract_end_at = Simulator.now + ECONOMY["contracts"]["duration_seconds"]
        dc.free_switch_available = False

    def update_contracts(self):
        duration = ECONOMY["contracts"]["duration_seconds"]
        for dc in self.dcs:
            if dc.ready and not dc.customer:
                if self.strategy == "idle":
                    self.sign_customer(dc, "internet")
                else:
                    available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                    if self.strategy == "aggressive":
                        available = [key for key in ("internet", "mining") if key in available]
                    self.switch_to_best_customer(dc, available)
            if not dc.customer:
                continue
            if dc.contract_end_at <= 0:
                dc.contract_end_at = dc.ready_at + duration
            while Simulator.now >= dc.contract_end_at:
                dc.contract_end_at += duration
                dc.locked_market_multiplier = self.market_multiplier(dc.customer)
                dc.free_switch_available = True
            if self.strategy == "active" and dc.free_switch_available:
                available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                self.switch_to_best_customer(dc, available)

    def maybe_upgrade_network(self):
        desired = 2 if self.era == 1 else (3 if self.era == 2 else 4)
        if self.strategy == "idle":
            desired = min(desired, 2)
        while self.network < desired:
            level = TECHNOLOGY["network"][str(self.network + 1)]
            reserve = 1.4 if self.strategy == "active" else (1.0 if self.strategy == "aggressive" else 2.0)
            if self.cash < level["cost"] * reserve:
                break
            self.cash -= level["cost"]
            self.network += 1

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
        reserve = {"idle": 1.4, "active": 1.05, "aggressive": 1.0}[self.strategy]
        if self.strategy == "active" and 10 <= self.total_built < ECONOMY["prestige"]["minimum_datacenters"]:
            reserve += (self.total_built - 9) * 0.50
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
            if self.total_built >= ECONOMY["prestige"]["minimum_datacenters"] and self.prestige_ready_at is None:
                self.prestige_ready_at = Simulator.now
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
                self.maybe_upgrade_network()

    def net_worth(self, at=None):
        now = Simulator.now if at is None else at
        return self.cash + sum(BUILDINGS[dc.building_id]["cost"] * max(0, 1 - (now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]) * 0.4 for dc in self.dcs)

    def record(self):
        day = Simulator.now / DAY
        if self.curve and abs(self.curve[-1][0] - day) < 0.5:
            return
        self.curve.append((day, self.net_worth(), self.cash, len(self.dcs), self.era, self.revenue, self.arrears, self.total_built))


def write_csv(results):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, sim in results.items():
        with (OUT / f"{name}.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["real_day", "net_worth", "cash", "datacenters", "era", "total_revenue", "arrears_count", "total_built"])
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


def contract_locking_probe():
    sim = Simulator("idle", 17)
    Simulator.now = 0.0
    baseline = CUSTOMERS["mining"]["era_baseline"]["1"]
    dc = Datacenter(
        "dc_t0", 0.0, 0.0, ["rack_compute_t1"], customer="mining",
        contract_end_at=ECONOMY["contracts"]["duration_seconds"],
        locked_market_multiplier=baseline,
    )
    sim.dcs = [dc]
    before = sim.dc_monthly_income(dc)
    sim.events = [("mining_crash", ECONOMY["contracts"]["duration_seconds"] * 4)]
    during = sim.dc_monthly_income(dc)
    Simulator.now = dc.contract_end_at
    sim.update_contracts()
    after_renewal = sim.dc_monthly_income(dc)
    return math.isclose(before, during) and after_renewal < during and dc.free_switch_available


def print_acceptance(results, cohorts, legacy_idle_cohort):
    active_day_1 = point_at(results["active"], 1)
    active_day_7 = point_at(results["active"], 7)
    idle_day_7 = point_at(results["idle"], 7)
    idle_ratio = idle_day_7[5] / active_day_7[5] if active_day_7[5] else 0
    legacy_idle_revenue = statistics.mean(sim.revenue for sim in legacy_idle_cohort) or 1.0
    idle_fault_loss = max(0.0, 1.0 - statistics.mean(sim.revenue for sim in cohorts["idle"]) / legacy_idle_revenue)
    checks = [
        (contract_locking_probe(), "mining downturn leaves an existing contract unchanged until automatic renewal"),
        (idle_fault_loss < 0.08, f"passive auto-repair curve loses {idle_fault_loss:.1%} versus the same-seed pre-A4 fault model (target <8%)"),
        (2 <= active_day_1[3] <= 3 and active_day_1[2] > 0, "day 1 active player has 2–3 data centers and positive cash"),
        (6 <= active_day_7[3] <= 10 and active_day_7[4] >= 2, "day 7 active player has 6–10 data centers and reaches era 2"),
        (0.4 <= idle_ratio <= 0.6, f"day 7 idle revenue is {idle_ratio:.0%} of active revenue"),
    ]
    aggressive_rate = sum(sim.arrears > 0 for sim in cohorts["aggressive"]) / len(cohorts["aggressive"])
    all_runs = [sim for sims in cohorts.values() for sim in sims]
    bankruptcy_rate = sum(sim.bankrupt for sim in all_runs) / len(all_runs)
    prestige_days = [sim.prestige_ready_at / DAY for sim in cohorts["active"] if sim.prestige_ready_at is not None]
    median_prestige = statistics.median(prestige_days) if prestige_days else math.inf
    customer_seconds = {
        customer: sum(sim.customer_seconds[customer] for sim in cohorts["active"])
        for customer in CUSTOMERS
    }
    customer_total = sum(customer_seconds.values()) or 1
    customer_shares = {customer: seconds / customer_total for customer, seconds in customer_seconds.items()}
    checks.extend([
        (14 <= median_prestige <= 21, f"active prestige readiness median is day {median_prestige:.1f} (target day 14–21)"),
        (all(share >= 0.10 for share in customer_shares.values()), "active contract-time share: " + ", ".join(f"{key}={value:.0%}" for key, value in customer_shares.items())),
        (0.30 <= aggressive_rate <= 0.60, f"aggressive arrears incidence is {aggressive_rate:.0%} (target 30–60%)"),
        (bankruptcy_rate < 0.10, f"multi-seed bankruptcy incidence is {bankruptcy_rate:.0%} (target <10%)"),
    ])
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
    parser.add_argument("--seed-count", type=int, default=20)
    parser.add_argument("--maintenance-scale", type=float, default=1.0, help="Calibration-only multiplier for T2/T3 maintenance")
    parser.add_argument("--maintenance-t2-scale", type=float, default=None, help="Override the T2 calibration multiplier")
    parser.add_argument("--maintenance-t3-scale", type=float, default=None, help="Override the T3 calibration multiplier")
    parser.add_argument("--no-write", action="store_true", help="Do not replace the canonical CSV/SVG outputs")
    args = parser.parse_args()
    BUILDINGS["dc_t2"]["maintenance_per_month"] *= args.maintenance_t2_scale if args.maintenance_t2_scale is not None else args.maintenance_scale
    BUILDINGS["dc_t3"]["maintenance_per_month"] *= args.maintenance_t3_scale if args.maintenance_t3_scale is not None else args.maintenance_scale
    strategy_names = ("idle", "active", "aggressive")
    cohorts = {
        name: [Simulator(name, args.seed + run * 101 + index).run(args.days) for run in range(max(1, args.seed_count))]
        for index, name in enumerate(strategy_names)
    }
    legacy_idle_cohort = [Simulator("idle", args.seed + run * 101, cozy_faults=False).run(args.days) for run in range(max(1, args.seed_count))]
    results = {name: cohorts[name][0] for name in strategy_names}
    if not args.no_write:
        write_csv(results)
        write_svg(results)
    for name, sim in results.items():
        print(f"{name:10s} day={sim.ended_at / DAY:.0f} dc={len(sim.dcs):2d} era={sim.era} revenue=${sim.revenue:,.0f} net=${sim.net_worth(sim.ended_at):,.0f} min_cash=${sim.minimum_cash:,.0f} arrears={sim.arrears} bankrupt={sim.bankrupt}")
    print_acceptance(results, cohorts, legacy_idle_cohort)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
