extends Node

const SAVE_VERSION := 4
const SAVE_PATH := "user://save_v1.json"
const TEMP_PATH := "user://save_v1.tmp"
const BACKUP_COUNT := 3

var last_load_notice_key := ""

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_save() -> Dictionary:
	var candidates: Array[String] = [SAVE_PATH]
	for index: int in range(BACKUP_COUNT):
		candidates.append("user://save_v1.bak%d.json" % index)
	return _load_candidates(candidates)

func load_save_from_paths_for_tests(candidates: Array[String]) -> Dictionary:
	return _load_candidates(candidates)

func consume_load_notice_key() -> String:
	var key := last_load_notice_key
	last_load_notice_key = ""
	return key

func _load_candidates(candidates: Array[String]) -> Dictionary:
	last_load_notice_key = ""
	var found_any_file := false
	for index: int in range(candidates.size()):
		var path := candidates[index]
		found_any_file = found_any_file or FileAccess.file_exists(path)
		var loaded := _read_json(path)
		if not loaded.is_empty():
			if index > 0:
				last_load_notice_key = "TOAST_SAVE_RECOVERED"
			return migrate(loaded)
	if found_any_file:
		last_load_notice_key = "TOAST_SAVE_RESET"
	return {}

func write_save(state: Dictionary) -> bool:
	var payload := state.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to open temporary save file: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	file.close()
	_rotate_backups()
	var absolute_temp := ProjectSettings.globalize_path(TEMP_PATH)
	var absolute_save := ProjectSettings.globalize_path(SAVE_PATH)
	var error := DirAccess.rename_absolute(absolute_temp, absolute_save)
	if error != OK:
		push_error("Atomic save rename failed: %s" % error_string(error))
		return false
	return true

func delete_active_save() -> void:
	for path: String in [SAVE_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func migrate(raw_state: Dictionary) -> Dictionary:
	var version := int(raw_state.get("save_version", 0))
	var migrated := raw_state.duplicate(true)
	if version < 1:
		migrated["save_version"] = 1
	if version < 2:
		migrated["save_version"] = 2
	if version < 3:
		migrated["save_version"] = 3
	if version < 4:
		migrated["save_version"] = 4
	return migrated

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}

func _rotate_backups() -> void:
	var oldest := "user://save_v1.bak%d.json" % (BACKUP_COUNT - 1)
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(oldest))
	for index: int in range(BACKUP_COUNT - 2, -1, -1):
		var source := "user://save_v1.bak%d.json" % index
		var target := "user://save_v1.bak%d.json" % (index + 1)
		if FileAccess.file_exists(source):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path("user://save_v1.bak0.json"))
