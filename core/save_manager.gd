extends Node

const SAVE_VERSION := 2
const SAVE_PATH := "user://save_v1.json"
const TEMP_PATH := "user://save_v1.tmp"
const BACKUP_COUNT := 3

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_save() -> Dictionary:
	var candidates := [SAVE_PATH]
	for index: int in range(BACKUP_COUNT):
		candidates.append("user://save_v1.bak%d.json" % index)
	for path: String in candidates:
		var loaded := _read_json(path)
		if not loaded.is_empty():
			return migrate(loaded)
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

func archive_game_over(state: Dictionary) -> bool:
	var stamp := int(Time.get_unix_time_from_system())
	var path := "user://save_gameover_%d.json" % stamp
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state, "\t", false))
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
	return migrated

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
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
