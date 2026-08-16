extends Node

const Rules := preload("res://gameplay/game_rules.gd")
const Market := preload("res://gameplay/market_system.gd")
const Inquiry := preload("res://gameplay/inquiry_system.gd")
const MAIN_SCENE := preload("res://main.tscn")
const ThemeMaker := preload("res://ui/theme_factory.gd")
const DutyLogScene := preload("res://ui/duty_log.gd")
const Persona := preload("res://gameplay/persona_system.gd")
const CampusCatScene := preload("res://gameplay/map/campus_cat.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	await get_tree().process_frame
	_run_data_tests()
	_run_warmth_presentation_tests()
	await _run_asset_integration_tests()
	AudioService.apply_settings({"music_enabled": false, "sfx_enabled": false})
	await _run_ui_refresh_test()
	await _run_operation_feedback_tests()
	await _run_explained_action_contract_tests()
	await _run_power_install_recovery_tests()
	await _run_rewarded_progress_tests()
	_run_rule_tests()
	_run_market_save_compatibility_tests()
	_run_gameplay_optimization_tests()
	_run_meta_progression_tests()
	_run_gameplay_depth_tests()
	_run_remaining_set_bonus_tests()
	_run_inquiry_tests()
	_run_fault_softening_tests()
	_run_initial_state_test()
	_run_core_loop_test()
	await _run_datacenter_board_tests()
	await _run_wp4_decision_ui_tests()
	await _run_contract_capacity_ui_tests()
	await _run_wp6_presentation_tests()
	_run_construction_controls_test()
	_run_construction_bays_tests()
	_run_commerce_test()
	_run_offline_test()
	_run_long_offline_test()
	_run_aging_test()
	_run_bankruptcy_test()
	_run_prestige_test()
	_run_account_reset_test()
	print("TESTS: %d passed, %d failed" % [passed, failed])
	AudioService.stop_all()
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)

func _run_data_tests() -> void:
	_expect(DataRepository.errors.is_empty(), "all JSON data files load")
	_expect(DataRepository.validate_references().is_empty(), "cross-table references are valid")
	_expect(DataRepository.get_table("events").get("items", {}).size() == 19, "market includes major contracts and three rare events")
	_expect(Monetization.is_product_available("noads") and Monetization.localized_price("noads", "") == "US$ 5.99", "mock StoreKit catalog exposes localized product prices")

func _run_warmth_presentation_tests() -> void:
	Game.reset_for_tests()
	var report := {
		"elapsed_seconds": 21600.0,
		"income": 5432.0,
		"takeovers": [{"sold_count": 1}],
		"eras": [{"era_id": 2}],
		"events": [{"type": "event_started", "event_id": "sovereign_ai"}],
		"inquiries": [{"id": "inquiry_1"}, {"id": "inquiry_2"}],
		"faults": [{"datacenter_id": "dc_1", "slot": 0}],
		"contracts": [{"type": "contract_auto_renewed"}],
		"aging": [{"datacenter_id": "dc_1", "stage": "aging"}],
	}
	var persistent_before := {
		"market_rng": int(Game.state.get("market", {}).get("rng_state", 0)),
		"inquiry_rng": int(Game.state.get("inquiries", {}).get("rng_state", 0)),
		"fault_schedule": Game.state.get("plots", []).duplicate(true),
	}
	var first := DutyLogScene.compose(report, DataRepository.tables, Game.state)
	var second := DutyLogScene.compose(report, DataRepository.tables, Game.state)
	var persistent_after := {
		"market_rng": int(Game.state.get("market", {}).get("rng_state", 0)),
		"inquiry_rng": int(Game.state.get("inquiries", {}).get("rng_state", 0)),
		"fault_schedule": Game.state.get("plots", []).duplicate(true),
	}
	_expect(first == second, "duty log composition is deterministic for identical report content")
	_expect(first.size() == 4 and str(first[0].get("type", "")) == "takeover" and str(first[1].get("type", "")) == "era" and str(first[2].get("type", "")) == "rare_market" and str(first[3].get("type", "")) == "income", "duty log keeps priority order and reserves one row for authoritative income")
	_expect(str(first[3].get("text", "")).contains(Game.format_number(5432.0)) and is_equal_approx(float(first[3].get("authoritative_income", -1.0)), 5432.0), "duty log displays the report income without recomputing the bill")
	_expect(persistent_before == persistent_after, "duty log temporary RNG leaves market inquiry and fault scheduling state byte-for-byte unchanged")
	var empty_rows := DutyLogScene.compose({"income": 0.0}, DataRepository.tables, Game.state)
	_expect(empty_rows.size() == 1 and str(empty_rows[0].get("type", "")) == "income", "an empty offline report returns only the income fallback line")

	# The era row must come from a REAL offline advance, not only from the
	# hand-built fixture above — the report plumbing regressed silently once.
	Game.reset_for_tests()
	Game.state["player"]["total_revenue"] = 49999.0
	Game.state["player"]["cash"] = 100000.0
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(600.0, false)
	var era_dc := ""
	for plot: Dictionary in Game.state.get("plots", []):
		if plot.get("datacenter") is Dictionary:
			era_dc = str((plot["datacenter"] as Dictionary).get("id", ""))
	Game.install_power(era_dc, "power_t1")
	Game.advance_time(600.0, false)
	Game.install_rack(era_dc, 0, "rack_compute_t1")
	Game.advance_time(600.0, false)
	Game.sign_contract(era_dc, "internet")
	var era_report := Game.advance_time(14400.0, true)
	var era_entries: Array = era_report.get("eras", [])
	_expect(era_entries.size() == 1 and int((era_entries[0] as Dictionary).get("era_id", 0)) == 2, "a real offline advance that crosses an era threshold records the unlock in the report")
	var era_rows := DutyLogScene.compose(era_report, DataRepository.tables, Game.state)
	var era_row_found := false
	for row: Dictionary in era_rows:
		if str(row.get("type", "")) == "era":
			era_row_found = true
	_expect(era_row_found, "the duty log surfaces an era unlocked while offline")

	var inquiry := {"id": "persona_binding_42", "template_id": "internet_anchor"}
	var persona_before := {
		"market": Game.state.get("market", {}).duplicate(true),
		"inquiries": Game.state.get("inquiries", {}).duplicate(true),
		"plots": Game.state.get("plots", []).duplicate(true),
	}
	var bound_first := Persona.persona_for_inquiry(inquiry, Game.data)
	var bound_second := Persona.persona_for_inquiry(inquiry, Game.data)
	var persona_after := {
		"market": Game.state.get("market", {}).duplicate(true),
		"inquiries": Game.state.get("inquiries", {}).duplicate(true),
		"plots": Game.state.get("plots", []).duplicate(true),
	}
	_expect(not bound_first.is_empty() and bound_first == bound_second, "persona binding is stable for the same inquiry and template")
	_expect(persona_before == persona_after, "persona binding consumes no persistent random stream")
	var all_persona_keys_resolve := true
	for item: Dictionary in Game.data.get("personas", {}).get("items", {}).values():
		all_persona_keys_resolve = all_persona_keys_resolve and tr(str(item.get("name_key", ""))) != str(item.get("name_key", ""))
		for lines: Array in item.get("lines", {}).values():
			for key: String in lines:
				all_persona_keys_resolve = all_persona_keys_resolve and tr(key) != key
	_expect(all_persona_keys_resolve, "all persona names and dialogue keys resolve through localization")

	Game.reset_for_tests()
	var relationship_dc := _test_datacenter("persona_relationship_dc", "dc_t1")
	relationship_dc["power_unit"] = "power_t1"
	relationship_dc["coolers"] = {"north": "cool_air_t1"}
	relationship_dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	relationship_dc["customer_id"] = "internet"
	relationship_dc["locked_market_multiplier"] = 1.0
	relationship_dc["contract_end_at"] = Game.simulation_time() + 600000.0
	Game.state["plots"][0]["datacenter"] = relationship_dc
	Game.state["plots"][0]["status"] = "operational"
	var relationship_notices: Array = []
	var relationship_callback := func(customer_id: String, level_index: int) -> void:
		relationship_notices.append([customer_id, level_index])
	EventBus.relationship_level_changed.connect(relationship_callback)
	Game.call("_accrue_customer_relationships", 500000.0, true)
	EventBus.relationship_level_changed.disconnect(relationship_callback)
	_expect(relationship_notices == [["internet", 3]], "one relationship signal emits only the highest level when one tick crosses multiple levels")

	Game.reset_for_tests()
	var cat_config: Dictionary = DataRepository.get_table("campus_cat")
	Game.state["flags"]["standard_built"] = true
	_expect(not CampusCatScene.is_unlocked(Game.state, cat_config), "campus cat stays hidden and inert throughout the tutorial")
	Game.state["tutorial"]["completed"] = true
	_expect(CampusCatScene.is_unlocked(Game.state, cat_config), "building a standard facility unlocks the campus cat after FTUE")
	Game.state["flags"]["standard_built"] = false
	Game.state["player"]["total_datacenters_built"] = 2
	_expect(CampusCatScene.is_unlocked(Game.state, cat_config), "two completed facilities independently unlock the campus cat")
	var cat_streams_before := {
		"market": Game.state.get("market", {}).duplicate(true),
		"inquiries": Game.state.get("inquiries", {}).duplicate(true),
		"plots": Game.state.get("plots", []).duplicate(true),
	}
	var cat := CampusCatScene.new()
	add_child(cat)
	cat.configure(Game.state, Game.data, 0, Vector2(120, 100), Rect2(40, 40, 720, 760))
	var contexts := {
		"sleep": "cat_nap",
		"stroll": "cat_parade",
		"sit": "cat_watch",
	}
	var all_contexts_match := true
	for state_id: String in contexts:
		cat.force_state_for_tests(state_id)
		all_contexts_match = all_contexts_match and cat.interact_for_tests() == str(contexts[state_id])
	cat.force_state_for_tests("sit", true)
	all_contexts_match = all_contexts_match and cat.interact_for_tests() == "cat_festival"
	_expect(all_contexts_match, "cat sleep stroll watch and rare-event contexts discover the four authored campus-life cards")
	var discovered_before_repeat: Dictionary = Game.state["meta"]["discovered"].duplicate(true)
	cat.interact_for_tests()
	_expect(Game.state["meta"]["discovered"] == discovered_before_repeat, "repeated cat interactions never rediscover or duplicate a campus-life card")
	var cat_status := Game.collection_group_status("campus_life")
	var cat_gems_before := int(Game.state["player"].get("gems", 0))
	var cat_reward := Game.claim_collection_reward("campus_life")
	var cat_reward_repeat := Game.claim_collection_reward("campus_life")
	_expect(bool(cat_status.get("complete", false)) and bool(cat_reward.get("ok", false)) and int(Game.state["player"].get("gems", 0)) == cat_gems_before + 5 and not bool(cat_reward_repeat.get("ok", false)), "campus-life group grants its existing collection reward exactly once")
	var cat_streams_after := {
		"market": Game.state.get("market", {}).duplicate(true),
		"inquiries": Game.state.get("inquiries", {}).duplicate(true),
		"plots": Game.state.get("plots", []).duplicate(true),
	}
	_expect(cat_streams_before == cat_streams_after, "cat state selection and interaction consume no persistent gameplay random stream")
	var quiet_rows := DutyLogScene.compose({"income": 0.0}, DataRepository.tables, Game.state)
	_expect(quiet_rows.size() == 2 and str(quiet_rows[0].get("type", "")) == "cat" and str(quiet_rows[1].get("type", "")) == "income", "a quiet unlocked night adds one cat observation before the authoritative income row")
	cat.queue_free()
	Game.reset_for_tests()

