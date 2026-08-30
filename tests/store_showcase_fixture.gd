class_name StoreShowcaseFixture
extends RefCounted

const Rules := preload("res://gameplay/game_rules.gd")


static func apply() -> String:
	# This is a save-shaped, deterministic late-game account.  The store capture
	# harness drives the real game/UI from it; no presentation-only labels or
	# fake cards are introduced.
	Game.reset_for_tests()
	var now := Game.simulation_time()
	var plots: Array[Dictionary] = []
	var building_cycle := ["dc_t1", "dc_t2", "dc_t3", "dc_t2", "dc_t3", "dc_t1"]
	var customer_cycle := ["internet", "cloud", "gpu_company", "mining"]
	# Twelve currently operating facilities fill two campuses.  The account has
	# built twenty in total; older sites were retired before this late-game save.
	# This keeps the park selector honest and fully visible on a phone while the
	# IPO progress still reflects the player's complete company history.
	for index: int in range(12):
		var building_id: String = building_cycle[index % building_cycle.size()]
		# Make the first data center the authored 3x3 board used by shot 02.
		if index == 0:
			building_id = "dc_t3"
		var dc := _datacenter(index, building_id, customer_cycle[index % customer_cycle.size()], now)
		plots.append({
			"id": "plot_%d" % (index + 1),
			"index": index + 1,
			"purchase_price": 0.0 if index == 0 else Rules.land_price(index + 1, DataRepository.get_table("economy")),
			"purchased": true,
			"status": "operational",
			"datacenter": dc,
		})
	Game.state["plots"] = plots
	Game.state["construction_queue"] = [{
		"id": "engineering_upgrade_04",
		"type": "technology",
		"technology_id": "construction_bays",
		"started_at": now,
		"complete_at": now + 1840.0,
		"duration_seconds": 3600.0,
		"ad_uses": 0,
	}]
	Game.state["player"].merge({
		"cash": 38642000.0,
		"gems": 320,
		"total_revenue": 183750000.0,
		"brand_multiplier": 1.42,
		"era": 3,
		"network_level": 4,
		"total_datacenters_built": 20,
	}, true)
	Game.state["technology"] = {"repair_team": 3, "construction_bays": 3, "auto_retirement": true}
	Game.state["tutorial"] = {
		"step": 99,
		"completed": true,
		"dismissed_messages": ["first_set_bonus", "first_engineering_bays", "first_inquiry"],
	}
	Game.state["flags"] = {"standard_built": true, "last_presented_era": 3}
	Game.state["stats"].merge({
		"prestige_count": 1,
		"contracts_signed": 31,
		"inquiries_accepted": 9,
		"inquiry_bonus_revenue": 218000.0,
		"highest_net_worth": 51400000.0,
	}, true)
	Game.state["meta"].merge({
		"campus_specializations": {"0": "cloud", "1": "ai_compute"},
		"customer_service_seconds": {"internet": 310000.0, "mining": 151000.0, "cloud": 287000.0, "gpu_company": 194000.0},
		"seen_customers": {"internet": true, "mining": true, "cloud": true, "gpu_company": true},
		"seen_events": {"shopping_festival": true, "coin_boom": true, "cloud_migration": true, "sovereign_ai": true},
		"board_allocations": {"construction": 1, "operations": 1, "business": 0},
		"roadmap_claimed": {"first_facility": true, "campus_operator": true, "cloud_transition": true, "client_portfolio": true, "global_network": true, "first_inquiry": true},
		"company_history": [{
			"prestige_number": 1,
			"total_revenue": 48600000.0,
			"net_worth": 13200000.0,
			"datacenters_built": 20,
			"best_campus": 0,
			"best_campus_income": 143000.0,
			"longest_customer_id": "internet",
			"longest_customer_seconds": 216000.0,
		}],
	}, true)
	_fill_market(now)
	Game.state["inquiries"] = {
		"open": [
			{"id": "inquiry_41", "template_id": "edge_delivery", "slot": 0, "arrived_at": now - 1200.0},
			{"id": "inquiry_42", "template_id": "mining_rush", "slot": 1, "arrived_at": now - 420.0},
		],
		"next_arrival_at": now + 86400.0,
		"cooldowns": {},
		"rng_state": 918273,
		"sequence": 43,
	}
	Game.state["settings"]["locale"] = TranslationServer.get_locale()
	return str((plots[0]["datacenter"] as Dictionary).get("id", ""))


