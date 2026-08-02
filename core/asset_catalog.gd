extends Node

const MANIFEST_PATH := "res://assets/art/manifest.json"

var manifest: Dictionary = {}
var missing_once: Dictionary = {}

func _ready() -> void:
	reload_manifest()

func reload_manifest() -> void:
	manifest.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		manifest = parsed
		_expand_groups()

func texture(asset_id: String) -> Texture2D:
	var item: Dictionary = manifest.get("items", {}).get(asset_id, {})
	var path := str(item.get("path", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not missing_once.has(asset_id):
		missing_once[asset_id] = true
	return null

func has_asset(asset_id: String) -> bool:
	return texture(asset_id) != null

func expected_size(asset_id: String) -> Vector2i:
	var item: Dictionary = manifest.get("items", {}).get(asset_id, {})
	var size: Array = item.get("size", [0, 0])
	return Vector2i(int(size[0]), int(size[1])) if size.size() == 2 else Vector2i.ZERO

func _expand_groups() -> void:
	var items: Dictionary = manifest.get("items", {})
	for group: Dictionary in manifest.get("groups", []):
		var directory := str(group.get("directory", ""))
		for asset_id: String in group.get("ids", []):
			items[asset_id] = {
				"path": "res://assets/art/%s/%s.png" % [directory, asset_id],
				"size": group.get("size", [0, 0]),
				"alpha": bool(group.get("alpha", true)),
				"max_bytes": int(group.get("max_bytes", 1572864)),
			}
	manifest["items"] = items
