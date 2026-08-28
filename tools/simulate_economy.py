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
META = load("meta_progression")
INQUIRIES = load("inquiries")
MONTH = ECONOMY["time"]["real_seconds_per_game_month"]
YEAR = ECONOMY["time"]["real_seconds_per_game_year"]
DAY = 86400
STEP = ECONOMY["time"]["real_seconds_per_game_day"]
PORTFOLIO_THRESHOLD = 0.60
ACTIVE_PRESTIGE_RESERVE_STEP = 1.8
AGGRESSIVE_SESSION_SECONDS = 21600.0
AGGRESSIVE_SESSIONS_PER_DAY = 6


LOADOUTS = {
    "dc_t0": (["rack_compute_t1"] * 2, "power_t1", ["cool_air_t1"]),
    "dc_t1": (["rack_compute_t1"] * 4 + ["rack_storage_t1"] * 2, "power_t2", ["cool_air_t1"] * 2),
    "dc_t2": (["rack_compute_t2"] * 3 + ["rack_storage_t2"] * 2 + ["rack_gpu_t1"], "power_t2", ["cool_air_t2"] * 3),
    "dc_t3": (["rack_gpu_t2"] * 3 + ["rack_storage_t2"] * 5 + ["rack_compute_t2"], "power_t3", ["cool_liquid_t2"] * 4),
}