static func _datacenter(index: int, building_id: String, customer_id: String, now: float) -> Dictionary:
	var building := DataRepository.get_entry("buildings", building_id)
	var unlocked: Array = building.get("unlocked_slots", [])
	var racks: Array = []
	racks.resize(9)
	racks.fill(null)
	# The middle row receives ambient cooling only.  Keep it at heat 1 so the
	# showcase is a well-run park while all three rows still earn set bonuses.
	var pattern := ["rack_compute_t2", "rack_compute_t2", "rack_compute_t2", "rack_storage_t1", "rack_storage_t1", "rack_storage_t1", "rack_gpu_t2", "rack_gpu_t2", "rack_gpu_t2"]
	if building_id == "dc_t1":
		pattern = ["rack_compute_t1", "rack_compute_t1", "rack_compute_t1", "rack_storage_t1", "rack_storage_t1", "rack_storage_t1"]
	for slot_variant: Variant in unlocked:
		var slot := int(slot_variant)
		var rack_id: String = pattern[slot % pattern.size()]
		racks[slot] = {
			"rack_id": rack_id,
			"status": "active",
			"enabled": true,
			"installed_at": now - 14400.0 - float(index * 270),
			"fault_at": -1.0,
			"cost": float(DataRepository.get_entry("racks", rack_id).get("cost", 0.0)),
		}
	var power_unit := "power_t2" if building_id == "dc_t1" else "power_t3"
	var coolers := {"north": "cool_air_t2", "south": "cool_air_t2"} if building_id == "dc_t1" else {"north": "cool_liquid_t2", "east": "cool_liquid_t2", "south": "cool_liquid_t2"}
	if building_id == "dc_t3":
		coolers["west"] = "cool_liquid_t2"
	var duration_id := "strategic" if index % 3 == 0 else ("flexible" if index % 3 == 1 else "standard")
	return {
		"id": "dc_%02d" % (index + 1),
		"building_id": building_id,
		"status": "operational",
		"built_at": now - float(building.get("lifespan_seconds", 432000.0)) * (0.12 + float(index % 6) * 0.055),
		"power_unit": power_unit,
		"coolers": coolers,
		"racks": racks,
		"customer_id": customer_id,
		"contract_duration_id": duration_id,
		"contract_income_multiplier": 1.0,
		"locked_market_multiplier": 1.18 + float(index % 4) * 0.04,
		"contract_end_at": now + 21600.0 + float(index % 5) * 3600.0,
		"free_switch_available": index % 4 == 0,
		"persona_id": "",
		"aging_notices": [],
	}


static func _fill_market(now: float) -> void:
	var history: Dictionary = {}
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var values: Array[Dictionary] = []
		for index: int in range(160):
			var wave := sin(float(index) * 0.19 + float(customer_id.length())) * 0.13
			values.append({"at": now - float(159 - index) * 240.0, "value": 1.04 + wave + float(index % 11) * 0.007})
		history[customer_id] = values
	Game.state["market"] = {
		"active": [{"event_id": "sovereign_ai", "started_at": now - 1800.0, "end_at": now + 5400.0}],
		"previews": [{"event_id": "cloud_framework_deal", "previewed_at": now, "start_at": now + 3600.0}],
		"history": history,
		"noise": {"internet": 0.04, "mining": -0.03, "cloud": 0.06, "gpu_company": 0.08},
		"next_noise_at": now + 240.0,
		"next_event_at": now + 10800.0,
		"rng_state": 73471,
	}
