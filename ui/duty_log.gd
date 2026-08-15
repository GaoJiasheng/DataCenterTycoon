class_name DutyLog
extends RefCounted

const MAX_ROWS := 4
const PersonaSystemScene := preload("res://gameplay/persona_system.gd")
const CampusCatScene := preload("res://gameplay/map/campus_cat.gd")

static func compose(report: Dictionary, data: Dictionary, game_state: Dictionary) -> Array[Dictionary]:
	var config: Dictionary = data.get("duty_log", {}).get("entries", {})
	if config.is_empty():
		return []
	var candidates: Array[Dictionary] = []
	_append_count_candidate(candidates, "takeover", report.get("takeovers", []).size(), config)
	_append_count_candidate(candidates, "era", report.get("eras", []).size(), config)
	var rare_name := _rare_event_name(report, data)
	if not rare_name.is_empty():
		_append_candidate(candidates, "rare_market", [rare_name], config)
	var inquiry_count: int = report.get("inquiries", []).size()
	if inquiry_count > 0:
		_append_candidate(candidates, "inquiry", [_inquiry_persona_name(report, data), inquiry_count], config)
	_append_count_candidate(candidates, "fault", report.get("faults", []).size(), config)
	var renewals := 0
	for contract: Dictionary in report.get("contracts", []):
		if str(contract.get("type", "")) == "contract_auto_renewed":
			renewals += 1
	_append_count_candidate(candidates, "contract", renewals, config)
	_append_count_candidate(candidates, "aging", report.get("aging", []).size(), config)
	# Quiet nights get one warm observation only after the cat has legitimately
	# moved in. Operational events always take precedence over this fallback.
	if candidates.is_empty() and CampusCatScene.is_unlocked(game_state, data.get("campus_cat", {})):
		_append_candidate(candidates, "cat", [], config)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("priority", 0)) > int(right.get("priority", 0))
	)
	# Revenue is always the authoritative report value. It is appended after the
	# three most important happenings so the narrative can never hide the bill.
	var selected: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if selected.size() >= MAX_ROWS - 1:
			break
		selected.append(candidate)
	_append_candidate(selected, "income", [Game.format_number(float(report.get("income", 0.0)))], config)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_canonical(report).hash()) & 0x7fffffff
	var result: Array[Dictionary] = []
	for candidate: Dictionary in selected:
		var templates: Array = candidate.get("templates", [])
		if templates.is_empty():
			continue
		var key: String = str(templates[rng.randi_range(0, templates.size() - 1)])
		var translated: String = TranslationServer.translate(key)
		var args: Array = candidate.get("args", [])
		var rendered: String = translated % args if not args.is_empty() else translated
		result.append({
			"type": str(candidate.get("type", "income")),
			"text": rendered,
			"icon_asset": str(candidate.get("icon_asset", "ic_check")),
			"authoritative_income": float(report.get("income", 0.0)) if str(candidate.get("type", "")) == "income" else -1.0,
		})
	return result

static func _append_count_candidate(target: Array[Dictionary], type: String, count: int, config: Dictionary) -> void:
	if count > 0:
		_append_candidate(target, type, [count], config)

static func _append_candidate(target: Array[Dictionary], type: String, args: Array, config: Dictionary) -> void:
	var entry: Dictionary = config.get(type, {})
	if entry.is_empty():
		return
	target.append({
		"type": type,
		"priority": int(entry.get("priority", 0)),
		"templates": entry.get("templates", []),
		"icon_asset": str(entry.get("icon_asset", "ic_check")),
		"args": args,
	})

static func _rare_event_name(report: Dictionary, data: Dictionary) -> String:
	for notice: Dictionary in report.get("events", []):
		if str(notice.get("type", "")) not in ["event_started", "event_previewed", ""]:
			continue
		var event: Dictionary = data.get("events", {}).get("items", {}).get(str(notice.get("event_id", "")), {})
		if bool(event.get("rare", false)):
			return TranslationServer.translate(str(event.get("name_key", "NAV_MARKET")))
	return ""

static func _inquiry_persona_name(report: Dictionary, data: Dictionary) -> String:
	var notices: Array = report.get("inquiries", [])
	if notices.is_empty():
		return TranslationServer.translate("INQUIRY_BOARD")
	var notice: Dictionary = notices[0]
	var inquiry := {"id": str(notice.get("inquiry_id", notice.get("id", ""))), "template_id": str(notice.get("template_id", ""))}
	var persona := PersonaSystemScene.persona_for_inquiry(inquiry, data)
	if not persona.is_empty():
		return TranslationServer.translate(str(persona.get("name_key", "")))
	var template: Dictionary = data.get("inquiries", {}).get("items", {}).get(str(inquiry.get("template_id", "")), {})
	var customer: Dictionary = data.get("customers", {}).get("items", {}).get(str(template.get("customer_id", "")), {})
	return TranslationServer.translate(str(customer.get("name_key", "INQUIRY_BOARD")))

static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
		var parts: PackedStringArray = []
		for key: Variant in keys:
			parts.append("%s:%s" % [str(key), _canonical((value as Dictionary)[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: PackedStringArray = []
		for item: Variant in value:
			parts.append(_canonical(item))
		return "[%s]" % ",".join(parts)
	return JSON.stringify(value)
