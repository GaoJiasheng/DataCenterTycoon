extends Node

const AUTOSAVE_SECONDS := 30.0
const MAX_ADVANCE_ITERATIONS := 20000
const Rules := preload("res://gameplay/game_rules.gd")
const Market := preload("res://gameplay/market_system.gd")

var state: Dictionary = {}
var data: Dictionary = {}
var last_offline_report: Dictionary = {}
var _market := Market.new()
var _tick_accumulator := 0.0
var _autosave_accumulator := 0.0
var _in_background := false
var _pending_purchases: Dictionary = {}
var _pending_rewards: Dictionary = {}
var persistence_enabled := true

func _ready() -> void:
	data = DataRepository.tables
	state = SaveManager.load_save()
	if state.is_empty():
		state = _new_state()
	_ensure_state_shape()
	_market.ensure_state(state, data)
	_apply_locale()
	AudioService.apply_settings(state.get("settings", {}))
	Monetization.reward_result.connect(_on_reward_result)
	Monetization.purchase_result.connect(_on_purchase_result)
	_settle_wall_gap()
	set_process(true)

func _process(delta: float) -> void:
	if _in_background or state.get("bankruptcy", {}).get("status", "normal") == "game_over":
		return
	_tick_accumulator += delta
	_autosave_accumulator += delta
	if _tick_accumulator >= 1.0:
		var step := _tick_accumulator
		_tick_accumulator = 0.0
		advance_time(step, false)
	if _autosave_accumulator >= AUTOSAVE_SECONDS:
		_autosave_accumulator = 0.0
		save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_in_background = true
		save_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_in_background = false
		_settle_wall_gap()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()

func save_now() -> bool:
	if state.is_empty() or not persistence_enabled:
		return false
	var now := GameClock.wall_time()
	state["clock"]["last_wall_time"] = now
	state["clock"]["highest_wall_time"] = maxi(int(state["clock"].get("highest_wall_time", now)), now)
	return SaveManager.write_save(state)

func advance_time(real_seconds: float, offline: bool) -> Dictionary:
	var report := {
		"elapsed_seconds": maxf(0.0, real_seconds),
		"credited_seconds": 0.0,
		"income": 0.0,
		"completed": [],
		"faults": [],
		"events": [],
		"contracts": [],
		"aging": [],
	}
	if real_seconds <= 0.0 or state.get("bankruptcy", {}).get("status", "normal") == "game_over":
		return report
	var financial_remaining := real_seconds
	if offline:
		financial_remaining = minf(real_seconds, offline_income_cap_seconds())
	report["credited_seconds"] = financial_remaining
	var remaining := real_seconds
	var iterations := 0
	while remaining > 0.0001 and iterations < MAX_ADVANCE_ITERATIONS:
		iterations += 1
		var now := simulation_time()
		var financial := financial_remaining > 0.0001
		var max_step := 240.0 if financial else 7200.0
		var step := minf(remaining, max_step)
		if financial:
			step = minf(step, financial_remaining)
		var boundary := _next_boundary_after(now, financial)
		if boundary < INF:
			step = minf(step, maxf(0.05, boundary - now))
		if financial:
			var earned := _accrue_income(step)
			report["income"] = float(report["income"]) + earned
			financial_remaining -= step
		state["clock"]["simulation_seconds"] = now + step
		if not offline and state.get("bankruptcy", {}).get("status", "normal") == "arrears":
			state["bankruptcy"]["arrears_online_seconds"] = float(state["bankruptcy"].get("arrears_online_seconds", 0.0)) + step
		_process_due(financial, offline, report)
		remaining -= step
	if iterations >= MAX_ADVANCE_ITERATIONS and remaining > 0.0001:
		push_warning("Advance iteration cap reached; coarsely advancing %.1f seconds" % remaining)
		state["clock"]["simulation_seconds"] = simulation_time() + remaining
		_process_due(false, offline, report)
	_check_era_unlocks()
	_check_achievements()
	_update_highest_net_worth()
	EventBus.state_changed.emit("offline_advance" if offline else "tick")
	return report

func simulation_time() -> float:
	return float(state.get("clock", {}).get("simulation_seconds", 0.0))

func offline_income_cap_seconds() -> float:
	var offline: Dictionary = data.get("economy", {}).get("offline", {})
	if has_entitlement("offline24"):
		return float(offline.get("extended_income_cap_seconds", 86400.0))
	return float(offline.get("base_income_cap_seconds", 28800.0))

func monthly_income() -> float:
	var result := 0.0
	for plot: Dictionary in state.get("plots", []):
		if plot.get("datacenter") is Dictionary:
			result += datacenter_monthly_income(plot["datacenter"])
	return result

func datacenter_monthly_income(datacenter: Dictionary) -> float:
	return Rules.datacenter_income_per_month(datacenter, state, data, func(customer_id: String) -> float: return _market.customer_multiplier(customer_id, state, data))

func market_multiplier(customer_id: String) -> float:
	return _market.customer_multiplier(customer_id, state, data)

func contract_market_multiplier(customer_id: String) -> float:
	return _market.customer_multiplier(customer_id, state, data, false)

func rack_purchase_cost(rack_id: String) -> float:
	var rack: Dictionary = data.get("racks", {}).get("items", {}).get(rack_id, {})
	return float(rack.get("cost", 0.0)) * _market.purchase_multiplier(str(rack.get("kind", "")), state, data)

func monthly_maintenance() -> float:
	var result := 0.0
	for plot: Dictionary in state.get("plots", []):
		if plot.get("datacenter") is Dictionary:
			result += Rules.datacenter_maintenance(plot["datacenter"], data.get("buildings", {}))
	return result

func net_worth() -> float:
	return Rules.total_net_worth(state, data)

func next_plot_price() -> float:
	return Rules.land_price(state.get("plots", []).size() + 1, data.get("economy", {}))

func buy_next_plot() -> Dictionary:
	var index: int = state.get("plots", []).size() + 1
	var price := Rules.land_price(index, data.get("economy", {}))
	if not _spend_cash(price):
		return _failure("not_enough_cash")
	state["plots"].append({"id": "plot_%d" % index, "index": index, "purchase_price": price, "purchased": true, "status": "empty", "datacenter": null})
	_tutorial_event("plot_bought")
	_commit_action("plot_bought")
	return _success({"plot_id": "plot_%d" % index, "price": price})

func start_datacenter_construction(plot_id: String, building_id: String) -> Dictionary:
	var plot := find_plot(plot_id)
	var building: Dictionary = data.get("buildings", {}).get("items", {}).get(building_id, {})
	if plot.is_empty() or plot.get("status", "") != "empty":
		return _failure("plot_unavailable")
	if building.is_empty() or not is_unlocked(building):
		return _failure("locked")
	if bool(building.get("tutorial_only", false)) and bool(state.get("flags", {}).get("standard_built", false)):
		return _failure("tutorial_building_retired")
	if not _queue_has_capacity():
		return _failure("queue_full")
	var cost := float(building.get("cost", 0.0))
	if not _spend_cash(cost):
		return _failure("not_enough_cash")
	var build_seconds := _tutorial_duration(building, "tutorial_build_seconds", float(building.get("build_seconds", 0.0)))
	var item := _queue_item("datacenter", build_seconds)
	item.merge({"plot_id": plot_id, "building_id": building_id, "cost": cost})
	state["construction_queue"].append(item)
	plot["status"] = "building"
	plot["construction_id"] = item["id"]
	_tutorial_event("%s_started" % building_id)
	AudioService.play_sfx("sfx_build_start")
	_commit_action("datacenter_started")
	return _success({"construction": item})