func _run_asset_integration_tests() -> void:
	var art_items: Dictionary = AssetCatalog.manifest.get("items", {})
	var art_loads := art_items.size() == 180
	for item: Dictionary in art_items.values():
		var path := str(item.get("path", ""))
		art_loads = art_loads and ResourceLoader.exists(path) and load(path) is Texture2D
	_expect(art_loads, "all 180 production textures import and load")
	var audio_items: Dictionary = AudioService.manifest.get("items", {})
	var audio_loads := audio_items.size() == 23
	for cue_id: String in audio_items:
		audio_loads = audio_loads and AudioService._load_stream(cue_id) != null
	_expect(audio_loads, "all 23 production audio cues import and load")
	var regular_font := ThemeMaker.font_regular()
	var glyphs_present := regular_font != null
	for character: String in ["稳", "障", "购", "罄"]:
		glyphs_present = glyphs_present and regular_font.has_char(character.unicode_at(0))
	_expect(glyphs_present, "packaged UI fonts contain risk glyphs 稳障购罄")
	var park_map := ParkMap.new()
	add_child(park_map)
	park_map.setup([{"id": "asset_test_plot", "index": 1, "status": "empty"}])
	var plot_button: Button = null
	for child: Node in park_map.content.get_children():
		if child is Button:
			plot_button = child as Button
			break
	var button_layout_ok := plot_button != null
	if plot_button != null:
		var world_art := plot_button.find_child("WorldArt", false, false) as TextureRect
		button_layout_ok = world_art != null and world_art.texture != null and plot_button.size == ParkMap.PLOT_SIZE and world_art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_expect(button_layout_ok, "production map art renders in the direct-touch world layout")
	var left_top: Vector2 = park_map.call("_plot_position", 0, 4)
	var right_top: Vector2 = park_map.call("_plot_position", 1, 4)
	var left_bottom: Vector2 = park_map.call("_plot_position", 2, 4)
	var right_bottom: Vector2 = park_map.call("_plot_position", 3, 4)
	var next_sale: Vector2 = park_map.call("_sale_position", 4)
	var first_axis := right_top - left_top
	var paired_sale: Vector2 = park_map.call("_sale_position", 3)
	var next_campus_sale: Vector2 = park_map.call("_sale_position", 6)
	var next_campus_first: Vector2 = park_map.call("_plot_position", 6, 12)
	var campus_center_x := park_map.world_size.x * 0.5 - ParkMap.PLOT_SIZE.x * 0.5
	var campus_grid_ok := first_axis.is_equal_approx(Vector2(ParkMap.COLUMN_STEP, 0.0)) and is_equal_approx(left_top.y, right_top.y) and is_equal_approx(left_bottom.y, right_bottom.y) and (left_bottom - left_top).is_equal_approx(Vector2(0, ParkMap.ROW_STEP)) and (right_bottom - right_top).is_equal_approx(Vector2(0, ParkMap.ROW_STEP)) and is_equal_approx(next_sale.x, campus_center_x) and is_equal_approx(next_sale.y, ParkMap.CAMPUS_TOP + ParkMap.ROW_STEP * 2.0) and paired_sale.is_equal_approx(Vector2(ParkMap.CAMPUS_LEFT + ParkMap.COLUMN_STEP, ParkMap.CAMPUS_TOP + ParkMap.ROW_STEP)) and next_campus_sale.is_equal_approx(Vector2(campus_center_x, ParkMap.CAMPUS_TOP)) and next_campus_first.is_equal_approx(Vector2(ParkMap.CAMPUS_LEFT, ParkMap.CAMPUS_TOP)) and bool(plot_button.get_meta("grid_slot", -1) == 0)
	var camera_start := park_map.camera_offset
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.position = Vector2(360, 720)
	touch_down.pressed = true
	park_map.call("_gui_input", touch_down)
	var drag_out := InputEventScreenDrag.new()
	drag_out.index = 0
	drag_out.position = Vector2(324, 674)
	drag_out.relative = Vector2(-36, -46)
	park_map.call("_gui_input", drag_out)
	var dragged_offset := park_map.camera_offset
	var drag_back := InputEventScreenDrag.new()
	drag_back.index = 0
	drag_back.position = Vector2(342, 696)
	drag_back.relative = Vector2(18, 22)
	park_map.call("_gui_input", drag_back)
	var panned_both_axes := dragged_offset.x < camera_start.x and dragged_offset.y < camera_start.y and park_map.camera_offset.x > dragged_offset.x and park_map.camera_offset.y > dragged_offset.y
	touch_down.pressed = false
	park_map.call("_gui_input", touch_down)
	var zoom_start := park_map.zoom
	var pinch_a := InputEventScreenTouch.new()
	pinch_a.index = 0
	pinch_a.position = Vector2(280, 720)
	pinch_a.pressed = true
	park_map.call("_gui_input", pinch_a)
	var pinch_b := InputEventScreenTouch.new()
	pinch_b.index = 1
	pinch_b.position = Vector2(520, 720)
	pinch_b.pressed = true
	park_map.call("_gui_input", pinch_b)
	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = Vector2(580, 720)
	pinch_drag.relative = Vector2(60, 0)
	park_map.call("_gui_input", pinch_drag)
	var camera_gesture_ok := panned_both_axes and park_map.zoom > zoom_start and plot_button.mouse_filter == Control.MOUSE_FILTER_PASS
	pinch_a.pressed = false
	pinch_b.pressed = false
	park_map.call("_gui_input", pinch_a)
	park_map.call("_gui_input", pinch_b)
	park_map.reset_camera()
	# The cinematic polish stays presentation-only and must clean up after itself.
	Game.reset_for_tests()
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(300.0, false)
	park_map.setup(Game.state.get("plots", []))
	await get_tree().process_frame
	park_map.play_construction_completion("plot_1")
	var dust_sweeps := park_map.find_children("CompletionDust*", "TextureRect", true, false)
	var construction_stage_ok := park_map.find_child("ConstructionGhost", true, false) != null and dust_sweeps.size() == 1
	if construction_stage_ok:
		var dust_sweep := dust_sweeps[0] as TextureRect
		var completed_art := park_map.find_child("WorldArt", true, false) as TextureRect
		construction_stage_ok = dust_sweep.name == "CompletionDustSweep" and dust_sweep.size.x > dust_sweep.size.y and dust_sweep.texture == AssetCatalog.texture("fx_dust_puff") and completed_art != null and dust_sweep.get_index() < completed_art.get_index()
	await get_tree().create_timer(0.82).timeout
	construction_stage_ok = construction_stage_ok and park_map.find_child("ConstructionGhost", true, false) == null and park_map.find_children("CompletionDust*", "TextureRect", true, false).is_empty()
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	Game.install_power(str(dc.get("id", "")), "power_t1")
	Game.advance_time(300.0, false)
	park_map.set_preview_hour(12.0)
	park_map.setup(Game.state.get("plots", []))
	await get_tree().process_frame
	var active_art := park_map.get("_active_art") as Array
	park_map.set("_ambient_time", 0.0)
	park_map.call("_process", 0.0)
	var window_breath_ok := not active_art.is_empty()
	if window_breath_ok:
		var powered_art := active_art[0] as TextureRect
		window_breath_ok = powered_art.scale.is_equal_approx(Vector2.ONE) and powered_art.self_modulate.r >= 1.0 and powered_art.self_modulate.r <= 1.06
	park_map.play_power_on(str(dc.get("id", "")))
	var power_stage_ok := park_map.find_child("PowerOnDarkGhost", true, false) != null and park_map.find_child("PowerOnGlow", true, false) == null
	await get_tree().create_timer(0.72).timeout
	power_stage_ok = power_stage_ok and park_map.find_child("PowerOnDarkGhost", true, false) == null and park_map.find_child("PowerOnGlow", true, false) == null
	park_map.set("_idle_seconds", ParkMap.CAMERA_BREATH_DELAY + 2.0)
	park_map.set("_camera_breath_phase", PI / 0.24)
	park_map.call("_update_camera_breath", 0.0)
	var camera_breath_ok := bool(park_map.get("_camera_breathing")) and park_map.content.scale.x > park_map.zoom and park_map.content.scale.x <= park_map.zoom * 1.021
	park_map.notify_user_input()
	camera_breath_ok = camera_breath_ok and park_map.content.scale.is_equal_approx(Vector2.ONE * park_map.zoom)
	campus_grid_ok = campus_grid_ok and camera_gesture_ok and construction_stage_ok and power_stage_ok and window_breath_ok and camera_breath_ok
	_expect(campus_grid_ok, "campus grid and presentation-only world transitions stay deterministic and self-cleaning")
	park_map.queue_free()
	await get_tree().process_frame

func _run_ui_refresh_test() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_refresh")
	await get_tree().process_frame
	var spotlight := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	var primary := main.find_child("PrimaryWorldAction", true, false) as Control
	var spotlight_rect: Rect2 = spotlight.get("target_rect") if spotlight != null else Rect2()
	_expect(spotlight != null and spotlight.visible and bool(spotlight.call("is_actionable")) and primary != null and spotlight_rect.intersects(primary.get_global_rect()), "FTUE spotlight resolves and gates input to the primary build action")
	Game.state["tutorial"]["step"] = 1
	main.call("_refresh_hud")
	# A step whose data center is gone must hand the player a way back rather than
	# fading to an inert bubble: the old behaviour left a save stranded on "under
	# construction, 0s left" with nothing on screen to tap.
	var rebuild_rect: Rect2 = spotlight.get("target_rect")
	_expect(spotlight.visible and bool(spotlight.call("is_actionable")) and primary != null and primary.visible and rebuild_rect.intersects(primary.get_global_rect()), "FTUE routes back to rebuilding when its data center is absent")
	# The remaining checks exercise ordinary post-FTUE pages and sheets. Leaving
	# the tutorial active would correctly force their incompatible surfaces back
	# to the current lesson, contaminating these unrelated UI assertions.
	Game.state["tutorial"]["completed"] = true
	main.call("_refresh_hud")
	main.call("_navigate", "store")
	main.call("_refresh")
	await get_tree().process_frame
	var scroll := main.find_child("PageScroll", true, false) as ScrollContainer
	var stable := scroll != null
	var before_id := 0
	var before_scroll := 0
	if scroll != null:
		var scroll_content := scroll.get_child(0) as Control
		if scroll_content != null:
			scroll_content.custom_minimum_size.y = maxf(scroll_content.get_combined_minimum_size().y, scroll.size.y + 640.0)
		await get_tree().process_frame
		await get_tree().process_frame
		scroll.scroll_vertical = 240
		await get_tree().process_frame
		before_id = scroll.get_instance_id()
		before_scroll = scroll.scroll_vertical
		Game.advance_time(2.0, false)
		await get_tree().create_timer(0.40).timeout
		var after_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		stable = after_scroll != null and after_scroll.get_instance_id() == before_id and after_scroll.scroll_vertical == before_scroll and before_scroll > 0
	_expect(stable, "tick refresh preserves the live page node and nonzero scroll position")
	main.call("_navigate", "map")
	main.call("_refresh")
	main.call("_show_plot_purchase")
	await get_tree().process_frame
	var overlay := main.find_child("ActionSheetOverlay", true, false) as ColorRect
	var drag_handle := main.find_child("SheetDragHandle", true, false) as Control
	var sheet_close := main.find_child("SheetCloseButton", true, false) as Button
	var sheet_routes_ok: bool = overlay != null and bool(overlay.get_meta("backdrop_dismiss_enabled", false)) and int(overlay.get_meta("explicit_close_count", 0)) == 1 and sheet_close != null and drag_handle != null and drag_handle.size.y >= 88.0 and not overlay.gui_input.get_connections().is_empty() and not drag_handle.gui_input.get_connections().is_empty()
	_expect(sheet_routes_ok, "action sheet exposes one explicit close, backdrop tap, and 44pt drag-dismiss routes")
	_expect(main.find_child("SheetCancelButton", true, false) == null, "action sheet removes the redundant full-width cancel action")
	var backdrop_press := InputEventScreenTouch.new()
	backdrop_press.position = Vector2(8, 8)
	backdrop_press.pressed = true
	overlay.gui_input.emit(backdrop_press)
	var backdrop_release := InputEventScreenTouch.new()
	backdrop_release.position = Vector2(8, 8)
	backdrop_release.pressed = false
	overlay.gui_input.emit(backdrop_release)
	await get_tree().create_timer(0.24).timeout
	_expect(not is_instance_valid(overlay), "action sheet backdrop tap closes after its exit animation")
	# Generic reward-juice coverage belongs to the post-tutorial state. Active
	# FTUE steps intentionally suppress world coin trajectories (FT2).
	main.call("_refresh_hud")
	main.call("_fly_cash_reward", Vector2(220, 520), 12)
	await get_tree().process_frame
	var fx_layer := main.find_child("FxLayer", true, false)
	_expect(fx_layer != null and int(fx_layer.call("active_coin_count")) == 8, "coin feedback caps a reward burst at eight particles")
	await get_tree().create_timer(1.1).timeout
	_expect(fx_layer != null and int(fx_layer.call("active_coin_count")) == 0, "coin feedback releases all particles after wallet arrival")
	Game.state["player"]["cash"] = float(Game.state["player"].get("cash", 0.0)) + 100.0
	main.call("_refresh_hud")
	_expect(is_equal_approx(float(main.get("_cash_target")), float(Game.state["player"]["cash"])), "cash HUD animates toward the authoritative balance")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _run_operation_feedback_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.buy_next_plot()
	Game.buy_next_plot()
	Game.buy_next_plot()
	var first := Game.start_datacenter_construction("plot_1", "dc_t0")
	var second := Game.start_datacenter_construction("plot_2", "dc_t1")
	var rejected := Game.start_datacenter_construction("plot_3", "dc_t1")
	var service_dc := _test_datacenter("feedback_dc", "dc_t1")
	Game.state["plots"][3]["datacenter"] = service_dc
	Game.state["plots"][3]["status"] = "operational"
	var rejected_power := Game.install_power("feedback_dc", "power_t1")
	var rejected_cooler := Game.install_cooler("feedback_dc", "north", "cool_air_t1")
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_refresh")
	main.call("_show_building_picker", "plot_3")
	await get_tree().process_frame
	main.call("_handle_result", rejected, {"plot_id": "plot_3", "operation": "datacenter"})
	await get_tree().process_frame
	var toast := main.get("toast_label") as Label
	var feedback_layer := main.get("feedback_layer") as CanvasLayer
	var picker := main.find_child("BuildingPicker", true, false) as CanvasItem
	var queue_feedback_ok := bool(first.get("ok", false)) and bool(second.get("ok", false)) and str(rejected.get("reason", "")) == "queue_full"
	queue_feedback_ok = queue_feedback_ok and str(rejected_power.get("reason", "")) == "queue_full" and str(rejected_cooler.get("reason", "")) == "queue_full"
	queue_feedback_ok = queue_feedback_ok and toast != null and toast.visible and feedback_layer != null and feedback_layer.layer > 0 and toast.z_index > (picker.z_index if picker != null else 0)
	queue_feedback_ok = queue_feedback_ok and "2/2" in toast.text and Game.format_duration(300.0) in toast.text and toast.autowrap_mode != TextServer.AUTOWRAP_OFF
	service_dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "installing", "install_complete_at": Game.simulation_time() + 240.0}
	service_dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "installing", "install_complete_at": Game.simulation_time() + 480.0}
	var rejected_rack := Game.install_rack("feedback_dc", 3, "rack_compute_t1")
	main.call("_handle_result", rejected_rack, {"datacenter_id": "feedback_dc", "slot": 3, "operation": "rack"})
	queue_feedback_ok = queue_feedback_ok and str(rejected_rack.get("reason", "")) == "rack_install_limit" and Game.format_duration(240.0) in toast.text
	# A second rapid failure must replace and restart the feedback lifetime.  The
	# old implementation left both fade tweens alive, so the first click could
	# hide the message raised by the second click.
	main.call("_handle_result", {"ok": false, "reason": "not_enough_cash"})
	await get_tree().create_timer(1.8).timeout
	queue_feedback_ok = queue_feedback_ok and toast.visible and toast.text == tr("REASON_NOT_ENOUGH_CASH")
	_expect(queue_feedback_ok, "rejected operations stay visible above sheets and rapid retries restart friendly feedback")

	var reasons := [
		"already_owned", "building_tier_too_low", "construction_in_progress", "construction_missing",
		"contract_capacity_required", "cooler_slots_full", "datacenter_missing", "datacenter_unavailable", "invalid_edge", "invalid_slot",
		"locked", "not_an_upgrade", "not_enough_cash", "not_enough_gems", "not_faulted", "not_ruined", "power_required",
		"plot_unavailable", "prestige_locked", "product_unavailable", "purchase_limit", "purchase_pending",
		"queue_full", "rack_install_limit", "rack_unavailable", "reward_limit", "reward_pending",
		"reward_unavailable", "slot_empty", "slot_locked", "slot_occupied", "ticket_unavailable",
		"too_new_to_retire", "tutorial_building_retired", "unknown",
	]
	var original_locale := TranslationServer.get_locale()
	var all_reasons_localized := true
	for locale: String in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for reason: String in reasons:
			var copy := str(main.call("_reason_text", reason))
			all_reasons_localized = all_reasons_localized and not copy.is_empty() and copy != reason and not copy.begins_with("REASON_")
	TranslationServer.set_locale(original_locale)
	_expect(all_reasons_localized, "every core operation rejection has readable English and Chinese copy")
	main.queue_free()
	await get_tree().process_frame

