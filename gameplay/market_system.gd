class_name MarketSystem
extends RefCounted

func ensure_state(game_state: Dictionary, data: Dictionary) -> void:
	var market: Dictionary = game_state.get("market", {})
	var economy: Dictionary = data.get("economy", {})
	var day_seconds := float(economy.get("time", {}).get("real_seconds_per_game_day", 240.0))
	if not market.has("noise"):
		market["noise"] = {}
		for customer_id: String in data.get("customers", {}).get("items", {}):
			market["noise"][customer_id] = 1.0
	if not market.has("next_noise_at"):
		market["next_noise_at"] = float(game_state.get("clock", {}).get("simulation_seconds", 0.0)) + day_seconds
	if not market.has("next_event_at") or float(market.get("next_event_at", 0.0)) > 1000000000.0:
		market["next_event_at"] = float(economy.get("time", {}).get("real_seconds_per_game_month", 7200.0))
	game_state["market"] = market

func process_due(game_state: Dictionary, data: Dictionary) -> Array[Dictionary]:
	ensure_state(game_state, data)
	var notices: Array[Dictionary] = []
	var market: Dictionary = game_state["market"]
	var now := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var still_active: Array = []
	for active: Dictionary in market.get("active", []):
		if float(active.get("end_at", 0.0)) <= now:
			notices.append({"type": "event_ended", "event_id": active.get("event_id", "")})
		else:
			still_active.append(active)
	market["active"] = still_active
	var still_previews: Array = []
	for preview: Dictionary in market.get("previews", []):
		if float(preview.get("start_at", 0.0)) <= now:
			var event_data: Dictionary = data.get("events", {}).get("items", {}).get(preview.get("event_id", ""), {})
			var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
			market["active"].append({
				"event_id": preview.get("event_id", ""),
				"started_at": float(preview.get("start_at", now)),
				"end_at": float(preview.get("start_at", now)) + float(event_data.get("duration_months", 1)) * month_seconds,
			})
			notices.append({"type": "event_started", "event_id": preview.get("event_id", "")})
		else:
			still_previews.append(preview)
	market["previews"] = still_previews
	_process_noise(game_state, data)
	var config: Dictionary = data.get("economy", {}).get("market", {})
	if now >= float(market.get("next_event_at", 0.0)) and market["active"].size() + market["previews"].size() < int(config.get("max_active_events", 2)):
		var event_id := _pick_event(game_state, data)
		if not event_id.is_empty():
			var start_at := now + float(config.get("preview_seconds", 7200.0))
			market["previews"].append({"event_id": event_id, "previewed_at": now, "start_at": start_at})
			notices.append({"type": "event_previewed", "event_id": event_id})
		var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
		var min_months := float(config.get("event_interval_months_min", 1.0))
		var max_months := float(config.get("event_interval_months_max", 3.0))
		market["next_event_at"] = now + lerpf(min_months, max_months, _random(game_state)) * month_seconds
	game_state["market"] = market
	return notices

func next_transition_after(game_state: Dictionary, after: float, include_noise: bool = true) -> float:
	var market: Dictionary = game_state.get("market", {})
	var result := INF
	var keys: Array[String] = ["next_event_at"]
	if include_noise:
		keys.append("next_noise_at")
	for key: String in keys:
		var value := float(market.get(key, INF))
		if value > after:
			result = minf(result, value)
	for preview: Dictionary in market.get("previews", []):
		var value := float(preview.get("start_at", INF))
		if value > after:
			result = minf(result, value)
	for active: Dictionary in market.get("active", []):
		var value := float(active.get("end_at", INF))
		if value > after:
			result = minf(result, value)
	return result

func customer_multiplier(customer_id: String, game_state: Dictionary, data: Dictionary, include_noise: bool = true) -> float:
	var customer: Dictionary = data.get("customers", {}).get("items", {}).get(customer_id, {})
	var era := str(game_state.get("player", {}).get("era", 1))
	var result := float(customer.get("era_baseline", {}).get(era, 0.0))
	if result <= 0.0:
		return 0.0
	var market: Dictionary = game_state.get("market", {})
	if include_noise:
		result *= float(market.get("noise", {}).get(customer_id, 1.0))
	for active: Dictionary in market.get("active", []):
		var event_data: Dictionary = data.get("events", {}).get("items", {}).get(active.get("event_id", ""), {})
		result *= float(event_data.get("all_customer_multiplier", 1.0))
		result *= float(event_data.get("customer_multipliers", {}).get(customer_id, 1.0))
	return result

