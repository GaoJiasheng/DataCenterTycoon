extends Node

const MAIN_SCENE := preload("res://main.tscn")
const OUTPUT_ROOT := "/tmp/data_center_tycoon_visual_"

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(402, 874))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var valid := true
	valid = (await _capture(main, "map")) and valid
	main.call("_show_plot_purchase")
	valid = (await _capture(main, "action_sheet")) and valid
	var action_sheet := main.find_child("ActionSheetOverlay", true, false)
	if action_sheet != null:
		action_sheet.queue_free()
		await get_tree().process_frame
	main.call("_show_building_picker", "plot_1")
	await get_tree().create_timer(0.35).timeout
	valid = (await _capture(main, "build_drawer")) and valid
	var building_picker := main.find_child("BuildingPicker", true, false)
	if building_picker != null:
		building_picker.queue_free()
		await get_tree().process_frame
	main.park_map.reset_camera()
	Game.start_datacenter_construction("plot_1", "dc_t0")
	main.call("_navigate", "build")
	valid = (await _capture(main, "construction_queue")) and valid
	Game.advance_time(300.0, false)
	main.call("_navigate", "map")
	valid = (await _capture(main, "map_built")) and valid
	await get_tree().create_timer(0.9).timeout
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var mixed_powered := dc.duplicate(true)
	mixed_powered["id"] = "visual_mixed_powered"
	mixed_powered["power_unit"] = "power_t1"
	var mixed_plots: Array[Dictionary] = [
		{"id": "visual_mixed_0", "index": 1, "status": "operational", "datacenter": dc.duplicate(true)},
		{"id": "visual_mixed_1", "index": 2, "status": "empty"},
		{"id": "visual_mixed_2", "index": 3, "status": "empty"},
		{"id": "visual_mixed_3", "index": 4, "status": "operational", "datacenter": mixed_powered},
	]
	main.park_map.setup(mixed_plots)
	valid = (await _capture(main, "campus_mixed")) and valid
	var dense_plots: Array[Dictionary] = []
	for index: int in range(6):
		var dense_dc := dc.duplicate(true)
		dense_dc["id"] = "visual_dc_%d" % index
		dense_dc["building_id"] = "dc_t%d" % mini(index, 3)
		dense_dc["power_unit"] = "power_t1"
		dense_plots.append({"id": "visual_plot_%d" % index, "index": index + 1, "status": "operational", "datacenter": dense_dc})
	main.park_map.setup(dense_plots)
	valid = (await _capture(main, "campus_dense")) and valid
	var alert_fault := dc.duplicate(true)
	alert_fault["id"] = "visual_alert_fault"
	alert_fault["power_unit"] = "power_t1"
	alert_fault["racks"][0] = {"rack_id": "rack_compute_t1", "status": "faulted", "enabled": true}
	var alert_unpowered := dc.duplicate(true)
	alert_unpowered["id"] = "visual_alert_unpowered"
	alert_unpowered["power_unit"] = ""
	var alert_contract := dc.duplicate(true)
	alert_contract["id"] = "visual_alert_contract"
	alert_contract["power_unit"] = "power_t1"
	alert_contract["customer_id"] = "internet"
	alert_contract["contract_end_at"] = Game.simulation_time()
	main.park_map.setup([
		{"id": "visual_alert_plot_0", "index": 1, "status": "operational", "datacenter": alert_fault},
		{"id": "visual_alert_plot_1", "index": 2, "status": "operational", "datacenter": alert_unpowered},
		{"id": "visual_alert_plot_2", "index": 3, "status": "operational", "datacenter": alert_contract},
	])
	valid = (await _capture(main, "world_alerts")) and valid
	main.park_map.setup(Game.state.get("plots", []))
	main.call("_open_datacenter", str(dc.get("id", "")))
	valid = (await _capture(main, "dc_context")) and valid
	var dc_context := main.find_child("DatacenterContext", true, false)
	if dc_context != null:
		dc_context.queue_free()
		await get_tree().process_frame
	dc["power_unit"] = "power_t1"
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": false, "fault_at": -1.0}
	dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "installing", "enabled": true, "started_at": Game.simulation_time(), "install_complete_at": Game.simulation_time() + 90.0, "ad_uses": 0}
	dc["coolers"]["north"] = "cool_air_t1"
	dc["customer_id"] = "internet"
	dc["contract_end_at"] = Game.simulation_time()
	dc["renewal_window_end_at"] = Game.simulation_time() + 7200.0
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	valid = (await _capture(main, "dc_board")) and valid
	dc["power_unit"] = "power_t2"
	dc["racks"][4] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true, "fault_at": -1.0}
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	valid = (await _capture(main, "dc_board_overheat")) and valid
	var board := main.find_child("DatacenterBoard", true, false)
	if board != null:
		board.call("set_placement_preview", 3, "rack_gpu_t1")
	valid = (await _capture(main, "dc_board_placing", false)) and valid
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "contracts")
	valid = (await _capture(main, "dc_contracts")) and valid
	main.call("_show_rack_actions", str(dc.get("id", "")), 1)
	valid = (await _capture(main, "rack_install_actions")) and valid
	var rack_install_sheet := main.find_child("ActionSheetOverlay", true, false)
	if rack_install_sheet != null:
		rack_install_sheet.queue_free()
		await get_tree().process_frame
	main.call("_show_rack_actions", str(dc.get("id", "")), 0)
	valid = (await _capture(main, "rack_pause_actions")) and valid
	var rack_pause_sheet := main.find_child("ActionSheetOverlay", true, false)
	if rack_pause_sheet != null:
		rack_pause_sheet.queue_free()
		await get_tree().process_frame
	main.call("_show_rack_picker", str(dc.get("id", "")), 3)
	valid = (await _capture(main, "rack_picker")) and valid
	var rack_picker_sheet := main.find_child("ActionSheetOverlay", true, false)
	if rack_picker_sheet != null:
		rack_picker_sheet.queue_free()
		await get_tree().process_frame
	main.call("_navigate", "map")
	await get_tree().process_frame
	main.call("_show_operations_hub")
	valid = (await _capture(main, "operations")) and valid
	var operations := main.find_child("OperationsHub", true, false)
	if operations != null:
		operations.queue_free()
		await get_tree().process_frame
	for page: String in ["market", "tech", "store", "settings"]:
		main.call("_navigate", page)
		valid = (await _capture(main, page)) and valid
		if page == "store":
			valid = (await _scroll_survives_tick(main)) and valid
		if page == "tech":
			main.call("_set_tech_section", "achievements")
			valid = (await _capture(main, "achievements")) and valid
	main.call("_show_era_overlay", 2, DataRepository.get_entry("eras", "2"))
	valid = (await _capture(main, "era_unlock")) and valid
	var era_overlay := main.find_child("EraOverlay", true, false)
	if era_overlay != null:
		era_overlay.queue_free()
		await get_tree().process_frame
	main.call("_on_bankruptcy_state_changed", "game_over")
	valid = (await _capture(main, "game_over")) and valid
	var game_over_sheet := main.find_child("ActionSheetOverlay", true, false)
	if game_over_sheet != null:
		game_over_sheet.queue_free()
		await get_tree().process_frame
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("VISUAL_SMOKE: %s 24 iPhone 17 portrait states -> %s*.png" % ["PASS" if valid else "FAIL", OUTPUT_ROOT])
	get_tree().quit(0 if valid else 1)