func _run_explained_action_contract_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["era"] = 1
	Game.state["player"]["network_level"] = 2
	Game.state["player"]["cash"] = 500000.0
	Game.state["entitlements"]["noads"] = true
	var now := Game.simulation_time()
	Game.state["construction_queue"] = [{
		"id": "feedback_limit_job", "type": "datacenter", "started_at": now,
		"complete_at": now + 600.0, "ad_uses": 2,
	}]
	var dc := _test_datacenter("feedback_entry_dc", "dc_t0")
	dc["power_unit"] = "power_t1"
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"

	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_navigate", "tech")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var explained_locked: Array[Node] = []
	for node: Node in main.find_children("*", "Button", true, false):
		if str(node.get_meta("unavailable_reason", "")) == "locked":
			explained_locked.append(node)
	var locked_buttons_tappable := explained_locked.size() >= 2
	for node: Node in explained_locked:
		locked_buttons_tappable = locked_buttons_tappable and not (node as Button).disabled and not (node as Button).pressed.get_connections().is_empty()
	var era_copy := str(main.call("_failure_message", "locked", {"unlock_era": 2}))
	_expect(locked_buttons_tappable and "2" in era_copy, "locked technology actions stay tappable and explain their exact unlock era")

	main.call("_navigate", "build")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var limited_reward: Button = null
	for node: Node in main.find_children("*", "Button", true, false):
		if str(node.get_meta("unavailable_reason", "")) == "reward_limit":
			limited_reward = node as Button
			break
	_expect(limited_reward != null and not limited_reward.disabled and not limited_reward.pressed.get_connections().is_empty(), "exhausted reward actions remain tappable so the limit is explained")

	main.call("_navigate", "store")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var owned_product := main.find_child("StoreBuy_noads", true, false) as Button
	_expect(owned_product != null and not owned_product.disabled and str(owned_product.get_meta("unavailable_reason", "")) == "already_owned", "owned store actions explain their terminal state instead of silently disabling")

	main.call("_navigate", "map")
	main.call("_refresh")
	await get_tree().process_frame
	main.call("_show_rack_picker", dc["id"], 2)
	await get_tree().process_frame
	var toast := main.get("toast_label") as Label
	var guarded_entries_ok := toast != null and toast.text == tr("REASON_SLOT_LOCKED") and main.find_child("ActionSheetOverlay", true, false) == null
	main.call("_show_attachment_picker", "missing_dc", "power", "")
	await get_tree().process_frame
	guarded_entries_ok = guarded_entries_ok and toast.text == tr("REASON_DATACENTER_MISSING")
	main.call("_show_rack_actions", dc["id"], 12)
	await get_tree().process_frame
	guarded_entries_ok = guarded_entries_ok and toast.text == tr("REASON_INVALID_SLOT")
	main.call("_open_datacenter_detail", "missing_dc", "contracts")
	await get_tree().process_frame
	guarded_entries_ok = guarded_entries_ok and toast.text == tr("REASON_DATACENTER_MISSING") and str(main.get("active_page")) == "map"
	_expect(guarded_entries_ok, "stale data-center rack attachment and contract entry points always return visible guidance")

	main.queue_free()
	await get_tree().process_frame

func _run_power_install_recovery_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 1500.0
	var dc := _test_datacenter("power_recovery_dc", "dc_t1")
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_open_datacenter_detail", dc["id"], "board")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var power_slot := main.find_child("PowerSlot", true, false) as Button
	var power_usage := main.find_child("BoardPowerUsage", true, false) as RichTextLabel
	_expect(power_slot != null and "$600" in power_slot.text and power_usage != null and str(power_usage.get_meta("display_copy", "")) == tr("POWER_UNPOWERED_HINT"), "an unpowered room presents a price-disclosed one-tap T1 recovery action")

	var now := Game.simulation_time()
	Game.state["construction_queue"] = [
		{"id": "power_blocker_a", "type": "datacenter", "started_at": now, "complete_at": now + 300.0},
		{"id": "power_blocker_b", "type": "datacenter", "started_at": now, "complete_at": now + 600.0},
	]
	var cash_before := float(Game.state["player"]["cash"])
	if power_slot != null:
		power_slot.pressed.emit()
	await get_tree().process_frame
	var blocker := main.find_child("ActionSheetOverlay", true, false) as Control
	var queue_action := main.find_child("Choice_queue", true, false) as Button
	var blocker_status := main.find_child("ActionSheetStatus", true, false) as Label
	_expect(blocker != null and queue_action != null and blocker_status != null and "2/2" in blocker_status.text, "a full queue explains why transformer installation cannot start and offers the queue action")
	_expect(is_equal_approx(float(Game.state["player"]["cash"]), cash_before) and _pending_power_job_for_test(dc["id"]).is_empty(), "a blocked transformer tap never spends cash or creates a hidden project")
	queue_action.pressed.emit()
	await get_tree().create_timer(0.35).timeout
	_expect(str(main.get("active_page")) == "build" and main.find_child("ActionSheetOverlay", true, false) == null, "the blocker action takes the player directly to the construction queue")

	Game.state["construction_queue"] = []
	main.call("_on_power_slot_selected", dc["id"])
	await get_tree().process_frame
	await get_tree().process_frame
	var pending := _pending_power_job_for_test(dc["id"])
	power_slot = main.find_child("PowerSlot", true, false) as Button
	power_usage = main.find_child("BoardPowerUsage", true, false) as RichTextLabel
	# The build page does not contain a board; reopen it to verify that the same
	# control now reports progress rather than continuing to say Install.
	main.call("_open_datacenter_detail", dc["id"], "board")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	power_slot = main.find_child("PowerSlot", true, false) as Button
	power_usage = main.find_child("BoardPowerUsage", true, false) as RichTextLabel
	_expect(not pending.is_empty() and is_equal_approx(float(Game.state["player"]["cash"]), 900.0), "the normal first-transformer tap starts T1 immediately and charges exactly its disclosed price")
	_expect(power_slot != null and power_slot.text == tr("INSTALLING") and power_usage != null and bool(power_usage.get_meta("power_pending", false)) and str(power_usage.get_meta("display_copy", "")) != tr("POWER_UNPOWERED_HINT"), "a pending transformer replaces the dead dark-room state with visible installation progress")
	main.queue_free()
	await get_tree().process_frame

func _pending_power_job_for_test(datacenter_id: String) -> Dictionary:
	for queued: Dictionary in Game.state.get("construction_queue", []):
		if str(queued.get("type", "")) == "power" and str(queued.get("datacenter_id", "")) == datacenter_id:
			return queued
	return {}

func _run_rewarded_progress_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 10000.0
	Game.state["entitlements"]["noads"] = true
	var result := Game.start_datacenter_construction("plot_1", "dc_t1")
	var item: Dictionary = result.get("construction", {})
	Game.advance_time(160.0, false)
	var reward := Game.request_reward("construction:%s" % item.get("id", ""))
	var remaining := float(item.get("complete_at", 0.0)) - Game.simulation_time()
	_expect(bool(reward.get("ok", false)) and int(item.get("ad_uses", 0)) == 1 and is_equal_approx(float(item.get("duration_seconds", 0.0)), 3600.0) and absf(remaining - 1640.0) < 0.1, "a 30-minute reward advances a one-hour project while preserving its original duration")
	# Simulate an upgraded save whose rewarded project predates duration_seconds.
	item.erase("duration_seconds")
	Game._ensure_state_shape()
	_expect(is_equal_approx(float(item.get("duration_seconds", 0.0)), 3600.0), "legacy rewarded projects reconstruct their authored duration instead of treating the shortened end time as total work")

	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_refresh")
	await get_tree().process_frame
	var world_progress := main.find_child("ConstructionProgress", true, false) as ProgressBar
	var world_fraction := world_progress.value / world_progress.max_value if world_progress != null else 0.0
	main.call("_navigate", "build")
	main.call("_refresh")
	await get_tree().process_frame
	var queue_progress := main.find_child("QueueConstructionProgress", true, false) as ProgressBar
	var queue_fraction := queue_progress.value / queue_progress.max_value if queue_progress != null else 0.0
	_expect(world_progress != null and world_fraction > 0.53 and world_fraction < 0.56, "the park construction bar counts rewarded minutes as completed progress")
	_expect(queue_progress != null and queue_fraction > 0.53 and queue_fraction < 0.56, "the construction queue shows roughly fifty-four percent after 2m40s elapsed plus a 30-minute reward")
	main.queue_free()
	await get_tree().process_frame