# Shortened first-run timings. Only the specific items the tutorial walks the
# player through carry an override, and only until the tutorial completes, so
# ordinary pacing and the balance model are untouched afterwards.
func _tutorial_duration(entry: Dictionary, override_key: String, fallback: float) -> float:
	if bool(state.get("tutorial", {}).get("completed", false)):
		return fallback
	return float(entry.get(override_key, fallback))

func install_rack(datacenter_id: String, slot: int, rack_id: String) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	var rack: Dictionary = data.get("racks", {}).get("items", {}).get(rack_id, {})
	if dc.is_empty() or dc.get("status", "") != "operational":
		return _failure("datacenter_unavailable")
	if rack.is_empty() or not is_unlocked(rack):
		return _failure("locked")
	var building: Dictionary = data.get("buildings", {}).get("items", {}).get(dc.get("building_id", ""), {})
	var slot_unlocked := false
	for unlocked_slot: Variant in building.get("unlocked_slots", []):
		if int(unlocked_slot) == slot:
			slot_unlocked = true
			break
	if not slot_unlocked or slot < 0 or slot >= 9:
		return _failure("slot_locked")
	if dc["racks"][slot] != null:
		return _failure("slot_occupied")
	var installing := 0
	for entry: Variant in dc.get("racks", []):
		if entry is Dictionary and entry.get("status", "") == "installing":
			installing += 1
	if installing >= int(data.get("economy", {}).get("construction", {}).get("rack_install_capacity_per_datacenter", 2)):
		return _failure("rack_install_limit")
	var cost := rack_purchase_cost(rack_id)
	if not _spend_cash(cost):
		return _failure("not_enough_cash")
	var started := simulation_time()
	var installed := {
		"rack_id": rack_id,
		"status": "installing",
		"enabled": true,
		"started_at": started,
		"install_complete_at": started + _tutorial_duration(rack, "tutorial_install_seconds", float(rack.get("install_seconds", 0.0))),
		"ad_uses": 0,
		"cost": cost,
	}
	dc["racks"][slot] = installed
	_commit_action("rack_started")
	return _success({"rack_installation": installed.duplicate(true), "datacenter_id": datacenter_id, "slot": slot})

func uninstall_rack(datacenter_id: String, slot: int) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	if dc.is_empty() or dc.get("status", "") != "operational" or slot < 0 or slot >= dc.get("racks", []).size():
		return _failure("invalid_slot")
	var installed: Variant = dc["racks"][slot]
	if not installed is Dictionary or installed.is_empty() or installed.get("status", "") == "installing":
		return _failure("slot_empty")
	var rack: Dictionary = data.get("racks", {}).get("items", {}).get(installed.get("rack_id", ""), {})
	var refund: float = round(float(rack.get("cost", 0.0)) * float(data.get("economy", {}).get("aging", {}).get("rack_refund_ratio", 0.5)))
	state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + refund
	dc["racks"][slot] = null
	_reschedule_dc_faults(dc)
	_commit_action("rack_uninstalled")
	return _success({"refund": refund})

func set_rack_enabled(datacenter_id: String, slot: int, enabled: bool) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	var installed := _installed_rack(datacenter_id, slot)
	if dc.is_empty() or installed.is_empty() or installed.get("status", "") != "active":
		return _failure("rack_unavailable")
	if bool(installed.get("enabled", true)) == enabled:
		return _success({"enabled": enabled})
	installed["enabled"] = enabled
	installed["fault_at"] = -1.0
	_reschedule_dc_faults(dc)
	_commit_action("rack_power_changed")
	return _success({"enabled": enabled})

func install_power(datacenter_id: String, power_id: String) -> Dictionary:
	return _install_attachment(datacenter_id, power_id, "power", "")

func install_cooler(datacenter_id: String, edge: String, cooler_id: String) -> Dictionary:
	if not Rules.COOLER_EDGES.has(edge):
		return _failure("invalid_edge")
	return _install_attachment(datacenter_id, cooler_id, "cooler", edge)

func sign_contract(datacenter_id: String, customer_id: String) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	var customer: Dictionary = data.get("customers", {}).get("items", {}).get(customer_id, {})
	if dc.is_empty() or dc.get("status", "") != "operational":
		return _failure("datacenter_unavailable")
	if customer.is_empty() or int(customer.get("unlock_era", 1)) > int(state["player"].get("era", 1)) or int(customer.get("minimum_network_level", 1)) > int(state["player"].get("network_level", 1)):
		return _failure("locked")
	var previous := str(dc.get("customer_id", ""))
	if previous == customer_id:
		return _success({"breach_fee": 0.0, "unchanged": true, "locked_market_multiplier": float(dc.get("locked_market_multiplier", contract_market_multiplier(customer_id)))})
	var fee := contract_switch_fee(datacenter_id, customer_id)
	if not previous.is_empty() and previous != customer_id:
		if not _spend_cash(fee):
			return _failure("not_enough_cash")
	dc["customer_id"] = customer_id
	dc["locked_market_multiplier"] = contract_market_multiplier(customer_id)
	dc["contract_end_at"] = simulation_time() + float(data.get("economy", {}).get("contracts", {}).get("duration_seconds", 43200.0))
	dc["free_switch_available"] = false
	state["stats"]["contracts_signed"] = int(state["stats"].get("contracts_signed", 0)) + 1
	_tutorial_event("contract_signed")
	_commit_action("contract_signed")
	return _success({"breach_fee": fee})

func contract_switch_fee(datacenter_id: String, customer_id: String) -> float:
	var dc := find_datacenter(datacenter_id)
	if dc.is_empty() or str(dc.get("customer_id", "")).is_empty() or dc.get("customer_id", "") == customer_id:
		return 0.0
	if bool(dc.get("free_switch_available", false)):
		return 0.0
	var config: Dictionary = data.get("economy", {}).get("contracts", {})
	return maxf(float(config.get("minimum_breach_fee", 25.0)), datacenter_monthly_income(dc) * float(config.get("breach_fee_monthly_income_ratio", 0.25)))

func dispatch_repair(datacenter_id: String, slot: int) -> Dictionary:
	var installed := _installed_rack(datacenter_id, slot)
	if installed.is_empty() or installed.get("status", "") != "faulted":
		return _failure("not_faulted")
	var rack: Dictionary = data.get("racks", {}).get("items", {}).get(installed.get("rack_id", ""), {})
	var cost: float = ceil(float(rack.get("cost", 0.0)) * float(data.get("economy", {}).get("faults", {}).get("repair_cost_ratio", 0.05)))
	if not _spend_cash(cost):
		return _failure("not_enough_cash")
	var faults: Dictionary = data.get("economy", {}).get("faults", {})
	var duration := lerpf(float(faults.get("repair_seconds_min", 600.0)), float(faults.get("repair_seconds_max", 1800.0)), _random())
	duration *= _repair_time_multiplier()
	installed["status"] = "repairing"
	installed.erase("auto_repair_at")
	installed["repair_complete_at"] = simulation_time() + duration
	AudioService.play_sfx("sfx_repair")
	_commit_action("repair_started")
	return _success({"cost": cost, "duration": duration})

func instant_repair_with_gems(datacenter_id: String, slot: int) -> Dictionary:
	var installed := _installed_rack(datacenter_id, slot)
	if installed.is_empty() or installed.get("status", "") != "faulted":
		return _failure("not_faulted")
	var gems := int(data.get("economy", {}).get("faults", {}).get("instant_repair_gems", 2))
	if int(state["player"].get("gems", 0)) < gems:
		return _failure("not_enough_gems")
	state["player"]["gems"] = int(state["player"].get("gems", 0)) - gems
	_complete_repair(datacenter_id, slot)
	_commit_action("repair_instant")
	return _success({"gems": gems})

