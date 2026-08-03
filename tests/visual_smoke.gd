extends Node

const MAIN_SCENE := preload("res://main.tscn")
const OUTPUT_ROOT_PREFIX := "/tmp/data_center_tycoon_visual_"
const PREVIEW_SIZE := Vector2i(990, 2151)

var output_root := OUTPUT_ROOT_PREFIX
var capture_locale := "zh_CN"

func _ready() -> void:
	capture_locale = _requested_locale()
	TranslationServer.set_locale(capture_locale)
	output_root = "%s%s_" % [OUTPUT_ROOT_PREFIX, capture_locale]
	# Regression captures use 75% of the iPhone 17 Pro Max physical 1320x2868
	# resolution (150% of the 660x1434 desktop preview). The design canvas stays unchanged.
	# Borderless mode prevents macOS from shrinking the tall capture to reserve title-bar space.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(PREVIEW_SIZE)
	Game.reset_for_tests()
	Game.last_offline_report = {}
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var preview_hour := _requested_preview_hour()
	if preview_hour >= 0.0:
		main.park_map.call("set_preview_hour", preview_hour)
	var valid := true
	valid = (await _capture(main, "map")) and valid
	valid = (await _capture(main, "ftue_spotlight")) and valid
	Game.state["tutorial"]["completed"] = true
	main.call("_refresh_hud")
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
	# Capture the settled building rather than the intentional completion squash.
	await get_tree().create_timer(0.65).timeout
	valid = (await _capture(main, "map_built")) and valid
	await get_tree().create_timer(0.9).timeout
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var completion_nodes_clean: bool = main.park_map.find_child("ConstructionGhost", true, false) == null and main.park_map.find_children("CompletionDust*", "TextureRect", true, false).is_empty()
	var fx_layer: Node = main.find_child("FxLayer", true, false)
	completion_nodes_clean = completion_nodes_clean and fx_layer != null and int(fx_layer.call("active_coin_count")) == 0
	if not completion_nodes_clean:
		push_error("VISUAL_SMOKE: construction or coin FX did not self-clean")
		valid = false
	var power_result: Dictionary = Game.install_power(str(dc.get("id", "")), "power_t1")
	if not bool(power_result.get("ok", false)):
		push_error("VISUAL_SMOKE: unable to stage the power-on transition")
		valid = false
	else:
		Game.advance_time(300.0, false)
		await get_tree().create_timer(0.40).timeout
		var power_transition_live: bool = main.park_map.find_child("PowerOnDarkGhost", true, false) != null and main.park_map.find_child("PowerOnGlow", true, false) != null
		if not power_transition_live:
			push_error("VISUAL_SMOKE: dark-to-active power-on transition did not start")
			valid = false
		await get_tree().create_timer(0.72).timeout
		var power_transition_clean: bool = main.park_map.find_child("PowerOnDarkGhost", true, false) == null and main.park_map.find_child("PowerOnGlow", true, false) == null and int(fx_layer.call("active_coin_count")) == 0
		if not power_transition_clean:
			push_error("VISUAL_SMOKE: power-on transition or coin FX did not self-clean")
			valid = false
	# Restore the canonical unpowered fixture expected by the later context and
	# board states; the transition probe above is intentionally presentation-only.
	dc["power_unit"] = ""
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
	main.call("_sign_contract", str(dc.get("id", "")), "mining")
	valid = (await _capture(main, "contract_comparison")) and valid
	var contract_sheet := main.find_child("ActionSheetOverlay", true, false)
	if contract_sheet != null:
		contract_sheet.queue_free()
		await get_tree().process_frame
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
	main.call("_navigate", "market")
	Game.state["market"]["history"] = {}
	Game.state["market"]["active"] = []
	Game.state["market"]["previews"] = []
	valid = (await _capture(main, "market_empty")) and valid
	_fill_market_history(2)
	var now := Game.simulation_time()
	Game.state["market"]["active"] = [{"event_id": "shopping_festival", "started_at": now - 1800.0, "end_at": now + 5400.0}]
	Game.state["market"]["previews"] = [{"event_id": "coin_boom", "previewed_at": now, "start_at": now + 3600.0}]
	valid = (await _capture(main, "market_active")) and valid
	_fill_market_history(730)
	valid = (await _capture(main, "market_rich")) and valid
	for page: String in ["tech", "store", "settings"]:
		main.call("_navigate", page)
		valid = (await _capture(main, page)) and valid
		if page == "store":
			valid = (await _scroll_survives_tick(main)) and valid
		if page == "tech":
			main.call("_set_tech_section", "achievements")
			valid = (await _capture(main, "achievements")) and valid
	main.call("_show_offline_dialog", {"elapsed_seconds": 14400.0, "income": 12840.0, "completed": [{"id": "job"}], "faults": [{"id": "fault"}], "events": [{"id": "event"}], "aging": [{"id": "aged"}], "contracts": []})
	valid = (await _capture(main, "offline_reward", false)) and valid
	var offline_overlay := main.find_child("OfflineOverlay", true, false)
	if offline_overlay != null:
		offline_overlay.queue_free()
		await get_tree().process_frame
	Game.state["bankruptcy"] = {"status": "arrears", "debt": 4250.0, "arrears_online_seconds": 3600.0, "rescue_uses": 0, "rescue_day": -1}
	Game.state["player"]["cash"] = 0.0
	main.call("_on_bankruptcy_state_changed", "arrears")
	await get_tree().create_timer(0.40).timeout
	valid = (await _capture(main, "arrears", false)) and valid
	Game.state["bankruptcy"] = {"status": "normal", "debt": 0.0, "arrears_online_seconds": 0.0, "rescue_uses": 0, "rescue_day": -1}
	main.call("_on_bankruptcy_state_changed", "normal")
	await get_tree().process_frame
	main.call("_show_era_overlay", 2, DataRepository.get_entry("eras", "2"))
	valid = (await _capture(main, "era_unlock")) and valid
	var era_overlay := main.find_child("EraOverlay", true, false)
	if era_overlay != null:
		era_overlay.queue_free()
		await get_tree().process_frame
	main.call("_on_bankruptcy_state_changed", "game_over")
	await get_tree().create_timer(1.25).timeout
	valid = (await _capture(main, "game_over", false)) and valid
	var game_over_sheet := main.find_child("ActionSheetOverlay", true, false)
	if game_over_sheet != null:
		game_over_sheet.queue_free()
		await get_tree().process_frame
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("VISUAL_SMOKE: %s 30 iPhone 17 portrait states at %dx%d locale=%s -> %s*.png" % ["PASS" if valid else "FAIL", PREVIEW_SIZE.x, PREVIEW_SIZE.y, capture_locale, output_root])
	get_tree().quit(0 if valid else 1)