func _run_rule_tests() -> void:
	var economy: Dictionary = DataRepository.get_table("economy")
	_expect(is_equal_approx(Rules.land_price(2, economy), 965.0), "second plot price follows the bounded power curve")
	_expect(is_equal_approx(Rules.land_price(5, economy), 2862.0), "fifth plot price keeps the original early-game scale")
	_expect(is_equal_approx(Rules.land_price(7, economy), 4815.0), "first expansion-campus plot applies only the configured eight-percent premium")
	_expect(is_equal_approx(Rules.land_price(100, economy), 222970.0), "hundredth plot remains below a top-tier building cost")
	var last_starter := Rules.campus_layout_for_plot(6, economy)
	var first_expansion := Rules.campus_layout_for_plot(7, economy)
	var third_campus := Rules.campus_layout_for_plot(15, economy)
	_expect(str(last_starter.get("type_id", "")) == "type_1" and int(last_starter.get("local_slot", -1)) == 5, "starter campus owns exactly six ordered slots")
	_expect(str(first_expansion.get("type_id", "")) == "type_2" and int(first_expansion.get("capacity", 0)) == 8 and int(first_expansion.get("campus_index", -1)) == 1, "second campus is the eight-slot expansion type")
	_expect(int(third_campus.get("campus_index", -1)) == 2 and str(third_campus.get("type_id", "")) == "type_2", "expansion campus type repeats without imposing a global building cap")
	_expect(is_equal_approx(Rules.aging_efficiency(0.75), 0.85), "aging efficiency interpolates")
	_expect(is_equal_approx(Rules.aging_efficiency(0.95), 0.55), "decline efficiency interpolates")
	var ambient_dc := {"power_unit": "power_t1", "coolers": {}, "racks": [null, null, null, null, {"rack_id": "rack_storage_t1", "status": "active"}, null, null, null, null]}
	var ambient_status: Dictionary = Rules.rack_runtime_status(ambient_dc, 4, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_expect(not bool(ambient_status.get("overheated", true)), "ambient cooling keeps a center storage rack healthy")
	var future := GameClock.wall_time() + 100
	_expect(bool(GameClock.elapsed_since(future, future).get("rollback", false)), "wall-clock rollback is rejected")
	_expect(int(SaveManager.migrate({"save_version": 0}).get("save_version", 0)) == SaveManager.SAVE_VERSION, "legacy save migrates to current schema")

func _run_meta_progression_tests() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 1
	var gems_before := int(Game.state["player"].get("gems", 0))
	var roadmap := Game.claim_roadmap_reward("first_facility")
	var roadmap_repeat := Game.claim_roadmap_reward("first_facility")
	_expect(bool(roadmap.get("ok", false)) and int(Game.state["player"].get("gems", 0)) == gems_before + 3 and not bool(roadmap_repeat.get("ok", false)), "roadmap rewards a permanent milestone exactly once")

	var dc := _test_datacenter("dc_meta", "dc_t1")
	dc["power_unit"] = "power_t2"
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	dc["racks"][1] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	Game.state["meta"]["seen_customers"]["internet"] = true
	var strategic_locked := Game.sign_contract(dc["id"], "internet", "strategic")
	Game.state["meta"]["customer_service_seconds"]["internet"] = 43200.0
	var strategic := Game.sign_contract(dc["id"], "internet", "strategic")
	var term_seconds := float(dc.get("contract_end_at", 0.0)) - Game.simulation_time()
	_expect(not bool(strategic_locked.get("ok", false)) and strategic_locked.get("reason", "") == "relationship_required" and bool(strategic.get("ok", false)) and is_equal_approx(float(dc.get("contract_income_multiplier", 0.0)), 1.04) and is_equal_approx(term_seconds, 12.0 * 7200.0), "strategic contracts require familiarity and then lock twelve months at the authored premium")
	var before_service := float(Game.state["meta"]["customer_service_seconds"]["internet"])
	Game.advance_time(240.0, false)
	_expect(float(Game.state["meta"]["customer_service_seconds"]["internet"]) > before_service and float(Rules.relationship_level("internet", Game.state, Game.data).get("income_multiplier", 0.0)) >= 1.01, "customer relationships grow through service and never decay")

	var specialization := Game.set_campus_specialization(0, "hosting")
	var status := Rules.campus_specialization_status(0, "hosting", Game.state, Game.data)
	_expect(bool(specialization.get("ok", false)) and bool(status.get("active", false)) and Rules.campus_specialization_income_multiplier(dc, Game.state, Game.data) > 1.0, "a campus specialization activates only from its real layout conditions")

	Game.state["stats"]["prestige_count"] = 2
	var board_a := Game.allocate_board_point("construction")
	var board_b := Game.allocate_board_point("business")
	var board_full := Game.allocate_board_point("operations")
	_expect(bool(board_a.get("ok", false)) and bool(board_b.get("ok", false)) and not bool(board_full.get("ok", false)) and Game.board_points_available() == 0, "one permanent board point is available per completed company legacy")

	Game.call("_discover", "buildings", "dc_t0")
	Game.call("_discover", "racks", "rack_compute_t1")
	Game.call("_discover", "attachments", "power_t1")
	var facility_status := Game.collection_group_status("facilities")
	_expect(bool(facility_status.get("ok", false)) and int(facility_status.get("discovered", 0)) >= 3 and int(facility_status.get("total", 0)) > int(facility_status.get("discovered", 0)), "company collection counts only assets actually encountered")

	var meta_snapshot: Dictionary = Game.state["meta"].duplicate(true)
	Game._ensure_state_shape()
	_expect(Game.state["meta"].has("collection_claimed") and Game.state["meta"].has("discovered") and Game.state["meta"]["roadmap_claimed"] == meta_snapshot["roadmap_claimed"], "meta progression survives state-shape migration without losing claims")

func _run_market_save_compatibility_tests() -> void:
	Game.reset_for_tests()
	# JSON parses whole numbers as floats. This is the exact shape loaded from an
	# on-device save, and must still resolve the string-keyed era price table.
	Game.state["player"]["era"] = 1.0
	Game.state["player"]["network_level"] = 1.0
	Game.state["technology"]["repair_team"] = 1.0
	Game.state["market"]["noise"]["internet"] = 0.0
	Game.state["market"]["history"]["internet"] = [
		{"at": 0.0, "value": 0.0},
		{"at": 240.0, "value": 0.0},
	]
	Game.state["market"].erase("quote_schema_version")
	var market := Market.new()
	market.ensure_state(Game.state, Game.data)
	var quote := Game.market_multiplier("internet")
	var repaired_history: Array = Game.state["market"]["history"]["internet"]
	_expect(quote > 0.0 and is_equal_approx(float(Game.state["market"]["noise"]["internet"]), 1.0) and repaired_history.is_empty(), "float-shaped saves restore positive market quotes and discard impossible zero history")

	var dc := _test_datacenter("dc_float_progression", "dc_t1")
	dc["power_unit"] = "power_t1"
	dc["coolers"] = {"north": "cool_air_t1"}
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	dc["customer_id"] = "internet"
	dc["locked_market_multiplier"] = 1.0
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var float_progression_income := Game.datacenter_monthly_income(dc)
	Game.state["player"]["era"] = 1
	Game.state["player"]["network_level"] = 1
	var integer_progression_income := Game.datacenter_monthly_income(dc)
	_expect(float_progression_income > 0.0 and is_equal_approx(float_progression_income, integer_progression_income), "saved float era and network levels preserve the same positive rack income as a fresh session")

func _run_gameplay_optimization_tests() -> void:
	var market := Market.new()
	var event_state := Game._new_state()
	event_state["player"]["era"] = 3
	event_state["player"]["network_level"] = 1
	var low_network_clean := true
	for index: int in range(300):
		var event_id := market._pick_event(event_state, Game.data)
		low_network_clean = low_network_clean and int(DataRepository.get_entry("events", event_id).get("minimum_network_level", 1)) <= 1
	_expect(low_network_clean, "major market contracts never appear below their network requirement")
	event_state["player"]["network_level"] = 4
	var saw_major_contract := false
	for index: int in range(300):
		var event_id := market._pick_event(event_state, Game.data)
		if int(DataRepository.get_entry("events", event_id).get("minimum_network_level", 1)) >= 3:
			saw_major_contract = true
	_expect(saw_major_contract, "high-level networks unlock major market contracts")

	var storage_dc := _test_datacenter("dc_market_storage", "dc_t1")
	storage_dc["customer_id"] = "internet"
	storage_dc["power_unit"] = "power_t1"
	storage_dc["racks"][4] = {"rack_id": "rack_storage_t1", "status": "active", "enabled": true}
	var storage_state := Game._new_state()
	storage_state["plots"][0]["datacenter"] = storage_dc
	storage_state["plots"][0]["status"] = "operational"
	var storage_downturn := Rules.datacenter_income_per_month(storage_dc, storage_state, Game.data, func(_customer_id: String) -> float: return 0.5)
	_expect(is_equal_approx(storage_downturn, 36.125), "storage racks absorb downturns with thirty-percent market sensitivity")
	var gpu_dc := _test_datacenter("dc_market_gpu", "dc_t1")
	gpu_dc["customer_id"] = "gpu_company"
	gpu_dc["power_unit"] = "power_t2"
	gpu_dc["coolers"] = {"north": "cool_air_t2"}
	gpu_dc["racks"][0] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	var gpu_state := Game._new_state()
	gpu_state["player"]["era"] = 2
	gpu_state["player"]["network_level"] = 2
	gpu_state["plots"][0]["datacenter"] = gpu_dc
	gpu_state["plots"][0]["status"] = "operational"
	var gpu_downturn := Rules.datacenter_income_per_month(gpu_dc, gpu_state, Game.data, func(_customer_id: String) -> float: return 0.5)
	_expect(is_equal_approx(gpu_downturn, 276.0), "GPU racks amplify market movements with one-hundred-twenty-percent sensitivity")

	Game.reset_for_tests()
	Game.state["plots"][0]["datacenter"] = _test_datacenter("dc_parallel", "dc_t0")
	Game.state["plots"][0]["status"] = "operational"
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	Game.state["construction_queue"] = [Game._queue_item("network", 1000.0), Game._queue_item("network", 1000.0)]
	var first := Game.install_rack(dc["id"], 0, "rack_compute_t1")
	var second := Game.install_rack(dc["id"], 1, "rack_storage_t1")
	var third := Game.install_rack(dc["id"], 3, "rack_compute_t1")
	_expect(bool(first.get("ok", false)) and bool(second.get("ok", false)) and Game.state["construction_queue"].size() == 2, "two rack installs run inside a data center without occupying the global queue")
	_expect(not bool(third.get("ok", true)) and third.get("reason", "") == "rack_install_limit", "a data center enforces its two-rack installation capacity")
	Game.advance_time(120.0, false)
	_expect(dc["racks"][0].get("status", "") == "active" and dc["racks"][1].get("status", "") == "active", "parallel rack installations finish independently")
	dc["power_unit"] = "power_t1"
	dc["customer_id"] = "internet"
	Game._reschedule_dc_faults(dc)
	var full_income := Game.datacenter_monthly_income(dc)
	var paused := Game.set_rack_enabled(dc["id"], 0, false)
	var paused_status := Rules.rack_runtime_status(dc, 0, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_expect(bool(paused.get("ok", false)) and not bool(paused_status.get("powered", true)) and float(dc["racks"][0].get("fault_at", 0.0)) < 0.0, "pausing a rack removes it from power allocation and fault scheduling")
	_expect(Game.datacenter_monthly_income(dc) < full_income, "paused racks stop generating contract income")
	_expect(Game.set_rack_enabled(dc["id"], 0, true).get("ok", false) and float(dc["racks"][0].get("fault_at", -1.0)) > Game.simulation_time(), "resuming a rack restores fault scheduling")
	Game.reset_for_tests()
	Game.state["plots"][0]["datacenter"] = _test_datacenter("dc_rack_accelerator", "dc_t0")
	Game.state["plots"][0]["status"] = "operational"
	dc = Game.state["plots"][0]["datacenter"]
	Game.install_rack(dc["id"], 0, "rack_compute_t1")
	var gems_before := int(Game.state["player"]["gems"])
	_expect(Game.speed_up_rack_install_with_gems(dc["id"], 0).get("ok", false) and dc["racks"][0].get("status", "") == "active" and int(Game.state["player"]["gems"]) == gems_before - 1, "rack-local installation keeps its diamond accelerator")
	Game.reset_for_tests()
	Game.state["plots"][0]["datacenter"] = _test_datacenter("dc_legacy_rack", "dc_t0")
	Game.state["plots"][0]["status"] = "operational"
	dc = Game.state["plots"][0]["datacenter"]
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "installing", "construction_id": "legacy_rack_job"}
	Game.state["construction_queue"] = [{"id": "legacy_rack_job", "type": "rack", "datacenter_id": dc["id"], "slot": 0, "rack_id": "rack_compute_t1", "started_at": 10.0, "complete_at": 130.0, "ad_uses": 1, "cost": 300.0}]
	Game._ensure_state_shape()
	_expect(Game.state["construction_queue"].is_empty() and float(dc["racks"][0].get("install_complete_at", 0.0)) == 130.0 and bool(dc["racks"][0].get("enabled", false)), "v1 rack queue jobs migrate into v2 rack-local installation state")

	Game.reset_for_tests()
	Game.state["plots"][0]["datacenter"] = _test_datacenter("dc_contract", "dc_t1")
	Game.state["plots"][0]["status"] = "operational"
	dc = Game.state["plots"][0]["datacenter"]
	Game.state["player"]["era"] = 2
	Game.state["player"]["network_level"] = 2
	dc["power_unit"] = "power_t2"
	dc["coolers"] = {"north": "cool_air_t2"}
	dc["racks"][0] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	_expect(Game.sign_contract(dc["id"], "gpu_company").get("ok", false), "contract starts a fixed initial term and locks the no-noise market rate")
	var locked_before_event := float(dc.get("locked_market_multiplier", 0.0))
	var income_before_event := Game.datacenter_monthly_income(dc)
	Game.state["market"]["active"] = [{"event_id": "ai_model_boom", "started_at": Game.simulation_time(), "end_at": Game.simulation_time() + 43200.0 * 4.0}]
	_expect(is_equal_approx(Game.contract_market_multiplier("gpu_company"), locked_before_event * 3.0) and is_equal_approx(Game.datacenter_monthly_income(dc), income_before_event), "a new three-times market event does not change income on an existing locked contract")
	var term_end := float(dc.get("contract_end_at", 0.0))
	var renewal_report := Game.advance_time(term_end - Game.simulation_time(), false)
	_expect(float(dc.get("contract_end_at", 0.0)) == term_end + 43200.0 and bool(dc.get("free_switch_available", false)) and is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), Game.contract_market_multiplier("gpu_company")) and renewal_report.get("contracts", []).size() == 1, "term expiry renews without a gap, relocks at the no-noise rate, and grants one non-expiring free switch")
	var cash_after_renewal := float(Game.state["player"]["cash"])
	Game.advance_time(1.0, false)
	_expect(float(Game.state["player"]["cash"]) > cash_after_renewal, "automatic renewal keeps contract income continuous across the term boundary")
	var cash_before_switch := float(Game.state["player"]["cash"])
	_expect(Game.sign_contract(dc["id"], "cloud").get("ok", false) and is_equal_approx(float(Game.state["player"]["cash"]), cash_before_switch) and not bool(dc.get("free_switch_available", true)) and is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), Game.contract_market_multiplier("cloud")), "the saved free switch changes client and locked income exactly once without a fee")
	var paid_fee := Game.contract_switch_fee(dc["id"], "internet")
	var cash_before_paid_switch := float(Game.state["player"]["cash"])
	_expect(paid_fee >= 25.0 and Game.sign_contract(dc["id"], "internet").get("ok", false) and is_equal_approx(float(Game.state["player"]["cash"]), cash_before_paid_switch - paid_fee), "the next early switch restores the twenty-five-percent breach fee")
	term_end = float(dc.get("contract_end_at", 0.0))
	var offline_renewals := Game.advance_time(term_end + 43200.0 - Game.simulation_time(), true)
	var persisted_state := Game.state.duplicate(true)
	Game.state = persisted_state
	Game._ensure_state_shape()
	dc = Game.state["plots"][0]["datacenter"]
	_expect(bool(dc.get("free_switch_available", false)) and offline_renewals.get("contracts", []).size() == 2, "unused free-switch eligibility survives multiple offline renewals and a save reload without stacking")
	dc.erase("locked_market_multiplier")
	dc.erase("free_switch_available")
	dc["renewal_window_end_at"] = Game.simulation_time() + 60.0
	Game._ensure_state_shape()
	_expect(not dc.has("renewal_window_end_at") and bool(dc.get("free_switch_available", false)) and dc.has("locked_market_multiplier"), "legacy renewal-window saves migrate to a locked rate and non-expiring free switch")

