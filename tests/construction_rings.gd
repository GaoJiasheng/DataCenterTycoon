extends Node

const MAIN_SCENE := preload("res://main.tscn")
var main: Node
var failures := 0

func _ready() -> void:
	TranslationServer.set_locale("en" if "--locale=en" in OS.get_cmdline_user_args() else "zh_CN")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(990, 2151))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.set_process(false)
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 1000000.0
	Game.state["player"]["era"] = 2
	Game.state["technology"]["construction_bays"] = 4
	Game.start_datacenter_construction("plot_1", "dc_t2")
	Game.advance_time(15000.0, false)
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var dc_id := str(dc.get("id", ""))
	Game.install_power(dc_id, "power_t1")
	Game.install_cooler(dc_id, "north", "cool_air_t1")
	Game.install_cooler(dc_id, "east", "cool_liquid_t1")
	Game.install_rack(dc_id, 0, "rack_compute_t1")
	Game.install_rack(dc_id, 1, "rack_storage_t1")
	Game.buy_next_plot()
	var site_result := Game.start_datacenter_construction("plot_2", "dc_t1")
	_check(bool(site_result.get("ok", false)), "fixture can construct an IDC alongside equipment")
	Game.state["flags"]["last_presented_era"] = int(Game.state["player"]["era"])
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _settle()
	main.park_map.set_preview_hour(12.0)
	_check(not main.tutorial_overlay.visible and not main.tutorial_hint_button.visible, "experienced players have no installation coach popup")
	var icons: Array[String] = []
	for node: Node in main.park_map.find_children("InstallProgress_*", "", true, false):
		icons.append(str(node.get_meta("icon_id", "")))
	_check(icons.size() == 4 and "ic_power" in icons and "cool_air_t1_active" in icons and "cool_liquid_t1_active" in icons and "rack_compute_t1_active" in icons, "map distinguishes power, rack, air, and liquid installations")
	var rack_group: ProgressBar
	for node: Node in main.park_map.find_children("InstallProgress_*", "", true, false):
		if str(node.get_meta("icon_id", "")) == "rack_compute_t1_active":
			rack_group = node as ProgressBar
	_check(rack_group != null and int(rack_group.get_meta("job_count", 0)) == 2, "concurrent racks retain a visible count without crowding the building")
	Game.advance_time(60.0, false)
	await _settle()
	await _shot("map")
	var world_build := main.find_child("ConstructionProgress", true, false) as ProgressBar
	_check(world_build != null and world_build.value > 0.0, "IDC progress is attached to its construction site and advances")
	main.call("_show_site_construction", str(site_result["construction"]["id"]))
	await _settle()
	_check(main.find_child("SiteConstructionRing", true, false) != null, "tapping a construction site exposes its own clock progress")
	await _shot("site")
	var site_remaining := main.get_node("ConstructionContext").find_children("*", "Label", true, false)
	var original_copy := ""
	for node: Label in site_remaining:
		if "59m" in node.text:
			original_copy = node.text
	Game.advance_time(5.0, false)
	await _settle()
	var stale_copy := false
	for node: Label in main.get_node("ConstructionContext").find_children("*", "Label", true, false):
		stale_copy = stale_copy or (not original_copy.is_empty() and node.text == original_copy)
	_check(not stale_copy, "construction detail countdown refreshes while the sheet remains open")
	main.get_node("ConstructionContext").queue_free()
	await get_tree().process_frame
	main.call("_open_datacenter", dc_id)
	await _settle()
	var board := main.find_child("DatacenterBoard", true, false) as DatacenterBoard
	_check(board != null, "building tap opens its real board")
	_check(board.find_child("PowerInstallTimer", true, false) != null, "transformer progress stays at the transformer control")
	for edge: String in ["north", "east"]:
		var cooler := board.find_child("Cooler_%s" % edge, true, false) as Control
		var ring := cooler.find_child("CoolerInstallTimer", true, false) as ProgressBar
		_check(ring != null and cooler.get_global_rect().encloses(ring.get_global_rect()), "%s cooling progress stays on that exact edge" % edge)
	var ring0 := board.find_child("RackSlot0", true, false).find_child("RackInstallTimer", true, false) as ProgressBar
	var ring1 := board.find_child("RackSlot1", true, false).find_child("RackInstallTimer", true, false) as ProgressBar
	_check(ring0 != null and ring1 != null and ring0.value > 0.0 and ring1.value > 0.0, "each installing rack has independent live progress")
	var ring_identity := ring0.get_instance_id()
	Game.advance_time(15.0, false)
	await _settle()
	ring0 = board.find_child("RackSlot0", true, false).find_child("RackInstallTimer", true, false) as ProgressBar
	_check(ring0.get_instance_id() == ring_identity and ring0.value >= 75.0, "countdown updates without rebuilding the board or losing the touched slot")
	await _shot("board")
	Game.advance_time(330.0, false)
	await _settle()
	_check(board.find_children("RackInstallTimer", "", true, false).is_empty() and board.find_child("PowerInstallTimer", true, false) == null, "completed rack and transformer rings disappear")
	_check(board.find_child("Cooler_east", true, false).find_child("CoolerInstallTimer", true, false) != null, "a slower liquid install keeps its own remaining progress")
	await _shot("liquid")
	# A shortened finish time must not reset progress to a new, shorter duration.
	var job: Dictionary = site_result["construction"]
	job["complete_at"] -= 1800.0
	var ring := main.park_map.find_child("ConstructionProgress", true, false) as ProgressBar
	if ring != null:
		ring.call("refresh_progress")
	_check(ring != null and is_equal_approx(ring.max_value, 3600.0) and ring.value > 1800.0, "accelerated work is included in the same original-duration ring")
	main.get_node("DatacenterContext").queue_free()
	await get_tree().process_frame
	main.call("_show_site_construction", str(job.get("id", "")))
	await _settle()
	Game.advance_time(4000.0, false)
	await _settle()
	_check(main.find_child("ConstructionContext", true, false) == null, "a finished site closes its progress sheet automatically")
	# Tutorial still supplies the novice-only waiting explanation.
	main.queue_free()
	await get_tree().process_frame
	Game.reset_for_tests()
	Game.set_process(false)
	Game.start_datacenter_construction("plot_1", "dc_t0")
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _settle()
	_check(main.tutorial_overlay.visible and str(main.tutorial_overlay.get_meta("tutorial_mode", "")) == "waiting", "new players retain the construction waiting coach")
	await _shot("tutorial")
	print("CONSTRUCTION_RINGS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _settle() -> void:
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/dct_rings_%s_%s.png" % [TranslationServer.get_locale(), label])

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("CONSTRUCTION_RINGS: " + message)
