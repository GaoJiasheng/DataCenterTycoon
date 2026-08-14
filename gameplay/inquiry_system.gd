class_name InquirySystem
extends RefCounted

const Rules := preload("res://gameplay/game_rules.gd")
const DEFAULT_RNG_STATE := 918273

func ensure_state(game_state: Dictionary, data: Dictionary) -> void:
	var inquiry_state: Dictionary = game_state.get("inquiries", {})
	if not inquiry_state.get("open") is Array:
		inquiry_state["open"] = []
	if not inquiry_state.get("cooldowns") is Dictionary:
		inquiry_state["cooldowns"] = {}
	if not inquiry_state.has("next_arrival_at"):
		inquiry_state["next_arrival_at"] = 0.0
	if int(inquiry_state.get("rng_state", 0)) <= 0:
		inquiry_state["rng_state"] = DEFAULT_RNG_STATE
	if not inquiry_state.has("sequence"):
		inquiry_state["sequence"] = 0
	game_state["inquiries"] = inquiry_state

func is_enabled(game_state: Dictionary, data: Dictionary) -> bool:
	var settings: Dictionary = data.get("inquiries", {}).get("settings", {})
	return bool(game_state.get("tutorial", {}).get("completed", false)) \
		and int(game_state.get("player", {}).get("total_datacenters_built", 0)) >= int(settings.get("min_datacenters_built", 2))

func process(game_state: Dictionary, data: Dictionary) -> Array[Dictionary]:
	ensure_state(game_state, data)
	var notices: Array[Dictionary] = []
	if not is_enabled(game_state, data):
		return notices
	var inquiry_state: Dictionary = game_state["inquiries"]
	var settings: Dictionary = data.get("inquiries", {}).get("settings", {})
	var now := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var max_open := int(settings.get("max_open", 3))
	var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
	for key: String in inquiry_state.get("cooldowns", {}).keys():
		if float(inquiry_state["cooldowns"].get(key, 0.0)) <= now:
			inquiry_state["cooldowns"].erase(key)
	if float(inquiry_state.get("next_arrival_at", 0.0)) <= 0.0:
		inquiry_state["next_arrival_at"] = now
	var guard := 0
	while inquiry_state.get("open", []).size() < max_open and now >= float(inquiry_state.get("next_arrival_at", INF)) and guard < max_open + 2:
		guard += 1
		var due_at := float(inquiry_state.get("next_arrival_at", now))
		var slot := _available_slot(inquiry_state, max_open, due_at)
		if slot < 0:
			var cooldown_boundary := _next_cooldown_after(inquiry_state, due_at)
			inquiry_state["next_arrival_at"] = cooldown_boundary
			break
		var template_id := _pick_template(game_state, data)
		if template_id.is_empty():
			inquiry_state["next_arrival_at"] = due_at + _arrival_interval(inquiry_state, settings, month_seconds)
			break
		var sequence := int(inquiry_state.get("sequence", 0)) + 1
		inquiry_state["sequence"] = sequence
		var inquiry := {
			"id": "inquiry_%d" % sequence,
			"template_id": template_id,
			"slot": slot,
			"arrived_at": due_at,
		}
		inquiry_state["open"].append(inquiry)
		notices.append({"type": "inquiry_arrived", "inquiry_id": inquiry["id"], "template_id": template_id, "slot": slot, "arrived_at": due_at})
		inquiry_state["next_arrival_at"] = due_at + _arrival_interval(inquiry_state, settings, month_seconds)
	game_state["inquiries"] = inquiry_state
	return notices

func next_transition_after(game_state: Dictionary, data: Dictionary, after: float) -> float:
	if not is_enabled(game_state, data):
		return INF
	var inquiry_state: Dictionary = game_state.get("inquiries", {})
	var max_open := int(data.get("inquiries", {}).get("settings", {}).get("max_open", 3))
	if inquiry_state.get("open", []).size() >= max_open:
		return INF
	var value := float(inquiry_state.get("next_arrival_at", INF))
	return value if value > after else INF

func find_open(inquiry_id: String, game_state: Dictionary) -> Dictionary:
	for inquiry: Dictionary in game_state.get("inquiries", {}).get("open", []):
		if str(inquiry.get("id", "")) == inquiry_id:
			return inquiry
	return {}

func template_for(inquiry: Dictionary, data: Dictionary) -> Dictionary:
	return data.get("inquiries", {}).get("items", {}).get(str(inquiry.get("template_id", "")), {})