func _run_gameplay_depth_tests() -> void:
	var events: Dictionary = DataRepository.get_table("events").get("items", {})
	_expect(int(DataRepository.get_table("inquiries").get("items", {}).get("mining_rush", {}).get("unlock_era", 0)) == 2, "the GPU-gated mining inquiry cannot arrive before Era 2")
	var rare_ids := ["sovereign_ai", "compute_famine", "compliance_archive"]
	var rare_data_ok := true
	for event_id: String in rare_ids:
		var event: Dictionary = events.get(event_id, {})
		rare_data_ok = rare_data_ok and bool(event.get("rare", false)) and int(event.get("weight", 0)) == 1
	rare_data_ok = rare_data_ok and is_equal_approx(float(events.get("sovereign_ai", {}).get("customer_multipliers", {}).get("gpu_company", 0.0)), 5.0)
	rare_data_ok = rare_data_ok and is_equal_approx(float(events.get("compute_famine", {}).get("all_customer_multiplier", 0.0)), 1.8)
	_expect(rare_data_ok, "three authored low-weight rare market events stay in the replayable event pool")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["era"] = 2
	Game.state["player"]["network_level"] = 2
	Game.state["meta"]["customer_service_seconds"]["gpu_company"] = 43200.0
	var dc := _test_datacenter("dc_rare_lock", "dc_t1")
	dc["power_unit"] = "power_t2"
	dc["racks"][0] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var month_seconds := float(Game.data["economy"]["time"]["real_seconds_per_game_month"])
	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": 0.0, "end_at": month_seconds}]
	var flexible := Game.sign_contract(dc["id"], "gpu_company", "flexible")
	var flexible_rate := float(dc.get("locked_market_multiplier", 0.0))
	var standard := Game.sign_contract(dc["id"], "gpu_company", "standard")
	var standard_rate := float(dc.get("locked_market_multiplier", 0.0))
	var strategic_forecast := Game.contract_forecast(dc["id"], "gpu_company", "strategic")
	var strategic := Game.sign_contract(dc["id"], "gpu_company", "strategic")
	var strategic_rate := float(dc.get("locked_market_multiplier", 0.0))
	_expect(bool(flexible.get("ok", false)) and bool(standard.get("ok", false)) and is_equal_approx(flexible_rate, 7.0 / 3.0) and is_equal_approx(standard_rate, 10.0 / 6.0), "a one-month five-times event is integrated exactly across flexible and standard terms")
	_expect(bool(strategic.get("ok", false)) and is_equal_approx(strategic_rate, 16.0 / 12.0) and not bool(strategic_forecast.get("lock_cap_applied", true)), "the same one-month event is diluted across the full strategic term before the cap")
	Game.state["market"]["active"] = [
		{"event_id": "sovereign_ai", "started_at": 0.0, "end_at": month_seconds},
		{"event_id": "compute_famine", "started_at": 0.0, "end_at": month_seconds * 2.0},
	]
	var overlap := Game.contract_forecast(dc["id"], "gpu_company", "flexible")
	_expect(is_equal_approx(float(overlap.get("locked_market_multiplier", 0.0)), 11.8 / 3.0), "overlapping active events use every exact end-time cut point in the lock integral")
	Game.state["market"]["active"] = []
	Game.state["market"]["previews"] = [{"event_id": "sovereign_ai", "previewed_at": 0.0, "start_at": month_seconds}]
	var calm := Game.contract_forecast(dc["id"], "gpu_company", "standard")
	_expect(is_equal_approx(float(calm.get("locked_market_multiplier", 0.0)), 1.0) and is_zero_approx(float(calm.get("prorated_event_seconds", -1.0))), "no active event locks the era baseline and previews are never integrated")
	Game.state["market"]["previews"] = []
	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": 0.0, "end_at": month_seconds * 12.0}]
	var premium_capped := Game.contract_forecast(dc["id"], "gpu_company", "strategic", 1.35)
	_expect(is_equal_approx(float(premium_capped.get("uncapped_market_multiplier", 0.0)), 6.75) and is_equal_approx(float(premium_capped.get("locked_market_multiplier", 0.0)), 2.5), "inquiry premium is applied after proration and the strategic cap is applied last")
	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": 0.0, "end_at": month_seconds}]
	dc["contract_end_at"] = Game.simulation_time() + 1.0
	var renewal_report := Game.advance_time(1.0, false)
	var renewal_expected := (5.0 * (month_seconds - 1.0) + (month_seconds * 11.0 + 1.0)) / (month_seconds * 12.0)
	_expect(is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), renewal_expected) and renewal_report.get("contracts", []).size() == 1, "strategic automatic renewal uses the same exact prorated lock-rate path")
	dc["locked_market_multiplier"] = 5.0
	Game._ensure_state_shape()
	_expect(is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), 5.0), "loading a legacy strategic contract never retroactively clamps its saved lock rate")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["era"] = 3
	Game.state["player"]["network_level"] = 4
	Game.state["market"]["next_event_at"] = 0.0
	Game.state["market"]["rng_state"] = 934857
	var replay_baseline := Game.state.duplicate(true)
	for _index: int in range(12):
		Game._locked_rate_for("gpu_company", "flexible")
	Game.advance_time(month_seconds * 8.0, false)
	var sequence_after_quotes: Dictionary = Game.state["market"].duplicate(true)
	Game.state = replay_baseline.duplicate(true)
	Game._ensure_state_shape()
	Game.advance_time(month_seconds * 8.0, false)
	_expect(sequence_after_quotes == Game.state["market"], "prorated lock quotes consume no market RNG and preserve the same-seed event sequence exactly")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	dc = _test_datacenter("dc_set_bonus", "dc_t3")
	dc["power_unit"] = "power_t3"
	dc["coolers"] = {"north": "cool_liquid_t2", "south": "cool_liquid_t2", "east": "cool_liquid_t2", "west": "cool_liquid_t2"}
	dc["customer_id"] = "cloud"
	dc["locked_market_multiplier"] = 1.0
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var racks_table: Dictionary = Game.data["racks"]
	var attachments_table: Dictionary = Game.data["attachments"]
	var authored_set_multiplier := float(Game.data["economy"]["layout"]["set_bonus_multiplier"])
	for slot: int in [0, 1, 2]:
		dc["racks"][slot] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	var row_members := Rules.set_bonus_slots(dc, racks_table, attachments_table)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = 1.0
	var row_base_income := Game.datacenter_monthly_income(dc)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = authored_set_multiplier
	var row_set_income := Game.datacenter_monthly_income(dc)
	_expect(row_members[0] and row_members[1] and row_members[2] and row_members.count(true) == 3 and is_equal_approx(row_set_income, row_base_income * authored_set_multiplier), "a complete powered same-kind row grants every member exactly the authored ten-percent bonus")

func _run_inquiry_tests() -> void:
	var inquiry_system := Inquiry.new()
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 2
	Game.state["player"]["era"] = 2
	Game.state["player"]["network_level"] = 2
	var baseline: Dictionary = Game.state.duplicate(true)
	var with_inquiries: Dictionary = Game.state.duplicate(true)
	var baseline_market := Market.new()
	var inquiry_market := Market.new()
	for month: int in range(1, 13):
		baseline["clock"]["simulation_seconds"] = float(month) * 7200.0
		with_inquiries["clock"]["simulation_seconds"] = float(month) * 7200.0
		baseline_market.process_due(baseline, Game.data)
		inquiry_system.process(with_inquiries, Game.data)
		inquiry_market.process_due(with_inquiries, Game.data)
	_expect(JSON.stringify(baseline.get("market", {})) == JSON.stringify(with_inquiries.get("market", {})), "inquiry arrivals use an independent random stream and preserve the baseline market sequence element for element")

	var dc := _test_datacenter("dc_inquiry", "dc_t2")
	dc["power_unit"] = "power_t2"
	dc["coolers"] = {"north": "cool_air_t2"}
	dc["racks"][0] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	dc["racks"][1] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var kind_inquiry := {"id": "kind", "template_id": "mining_rush", "slot": 0, "arrived_at": 0.0}
	var kind_positive := inquiry_system.evaluate(kind_inquiry, dc, Game.state, Game.data)
	dc["racks"][1] = null
	var kind_negative := inquiry_system.evaluate(kind_inquiry, dc, Game.state, Game.data)
	_expect(bool(kind_positive.get("eligible", false)) and not bool(kind_negative.get("eligible", true)), "inquiry rack-kind and rack-count requirements have positive and negative evaluations")

	dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "active", "enabled": true}
	dc["racks"][2] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	var unique_inquiry := {"id": "unique", "template_id": "cloud_frame", "slot": 0, "arrived_at": 0.0}
	var unique_positive := inquiry_system.evaluate(unique_inquiry, dc, Game.state, Game.data)
	dc["racks"][2] = null
	var unique_negative := inquiry_system.evaluate(unique_inquiry, dc, Game.state, Game.data)
	_expect(bool(unique_positive.get("eligible", false)) and not bool(unique_negative.get("eligible", true)), "inquiry unique-rack-kind requirements have positive and negative evaluations")

	var network_inquiry := {"id": "network", "template_id": "edge_delivery", "slot": 0, "arrived_at": 0.0}
	var network_positive := inquiry_system.evaluate(network_inquiry, dc, Game.state, Game.data)
	Game.state["player"]["network_level"] = 1
	var network_negative := inquiry_system.evaluate(network_inquiry, dc, Game.state, Game.data)
	_expect(bool(network_positive.get("eligible", false)) and not bool(network_negative.get("eligible", true)), "inquiry network requirements have positive and negative evaluations")
	Game.state["player"]["network_level"] = 2

	var relationship_inquiry := {"id": "relationship", "template_id": "internet_anchor", "slot": 0, "arrived_at": 0.0}
	Game.state["meta"]["customer_service_seconds"]["internet"] = 172800.0
	var relationship_positive := inquiry_system.evaluate(relationship_inquiry, dc, Game.state, Game.data)
	Game.state["meta"]["customer_service_seconds"]["internet"] = 0.0
	var relationship_negative := inquiry_system.evaluate(relationship_inquiry, dc, Game.state, Game.data)
	_expect(bool(relationship_positive.get("eligible", false)) and not bool(relationship_negative.get("eligible", true)), "inquiry relationship requirements have positive and negative evaluations")

	var specialization_inquiry := {"id": "specialization", "template_id": "cloud_certification", "slot": 0, "arrived_at": 0.0}
	Game.state["meta"]["campus_specializations"]["0"] = "cloud"
	var specialization_positive := inquiry_system.evaluate(specialization_inquiry, dc, Game.state, Game.data)
	Game.state["meta"]["campus_specializations"]["0"] = "hosting"
	var specialization_negative := inquiry_system.evaluate(specialization_inquiry, dc, Game.state, Game.data)
	_expect(bool(specialization_positive.get("eligible", false)) and not bool(specialization_negative.get("eligible", true)), "inquiry specialization requirements reuse the live campus condition with positive and negative evaluations")

	Game.state["inquiries"]["open"] = [kind_inquiry]
	dc["racks"][1] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	dc["racks"][2] = null
	var quote := Game.inquiry_offer("kind", dc["id"])
	var cash_before := float(Game.state["player"]["cash"])
	var service_before := float(Game.state["meta"]["customer_service_seconds"]["mining"])
	var accepted := Game.accept_inquiry("kind", dc["id"], quote)
	_expect(bool(accepted.get("ok", false)) and is_equal_approx(float(Game.state["player"]["cash"]), cash_before + float(quote.get("bonus", 0.0))) and is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), float(quote.get("locked_market_multiplier", -1.0))) and is_equal_approx(float(accepted.get("projected", 0.0)), float(quote.get("projected", -1.0))) and is_equal_approx(float(Game.state["meta"]["customer_service_seconds"]["mining"]), service_before + 21600.0), "accepting an inquiry credits the displayed bonus, exact locked rate, forecast, and authored relationship service")
	_expect(dc.has("inquiry_contract_id") and dc.has("inquiry_template_id") and dc.has("inquiry_premium"), "an accepted inquiry records all three attribution fields on its contract")
	var manual_switch := Game.sign_contract(dc["id"], "internet", "standard")
	_expect(bool(manual_switch.get("ok", false)) and not dc.has("inquiry_contract_id") and not dc.has("inquiry_template_id") and not dc.has("inquiry_premium"), "a later manual contract switch clears every inquiry attribution field symmetrically")

	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": 0.0, "end_at": 1000000000.0}]
	for slot: int in range(4):
		dc["racks"][slot] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true}
	Game.state["inquiries"]["open"] = [{"id": "cap", "template_id": "gpu_surge", "slot": 0, "arrived_at": 0.0}]
	var capped_quote := Game.inquiry_offer("cap", dc["id"])
	_expect(bool(capped_quote.get("lock_cap_applied", false)) and is_equal_approx(float(capped_quote.get("locked_market_multiplier", 0.0)), 2.5), "strategic inquiry premium still obeys the disclosed 2.5-times lock cap")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 2
	var arrival := Game.advance_time(0.1, false)
	var first_open: Array = Game.state["inquiries"]["open"]
	var persistent_id := str(first_open[0].get("id", "")) if not first_open.is_empty() else ""
	Game.advance_time(400.0 * 7200.0, false)
	var still_present := false
	for item: Dictionary in Game.state["inquiries"]["open"]:
		still_present = still_present or str(item.get("id", "")) == persistent_id
	_expect(arrival.get("inquiries", []).size() == 1 and still_present, "an inquiry arrives after the gate and remains open after four hundred game months with no expiration field or countdown")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 2
	Game.advance_time(0.1, false)
	var declined_id := str(Game.state["inquiries"]["open"][0].get("id", ""))
	var declined := Game.decline_inquiry(declined_id)
	Game.advance_time(2.0 * 7200.0 - 1.0, false)
	var before_refill: int = Game.state["inquiries"]["open"].size()
	Game.advance_time(2.0, false)
	_expect(bool(declined.get("ok", false)) and before_refill == 0 and Game.state["inquiries"]["open"].size() == 1, "declining has no penalty, cannot refill that slot inside two game months, and refills after the cooldown")

	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 2
	Game.advance_time(0.1, false)
	Game.state["inquiries"]["open"].clear()
	var next_arrival := float(Game.state["inquiries"].get("next_arrival_at", INF))
	var offline_report := Game.advance_time(next_arrival - Game.simulation_time() + 1.0, true)
	_expect(offline_report.get("inquiries", []).size() == 1 and Game.state["inquiries"]["open"].size() == 1, "offline advancement segments at next_arrival_at and records the crossed inquiry arrival as a milestone")