func retire_datacenter(datacenter_id: String) -> Dictionary:
	var plot := find_plot_for_datacenter(datacenter_id)
	if plot.is_empty():
		return _failure("datacenter_missing")
	var dc: Dictionary = plot["datacenter"]
	if dc.get("status", "") != "operational":
		return _failure("datacenter_unavailable")
	if _has_jobs_for_datacenter(datacenter_id):
		return _failure("construction_in_progress")
	var progress := Rules.age_progress(dc, simulation_time(), data.get("buildings", {}))
	if progress < float(data.get("economy", {}).get("aging", {}).get("aging_start", 0.6)):
		return _failure("too_new_to_retire")
	var refund := Rules.retirement_value(dc, simulation_time(), data)
	state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + refund
	plot["datacenter"] = null
	plot["status"] = "empty"
	state["stats"]["datacenters_retired"] = int(state["stats"].get("datacenters_retired", 0)) + 1
	_tutorial_event("dc_retired")
	AudioService.play_sfx("sfx_retire")
	_commit_action("datacenter_retired")
	return _success({"refund": refund})

func demolish_ruin(datacenter_id: String) -> Dictionary:
	var plot := find_plot_for_datacenter(datacenter_id)
	if plot.is_empty() or plot.get("datacenter", {}).get("status", "") != "ruined":
		return _failure("not_ruined")
	var cost := Rules.demolition_cost(plot["datacenter"], data)
	if not _spend_cash(cost):
		return _failure("not_enough_cash")
	plot["datacenter"] = null
	plot["status"] = "empty"
	_commit_action("ruin_demolished")
	return _success({"cost": cost})

func upgrade_network() -> Dictionary:
	var next_level := int(state["player"].get("network_level", 1)) + 1
	var level: Dictionary = data.get("technology", {}).get("network", {}).get(str(next_level), {})
	if level.is_empty() or not is_unlocked(level):
		return _failure("locked")
	for pending: Dictionary in state.get("construction_queue", []):
		if pending.get("type", "") == "network":
			return _failure("construction_in_progress")
	if not _queue_has_capacity():
		return _failure("queue_full")
	if not _spend_cash(float(level.get("cost", 0.0))):
		return _failure("not_enough_cash")
	var item := _queue_item("network", float(level.get("build_seconds", 0.0)))
	item.merge({"level": next_level, "cost": float(level.get("cost", 0.0))})
	state["construction_queue"].append(item)
	_commit_action("network_upgrade_started")
	return _success({"construction": item})

func upgrade_repair_team() -> Dictionary:
	var current := int(state.get("technology", {}).get("repair_team", 1))
	var next := current + 1
	var level: Dictionary = data.get("technology", {}).get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(str(next), {})
	if level.is_empty() or not is_unlocked(level):
		return _failure("locked")
	if not _spend_cash(float(level.get("cost", 0.0))):
		return _failure("not_enough_cash")
	state["technology"]["repair_team"] = next
	_commit_action("repair_team_upgraded")
	return _success({"level": next})

func speed_up_construction_with_gems(construction_id: String) -> Dictionary:
	var item := find_construction(construction_id)
	if item.is_empty():
		return _failure("construction_missing")
	var remaining := maxf(0.0, float(item.get("complete_at", 0.0)) - simulation_time())
	var gems := maxi(1, int(ceil(remaining / 600.0)) * int(data.get("economy", {}).get("construction", {}).get("gems_per_600_seconds", 1)))
	if int(state["player"].get("gems", 0)) < gems:
		return _failure("not_enough_gems")
	state["player"]["gems"] = int(state["player"].get("gems", 0)) - gems
	item["complete_at"] = simulation_time()
	var report := {"completed": [], "faults": [], "events": [], "contracts": [], "aging": []}
	_process_due(true, false, report)
	_commit_action("construction_sped_up")
	return _success({"gems": gems})

func speed_up_rack_install_with_gems(datacenter_id: String, slot: int) -> Dictionary:
	var installed := _installed_rack(datacenter_id, slot)
	if installed.is_empty() or installed.get("status", "") != "installing":
		return _failure("rack_unavailable")
	var remaining := maxf(0.0, float(installed.get("install_complete_at", 0.0)) - simulation_time())
	var gems := maxi(1, int(ceil(remaining / 600.0)) * int(data.get("economy", {}).get("construction", {}).get("gems_per_600_seconds", 1)))
	if int(state["player"].get("gems", 0)) < gems:
		return _failure("not_enough_gems")
	state["player"]["gems"] = int(state["player"].get("gems", 0)) - gems
	installed["install_complete_at"] = simulation_time()
	var report := {"completed": [], "faults": [], "events": [], "contracts": [], "aging": []}
	_process_due(true, false, report)
	_commit_action("rack_install_sped_up")
	return _success({"gems": gems})

func use_instant_build_ticket(construction_id: String) -> Dictionary:
	var item := find_construction(construction_id)
	if item.is_empty():
		return _failure("construction_missing")
	if int(state.get("inventory", {}).get("instant_build_tickets", 0)) <= 0:
		return _failure("ticket_unavailable")
	state["inventory"]["instant_build_tickets"] = int(state["inventory"].get("instant_build_tickets", 0)) - 1
	item["complete_at"] = simulation_time()
	var report := {"completed": [], "faults": [], "events": [], "contracts": [], "aging": []}
	_process_due(true, false, report)
	_commit_action("instant_build_ticket")
	return _success()

func prestige() -> Dictionary:
	var config: Dictionary = data.get("economy", {}).get("prestige", {})
	if int(state["player"].get("total_datacenters_built", 0)) < int(config.get("minimum_datacenters", 20)):
		return _failure("prestige_locked")
	var worth := net_worth()
	var raw_gain := 1.0 + float(config.get("log_coefficient", 0.15)) * log(maxf(1.0, worth / float(config.get("net_worth_anchor", 100000.0)))) / log(10.0)
	var gain := clampf(raw_gain, float(config.get("minimum_gain", 1.05)), float(config.get("maximum_gain", 1.6)))
	var kept := _account_state_snapshot()
	kept.merge({
		"era": int(state["player"].get("era", 1)),
		"network_level": int(state["player"].get("network_level", 1)),
		"brand_multiplier": float(state["player"].get("brand_multiplier", 1.0)) * gain,
		"prestige_count": int(state["stats"].get("prestige_count", 0)) + 1,
		"tutorial": state.get("tutorial", {}).duplicate(true),
		"flags": state.get("flags", {}).duplicate(true),
	}, true)
	state = _new_state()
	state["player"]["cash"] = worth
	_restore_account_state(kept)
	state["player"]["era"] = kept["era"]
	state["player"]["network_level"] = kept["network_level"]
	state["player"]["brand_multiplier"] = kept["brand_multiplier"]
	state["stats"]["prestige_count"] = kept["prestige_count"]
	state["tutorial"] = kept["tutorial"]
	state["flags"] = kept["flags"]
	_market.ensure_state(state, data)
	AudioService.play_sfx("sfx_prestige")
	_commit_action("prestige")
	return _success({"liquidated_net_worth": worth, "gain": gain, "brand_multiplier": kept["brand_multiplier"]})

func request_reward(placement: String) -> Dictionary:
	var allowed := _can_request_reward(placement)
	if not bool(allowed.get("ok", false)):
		return allowed
	if bool(_pending_rewards.get(placement, false)):
		return _failure("reward_pending")
	_pending_rewards[placement] = true
	Monetization.request_reward(placement)
	return _success()

func purchase(product_id: String) -> Dictionary:
	var allowed := can_purchase_product(product_id)
	if not bool(allowed.get("ok", false)):
		return allowed
	if bool(_pending_purchases.get(product_id, false)):
		return _failure("purchase_pending")
	_pending_purchases[product_id] = true
	Monetization.purchase(product_id)
	return _success()

