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
	return round(float(land.get("base_price", 500.0)) * pow(float(land.get("growth_factor", 1.55)), plot_index - 1))

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
		if not installed is Dictionary or installed.is_empty() or installed.get("status", "") == "installing":
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
	var powered := powered_slots(datacenter, racks_table, attachments_table)[slot]
	var cooling := cooling_at(datacenter, slot, attachments_table, economy)
	return {
		"present": true,
		"powered": powered,
		"overheated": powered and cooling < float(rack.get("heat", 0.0)),
		"faulted": installed.get("status", "active") == "faulted",
		"repairing": installed.get("status", "active") == "repairing",
		"cooling": cooling,
		"heat": float(rack.get("heat", 0.0)),
	}

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
	var racks: Array = datacenter.get("racks", [])
	for slot: int in range(mini(9, racks.size())):
		if not racks[slot] is Dictionary or racks[slot].is_empty() or not powered[slot]:
			continue
		var installed: Dictionary = racks[slot]
		if installed.get("status", "active") != "active":
			continue
		var rack: Dictionary = racks_table.get("items", {}).get(installed.get("rack_id", ""), {})
		var kind := str(rack.get("kind", ""))
		kinds[kind] = true
		var overheat_multiplier := 1.0
		if cooling_at(datacenter, slot, attachments, data.get("economy", {})) < float(rack.get("heat", 0.0)):
			overheat_multiplier = float(data.get("economy", {}).get("aging", {}).get("overheat_income_multiplier", 0.5))
		result += float(rack.get("income_per_month", 0.0)) * float(customer.get("fit", {}).get(kind, 0.0)) * overheat_multiplier
	if kinds.size() >= int(customer.get("diversity_required_kinds", 999)):
		result *= float(customer.get("diversity_multiplier", 1.0))
	var player: Dictionary = game_state.get("player", {})
	var network_level := str(player.get("network_level", 1))
	var network: Dictionary = data.get("technology", {}).get("network", {}).get(network_level, {})
	var era: Dictionary = data.get("eras", {}).get("items", {}).get(str(player.get("era", 1)), {})
	result *= aging_efficiency(progress)
	result *= float(market_multiplier.call(customer_id))
	result *= float(network.get("income_multiplier", 1.0))
	result *= float(era.get("income_multiplier", 1.0))
	result *= float(player.get("brand_multiplier", 1.0))
	result *= float(building.get("structure_multiplier", 1.0))
	if game_state.get("bankruptcy", {}).get("status", "normal") == "arrears":
		result *= float(data.get("economy", {}).get("bankruptcy", {}).get("arrears_income_multiplier", 0.5))
	return result

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
	return round(value)

static func demolition_cost(datacenter: Dictionary, data: Dictionary) -> float:
	var building: Dictionary = data.get("buildings", {}).get("items", {}).get(datacenter.get("building_id", ""), {})
	return round(float(building.get("cost", 0.0)) * float(data.get("economy", {}).get("aging", {}).get("demolition_cost_ratio", 0.15)))

static func total_net_worth(game_state: Dictionary, data: Dictionary) -> float:
	var total := float(game_state.get("player", {}).get("cash", 0.0))
	var simulation_seconds := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	for plot: Dictionary in game_state.get("plots", []):
		if plot.get("datacenter") is Dictionary:
			total += retirement_value(plot["datacenter"], simulation_seconds, data)
		if bool(plot.get("purchased", false)):
			total += land_price(int(plot.get("index", 1)), data.get("economy", {})) * float(data.get("economy", {}).get("land", {}).get("prestige_refund_ratio", 0.5))
	return total
