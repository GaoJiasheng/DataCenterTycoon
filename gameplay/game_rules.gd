class_name GameRules
extends RefCounted

const COOLER_EDGES := {
	"north": [0, 1, 2],
	"east": [2, 5, 8],
	"south": [6, 7, 8],
	"west": [0, 3, 6],
}

static func land_price(plot_index: int, economy: Dictionary) -> float:
	if plot_index <= int(economy.get("starting", {}).get("free_plot_count", 1)):
		return 0.0
	var land: Dictionary = economy.get("land", {})
	var campus := campus_layout_for_plot(plot_index, economy)
	var multiplier := float(campus.get("land_price_multiplier", 1.0))
	var growth_base := 1.0 + float(land.get("growth_step", 0.55)) * float(plot_index - 1)
	return round(float(land.get("base_price", 500.0)) * pow(growth_base, float(land.get("growth_exponent", 1.5))) * multiplier)

static func campus_layout_for_plot(plot_index: int, economy: Dictionary) -> Dictionary:
	var campuses: Dictionary = economy.get("campuses", {})
	var types: Dictionary = campuses.get("types", {})
	var sequence: Array = campuses.get("sequence", [])
	if sequence.is_empty() or types.is_empty():
		return {
			"campus_index": maxi(0, (plot_index - 1) / 6),
			"local_slot": maxi(0, (plot_index - 1) % 6),
			"start_plot_index": maxi(1, ((plot_index - 1) / 6) * 6 + 1),
			"type_id": "type_1",
			"capacity": 6,
			"name_key": "CAMPUS_TYPE_STANDARD",
			"land_price_multiplier": 1.0,
			"accent": "3aa7f0",
		}
	var remaining := maxi(1, plot_index)
	var campus_index := 0
	var start_plot_index := 1
	for raw_type_id: Variant in sequence:
		var type_id := str(raw_type_id)
		var definition: Dictionary = types.get(type_id, {})
		var capacity := maxi(1, int(definition.get("capacity", 6)))
		if remaining <= capacity:
			return _campus_layout_result(campus_index, remaining - 1, start_plot_index, type_id, definition, capacity)
		remaining -= capacity
		start_plot_index += capacity
		campus_index += 1
	var repeat_last := bool(campuses.get("repeat_last", true))
	var fallback_type_id := str(sequence.back()) if repeat_last else str(sequence[posmod(campus_index, sequence.size())])
	var fallback: Dictionary = types.get(fallback_type_id, {})
	var fallback_capacity := maxi(1, int(fallback.get("capacity", 6)))
	if repeat_last:
		var extra_campuses := (remaining - 1) / fallback_capacity
		campus_index += extra_campuses
		start_plot_index += extra_campuses * fallback_capacity
		remaining = (remaining - 1) % fallback_capacity + 1
	return _campus_layout_result(campus_index, remaining - 1, start_plot_index, fallback_type_id, fallback, fallback_capacity)

static func campus_layout_for_index(campus_index: int, economy: Dictionary) -> Dictionary:
	var target := maxi(0, campus_index)
	var plot_index := 1
	var current := 0
	while current < target:
		var layout := campus_layout_for_plot(plot_index, economy)
		plot_index += maxi(1, int(layout.get("capacity", 6)))
		current += 1
	return campus_layout_for_plot(plot_index, economy)

static func campus_count_for_slots(slot_count: int, economy: Dictionary) -> int:
	return int(campus_layout_for_plot(maxi(1, slot_count), economy).get("campus_index", 0)) + 1

static func _campus_layout_result(campus_index: int, local_slot: int, start_plot_index: int, type_id: String, definition: Dictionary, capacity: int) -> Dictionary:
	return {
		"campus_index": campus_index,
		"local_slot": local_slot,
		"start_plot_index": start_plot_index,
		"type_id": type_id,
		"capacity": capacity,
		"name_key": str(definition.get("name_key", "CAMPUS_TYPE_STANDARD")),
		"land_price_multiplier": float(definition.get("land_price_multiplier", 1.0)),
		"accent": str(definition.get("accent", "3aa7f0")),
	}

static func age_progress(datacenter: Dictionary, simulation_seconds: float, buildings: Dictionary) -> float:
	if datacenter.is_empty() or datacenter.get("status", "") == "ruined":
		return 1.0
	var building: Dictionary = buildings.get("items", {}).get(datacenter.get("building_id", ""), {})
	var lifespan := maxf(1.0, float(building.get("lifespan_seconds", 1.0)))
	return clampf((simulation_seconds - float(datacenter.get("built_at", simulation_seconds))) / lifespan, 0.0, 1.0)