func purchase_multiplier(kind: String, game_state: Dictionary, data: Dictionary) -> float:
	var result := 1.0
	for active: Dictionary in game_state.get("market", {}).get("active", []):
		var event_data: Dictionary = data.get("events", {}).get("items", {}).get(active.get("event_id", ""), {})
		result *= float(event_data.get("purchase_multipliers", {}).get(kind, 1.0))
	return result

func snapshot_history(game_state: Dictionary, data: Dictionary, sample_at: float = -1.0) -> void:
	var market: Dictionary = game_state.get("market", {})
	var now := sample_at if sample_at >= 0.0 else float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var limit := int(data.get("economy", {}).get("time", {}).get("market_history_game_days", 730))
	for customer_id: String in data.get("customers", {}).get("items", {}):
		if not market.get("history", {}).has(customer_id):
			market["history"][customer_id] = []
		var series: Array = market["history"][customer_id]
		series.append({"at": now, "value": customer_multiplier(customer_id, game_state, data)})
		if series.size() > limit:
			series = series.slice(series.size() - limit)
		market["history"][customer_id] = series

func _process_noise(game_state: Dictionary, data: Dictionary) -> void:
	var market: Dictionary = game_state["market"]
	var now := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var day_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_day", 240.0))
	var config: Dictionary = data.get("economy", {}).get("market", {})
	while now >= float(market.get("next_noise_at", INF)):
		var sample_at := float(market["next_noise_at"])
		for customer_id: String in data.get("customers", {}).get("items", {}):
			market["noise"][customer_id] = lerpf(float(config.get("noise_min", 0.95)), float(config.get("noise_max", 1.05)), _random(game_state))
		market["next_noise_at"] = float(market["next_noise_at"]) + day_seconds
		snapshot_history(game_state, data, sample_at)

func _pick_event(game_state: Dictionary, data: Dictionary) -> String:
	var player_era := int(game_state.get("player", {}).get("era", 1))
	var network_level := int(game_state.get("player", {}).get("network_level", 1))
	var blocked_customers: Dictionary = {}
	if not bool(data.get("economy", {}).get("market", {}).get("allow_same_customer_event_stack", false)):
		for queued: Dictionary in game_state.get("market", {}).get("active", []) + game_state.get("market", {}).get("previews", []):
			var existing: Dictionary = data.get("events", {}).get("items", {}).get(queued.get("event_id", ""), {})
			for customer_id: String in existing.get("customer_multipliers", {}):
				blocked_customers[customer_id] = true
	var eligible: Array[String] = []
	var total_weight := 0.0
	for event_id: String in data.get("events", {}).get("items", {}):
		var event_data: Dictionary = data["events"]["items"][event_id]
		if int(event_data.get("minimum_era", 1)) > player_era:
			continue
		if int(event_data.get("minimum_network_level", 1)) > network_level:
			continue
		var blocked := false
		for customer_id: String in event_data.get("customer_multipliers", {}):
			if blocked_customers.has(customer_id):
				blocked = true
		if blocked:
			continue
		eligible.append(event_id)
		total_weight += float(event_data.get("weight", 1.0))
	if eligible.is_empty():
		return ""
	var roll := _random(game_state) * total_weight
	for event_id: String in eligible:
		roll -= float(data["events"]["items"][event_id].get("weight", 1.0))
		if roll <= 0.0:
			return event_id
	return eligible[-1]

func _random(game_state: Dictionary) -> float:
	var market: Dictionary = game_state.get("market", {})
	var current := int(market.get("rng_state", 73471))
	current = int((current * 48271) % 2147483647)
	if current <= 0:
		current = 73471
	market["rng_state"] = current
	return float(current) / 2147483647.0