func _capture(main: Node, name: String, refresh: bool = true) -> bool:
	print("VISUAL_SMOKE: rendering %s" % name)
	if refresh:
		main.call("_refresh")
	for _frame: int in range(3):
		await get_tree().process_frame
	await get_tree().create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var valid := not image.is_empty() and image.get_width() >= 402 and image.get_height() >= 874 and _layout_is_safe(main, name)
	var output_path := "%s%s.png" % [OUTPUT_ROOT, name]
	var save_error := image.save_png(output_path) if valid else ERR_CANT_CREATE
	if not valid or save_error != OK:
		push_error("VISUAL_SMOKE: %s failed size=%dx%d save_error=%d" % [name, image.get_width(), image.get_height(), save_error])
	else:
		print("VISUAL_SMOKE: captured %s" % name)
	return valid and save_error == OK

func _scroll_survives_tick(main: Node) -> bool:
	var scroll := main.find_child("PageScroll", true, false) as ScrollContainer
	if scroll == null:
		push_error("VISUAL_SMOKE: store has no named PageScroll")
		return false
	var scroll_content := scroll.get_child(0) as Control
	if scroll_content != null:
		scroll_content.custom_minimum_size.y = maxf(scroll_content.get_combined_minimum_size().y, scroll.size.y + 640.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.30).timeout
	var scrollbar := scroll.get_v_scroll_bar()
	var target := mini(240, maxi(0, int(scrollbar.max_value - scrollbar.page)))
	scroll.scroll_vertical = target
	await get_tree().process_frame
	var before_id := scroll.get_instance_id()
	var before_scroll := scroll.scroll_vertical
	var before_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	Game.advance_time(2.0, false)
	await get_tree().create_timer(0.40).timeout
	var after_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
	var after_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var valid := target > 0 and after_scroll != null and after_scroll.get_instance_id() == before_id and after_scroll.scroll_vertical == before_scroll and absi(after_nodes - before_nodes) <= 2
	if not valid:
		push_error("VISUAL_SMOKE: tick rebuilt store or moved scroll before=%d/%d after=%s nodes=%d→%d" % [before_id, before_scroll, str(after_scroll), before_nodes, after_nodes])
	else:
		print("VISUAL_SMOKE: store tick preserved node=%d scroll=%d nodes_delta=%d" % [before_id, before_scroll, after_nodes - before_nodes])
	return valid