static func aging_efficiency(progress: float) -> float:
	if progress <= 0.6:
		return 1.0
	if progress <= 0.9:
		return 1.0 - ((progress - 0.6) / 0.3) * 0.3
	return 0.7 - ((progress - 0.9) / 0.1) * 0.3

static func aging_stage(progress: float) -> String:
	if progress >= 1.0:
		return "ruined"
	if progress > 0.9:
		return "decline"
	if progress > 0.6:
		return "aging"
	return "new"

static func aging_fault_multiplier(progress: float, economy: Dictionary) -> float:
	var aging: Dictionary = economy.get("aging", {})
	if progress > float(aging.get("decline_start", 0.9)):
		return float(aging.get("decline_fault_multiplier", 6.0))
	if progress > float(aging.get("aging_start", 0.6)):
		return float(aging.get("aging_fault_multiplier", 3.0))
	return 1.0

static func powered_slots(datacenter: Dictionary, racks_table: Dictionary, attachments_table: Dictionary) -> Array[bool]:
	var result: Array[bool] = []
	result.resize(9)
	result.fill(false)
	var power_id := str(datacenter.get("power_unit", ""))
	if power_id.is_empty():
		return result
	var power: Dictionary = attachments_table.get("items", {}).get(power_id, {})
	var remaining := float(power.get("capacity", 0.0))
	var racks: Array = datacenter.get("racks", [])
	for slot: int in range(mini(9, racks.size())):
		var installed: Variant = racks[slot]
		if not installed is Dictionary or installed.is_empty() or installed.get("status", "") == "installing" or not bool(installed.get("enabled", true)):
			continue
		var rack: Dictionary = racks_table.get("items", {}).get(installed.get("rack_id", ""), {})
		var demand := float(rack.get("power", 0.0))
		if remaining >= demand:
			result[slot] = true
			remaining -= demand
	return result

static func cooling_at(datacenter: Dictionary, slot: int, attachments_table: Dictionary, economy: Dictionary = {}) -> float:
	var total := float(economy.get("cooling", {}).get("ambient_per_slot", 0.0))
	var coolers: Dictionary = datacenter.get("coolers", {})
	for edge: String in COOLER_EDGES:
		if slot not in COOLER_EDGES[edge]:
			continue
		var cooler_id := str(coolers.get(edge, ""))
		if cooler_id.is_empty():
			continue
		var cooler: Dictionary = attachments_table.get("items", {}).get(cooler_id, {})
		total += float(cooler.get("cooling", 0.0))
	return total

static func rack_runtime_status(datacenter: Dictionary, slot: int, racks_table: Dictionary, attachments_table: Dictionary, economy: Dictionary = {}) -> Dictionary:
	var racks: Array = datacenter.get("racks", [])
	if slot < 0 or slot >= racks.size() or not racks[slot] is Dictionary or racks[slot].is_empty():
		return {"present": false, "powered": false, "overheated": false, "faulted": false}
	var installed: Dictionary = racks[slot]
	var rack: Dictionary = racks_table.get("items", {}).get(installed.get("rack_id", ""), {})
	var enabled := bool(installed.get("enabled", true))
	var powered := enabled and powered_slots(datacenter, racks_table, attachments_table)[slot]
	var cooling := cooling_at(datacenter, slot, attachments_table, economy)
	return {
		"present": true,
		"enabled": enabled,
		"powered": powered,
		"overheated": powered and cooling < float(rack.get("heat", 0.0)),
		"faulted": installed.get("status", "active") == "faulted",
		"repairing": installed.get("status", "active") == "repairing",
		"cooling": cooling,
		"heat": float(rack.get("heat", 0.0)),
	}

static func set_bonus_lines(datacenter: Dictionary, racks_table: Dictionary, attachments_table: Dictionary) -> Array:
	var result: Array = []
	var powered := powered_slots(datacenter, racks_table, attachments_table)
	var racks: Array = datacenter.get("racks", [])
	var lines := [
		[0, 1, 2], [3, 4, 5], [6, 7, 8],
		[0, 3, 6], [1, 4, 7], [2, 5, 8],
	]
	for line: Array in lines:
		var kind := ""
		var complete := true
		for slot: int in line:
			if slot >= racks.size() or not racks[slot] is Dictionary or racks[slot].is_empty() or not powered[slot]:
				complete = false
				break
			var installed: Dictionary = racks[slot]
			if str(installed.get("status", "active")) not in ["active", "faulted"]:
				complete = false
				break
			var rack: Dictionary = racks_table.get("items", {}).get(installed.get("rack_id", ""), {})
			var slot_kind := str(rack.get("kind", ""))
			if slot_kind.is_empty() or (not kind.is_empty() and slot_kind != kind):
				complete = false
				break
			kind = slot_kind
		if complete:
			result.append(line.duplicate())
	return result