func _run_remaining_set_bonus_tests() -> void:
	Game.reset_for_tests()
	var dc := _test_datacenter("dc_set_bonus_remaining", "dc_t3")
	dc["power_unit"] = "power_t3"
	dc["coolers"] = {"north": "cool_liquid_t2", "south": "cool_liquid_t2", "east": "cool_liquid_t2", "west": "cool_liquid_t2"}
	dc["customer_id"] = "cloud"
	dc["locked_market_multiplier"] = 1.0
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var racks_table: Dictionary = Game.data["racks"]
	var attachments_table: Dictionary = Game.data["attachments"]
	var authored_set_multiplier := float(Game.data["economy"]["layout"]["set_bonus_multiplier"])
	dc["racks"].fill(null)
	for slot: int in [0, 3, 6]:
		dc["racks"][slot] = {"rack_id": "rack_storage_t1", "status": "active", "enabled": true}
	var column_members := Rules.set_bonus_slots(dc, racks_table, attachments_table)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = 1.0
	var column_base_income := Game.datacenter_monthly_income(dc)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = authored_set_multiplier
	var column_set_income := Game.datacenter_monthly_income(dc)
	_expect(column_members[0] and column_members[3] and column_members[6] and column_members.count(true) == 3 and is_equal_approx(column_set_income, column_base_income * authored_set_multiplier), "a complete powered same-kind column grants every member exactly the authored ten-percent bonus")

	dc["racks"].fill(null)
	for slot: int in [0, 1, 2, 3, 6]:
		dc["racks"][slot] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	var cross_members := Rules.set_bonus_slots(dc, racks_table, attachments_table)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = 1.0
	var cross_base_income := Game.datacenter_monthly_income(dc)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = authored_set_multiplier
	var cross_set_income := Game.datacenter_monthly_income(dc)
	_expect(cross_members.count(true) == 5 and is_equal_approx(cross_set_income, cross_base_income * authored_set_multiplier), "an intersecting row and column mark their union but never stack the center rack bonus")

	dc["racks"][2] = null
	_expect(Rules.set_bonus_slots(dc, racks_table, attachments_table).count(true) == 3, "removing one row member immediately removes only that row bonus while preserving an independent column")
	dc["racks"][2] = {"rack_id": "rack_compute_t1", "status": "installing", "enabled": true}
	_expect(Rules.set_bonus_slots(dc, racks_table, attachments_table).count(true) == 3, "an installing rack breaks its line without disturbing another complete line")
	dc["racks"][2] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": false}
	_expect(Rules.set_bonus_slots(dc, racks_table, attachments_table).count(true) == 3, "a paused rack breaks its line without disturbing another complete line")
	dc["power_unit"] = ""
	_expect(Rules.set_bonus_slots(dc, racks_table, attachments_table).count(true) == 0, "unpowered racks cannot form a set")
	dc["power_unit"] = "power_t3"
	dc["racks"][2] = {"rack_id": "rack_compute_t1", "status": "faulted", "enabled": true}
	cross_members = Rules.set_bonus_slots(dc, racks_table, attachments_table)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = 1.0
	var faulted_base_income := Game.datacenter_monthly_income(dc)
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = authored_set_multiplier
	var faulted_set_income := Game.datacenter_monthly_income(dc)
	_expect(cross_members.count(true) == 5 and is_equal_approx(faulted_set_income, faulted_base_income * authored_set_multiplier), "a faulted rack keeps set membership and applies degradation before the single set multiplier")
	Game.data["economy"]["layout"]["set_bonus_multiplier"] = authored_set_multiplier

func _test_datacenter(id: String, building_id: String) -> Dictionary:
	var racks: Array = []
	racks.resize(9)
	racks.fill(null)
	return {"id": id, "building_id": building_id, "status": "operational", "built_at": Game.simulation_time(), "power_unit": "", "coolers": {}, "racks": racks, "customer_id": "", "contract_end_at": 0.0, "free_switch_available": false, "aging_notices": []}

func _run_fault_softening_tests() -> void:
	Game.reset_for_tests()
	var dc := _test_datacenter("dc_fault_soft", "dc_t1")
	dc["power_unit"] = "power_t1"
	dc["coolers"] = {"north": "cool_air_t1"}
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true, "fault_at": Game.simulation_time() + 1.0}
	dc["customer_id"] = "internet"
	dc["locked_market_multiplier"] = Game.contract_market_multiplier("internet")
	dc["contract_end_at"] = Game.simulation_time() + 43200.0
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var normal_income := Game.datacenter_monthly_income(dc)
	Game.advance_time(1.0, false)
	var installed: Dictionary = dc["racks"][0]
	var auto_at := float(installed.get("auto_repair_at", 0.0))
	var faulted_income := Game.datacenter_monthly_income(dc)
	_expect(installed.get("status", "") == "faulted" and is_equal_approx(auto_at, Game.simulation_time() + 14400.0), "a new fault schedules its free repair exactly four hours later")
	_expect(is_equal_approx(faulted_income, normal_income * 0.4), "a faulted rack keeps forty percent of its normal income")
	Game.advance_time(14399.0, false)
	_expect(installed.get("status", "") == "faulted", "a fault remains softly degraded until its four-hour repair point")
	Game.advance_time(1.0, false)
	_expect(installed.get("status", "") == "active" and not installed.has("auto_repair_at") and int(Game.state["stats"].get("faults_repaired_auto", 0)) == 1 and int(Game.state["stats"].get("faults_repaired_manual", 0)) == 0, "an unattended fault repairs for free and records a separate automatic statistic")
	installed["status"] = "faulted"
	installed["auto_repair_at"] = Game.simulation_time() + 14400.0
	_expect(Game.instant_repair_with_gems(dc["id"], 0).get("ok", false) and not installed.has("auto_repair_at") and int(Game.state["stats"].get("faults_repaired_manual", 0)) == 1, "player-accelerated repair clears the automatic timer and records a manual statistic")

	Game.reset_for_tests()
	dc = _test_datacenter("dc_fault_offline", "dc_t1")
	dc["power_unit"] = "power_t1"
	dc["coolers"] = {"north": "cool_air_t1"}
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "faulted", "enabled": true, "fault_at": -1.0, "auto_repair_at": 14400.0}
	dc["customer_id"] = "internet"
	dc["locked_market_multiplier"] = Game.contract_market_multiplier("internet")
	dc["contract_end_at"] = 43200.0
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var active_probe := dc.duplicate(true)
	active_probe["racks"][0]["status"] = "active"
	active_probe["racks"][0].erase("auto_repair_at")
	normal_income = Game.datacenter_monthly_income(active_probe)
	var original_fault_rate := float(Game.data["economy"]["faults"].get("base_rate_per_game_month", 0.15))
	Game.data["economy"]["faults"]["base_rate_per_game_month"] = 0.000000001
	var offline_report := Game.advance_time(18000.0, true)
	Game.data["economy"]["faults"]["base_rate_per_game_month"] = original_fault_rate
	var expected_income := normal_income * (14400.0 * 0.4 + 3600.0) / 7200.0
	_expect(is_equal_approx(float(offline_report.get("income", 0.0)), expected_income) and dc["racks"][0].get("status", "") == "active", "offline settlement splits income at auto-repair: forty percent before and full income after")
	Game.state["stats"].erase("faults_repaired_manual")
	Game.state["stats"].erase("faults_repaired_auto")
	Game.state["stats"]["faults_repaired"] = 7
	Game._ensure_state_shape()
	_expect(int(Game.state["stats"].get("faults_repaired_manual", 0)) == 7 and int(Game.state["stats"].get("faults_repaired_auto", 0)) == 0 and not Game.state["stats"].has("faults_repaired"), "legacy repair totals migrate into the manual statistic without counting future automatic repairs")

func _run_wp4_decision_ui_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	var dc := _test_datacenter("dc_wp4_contract", "dc_t1")
	dc["power_unit"] = "power_t2"
	dc["coolers"] = {"north": "cool_air_t2"}
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "active", "enabled": true}
	dc["customer_id"] = "internet"
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	var projected := float(main.call("_projected_datacenter_income", dc, "mining"))
	var simulated := dc.duplicate(true)
	simulated["customer_id"] = "mining"
	simulated["locked_market_multiplier"] = Game.contract_market_multiplier("mining")
	var authoritative := Rules.datacenter_income_per_month(simulated, Game.state, Game.data, func(customer_id: String) -> float: return Game.market_multiplier(customer_id))
	_expect(is_equal_approx(projected, authoritative), "contract card projection matches the authoritative post-signing income rule")
	var route_unlocks: Array = main.call("_era_unlock_items", 2)
	_expect(route_unlocks.size() >= 4, "era route exposes at least four concrete next-era unlocks")
	var projection: Dictionary = main.call("_prestige_projection")
	_expect(float(projection.get("projected", 0.0)) > float(projection.get("current", 0.0)), "prestige card projects a positive permanent brand gain")
	main.call("_on_market_event_started", "shopping_festival")
	await get_tree().process_frame
	var notice := main.find_child("WorldNews", true, false) as PanelContainer
	var switcher := main.find_child("CampusSwitcher", true, false) as PanelContainer
	var legacy_banner := main.find_child("MarketEventBanner", true, false)
	var safe_band_gap := notice != null and switcher != null and not notice.get_global_rect().intersects(switcher.get_global_rect())
	var notice_contract := notice != null and notice.visible and str(notice.get_meta("destination", "")) == "market" and bool(notice.get_meta("transient_market_notice", false)) and not notice.gui_input.get_connections().is_empty() and legacy_banner == null and safe_band_gap
	_expect(notice_contract, "market transitions merge into one actionable safe-band notice visible=%s destination=%s transient=%s connections=%d legacy=%s notice=%s switcher=%s" % [str(notice.visible if notice != null else false), str(notice.get_meta("destination", "") if notice != null else "missing"), str(notice.get_meta("transient_market_notice", false) if notice != null else false), notice.gui_input.get_connections().size() if notice != null else 0, str(legacy_banner), str(notice.get_global_rect() if notice != null else Rect2()), str(switcher.get_global_rect() if switcher != null else Rect2())])
	main.queue_free()
	await get_tree().process_frame

func _run_contract_capacity_ui_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["era"] = 1.0
	Game.state["player"]["network_level"] = 1.0
	var dc := _test_datacenter("dc_empty_contract", "dc_t1")
	dc["power_unit"] = "power_t1"
	Game.state["plots"][0]["datacenter"] = dc
	Game.state["plots"][0]["status"] = "operational"
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_open_datacenter_detail", dc["id"], "contracts")
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var guide := main.find_child("ContractCapacityGuide", true, false) as PanelContainer
	var message := main.find_child("ContractCapacityMessage", true, false) as Label
	var rate := main.find_child("MarketRate_internet", true, false) as Label
	var projection := main.find_child("ContractProjection_internet", true, false) as Label
	var configure := main.find_child("ContractConfigureRacks", true, false) as Button
	var contract_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
	var contract_cards := main.find_children("Contract_*", "Button", true, false)
	var contract_scroll_range := contract_scroll.get_v_scroll_bar() if contract_scroll != null else null
	var touch_scroll_contract := contract_scroll != null and contract_scroll_range != null and contract_scroll_range.max_value > contract_scroll_range.page and int(contract_scroll.scroll_deadzone) == 12 and bool(contract_scroll.get_meta("touch_scroll_enabled", false)) and not contract_cards.is_empty()
	for contract_card_node: Node in contract_cards:
		var contract_card := contract_card_node as Button
		touch_scroll_contract = touch_scroll_contract and contract_card.mouse_filter == Control.MOUSE_FILTER_PASS and contract_card.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE and bool(contract_card.get_meta("scroll_drag_passthrough", false))
	_expect(guide != null and str(guide.get_meta("capacity_state", "")) == "empty" and message != null and configure != null, "an empty data center explains that racks are the sellable capacity and exposes a direct configuration action")
	_expect(rate != null and not rate.text.contains("×0.00") and projection != null and projection.text == tr("CONTRACT_PROJECTED_AFTER_RACK"), "the empty contract page keeps a valid market quote and replaces misleading zero revenue with the rack prerequisite")
	_expect(touch_scroll_contract, "contract customer cards pass iOS drags to their touch-scroll page while remaining release-to-select actions")
	main.call("_sign_contract", dc["id"], "internet")
	await get_tree().process_frame
	var feedback := main.get("toast_label") as Label
	var action_sheet := main.find_child("ActionSheetOverlay", true, false)
	_expect(str(dc.get("customer_id", "")).is_empty() and action_sheet == null and feedback != null and feedback.text == tr("REASON_CONTRACT_CAPACITY_REQUIRED"), "tapping a contract without online racks returns a friendly earning-path explanation instead of a zero-income confirmation")
	if configure != null:
		configure.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(str(main.get("active_page")) == "detail" and str(main.get("_detail_focus")) == "board", "the contract capacity action routes directly to rack configuration")
	main.queue_free()
	await get_tree().process_frame