func evaluate(inquiry: Dictionary, datacenter: Dictionary, game_state: Dictionary, data: Dictionary) -> Dictionary:
	var template := template_for(inquiry, data)
	if template.is_empty() or datacenter.is_empty():
		return {"eligible": false, "checks": [], "reason": "missing"}
	var checks: Array[Dictionary] = []
	checks.append(_check("operational", 1 if str(datacenter.get("status", "")) == "operational" else 0, 1))
	var requirements: Dictionary = template.get("requirements", {})
	var snapshot := Rules.rack_requirement_snapshot([datacenter], data)
	if requirements.has("rack_kind"):
		var kind := str(requirements.get("rack_kind", ""))
		checks.append(_check("rack_kind:%s" % kind, int(snapshot.get("kind_counts", {}).get(kind, 0)), int(requirements.get("rack_count", 0))))
	if requirements.has("unique_rack_kinds"):
		checks.append(_check("unique_rack_kinds", int(snapshot.get("unique_kind_count", 0)), int(requirements.get("unique_rack_kinds", 0))))
	if requirements.has("network_level"):
		checks.append(_check("network_level", int(game_state.get("player", {}).get("network_level", 1)), int(requirements.get("network_level", 1))))
	if requirements.has("relationship_level"):
		var customer_id := str(template.get("customer_id", ""))
		checks.append(_check("relationship_level", int(Rules.relationship_level(customer_id, game_state, data).get("index", 0)), int(requirements.get("relationship_level", 0))))
	if requirements.has("specialization"):
		var plot_index := _plot_index_for_datacenter(str(datacenter.get("id", "")), game_state)
		var campus_index := int(Rules.campus_layout_for_plot(plot_index, data.get("economy", {})).get("campus_index", -1)) if plot_index > 0 else -1
		var specialization_id := str(requirements.get("specialization", ""))
		var selected := str(game_state.get("meta", {}).get("campus_specializations", {}).get(str(campus_index), "")) == specialization_id
		var active := selected and bool(Rules.campus_specialization_status(campus_index, specialization_id, game_state, data).get("active", false))
		checks.append(_check("specialization:%s" % specialization_id, 1 if active else 0, 1))
	var eligible := true
	for check: Dictionary in checks:
		if not bool(check.get("met", false)):
			eligible = false
			break
	return {"eligible": eligible, "checks": checks, "reason": "ready" if eligible else "requirements"}

func decline(inquiry_id: String, game_state: Dictionary, data: Dictionary) -> Dictionary:
	ensure_state(game_state, data)
	var inquiry := find_open(inquiry_id, game_state)
	if inquiry.is_empty():
		return {"ok": false, "reason": "inquiry_unavailable"}
	var inquiry_state: Dictionary = game_state["inquiries"]
	var retained: Array = []
	for item: Dictionary in inquiry_state.get("open", []):
		if str(item.get("id", "")) != inquiry_id:
			retained.append(item)
	inquiry_state["open"] = retained
	var now := float(game_state.get("clock", {}).get("simulation_seconds", 0.0))
	var month_seconds := float(data.get("economy", {}).get("time", {}).get("real_seconds_per_game_month", 7200.0))
	var cooldown := float(data.get("inquiries", {}).get("settings", {}).get("decline_cooldown_months", 2.0)) * month_seconds
	var ready_at := now + cooldown
	inquiry_state["cooldowns"][str(int(inquiry.get("slot", 0)))] = ready_at
	if float(inquiry_state.get("next_arrival_at", INF)) < now or float(inquiry_state.get("next_arrival_at", INF)) > ready_at:
		inquiry_state["next_arrival_at"] = ready_at
	return {"ok": true, "inquiry_id": inquiry_id, "slot": int(inquiry.get("slot", 0)), "refill_at": ready_at}

func accept(inquiry_id: String, datacenter: Dictionary, game_state: Dictionary, data: Dictionary, quote: Dictionary, sign_contract: Callable) -> Dictionary:
	var inquiry := find_open(inquiry_id, game_state)
	if inquiry.is_empty():
		return {"ok": false, "reason": "inquiry_unavailable"}
	var template := template_for(inquiry, data)
	var evaluation := evaluate(inquiry, datacenter, game_state, data)
	if not bool(evaluation.get("eligible", false)):
		return {"ok": false, "reason": "inquiry_requirements", "evaluation": evaluation}
	if str(quote.get("inquiry_id", "")) != inquiry_id or str(quote.get("datacenter_id", "")) != str(datacenter.get("id", "")) or str(quote.get("template_id", "")) != str(inquiry.get("template_id", "")):
		return {"ok": false, "reason": "inquiry_quote_stale"}
	var premium := float(template.get("premium", 1.0))
	var locked_rate := float(quote.get("locked_market_multiplier", 0.0))
	var signed: Dictionary = sign_contract.call(str(datacenter.get("id", "")), str(template.get("customer_id", "")), str(template.get("duration_id", "standard")), premium, locked_rate, false)
	if not bool(signed.get("ok", false)):
		return signed
	var bonus := maxf(0.0, float(quote.get("bonus", 0.0)))
	game_state["player"]["cash"] = float(game_state.get("player", {}).get("cash", 0.0)) + bonus
	game_state["player"]["total_revenue"] = float(game_state.get("player", {}).get("total_revenue", 0.0)) + bonus
	var customer_id := str(template.get("customer_id", ""))
	game_state["meta"]["customer_service_seconds"][customer_id] = float(game_state.get("meta", {}).get("customer_service_seconds", {}).get(customer_id, 0.0)) + float(template.get("bonus_service_seconds", 0.0))
	game_state["stats"]["inquiries_accepted"] = int(game_state.get("stats", {}).get("inquiries_accepted", 0)) + 1
	game_state["stats"]["inquiry_bonus_revenue"] = float(game_state.get("stats", {}).get("inquiry_bonus_revenue", 0.0)) + bonus
	datacenter["inquiry_contract_id"] = inquiry_id
	datacenter["inquiry_template_id"] = str(inquiry.get("template_id", ""))
	datacenter["inquiry_premium"] = premium
	remove_open(inquiry_id, game_state)
	return {
		"ok": true,
		"inquiry_id": inquiry_id,
		"datacenter_id": str(datacenter.get("id", "")),
		"customer_id": customer_id,
		"bonus": bonus,
		"locked_market_multiplier": locked_rate,
		"projected": float(quote.get("projected", 0.0)),
	}