func can_purchase_product(product_id: String) -> Dictionary:
	var product: Dictionary = data.get("store", {}).get("items", {}).get(product_id, {})
	if product.is_empty():
		return _failure("product_unavailable")
	if int(product.get("unlock_era", 1)) > int(state.get("player", {}).get("era", 1)):
		return _failure("locked")
	if int(product.get("unlock_prestige", 0)) > int(state.get("stats", {}).get("prestige_count", 0)):
		return _failure("locked")
	if product.get("type", "") == "non_consumable" and has_entitlement(product_id):
		return _failure("already_owned")
	if product.get("type", "") == "limited_consumable" and int(state.get("purchases", {}).get(product_id, 0)) >= int(product.get("limit", 1)):
		return _failure("purchase_limit")
	return _success()

func has_entitlement(product_id: String) -> bool:
	return bool(state.get("entitlements", {}).get(product_id, false))

func set_locale(locale: String) -> void:
	state["settings"]["locale"] = locale
	TranslationServer.set_locale(locale)
	EventBus.locale_changed.emit(locale)
	_commit_action("locale_changed")

func set_audio_setting(key: String, enabled: bool) -> void:
	if key not in ["music_enabled", "sfx_enabled", "haptics_enabled"]:
		return
	state["settings"][key] = enabled
	AudioService.apply_settings(state["settings"])
	_commit_action("settings_changed")

func mark_era_presented(era_id: int) -> void:
	state["flags"]["last_presented_era"] = maxi(int(state.get("flags", {}).get("last_presented_era", 1)), era_id)
	if persistence_enabled:
		save_now()

func start_new_company() -> void:
	var kept := _account_state_snapshot()
	if not state.is_empty() and persistence_enabled:
		SaveManager.archive_game_over(state)
	state = _new_state()
	_restore_account_state(kept)
	_market.ensure_state(state, data)
	_commit_action("new_company")

func reset_for_tests() -> void:
	persistence_enabled = false
	_pending_purchases.clear()
	_pending_rewards.clear()
	state = _new_state()
	_market.ensure_state(state, data)

func find_plot(plot_id: String) -> Dictionary:
	for plot: Dictionary in state.get("plots", []):
		if plot.get("id", "") == plot_id:
			return plot
	return {}

func find_datacenter(datacenter_id: String) -> Dictionary:
	var plot := find_plot_for_datacenter(datacenter_id)
	return plot.get("datacenter", {}) if not plot.is_empty() else {}

func find_plot_for_datacenter(datacenter_id: String) -> Dictionary:
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and dc.get("id", "") == datacenter_id:
			return plot
	return {}

func find_construction(construction_id: String) -> Dictionary:
	for item: Dictionary in state.get("construction_queue", []):
		if item.get("id", "") == construction_id:
			return item
	return {}

func is_unlocked(item: Dictionary) -> bool:
	return int(item.get("unlock_era", item.get("minimum_era", 1))) <= int(state.get("player", {}).get("era", 1))