static func set_bonus_slots(datacenter: Dictionary, racks_table: Dictionary, attachments_table: Dictionary) -> Array[bool]:
	var result: Array[bool] = []
	result.resize(9)
	result.fill(false)
	for line: Array in set_bonus_lines(datacenter, racks_table, attachments_table):
		for slot: int in line:
			result[slot] = true
	return result

static func datacenter_income_per_month(datacenter: Dictionary, game_state: Dictionary, data: Dictionary, market_multiplier: Callable) -> float:
	if datacenter.get("status", "") != "operational":
		return 0.0
	var customer_id := str(datacenter.get("customer_id", ""))
	if customer_id.is_empty():
		return 0.0
	var customers: Dictionary = data.get("customers", {})
	var customer: Dictionary = customers.get("items", {}).get(customer_id, {})
	if customer.is_empty():
		return 0.0
	var racks_table: Dictionary = data.get("racks", {})
	var attachments: Dictionary = data.get("attachments", {})
	var buildings: Dictionary = data.get("buildings", {})
	var building: Dictionary = buildings.get("items", {}).get(datacenter.get("building_id", ""), {})
	var simulation_seconds := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var progress := age_progress(datacenter, simulation_seconds, buildings)
	var result := 0.0
	var kinds: Dictionary = {}
	var powered := powered_slots(datacenter, racks_table, attachments)
	var set_members := set_bonus_slots(datacenter, racks_table, attachments)
	var set_multiplier := float(data.get("economy", {}).get("layout", {}).get("set_bonus_multiplier", 1.10))
	var racks: Array = datacenter.get("racks", [])
	for slot: int in range(mini(9, racks.size())):
		if not racks[slot] is Dictionary or racks[slot].is_empty() or not powered[slot]:
			continue
		var installed: Dictionary = racks[slot]
		var rack_status := str(installed.get("status", "active"))
		if rack_status not in ["active", "faulted"]:
			continue
		var rack: Dictionary = racks_table.get("items", {}).get(installed.get("rack_id", ""), {})
		var kind := str(rack.get("kind", ""))
		kinds[kind] = true
		var overheat_multiplier := 1.0
		if cooling_at(datacenter, slot, attachments, data.get("economy", {})) < float(rack.get("heat", 0.0)):
			overheat_multiplier = float(data.get("economy", {}).get("aging", {}).get("overheat_income_multiplier", 0.5))
		var raw_market_multiplier := float(datacenter.get("locked_market_multiplier", market_multiplier.call(customer_id)))
		var sensitivity := float(rack.get("market_sensitivity", 1.0))
		var effective_market_multiplier := maxf(0.0, 1.0 + (raw_market_multiplier - 1.0) * sensitivity)
		var fault_multiplier := float(data.get("economy", {}).get("faults", {}).get("faulted_income_multiplier", 0.4)) if rack_status == "faulted" else 1.0
		var layout_multiplier := set_multiplier if set_members[slot] else 1.0
		result += float(rack.get("income_per_month", 0.0)) * float(customer.get("fit", {}).get(kind, 0.0)) * overheat_multiplier * effective_market_multiplier * fault_multiplier * layout_multiplier
	if kinds.size() >= int(customer.get("diversity_required_kinds", 999)):
		result *= float(customer.get("diversity_multiplier", 1.0))
	var player: Dictionary = game_state.get("player", {})
	# JSON persists integral progression values as floats. Normalize before using
	# them as string keys ("1", not "1.0").
	var network_level := str(int(player.get("network_level", 1)))
	var network: Dictionary = data.get("technology", {}).get("network", {}).get(network_level, {})
	var era: Dictionary = data.get("eras", {}).get("items", {}).get(str(int(player.get("era", 1))), {})
	result *= aging_efficiency(progress)
	result *= float(network.get("income_multiplier", 1.0))
	result *= float(era.get("income_multiplier", 1.0))
	result *= float(player.get("brand_multiplier", 1.0))
	result *= float(building.get("structure_multiplier", 1.0))
	result *= float(datacenter.get("contract_income_multiplier", 1.0))
	result *= relationship_income_multiplier(customer_id, game_state, data)
	result *= campus_specialization_income_multiplier(datacenter, game_state, data)
	result *= board_business_income_multiplier(game_state, data)
	if game_state.get("bankruptcy", {}).get("status", "normal") == "arrears":
		result *= float(data.get("economy", {}).get("bankruptcy", {}).get("arrears_income_multiplier", 0.5))
	return result