func remove_open(inquiry_id: String, game_state: Dictionary) -> void:
	var retained: Array = []
	for item: Dictionary in game_state.get("inquiries", {}).get("open", []):
		if str(item.get("id", "")) != inquiry_id:
			retained.append(item)
	game_state["inquiries"]["open"] = retained

func _check(kind: String, current: int, target: int) -> Dictionary:
	return {"kind": kind, "current": current, "target": target, "met": current >= target}

func _plot_index_for_datacenter(datacenter_id: String, game_state: Dictionary) -> int:
	for plot: Dictionary in game_state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and str((dc as Dictionary).get("id", "")) == datacenter_id:
			return int(plot.get("index", 1))
	return -1

func _available_slot(inquiry_state: Dictionary, max_open: int, at: float) -> int:
	var occupied := {}
	for inquiry: Dictionary in inquiry_state.get("open", []):
		occupied[int(inquiry.get("slot", -1))] = true
	for slot: int in range(max_open):
		if occupied.has(slot):
			continue
		if float(inquiry_state.get("cooldowns", {}).get(str(slot), 0.0)) <= at:
			return slot
	return -1

func _next_cooldown_after(inquiry_state: Dictionary, after: float) -> float:
	var result := INF
	for value: Variant in inquiry_state.get("cooldowns", {}).values():
		if float(value) > after:
			result = minf(result, float(value))
	return result

func _arrival_interval(inquiry_state: Dictionary, settings: Dictionary, month_seconds: float) -> float:
	var minimum := float(settings.get("arrival_months_min", 4.0))
	var maximum := float(settings.get("arrival_months_max", 8.0))
	return lerpf(minimum, maximum, _random(inquiry_state)) * month_seconds

func _pick_template(game_state: Dictionary, data: Dictionary) -> String:
	var inquiry_state: Dictionary = game_state["inquiries"]
	var player_era := int(game_state.get("player", {}).get("era", 1))
	var network_level := int(game_state.get("player", {}).get("network_level", 1))
	var eligible: Array[String] = []
	var total_weight := 0.0
	for template_id: String in data.get("inquiries", {}).get("items", {}):
		var template: Dictionary = data["inquiries"]["items"][template_id]
		var customer_id := str(template.get("customer_id", ""))
		var customer: Dictionary = data.get("customers", {}).get("items", {}).get(customer_id, {})
		if customer.is_empty() or int(template.get("unlock_era", 1)) > player_era or int(customer.get("unlock_era", 1)) > player_era:
			continue
		if int(template.get("minimum_network_level", 1)) > network_level or int(customer.get("minimum_network_level", 1)) > network_level:
			continue
		var duration: Dictionary = data.get("meta_progression", {}).get("contract_durations", {}).get(str(template.get("duration_id", "")), {})
		if int(Rules.relationship_level(customer_id, game_state, data).get("index", 0)) < int(duration.get("relationship_level_required", 0)):
			continue
		var weight := maxf(0.0, float(template.get("weight", 0.0)))
		if weight <= 0.0:
			continue
		eligible.append(template_id)
		total_weight += weight
	if eligible.is_empty() or total_weight <= 0.0:
		return ""
	var roll := _random(inquiry_state) * total_weight
	var cursor := 0.0
	for template_id: String in eligible:
		cursor += float(data["inquiries"]["items"][template_id].get("weight", 0.0))
		if roll <= cursor:
			return template_id
	return eligible.back()

func _random(inquiry_state: Dictionary) -> float:
	var value := int(inquiry_state.get("rng_state", DEFAULT_RNG_STATE))
	value = int((value * 48271) % 2147483647)
	if value <= 0:
		value = DEFAULT_RNG_STATE
	inquiry_state["rng_state"] = value
	return float(value) / 2147483647.0