func format_number(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 1000000000.0:
		return "%.2fB" % (value / 1000000000.0)
	if absolute >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if absolute >= 1000.0:
		return "%.1fK" % (value / 1000.0)
	return "%d" % int(round(value))

func format_duration(seconds: float) -> String:
	var whole := maxi(0, int(ceil(seconds)))
	if whole >= 3600:
		return "%dh %02dm" % [whole / 3600, (whole % 3600) / 60]
	if whole >= 60:
		return "%dm %02ds" % [whole / 60, whole % 60]
	return "%ds" % whole

func _settle_wall_gap() -> void:
	var clock: Dictionary = state.get("clock", {})
	var result := GameClock.elapsed_since(int(clock.get("last_wall_time", GameClock.wall_time())), int(clock.get("highest_wall_time", 0)))
	clock["last_wall_time"] = int(result["now"])
	clock["highest_wall_time"] = int(result["highest"])
	if bool(result.get("rollback", false)):
		EventBus.toast_requested.emit("TOAST_TIME_ROLLBACK", {})
		return
	var elapsed := float(result.get("elapsed", 0))
	if elapsed >= 2.0:
		last_offline_report = advance_time(elapsed, true)
		EventBus.offline_settled.emit(last_offline_report)
	save_now()

func _next_boundary_after(now: float, include_noise: bool) -> float:
	var result := float(state.get("clock", {}).get("next_maintenance_at", INF))
	for item: Dictionary in state.get("construction_queue", []):
		var value := float(item.get("complete_at", INF))
		if value > now:
			result = minf(result, value)
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		for installed: Variant in dc.get("racks", []):
			if not installed is Dictionary:
				continue
			for key: String in ["install_complete_at", "repair_complete_at", "auto_repair_at", "fault_at"]:
				var value := float(installed.get(key, INF))
				if value > now:
					result = minf(result, value)
		if not str(dc.get("customer_id", "")).is_empty():
			var contract_end := float(dc.get("contract_end_at", INF))
			if contract_end > now:
				result = minf(result, contract_end)
	var market_boundary := _market.next_transition_after(state, now, include_noise)
	return minf(result, market_boundary)

func _accrue_income(seconds: float) -> float:
	var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
	var earned := monthly_income() * seconds / month_seconds
	state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + earned
	state["player"]["total_revenue"] = float(state["player"].get("total_revenue", 0.0)) + earned
	_try_clear_arrears()
	return earned

func _process_due(financial: bool, offline: bool, report: Dictionary) -> void:
	var now := simulation_time()
	_process_construction_completions(now, report)
	_process_rack_installations(now, report)
	_process_repairs_and_faults(now, report)
	for notice: Dictionary in _market.process_due(state, data):
		report.get("events", []).append(notice)
		match notice.get("type", ""):
			"event_previewed": EventBus.market_event_previewed.emit(notice.get("event_id", ""))
			"event_started": EventBus.market_event_started.emit(notice.get("event_id", ""))
			"event_ended": EventBus.market_event_ended.emit(notice.get("event_id", ""))
	# Renew only after applying market transitions at this exact boundary so the
	# new locked rate reflects events that have just started or ended.
	_process_contract_renewals(now, report)
	_process_aging(now, offline, report)
	_process_maintenance(financial)
	_check_bankruptcy()

func _process_construction_completions(now: float, report: Dictionary) -> void:
	var pending: Array = []
	for item: Dictionary in state.get("construction_queue", []):
		if float(item.get("complete_at", INF)) > now:
			pending.append(item)
			continue
		match item.get("type", ""):
			"datacenter": _complete_datacenter(item)
			"rack": _complete_rack(item)
			"power": _complete_attachment(item, "power")
			"cooler": _complete_attachment(item, "cooler")
			"network": state["player"]["network_level"] = int(item.get("level", 1))
		report.get("completed", []).append(item.duplicate(true))
		EventBus.construction_completed.emit(item)
	state["construction_queue"] = pending

func _complete_datacenter(item: Dictionary) -> void:
	var plot := find_plot(str(item.get("plot_id", "")))
	if plot.is_empty():
		return
	var id := _next_id("dc")
	var racks: Array = []
	racks.resize(9)
	racks.fill(null)
	plot["datacenter"] = {
		"id": id,
		"building_id": item.get("building_id", ""),
		"status": "operational",
		"built_at": float(item.get("complete_at", simulation_time())),
		"power_unit": "",
		"coolers": {},
		"racks": racks,
		"customer_id": "",
		"contract_end_at": 0.0,
		"free_switch_available": false,
		"aging_notices": [],
	}
	plot["status"] = "operational"
	plot.erase("construction_id")
	state["player"]["total_datacenters_built"] = int(state["player"].get("total_datacenters_built", 0)) + 1
	if item.get("building_id", "") == "dc_t1":
		state["flags"]["standard_built"] = true
	AudioService.play_sfx("sfx_build_complete")

func _complete_rack(item: Dictionary) -> void:
	var dc := find_datacenter(str(item.get("datacenter_id", "")))
	var slot := int(item.get("slot", -1))
	if dc.is_empty() or slot < 0 or slot >= 9:
		return
	dc["racks"][slot] = {"rack_id": item.get("rack_id", ""), "status": "active", "enabled": true, "installed_at": float(item.get("complete_at", simulation_time())), "fault_at": -1.0}
	_reschedule_dc_faults(dc)
	_tutorial_event("rack_installed")
	AudioService.play_sfx("sfx_rack_install")

func _process_rack_installations(now: float, report: Dictionary) -> void:
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or dc.get("status", "") != "operational":
			continue
		for slot: int in range(dc.get("racks", []).size()):
			var installed: Variant = dc["racks"][slot]
			if not installed is Dictionary or installed.get("status", "") != "installing":
				continue
			if float(installed.get("install_complete_at", INF)) > now:
				continue
			_complete_rack_installation(dc, slot, now, report)

func _complete_rack_installation(dc: Dictionary, slot: int, now: float, report: Dictionary) -> void:
	var installed: Dictionary = dc.get("racks", [])[slot]
	var completed := {
		"type": "rack",
		"datacenter_id": dc.get("id", ""),
		"slot": slot,
		"rack_id": installed.get("rack_id", ""),
		"complete_at": float(installed.get("install_complete_at", now)),
	}
	installed["status"] = "active"
	installed["enabled"] = bool(installed.get("enabled", true))
	installed["installed_at"] = float(installed.get("install_complete_at", now))
	installed["fault_at"] = -1.0
	for key: String in ["started_at", "install_complete_at", "ad_uses", "cost", "construction_id"]:
		installed.erase(key)
	_reschedule_dc_faults(dc)
	report.get("completed", []).append(completed)
	EventBus.construction_completed.emit(completed)
	_tutorial_event("rack_installed")
	AudioService.play_sfx("sfx_rack_install")

func _complete_attachment(item: Dictionary, kind: String) -> void:
	var dc := find_datacenter(str(item.get("datacenter_id", "")))
	if dc.is_empty():
		return
	if kind == "power":
		dc["power_unit"] = item.get("attachment_id", "")
		_tutorial_event("power_installed")
		AudioService.play_sfx("sfx_power_on")
	else:
		dc["coolers"][item.get("edge", "north")] = item.get("attachment_id", "")
		_tutorial_event("cooler_installed")
	_reschedule_dc_faults(dc)

func _process_repairs_and_faults(now: float, report: Dictionary) -> void:
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or dc.get("status", "") != "operational":
			continue
		for slot: int in range(dc.get("racks", []).size()):
			var installed: Variant = dc["racks"][slot]
			if not installed is Dictionary:
				continue
			if installed.get("status", "") == "faulted" and float(installed.get("auto_repair_at", INF)) <= now:
				_complete_repair(dc.get("id", ""), slot, true)
				continue
			if installed.get("status", "") == "repairing" and float(installed.get("repair_complete_at", INF)) <= now:
				_complete_repair(dc.get("id", ""), slot, false)
				continue
			if installed.get("status", "") == "active":
				var runtime := Rules.rack_runtime_status(dc, slot, data.get("racks", {}), data.get("attachments", {}), data.get("economy", {}))
				if not bool(runtime.get("powered", false)):
					installed["fault_at"] = -1.0
				elif float(installed.get("fault_at", -1.0)) < 0.0:
					_schedule_fault(dc, slot)
				elif float(installed.get("fault_at", INF)) <= now:
					installed["status"] = "faulted"
					installed["fault_at"] = -1.0
					installed["auto_repair_at"] = now + float(data.get("economy", {}).get("faults", {}).get("auto_repair_seconds", 14400.0))
					var fault := {"datacenter_id": dc.get("id", ""), "slot": slot}
					report.get("faults", []).append(fault)
					EventBus.rack_fault_occurred.emit(dc.get("id", ""), slot)
					AudioService.play_sfx("sfx_fault")

func _process_contract_renewals(now: float, report: Dictionary) -> void:
	var duration := float(data.get("economy", {}).get("contracts", {}).get("duration_seconds", 43200.0))
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or str(dc.get("customer_id", "")).is_empty():
			continue
		while float(dc.get("contract_end_at", INF)) <= now:
			dc["contract_end_at"] = float(dc.get("contract_end_at", now)) + duration
			dc["locked_market_multiplier"] = contract_market_multiplier(str(dc.get("customer_id", "")))
			dc["free_switch_available"] = true
			var renewed := {"type": "contract_auto_renewed", "datacenter_id": dc.get("id", ""), "customer_id": dc.get("customer_id", ""), "contract_end_at": dc.get("contract_end_at", 0.0), "free_switch_available": true}
			report.get("contracts", []).append(renewed)
			EventBus.contract_auto_renewed.emit(dc.get("id", ""), dc.get("customer_id", ""), float(dc.get("contract_end_at", 0.0)))

func _process_aging(now: float, offline: bool, report: Dictionary) -> void:
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or dc.get("status", "") != "operational":
			continue
		var progress := Rules.age_progress(dc, now, data.get("buildings", {}))
		var stage := Rules.aging_stage(progress)
		if stage in ["aging", "decline"] and stage not in dc.get("aging_notices", []):
			dc["aging_notices"].append(stage)
			report.get("aging", []).append({"datacenter_id": dc.get("id", ""), "stage": stage})
			if stage == "aging":
				EventBus.datacenter_entered_aging.emit(dc.get("id", ""))
			_reschedule_dc_faults(dc)
		if progress >= 1.0:
			if offline:
				var building: Dictionary = data.get("buildings", {}).get("items", {}).get(dc.get("building_id", ""), {})
				dc["built_at"] = now - float(building.get("lifespan_seconds", 1.0)) * float(data.get("economy", {}).get("offline", {}).get("force_retirement_progress_cap", 0.999))
				dc["offline_expired"] = true
			else:
				dc["status"] = "ruined"
				dc["customer_id"] = ""
				plot["status"] = "ruined"

func _process_maintenance(charge: bool) -> void:
	var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
	while simulation_time() >= float(state["clock"].get("next_maintenance_at", INF)):
		if charge:
			_charge_maintenance(monthly_maintenance())
		state["clock"]["next_maintenance_at"] = float(state["clock"].get("next_maintenance_at", simulation_time())) + month_seconds

func _charge_maintenance(amount: float) -> void:
	if amount <= 0.0:
		return
	var cash := float(state["player"].get("cash", 0.0))
	if state["bankruptcy"].get("status", "normal") == "normal" and cash >= amount:
		state["player"]["cash"] = cash - amount
		state["stats"]["total_spent"] = float(state["stats"].get("total_spent", 0.0)) + amount
		return
	var paid := minf(cash, amount)
	state["player"]["cash"] = cash - paid
	state["bankruptcy"]["debt"] = float(state["bankruptcy"].get("debt", 0.0)) + amount - paid
	if state["bankruptcy"].get("status", "normal") == "normal":
		state["bankruptcy"]["status"] = "arrears"
		state["bankruptcy"]["arrears_online_seconds"] = 0.0
		EventBus.bankruptcy_state_changed.emit("arrears")

func _try_clear_arrears() -> void:
	if state.get("bankruptcy", {}).get("status", "normal") != "arrears":
		return
	var debt := float(state["bankruptcy"].get("debt", 0.0))
	var cash := float(state["player"].get("cash", 0.0))
	if cash < debt:
		return
	state["player"]["cash"] = cash - debt
	state["bankruptcy"]["debt"] = 0.0
	state["bankruptcy"]["status"] = "normal"
	state["bankruptcy"]["arrears_online_seconds"] = 0.0
	state["stats"]["arrears_recovered"] = int(state["stats"].get("arrears_recovered", 0)) + 1
	EventBus.bankruptcy_state_changed.emit("normal")

func _check_bankruptcy() -> void:
	if state.get("bankruptcy", {}).get("status", "normal") != "arrears":
		return
	var limit := float(data.get("economy", {}).get("bankruptcy", {}).get("game_over_after_online_seconds", 21600.0))
	if float(state["bankruptcy"].get("arrears_online_seconds", 0.0)) < limit:
		return
	state["bankruptcy"]["status"] = "game_over"
	if persistence_enabled:
		save_now()
	SaveManager.archive_game_over(state)
	AudioService.play_sfx("sfx_bankrupt")
	EventBus.bankruptcy_state_changed.emit("game_over")

func _check_era_unlocks() -> void:
	var current := int(state["player"].get("era", 1))
	for era_id: int in range(current + 1, 4):
		var era: Dictionary = data.get("eras", {}).get("items", {}).get(str(era_id), {})
		if float(state["player"].get("total_revenue", 0.0)) < float(era.get("revenue_required", INF)):
			break
		state["player"]["era"] = era_id
		state["player"]["gems"] = int(state["player"].get("gems", 0)) + int(era.get("reward_gems", 0))
		EventBus.era_unlocked.emit(era_id)
		AudioService.play_sfx("sfx_era")

func _check_achievements() -> void:
	for achievement_id: String in data.get("achievements", {}).get("items", {}):
		if bool(state.get("achievements", {}).get(achievement_id, false)):
			continue
		var achievement: Dictionary = data["achievements"]["items"][achievement_id]
		var metric := str(achievement.get("metric", ""))
		var value: float
		if metric in state.get("player", {}):
			value = float(state["player"].get(metric, 0.0))
		else:
			value = float(state.get("stats", {}).get(metric, 0.0))
		if value >= float(achievement.get("target", INF)):
			state["achievements"][achievement_id] = true
			state["player"]["gems"] = int(state["player"].get("gems", 0)) + int(achievement.get("reward_gems", 0))
			EventBus.toast_requested.emit("TOAST_ACHIEVEMENT", {"name": tr(achievement.get("name_key", ""))})

func _update_highest_net_worth() -> void:
	state["stats"]["highest_net_worth"] = maxf(float(state["stats"].get("highest_net_worth", 0.0)), net_worth())

func _install_attachment(datacenter_id: String, attachment_id: String, kind: String, edge: String) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	var attachment: Dictionary = data.get("attachments", {}).get("items", {}).get(attachment_id, {})
	if dc.is_empty() or dc.get("status", "") != "operational":
		return _failure("datacenter_unavailable")
	if attachment.is_empty() or attachment.get("kind", "") != kind or not is_unlocked(attachment):
		return _failure("locked")
	var building: Dictionary = data.get("buildings", {}).get("items", {}).get(dc.get("building_id", ""), {})
	if int(attachment.get("requires_building_tier", 0)) > int(building.get("tier", 0)):
		return _failure("building_tier_too_low")
	if kind == "cooler" and not dc.get("coolers", {}).has(edge) and dc.get("coolers", {}).size() >= int(building.get("cooler_slots", 0)):
		return _failure("cooler_slots_full")
	for pending: Dictionary in state.get("construction_queue", []):
		if pending.get("datacenter_id", "") != datacenter_id or pending.get("type", "") != kind:
			continue
		if kind == "power" or pending.get("edge", "") == edge:
			return _failure("construction_in_progress")
	if not _queue_has_capacity():
		return _failure("queue_full")
	var old_id := str(dc.get("power_unit", "")) if kind == "power" else str(dc.get("coolers", {}).get(edge, ""))
	var refund := 0.0
	if not old_id.is_empty():
		var old_item: Dictionary = data.get("attachments", {}).get("items", {}).get(old_id, {})
		if int(attachment.get("tier", 0)) <= int(old_item.get("tier", 0)):
			return _failure("not_an_upgrade")
		refund = float(data.get("attachments", {}).get("items", {}).get(old_id, {}).get("cost", 0.0)) * float(data.get("economy", {}).get("aging", {}).get("attachment_refund_ratio", 0.4))
	var net_cost := maxf(0.0, float(attachment.get("cost", 0.0)) - refund)
	if not _spend_cash(net_cost):
		return _failure("not_enough_cash")
	var item := _queue_item(kind, _tutorial_duration(attachment, "tutorial_install_seconds", float(attachment.get("install_seconds", 0.0))))
	item.merge({"datacenter_id": datacenter_id, "attachment_id": attachment_id, "edge": edge, "old_id": old_id, "cost": net_cost})
	state["construction_queue"].append(item)
	_commit_action("attachment_started")
	return _success({"construction": item, "trade_in": refund})

func _schedule_fault(dc: Dictionary, slot: int) -> void:
	var installed: Variant = dc.get("racks", [])[slot]
	if not installed is Dictionary or installed.get("status", "") != "active":
		return
	var runtime := Rules.rack_runtime_status(dc, slot, data.get("racks", {}), data.get("attachments", {}), data.get("economy", {}))
	if not bool(runtime.get("powered", false)):
		installed["fault_at"] = -1.0
		return
	var rate := float(data.get("economy", {}).get("faults", {}).get("base_rate_per_game_month", 0.15))
	var progress := Rules.age_progress(dc, simulation_time(), data.get("buildings", {}))
	rate *= Rules.aging_fault_multiplier(progress, data.get("economy", {}))
	if bool(runtime.get("overheated", false)):
		rate *= float(data.get("economy", {}).get("faults", {}).get("overheat_rate_multiplier", 2.5))
	var months := -log(maxf(0.000001, 1.0 - _random())) / maxf(0.000001, rate)
	installed["fault_at"] = simulation_time() + months * float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))