func _requested_locale() -> String:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			var requested := argument.trim_prefix("--locale=")
			if requested in ["en", "zh_CN"]:
				return requested
	return "zh_CN"

func _requested_preview_hour() -> float:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-hour="):
			return clampf(float(argument.trim_prefix("--preview-hour=")), 0.0, 23.99)
	return -1.0

func _fill_market_history(point_count: int) -> void:
	var history: Dictionary = {}
	var now := Game.simulation_time()
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var values: Array = []
		for index: int in range(point_count):
			var wave := sin(float(index) * 0.17 + float(customer_id.length())) * 0.12
			values.append({"at": now - float(point_count - 1 - index) * 240.0, "value": 1.0 + wave + float(index % 9) * 0.006})
		history[customer_id] = values
	Game.state["market"]["history"] = history

func _capture(main: Node, name: String, refresh: bool = true) -> bool:
	print("VISUAL_SMOKE: rendering %s" % name)
	if refresh:
		main.call("_refresh")
	for _frame: int in range(3):
		await get_tree().process_frame
	if name == "era_unlock":
		await get_tree().create_timer(1.25).timeout
	await get_tree().create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# macOS may report the drawable one physical pixel narrower than the requested
	# client area. Keep a 2px platform tolerance, but always execute layout gates.
	var image_valid := not image.is_empty() and image.get_width() >= PREVIEW_SIZE.x - 2 and image.get_height() >= PREVIEW_SIZE.y - 2
	var layout_valid := _layout_is_safe(main, name)
	var valid := image_valid and layout_valid
	var output_path := "%s%s.png" % [output_root, name]
	# `aspect=keep` can make the macOS Metal drawable one pixel narrower because
	# 804:1748 and 1320:2868 differ by 0.06%. Normalize only that platform pixel
	# so every delivered review image has the promised exact 990x2151 contract.
	if image_valid and image.get_size() != PREVIEW_SIZE:
		image.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var save_error := image.save_png(output_path) if not image.is_empty() else ERR_CANT_CREATE
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
		var noon_grade: Dictionary = main.park_map.call("color_grade_for_hour", 12.0)
		var evening_grade: Dictionary = main.park_map.call("color_grade_for_hour", 19.0)
		var night_grade: Dictionary = main.park_map.call("color_grade_for_hour", 23.0)
		var noon_tint: Color = noon_grade.get("tint", Color.TRANSPARENT)
		var evening_tint: Color = evening_grade.get("tint", Color.TRANSPARENT)
		var night_tint: Color = night_grade.get("tint", Color.TRANSPARENT)
		if not noon_tint.is_equal_approx(ParkMap.DAY_TINT) or not evening_tint.is_equal_approx(ParkMap.EVENING_TINT) or not night_tint.is_equal_approx(ParkMap.NIGHT_TINT) or not is_equal_approx(float(night_grade.get("window_boost", 1.0)), 1.30):
			push_error("VISUAL_SMOKE: map does not expose the day/evening/night grading contract")
			valid = false
		if not ThemeFactory.SURFACE.is_equal_approx(Color("122438")) or not ThemeFactory.SURFACE_GROUP.is_equal_approx(Color(0, 0, 0, 0.22)) or not ThemeFactory.COLORS.cyan.is_equal_approx(Color("9fb8cc")):
			push_error("VISUAL_SMOKE: final-look surface or secondary-text palette drifted")
			valid = false
		var task_caption := main.find_child("TaskCaption", true, false) as Label
		var operations_caption := main.find_child("OperationsCaption", true, false) as Label
		var task_button := main.find_child("TaskButton", true, false) as Button
		var operations_button := main.find_child("OperationsButton", true, false) as Button
		if task_caption == null or operations_caption == null or task_button == null or operations_button == null or task_caption.get_parent() == task_button or operations_caption.get_parent() == operations_button or not task_button.text.is_empty() or not operations_button.text.is_empty():
			push_error("VISUAL_SMOKE: map circular entries do not keep their labels outside the icon buttons")
			valid = false
		for caption: Label in [task_caption, operations_caption]:
			if caption != null:
				var caption_rect := caption.get_global_rect()
				var button_rect := task_button.get_global_rect() if caption == task_caption else operations_button.get_global_rect()
				if not viewport_rect.grow(-4.0).encloses(caption_rect) or caption_rect.end.y > button_rect.position.y + 1.0:
					push_error("VISUAL_SMOKE: map action caption is outside the safe strip or below its button %s caption=%s button=%s" % [caption.name, caption_rect, button_rect])
					valid = false
	if state_name == "campus_dense":
		# F1 is deliberately separate from the generic button-color sweep: its old
		# 720-weight CJK fallback technically reported white, while the 4px outline
		# visually swallowed the glyph interiors. Lock the exact world CTA contract.
		var primary_world_action := main.find_child("PrimaryWorldAction", true, false) as Button
		var primary_world_text := main.find_child("PrimaryWorldActionText", true, false) as Label
		var primary_world_fill := main.find_child("PrimaryWorldActionTextFill", true, false) as Label
		var primary_states := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]
		var primary_is_white := primary_world_action != null and primary_world_text != null and primary_world_fill != null
		if primary_world_action != null:
			for color_name: String in primary_states:
				primary_is_white = primary_is_white and primary_world_action.get_theme_color(color_name).is_equal_approx(Color.WHITE)
			primary_is_white = primary_is_white and primary_world_action.get_theme_font("font") == ThemeFactory.font_world_heavy()
			primary_is_white = primary_is_white and primary_world_action.get_theme_constant("outline_size") == 4
			primary_is_white = primary_is_white and primary_world_action.get_theme_color("font_outline_color").is_equal_approx(ThemeFactory.COLORS.ink)
		if primary_world_text != null and primary_world_fill != null:
			primary_is_white = primary_is_white and primary_world_text.text == str(primary_world_action.get_meta("primary_action_text", ""))
			primary_is_white = primary_is_white and primary_world_text.get_theme_color("font_color").is_equal_approx(Color.WHITE) and primary_world_text.get_theme_constant("outline_size") == 4
			primary_is_white = primary_is_white and primary_world_fill.text == primary_world_text.text and primary_world_fill.get_theme_color("font_color").is_equal_approx(Color.WHITE) and primary_world_fill.get_theme_color("font_outline_color").is_equal_approx(Color.WHITE) and primary_world_fill.get_theme_constant("outline_size") == 1
		if not primary_is_white:
			push_error("VISUAL_SMOKE: F1 PrimaryWorldAction is not pure-white heavy CJK with a 4px ink outline")
			valid = false
		for caption_name: String in ["TaskCaption", "OperationsCaption"]:
			var world_caption := main.find_child(caption_name, true, false) as Label
			var world_caption_fill := main.find_child("%sFill" % caption_name, true, false) as Label
			if world_caption == null or world_caption_fill == null or world_caption_fill.get_parent() != world_caption or not world_caption.get_theme_color("font_color").is_equal_approx(Color.WHITE) or world_caption.get_theme_font_size("font_size") != 20 or world_caption.get_theme_constant("outline_size") != 3 or not world_caption.get_theme_color("font_outline_color").is_equal_approx(ThemeFactory.COLORS.ink) or world_caption.get_theme_font("font") != ThemeFactory.font_world_heavy() or not world_caption_fill.get_theme_color("font_color").is_equal_approx(Color.WHITE) or not world_caption_fill.get_theme_color("font_outline_color").is_equal_approx(Color.WHITE) or world_caption_fill.get_theme_constant("outline_size") != 1:
				push_error("VISUAL_SMOKE: F10 world action caption violates the 20u white/heavy/3px contract: %s" % caption_name)
				valid = false
	if state_name == "store":
		var best_value := main.find_child("BestValueRibbon", true, false) as PanelContainer
		var best_value_label := main.find_child("BestValueLabel", true, false) as Label
		if best_value == null or best_value_label == null or best_value.size.x + 1.0 < best_value_label.get_combined_minimum_size().x + 24.0 or best_value.size.y + 1.0 < best_value_label.get_combined_minimum_size().y + 12.0:
			push_error("VISUAL_SMOKE: store best-value ribbon does not fit its localized label")
			valid = false
	if state_name == "ftue_spotlight":
		var spotlight := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
		var primary := main.find_child("PrimaryWorldAction", true, false) as Control
		var pointer := main.find_child("TutorialPointer", true, false) as Control
		var callout := main.find_child("TutorialCallout", true, false) as Control
		var tutorial_message := main.find_child("TutorialMessage", true, false) as Label
		var hole_border := main.find_child("TutorialHoleBorder", true, false) as PanelContainer
		var hole: Rect2 = spotlight.get("target_rect") if spotlight != null else Rect2()
		if spotlight == null or not spotlight.visible or not bool(spotlight.call("is_actionable")) or primary == null or pointer == null or not pointer.visible or not hole.intersects(primary.get_global_rect()):
			push_error("VISUAL_SMOKE: FTUE spotlight does not resolve the primary action hole and pointer")
			valid = false
		if pointer != null and AssetCatalog.texture("ic_pointer_hand") == null:
			var pointer_parts := pointer.find_children("Pointer*", "Polygon2D", true, false)
			if pointer_parts.size() != 4 or pointer_parts.any(func(part: Node) -> bool: return not bool((part as Polygon2D).antialiased)):
				push_error("VISUAL_SMOKE: FTUE pointer fallback lacks its antialiased capsule/triangle outline")
				valid = false
		var mask := main.find_child("TutorialMask0", true, false) as ColorRect
		if mask == null or mask.color.a < 0.62:
			push_error("VISUAL_SMOKE: FTUE dim layer is below 0.62")
			valid = false
		if pointer != null and pointer.get_global_rect().end.y > hole.position.y - 12.0:
			push_error("VISUAL_SMOKE: FTUE pointer overlaps the spotlight target")
			valid = false
		if callout == null or tutorial_message == null or not callout.get_global_rect().grow(1.0).encloses(tutorial_message.get_global_rect()):
			push_error("VISUAL_SMOKE: FTUE message is outside its adaptive callout")
			valid = false
		var hole_style: StyleBoxFlat = null
		if hole_border != null:
			hole_style = hole_border.get_theme_stylebox("panel") as StyleBoxFlat
		if hole_style == null or hole_style.get_border_width(SIDE_TOP) < 6:
			push_error("VISUAL_SMOKE: FTUE spotlight border is below 6u")
			valid = false
	if state_name in ["dc_contracts", "contract_comparison", "market_empty", "market_active", "market_rich"]:
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
				var badge_style := badge.get_theme_stylebox("panel") as StyleBoxFlat
				if not bool(badge.get_meta("breathing", false)) or badge_style == null or not badge_style.border_color.is_equal_approx(Color.WHITE) or badge_style.get_border_width(SIDE_TOP) < 2:
					push_error("VISUAL_SMOKE: world alert lacks its white rim or breathing affordance")
					valid = false
				if not viewport_rect.intersects(badge.get_global_rect()):
					push_error("VISUAL_SMOKE: world alert is outside the viewport: %s" % badge.get_meta("alert_type"))
					valid = false
		if alert_count != 3:
			push_error("VISUAL_SMOKE: expected three actionable world alerts, got %d" % alert_count)
			valid = false
	if state_name in ["map_built", "campus_dense", "world_alerts"]:
		var building_count := main.find_children("WorldArt", "TextureRect", true, false).size()
		var foundation_count := main.find_children("PlotFoundation", "TextureRect", true, false).size()
		var expected_min := 6 if state_name == "campus_dense" else (3 if state_name == "world_alerts" else 1)
		if building_count < expected_min or foundation_count < expected_min:
			push_error("VISUAL_SMOKE: %s lacks unified plot foundations or building art %d/%d" % [state_name, foundation_count, building_count])
			valid = false
		if not main.find_children("BuildingGroundShadow", "Polygon2D", true, false).is_empty():
			push_error("VISUAL_SMOKE: %s retains a duplicate procedural shadow over A2 baked shadows" % state_name)
			valid = false
	if state_name == "campus_dense":
		var path_segments := main.find_children("CampusLane_*", "TextureRect", true, false)
		var lane_axes: Dictionary = {}
		for lane_node: Node in path_segments:
			var lane := lane_node as TextureRect
			lane_axes[str(lane.get_meta("lane_axis", ""))] = true
			if not bool(lane.get_meta("world_lane", false)) or not is_equal_approx(absf(tan(lane.rotation)), 0.5):
				push_error("VISUAL_SMOKE: dense campus lane left the shared 2:1 axis: %s rotation=%f" % [lane.name, lane.rotation])
				valid = false
		var prop_types: Dictionary = {}
		var environment_count := 0
		var grid_slots: Dictionary = {}
		for node: Node in main.find_children("*", "", true, false):
			if node.has_meta("world_environment"):
				environment_count += 1
			var prop_type := str(node.get_meta("world_prop_type", ""))
			if not prop_type.is_empty():
				prop_types[prop_type] = true
			if node is Button and node.has_meta("grid_slot"):
				grid_slots[int(node.get_meta("grid_slot"))] = true
		if path_segments.size() != 6 or lane_axes.size() != 2:
			push_error("VISUAL_SMOKE: dense campus lacks the six-link two-axis lane graph: links=%d axes=%d" % [path_segments.size(), lane_axes.size()])
			valid = false
		if grid_slots.size() != 7:
			push_error("VISUAL_SMOKE: dense campus plots and sale pad do not share seven explicit grid slots: %d" % grid_slots.size())
			valid = false
		if prop_types.size() < 4:
			push_error("VISUAL_SMOKE: dense campus exposes fewer than four environment prop types: %d" % prop_types.size())
			valid = false
		if environment_count > 60:
			push_error("VISUAL_SMOKE: dense campus decoration budget exceeded: %d" % environment_count)
			valid = false
		var edge_fog := main.find_child("WorldEdgeFog", true, false) as TextureRect
		if edge_fog == null or edge_fog.modulate.a < 0.49 or edge_fog.modulate.a > 0.66:
			push_error("VISUAL_SMOKE: world edge fog is missing or outside its breathing range")
			valid = false
	if state_name == "dc_context":
		var contract_hint := main.find_child("ContractPowerHint", true, false) as Label
		var contract_cta := main.find_child("ContractCTA", true, false) as Button
		if contract_hint == null or contract_cta == null or bool(contract_cta.get_meta("glossy_button", false)):
			push_error("VISUAL_SMOKE: unpowered context does not explain why contracts are unavailable")
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
		var placement_badges := main.find_children("PlacementState", "PanelContainer", true, false)
		for placement_node: Node in placement_badges:
			var placement_state := str(placement_node.get_meta("placement_state", ""))
			var should_show := placement_state in ["ok", "heat", "power"]
			if placement_state not in ["ok", "heat", "power", "locked", "occupied"] or (placement_node as Control).visible != should_show:
				push_error("VISUAL_SMOKE: placement preview state is not semantically visible: %s" % placement_state)
				valid = false
		for symbol_node: Node in main.find_children("PlacementSymbol", "Label", true, false):
			if (symbol_node as Label).text not in ["✓", "⚡", "♨"]:
				push_error("VISUAL_SMOKE: placement preview uses an illegal text badge %s" % (symbol_node as Label).text)
				valid = false
		if state_name != "dc_board_placing" and not placement_badges.is_empty():
			push_error("VISUAL_SMOKE: non-placement board retains placement badges")
			valid = false
		if state_name == "dc_board":
			var install_timer := main.find_child("RackInstallTimer", true, false) as Control
			var install_progress := main.find_child("TimerProgress", true, false) as ProgressBar
			var install_remaining := main.find_child("TimerRemaining", true, false) as Label
			var timer_parent := install_timer.get_parent() as Control if install_timer != null else null
			var timer_inside := install_timer != null and timer_parent != null and timer_parent.get_global_rect().grow(-4.0).encloses(install_timer.get_global_rect())
			if not timer_inside or install_progress == null or install_progress.position.y > 6.0 or install_progress.size.y > 14.0 or install_remaining == null or install_remaining.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT or not install_remaining.get_theme_color("font_color").is_equal_approx(Color.WHITE) or install_remaining.get_theme_constant("outline_size") < 3:
				push_error("VISUAL_SMOKE: F7 installing rack timer is not a fully contained top strip with right-aligned white time")
				valid = false
		var installed_cooler := main.find_child("Cooler_north", true, false) as Button
		if installed_cooler == null or installed_cooler.icon != null or installed_cooler.find_children("CoolerArt", "TextureRect", true, false).size() != 1:
			push_error("VISUAL_SMOKE: installed cooler is not rendered by exactly one icon branch")
			valid = false
		var locked_coolers := 0
		for cooler_node: Node in main.find_children("Cooler_*", "Button", true, false):
			if str(cooler_node.get_meta("cooler_state", "")) == "locked":
				locked_coolers += 1
		if locked_coolers != 3:
			push_error("VISUAL_SMOKE: T0 board expected three locked cooler slots, got %d" % locked_coolers)
			valid = false
		if power_meter != null and (power_meter as Control).size.y < 40.0:
			push_error("VISUAL_SMOKE: board power meter is below 40u")
			valid = false
		if power_meter != null:
			var meter_parent := (power_meter as Control).get_parent() as Control
			if meter_parent == null or not meter_parent.get_global_rect().grow(1.0).encloses((power_meter as Control).get_global_rect()):
				push_error("VISUAL_SMOKE: board power meter is clipped by its content group")
				valid = false
	if state_name.begins_with("market_"):
		var chart := main.find_child("MarketChart", true, false) as MarketChart
		var legend := main.find_child("MarketLegend", true, false) as GridContainer
		if chart == null or legend == null or legend.get_child_count() != 4:
			push_error("VISUAL_SMOKE: %s lacks the chart or four-series legend" % state_name)
			valid = false
		if chart != null and not bool(chart.get_meta("one_x_baseline", false)):
			push_error("VISUAL_SMOKE: %s lacks the ×1.0 dashed baseline" % state_name)
			valid = false
		if legend != null:
			for legend_node: Node in legend.get_children():
				var legend_button := legend_node as Button
				if legend_button == null or bool(legend_button.get_meta("glossy_button", false)) or not legend_button.get_theme_color("font_color").is_equal_approx(Color.WHITE):
					push_error("VISUAL_SMOKE: %s legend is not a flat series-color button" % state_name)
					valid = false
		if state_name == "market_empty" and chart != null and not chart.series.is_empty():
			push_error("VISUAL_SMOKE: market_empty unexpectedly has history")
			valid = false
		if state_name == "market_active" and (main.find_child("MarketEventActive", true, false) == null or main.find_child("EventTimer", true, false) == null):
			push_error("VISUAL_SMOKE: active market lacks an event card and timer")
			valid = false
		if state_name == "market_active":
			var event_card := main.find_child("MarketEventActive", true, false) as Control
			var first_customer := main.find_child("MarketCustomer_internet", true, false) as Control
			if event_card == null or first_customer == null or event_card.global_position.y >= first_customer.global_position.y:
				push_error("VISUAL_SMOKE: active market event is not above customer trends")
				valid = false
		if state_name == "market_rich":
			for spark: Node in main.find_children("Sparkline_*", "Sparkline", true, false):
				if (spark as Sparkline).values.size() != 24:
					push_error("VISUAL_SMOKE: rich market sparkline is not reduced to 24 points")
					valid = false
	if state_name == "tech":
		if main.find_children("EraNode_*", "PanelContainer", true, false).size() != 3 or main.find_child("EraUnlockPreview", true, false) == null or main.find_child("PrestigeProgressBar", true, false) == null:
			push_error("VISUAL_SMOKE: tech page lacks the three-era route or prestige progress")
			valid = false
		var affordability_count := 0
		for button_node: Node in main.find_children("*", "Button", true, false):
			if button_node.has_meta("purchase_cost"):
				affordability_count += 1
		if affordability_count < 2:
			push_error("VISUAL_SMOKE: tech upgrades do not share the affordability contract")
			valid = false
		for era_node: Node in main.find_children("EraNode_*", "PanelContainer", true, false):
			if (era_node as Control).custom_minimum_size.x < 170.0:
				push_error("VISUAL_SMOKE: tech era node is too narrow for localized names")
				valid = false
	if state_name == "achievements" and main.find_children("AchievementProgress_*", "ProgressBar", true, false).size() != DataRepository.get_table("achievements").get("items", {}).size():
		push_error("VISUAL_SMOKE: achievement cards do not expose per-goal progress")
		valid = false
	if state_name == "rack_picker":
		var rack_choice_count := 0
		for choice_node: Node in main.find_children("Choice_rack_*", "Button", true, false):
			rack_choice_count += 1
			if (choice_node as Button).icon == null:
				push_error("VISUAL_SMOKE: rack picker option lacks a 64u rack thumbnail")
				valid = false
		if rack_choice_count < 2:
			push_error("VISUAL_SMOKE: rack picker did not render its purchasable choices")
			valid = false
	if state_name in ["rack_install_actions", "rack_pause_actions"]:
		var status_label := main.find_child("ActionSheetStatus", true, false) as Label
		if status_label == null or (state_name == "rack_install_actions" and not status_label.get_theme_color("font_color").is_equal_approx(ThemeFactory.COLORS.orange)):
			push_error("VISUAL_SMOKE: rack action state lacks semantic status color")
			valid = false
		if state_name == "rack_pause_actions":
			var resume := main.find_child("Choice_power", true, false) as Button
			if resume == null or not bool(resume.get_meta("glossy_button", false)):
				push_error("VISUAL_SMOKE: resume action is not the primary rack action")
				valid = false
	if state_name == "contract_comparison":
		var sheet := main.find_child("ActionSheetOverlay", true, false)
		if sheet == null:
			push_error("VISUAL_SMOKE: contract comparison sheet did not open")
			valid = false
	if state_name == "store":
		var eligible_store_buttons := 0
		for buy_node: Node in main.find_children("StoreBuy_*", "Button", true, false):
			if not (buy_node as Button).disabled:
				eligible_store_buttons += 1
				if not bool(buy_node.get_meta("glossy_button", false)):
					push_error("VISUAL_SMOKE: store price action is not consistently primary: %s" % buy_node.name)
					valid = false
		if eligible_store_buttons == 0 or main.find_child("BestValueRibbon", true, false) == null:
			push_error("VISUAL_SMOKE: store lacks eligible primary prices or its best-value ribbon")
			valid = false
		for section_id: String in ["deals", "gems", "perks"]:
			if main.find_child("StoreSection_%s" % section_id, true, false) == null:
				push_error("VISUAL_SMOKE: store lacks %s merchandising section" % section_id)
				valid = false
		if main.find_child("StoreCompliance", true, false) == null:
			push_error("VISUAL_SMOKE: store lacks purchase/legal footer")
			valid = false
	if state_name == "settings":
		if main.find_child("SettingsCompliance", true, false) == null or main.find_child("SettingsVersion", true, false) == null:
			push_error("VISUAL_SMOKE: settings lacks legal/support/version rows")
			valid = false
		if main.find_children("SettingsChevron", "Label", true, false).size() != 3:
			push_error("VISUAL_SMOKE: settings legal rows lack three chevrons")
			valid = false
	if state_name == "offline_reward":
		if main.find_child("OfflineRewardCard", true, false) == null or main.find_child("OfflineCoinPile", true, false) == null or main.find_child("OfflineDoubleButton", true, false) == null:
			push_error("VISUAL_SMOKE: offline reward lacks animated earnings art or primary ×2 placement")
			valid = false
		var credit_copy := main.find_child("OfflineCreditCopy", true, false) as Label
		if credit_copy == null or credit_copy.text.contains("12.8"):
			push_error("VISUAL_SMOKE: offline reward repeats a final amount while the headline is still rolling")
			valid = false
	if state_name == "arrears":
		var crisis_nodes := [main.find_child("ArrearsBanner", true, false), main.find_child("ArrearsVignette", true, false), main.find_child("ArrearsProgress", true, false), main.find_child("ArrearsRescueButton", true, false)]
		if crisis_nodes.any(func(node: Variant) -> bool: return node == null):
			push_error("VISUAL_SMOKE: arrears state lacks its persistent crisis HUD nodes=%s" % str(crisis_nodes))
			valid = false
		else:
			var arrears_banner := crisis_nodes[0] as PanelContainer
			var arrears_progress := crisis_nodes[2] as ProgressBar
			var arrears_button := crisis_nodes[3] as Button
			var shell_header := main.find_child("ShellHeader", true, false) as Control
			var banner_rect := arrears_banner.get_global_rect().grow(1.0)
			var content_fits := banner_rect.encloses(arrears_progress.get_global_rect()) and banner_rect.encloses(arrears_button.get_global_rect())
			var clears_hud := shell_header == null or not arrears_banner.get_global_rect().intersects(shell_header.get_global_rect())
			var crisis_style := arrears_banner.get_theme_stylebox("panel") as StyleBoxFlat
			var crisis_is_opaque := crisis_style != null and crisis_style.bg_color.a >= 0.95
			if arrears_banner.size.y + 1.0 < arrears_banner.get_combined_minimum_size().y or arrears_progress.size.y < 40.0 or arrears_button.text != tr("ARREARS_RESCUE") or not content_fits or not clears_hud or not crisis_is_opaque:
				push_error("VISUAL_SMOKE: arrears HUD is compressed or truncates its rescue action")
				valid = false
	if state_name == "era_unlock":
		var unlock_summary := main.find_child("EraUnlockSummary", true, false)
		if main.find_child("EraNewspaper", true, false) == null or unlock_summary == null or unlock_summary.get_child_count() < 3 or main.find_child("EraRewardValue", true, false) == null:
			push_error("VISUAL_SMOKE: era celebration lacks the newspaper unlock summary or reward counter")
			valid = false
		var reward_label := main.find_child("EraRewardValue", true, false) as Label
		var era_two := DataRepository.get_entry("eras", "2")
		if reward_label != null and reward_label.text != str(int(era_two.get("reward_gems", 0))):
			push_error("VISUAL_SMOKE: era reward did not settle on its final value: %s" % reward_label.text)
			valid = false
		if main.find_child("EraRewardChip", true, false) == null:
			push_error("VISUAL_SMOKE: era reward is not presented as an icon chip")
			valid = false
	if state_name == "game_over":
		var stat_count := main.find_children("GameOverStat_*", "", true, false).size()
		if main.find_child("GameOverStatsCard", true, false) == null or stat_count != 4 or main.find_child("GameOverRestart", true, false) == null:
			push_error("VISUAL_SMOKE: game over lacks the four-stat blackout presentation stats=%d card=%s restart=%s" % [stat_count, str(main.find_child("GameOverStatsCard", true, false)), str(main.find_child("GameOverRestart", true, false))])
			valid = false
		var game_over_title := main.find_child("GameOverTitle", true, false) as Label
		var game_over_restart := main.find_child("GameOverRestart", true, false) as Button
		if game_over_title == null or game_over_title.get_theme_font_size("font_size") < 44 or game_over_restart == null or game_over_restart.get_theme_font_size("font_size") != 28 or game_over_restart.get_theme_constant("outline_size") < 4:
			push_error("VISUAL_SMOKE: game over title/restart hierarchy is below the P1 contract")
			valid = false
	valid = _typography_and_touch_are_safe(main, state_name) and valid
	valid = _text_is_within_clipping_ancestors(main, state_name) and valid
	valid = _sibling_labels_do_not_overlap(main, state_name) and valid
	valid = _panel_content_is_not_compressed(main, state_name) and valid
	valid = _button_text_contrast_is_safe(main, state_name) and valid
	return valid