def campus_layout(plot_index):
    campuses = ECONOMY.get("campuses", {})
    definitions = campuses.get("types", {})
    sequence = campuses.get("sequence", [])
    if not sequence or not definitions:
        return {"campus_index": max(0, (plot_index - 1) // 6), "type_id": "type_1", "capacity": 6, "land_price_multiplier": 1.0}
    remaining = max(1, plot_index)
    campus_index = 0
    for type_id in sequence:
        definition = definitions[type_id]
        capacity = max(1, int(definition["capacity"]))
        if remaining <= capacity:
            return {"campus_index": campus_index, "type_id": type_id, **definition}
        remaining -= capacity
        campus_index += 1
    type_id = sequence[-1]
    definition = definitions[type_id]
    capacity = max(1, int(definition["capacity"]))
    campus_index += (remaining - 1) // capacity
    return {"campus_index": campus_index, "type_id": type_id, **definition}


def land_price(plot_index):
    if plot_index <= ECONOMY["starting"]["free_plot_count"]:
        return 0
    land = ECONOMY["land"]
    multiplier = campus_layout(plot_index).get("land_price_multiplier", 1.0)
    growth_base = 1.0 + land["growth_step"] * (plot_index - 1)
    return round(land["base_price"] * growth_base ** land["growth_exponent"] * multiplier)


def set_bonus_indices(racks):
    """Mirror Rules.set_bonus_slots for the simulator's always-powered loadouts."""
    result = set()
    lines = ((0, 1, 2), (3, 4, 5), (6, 7, 8), (0, 3, 6), (1, 4, 7), (2, 5, 8))
    for line in lines:
        if any(slot >= len(racks) or not racks[slot] for slot in line):
            continue
        kinds = {RACKS[racks[slot]]["kind"] for slot in line}
        if len(kinds) == 1:
            result.update(line)
    return result


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
    contract_duration_id: str = "standard"
    contract_income_multiplier: float = 1.0
    inquiry_contract: bool = False
    inquiry_revenue_fraction: float = 0.0

    @property
    def ready(self):
        return self.ready_at <= Simulator.now


class Simulator:
    now = 0.0

    def __init__(
        self,
        strategy,
        seed,
        cozy_faults=True,
        market_lock_mode="normal",
        strategic_cap_enabled=True,
        active_contract_term="standard",
        prestige_count=0,
    ):
        self.strategy = strategy
        self.cozy_faults = cozy_faults
        self.market_rng = random.Random(seed)
        self.fault_rng = random.Random(seed ^ 0x5F3759DF)
        self.inquiry_rng = random.Random(seed ^ 0x1A2B3C4D)
        self.cash = float(ECONOMY["starting"]["cash"])
        self.revenue = 0.0
        self.era = 1
        self.network = 1
        self.dcs = []
        self.plots = 1
        self.land_spend = 0.0
        self.total_built = 0
        self.maintenance_at = MONTH
        self.events = []
        self.next_event = MONTH
        self.arrears = 0
        self.debt = 0.0
        self.missed_maintenance = 0
        self.arrears_online_seconds = 0.0
        self.takeovers = 0
        self.bank_sold = 0
        self.debt_forgiven = 0.0
        self.relief_received = 0.0
        self.negative_cash_months = 0
        self.ended_at = 0.0
        self.minimum_cash = self.cash
        self.minimum_maintenance_coverage = math.inf
        self.curve = []
        self.customer_seconds = {customer: 0.0 for customer in CUSTOMERS}
        self.prestige_ready_at = None
        self.auto_retirement = False
        self.auto_retirements = 0
        self.sessions_per_day = 2 if strategy == "idle" else (AGGRESSIVE_SESSIONS_PER_DAY if strategy == "aggressive" else 6)
        self.session_count = 0
        self.next_session = 0.0
        self.construction_bays = 1
        self.construction_bay_purchases = []
        self.build_start_times = []
        self.maximum_construction_queue = 0
        self.open_inquiries = []
        self.next_inquiry = 0.0
        self.inquiry_sequence = 0
        self.inquiries_accepted = 0
        self.inquiry_bonus_revenue = 0.0
        self.inquiry_contract_revenue = 0.0
        self.market_lock_mode = market_lock_mode
        self.strategic_cap_enabled = strategic_cap_enabled
        self.active_contract_term = active_contract_term
        self.prestige_count = prestige_count

    def run(self, days):
        Simulator.now = 0.0
        while Simulator.now < days * DAY:
            self.update_market()
            self.update_inquiries()
            self.update_contracts()
            self.complete_auto_repairs()
            self.process_auto_retirements()
            self.accrue()
            self.roll_faults()
            if Simulator.now >= self.maintenance_at:
                self.pay_maintenance()
                self.maintenance_at += MONTH
            if Simulator.now >= self.next_session:
                self.player_session()
                self.next_session += DAY / self.sessions_per_day
            self.maximum_construction_queue = max(self.maximum_construction_queue, self.construction_queue_size())
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

    def active_event_multiplier(self, customer):
        result = 1.0
        for event_id, _end in self.events:
            event = EVENTS[event_id]
            result *= event.get("all_customer_multiplier", 1)
            result *= event.get("customer_multipliers", {}).get(customer, 1)
        return result

    def preferred_active_contract_duration(self, customer):
        if self.active_event_multiplier(customer) >= 1.5:
            return "flexible"
        if (
            self.active_contract_term == "strategic"
            and self.relationship_level(customer)
            >= META["contract_durations"]["strategic"]["relationship_level_required"]
        ):
            return "strategic"
        return "standard"

    def locked_rate(self, customer, duration_id, premium=1.0):
        baseline = CUSTOMERS[customer]["era_baseline"].get(str(self.era), 0)
        if self.market_lock_mode == "era_baseline":
            market = baseline
        elif self.market_lock_mode == "instant":
            market = self.market_multiplier(customer)
        else:
            duration = META["contract_durations"][duration_id]["months"] * MONTH
            term_end = Simulator.now + duration
            cuts = sorted({
                Simulator.now,
                term_end,
                *(end for _event_id, end in self.events if Simulator.now < end < term_end),
            })
            integral = 0.0
            for start, end in zip(cuts, cuts[1:]):
                segment = baseline
                for event_id, event_end in self.events:
                    if event_end > start:
                        event = EVENTS[event_id]
                        segment *= event.get("all_customer_multiplier", 1)
                        segment *= event.get("customer_multipliers", {}).get(customer, 1)
                integral += segment * (end - start)
            market = integral / duration
        rate = market * premium
        if duration_id == "strategic" and self.strategic_cap_enabled:
            return min(rate, ECONOMY["contracts"]["strategic_lock_cap"])
        return rate

    def relationship_level(self, customer):
        result = 0
        for index, level in enumerate(META["relationships"]["levels"]):
            if self.customer_seconds.get(customer, 0.0) >= level["service_seconds"]:
                result = index
        return result

    def update_inquiries(self):
        settings = INQUIRIES["settings"]
        if self.total_built < settings["min_datacenters_built"]:
            return
        if self.next_inquiry <= 0:
            self.next_inquiry = Simulator.now
        while len(self.open_inquiries) < settings["max_open"] and Simulator.now >= self.next_inquiry:
            eligible = []
            for template_id, template in INQUIRIES["items"].items():
                customer = CUSTOMERS[template["customer_id"]]
                duration = META["contract_durations"][template["duration_id"]]
                if template["unlock_era"] > self.era or customer["unlock_era"] > self.era:
                    continue
                if template["minimum_network_level"] > self.network or customer["minimum_network_level"] > self.network:
                    continue
                if self.relationship_level(template["customer_id"]) < duration["relationship_level_required"]:
                    continue
                eligible.append((template_id, template))
            if not eligible:
                self.next_inquiry += self.inquiry_rng.uniform(
                    settings["arrival_months_min"], settings["arrival_months_max"]
                ) * MONTH
                return
            total_weight = sum(float(template["weight"]) for _template_id, template in eligible)
            roll = self.inquiry_rng.random() * total_weight
            selected_id, selected = eligible[-1]
            for candidate_id, candidate in eligible:
                roll -= float(candidate["weight"])
                if roll <= 0:
                    selected_id, selected = candidate_id, candidate
                    break
            self.inquiry_sequence += 1
            self.open_inquiries.append({
                "id": f"inquiry_{self.inquiry_sequence}",
                "template_id": selected_id,
                "arrived_at": self.next_inquiry,
            })
            self.next_inquiry += self.inquiry_rng.uniform(
                settings["arrival_months_min"], settings["arrival_months_max"]
            ) * MONTH

    def campus_specialization_active(self, dc, specialization_id):
        if self.strategy != "active":
            return False
        specialization = META["campus_specializations"].get(specialization_id, {})
        if not specialization or specialization.get("unlock_era", 1) > self.era:
            return False
        campus = campus_layout(self.dcs.index(dc) + 1)["campus_index"]
        campus_dcs = [
            item for index, item in enumerate(self.dcs, start=1)
            if campus_layout(index)["campus_index"] == campus
        ]
        requirements = specialization.get("requirements", {})
        kinds = [RACKS[rack_id]["kind"] for item in campus_dcs for rack_id in item.racks]
        customers = {item.customer for item in campus_dcs if item.customer}
        if requirements.get("rack_kind") and kinds.count(requirements["rack_kind"]) < requirements.get("rack_count", 0):
            return False
        if len(set(kinds)) < requirements.get("unique_rack_kinds", 0):
            return False
        return len(customers) >= requirements.get("unique_customers", 0)

    def inquiry_requirements_met(self, template, dc):
        if not dc.ready:
            return False
        requirements = template.get("requirements", {})
        kinds = [RACKS[rack_id]["kind"] for rack_id in dc.racks]
        if requirements.get("rack_kind") and kinds.count(requirements["rack_kind"]) < requirements.get("rack_count", 0):
            return False
        if len(set(kinds)) < requirements.get("unique_rack_kinds", 0):
            return False
        if self.network < requirements.get("network_level", 0):
            return False
        if self.relationship_level(template["customer_id"]) < requirements.get("relationship_level", 0):
            return False
        specialization = requirements.get("specialization")
        if specialization and not self.campus_specialization_active(dc, specialization):
            return False
        return True

    def adjust_one_rack_for_inquiry(self, template, dc):
        requirements = template.get("requirements", {})
        if any(key in requirements for key in ("network_level", "relationship_level", "specialization")):
            return False
        kinds = [RACKS[rack_id]["kind"] for rack_id in dc.racks]
        target_kind = requirements.get("rack_kind")
        replacement_index = -1
        if target_kind:
            if requirements.get("rack_count", 0) - kinds.count(target_kind) != 1:
                return False
            replacement_index = next((index for index, kind in enumerate(kinds) if kind != target_kind), -1)
        else:
            target_unique = requirements.get("unique_rack_kinds", 0)
            if target_unique - len(set(kinds)) != 1:
                return False
            absent = [kind for kind in ("compute", "storage", "gpu") if kind not in kinds]
            if not absent:
                return False
            target_kind = absent[0]
            replacement_index = next((index for index, kind in enumerate(kinds) if kinds.count(kind) > 1), -1)
        candidates = [
            (rack_id, rack) for rack_id, rack in RACKS.items()
            if rack["kind"] == target_kind and rack.get("unlock_era", 1) <= self.era
        ]
        if replacement_index < 0 or not candidates:
            return False
        rack_id, rack = min(candidates, key=lambda item: item[1]["cost"])
        if self.cash < rack["cost"]:
            return False
        original = dc.racks[replacement_index]
        dc.racks[replacement_index] = rack_id
        if not self.inquiry_requirements_met(template, dc):
            dc.racks[replacement_index] = original
            return False
        self.cash -= rack["cost"]
        return True

    def accept_available_inquiries(self):
        if self.strategy not in ("active", "idle"):
            return
        for inquiry in list(self.open_inquiries):
            template = INQUIRIES["items"][inquiry["template_id"]]
            accepted_dc = None
            for dc in self.dcs:
                if self.inquiry_requirements_met(template, dc):
                    accepted_dc = dc
                    break
            if accepted_dc is None and self.strategy == "active":
                for dc in self.dcs:
                    if dc.ready and self.adjust_one_rack_for_inquiry(template, dc):
                        accepted_dc = dc
                        break
            if accepted_dc is None:
                continue
            self.sign_inquiry(accepted_dc, template)
            self.open_inquiries.remove(inquiry)

    def sign_inquiry(self, dc, template):
        customer = template["customer_id"]
        duration_id = template["duration_id"]
        self.sign_customer(dc, customer, duration_id, template["premium"], force=True)
        projected = self.dc_monthly_income(dc)
        locked = dc.locked_market_multiplier
        dc.locked_market_multiplier = self.locked_rate(customer, duration_id, 1.0)
        baseline_projected = self.dc_monthly_income(dc)
        dc.locked_market_multiplier = locked
        dc.inquiry_contract = True
        dc.inquiry_revenue_fraction = max(0.0, projected - baseline_projected) / max(1.0, projected)
        bonus = projected * template["bonus_months"]
        self.cash += bonus
        self.revenue += bonus
        self.inquiry_bonus_revenue += bonus
        self.customer_seconds[customer] += template["bonus_service_seconds"]
        self.inquiries_accepted += 1

    def dc_monthly_income(self, dc):
        if not dc.ready or not dc.customer or Simulator.now - dc.built_at >= BUILDINGS[dc.building_id]["lifespan_seconds"]:
            return 0
        customer = CUSTOMERS[dc.customer]
        subtotal = 0
        kinds = set()
        raw_market = dc.locked_market_multiplier
        set_members = set_bonus_indices(dc.racks)
        set_multiplier = ECONOMY["layout"]["set_bonus_multiplier"]
        for index, rack_id in enumerate(dc.racks):
            fault_multiplier = (ECONOMY["faults"]["faulted_income_multiplier"] if self.cozy_faults else 0.0) if index in dc.faulted else 1.0
            rack = RACKS[rack_id]
            kinds.add(rack["kind"])
            sensitivity = rack.get("market_sensitivity", 1.0)
            effective_market = max(0, 1 + (raw_market - 1) * sensitivity)
            layout_multiplier = set_multiplier if index in set_members else 1.0
            subtotal += rack["income_per_month"] * customer["fit"][rack["kind"]] * effective_market * fault_multiplier * layout_multiplier
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
        relationship = META["relationships"]["levels"][0]
        served = self.customer_seconds.get(dc.customer, 0.0)
        for level in META["relationships"]["levels"]:
            if served >= level["service_seconds"]:
                relationship = level
        return subtotal * max(0, efficiency) * network * BUILDINGS[dc.building_id]["structure_multiplier"] * dc.contract_income_multiplier * relationship["income_multiplier"]

    def accrue(self):
        monthly_incomes = [(dc, self.dc_monthly_income(dc)) for dc in self.dcs]
        income = sum(value for _dc, value in monthly_incomes) * STEP / MONTH
        self.inquiry_contract_revenue += sum(
            value * dc.inquiry_revenue_fraction for dc, value in monthly_incomes if dc.inquiry_contract
        ) * STEP / MONTH
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
            self.negative_cash_months += 1
            self.debt = total_due - self.cash
            self.arrears += 1
            self.cash = 0
            self.missed_maintenance += 1

    def player_session(self):
        self.session_count += 1
        if self.debt > 0:
            self.arrears_online_seconds += AGGRESSIVE_SESSION_SECONDS if self.strategy == "aggressive" else 300.0
            if self.arrears_online_seconds >= ECONOMY["bankruptcy"]["takeover_after_online_seconds"]:
                self.process_bank_takeover()
        if not self.cozy_faults or self.strategy == "active":
            for dc in self.dcs:
                for index in list(dc.faulted):
                    cost = math.ceil(RACKS[dc.racks[index]]["cost"] * ECONOMY["faults"]["repair_cost_ratio"])
                    if self.cash >= cost:
                        self.cash -= cost
                        del dc.faulted[index]
        if self.strategy == "active":
            for dc in self.dcs:
                if not dc.ready:
                    continue
                if dc.customer and not dc.free_switch_available:
                    desired_duration = self.preferred_active_contract_duration(dc.customer)
                    if desired_duration != dc.contract_duration_id:
                        self.sign_customer(dc, dc.customer, desired_duration, force=True)
                    continue
                available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                self.switch_to_best_customer(dc, available)
        elif self.strategy == "aggressive":
            for dc in self.dcs:
                if not dc.ready:
                    continue
                self.switch_to_hottest_customer(dc, ("internet", "mining"))
        else:
            for dc in self.dcs:
                if dc.ready and not dc.customer:
                    self.sign_customer(dc, "internet")
        self.accept_available_inquiries()
        self.retire_old()
        self.maybe_upgrade_network()
        self.maybe_purchase_auto_retirement()
        self.maybe_purchase_construction_bays()
        # Passive owners check in twice but make one capital-allocation decision
        # per day; the other visit is collection/inspection only.
        if self.strategy == "idle" and self.session_count % 2 == 0:
            return
        attempts = 6 if self.strategy == "aggressive" else (max(1, self.queue_capacity() - 1) if self.strategy == "active" else 1)
        for _ in range(attempts):
            if not self.try_expand():
                break

    def process_bank_takeover(self):
        config = ECONOMY["bankruptcy"]
        candidates = sorted(
            (
                dc for dc in self.dcs
                if dc.ready and Simulator.now - dc.built_at < BUILDINGS[dc.building_id]["lifespan_seconds"]
            ),
            key=lambda dc: dc.built_at,
        )
        sold_ids = set()
        for dc in candidates:
            if self.debt <= 0:
                break
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            proceeds = round(self.retirement_value(dc, age) * config["takeover_value_ratio"])
            debt_paid = min(proceeds, self.debt)
            self.debt -= debt_paid
            self.cash += proceeds - debt_paid
            sold_ids.add(id(dc))
            self.bank_sold += 1
        if sold_ids:
            self.dcs = [dc for dc in self.dcs if id(dc) not in sold_ids]
        if self.debt > 0:
            self.debt_forgiven += self.debt
            self.debt = 0.0
        operational_remaining = any(
            dc.ready and Simulator.now - dc.built_at < BUILDINGS[dc.building_id]["lifespan_seconds"]
            for dc in self.dcs
        )
        relief = 0.0 if operational_remaining else max(0.0, config["relief_cash_floor"] - self.cash)
        self.cash += relief
        self.relief_received += relief
        self.takeovers += 1
        self.missed_maintenance = 0
        self.arrears_online_seconds = 0.0

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
            # Active play diversifies only among commercially credible bids; it
            # should never earn less than a passive fixed-client portfolio just
            # to force equal representation in the audit.
            portfolio_candidates = [customer for customer in available if values[customer] >= best_value * PORTFOLIO_THRESHOLD]
            total_seconds = sum(self.customer_seconds[customer] for customer in available) or 1.0
            choice = min(
                portfolio_candidates,
                key=lambda customer: (self.customer_seconds[customer] / total_seconds, contracted[customer], -values[customer]),
            )
        else:
            choice = max(viable, key=lambda customer: (-(contracted[customer]), values[customer]))
        if choice == dc.customer:
            desired_duration = self.preferred_active_contract_duration(choice)
            if dc.contract_duration_id != desired_duration:
                self.sign_customer(dc, choice, desired_duration, force=True)
            return
        fee = 0 if not dc.customer or free_switch else max(ECONOMY["contracts"]["minimum_breach_fee"], self.dc_monthly_income(dc) * ECONOMY["contracts"]["breach_fee_monthly_income_ratio"])
        if self.cash >= fee:
            self.cash -= fee
            self.sign_customer(dc, choice)

    def switch_to_hottest_customer(self, dc, available):
        # The aggressive cohort flips its whole speculative book between two
        # headline narratives and does not account for its own rack mix. That
        # creates genuine concentration/churn risk without making the underlying
        # data-center tiers unprofitable for sensible idle/active portfolios.
        headline = "mining" if self.session_count % 2 else "internet"
        choice = headline if headline in available else available[0]
        if choice == dc.customer:
            return
        fee = 0 if not dc.customer or dc.free_switch_available else max(
            ECONOMY["contracts"]["minimum_breach_fee"],
            self.dc_monthly_income(dc) * ECONOMY["contracts"]["breach_fee_monthly_income_ratio"],
        )
        if self.cash >= fee:
            self.cash -= fee
            self.sign_customer(dc, choice)

    def sign_customer(self, dc, customer, duration_id="standard", premium=1.0, force=False):
        if dc.customer == customer and not force:
            return
        dc.customer = customer
        relationship_index = 0
        for index, level in enumerate(META["relationships"]["levels"]):
            if self.customer_seconds.get(customer, 0.0) >= level["service_seconds"]:
                relationship_index = index
        if not force and self.strategy == "active":
            duration_id = self.preferred_active_contract_duration(customer)
        duration = META["contract_durations"][duration_id]
        dc.contract_duration_id = duration_id
        dc.locked_market_multiplier = self.locked_rate(customer, duration_id, premium)
        dc.contract_income_multiplier = duration["income_multiplier"]
        dc.contract_end_at = Simulator.now + duration["months"] * MONTH
        dc.free_switch_available = False
        dc.inquiry_contract = False
        dc.inquiry_revenue_fraction = 0.0

    def update_contracts(self):
        for dc in self.dcs:
            if dc.ready and not dc.customer:
                if self.strategy == "idle":
                    self.sign_customer(dc, "internet")
                else:
                    available = [key for key, value in CUSTOMERS.items() if value["unlock_era"] <= self.era and value["minimum_network_level"] <= self.network]
                    if self.strategy == "aggressive":
                        available = [key for key in ("internet", "mining") if key in available]
                    if self.strategy == "aggressive":
                        self.switch_to_hottest_customer(dc, available)
                    else:
                        self.switch_to_best_customer(dc, available)
            if not dc.customer:
                continue
            duration = META["contract_durations"].get(dc.contract_duration_id, META["contract_durations"]["standard"])
            duration_seconds = duration["months"] * MONTH
            if dc.contract_end_at <= 0:
                dc.contract_end_at = dc.ready_at + duration_seconds
            while Simulator.now >= dc.contract_end_at:
                dc.contract_end_at += duration_seconds
                dc.locked_market_multiplier = self.locked_rate(dc.customer, dc.contract_duration_id)
                dc.free_switch_available = True
                dc.inquiry_contract = False
                dc.inquiry_revenue_fraction = 0.0
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

    def maybe_purchase_auto_retirement(self):
        if self.auto_retirement or self.era < 2 or self.strategy == "aggressive":
            return
        upgrade = TECHNOLOGY["upgrades"]["auto_retirement"]["levels"]["1"]
        if self.cash >= upgrade["cost"]:
            self.cash -= upgrade["cost"]
            self.auto_retirement = True

    def queue_capacity(self):
        base = int(ECONOMY["construction"]["base_queue_capacity"])
        level = TECHNOLOGY["upgrades"].get("construction_bays", {}).get("levels", {}).get(str(self.construction_bays), {})
        return max(base, int(level.get("queue_capacity", base)))

    def construction_queue_size(self):
        return sum(not dc.ready for dc in self.dcs)

    def maybe_purchase_construction_bays(self):
        if self.strategy != "active" or self.construction_queue_size() < self.queue_capacity():
            return
        next_level = str(self.construction_bays + 1)
        level = TECHNOLOGY["upgrades"].get("construction_bays", {}).get("levels", {}).get(next_level)
        if not level or self.era < level.get("unlock_era", 1) or level.get("minimum_prestige", 0) > self.prestige_count:
            return
        # The active reference player buys a throughput upgrade once it is
        # affordable under real queue pressure, while retaining a modest
        # operating cushion rather than waiting to hold the purchase twice.
        if self.cash <= level["cost"] * 1.15:
            return
        self.cash -= level["cost"]
        self.construction_bays += 1
        self.construction_bay_purchases.append({
            "level": self.construction_bays,
            "at": Simulator.now,
            "built": self.total_built,
        })

    def ruin_scrap_value(self, dc):
        _racks, power, coolers = LOADOUTS[dc.building_id]
        aging = ECONOMY["aging"]
        value = BUILDINGS[dc.building_id]["cost"] * aging["ruin_building_scrap_ratio"]
        value += (ATTACHMENTS[power]["cost"] + sum(ATTACHMENTS[item]["cost"] for item in coolers)) * aging["ruin_attachment_scrap_ratio"]
        value += sum(RACKS[item]["cost"] for item in dc.racks) * aging["rack_refund_ratio"]
        return round(value)

    def retirement_value(self, dc, age):
        _racks, power, coolers = LOADOUTS[dc.building_id]
        aging = ECONOMY["aging"]
        value = BUILDINGS[dc.building_id]["cost"] * aging["retirement_building_refund_ratio"] * max(0, 1 - age)
        value += (ATTACHMENTS[power]["cost"] + sum(ATTACHMENTS[item]["cost"] for item in coolers)) * aging["attachment_refund_ratio"]
        value += sum(RACKS[item]["cost"] for item in dc.racks) * aging["rack_refund_ratio"]
        rounded = round(value)
        return max(rounded, self.ruin_scrap_value(dc) + 1) if age < 1 else rounded

    def process_auto_retirements(self):
        if not self.auto_retirement:
            return
        survivors = []
        for dc in self.dcs:
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            if age < ECONOMY["aging"]["auto_retire_progress"]:
                survivors.append(dc)
                continue
            self.cash += self.retirement_value(dc, age)
            self.auto_retirements += 1
        self.dcs = survivors

    def retire_old(self):
        survivors = []
        for dc in self.dcs:
            age = max(0, Simulator.now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            # A passive owner does not micromanage an early harvest: once Era 2
            # unlocks, the 95% technology above handles retirement for them.
            threshold = 0.95 if self.strategy == "idle" else (0.85 if self.strategy == "active" else 1.0)
            if age < threshold:
                survivors.append(dc)
                continue
            if age < 1:
                self.cash += self.retirement_value(dc, age)
            else:
                self.cash += self.ruin_scrap_value(dc)
        self.dcs = survivors

    def try_expand(self):
        if self.construction_queue_size() >= self.queue_capacity():
            return False
        reserve = {"idle": 1.4, "active": 1.05, "aggressive": 1.0}[self.strategy]
        if self.strategy == "active" and 10 <= self.total_built < ECONOMY["prestige"]["minimum_datacenters"]:
            reserve += (self.total_built - 9) * ACTIVE_PRESTIGE_RESERVE_STEP
        if not self.dcs:
            reserve = 1.0
        candidates = ["dc_t0"] if self.total_built == 0 else (["dc_t3", "dc_t2", "dc_t1"] if self.era >= 3 else (["dc_t2", "dc_t1"] if self.era >= 2 else ["dc_t1"]))
        for building_id in candidates:
            racks, power, coolers = LOADOUTS[building_id]
            if self.strategy == "aggressive" and building_id == "dc_t1":
                racks = ["rack_compute_t1"] * 3 + ["rack_storage_t1"] * 2
            needs_land = len(self.dcs) >= self.plots
            next_plot = self.plots + 1
            land = land_price(next_plot) if needs_land else 0
            package = BUILDINGS[building_id]["cost"] + ATTACHMENTS[power]["cost"] + sum(ATTACHMENTS[c]["cost"] for c in coolers) + sum(RACKS[r]["cost"] for r in racks) + land
            if self.cash < package * reserve:
                continue
            self.cash -= package
            self.total_built += 1
            self.build_start_times.append(Simulator.now)
            if self.total_built >= ECONOMY["prestige"]["minimum_datacenters"] and self.prestige_ready_at is None:
                self.prestige_ready_at = Simulator.now
            if needs_land:
                self.plots += 1
                self.land_spend += land
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
        total = self.cash
        for dc in self.dcs:
            age = max(0, now - dc.built_at) / BUILDINGS[dc.building_id]["lifespan_seconds"]
            total += self.retirement_value(dc, age) if age < 1 else self.ruin_scrap_value(dc)
        return total

    def record(self):
        day = Simulator.now / DAY
        if self.curve and abs(self.curve[-1][0] - day) < 0.5:
            return
        self.curve.append((day, self.net_worth(), self.cash, len(self.dcs), self.era, self.revenue, self.arrears, self.total_built, self.takeovers, self.bank_sold, self.land_spend))


def write_csv(results):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, sim in results.items():
        with (OUT / f"{name}.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["real_day", "net_worth", "cash", "datacenters", "era", "total_revenue", "arrears_count", "total_built", "takeovers", "bank_sold", "land_spend"])
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
        contract_end_at=META["contract_durations"]["standard"]["months"] * MONTH,
        locked_market_multiplier=baseline,
    )
    sim.dcs = [dc]
    before = sim.dc_monthly_income(dc)
    sim.events = [("mining_crash", META["contract_durations"]["standard"]["months"] * MONTH * 4)]
    during = sim.dc_monthly_income(dc)
    Simulator.now = dc.contract_end_at
    sim.update_contracts()
    after_renewal = sim.dc_monthly_income(dc)
    return math.isclose(before, during) and after_renewal < during and dc.free_switch_available


def contract_terms_probe():
    """Keep every authored term mechanically represented without changing cohorts."""
    terms = META["contract_durations"]
    return (
        set(terms) == {"flexible", "standard", "strategic"}
        and terms["flexible"]["months"] < terms["standard"]["months"] < terms["strategic"]["months"]
        and terms["flexible"]["income_multiplier"] < terms["standard"]["income_multiplier"] < terms["strategic"]["income_multiplier"]
        and terms["strategic"]["relationship_level_required"] > 0
    )


def strategic_lock_cap_probe():
    sim = Simulator("active", 31)
    Simulator.now = 0.0
    sim.era = 2
    sim.events = [("sovereign_ai", 12 * MONTH)]
    return (
        math.isclose(sim.locked_rate("gpu_company", "flexible"), 5.0)
        and math.isclose(sim.locked_rate("gpu_company", "standard"), 5.0)
        and math.isclose(sim.locked_rate("gpu_company", "strategic"), 2.5)
    )


def layout_set_probe():
    racks = ["rack_compute_t2"] * 3 + ["rack_storage_t2"] * 3 + ["rack_gpu_t1"] * 3
    members = set_bonus_indices(racks)
    sim = Simulator("active", 37)
    Simulator.now = 0.0
    dc = Datacenter("dc_t3", 0.0, 0.0, racks, customer="cloud", locked_market_multiplier=1.0)
    with_set = sim.dc_monthly_income(dc)
    original = ECONOMY["layout"]["set_bonus_multiplier"]
    ECONOMY["layout"]["set_bonus_multiplier"] = 1.0
    without_set = sim.dc_monthly_income(dc)
    ECONOMY["layout"]["set_bonus_multiplier"] = original
    diversity = CUSTOMERS["cloud"].get("diversity_multiplier", 1.0)
    return len(members) == 9 and math.isclose(diversity, 1.15) and math.isclose(with_set, without_set * original)


def rare_event_frequency_probe(seed_count=20, draws_per_seed=1000):
    eligible = [
        (event_id, event) for event_id, event in EVENTS.items()
        if event.get("minimum_era", 1) <= 3 and event.get("minimum_network_level", 1) <= 4
    ]
    total_weight = sum(float(event["weight"]) for _event_id, event in eligible)
    rare_weight = sum(float(event["weight"]) for _event_id, event in eligible if event.get("rare", False))
    expected = rare_weight / total_weight
    rare_draws = 0
    total_draws = seed_count * draws_per_seed
    for seed in range(seed_count):
        rng = random.Random(20260814 + seed * 101)
        for _draw in range(draws_per_seed):
            roll = rng.random() * total_weight
            selected = eligible[-1]
            for candidate in eligible:
                roll -= float(candidate[1]["weight"])
                if roll <= 0:
                    selected = candidate
                    break
            rare_draws += int(bool(selected[1].get("rare", False)))
    observed = rare_draws / total_draws
    return expected, observed, expected * 0.5 <= observed <= expected * 1.5


def _active_probe_cohort(seed, seed_count, **options):
    return [
        Simulator("active", seed + run * 101 + 1, **options).run(30)
        for run in range(max(1, seed_count))
    ]


def run_depth_attribution_probe(seed, seed_count):
    """B5's three-way lock-timing attribution; never mutates authored data."""
    groups = {
        # A is the pre-B3 counterfactual: a familiar active player uses the
        # longest lock and the rare quote is not capped.
        "A_event_timing_uncapped": _active_probe_cohort(
            seed, seed_count, market_lock_mode="instant",
            strategic_cap_enabled=False, active_contract_term="strategic",
        ),
        # B removes only event timing from the lock quote.
        "B_era_baseline_uncapped": _active_probe_cohort(
            seed, seed_count, market_lock_mode="era_baseline",
            strategic_cap_enabled=False, active_contract_term="strategic",
        ),
        # A' restores event timing under the shipped B3 strategic cap.
        "A_prime_event_timing_capped": _active_probe_cohort(
            seed, seed_count, market_lock_mode="instant",
            strategic_cap_enabled=True, active_contract_term="strategic",
        ),
    }
    means = {
        name: statistics.mean(sim.net_worth(sim.ended_at) for sim in cohort)
        for name, cohort in groups.items()
    }
    timing_gain = means["A_event_timing_uncapped"] - means["B_era_baseline_uncapped"]
    timing_share = timing_gain / max(1.0, means["A_event_timing_uncapped"])
    capped_gain = means["A_prime_event_timing_capped"] - means["B_era_baseline_uncapped"]
    capped_share = capped_gain / max(1.0, means["A_prime_event_timing_capped"])
    compression = 1.0 - capped_share / max(1e-9, timing_share)
    net_compression = 1.0 - means["A_prime_event_timing_capped"] / max(1.0, means["A_event_timing_uncapped"])
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "depth_attribution.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["group", "seed_count", "mean_day30_net_worth"])
        for name, value in means.items():
            writer.writerow([name, seed_count, f"{value:.2f}"])
        writer.writerow(["event_timing_share_uncapped", seed_count, f"{timing_share:.6f}"])
        writer.writerow(["event_timing_share_capped", seed_count, f"{capped_share:.6f}"])
        writer.writerow(["b3_share_compression", seed_count, f"{compression:.6f}"])
        writer.writerow(["b3_net_worth_compression", seed_count, f"{net_compression:.6f}"])
    return means, timing_share, capped_share, compression, net_compression


def run_t2_maintenance_probe(seed, seed_count):
    """B5's report-only T2 sweep; restore the production value on exit."""
    original = float(BUILDINGS["dc_t2"]["maintenance_per_month"])
    candidates = (900, 950, 1000, 1050, 1100, 1150)
    rows = []
    try:
        for candidate in candidates:
            BUILDINGS["dc_t2"]["maintenance_per_month"] = float(candidate)
            cohorts = {
                name: [
                    Simulator(name, seed + run * 101 + index).run(30)
                    for run in range(max(1, seed_count))
                ]
                for index, name in enumerate(("idle", "active", "aggressive"))
            }
            active_slopes = [
                (point_at(sim, 17)[1] - point_at(sim, 7)[1]) / 10.0
                for sim in cohorts["active"]
            ]
            rows.append({
                "maintenance": candidate,
                "active_day7_17_slope": statistics.mean(active_slopes),
                "idle_takeovers": sum(sim.takeovers for sim in cohorts["idle"]),
                "idle_debt_months": sum(sim.negative_cash_months for sim in cohorts["idle"]),
                "aggressive_takeover_rate": sum(sim.takeovers > 0 for sim in cohorts["aggressive"]) / len(cohorts["aggressive"]),
            })
    finally:
        BUILDINGS["dc_t2"]["maintenance_per_month"] = original
    baseline = next(row for row in rows if row["maintenance"] == 1150)
    for row in rows:
        row["slope_improvement"] = row["active_day7_17_slope"] / max(1.0, baseline["active_day7_17_slope"]) - 1.0
        row["constraints_pass"] = (
            row["idle_takeovers"] == 0
            and row["idle_debt_months"] == 0
            and 0.20 <= row["aggressive_takeover_rate"] <= 0.50
        )
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "t2_maintenance_sweep.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return rows


def retirement_harvest_probe():
    sim = Simulator("idle", 23)
    for building_id, (racks, _power, _coolers) in LOADOUTS.items():
        dc = Datacenter(building_id, 0.0, 0.0, list(racks))
        scrap = sim.ruin_scrap_value(dc)
        for step in range(600, 1000):
            if sim.retirement_value(dc, step / 1000.0) <= scrap:
                return False
    return True


def print_acceptance(results, cohorts, legacy_idle_cohort):
    active_day_1 = point_at(results["active"], 1)
    active_day_7 = point_at(results["active"], 7)
    idle_day_7 = point_at(results["idle"], 7)
    idle_ratio = idle_day_7[5] / active_day_7[5] if active_day_7[5] else 0
    legacy_idle_revenue = statistics.mean(sim.revenue for sim in legacy_idle_cohort) or 1.0
    idle_fault_loss = max(0.0, 1.0 - statistics.mean(sim.revenue for sim in cohorts["idle"]) / legacy_idle_revenue)
    rare_expected, rare_observed, rare_frequency_ok = rare_event_frequency_probe()
    active_idle_net_ratio = statistics.mean(sim.net_worth(sim.ended_at) for sim in cohorts["active"]) / max(1.0, statistics.mean(sim.net_worth(sim.ended_at) for sim in cohorts["idle"]))
    inquiry_accepts = [sim.inquiries_accepted for sim in cohorts["active"]]
    inquiry_revenue = sum(sim.inquiry_bonus_revenue + sim.inquiry_contract_revenue for sim in cohorts["active"])
    inquiry_share = inquiry_revenue / max(1.0, sum(sim.revenue for sim in cohorts["active"]))
    idle_revenue_monotonic = all(
        all(current[5] + 1e-6 >= previous[5] for previous, current in zip(sim.curve, sim.curve[1:]))
        for sim in cohorts["idle"]
    )
    bay_buyers = [sim for sim in cohorts["active"] if sim.construction_bay_purchases]
    bay_before = 0
    bay_after = 0
    bay_windows = 0
    for sim in bay_buyers:
        for purchase in sim.construction_bay_purchases:
            at = purchase["at"]
            if at + 5 * DAY > sim.ended_at:
                continue
            bay_before += sum(at - 5 * DAY <= started < at for started in sim.build_start_times)
            bay_after += sum(at <= started < at + 5 * DAY for started in sim.build_start_times)
            bay_windows += 1
    checks = [
        (campus_layout(6)["type_id"] == "type_1" and campus_layout(7)["type_id"] == "type_2" and campus_layout(15)["campus_index"] == 2, "campus sequence partitions unlimited plots into a 6-slot starter page followed by 8-slot expansion pages"),
        (math.isclose(land_price(7) / round(ECONOMY["land"]["base_price"] * (1.0 + ECONOMY["land"]["growth_step"] * 6) ** ECONOMY["land"]["growth_exponent"]), 1.08, rel_tol=0.001), "expansion-campus land premium stays at the intended modest 8%"),
        (contract_locking_probe(), "mining downturn leaves an existing contract unchanged until automatic renewal"),
        (contract_terms_probe(), "flexible, standard, and relationship-gated strategic terms preserve their authored risk/reward order"),
        (strategic_lock_cap_probe(), "five-times rare quotes remain uncapped for flexible/standard terms and cap strategic locks at 2.5x"),
        (layout_set_probe(), "three same-kind rows receive one 1.10x set bonus while retaining the cloud 1.15x diversity bonus"),
        (rare_frequency_ok, f"rare-event share is {rare_observed:.2%} versus authored {rare_expected:.2%} (within ±50%)"),
        (min(inquiry_accepts) >= 3, f"active inquiry accepts range {min(inquiry_accepts)}–{max(inquiry_accepts)} in 30 days (target every seed >=3)"),
        (inquiry_share <= 0.35, f"inquiry-attributable premium and signing bonuses are {inquiry_share:.1%} of active revenue (target <=35%)"),
        (idle_revenue_monotonic, "idle cumulative revenue never declines while persistent inquiries are ignored"),
        (len(bay_buyers) > 0, f"engineering expansion is purchased in {len(bay_buyers)}/{len(cohorts['active'])} active seeds that reach simultaneous cash and queue pressure"),
        (bay_windows > 0 and bay_after > bay_before, f"engineering expansion raises five-day build starts from {bay_before} before to {bay_after} after across {bay_windows} measured purchase windows"),
        (all(sim.maximum_construction_queue <= sim.queue_capacity() for sims in cohorts.values() for sim in sims), "every simulated build queue stays within its authored 2–5 lane capacity"),
        (active_idle_net_ratio <= 25.0, f"active/idle day-30 net-worth ratio is {active_idle_net_ratio:.2f}x (target <=25x)"),
        (retirement_harvest_probe(), "normal retirement beats ruin scrap for every loadout at each 0.1% step from 60.0% through 99.9% lifespan"),
        (idle_fault_loss < 0.08, f"passive auto-repair curve loses {idle_fault_loss:.1%} versus the same-seed pre-A4 fault model (target <8%)"),
        (2 <= active_day_1[3] <= 3 and active_day_1[2] > 0, "day 1 active player has 2–3 data centers and positive cash"),
        (6 <= active_day_7[3] <= 10 and active_day_7[4] >= 2, "day 7 active player has 6–10 data centers and reaches era 2"),
        (0.4 <= idle_ratio <= 0.6, f"day 7 idle revenue is {idle_ratio:.0%} of active revenue"),
    ]
    aggressive_rate = sum(sim.takeovers > 0 for sim in cohorts["aggressive"]) / len(cohorts["aggressive"])
    all_runs = [sim for sims in cohorts.values() for sim in sims]
    idle_takeovers = sum(sim.takeovers for sim in cohorts["idle"])
    idle_negative_months = sum(sim.negative_cash_months for sim in cohorts["idle"])
    all_positive = all(sim.net_worth(sim.ended_at) > 0 for sim in all_runs)
    aggressive_day_27 = statistics.mean(point_at(sim, 27)[1] for sim in cohorts["aggressive"])
    aggressive_day_30 = statistics.mean(sim.net_worth(sim.ended_at) for sim in cohorts["aggressive"])
    relief_floor = float(ECONOMY["bankruptcy"]["relief_cash_floor"])
    aggressive_recoverable = all(sim.net_worth(sim.ended_at) >= relief_floor for sim in cohorts["aggressive"])
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
        (idle_takeovers == 0 and idle_negative_months == 0, f"idle cohort has {idle_takeovers} takeovers and {idle_negative_months} debt-producing months (target 0/0)"),
        (0.20 <= aggressive_rate <= 0.50, f"aggressive bank-takeover incidence is {aggressive_rate:.0%} (target 20–50%)"),
        (all_positive and aggressive_recoverable, f"every run ends positive and every aggressive save retains at least the ${relief_floor:,.0f} recovery floor (day 27 ${aggressive_day_27:,.0f}; day 30 ${aggressive_day_30:,.0f})"),
    ])
    for passed, description in checks:
        print(f"{'PASS' if passed else 'TUNE'}: {description}")
    aggressive = results["aggressive"]
    coverage = aggressive.minimum_maintenance_coverage
    print(f"INFO: representative aggressive arrears={aggressive.arrears}; minimum maintenance coverage={coverage:.2f}x")
    diversified = all(len({RACKS[rack]["kind"] for rack in loadout[0]}) >= 2 for key, loadout in LOADOUTS.items() if key != "dc_t0")
    print(f"{'PASS' if diversified else 'TUNE'}: every post-tutorial reference loadout uses at least two rack kinds")
    grouped = all(bool(set_bonus_indices(loadout[0])) for key, loadout in LOADOUTS.items() if key != "dc_t0")
    print(f"{'PASS' if grouped else 'TUNE'}: every post-tutorial reference loadout preserves diversity while forming at least one same-kind row")


def main():
    global ACTIVE_PRESTIGE_RESERVE_STEP, AGGRESSIVE_SESSION_SECONDS, AGGRESSIVE_SESSIONS_PER_DAY, PORTFOLIO_THRESHOLD
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260802)
    parser.add_argument("--seed-count", type=int, default=20)
    parser.add_argument("--maintenance-scale", type=float, default=1.0, help="Calibration-only multiplier for T2/T3 maintenance")
    parser.add_argument("--maintenance-t2-scale", type=float, default=None, help="Override the T2 calibration multiplier")
    parser.add_argument("--maintenance-t3-scale", type=float, default=None, help="Override the T3 calibration multiplier")
    parser.add_argument("--portfolio-threshold", type=float, default=0.60, help="Calibration-only active-bid viability threshold")
    parser.add_argument("--active-prestige-reserve-step", type=float, default=1.8, help="Calibration-only reserve growth before first prestige")
    parser.add_argument("--aggressive-session-seconds", type=float, default=21600.0, help="Calibration-only online time per aggressive session")
    parser.add_argument("--aggressive-sessions-per-day", type=int, default=6, help="Calibration-only aggressive check-in frequency")
    parser.add_argument("--active-contract-term", choices=("standard", "strategic"), default="standard", help="Reference active cohort's preferred term once eligible")
    parser.add_argument("--run-depth-probes", action="store_true", help="Write the report-only B5 attribution and T2 maintenance sweep CSVs")
    parser.add_argument("--no-write", action="store_true", help="Do not replace the canonical CSV/SVG outputs")
    args = parser.parse_args()
    PORTFOLIO_THRESHOLD = args.portfolio_threshold
    ACTIVE_PRESTIGE_RESERVE_STEP = args.active_prestige_reserve_step
    AGGRESSIVE_SESSION_SECONDS = args.aggressive_session_seconds
    AGGRESSIVE_SESSIONS_PER_DAY = args.aggressive_sessions_per_day
    BUILDINGS["dc_t2"]["maintenance_per_month"] *= args.maintenance_t2_scale if args.maintenance_t2_scale is not None else args.maintenance_scale
    BUILDINGS["dc_t3"]["maintenance_per_month"] *= args.maintenance_t3_scale if args.maintenance_t3_scale is not None else args.maintenance_scale
    strategy_names = ("idle", "active", "aggressive")
    cohorts = {
        name: [
            Simulator(
                name,
                args.seed + run * 101 + index,
                active_contract_term=args.active_contract_term if name == "active" else "standard",
            ).run(args.days)
            for run in range(max(1, args.seed_count))
        ]
        for index, name in enumerate(strategy_names)
    }
    legacy_idle_cohort = [Simulator("idle", args.seed + run * 101, cozy_faults=False).run(args.days) for run in range(max(1, args.seed_count))]
    results = {name: cohorts[name][0] for name in strategy_names}
    if not args.no_write:
        write_csv(results)
        write_svg(results)
    for name, sim in results.items():
        print(f"{name:10s} day={sim.ended_at / DAY:.0f} dc={len(sim.dcs):2d} era={sim.era} revenue=${sim.revenue:,.0f} net=${sim.net_worth(sim.ended_at):,.0f} land=${sim.land_spend:,.0f} min_cash=${sim.minimum_cash:,.0f} arrears={sim.arrears} takeovers={sim.takeovers} sold={sim.bank_sold} inquiries={sim.inquiries_accepted} queue={sim.maximum_construction_queue}/{sim.queue_capacity()} bays={sim.construction_bays}")
    print_acceptance(results, cohorts, legacy_idle_cohort)
    if args.run_depth_probes:
        means, timing_share, capped_share, compression, net_compression = run_depth_attribution_probe(args.seed, args.seed_count)
        print("B5 ATTRIBUTION: " + ", ".join(f"{name}=${value:,.0f}" for name, value in means.items()))
        print(f"B5 ATTRIBUTION: event timing share {timing_share:.1%} uncapped -> {capped_share:.1%} capped; share compression {compression:.1%}; net-worth compression {net_compression:.1%}")
        maintenance_rows = run_t2_maintenance_probe(args.seed, args.seed_count)
        for row in maintenance_rows:
            print(
                "B5 T2: ${maintenance}/mo slope=${active_day7_17_slope:,.0f}/day "
                "improvement={slope_improvement:.1%} idle={idle_takeovers}/{idle_debt_months} "
                "aggressive={aggressive_takeover_rate:.0%} constraints={constraints_pass}".format(**row)
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