func _reschedule_dc_faults(dc: Dictionary) -> void:
	for slot: int in range(dc.get("racks", []).size()):
		var installed: Variant = dc["racks"][slot]
		if installed is Dictionary and installed.get("status", "") == "active":
			installed["fault_at"] = -1.0
			_schedule_fault(dc, slot)

func _complete_repair(datacenter_id: String, slot: int, automatic: bool = false) -> void:
	var installed := _installed_rack(datacenter_id, slot)
	if installed.is_empty() or str(installed.get("status", "")) not in ["faulted", "repairing"]:
		return
	installed["status"] = "active"
	installed.erase("repair_complete_at")
	installed.erase("auto_repair_at")
	var stat_key := "faults_repaired_auto" if automatic else "faults_repaired_manual"
	state["stats"][stat_key] = int(state["stats"].get(stat_key, 0)) + 1
	var dc := find_datacenter(datacenter_id)
	_schedule_fault(dc, slot)
	AudioService.play_sfx("sfx_repair")

func _installed_rack(datacenter_id: String, slot: int) -> Dictionary:
	var dc := find_datacenter(datacenter_id)
	if dc.is_empty() or dc.get("status", "") != "operational" or slot < 0 or slot >= dc.get("racks", []).size():
		return {}
	var installed: Variant = dc["racks"][slot]
	return installed if installed is Dictionary else {}

func _queue_has_capacity() -> bool:
	return state.get("construction_queue", []).size() < int(data.get("economy", {}).get("construction", {}).get("base_queue_capacity", 2))

func _has_jobs_for_datacenter(datacenter_id: String) -> bool:
	for item: Dictionary in state.get("construction_queue", []):
		if item.get("datacenter_id", "") == datacenter_id:
			return true
	var dc := find_datacenter(datacenter_id)
	for installed: Variant in dc.get("racks", []):
		if installed is Dictionary and installed.get("status", "") == "installing":
			return true
	return false