func _text_is_within_clipping_ancestors(main: Node, state_name: String) -> bool:
	var valid := true
	var viewport_rect := get_viewport().get_visible_rect()
	var text_controls: Array[Control] = []
	for node: Node in main.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.is_visible_in_tree() and not label.text.is_empty():
			text_controls.append(label)
	for node: Node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.is_visible_in_tree() and not button.text.is_empty():
			text_controls.append(button)
	for control: Control in text_controls:
		var rect := control.get_global_rect()
		if not viewport_rect.intersects(rect):
			continue
		var scroll_ancestor := control.get_parent()
		var page_scroll_rect := Rect2()
		while scroll_ancestor is Control:
			if scroll_ancestor is ScrollContainer and scroll_ancestor.name == "PageScroll":
				page_scroll_rect = (scroll_ancestor as Control).get_global_rect()
				break
			scroll_ancestor = scroll_ancestor.get_parent()
		var horizontally_inside_page_scroll: bool = page_scroll_rect.has_area() and rect.position.x >= page_scroll_rect.position.x - 1.0 and rect.end.x <= page_scroll_rect.end.x + 1.0
		var intentionally_scrolled_vertically: bool = horizontally_inside_page_scroll and (rect.position.y < page_scroll_rect.position.y or rect.end.y > page_scroll_rect.end.y)
		if intentionally_scrolled_vertically:
			continue
		var ancestor := control.get_parent()
		while ancestor is Control:
			var clipping_control := ancestor as Control
			if clipping_control.clip_contents:
				var clip_rect := clipping_control.get_global_rect()
				# A scroll view may legitimately keep whole rows outside its window.
				# A row whose centre is visible, however, must never lose text at an edge.
				if clip_rect.has_point(rect.get_center()) and not clip_rect.grow(1.0).encloses(rect):
					push_error("VISUAL_SMOKE: %s clipped text %s in %s rect=%s clip=%s" % [state_name, control.name, clipping_control.name, rect, clip_rect])
					valid = false
			ancestor = ancestor.get_parent()
	return valid

