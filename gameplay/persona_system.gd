class_name PersonaSystem
extends RefCounted

static func personas_for_customer(customer_id: String, data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for persona_id: String in data.get("personas", {}).get("items", {}):
		var persona: Dictionary = data["personas"]["items"][persona_id]
		if str(persona.get("customer_id", "")) != customer_id:
			continue
		var copy := persona.duplicate(true)
		copy["id"] = persona_id
		result.append(copy)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var order_delta := int(left.get("order", 0)) - int(right.get("order", 0))
		return order_delta < 0 if order_delta != 0 else str(left.get("id", "")) < str(right.get("id", ""))
	)
	return result

static func persona_for_inquiry(inquiry: Dictionary, data: Dictionary) -> Dictionary:
	var template_id := str(inquiry.get("template_id", ""))
	var template: Dictionary = data.get("inquiries", {}).get("items", {}).get(template_id, {})
	var candidates := personas_for_customer(str(template.get("customer_id", "")), data)
	if candidates.is_empty():
		return {}
	var token := str(inquiry.get("id", "")) + template_id
	var index := int(token.hash()) & 0x7fffffff
	return candidates[index % candidates.size()].duplicate(true)

static func default_persona(customer_id: String, data: Dictionary) -> Dictionary:
	var candidates := personas_for_customer(customer_id, data)
	return candidates[0].duplicate(true) if not candidates.is_empty() else {}

static func persona_by_id(persona_id: String, data: Dictionary) -> Dictionary:
	var persona: Dictionary = data.get("personas", {}).get("items", {}).get(persona_id, {})
	if persona.is_empty():
		return {}
	var copy := persona.duplicate(true)
	copy["id"] = persona_id
	return copy

static func persona_for_contract(datacenter: Dictionary, data: Dictionary) -> Dictionary:
	var stored := persona_by_id(str(datacenter.get("persona_id", "")), data)
	if not stored.is_empty() and str(stored.get("customer_id", "")) == str(datacenter.get("customer_id", "")):
		return stored
	return default_persona(str(datacenter.get("customer_id", "")), data)

static func line_key(persona: Dictionary, category: String, context: String = "") -> String:
	var lines: Array = persona.get("lines", {}).get(category, [])
	if lines.is_empty():
		return ""
	var token := "%s:%s:%s" % [str(persona.get("id", "")), category, context]
	var index := int(token.hash()) & 0x7fffffff
	return str(lines[index % lines.size()])