func _run_wp6_presentation_tests() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_navigate", "store")
	main.call("_refresh")
	await get_tree().process_frame
	_expect(main.find_children("StoreSection_*", "", true, false).size() == 3 and main.find_child("StoreCompliance", true, false) != null, "store presents deals gems perks and compliance as distinct merchandising regions")
	main.call("_navigate", "settings")
	main.call("_refresh")
	await get_tree().process_frame
	var settings_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
	var settings_buttons := settings_scroll.find_children("*", "Button", true, false) if settings_scroll != null else []
	var settings_full_surface := settings_scroll != null and bool(settings_scroll.get_meta("full_surface_touch_scroll", false)) and int(settings_scroll.scroll_deadzone) == 12 and not settings_buttons.is_empty()
	for settings_button_node: Node in settings_buttons:
		var settings_action := settings_button_node as BaseButton
		settings_full_surface = settings_full_surface and settings_action.mouse_filter == Control.MOUSE_FILTER_PASS and settings_action.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE and bool(settings_action.get_meta("scroll_drag_passthrough", false))
	_expect(main.find_child("SettingsCompliance", true, false) != null and main.find_child("SettingsVersion", true, false) != null, "settings exposes legal support and build information")
	_expect(settings_full_surface, "settings distinguishes release taps from full-content iOS drags")
	var music_toggle := main.find_child("SettingsToggle_music_enabled", true, false) as Button
	var touch_gesture_ok := settings_scroll != null and music_toggle != null
	var initial_music := bool(Game.state.get("settings", {}).get("music_enabled", true))
	if touch_gesture_ok:
		var settings_content := settings_scroll.get_child(0) as Control
		settings_content.custom_minimum_size.y = maxf(settings_content.get_combined_minimum_size().y, settings_scroll.size.y + 640.0)
		await get_tree().process_frame
		await get_tree().process_frame
		settings_scroll.scroll_vertical = 0
		await get_tree().process_frame
		var start := music_toggle.get_global_rect().get_center()
		# First prove that a stationary release still performs the button action.
		for pressed: bool in [true, false]:
			var tap := InputEventScreenTouch.new()
			tap.index = 8
			tap.position = start
			tap.pressed = pressed
			get_viewport().push_input(tap, true)
			await get_tree().process_frame
		touch_gesture_ok = bool(Game.state.get("settings", {}).get("music_enabled", true)) != initial_music
		Game.set_audio_setting("music_enabled", initial_music)
		music_toggle.set_pressed_no_signal(initial_music)
		# Then begin from the same interactive control and cross the scroll
		# deadzone. The page must move while the setting stays unchanged.
		var press := InputEventScreenTouch.new()
		press.index = 7
		press.position = start
		press.pressed = true
		get_viewport().push_input(press, true)
		await get_tree().process_frame
		for distance: float in [48.0, 96.0, 144.0]:
			var drag := InputEventScreenDrag.new()
			drag.index = 7
			drag.position = start - Vector2(0, distance)
			drag.relative = Vector2(0, -48)
			drag.velocity = Vector2(0, -600)
			get_viewport().push_input(drag, true)
			await get_tree().process_frame
		var release := InputEventScreenTouch.new()
		release.index = 7
		release.position = start - Vector2(0, 144)
		release.pressed = false
		get_viewport().push_input(release, true)
		await get_tree().process_frame
		touch_gesture_ok = touch_gesture_ok and settings_scroll.scroll_vertical >= 96 and bool(Game.state.get("settings", {}).get("music_enabled", true)) == initial_music
		Game.set_audio_setting("music_enabled", initial_music)
	_expect(touch_gesture_ok, "dragging from a settings toggle scrolls without toggling, while a stationary tap still toggles")
	main.call("_show_offline_dialog", {"elapsed_seconds": 7200.0, "income": 5000.0, "completed": [{}], "faults": [{}], "events": [{}], "aging": [{}], "contracts": []})
	await get_tree().process_frame
	_expect(main.find_child("OfflineRewardCard", true, false) != null and main.find_child("OfflineDoubleButton", true, false) != null, "offline settlement has a dedicated animated reward card and ad-styled ×2 action")
	var offline := main.find_child("OfflineOverlay", true, false)
	if offline != null:
		offline.queue_free()
	Game.state["bankruptcy"] = {"status": "arrears", "debt": 250.0, "arrears_online_seconds": 120.0, "rescue_uses": 0, "rescue_day": -1}
	main.call("_on_bankruptcy_state_changed", "arrears")
	await get_tree().process_frame
	var arrears_close := main.find_child("ArrearsCloseButton", true, false) as Button
	_expect(main.find_child("ArrearsBanner", true, false) != null and main.find_child("ArrearsVignette", true, false) != null and main.find_child("ArrearsProgress", true, false) != null and arrears_close != null and arrears_close.custom_minimum_size.x >= ThemeMaker.TOUCH_MIN, "arrears opens as a timed HUD crisis with an explicit phone-sized close route")
	if arrears_close != null:
		arrears_close.emit_signal("pressed")
	await get_tree().process_frame
	main.call("_refresh_arrears_hud")
	await get_tree().process_frame
	_expect(main.find_child("ArrearsBanner", true, false) == null and bool(main.get("_arrears_banner_dismissed")), "dismissed arrears HUD stays collapsed for the current debt episode instead of rebuilding over management")
	# Reopen a new episode, then reproduce the TestFlight report exactly: a
	# maxed-out daily rescue must explain the limit and get out of the way.
	Game.state["reward_limits"]["rescue_day"] = int(GameClock.wall_time() / 86400)
	Game.state["reward_limits"]["rescue_uses"] = int(DataRepository.get_table("economy").get("bankruptcy", {}).get("rescue_uses_per_real_day", 3))
	main.call("_on_bankruptcy_state_changed", "arrears")
	await get_tree().process_frame
	var maxed_rescue := main.find_child("ArrearsRescueButton", true, false) as Button
	var maxed_rescue_route_present := maxed_rescue != null
	if maxed_rescue != null:
		maxed_rescue.emit_signal("pressed")
	await get_tree().process_frame
	var limit_feedback := main.get("toast_label") as Label
	_expect(maxed_rescue_route_present and main.find_child("ArrearsBanner", true, false) == null and limit_feedback != null and limit_feedback.text == tr("REASON_REWARD_LIMIT"), "a maxed emergency-fund claim gives a clear limit message and automatically collapses the blocking crisis card")
	Game.state["bankruptcy"]["status"] = "normal"
	main.call("_on_bankruptcy_state_changed", "normal")
	main.call("_show_era_overlay", 2, DataRepository.get_entry("eras", "2"))
	await get_tree().process_frame
	var unlock_summary := main.find_child("EraUnlockSummary", true, false)
	_expect(main.find_child("EraNewspaper", true, false) != null and unlock_summary != null and unlock_summary.get_child_count() == 3, "era unlock is staged as a newspaper milestone with three concrete unlocks")
	main.queue_free()
	await get_tree().process_frame

func _run_initial_state_test() -> void:
	Game.reset_for_tests()
	_expect(is_equal_approx(float(Game.state["player"]["cash"]), 40000.0), "new company starts with tuned cash")
	_expect(int(Game.state["player"]["gems"]) == 20, "new company starts with documented gems")
	_expect(Game.state["plots"].size() == 1 and is_equal_approx(Game.next_plot_price(), 965.0), "new company starts with one free plot and the bounded second-plot price")

func _run_core_loop_test() -> void:
	Game.reset_for_tests()
	var result := Game.start_datacenter_construction("plot_1", "dc_t0")
	_expect(bool(result.get("ok", false)), "container construction starts")
	Game.advance_time(300.0, false)
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	_expect(not dc.is_empty() and dc.get("status", "") == "operational", "container construction completes")
	_expect(Game.state["player"]["total_datacenters_built"] == 1, "build count increments")
	_expect(Game.install_power(dc["id"], "power_t1").get("ok", false), "power install starts")
	_expect(Game.install_cooler(dc["id"], "north", "cool_air_t1").get("ok", false), "cooler install starts")
	Game.advance_time(300.0, false)
	var rack_one: Dictionary = Game.install_rack(dc["id"], 0, "rack_compute_t1")
	var rack_two: Dictionary = Game.install_rack(dc["id"], 1, "rack_compute_t1")
	_expect(rack_one.get("ok", false), "first rack install starts")
	_expect(rack_two.get("ok", false), "second rack install starts")
	Game.advance_time(120.0, false)
	_expect(Game.sign_contract(dc["id"], "internet").get("ok", false), "internet contract signs")
	_expect(is_equal_approx(Game.datacenter_monthly_income(dc), 216.0 * float(dc.get("locked_market_multiplier", 0.0))), "two cooled compute racks earn documented locked-price income")
	_expect(Game.contract_switch_fee(dc["id"], "mining") >= 25.0, "contract switch exposes the breach fee before confirmation")
	var runtime: Dictionary = Rules.rack_runtime_status(dc, 0, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_expect(bool(runtime.get("powered", false)) and not bool(runtime.get("overheated", true)), "north cooler covers north rack")
	var cash_before := float(Game.state["player"]["cash"])
	Game.advance_time(7200.0, false)
	_expect(float(Game.state["player"]["total_revenue"]) > 200.0, "one month accrues contract revenue")
	_expect(float(Game.state["player"]["cash"]) < cash_before + 216.1, "maintenance is deducted at month boundary")

func _run_datacenter_board_tests() -> void:
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	dc["building_id"] = "dc_t2"
	dc["power_unit"] = "power_t2"
	dc["coolers"] = {"north": "cool_air_t2", "west": "cool_air_t2"}
	var empty_racks: Array = []
	empty_racks.resize(9)
	empty_racks.fill(null)
	dc["racks"] = empty_racks
	Game.state["player"]["era"] = 2
	var board := DatacenterBoard.new()
	board.setup(str(dc.get("id", "")))
	add_child(board)
	await get_tree().process_frame
	var corner := board.placement_state_for_slot(0, "rack_gpu_t1")
	var center := board.placement_state_for_slot(4, "rack_gpu_t1")
	_expect(str(corner.get("state", "")) == "ok" and str(center.get("state", "")) == "heat", "board preview makes double-cooled corner placement visibly safer than center placement")
	_expect(board.find_children("CoolingCoverage_*", "", true, false).size() == 6 and board.find_child("BoardPowerMeter", true, false) != null, "board renders three coverage tiles per cooler and a power meter")
	board.set_placement_preview(4, "rack_gpu_t1")
	await get_tree().process_frame
	_expect(board.find_children("PlacementState", "", true, false).size() == 9, "board placement preview classifies all nine slots")
	# The dedicated footprint slot prevents Control's visual-only scale from
	# shifting the authored board off center. It is the one permitted structural
	# node above the original sixty-node rendering budget.
	_expect(_node_tree_size(board) <= 61, "board stays within its sixty-one-node mobile budget")
	board.queue_free()
	await get_tree().process_frame

func _node_tree_size(root: Node) -> int:
	var result := 1
	for child: Node in root.get_children():
		result += _node_tree_size(child)
	return result

func _run_construction_controls_test() -> void:
	Game.reset_for_tests()
	var started := Game.start_datacenter_construction("plot_1", "dc_t0")
	var construction_id := str(started.get("construction", {}).get("id", ""))
	Game.state["inventory"]["instant_build_tickets"] = 1
	_expect(Game.use_instant_build_ticket(construction_id).get("ok", false), "instant build ticket completes a project")
	_expect(Game.state["construction_queue"].is_empty() and Game.state["inventory"]["instant_build_tickets"] == 0, "instant build ticket is consumed exactly once")
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	_expect(Game.install_power(dc["id"], "power_t2").get("ok", false), "higher-tier power unit install starts")
	Game.advance_time(4000.0, false)
	var downgrade := Game.install_power(dc["id"], "power_t1")
	_expect(not bool(downgrade.get("ok", true)) and downgrade.get("reason", "") == "not_an_upgrade", "installed attachments cannot be downgraded")
	Game.reset_for_tests()
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(300.0, false)
	dc = Game.state["plots"][0]["datacenter"]
	_expect(Game.install_power(dc["id"], "power_t1").get("ok", false), "first power project starts")
	var duplicate_power := Game.install_power(dc["id"], "power_t2")
	_expect(not bool(duplicate_power.get("ok", true)) and duplicate_power.get("reason", "") == "construction_in_progress", "same attachment slot rejects concurrent projects")
	Game.reset_for_tests()
	_expect(Game.upgrade_network().get("ok", false), "network project starts")
	var duplicate_network := Game.upgrade_network()
	_expect(not bool(duplicate_network.get("ok", true)) and duplicate_network.get("reason", "") == "construction_in_progress", "network upgrade rejects duplicate queue entries")
	Game.reset_for_tests()
	var queue_job := Game.start_datacenter_construction("plot_1", "dc_t0")
	var job: Dictionary = queue_job.get("construction", {})
	job["ad_uses"] = int(DataRepository.get_table("economy").get("construction", {}).get("max_ads_per_project", 2))
	var reward_attempt := Game.request_reward("construction:%s" % job.get("id", ""))
	_expect(not bool(reward_attempt.get("ok", true)) and reward_attempt.get("reason", "") == "reward_limit", "construction reward frequency limit is enforced")

func _run_construction_bays_tests() -> void:
	Game.reset_for_tests()
	Game.state["player"]["cash"] = 20000000.0
	_expect(not bool(Game.purchase_construction_bays().get("ok", true)), "engineering expansion level 2 stays locked before Era 2")
	Game.state["player"]["era"] = 2
	var level_two := Game.purchase_construction_bays()
	_expect(bool(level_two.get("ok", false)) and Game.queue_capacity() == 3, "engineering expansion level 2 raises the global build queue from two to three")
	for index: int in range(2, 5):
		Game.state["plots"].append({"id": "bay_plot_%d" % index, "index": index, "purchase_price": 0.0, "purchased": true, "status": "empty", "datacenter": null})
	var first := Game.start_datacenter_construction("plot_1", "dc_t1")
	var second := Game.start_datacenter_construction("bay_plot_2", "dc_t1")
	var third := Game.start_datacenter_construction("bay_plot_3", "dc_t1")
	var fourth := Game.start_datacenter_construction("bay_plot_4", "dc_t1")
	_expect(bool(first.get("ok", false)) and bool(second.get("ok", false)) and bool(third.get("ok", false)) and Game.state["construction_queue"].size() == 3, "a level-2 engineering department admits three simultaneous projects")
	_expect(not bool(fourth.get("ok", true)) and fourth.get("reason", "") == "queue_full", "the fourth project is explicitly rejected while capacity is three")

	Game.state["construction_queue"] = []
	_expect(not bool(Game.purchase_construction_bays().get("ok", true)), "engineering expansion level 3 stays locked before Era 3")
	Game.state["player"]["era"] = 3
	_expect(bool(Game.purchase_construction_bays().get("ok", false)) and Game.queue_capacity() == 4, "Era 3 unlocks the four-lane engineering department")
	_expect(not bool(Game.purchase_construction_bays().get("ok", true)), "the five-lane engineering department requires a completed company rebuild")
	_expect(Game.is_unlocked(DataRepository.get_entry("buildings", "dc_t1")), "minimum_prestige checks do not change unlock behavior for existing items without that field")
	Game.state["stats"]["prestige_count"] = 1
	_expect(bool(Game.purchase_construction_bays().get("ok", false)) and Game.queue_capacity() == 5, "one completed rebuild unlocks the five-lane engineering department")

	Game.state["player"]["total_datacenters_built"] = 20
	var rebuilt := Game.prestige()
	_expect(bool(rebuilt.get("ok", false)) and Game.queue_capacity() == 2 and int(Game.state["technology"].get("construction_bays", 0)) == 1, "company rebuild resets engineering capacity to the authored two-lane base")
	_expect(bool(Game.purchase_construction_bays().get("ok", false)) and Game.queue_capacity() == 3, "a rebuilt company can buy engineering expansion again with its carried cash")

func _run_commerce_test() -> void:
	Game.reset_for_tests()
	var gems_before := int(Game.state["player"]["gems"])
	Game._on_purchase_result("gems_s", true, "purchase", "test-transaction-1")
	Game._on_purchase_result("gems_s", true, "purchase", "test-transaction-1")
	_expect(int(Game.state["player"]["gems"]) == gems_before + 200, "duplicate StoreKit transaction grants a consumable once")
	Game.state["player"]["era"] = 2
	Game._on_purchase_result("pack_starter", true, "purchase", "test-transaction-2")
	var limited := Game.can_purchase_product("pack_starter")
	_expect(not bool(limited.get("ok", true)) and limited.get("reason", "") == "purchase_limit", "limited pack cannot be purchased twice")
	Game.reset_for_tests()
	Game.state["entitlements"]["noads"] = true
	Game.last_offline_report = {"income": 100.0, "doubled": false}
	var cash_before := float(Game.state["player"]["cash"])
	_expect(Game.request_reward("offline_double").get("ok", false), "No Ads entitlement activates rewarded action without video")
	_expect(is_equal_approx(float(Game.state["player"]["cash"]), cash_before + 100.0) and bool(Game.last_offline_report["doubled"]), "offline reward is granted exactly once")

func _run_offline_test() -> void:
	Game.reset_for_tests()
	var report := Game.advance_time(36000.0, true)
	_expect(is_equal_approx(float(report["credited_seconds"]), 28800.0), "base offline income is capped at eight hours")
	_expect(is_equal_approx(Game.simulation_time(), 36000.0), "offline state advances beyond income cap")
	_expect(Game.state["bankruptcy"]["status"] == "normal", "offline progression never starts bankruptcy without costs")

func _run_long_offline_test() -> void:
	Game.reset_for_tests()
	var seconds := 90.0 * 86400.0
	var report := Game.advance_time(seconds, true)
	_expect(is_equal_approx(float(report["credited_seconds"]), 28800.0), "ninety-day absence still respects eight-hour income cap")
	_expect(is_equal_approx(Game.simulation_time(), seconds), "ninety-day state fast-forward completes without truncation")
	var history: Dictionary = Game.state.get("market", {}).get("history", {})
	var bounded := true
	for customer_id: String in history:
		bounded = bounded and history[customer_id].size() == 730
	_expect(bounded and history.size() == 4, "long-run market history fills and stays within two-year ring buffer")

func _run_aging_test() -> void:
	Game.reset_for_tests()
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(300.0, false)
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	Game.advance_time(90000.0, true)
	_expect(dc.get("status", "") == "operational" and bool(dc.get("offline_expired", false)), "offline expiry freezes before forced ruin")
	Game.advance_time(100.0, false)
	_expect(dc.get("status", "") == "ruined", "expired data center becomes ruin online")
	dc["power_unit"] = "power_t1"
	dc["coolers"] = {"north": "cool_air_t1"}
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	_expect(not bool(Game.retire_datacenter(dc["id"]).get("ok", true)), "ruin cannot be retired for salvage value")
	_expect(not bool(Game.uninstall_rack(dc["id"], 0).get("ok", true)), "rack cannot be salvaged from a ruin")
	var scrap := Rules.ruin_scrap_value(dc, Game.data)
	var cash_before_scrap := float(Game.state["player"]["cash"])
	var cleared := Game.demolish_ruin(dc["id"])
	_expect(bool(cleared.get("ok", false)) and is_equal_approx(float(cleared.get("refund", 0.0)), scrap) and is_equal_approx(float(Game.state["player"]["cash"]), cash_before_scrap + scrap), "clearing a ruin is free and deposits building attachment and rack scrap")

	Game.reset_for_tests()
	var lifespan := float(DataRepository.get_entry("buildings", "dc_t1").get("lifespan_seconds", 432000.0))
	var harvest_dc := _test_datacenter("dc_harvest", "dc_t1")
	harvest_dc["built_at"] = Game.simulation_time() - lifespan * 0.94
	harvest_dc["power_unit"] = "power_t1"
	harvest_dc["coolers"] = {"north": "cool_air_t1"}
	harvest_dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	var harvest_value := Rules.retirement_value(harvest_dc, Game.simulation_time(), Game.data)
	var late_scrap := Rules.ruin_scrap_value(harvest_dc, Game.data)
	_expect(harvest_value > late_scrap, "normal retirement at ninety-four percent always pays strictly more than waiting for scrap")

	Game.state["player"]["era"] = 2
	Game.state["player"]["cash"] = 40000.0
	_expect(Game.purchase_auto_retirement().get("ok", false) and bool(Game.state["technology"].get("auto_retirement", false)), "Era 2 can purchase the single auto-retirement technology for fifteen thousand")
	harvest_dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "installing", "enabled": true, "cost": 321.0, "install_complete_at": Game.simulation_time() + 10000.0}
	Game.state["plots"][0]["datacenter"] = harvest_dc
	Game.state["plots"][0]["status"] = "operational"
	Game.state["construction_queue"] = [{"id": "job_auto_retire", "type": "cooler", "datacenter_id": harvest_dc["id"], "attachment_id": "cool_air_t2", "cost": 777.0, "started_at": Game.simulation_time(), "complete_at": Game.simulation_time() + 10000.0}]
	var retirement_probe := harvest_dc.duplicate(true)
	retirement_probe["racks"][1] = null
	var auto_at := Game.simulation_time() + lifespan * 0.01
	var expected_harvest := Rules.retirement_value(retirement_probe, auto_at, Game.data)
	var cash_before_auto := float(Game.state["player"]["cash"])
	var auto_report := Game.advance_time(5000.0, true)
	var auto_entry: Dictionary = {}
	for aging_entry: Dictionary in auto_report.get("aging", []):
		if aging_entry.get("type", "") == "datacenter_auto_retired":
			auto_entry = aging_entry
			break
	_expect(Game.state["plots"][0].get("datacenter") == null and Game.state["construction_queue"].is_empty() and is_equal_approx(float(Game.state["player"]["cash"]), cash_before_auto + expected_harvest + 1098.0), "offline auto-retirement at ninety-five percent harvests recovery and fully refunds pending jobs")
	_expect(auto_entry.get("type", "") == "datacenter_auto_retired" and is_equal_approx(float(auto_entry.get("refund", 0.0)), expected_harvest) and is_equal_approx(float(auto_entry.get("job_refund", 0.0)), 1098.0), "offline auto-retirement is recorded as a recovery event in the return report")