func _sibling_labels_do_not_overlap(main: Node, state_name: String) -> bool:
	var valid := true
	var labels_by_parent: Dictionary = {}
	var viewport_rect := get_viewport().get_visible_rect()
	for node: Node in main.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.is_visible_in_tree() or label.text.is_empty():
			continue
		var rect := label.get_global_rect()
		if not viewport_rect.intersects(rect):
			continue
		var parent_id := label.get_parent().get_instance_id()
		if not labels_by_parent.has(parent_id):
			labels_by_parent[parent_id] = []
		(labels_by_parent[parent_id] as Array).append(label)
	for siblings: Array in labels_by_parent.values():
		for left_index: int in range(siblings.size()):
			var left := siblings[left_index] as Label
			var left_rect := left.get_global_rect().grow(-2.0)
			for right_index: int in range(left_index + 1, siblings.size()):
				var right := siblings[right_index] as Label
				var right_rect := right.get_global_rect().grow(-2.0)
				if left_rect.has_area() and right_rect.has_area() and left_rect.intersects(right_rect):
					push_error("VISUAL_SMOKE: %s sibling labels overlap %s/%s rects=%s/%s" % [state_name, left.name, right.name, left_rect, right_rect])
					valid = false
	return valid

func _panel_content_is_not_compressed(main: Node, state_name: String) -> bool:
	var valid := true
	var viewport_rect := get_viewport().get_visible_rect()
	for node: Node in main.find_children("*", "PanelContainer", true, false):
		var panel := node as PanelContainer
		if panel == null or not panel.is_visible_in_tree() or not viewport_rect.intersects(panel.get_global_rect()):
			continue
		for child: Node in panel.get_children():
			var content := child as Control
			if content == null or not content.visible:
				continue
			var minimum := content.get_combined_minimum_size()
			if minimum.x > panel.size.x + 1.0 or minimum.y > panel.size.y + 1.0:
				push_error("VISUAL_SMOKE: %s compressed panel content %s/%s panel=%s minimum=%s" % [state_name, panel.name, content.name, panel.size, minimum])
				valid = false
	return valid