static func relationship_level(customer_id: String, game_state: Dictionary, data: Dictionary) -> Dictionary:
	var service_seconds := float(game_state.get("meta", {}).get("customer_service_seconds", {}).get(customer_id, 0.0))
	var levels: Array = data.get("meta_progression", {}).get("relationships", {}).get("levels", [])
	var selected := {"index": 0, "id": "new", "service_seconds": 0.0, "income_multiplier": 1.0}
	for index: int in range(levels.size()):
		var level: Dictionary = levels[index]
		if service_seconds >= float(level.get("service_seconds", INF)):
			selected = level.duplicate(true)
			selected["index"] = index
	return selected

static func relationship_income_multiplier(customer_id: String, game_state: Dictionary, data: Dictionary) -> float:
	return float(relationship_level(customer_id, game_state, data).get("income_multiplier", 1.0))

static func campus_specialization_income_multiplier(datacenter: Dictionary, game_state: Dictionary, data: Dictionary) -> float:
	var plot_index := 0
	for plot: Dictionary in game_state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and str((dc as Dictionary).get("id", "")) == str(datacenter.get("id", "")):
			plot_index = int(plot.get("index", 1))
			break
	if plot_index <= 0:
		return 1.0
	var layout := campus_layout_for_plot(plot_index, data.get("economy", {}))
	var campus_index := int(layout.get("campus_index", 0))
	var specialization_id := str(game_state.get("meta", {}).get("campus_specializations", {}).get(str(campus_index), ""))
	if specialization_id.is_empty():
		return 1.0
	var specialization: Dictionary = data.get("meta_progression", {}).get("campus_specializations", {}).get(specialization_id, {})
	if specialization.is_empty() or not _campus_specialization_requirements_met(campus_index, specialization, game_state, data):
		return 1.0
	var customer_ids: Array = specialization.get("customer_ids", [])
	if not customer_ids.is_empty() and str(datacenter.get("customer_id", "")) not in customer_ids:
		return 1.0
	return float(specialization.get("income_multiplier", 1.0))

static func campus_specialization_status(campus_index: int, specialization_id: String, game_state: Dictionary, data: Dictionary) -> Dictionary:
	var specialization: Dictionary = data.get("meta_progression", {}).get("campus_specializations", {}).get(specialization_id, {})
	if specialization.is_empty():
		return {"active": false, "reason": "missing"}
	if int(specialization.get("unlock_era", 1)) > int(game_state.get("player", {}).get("era", 1)):
		return {"active": false, "reason": "locked"}
	return {"active": _campus_specialization_requirements_met(campus_index, specialization, game_state, data), "reason": "ready"}

static func _campus_specialization_requirements_met(campus_index: int, specialization: Dictionary, game_state: Dictionary, data: Dictionary) -> bool:
	var rack_kind_counts := {"compute": 0, "storage": 0, "gpu": 0}
	var unique_kinds := {}
	var unique_customers := {}
	for plot: Dictionary in game_state.get("plots", []):
		var layout := campus_layout_for_plot(int(plot.get("index", 1)), data.get("economy", {}))
		if int(layout.get("campus_index", -1)) != campus_index:
			continue
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var customer_id := str((dc as Dictionary).get("customer_id", ""))
		if not customer_id.is_empty():
			unique_customers[customer_id] = true
		for installed: Variant in (dc as Dictionary).get("racks", []):
			if not installed is Dictionary or installed.is_empty() or str((installed as Dictionary).get("status", "")) not in ["active", "faulted"]:
				continue
			var rack: Dictionary = data.get("racks", {}).get("items", {}).get(str((installed as Dictionary).get("rack_id", "")), {})
			var kind := str(rack.get("kind", ""))
			if not kind.is_empty():
				rack_kind_counts[kind] = int(rack_kind_counts.get(kind, 0)) + 1
				unique_kinds[kind] = true
	var requirements: Dictionary = specialization.get("requirements", {})
	if requirements.has("rack_kind") and int(rack_kind_counts.get(str(requirements.get("rack_kind", "")), 0)) < int(requirements.get("rack_count", 0)):
		return false
	if unique_kinds.size() < int(requirements.get("unique_rack_kinds", 0)):
		return false
	if unique_customers.size() < int(requirements.get("unique_customers", 0)):
		return false
	return true