func _queue_item(type: String, duration: float) -> Dictionary:
	var started := simulation_time()
	return {"id": _next_id("job"), "type": type, "started_at": started, "complete_at": started + duration, "ad_uses": 0}

func _next_id(prefix: String) -> String:
	state["next_id"] = int(state.get("next_id", 1)) + 1
	return "%s_%d" % [prefix, int(state["next_id"])]

func _spend_cash(amount: float) -> bool:
	if amount < 0.0 or float(state["player"].get("cash", 0.0)) + 0.0001 < amount:
		return false
	state["player"]["cash"] = float(state["player"].get("cash", 0.0)) - amount
	state["stats"]["total_spent"] = float(state["stats"].get("total_spent", 0.0)) + amount
	return true

func _repair_time_multiplier() -> float:
	var level := str(state.get("technology", {}).get("repair_team", 1))
	return float(data.get("technology", {}).get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(level, {}).get("repair_time_multiplier", 1.0))

func _random() -> float:
	var current := int(state.get("market", {}).get("rng_state", 73471))
	current = int((current * 48271) % 2147483647)
	if current <= 0:
		current = 73471
	state["market"]["rng_state"] = current
	return float(current) / 2147483647.0

func _tutorial_event(event_name: String) -> void:
	var tutorial: Dictionary = state.get("tutorial", {})
	if bool(tutorial.get("completed", false)):
		return
	var steps: Array = data.get("tutorial", {}).get("steps", [])
	var index := int(tutorial.get("step", 0))
	if index >= steps.size():
		tutorial["completed"] = true
		return
	if steps[index].get("completion_event", "") == event_name:
		tutorial["step"] = index + 1
		if index + 1 >= steps.size():
			tutorial["completed"] = true

func _on_reward_result(placement: String, success: bool) -> void:
	if not bool(_pending_rewards.get(placement, false)):
		return
	_pending_rewards.erase(placement)
	if not success or not bool(_can_request_reward(placement).get("ok", false)):
		return
	var payload: Dictionary = {}
	var parts := placement.split(":")
	match parts[0]:
		"offline_double":
			var amount := float(last_offline_report.get("income", 0.0))
			if amount > 0.0 and not bool(last_offline_report.get("doubled", false)):
				state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + amount
				state["player"]["total_revenue"] = float(state["player"].get("total_revenue", 0.0)) + amount
				last_offline_report["doubled"] = true
				payload["cash"] = amount
		"repair":
			if parts.size() >= 3:
				_complete_repair(parts[1], int(parts[2]))
				state["reward_limits"]["repair_uses"] = int(state["reward_limits"].get("repair_uses", 0)) + 1
		"construction":
			if parts.size() >= 2:
				var item := find_construction(parts[1])
				if not item.is_empty():
					var reduction := float(data.get("economy", {}).get("construction", {}).get("ad_reduction_seconds", 1800.0))
					item["complete_at"] = maxf(simulation_time(), float(item.get("complete_at", simulation_time())) - reduction)
					item["ad_uses"] = int(item.get("ad_uses", 0)) + 1
		"rack_install":
			if parts.size() >= 3:
				var installed := _installed_rack(parts[1], int(parts[2]))
				if not installed.is_empty():
					var reduction := float(data.get("economy", {}).get("construction", {}).get("ad_reduction_seconds", 1800.0))
					installed["install_complete_at"] = maxf(simulation_time(), float(installed.get("install_complete_at", simulation_time())) - reduction)
					installed["ad_uses"] = int(installed.get("ad_uses", 0)) + 1
					var report := {"completed": [], "faults": [], "events": [], "contracts": [], "aging": []}
					_process_due(true, false, report)
		"arrears_rescue":
			var maintenance := monthly_maintenance()
			var cash := maintenance * float(data.get("economy", {}).get("bankruptcy", {}).get("rescue_maintenance_ratio", 0.5))
			state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + cash
			payload["cash"] = cash
			state["reward_limits"]["rescue_uses"] = int(state["reward_limits"].get("rescue_uses", 0)) + 1
			_try_clear_arrears()
	_commit_action("reward_granted")
	EventBus.reward_granted.emit(placement, payload)

func _on_purchase_result(product_id: String, success: bool, message: String, transaction_id: String) -> void:
	_pending_purchases.erase(product_id)
	if not success:
		EventBus.purchase_completed.emit(product_id, false, message)
		return
	if product_id == "restore":
		EventBus.purchase_completed.emit(product_id, true, message)
		return
	var product: Dictionary = data.get("store", {}).get("items", {}).get(product_id, {})
	if product.is_empty():
		EventBus.purchase_completed.emit(product_id, false, "product_unavailable")
		return
	if message == "restore" and product.get("type", "") != "non_consumable":
		return
	if not transaction_id.is_empty() and bool(state.get("processed_transactions", {}).get(transaction_id, false)):
		EventBus.purchase_completed.emit(product_id, true, "duplicate_transaction")
		return
	if product.get("type", "") == "non_consumable":
		state["entitlements"][product_id] = true
		EventBus.entitlement_changed.emit(product_id, true)
	else:
		var purchases: Dictionary = state.get("purchases", {})
		if product.get("type", "") == "limited_consumable" and int(purchases.get(product_id, 0)) >= int(product.get("limit", 1)):
			EventBus.purchase_completed.emit(product_id, false, "purchase_limit")
			return
		state["player"]["gems"] = int(state["player"].get("gems", 0)) + int(product.get("gems", 0))
		state["player"]["cash"] = float(state["player"].get("cash", 0.0)) + float(product.get("cash", 0.0))
		state["inventory"]["instant_build_tickets"] = int(state["inventory"].get("instant_build_tickets", 0)) + int(product.get("tickets", 0))
		purchases[product_id] = int(purchases.get(product_id, 0)) + 1
		state["purchases"] = purchases
	if not transaction_id.is_empty():
		state["processed_transactions"][transaction_id] = true
	AudioService.play_sfx("sfx_purchase")
	_commit_action("purchase_completed")
	EventBus.purchase_completed.emit(product_id, true, message)

func _apply_locale() -> void:
	var locale := str(state.get("settings", {}).get("locale", ""))
	if locale.is_empty():
		locale = "zh_CN" if OS.get_locale().to_lower().begins_with("zh") else "en"
		state["settings"]["locale"] = locale
	TranslationServer.set_locale(locale)

func _can_request_reward(placement: String) -> Dictionary:
	var parts := placement.split(":")
	var limits: Dictionary = state.get("reward_limits", {})
	var now := GameClock.wall_time()
	match parts[0]:
		"offline_double":
			if bool(last_offline_report.get("doubled", false)) or float(last_offline_report.get("income", 0.0)) <= 0.0:
				return _failure("reward_unavailable")
		"repair":
			if parts.size() < 3 or _installed_rack(parts[1], int(parts[2])).get("status", "") != "faulted":
				return _failure("reward_unavailable")
			if now - int(limits.get("repair_window_start", 0)) >= 3600:
				limits["repair_window_start"] = now
				limits["repair_uses"] = 0
			if int(limits.get("repair_uses", 0)) >= int(data.get("economy", {}).get("faults", {}).get("rewarded_repairs_per_hour", 4)):
				return _failure("reward_limit")
		"construction":
			if parts.size() < 2:
				return _failure("reward_unavailable")
			var item := find_construction(parts[1])
			if item.is_empty() or int(item.get("ad_uses", 0)) >= int(data.get("economy", {}).get("construction", {}).get("max_ads_per_project", 2)):
				return _failure("reward_limit")
		"rack_install":
			if parts.size() < 3:
				return _failure("reward_unavailable")
			var installed := _installed_rack(parts[1], int(parts[2]))
			if installed.is_empty() or installed.get("status", "") != "installing":
				return _failure("reward_unavailable")
			if int(installed.get("ad_uses", 0)) >= int(data.get("economy", {}).get("construction", {}).get("max_ads_per_project", 2)):
				return _failure("reward_limit")
		"arrears_rescue":
			if state.get("bankruptcy", {}).get("status", "normal") != "arrears":
				return _failure("reward_unavailable")
			var real_day := now / 86400
			if int(limits.get("rescue_day", -1)) != real_day:
				limits["rescue_day"] = real_day
				limits["rescue_uses"] = 0
			if int(limits.get("rescue_uses", 0)) >= int(data.get("economy", {}).get("bankruptcy", {}).get("rescue_uses_per_real_day", 3)):
				return _failure("reward_limit")
	state["reward_limits"] = limits
	return _success()