func _button_text_contrast_is_safe(main: Node, state_name: String) -> bool:
	var valid := true
	for node: Node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree() or button.text.is_empty():
			continue
		var font_color := button.get_theme_color("font_color")
		var is_legal_color := font_color.is_equal_approx(Color.WHITE) or font_color.is_equal_approx(ThemeFactory.COLORS.cream)
		var outline_size := button.get_theme_constant("outline_size")
		var outline_color := button.get_theme_color("font_outline_color")
		# CJK strokes at small sizes get swallowed by a 4px outline; the readable
		# combination is 3px below 26u and 4px from 26u up.
		var required_outline := 4 if button.get_theme_font_size("font_size") >= 26 else 3
		if not is_legal_color or outline_size < required_outline or not outline_color.is_equal_approx(ThemeFactory.COLORS.ink):
			push_error("VISUAL_SMOKE: %s illegal button text contrast %s color=%s outline=%d/%s" % [state_name, button.name, font_color, outline_size, outline_color])
			valid = false
		if bool(button.get_meta("glossy_button", false)) and (button.text.contains("\n") or button.text.contains("\r")):
			push_error("VISUAL_SMOKE: %s glossy button contains multiline content %s text=%s" % [state_name, button.name, button.text])
			valid = false
		if bool(button.get_meta("glossy_button", false)) and (button.get_theme_font_size("font_size") != 28 or not font_color.is_equal_approx(Color.WHITE) or outline_size < 4 or button.get_theme_constant("shadow_offset_y") < 2):
			push_error("VISUAL_SMOKE: %s glossy CTA violates the 28u white/4px/shadow contract: %s" % [state_name, button.name])
			valid = false
		if bool(button.get_meta("glossy_button", false)):
			for state_color: String in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				if not button.get_theme_color(state_color).is_equal_approx(Color.WHITE):
					push_error("VISUAL_SMOKE: %s glossy CTA %s uses gray state text %s=%s" % [state_name, button.name, state_color, button.get_theme_color(state_color)])
					valid = false
			var normal_style := button.get_theme_stylebox("normal") as StyleBoxTexture
			if normal_style == null or normal_style.region_rect != Rect2(16, 36, 480, 180) or not is_equal_approx(normal_style.texture_margin_left, 74.0) or not is_equal_approx(normal_style.texture_margin_top, 12.0) or not is_equal_approx(normal_style.texture_margin_right, 74.0) or not is_equal_approx(normal_style.texture_margin_bottom, 22.0):
				push_error("VISUAL_SMOKE: %s glossy CTA %s uses stale A1 nine-slice geometry" % [state_name, button.name])
				valid = false
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