func _run_bankruptcy_test() -> void:
	Game.reset_for_tests()
	var oldest := _test_datacenter("dc_oldest", "dc_t1")
	oldest["built_at"] = -1000.0
	var newer := _test_datacenter("dc_newer", "dc_t1")
	newer["built_at"] = -100.0
	Game.state["plots"][0]["datacenter"] = oldest
	Game.state["plots"][0]["status"] = "operational"
	Game.state["plots"].append({"id": "plot_2", "index": 2, "purchase_price": 1000.0, "purchased": true, "status": "operational", "datacenter": newer})
	Game.state["bankruptcy"] = {"status": "arrears", "debt": 1000.0, "arrears_online_seconds": 21599.0, "rescue_uses": 0, "rescue_day": -1, "last_takeover": {}, "takeover_notice_pending": false}
	Game.state["player"]["cash"] = 0.0
	Game.state["player"]["era"] = 3
	Game.state["player"]["network_level"] = 4
	Game.state["player"]["gems"] = 99
	Game.state["technology"]["auto_retirement"] = true
	Game.state["achievements"]["era_two"] = true
	Game.state["achievements"]["era_three"] = true
	var takeover_report := Game.advance_time(2.0, false)
	var settlement: Dictionary = takeover_report.get("takeovers", [])[0] if not takeover_report.get("takeovers", []).is_empty() else {}
	_expect(Game.state["bankruptcy"]["status"] == "normal" and is_zero_approx(float(Game.state["bankruptcy"]["debt"])), "arrears timeout resolves through bank takeover instead of game over")
	_expect(settlement.get("sold_count", 0) == 1 and settlement.get("sold", [])[0].get("datacenter_id", "") == "dc_oldest", "bank takeover sells the oldest operational data center first")
	_expect(Game.find_datacenter("dc_oldest").is_empty() and not Game.find_datacenter("dc_newer").is_empty(), "bank takeover stops selling as soon as the debt is cleared")
	_expect(Game.state["player"]["era"] == 3 and Game.state["player"]["network_level"] == 4, "bank takeover preserves era and network progression")
	_expect(Game.state["player"]["gems"] == 99 and bool(Game.state["technology"]["auto_retirement"]), "bank takeover preserves technology and premium currency")
	_expect(Game.state["plots"].size() == 2 and bool(Game.state["plots"][0].get("purchased", false)) and bool(Game.state["plots"][1].get("purchased", false)), "bank takeover preserves every purchased plot")

	Game.reset_for_tests()
	var doomed := _test_datacenter("dc_insufficient", "dc_t1")
	Game.state["plots"][0]["datacenter"] = doomed
	Game.state["plots"][0]["status"] = "operational"
	Game.state["bankruptcy"] = {"status": "arrears", "debt": 100000.0, "arrears_online_seconds": 21600.0, "rescue_uses": 0, "rescue_day": -1, "last_takeover": {}, "takeover_notice_pending": false}
	Game.state["player"]["cash"] = 0.0
	var shortfall_report := Game.advance_time(1.0, false)
	var shortfall: Dictionary = shortfall_report.get("takeovers", [])[0] if not shortfall_report.get("takeovers", []).is_empty() else {}
	_expect(float(shortfall.get("debt_forgiven", 0.0)) > 0.0 and is_zero_approx(float(Game.state["bankruptcy"]["debt"])), "bank takeover forgives any debt left after all operational data centers are sold")
	_expect(is_equal_approx(float(Game.state["player"]["cash"]), 5000.0) and float(shortfall.get("relief_grant", 0.0)) > 0.0, "bank takeover grants enough restructuring cash to guarantee the five-thousand floor")

	Game.reset_for_tests()
	Game.state["bankruptcy"]["status"] = "game_over"
	Game.state["bankruptcy"]["debt"] = 250.0
	Game.state["player"]["cash"] = 0.0
	Game.call("_ensure_state_shape")
	_expect(Game.state["bankruptcy"]["status"] == "normal" and bool(Game.state["bankruptcy"].get("takeover_notice_pending", false)) and is_equal_approx(float(Game.state["player"]["cash"]), 5000.0), "legacy game-over saves migrate once into a playable takeover settlement")

func _run_prestige_test() -> void:
	Game.reset_for_tests()
	Game.state["player"]["total_datacenters_built"] = 20
	Game.state["player"]["cash"] = 100000.0
	Game.state["inventory"]["instant_build_tickets"] = 3
	Game.state["purchases"]["pack_starter"] = 1
	Game.state["processed_transactions"]["paid-transaction"] = true
	Game.state["tutorial"]["completed"] = true
	Game.state["flags"]["standard_built"] = true
	var old_brand := float(Game.state["player"]["brand_multiplier"])
	var result := Game.prestige()
	_expect(bool(result.get("ok", false)), "prestige unlocks after twenty builds")
	_expect(float(Game.state["player"]["brand_multiplier"]) > old_brand, "prestige increases permanent brand multiplier")
	_expect(Game.state["plots"].size() == 1, "prestige resets park to one plot")
	_expect(Game.state["inventory"]["instant_build_tickets"] == 3 and Game.state["purchases"]["pack_starter"] == 1, "prestige preserves paid inventory and purchase limits")
	_expect(bool(Game.state["processed_transactions"].get("paid-transaction", false)), "prestige preserves StoreKit transaction idempotency")
	_expect(bool(Game.state["tutorial"]["completed"]) and bool(Game.state["flags"]["standard_built"]), "prestige does not replay the tutorial")

func _run_account_reset_test() -> void:
	Game.reset_for_tests()
	Game.state["player"]["gems"] = 321
	Game.state["player"]["brand_multiplier"] = 1.25
	Game.state["stats"]["prestige_count"] = 2
	Game.state["inventory"]["instant_build_tickets"] = 4
	Game.state["entitlements"]["noads"] = true
	Game.state["purchases"]["pack_builder"] = 1
	Game.state["processed_transactions"]["account-transaction"] = true
	Game.state["achievements"]["first_prestige"] = true
	Game.start_new_company()
	_expect(Game.state["player"]["gems"] == 321 and is_equal_approx(Game.state["player"]["brand_multiplier"], 1.25), "new company preserves paid currency and permanent brand")
	_expect(Game.state["inventory"]["instant_build_tickets"] == 4 and bool(Game.state["entitlements"]["noads"]), "new company preserves inventory and entitlements")
	_expect(Game.state["purchases"]["pack_builder"] == 1 and bool(Game.state["processed_transactions"].get("account-transaction", false)), "new company preserves purchase limits and transaction history")
	_expect(bool(Game.state["achievements"].get("first_prestige", false)) and Game.state["stats"]["prestige_count"] == 2, "new company preserves account achievements and prestige count")

func _expect(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: %s" % description)
	else:
		failed += 1
		push_error("FAIL: %s" % description)
