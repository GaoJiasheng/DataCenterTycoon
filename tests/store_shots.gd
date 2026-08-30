extends Node

const MAIN_SCENE := preload("res://main.tscn")
const ShowcaseFixture := preload("res://tests/store_showcase_fixture.gd")
const Rules := preload("res://gameplay/game_rules.gd")
const LOGICAL_SIZE := Vector2i(804, 1748)
const DEVICE_SIZES := {
	"iphone_69": Vector2i(1320, 2868),
	"ipad_13": Vector2i(2048, 2732),
}
const SHOTS := [
	{"file": "01_park.png", "page": "park"},
	{"file": "02_datacenter.png", "page": "datacenter"},
	{"file": "03_market.png", "page": "market"},
	{"file": "04_technology.png", "page": "technology"},
	{"file": "05_prestige.png", "page": "prestige"},
]
const GUTTER_COLOR := Color("122438")

var capture_locale := "zh_CN"
var capture_device := "iphone_69"
var target_size: Vector2i = DEVICE_SIZES["iphone_69"]
var content_size := Vector2i.ZERO
var target_datacenter_id := ""
var capture_viewport: SubViewport
var main: Control


func _ready() -> void:
	var requested_locale := _argument("locale", "zh_CN")
	var requested_device := _argument("device", "iphone_69")
	if requested_locale not in ["en", "zh_CN", "all"] or requested_device not in ["iphone_69", "ipad_13", "all"]:
		push_error("STORE_SHOTS: expected --locale=en|zh_CN|all --device=iphone_69|ipad_13|all")
		get_tree().quit(2)
		return
	Game.persistence_enabled = false
	Game.last_offline_report = {}
	var locales := ["en", "zh_CN"] if requested_locale == "all" else [requested_locale]
	var devices := ["iphone_69", "ipad_13"] if requested_device == "all" else [requested_device]
	var valid := true
	for locale: String in locales:
		for device: String in devices:
			valid = (await _run_configuration(locale, device)) and valid
	_finish(valid)


func _run_configuration(locale: String, device: String) -> bool:
	capture_locale = locale
	capture_device = device
	target_size = DEVICE_SIZES[capture_device]
	TranslationServer.set_locale(capture_locale)
	target_datacenter_id = ShowcaseFixture.apply()
	_create_capture_viewport()
	await _settle(5)
	var valid := true
	if _has_flag("probe-only"):
		var probe_path := "/tmp/data_center_tycoon_store_probe_%s.png" % capture_device
		valid = await _save_frame(probe_path)
		print("STORE_SHOTS: %s native probe %s target=%s content=%s -> %s" % ["PASS" if valid else "FAIL", capture_device, target_size, content_size, probe_path])
	else:
		for shot: Dictionary in SHOTS:
			valid = (await _stage_and_capture(str(shot["page"]), str(shot["file"]))) and valid
	print("STORE_SHOTS: %s locale=%s device=%s target=%dx%d content=%dx%d" % ["PASS" if valid else "FAIL", capture_locale, capture_device, target_size.x, target_size.y, content_size.x, content_size.y])
	AudioService.stop_all()
	main.queue_free()
	capture_viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	main = null
	capture_viewport = null
	return valid


func _create_capture_viewport() -> void:
	var scale := minf(float(target_size.x) / float(LOGICAL_SIZE.x), float(target_size.y) / float(LOGICAL_SIZE.y))
	content_size = Vector2i(roundi(float(LOGICAL_SIZE.x) * scale), roundi(float(LOGICAL_SIZE.y) * scale))
	capture_viewport = SubViewport.new()
	capture_viewport.name = "StoreCaptureViewport"
	capture_viewport.size = content_size
	capture_viewport.size_2d_override = LOGICAL_SIZE
	capture_viewport.size_2d_override_stretch = true
	capture_viewport.transparent_bg = false
	capture_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.gui_embed_subwindows = true
	add_child(capture_viewport)
	main = MAIN_SCENE.instantiate() as Control
	capture_viewport.add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _stage_and_capture(page: String, file_name: String) -> bool:
	_clear_transient_feedback()
	match page:
		"park":
			main.call("_navigate", "map")
			main.call("_refresh")
			await get_tree().process_frame
			var park_map := main.get("park_map") as Node
			if park_map != null:
				park_map.call("focus_campus", 0, false)
				park_map.call("force_cat_state_for_tests", "stroll")
		"datacenter":
			main.call("_open_datacenter_detail", target_datacenter_id, "board")
		"market":
			main.call("_navigate", "market")
		"technology":
			main.call("_navigate", "tech")
			main.call("_set_tech_section", "upgrades")
		"prestige":
			main.call("_navigate", "tech")
			main.call("_set_tech_section", "upgrades")
	main.call("_refresh")
	await _settle(4)
	if not _validate_stage(page):
		return false
	if page == "technology":
		var page_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		var bays_card := main.find_child("ConstructionBaysCard", true, false) as Control
		if page_scroll != null and bays_card != null:
			page_scroll.ensure_control_visible(bays_card)
			await _settle(3)
	elif page == "prestige":
		var page_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		var prestige_card := main.find_child("PrestigeCard", true, false) as Control
		if page_scroll != null and prestige_card != null:
			page_scroll.ensure_control_visible(prestige_card)
			await _settle(3)
	var output_dir := "res://docs/store/screenshots/%s/%s" % [capture_locale, capture_device]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var output_path := "%s/%s" % [output_dir, file_name]
	var saved := await _save_frame(ProjectSettings.globalize_path(output_path))
	if not saved:
		push_error("STORE_SHOTS: failed %s" % output_path)
	else:
		print("STORE_SHOTS: wrote %s" % output_path)
	return saved