func _commit_action(reason: String) -> void:
	_check_era_unlocks()
	_check_achievements()
	_update_highest_net_worth()
	EventBus.state_changed.emit(reason)
	if bool(state.get("settings", {}).get("haptics_enabled", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(24)
	if persistence_enabled:
		save_now()

func _ensure_state_shape() -> void:
	var legacy_manual_repairs := -1
	if state.get("stats") is Dictionary and state["stats"].has("faults_repaired") and not state["stats"].has("faults_repaired_manual"):
		legacy_manual_repairs = int(state["stats"].get("faults_repaired", 0))
	var defaults := _new_state()
	for key: String in defaults:
		if not state.has(key):
			state[key] = defaults[key]
	for section: String in ["player", "clock", "bankruptcy", "tutorial", "inventory", "settings", "stats", "flags", "technology", "entitlements", "achievements", "purchases", "processed_transactions", "reward_limits"]:
		if not state.get(section) is Dictionary:
			state[section] = defaults.get(section, {})
		for key: String in defaults.get(section, {}):
			if not state[section].has(key):
				state[section][key] = defaults[section][key]
	if legacy_manual_repairs >= 0:
		state["stats"]["faults_repaired_manual"] = legacy_manual_repairs
		state["stats"].erase("faults_repaired")
	_migrate_legacy_rack_installations()
	for plot: Dictionary in state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var customer_id := str(dc.get("customer_id", ""))
		if not customer_id.is_empty() and not dc.has("locked_market_multiplier"):
			dc["locked_market_multiplier"] = contract_market_multiplier(customer_id)
		if dc.has("renewal_window_end_at"):
			if float(dc.get("renewal_window_end_at", 0.0)) > simulation_time():
				dc["free_switch_available"] = true
			dc.erase("renewal_window_end_at")
		if not dc.has("free_switch_available"):
			dc["free_switch_available"] = false
		for installed: Variant in dc.get("racks", []):
			if installed is Dictionary and not installed.is_empty():
				if not installed.has("enabled"):
					installed["enabled"] = true
				if str(installed.get("status", "")) == "faulted" and not installed.has("auto_repair_at"):
					installed["auto_repair_at"] = simulation_time() + float(data.get("economy", {}).get("faults", {}).get("auto_repair_seconds", 14400.0))
	state["save_version"] = SaveManager.SAVE_VERSION

func _migrate_legacy_rack_installations() -> void:
	var retained: Array = []
	for item: Dictionary in state.get("construction_queue", []):
		if item.get("type", "") != "rack":
			retained.append(item)
			continue
		var dc := find_datacenter(str(item.get("datacenter_id", "")))
		var slot := int(item.get("slot", -1))
		if dc.is_empty() or slot < 0 or slot >= dc.get("racks", []).size():
			continue
		var installed: Variant = dc["racks"][slot]
		if not installed is Dictionary or installed.is_empty():
			installed = {"rack_id": item.get("rack_id", ""), "status": "installing"}
			dc["racks"][slot] = installed
		installed["enabled"] = true
		installed["started_at"] = float(item.get("started_at", simulation_time()))
		installed["install_complete_at"] = float(item.get("complete_at", simulation_time()))
		installed["ad_uses"] = int(item.get("ad_uses", 0))
		installed["cost"] = float(item.get("cost", 0.0))
		installed.erase("construction_id")
	state["construction_queue"] = retained

func _new_state() -> Dictionary:
	var economy: Dictionary = DataRepository.get_table("economy")
	var now := GameClock.wall_time()
	return {
		"save_version": SaveManager.SAVE_VERSION,
		"profile_id": "%x%x" % [now, randi()],
		"next_id": 1,
		"player": {"cash": float(economy.get("starting", {}).get("cash", 10000.0)), "gems": int(economy.get("starting", {}).get("gems", 20)), "total_revenue": 0.0, "brand_multiplier": 1.0, "era": 1, "network_level": 1, "total_datacenters_built": 0},
		"clock": {"created_at": now, "last_wall_time": now, "highest_wall_time": now, "simulation_seconds": 0.0, "next_maintenance_at": float(economy.get("time", {}).get("real_seconds_per_game_month", 7200.0))},
		"plots": [{"id": "plot_1", "index": 1, "purchase_price": 0.0, "purchased": true, "status": "empty", "datacenter": null}],
		"construction_queue": [],
		"market": {"active": [], "previews": [], "history": {}, "noise": {}, "next_noise_at": float(economy.get("time", {}).get("real_seconds_per_game_day", 240.0)), "next_event_at": float(economy.get("time", {}).get("real_seconds_per_game_month", 7200.0)), "rng_state": 73471},
		"bankruptcy": {"status": "normal", "debt": 0.0, "arrears_online_seconds": 0.0, "rescue_uses": 0, "rescue_day": -1},
		"tutorial": {"step": 0, "completed": false, "dismissed_messages": []},
		"technology": {"repair_team": 1},
		"flags": {"standard_built": false, "last_presented_era": 1},
		"achievements": {},
		"entitlements": {},
		"purchases": {},
		"processed_transactions": {},
		"reward_limits": {"repair_window_start": now, "repair_uses": 0, "rescue_day": -1, "rescue_uses": 0},
		"inventory": {"instant_build_tickets": 0},
		"settings": {"locale": "", "music_enabled": true, "sfx_enabled": true, "haptics_enabled": true},
		"stats": {"total_spent": 0.0, "faults_repaired_manual": 0, "faults_repaired_auto": 0, "datacenters_retired": 0, "prestige_count": 0, "contracts_signed": 0, "arrears_recovered": 0, "highest_net_worth": 0.0},
	}

func _success(payload: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(payload)
	return result

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _account_state_snapshot() -> Dictionary:
	if state.is_empty():
		return {}
	return {
		"gems": int(state.get("player", {}).get("gems", 0)),
		"brand_multiplier": float(state.get("player", {}).get("brand_multiplier", 1.0)),
		"prestige_count": int(state.get("stats", {}).get("prestige_count", 0)),
		"inventory": state.get("inventory", {}).duplicate(true),
		"achievements": state.get("achievements", {}).duplicate(true),
		"entitlements": state.get("entitlements", {}).duplicate(true),
		"purchases": state.get("purchases", {}).duplicate(true),
		"processed_transactions": state.get("processed_transactions", {}).duplicate(true),
		"settings": state.get("settings", {}).duplicate(true),
	}

func _restore_account_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	state["player"]["gems"] = int(snapshot.get("gems", state["player"].get("gems", 0)))
	state["player"]["brand_multiplier"] = float(snapshot.get("brand_multiplier", state["player"].get("brand_multiplier", 1.0)))
	state["stats"]["prestige_count"] = int(snapshot.get("prestige_count", 0))
	for key: String in ["inventory", "achievements", "entitlements", "purchases", "processed_transactions", "settings"]:
		if snapshot.get(key) is Dictionary:
			state[key] = snapshot[key].duplicate(true)