func _layout_is_safe(main: Node, state_name: String) -> bool:
	var viewport_rect := get_viewport().get_visible_rect()
	var controls: Array[Control] = []
	for node_name: String in ["ShellHeader", "WorldActions", "CompanyButton", "GemResource", "SettingsButton", "TaskButton", "PrimaryWorldAction", "OperationsButton"]:
		var node := main.find_child(node_name, true, false) as Control
		if node != null and node.is_visible_in_tree():
			controls.append(node)
	var valid := true
	var font_probe := Label.new()
	font_probe.name = "GlyphProbe"
	font_probe.text = "稳障购罄"
	font_probe.visible = false
	main.add_child(font_probe)
	var probe_font := font_probe.get_theme_font("font")
	for character: String in ["稳", "障", "购", "罄"]:
		if not probe_font.has_char(character.unicode_at(0)):
			push_error("VISUAL_SMOKE: packaged font lacks glyph %s" % character)
			valid = false
	font_probe.queue_free()
	for control: Control in controls:
		var rect := control.get_global_rect()
		var inside := rect.position.x >= viewport_rect.position.x - 1.0 and rect.position.y >= viewport_rect.position.y - 1.0 and rect.end.x <= viewport_rect.end.x + 1.0 and rect.end.y <= viewport_rect.end.y + 1.0
		var touch_safe := control.name in ["ShellHeader", "WorldActions"] or rect.size.y >= 88.0
		if not inside or not touch_safe:
			push_error("VISUAL_SMOKE: %s unsafe %s rect=%s viewport=%s" % [state_name, control.name, rect, viewport_rect])
			valid = false
	if state_name == "map":
		var persistent_names := ["CompanyButton", "CashResource", "GemResource", "SettingsButton", "TaskButton", "PrimaryWorldAction", "OperationsButton"]
		var persistent_count := 0
		for node_name: String in persistent_names:
			var persistent := main.find_child(node_name, true, false) as Control
			if persistent != null and persistent.is_visible_in_tree():
				persistent_count += 1
		if persistent_count > 7 or main.find_child("BottomNav", true, false) != null:
			push_error("VISUAL_SMOKE: map has %d persistent controls or a legacy tab bar" % persistent_count)
			valid = false
	if state_name in ["dc_contracts", "market"]:
		for node: Node in main.find_children("*", "Button", true, false):
			var contract_button := node as Button
			if contract_button != null and contract_button.is_visible_in_tree() and contract_button.text.contains("0.00"):
				push_error("VISUAL_SMOKE: locked contract exposes a zero multiplier: %s" % contract_button.text)
				valid = false
		for node: Node in main.find_children("*", "Label", true, false):
			var market_label := node as Label
			if market_label != null and market_label.is_visible_in_tree() and market_label.text.contains("0.00"):
				push_error("VISUAL_SMOKE: locked customer exposes a zero multiplier: %s" % market_label.text)
				valid = false
	if state_name == "action_sheet":
		var drag_handle := main.find_child("SheetDragHandle", true, false) as Control
		if drag_handle == null or drag_handle.size.y < 88.0:
			push_error("VISUAL_SMOKE: action sheet drag target is below 44pt")
			valid = false
	if state_name == "world_alerts":
		var alert_count := 0
		for node: Node in main.find_children("StatusBadge", "PanelContainer", true, false):
			var badge := node as PanelContainer
			if badge != null and badge.has_meta("alert_type"):
				alert_count += 1
				if not viewport_rect.intersects(badge.get_global_rect()):
					push_error("VISUAL_SMOKE: world alert is outside the viewport: %s" % badge.get_meta("alert_type"))
					valid = false
		if alert_count != 3:
			push_error("VISUAL_SMOKE: expected three actionable world alerts, got %d" % alert_count)
			valid = false
	if state_name in ["dc_board", "dc_board_overheat", "dc_board_placing"]:
		var board := main.find_child("DatacenterBoard", true, false)
		var power_meter := main.find_child("BoardPowerMeter", true, false)
		if board == null or power_meter == null:
			push_error("VISUAL_SMOKE: %s lacks the board or power meter" % state_name)
			valid = false
		var coverage_count := main.find_children("CoolingCoverage_*", "", true, false).size()
		if coverage_count != 3:
			push_error("VISUAL_SMOKE: %s expected three north-cooler coverage tiles, got %d" % [state_name, coverage_count])
			valid = false
		if state_name == "dc_board_placing" and main.find_children("PlacementState", "", true, false).size() != 9:
			push_error("VISUAL_SMOKE: placement preview does not classify all nine slots")
			valid = false
	valid = _typography_and_touch_are_safe(main, state_name) and valid
	return valid

func _typography_and_touch_are_safe(main: Node, state_name: String) -> bool:
	var valid := true
	for node: Node in main.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.is_visible_in_tree() or label.text.is_empty():
			continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var line_height := font.get_height(font_size)
		if label.size.y + 1.0 < line_height:
			push_error("VISUAL_SMOKE: %s label line clipped %s size=%s line=%.1f" % [state_name, label.name, label.size, line_height])
			valid = false
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and label.get_combined_minimum_size().x > label.size.x + 1.0:
			push_error("VISUAL_SMOKE: %s label width overflow %s text=%s size=%s min=%s" % [state_name, label.name, label.text, label.size, label.get_combined_minimum_size()])
			valid = false
	for node: Node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree() or button.disabled:
			continue
		var minimum_touch := 64.0 if button.toggle_mode else 88.0
		if button.size.x + 1.0 < minimum_touch or button.size.y + 1.0 < minimum_touch:
			push_error("VISUAL_SMOKE: %s undersized touch target %s size=%s" % [state_name, button.name, button.size])
			valid = false
	return valid