static func board_business_income_multiplier(game_state: Dictionary, data: Dictionary) -> float:
	var rank := int(game_state.get("meta", {}).get("board_allocations", {}).get("business", 0))
	var per_rank := float(data.get("meta_progression", {}).get("board_specialties", {}).get("items", {}).get("business", {}).get("income_multiplier_per_rank", 0.0))
	return 1.0 + float(rank) * per_rank

static func datacenter_maintenance(datacenter: Dictionary, buildings: Dictionary) -> float:
	if datacenter.get("status", "") != "operational":
		return 0.0
	return float(buildings.get("items", {}).get(datacenter.get("building_id", ""), {}).get("maintenance_per_month", 0.0))

static func retirement_value(datacenter: Dictionary, simulation_seconds: float, data: Dictionary) -> float:
	var buildings: Dictionary = data.get("buildings", {})
	var building: Dictionary = buildings.get("items", {}).get(datacenter.get("building_id", ""), {})
	var progress := age_progress(datacenter, simulation_seconds, buildings)
	var economy: Dictionary = data.get("economy", {})
	var aging: Dictionary = economy.get("aging", {})
	var value := float(building.get("cost", 0.0)) * float(aging.get("retirement_building_refund_ratio", 0.4)) * (1.0 - progress)
	var attachments: Dictionary = data.get("attachments", {}).get("items", {})
	var attachment_ratio := float(aging.get("attachment_refund_ratio", 0.4))
	var power_id := str(datacenter.get("power_unit", ""))
	if attachments.has(power_id):
		value += float(attachments[power_id].get("cost", 0.0)) * attachment_ratio
	for cooler_id: String in datacenter.get("coolers", {}).values():
		if attachments.has(cooler_id):
			value += float(attachments[cooler_id].get("cost", 0.0)) * attachment_ratio
	var racks_table: Dictionary = data.get("racks", {}).get("items", {})
	var rack_ratio := float(aging.get("rack_refund_ratio", 0.5))
	for installed: Variant in datacenter.get("racks", []):
		if installed is Dictionary and racks_table.has(installed.get("rack_id", "")):
			value += float(racks_table[installed["rack_id"]].get("cost", 0.0)) * rack_ratio
	var rounded: float = round(value)
	if progress < 1.0:
		# The harvest must always beat waiting for ruin, even for a bare center at
		# the very end of its life where the linear building component approaches 0.
		return maxf(rounded, ruin_scrap_value(datacenter, data) + 1.0)
	return rounded

static func ruin_scrap_value(datacenter: Dictionary, data: Dictionary) -> float:
	var building: Dictionary = data.get("buildings", {}).get("items", {}).get(datacenter.get("building_id", ""), {})
	var aging: Dictionary = data.get("economy", {}).get("aging", {})
	var value := float(building.get("cost", 0.0)) * float(aging.get("ruin_building_scrap_ratio", 0.05))
	var attachments: Dictionary = data.get("attachments", {}).get("items", {})
	var attachment_ratio := float(aging.get("ruin_attachment_scrap_ratio", 0.1))
	var power_id := str(datacenter.get("power_unit", ""))
	if attachments.has(power_id):
		value += float(attachments[power_id].get("cost", 0.0)) * attachment_ratio
	for cooler_id: String in datacenter.get("coolers", {}).values():
		if attachments.has(cooler_id):
			value += float(attachments[cooler_id].get("cost", 0.0)) * attachment_ratio
	var racks_table: Dictionary = data.get("racks", {}).get("items", {})
	var rack_ratio := float(aging.get("rack_refund_ratio", 0.5))
	for installed: Variant in datacenter.get("racks", []):
		if installed is Dictionary and racks_table.has(installed.get("rack_id", "")):
			value += float(racks_table[installed["rack_id"]].get("cost", 0.0)) * rack_ratio
	return round(value)

static func total_net_worth(game_state: Dictionary, data: Dictionary) -> float:
	var total := float(game_state.get("player", {}).get("cash", 0.0))
	var simulation_seconds := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	for plot: Dictionary in game_state.get("plots", []):
		if plot.get("datacenter") is Dictionary:
			var dc: Dictionary = plot["datacenter"]
			total += ruin_scrap_value(dc, data) if dc.get("status", "") == "ruined" else retirement_value(dc, simulation_seconds, data)
		if bool(plot.get("purchased", false)):
			total += land_price(int(plot.get("index", 1)), data.get("economy", {})) * float(data.get("economy", {}).get("land", {}).get("prestige_refund_ratio", 0.5))
	return total