func _validate_stage(page: String) -> bool:
	var valid := true
	match page:
		"park":
			var operational := 0
			var tiers: Dictionary = {}
			for plot: Dictionary in Game.state.get("plots", []):
				var dc: Dictionary = plot.get("datacenter", {})
				if str(dc.get("status", "")) == "operational":
					operational += 1
					tiers[str(dc.get("building_id", ""))] = true
			valid = operational >= 5 and tiers.size() >= 3
		"datacenter":
			var target: Dictionary = Game.find_datacenter(target_datacenter_id)
			var occupied := 0
			for rack: Variant in target.get("racks", []):
				if rack is Dictionary and not (rack as Dictionary).is_empty():
					occupied += 1
			valid = occupied == 9 and Rules.set_bonus_slots(
				target,
				DataRepository.get_table("racks"),
				DataRepository.get_table("attachments")
			).count(true) == 9
		"market":
			var market: Dictionary = Game.state.get("market", {})
			var rich_history := true
			for customer_id: String in DataRepository.get_table("customers").get("items", {}):
				rich_history = rich_history and (market.get("history", {}).get(customer_id, []) as Array).size() >= 120
			var active_count := (market.get("active", []) as Array).size()
			var preview_count := (market.get("previews", []) as Array).size()
			var inquiry_count := (Game.state.get("inquiries", {}).get("open", []) as Array).size()
			var has_chart := main.find_child("MarketChart", true, false) != null
			var portrait_count := main.find_children("InquiryPersonaPortrait", "", true, false).size()
			valid = rich_history and active_count >= 1 and preview_count >= 1 and inquiry_count >= 2 and has_chart and portrait_count >= 2
			if not valid:
				print("STORE_SHOTS: market diagnostic history=%s active=%d preview=%d inquiries=%d chart=%s portraits=%d" % [rich_history, active_count, preview_count, inquiry_count, has_chart, portrait_count])
		"technology":
			valid = int(Game.state.get("player", {}).get("era", 0)) >= 3 \
				and int(Game.state.get("player", {}).get("network_level", 0)) >= 4 \
				and int(Game.state.get("technology", {}).get("repair_team", 0)) >= 3 \
				and main.find_child("ConstructionBaysCard", true, false) != null
		"prestige":
			valid = int(Game.state.get("player", {}).get("total_datacenters_built", 0)) >= 20 \
				and main.find_child("PrestigeCard", true, false) != null
	if not valid:
		push_error("STORE_SHOTS: staged content contract failed for %s" % page)
	return valid


func _save_frame(output_path: String) -> bool:
	await RenderingServer.frame_post_draw
	var content := capture_viewport.get_texture().get_image()
	if content == null or content.is_empty() or content.get_size() != content_size:
		push_error("STORE_SHOTS: empty or incorrectly sized native frame expected=%s actual=%s" % [content_size, content.get_size() if content != null else Vector2i.ZERO])
		return false
	content.convert(Image.FORMAT_RGB8)
	var framed := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGB8)
	framed.fill(GUTTER_COLOR)
	var offset := Vector2i((target_size.x - content_size.x) / 2, (target_size.y - content_size.y) / 2)
	framed.blit_rect(content, Rect2i(Vector2i.ZERO, content_size), offset)
	return framed.save_png(output_path) == OK


func _settle(frame_count: int) -> void:
	# Store captures call the authoritative refresh methods synchronously.  A
	# short frame drain is sufficient and avoids rendering dozens of full native
	# frames merely to advance a wall-clock timer in headless software rendering.
	for _frame: int in range(frame_count):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _clear_transient_feedback() -> void:
	var toast := main.get("toast_label") as Label
	if toast != null:
		toast.visible = false
	var toast_tween := main.get("_toast_tween") as Tween
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()


func _argument(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback


func _has_flag(name: String) -> bool:
	return "--%s" % name in OS.get_cmdline_user_args()


func _finish(valid: bool) -> void:
	AudioService.stop_all()
	get_tree().quit(0 if valid else 1)
