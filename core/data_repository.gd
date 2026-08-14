extends Node

const DATA_FILES := {
	"economy": "res://data/economy.json",
	"buildings": "res://data/buildings.json",
	"racks": "res://data/racks.json",
	"attachments": "res://data/attachments.json",
	"customers": "res://data/customers.json",
	"events": "res://data/events.json",
	"eras": "res://data/eras.json",
	"technology": "res://data/technology.json",
	"achievements": "res://data/achievements.json",
	"store": "res://data/store.json",
	"tutorial": "res://data/tutorial.json",
	"meta_progression": "res://data/meta_progression.json",
	"inquiries": "res://data/inquiries.json",
}

var tables: Dictionary = {}
var errors: PackedStringArray = []

func _ready() -> void:
	reload_all()

func reload_all() -> bool:
	tables.clear()
	errors.clear()
	for table_name: String in DATA_FILES:
		var path: String = DATA_FILES[table_name]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Missing data file: %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed == null or not parsed is Dictionary:
			errors.append("Invalid JSON object: %s" % path)
			continue
		tables[table_name] = parsed
	if not errors.is_empty():
		for message: String in errors:
			push_error(message)
	return errors.is_empty()

func get_table(table_name: String) -> Dictionary:
	return tables.get(table_name, {})

func get_entry(table_name: String, entry_id: String) -> Dictionary:
	var table: Dictionary = get_table(table_name)
	var entries: Variant = table.get("items", {})
	if entries is Dictionary:
		return entries.get(entry_id, {})
	return {}

func require_entry(table_name: String, entry_id: String) -> Dictionary:
	var entry := get_entry(table_name, entry_id)
	assert(not entry.is_empty(), "Missing data entry %s/%s" % [table_name, entry_id])
	return entry

func validate_references() -> PackedStringArray:
	var issues := PackedStringArray()
	for rack_id: String in get_table("racks").get("items", {}):
		var rack: Dictionary = get_entry("racks", rack_id)
		if not get_table("eras").get("items", {}).has(str(int(rack.get("unlock_era", 1)))):
			issues.append("Rack %s references missing era" % rack_id)
	for event_id: String in get_table("events").get("items", {}):
		var event: Dictionary = get_entry("events", event_id)
		for customer_id: String in event.get("customer_multipliers", {}):
			if not get_table("customers").get("items", {}).has(customer_id):
				issues.append("Event %s references missing customer %s" % [event_id, customer_id])
	for inquiry_id: String in get_table("inquiries").get("items", {}):
		var inquiry: Dictionary = get_entry("inquiries", inquiry_id)
		if not get_table("customers").get("items", {}).has(str(inquiry.get("customer_id", ""))):
			issues.append("Inquiry %s references missing customer" % inquiry_id)
		if not get_table("meta_progression").get("contract_durations", {}).has(str(inquiry.get("duration_id", ""))):
			issues.append("Inquiry %s references missing duration" % inquiry_id)
	return issues
