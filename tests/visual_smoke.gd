extends Node

const MAIN_SCENE := preload("res://main.tscn")
const Market := preload("res://gameplay/market_system.gd")
const Rules := preload("res://gameplay/game_rules.gd")
const ThemeMaker := preload("res://ui/theme_factory.gd")
const OUTPUT_ROOT_PREFIX := "/tmp/data_center_tycoon_visual_"
const LOGICAL_SIZE := Vector2(804, 1748)
const PROFILE_SIZES := {
	"se": Vector2i(750, 1334),
	"standard": Vector2i(990, 2151),
	"ipad": Vector2i(1024, 1366),
}
const CRITICAL_PROFILE_STATES := [
	"map",
	"ftue_spotlight",
	"dc_context_aging_bottom",
	"dc_board",
	"inquiry_persona_card",
	"tech",
	"store",
	"duty_log_dialog",
]

var output_root := OUTPUT_ROOT_PREFIX
var capture_locale := "zh_CN"
var capture_profile := "standard"
var preview_size := Vector2i(990, 2151)
var captured_count := 0

func _ready() -> void:
	capture_locale = _requested_locale()
	capture_profile = _requested_profile()
	preview_size = PROFILE_SIZES[capture_profile]
	TranslationServer.set_locale(capture_locale)
	output_root = "%s%s_%s_" % [OUTPUT_ROOT_PREFIX, capture_locale, capture_profile]
	# Regression captures use 75% of the iPhone 17 Pro Max physical 1320x2868
	# resolution (150% of the 660x1434 desktop preview). The design canvas stays unchanged.
	# Borderless mode prevents macOS from shrinking the tall capture to reserve title-bar space.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(preview_size)
	DisplayServer.window_move_to_foreground()
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
	# Reproduce a full two-project queue while the next build choice is open. The
	# error must render above the drawer and explain both capacity and next step.
	var feedback_now := Game.simulation_time()
	Game.state["construction_queue"] = [
		{"id": "visual_queue_1", "type": "datacenter", "started_at": feedback_now, "complete_at": feedback_now + 300.0},
		{"id": "visual_queue_2", "type": "power", "started_at": feedback_now, "complete_at": feedback_now + 600.0},
	]
	main.call("_handle_result", {"ok": false, "reason": "queue_full"}, {"operation": "datacenter"})
	var live_feedback := main.find_child("OperationFeedback", true, false) as Label
	var feedback_rect := live_feedback.get_global_rect() if live_feedback != null else Rect2()
	print("VISUAL_SMOKE: operation feedback visible=%s rect=%s alpha=%.2f text=%s" % [str(live_feedback.is_visible_in_tree() if live_feedback != null else false), str(feedback_rect), live_feedback.modulate.a if live_feedback != null else 0.0, live_feedback.text if live_feedback != null else "missing"])
	if live_feedback == null or not live_feedback.is_visible_in_tree() or not feedback_rect.intersects(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)) or not "2/2" in live_feedback.text:
		push_error("VISUAL_SMOKE: operation error is not visible above the build drawer")
		valid = false
	valid = (await _capture(main, "operation_error", false)) and valid
	Game.state["construction_queue"] = []
	var toast := main.get("toast_label") as Label
	if toast != null:
		toast.visible = false
	var toast_tween: Tween = main.get("_toast_tween") as Tween
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()
	var building_picker := main.find_child("BuildingPicker", true, false)
	if building_picker != null:
		building_picker.queue_free()
		await get_tree().process_frame
	main.park_map.reset_camera()
	# Rewarded time must count as completed work. Stage the exact reported case:
	# a one-hour Standard Data Center, 2m40s of natural time, then a -30m video.
	# The queue must show 27m20s remaining and roughly 54% progress, not ~9%.
	var rewarded_now := Game.simulation_time()
	Game.state["construction_queue"] = [{
		"id": "visual_rewarded_progress",
		"type": "datacenter",
		"plot_id": "plot_1",
		"building_id": "dc_t1",
		"started_at": rewarded_now - 160.0,
		"complete_at": rewarded_now + 1640.0,
		"duration_seconds": 3600.0,
		"ad_uses": 1,
	}]
	main.call("_navigate", "build")
	valid = (await _capture(main, "construction_rewarded_progress")) and valid
	Game.state["construction_queue"] = []
	main.call("_navigate", "map")
	Game.start_datacenter_construction("plot_1", "dc_t0")
	main.call("_navigate", "build")
	valid = (await _capture(main, "construction_queue")) and valid
	Game.advance_time(300.0, false)
	main.call("_navigate", "map")
	# Keep a dedicated review frame for the live completion effect.  This makes
	# regressions back to rings, duplicated clouds or building-covering FX visible
	# in every bilingual screenshot audit rather than only in motion.
	await get_tree().create_timer(0.42).timeout
	valid = (await _capture(main, "construction_complete_fx", false)) and valid
	# Then capture the settled building after every temporary node has left.
	await get_tree().create_timer(0.45).timeout
	valid = (await _capture(main, "map_built")) and valid
	await get_tree().create_timer(0.9).timeout
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	# C3: stage the one-cat world presentation with no discovery side effects,
	# then inspect the same collection section for four unrevealed formal cards.
	var built_before_cat := int(Game.state["player"].get("total_datacenters_built", 0))
	Game.state["player"]["total_datacenters_built"] = 2
	main.park_map.setup(Game.state.get("plots", []))
	main.park_map.force_cat_state_for_tests("stroll")
	valid = (await _capture(main, "campus_cat", false)) and valid
	main.call("_navigate", "tech")
	main.call("_set_tech_section", "collection")
	# Navigation is normally debounced by the live UI loop. The assertion below
	# inspects the collection tree immediately, so materialize that authoritative
	# page synchronously instead of racing a slower renderer's next refresh tick.
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().process_frame
	var campus_life := main.find_child("Collection_campus_life", true, false)
	var unknown_cat_cards := 0
	if campus_life != null:
		for label_node: Node in campus_life.find_children("*", "Label", true, false):
			if (label_node as Label).text == "?":
				unknown_cat_cards += 1
	if capture_profile == "standard" and (campus_life == null or unknown_cat_cards != 4 or campus_life.find_children("*", "TextureRect", true, false).size() < 4):
		push_error("VISUAL_SMOKE: campus-life collection must show four formal undiscovered cat cards")
		valid = false
	Game.state["player"]["total_datacenters_built"] = built_before_cat
	main.call("_navigate", "map")
	main.park_map.setup(Game.state.get("plots", []))
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
		var power_transition_live: bool = main.park_map.find_child("PowerOnDarkGhost", true, false) != null and main.park_map.find_child("PowerOnGlow", true, false) == null
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
	for index: int in range(13):
		var dense_dc := dc.duplicate(true)
		dense_dc["id"] = "visual_dc_%d" % index
		dense_dc["building_id"] = "dc_t%d" % mini(index % 4, 3)
		dense_dc["power_unit"] = "power_t1"
		dense_plots.append({"id": "visual_plot_%d" % index, "index": index + 1, "status": "operational", "datacenter": dense_dc})
	# Keep the fixture authoritative: the world sale badge, primary CTA, tabs and
	# overview must all calculate the same 14th-plot price and two-campus state.
	var canonical_plots: Array = Game.state["plots"]
	var canonical_cash := float(Game.state["player"].get("cash", 0.0))
	Game.state["plots"] = dense_plots
	Game.state["player"]["cash"] = 2000000.0
	main.set("_last_map_signature", "")
	main.call("_refresh")
	await get_tree().process_frame
	main.park_map.focus_campus(1, false)
	valid = (await _capture(main, "campus_dense", false)) and valid
	main.call("_show_campus_overview")
	valid = (await _capture(main, "campus_overview", false)) and valid
	var campus_overview := main.find_child("ActionSheetOverlay", true, false)
	if campus_overview != null:
		campus_overview.queue_free()
		await get_tree().process_frame
	Game.state["plots"] = canonical_plots
	Game.state["player"]["cash"] = canonical_cash
	main.set("_last_map_signature", "")
	main.call("_refresh")
	await get_tree().process_frame
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
	alert_contract["free_switch_available"] = true
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
	# The aging decision adds another content block to the phone drawer. Regress
	# the exact long-content state that used to push the CTA and illustrated frame
	# below the screen, then scroll to the bottom and prove the final action remains
	# reachable inside the safe-area-bounded viewport.
	var original_built_at := float(dc.get("built_at", 0.0))
	var context_building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	dc["built_at"] = Game.simulation_time() - float(context_building.get("lifespan_seconds", 1.0)) * 0.88
	main.call("_open_datacenter", str(dc.get("id", "")))
	await get_tree().process_frame
	await get_tree().process_frame
	var aging_scroll := main.find_child("ContextSheetScroll", true, false) as ScrollContainer
	if aging_scroll != null:
		var aging_bar := aging_scroll.get_v_scroll_bar()
		aging_scroll.scroll_vertical = maxi(0, int(aging_bar.max_value - aging_bar.page))
		await get_tree().process_frame
	valid = (await _capture(main, "dc_context_aging_bottom")) and valid
	dc_context = main.find_child("DatacenterContext", true, false)
	if dc_context != null:
		dc_context.queue_free()
		await get_tree().process_frame
	dc["built_at"] = original_built_at
	# Reproduce the on-device JSON shape that previously turned era 1 into the
	# missing key "1.0", then review the no-rack earning guidance before staging
	# the fully equipped board used by later states.
	dc["power_unit"] = "power_t1"
	Game.state["player"]["era"] = 1.0
	Game.state["player"]["network_level"] = 1.0
	for customer_id: String in ["internet", "mining"]:
		Game.state["market"]["noise"][customer_id] = 0.0
		Game.state["market"]["history"][customer_id] = [
			{"at": 0.0, "value": 0.0},
			{"at": 240.0, "value": 0.0},
		]
	Game.state["market"].erase("quote_schema_version")
	Market.new().ensure_state(Game.state, Game.data)
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "contracts")
	valid = (await _capture(main, "dc_contracts_empty")) and valid
	dc["power_unit"] = ""
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	valid = (await _capture(main, "dc_board_unpowered")) and valid
	var power_blocked_now := Game.simulation_time()
	Game.state["construction_queue"] = [
		{"id": "visual_power_block_a", "type": "datacenter", "started_at": power_blocked_now, "complete_at": power_blocked_now + 300.0},
		{"id": "visual_power_block_b", "type": "datacenter", "started_at": power_blocked_now, "complete_at": power_blocked_now + 600.0},
	]
	main.call("_on_power_slot_selected", str(dc.get("id", "")))
	valid = (await _capture(main, "power_install_blocked", false)) and valid
	Game.state["construction_queue"] = []
	var power_blocker := main.find_child("ActionSheetOverlay", true, false)
	if power_blocker != null:
		power_blocker.queue_free()
		await get_tree().process_frame
	dc["power_unit"] = "power_t1"
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": false, "fault_at": -1.0}
	dc["racks"][1] = {"rack_id": "rack_storage_t1", "status": "installing", "enabled": true, "started_at": Game.simulation_time(), "install_complete_at": Game.simulation_time() + 90.0, "ad_uses": 0}
	dc["coolers"]["north"] = "cool_air_t1"
	dc["customer_id"] = "internet"
	dc["contract_end_at"] = Game.simulation_time()
	dc["free_switch_available"] = true
	dc["persona_id"] = "internet_tang_man"
	Game.state["meta"]["customer_service_seconds"]["internet"] = 50000.0
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	valid = (await _capture(main, "dc_board")) and valid
	var set_fixture := {
		"building_id": dc.get("building_id", ""),
		"power_unit": dc.get("power_unit", ""),
		"coolers": dc.get("coolers", {}).duplicate(true),
		"racks": dc.get("racks", []).duplicate(true),
	}
	dc["building_id"] = "dc_t3"
	dc["power_unit"] = "power_t2"
	dc["coolers"] = {"north": "cool_air_t1"}
	var set_racks: Array = []
	set_racks.resize(9)
	set_racks.fill(null)
	for slot: int in [0, 1, 2]:
		set_racks[slot] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true, "fault_at": -1.0}
	for slot: int in [3, 4]:
		set_racks[slot] = {"rack_id": "rack_storage_t1", "status": "active", "enabled": true, "fault_at": -1.0}
	dc["racks"] = set_racks
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	var set_board := main.call("_visible_datacenter_board", str(dc.get("id", ""))) as DatacenterBoard
	if set_board != null:
		set_board.call("set_placement_preview", 5, "rack_storage_t1")
	valid = (await _capture(main, "dc_board_set_bonus", false)) and valid
	dc["building_id"] = set_fixture["building_id"]
	dc["power_unit"] = set_fixture["power_unit"]
	dc["coolers"] = set_fixture["coolers"]
	dc["racks"] = set_fixture["racks"]
	dc["power_unit"] = "power_t2"
	dc["racks"][4] = {"rack_id": "rack_gpu_t1", "status": "active", "enabled": true, "fault_at": -1.0}
	main.call("_open_datacenter_detail", str(dc.get("id", "")), "board")
	valid = (await _capture(main, "dc_board_overheat")) and valid
	var board := main.call("_visible_datacenter_board", str(dc.get("id", ""))) as DatacenterBoard
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
	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": now - 300.0, "end_at": now + 6900.0}]
	Game.state["market"]["previews"] = []
	valid = (await _capture(main, "rare_event_banner")) and valid
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 2
	Game.state["player"]["network_level"] = 2
	Game.state["inquiries"]["open"] = [
		{"id": "visual_inquiry_edge", "template_id": "edge_delivery", "slot": 0, "arrived_at": now},
		{"id": "visual_inquiry_mining", "template_id": "mining_rush", "slot": 1, "arrived_at": now},
	]
	# Freeze the next optional arrival beyond the atlas run. Otherwise the real
	# simulation clock can legitimately add a third inquiry while a slower
	# locale/profile is settling, making this fixed two-card fixture flaky.
	Game.state["inquiries"]["next_arrival_at"] = now + 86400.0
	valid = (await _capture(main, "inquiry_board")) and valid
	# Refresh synchronously here: with refresh=false the debounced page rebuild
	# can land inside the capture's settle frames, leaving the old market page
	# pending-free next to the new one — find_children then counts both and the
	# two-cards/two-portraits assertions fail on nothing (compact profiles hit
	# the window most often; the screenshot itself was always correct).
	valid = (await _capture(main, "inquiry_persona_card")) and valid
	main.call("_show_inquiry_datacenter_picker", "visual_inquiry_edge")
	valid = (await _capture(main, "inquiry_accept_sheet", false)) and valid
	var inquiry_sheet := main.find_child("ActionSheetOverlay", true, false)
	if inquiry_sheet != null:
		inquiry_sheet.queue_free()
		await get_tree().process_frame
	_fill_market_history(730)
	valid = (await _capture(main, "market_rich")) and valid
	# Meta-progression states use their real rendered illustrations and live data.
	main.call("_navigate", "tech")
	main.call("_set_tech_section", "roadmap")
	valid = (await _capture(main, "company_roadmap")) and valid
	main.call("_set_tech_section", "collection")
	valid = (await _capture(main, "company_collection")) and valid
	var original_prestige_count := int(Game.state["stats"].get("prestige_count", 0))
	Game.state["stats"]["prestige_count"] = 2
	main.call("_set_tech_section", "board")
	valid = (await _capture(main, "board_specialties")) and valid
	main.call("_navigate", "map")
	main.call("_show_campus_strategy", 0)
	valid = (await _capture(main, "campus_strategy", false)) and valid
	var strategy_sheet := main.find_child("ActionSheetOverlay", true, false)
	if strategy_sheet != null:
		strategy_sheet.queue_free()
		await get_tree().process_frame
	Game.state["stats"]["prestige_count"] = original_prestige_count
	for page: String in ["tech", "store", "settings"]:
		main.call("_navigate", page)
		if page == "tech":
			main.call("_set_tech_section", "upgrades")
			await get_tree().process_frame
			var tech_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
			var bays_card := main.find_child("ConstructionBaysCard", true, false) as Control
			if tech_scroll != null and bays_card != null:
				tech_scroll.ensure_control_visible(bays_card)
		valid = (await _capture(main, page)) and valid
		if page == "store":
			valid = (await _scroll_survives_tick(main)) and valid
		if page == "tech":
			main.call("_set_tech_section", "achievements")
			valid = (await _capture(main, "achievements")) and valid
	main.call("_open_public_document", "privacy")
	await get_tree().process_frame
	var legal_view := main.find_child("LegalView", true, false)
	if legal_view != null:
		legal_view.call("scroll_to_middle_for_tests")
	valid = (await _capture(main, "legal_view", false)) and valid
	if legal_view != null:
		legal_view.queue_free()
		await get_tree().process_frame
	main.call("_open_public_document", "attributions")
	await get_tree().process_frame
	var attributions_view := main.find_child("LegalView", true, false)
	if attributions_view != null:
		attributions_view.call("scroll_to_middle_for_tests")
	valid = (await _capture(main, "attributions_view", false)) and valid
	if attributions_view != null:
		attributions_view.queue_free()
		await get_tree().process_frame
	main.call("_show_offline_dialog", {"elapsed_seconds": 14400.0, "income": 12840.0, "balance_before": 28000.0, "completed": [{"id": "job"}], "faults": [{"id": "fault"}], "events": [{"type": "event_started", "event_id": "sovereign_ai"}], "inquiries": [{"id": "visual_inquiry"}], "aging": [{"id": "aged"}], "contracts": [], "takeovers": [{"sold_count": 1}]})
	valid = (await _capture(main, "duty_log_dialog", false)) and valid
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
	Game.state["bankruptcy"] = {"status": "normal", "debt": 0.0, "arrears_online_seconds": 0.0, "rescue_uses": 0, "rescue_day": -1, "takeover_notice_pending": true, "last_takeover": {"debt_before": 4250.0, "debt_paid": 3100.0, "debt_forgiven": 1150.0, "relief_grant": 5000.0, "remaining_datacenters": 2, "sold_count": 2, "sold": [{"datacenter_id": "dc_1", "proceeds": 1800.0}, {"datacenter_id": "dc_2", "proceeds": 1300.0}]}}
	main.call("_on_bankruptcy_state_changed", "takeover")
	await get_tree().create_timer(0.6).timeout
	valid = (await _capture(main, "bank_takeover", false)) and valid
	var takeover_overlay := main.find_child("BankTakeoverOverlay", true, false)
	if takeover_overlay != null:
		takeover_overlay.queue_free()
		await get_tree().process_frame
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("VISUAL_SMOKE: %s %d portrait states profile=%s at %dx%d locale=%s -> %s*.png" % ["PASS" if valid else "FAIL", captured_count, capture_profile, preview_size.x, preview_size.y, capture_locale, output_root])
	get_tree().quit(0 if valid else 1)

func _requested_locale() -> String:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			var requested := argument.trim_prefix("--locale=")
			if requested in ["en", "zh_CN"]:
				return requested
	return "zh_CN"

func _requested_profile() -> String:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			var requested := argument.trim_prefix("--profile=")
			if PROFILE_SIZES.has(requested):
				return requested
			push_error("VISUAL_SMOKE: unknown profile %s; expected se, standard, or ipad" % requested)
	return "standard"

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
	if capture_profile != "standard" and name not in CRITICAL_PROFILE_STATES:
		# Keep fixture transitions and live page state authoritative while compact
		# profiles retain only their eight release-blocking screenshots.
		if refresh:
			main.call("_refresh")
		await get_tree().process_frame
		await get_tree().process_frame
		# The live-page debounce is 0.25 s. Preserve the same settling contract as
		# a full capture so a skipped market frame still materializes inquiry cards.
		await get_tree().create_timer(0.26).timeout
		return true
	print("VISUAL_SMOKE: rendering %s" % name)
	# The review atlas should show the authored screen, not an unrelated reward
	# toast emitted by fixture setup in an earlier state. operation_error is the
	# one deliberate feedback-state capture.
	if name != "operation_error":
		var toast := main.get("toast_label") as Label
		if toast != null:
			toast.visible = false
		var toast_tween := main.get("_toast_tween") as Tween
		if toast_tween != null and toast_tween.is_valid():
			toast_tween.kill()
	if refresh:
		main.call("_refresh")
	for _frame: int in range(3):
		await get_tree().process_frame
	if name in ["duty_log_dialog", "offline_reward", "era_unlock"]:
		await get_tree().create_timer(1.25).timeout
	await get_tree().create_timer(0.24).timeout
	if name in ["dc_board_placing", "dc_board_set_bonus"]:
		# A pending live-page refresh may replace the board during the capture
		# delay. Drain two possible exit-tween replacements, clear any outgoing
		# board, then apply the preview to the last (top-painted) visible board.
		# The final pass intentionally does not yield before frame_post_draw.
		var live_board: DatacenterBoard = null
		for attempt: int in range(3):
			if attempt > 0:
				await get_tree().process_frame
			live_board = null
			for board_node: Node in main.find_children("DatacenterBoard", "", true, false):
				if board_node is DatacenterBoard and board_node.is_visible_in_tree():
					var candidate := board_node as DatacenterBoard
					candidate.clear_placement_preview()
					live_board = candidate
			if live_board != null:
				if name == "dc_board_set_bonus":
					live_board.set_placement_preview(5, "rack_storage_t1")
				else:
					live_board.set_placement_preview(3, "rack_gpu_t1")
		if live_board == null:
			push_error("VISUAL_SMOKE: %s has no visible board to stage" % name)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# With aspect=keep, Godot returns only the scaled content viewport; pillarbox
	# gutters belong to the host window. Validate that content size first, then
	# reconstruct the complete device frame using the same audited clear color.
	var expected_content := _expected_content_size()
	var image_valid := not image.is_empty() and absi(image.get_width() - expected_content.x) <= 2 and absi(image.get_height() - expected_content.y) <= 2
	var layout_valid := _layout_is_safe(main, name)
	if name == "dc_board":
		layout_valid = _page_right_edge_is_solid(main, image) and layout_valid
	if image_valid:
		image = _framed_capture(image)
		layout_valid = _letterbox_is_theme_filled(image) and layout_valid
	var valid := image_valid and layout_valid
	var output_path := "%s%s.png" % [output_root, name]
	var save_error := image.save_png(output_path) if not image.is_empty() else ERR_CANT_CREATE
	if not valid or save_error != OK:
		push_error("VISUAL_SMOKE: %s failed size=%dx%d save_error=%d" % [name, image.get_width(), image.get_height(), save_error])
	else:
		print("VISUAL_SMOKE: captured %s" % name)
		captured_count += 1
	return valid and save_error == OK

func _expected_content_size() -> Vector2i:
	var scale := minf(float(preview_size.x) / LOGICAL_SIZE.x, float(preview_size.y) / LOGICAL_SIZE.y)
	return Vector2i(roundi(LOGICAL_SIZE.x * scale), roundi(LOGICAL_SIZE.y * scale))

func _framed_capture(content: Image) -> Image:
	if content.get_size() == preview_size:
		return content
	var framed := Image.create(preview_size.x, preview_size.y, false, content.get_format())
	framed.fill(ThemeFactory.SURFACE)
	var offset := (preview_size - content.get_size()) / 2
	framed.blit_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), offset)
	return framed

func _letterbox_is_theme_filled(image: Image) -> bool:
	# canvas_items + aspect=keep remains untouched. Wider profiles therefore get
	# pillarbox gutters from the clear color; sample those gutters directly so a
	# black bar or leaking world texture cannot ship unnoticed.
	var configured_clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.BLACK)
	if not configured_clear.is_equal_approx(ThemeFactory.SURFACE):
		push_error("VISUAL_SMOKE: project clear color %s does not match theme surface %s" % [str(configured_clear), str(ThemeFactory.SURFACE)])
		return false
	var expected_aspect := LOGICAL_SIZE.x / LOGICAL_SIZE.y
	var image_aspect := float(image.get_width()) / maxf(1.0, float(image.get_height()))
	if image_aspect <= expected_aspect + 0.002:
		return true
	var content_width := int(round(float(image.get_height()) * expected_aspect))
	var gutter := maxi(0, (image.get_width() - content_width) / 2)
	if gutter < 2:
		return true
	var expected := ThemeFactory.SURFACE
	for sample_x: int in [gutter / 2, image.get_width() - 1 - gutter / 2]:
		for sample_y: int in [image.get_height() / 8, image.get_height() / 2, image.get_height() * 7 / 8]:
			var color := image.get_pixel(sample_x, sample_y)
			if absf(color.r - expected.r) > 0.035 or absf(color.g - expected.g) > 0.035 or absf(color.b - expected.b) > 0.035:
				push_error("VISUAL_SMOKE: %s letterbox is not theme-filled at %d,%d color=%s expected=%s" % [capture_profile, sample_x, sample_y, str(color), str(expected)])
				return false
	return true

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
	if state_name == "construction_rewarded_progress":
		var progress := main.find_child("QueueConstructionProgress", true, false) as ProgressBar
		var fraction := progress.value / progress.max_value if progress != null and progress.max_value > 0.0 else -1.0
		var remaining := float(progress.get_meta("remaining_seconds", -1.0)) if progress != null else -1.0
		if progress == null or not progress.is_visible_in_tree() or fraction < 0.53 or fraction > 0.56 or absf(remaining - 1640.0) > 2.0:
			push_error("VISUAL_SMOKE: rewarded one-hour construction must show ~54%% progress and 27m20s remaining; fraction=%.3f remaining=%.1f" % [fraction, remaining])
			valid = false
	if state_name in ["inquiry_board", "inquiry_persona_card"]:
		var inquiry_board := main.find_child("InquiryBoard", true, false)
		var inquiry_cards := main.find_children("InquiryCard_*", "PanelContainer", true, false)
		if inquiry_board == null or inquiry_cards.size() != 2 or not inquiry_board.find_children("*", "ProgressBar", true, false).is_empty():
			push_error("VISUAL_SMOKE: inquiry board must render two persistent cards with no expiry countdown or progress bar")
			valid = false
		if state_name == "inquiry_persona_card" and (main.find_children("InquiryPersonaPortrait", "TextureRect", true, false).size() != 2 or main.find_children("InquiryPersonaLine", "Label", true, false).size() != 2):
			push_error("VISUAL_SMOKE: inquiry persona state must show one formal portrait and line per open inquiry")
			valid = false
	if state_name == "dc_contracts" and (main.find_child("ContractPersonaContact", true, false) == null or main.find_child("ContractPersonaPortrait", true, false) == null):
		push_error("VISUAL_SMOKE: familiar contract must expose its named contact and portrait")
		valid = false
	if state_name == "inquiry_accept_sheet":
		var inquiry_sheet := main.find_child("ActionSheetOverlay", true, false)
		if inquiry_sheet == null or inquiry_sheet.find_children("Choice_*", "Button", true, false).is_empty():
			push_error("VISUAL_SMOKE: inquiry assignment sheet must expose data-center choices")
			valid = false
	if state_name == "map":
		var power_metrics := _asset_palette_metrics("ic_power")
		if float(power_metrics.get("gold_ratio", 0.0)) < 0.30 or float(power_metrics.get("used_aspect", 1.0)) > 0.78:
			push_error("VISUAL_SMOKE: F9 power icon is not a dominant standalone gold bolt")
			valid = false
		var era_neutral_floor := {"ic_era1": 0.20, "ic_era2": 0.16, "ic_era3": 0.14}
		for era_asset: String in era_neutral_floor:
			var era_metrics := _asset_palette_metrics(era_asset)
			var era_aspect := float(era_metrics.get("used_aspect", 0.0))
			if float(era_metrics.get("blue_ratio", 0.0)) < 0.30 or float(era_metrics.get("bright_neutral_ratio", 0.0)) < float(era_neutral_floor[era_asset]) or era_aspect < 0.90 or era_aspect > 1.10:
				push_error("VISUAL_SMOKE: F9 era medal lacks its navy field or readable gold numeral: %s metrics=%s" % [era_asset, str(era_metrics)])
				valid = false
	if state_name == "campus_cat":
		var cat := main.park_map.campus_cat as CampusCat
		if cat == null or not cat.is_visible_in_tree() or cat.current_state != "stroll" or cat.hit_radius() < 44.0 or main.park_map.find_children("CampusCat", "Node2D", true, false).size() != 1:
			push_error("VISUAL_SMOKE: campus cat must be one visible strolling sprite with a 44pt body-only hit target")
			valid = false
	if state_name != "map":
		var world_host := main.find_child("WorldHost", true, false) as Control
		if world_host == null or world_host.z_index > -1800:
			push_error("VISUAL_SMOKE: depth-sorted world can overdraw the active system page")
			valid = false
		elif main.park_map != null:
			for grid_plot: Node in main.park_map.find_children("GridPlot_*", "Button", true, false):
				if world_host.z_index + (grid_plot as CanvasItem).z_index >= 0:
					push_error("VISUAL_SMOKE: grid plot escapes the bounded world canvas band")
					valid = false
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
		var task_button := main.find_child("TaskButton", true, false) as Button
		var operations_button := main.find_child("OperationsButton", true, false) as Button
		var task_caption := task_button.find_child("WorldActionLabel", true, false) as Label if task_button != null else null
		var operations_caption := operations_button.find_child("WorldActionLabel", true, false) as Label if operations_button != null else null
		if task_caption == null or operations_caption == null or task_button == null or operations_button == null or not task_button.is_ancestor_of(task_caption) or not operations_button.is_ancestor_of(operations_caption) or not task_button.text.is_empty() or not operations_button.text.is_empty():
			push_error("VISUAL_SMOKE: map action labels are not owned by their clickable entries")
			valid = false
		for caption: Label in [task_caption, operations_caption]:
			if caption != null:
				var caption_rect := caption.get_global_rect()
				var button_rect := task_button.get_global_rect() if caption == task_caption else operations_button.get_global_rect()
				if not viewport_rect.grow(-4.0).encloses(caption_rect) or not button_rect.encloses(caption_rect) or caption.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					push_error("VISUAL_SMOKE: map action caption escapes its clickable button %s caption=%s button=%s" % [caption.name, caption_rect, button_rect])
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
			primary_is_white = primary_is_white and primary_world_action.get_theme_font("font") == ThemeFactory.font_bold()
			primary_is_white = primary_is_white and primary_world_action.get_theme_constant("outline_size") == 4
			primary_is_white = primary_is_white and primary_world_action.get_theme_color("font_outline_color").is_equal_approx(ThemeFactory.COLORS.ink)
		if primary_world_text != null and primary_world_fill != null:
			primary_is_white = primary_is_white and primary_world_text.text == str(primary_world_action.get_meta("primary_action_text", ""))
			primary_is_white = primary_is_white and primary_world_text.get_theme_color("font_color").is_equal_approx(Color.WHITE) and primary_world_text.get_theme_constant("outline_size") == 4
			primary_is_white = primary_is_white and primary_world_fill.text == primary_world_text.text and primary_world_fill.get_theme_color("font_color").is_equal_approx(Color.WHITE) and primary_world_fill.get_theme_color("font_outline_color").is_equal_approx(Color.WHITE) and primary_world_fill.get_theme_constant("outline_size") == 1
		if not primary_is_white:
			push_error("VISUAL_SMOKE: F1 PrimaryWorldAction is not pure-white bold CJK with a 4px ink outline")
			valid = false
		for button_name: String in ["TaskButton", "OperationsButton"]:
			var world_button := main.find_child(button_name, true, false) as Button
			var world_caption := world_button.find_child("WorldActionLabel", true, false) as Label if world_button != null else null
			if world_caption == null or not world_button.is_ancestor_of(world_caption) or not world_caption.get_theme_color("font_color").is_equal_approx(Color.WHITE) or world_caption.get_theme_font_size("font_size") != 20 or world_caption.get_theme_constant("outline_size") != 3 or not world_caption.get_theme_color("font_outline_color").is_equal_approx(ThemeFactory.COLORS.ink) or world_caption.get_theme_font("font") != ThemeFactory.font_world_heavy():
				push_error("VISUAL_SMOKE: F10 world action caption violates the owned 20u white/heavy/3px contract: %s" % button_name)
				valid = false
		var sale_price := main.find_child("SalePriceBadge", true, false) as PanelContainer
		var sale_tether := main.find_child("SalePriceTether", true, false) as ColorRect
		if sale_price == null or sale_tether == null or not bool(sale_price.get_meta("sale_sign_attached", false)) or not is_equal_approx(float(sale_price.get_meta("sale_price_gap", -1.0)), 12.0) or sale_price.size.x > 132.0 or sale_price.size.y > 44.0:
			push_error("VISUAL_SMOKE: W3 sale price is not a compact plate tethered 12u below the parcel art")
			valid = false
		for hud_name: String in ["TaskButton", "OperationsButton"]:
			var hud_entry := main.find_child(hud_name, true, false) as Button
			var hud_style := hud_entry.get_theme_stylebox("normal") as StyleBoxFlat if hud_entry != null else null
			if hud_entry == null or not bool(hud_entry.get_meta("world_hud_entry", false)) or hud_style == null or not hud_style.bg_color.is_equal_approx(Color("1c2c40")) or hud_style.get_border_width(SIDE_TOP) < 2:
				push_error("VISUAL_SMOKE: S4 map entry is not using the shared deep HUD material: %s" % hud_name)
				valid = false
	if state_name == "store":
		var best_value := main.find_child("BestValueRibbon", true, false) as PanelContainer
		var best_value_label := main.find_child("BestValueLabel", true, false) as Label
		if best_value == null or best_value_label == null or best_value.size.x + 1.0 < best_value_label.get_combined_minimum_size().x + 24.0 or best_value.size.y + 1.0 < best_value_label.get_combined_minimum_size().y + 12.0:
			push_error("VISUAL_SMOKE: store best-value ribbon does not fit its localized label")
			valid = false
		var page_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		var page_bar := page_scroll.get_v_scroll_bar() if page_scroll != null else null
		var page_grabber := page_bar.get_theme_stylebox("grabber") as StyleBoxFlat if page_bar != null else null
		if page_bar == null or not bool(page_bar.get_meta("system_scrollbar", false)) or page_bar.custom_minimum_size.x > 6.0 or page_grabber == null or not is_equal_approx(page_grabber.bg_color.a, 0.18):
			push_error("VISUAL_SMOKE: W5 system scrollbar is not the 6u translucent HUD rail")
			valid = false
		var locked_offer := main.find_child("StoreLockedOffer", true, false) as PanelContainer
		var locked_copy := main.find_child("CompactStatusText", true, false) as Label
		if locked_offer == null or locked_copy == null or locked_offer.custom_minimum_size.y > 96.0 or locked_copy.max_lines_visible != 1:
			push_error("VISUAL_SMOKE: S5 locked store offer is not a compact 96u single-line rail")
			valid = false
	if state_name == "campus_overview":
		var overview_sheet := main.find_child("ActionSheetOverlay", true, false) as Control
		var first_campus := main.find_child("Choice_campus_0", true, false) as Button
		var second_campus := main.find_child("Choice_campus_1", true, false) as Button
		if overview_sheet == null or first_campus == null or second_campus == null or first_campus.size.y < 88.0 or second_campus.size.y < 88.0:
			push_error("VISUAL_SMOKE: campus overview does not expose a scrollable touch-safe route for every district")
			valid = false
	if state_name == "ftue_spotlight":
		var spotlight := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
		var primary := main.find_child("PrimaryWorldAction", true, false) as Control
		var callout := main.find_child("TutorialCallout", true, false) as Control
		var tutorial_message := main.find_child("TutorialMessage", true, false) as Label
		var hole_border := main.find_child("TutorialHoleBorder", true, false) as PanelContainer
		var hole: Rect2 = spotlight.get("target_rect") if spotlight != null else Rect2()
		if spotlight == null or not spotlight.visible or not bool(spotlight.call("is_actionable")) or primary == null or not hole.intersects(primary.get_global_rect()):
			push_error("VISUAL_SMOKE: FTUE spotlight does not resolve the primary action hole")
			valid = false
		if main.find_child("TutorialPointer", true, false) != null:
			push_error("VISUAL_SMOKE: precise FTUE callout tail must not be duplicated by a hand pointer")
			valid = false
		var mask := main.find_child("TutorialMask0", true, false) as ColorRect
		if mask == null or mask.color.a < 0.62 or str(mask.get_meta("mask_geometry", "")) != "rounded_sdf" or not mask.material is ShaderMaterial:
			push_error("VISUAL_SMOKE: FTUE does not use the 0.62 rounded SDF dim layer")
			valid = false
		if callout == null or tutorial_message == null or not callout.get_global_rect().grow(1.0).encloses(tutorial_message.get_global_rect()):
			push_error("VISUAL_SMOKE: FTUE message is outside its adaptive callout")
			valid = false
		var hole_style: StyleBoxFlat = null
		if hole_border != null:
			hole_style = hole_border.get_theme_stylebox("panel") as StyleBoxFlat
		var shared_radius := int(hole_border.get_meta("spotlight_corner_radius", 0)) if hole_border != null else 0
		var mask_radius := int(mask.get_meta("spotlight_corner_radius", 0)) if mask != null else 0
		var border_layers := int(hole_border.get_meta("spotlight_border_layers", 0)) if hole_border != null else 0
		if hole_style == null or hole_style.get_border_width(SIDE_TOP) != 4 or shared_radius != 32 or mask_radius != shared_radius or border_layers != 1 or hole_style.border_color.is_equal_approx(ThemeFactory.COLORS.yellow):
			push_error("VISUAL_SMOKE: FTUE spotlight is not the single cyan 4u/32u rounded frame")
			valid = false
	if state_name in ["dc_contracts_empty", "dc_contracts", "contract_comparison", "market_empty", "market_active", "market_rich"]:
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
	if state_name == "dc_contracts_empty":
		var capacity_guide := main.find_child("ContractCapacityGuide", true, false) as PanelContainer
		var configure_racks := main.find_child("ContractConfigureRacks", true, false) as Button
		var internet_rate := main.find_child("MarketRate_internet", true, false) as Label
		var internet_projection := main.find_child("ContractProjection_internet", true, false) as Label
		if capacity_guide == null or str(capacity_guide.get_meta("capacity_state", "")) != "empty" or configure_racks == null or configure_racks.size.y < 88.0 or internet_rate == null or internet_rate.text.contains("×0.00") or internet_projection == null or internet_projection.text != tr("CONTRACT_PROJECTED_AFTER_RACK"):
			push_error("VISUAL_SMOKE: empty contract page does not explain the online-rack earning prerequisite with a valid market quote")
			valid = false
	if state_name == "action_sheet":
		var drag_handle := main.find_child("SheetDragHandle", true, false) as Control
		var sheet_close := main.find_child("SheetCloseButton", true, false) as Button
		var action_overlay := main.find_child("ActionSheetOverlay", true, false) as ColorRect
		if drag_handle == null or drag_handle.size.y < 88.0 or sheet_close == null or action_overlay == null or not bool(action_overlay.get_meta("backdrop_dismiss_enabled", false)) or int(action_overlay.get_meta("explicit_close_count", 0)) != 1:
			push_error("VISUAL_SMOKE: action sheet does not expose the close/backdrop/drag dismissal contract")
			valid = false
		for cancel_node: Node in main.find_children("*", "Button", true, false):
			var cancel_button := cancel_node as Button
			if cancel_button != null and cancel_button.is_visible_in_tree() and cancel_button.text == tr("CANCEL"):
				push_error("VISUAL_SMOKE: action sheet still renders a redundant full-width cancel action")
				valid = false
	if state_name == "build_drawer":
		var picker := main.find_child("BuildingPicker", true, false) as ColorRect
		var picker_sheet := picker.find_child("ContextSheet", true, false) as PanelContainer if picker != null else null
		var picker_scroll := picker.find_child("BuildingPickerScroll", true, false) as ScrollContainer if picker != null else null
		var picker_cards := picker.find_child("BuildingPickerCards", true, false) as HBoxContainer if picker != null else null
		var picker_safe := picker != null and picker_sheet != null and picker_scroll != null and picker_cards != null
		if picker_safe:
			var sheet_rect := picker_sheet.get_global_rect()
			var scroll_rect := picker_scroll.get_global_rect()
			var cards_rect := picker_cards.get_global_rect()
			picker_safe = viewport_rect.grow(1.0).encloses(sheet_rect)
			picker_safe = picker_safe and cards_rect.position.y + 1.0 >= scroll_rect.position.y and cards_rect.end.y <= scroll_rect.end.y + 1.0
			picker_safe = picker_safe and cards_rect.end.y <= sheet_rect.end.y + 1.0
			var starter_cards := main.find_children("Building_*", "Button", true, false)
			if starter_cards.size() >= 2:
				var first_card := starter_cards[0] as Button
				var second_card := starter_cards[1] as Button
				picker_safe = picker_safe and first_card.get_global_rect().end.x <= scroll_rect.end.x + 1.0 and second_card.get_global_rect().end.x <= scroll_rect.end.x + 1.0
		if not picker_safe:
			push_error("VISUAL_SMOKE: building picker clips its cards or painted frame on the iPhone viewport")
			valid = false
	if state_name == "world_alerts":
		var alert_count := 0
		for node: Node in main.find_children("StatusBadge", "PanelContainer", true, false):
			var badge := node as PanelContainer
			if badge != null and badge.has_meta("alert_type"):
				alert_count += 1
				var alert_type := str(badge.get_meta("alert_type", ""))
				var badge_style := badge.get_theme_stylebox("panel") as StyleBoxFlat
				var should_breathe := alert_type == "fault"
				if bool(badge.get_meta("breathing", false)) != should_breathe or badge_style == null or not badge_style.border_color.is_equal_approx(Color.WHITE) or badge_style.get_border_width(SIDE_TOP) < 2:
					push_error("VISUAL_SMOKE: world alert lacks its semantic urgency or white rim: %s" % alert_type)
					valid = false
				if str(badge.get_meta("alert_tone", "")) != alert_type:
					push_error("VISUAL_SMOKE: world alert tone does not match its action: %s" % alert_type)
					valid = false
				if not viewport_rect.intersects(badge.get_global_rect()):
					push_error("VISUAL_SMOKE: world alert is outside the viewport: %s" % badge.get_meta("alert_type"))
					valid = false
		if alert_count != 3:
			push_error("VISUAL_SMOKE: expected three actionable world alerts, got %d" % alert_count)
			valid = false
	if state_name in ["map_built", "campus_dense", "world_alerts"]:
		var building_count := main.find_children("WorldArt", "TextureRect", true, false).size()
		var expected_min := 6 if state_name == "campus_dense" else (3 if state_name == "world_alerts" else 1)
		if building_count < expected_min:
			push_error("VISUAL_SMOKE: %s lacks expected world building art %d" % [state_name, building_count])
			valid = false
		if not main.find_children("BuildingGroundShadow", "Polygon2D", true, false).is_empty():
			push_error("VISUAL_SMOKE: %s retains a duplicate procedural shadow over A2 baked shadows" % state_name)
			valid = false
		var building_baseline := -INF
		for building_node: Node in main.find_children("WorldArt", "TextureRect", true, false):
			var building_art := building_node as TextureRect
			var asset_id := str(building_art.get_meta("world_asset_id", ""))
			if asset_id.begins_with("dc_"):
				var baseline := float(building_art.get_meta("contact_baseline_y", -1.0))
				if str(building_art.get_meta("shadow_policy", "")) != "integrated_footprint" or str(building_art.get_meta("footprint_policy", "")) != "integrated" or not is_equal_approx(float(building_art.get_meta("grid_center_x", -1.0)), ParkMap.PLOT_SIZE.x * 0.5):
					push_error("VISUAL_SMOKE: building tier escaped the integrated centered-footprint contract: %s" % asset_id)
					valid = false
				if building_baseline > -INF and not is_equal_approx(baseline, building_baseline):
					push_error("VISUAL_SMOKE: building tiers do not share one contact baseline: %s" % asset_id)
					valid = false
				building_baseline = baseline
	if state_name == "campus_dense":
		var junctions := main.find_children("CampusJunction_*", "TextureRect", true, false)
		if not junctions.is_empty():
			push_error("VISUAL_SMOKE: dense campus still inserts disconnected road crosses between compact rows")
			valid = false
		if ParkMap.COLUMN_STEP - ParkMap.PLOT_SIZE.x > 8.0 or ParkMap.ROW_STEP > ParkMap.PLOT_SIZE.y:
			push_error("VISUAL_SMOKE: dense campus escaped the compact two-column grid contract")
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
				if node.has_meta("grid_slot") and float(node.get_meta("lane_clearance", 0.0)) < 20.0:
					push_error("VISUAL_SMOKE: W2 campus prop occupies the protected road band: %s clearance=%.1f" % [node.name, float(node.get_meta("lane_clearance", 0.0))])
					valid = false
				if prop_type == "deco_pylon":
					var pylon_slot := int(node.get_meta("grid_slot", -1))
					var expected_anchor := "left_rear" if pylon_slot % 2 == 0 else "right_rear"
					if str(node.get_meta("deco_anchor_name", "")) != expected_anchor:
						push_error("VISUAL_SMOKE: W2 pylon is not mirrored to its column's outer-rear anchor")
						valid = false
			if node is Button and node.has_meta("grid_slot"):
				grid_slots[int(node.get_meta("grid_slot"))] = true
		var row_slots: Dictionary = {}
		for node: Node in main.find_children("*", "Button", true, false):
			if not node.has_meta("grid_slot"):
				continue
			var row := int(node.get_meta("grid_row", -1))
			if not row_slots.has(row):
				row_slots[row] = []
			(row_slots[row] as Array).append(node)
		for row: int in row_slots:
			var row_nodes: Array = row_slots[row]
			if row_nodes.size() == 2:
				var first := row_nodes[0] as Control
				var second := row_nodes[1] as Control
				if not is_equal_approx(first.position.y, second.position.y) or not is_equal_approx(absf(first.position.x - second.position.x), ParkMap.COLUMN_STEP):
					push_error("VISUAL_SMOKE: campus row %d is not on one strict two-column baseline" % row)
					valid = false
			elif row_nodes.size() == 1:
				var only := row_nodes[0] as Control
				if not bool(only.get_meta("grid_centered", false)) or not is_equal_approx(only.position.x + only.size.x * 0.5, main.park_map.world_size.x * 0.5):
					push_error("VISUAL_SMOKE: lone campus row %d is not centered" % row)
					valid = false
		if not main.find_children("PlotFoundation", "TextureRect", true, false).is_empty():
			push_error("VISUAL_SMOKE: occupied campus still stacks a second non-parallel pad under integrated building plinths")
			valid = false
		if grid_slots.size() != 14:
			push_error("VISUAL_SMOKE: two typed campuses do not expose thirteen owned plots plus one sale slot: %d" % grid_slots.size())
			valid = false
		var campus_switcher := main.find_child("CampusSwitcher", true, false) as Control
		var campus_markers := main.find_children("CampusMarker_*", "PanelContainer", true, false)
		var campus_boundaries := main.find_children("CampusBoundary_*", "PanelContainer", true, false)
		var campus_tabs := main.find_children("CampusTab_*", "Button", true, false)
		var expansion_boundary := main.find_child("CampusBoundary_1", true, false) as PanelContainer
		var active_marker := main.find_child("CampusMarker_1", true, false) as PanelContainer
		var active_marker_label := active_marker.find_child("CampusMarkerLabel", true, false) as Label if active_marker != null else null
		var visible_plot_count := 0
		for plot_node: Node in main.park_map.content.get_children():
			if plot_node is Button and plot_node.has_meta("grid_slot") and (plot_node as Control).visible:
				visible_plot_count += 1
		if campus_switcher == null or not campus_switcher.visible or campus_markers.size() != 2 or campus_boundaries.size() != 2 or campus_tabs.size() != 2 or visible_plot_count != 8:
			push_error("VISUAL_SMOKE: typed campus tabs are not isolating one eight-slot expansion page switcher=%s markers=%d boundaries=%d tabs=%d plots=%d" % [str(campus_switcher != null and campus_switcher.visible), campus_markers.size(), campus_boundaries.size(), campus_tabs.size(), visible_plot_count])
			valid = false
		if expansion_boundary == null or int(expansion_boundary.get_meta("campus_capacity", 0)) != 8 or active_marker_label == null or "+8%" not in active_marker_label.text:
			push_error("VISUAL_SMOKE: expansion page does not disclose its eight-slot boundary and modest +8% land premium")
			valid = false
		if prop_types.size() < 4:
			push_error("VISUAL_SMOKE: dense campus exposes fewer than four environment prop types: %d" % prop_types.size())
			valid = false
		if environment_count > 60:
			push_error("VISUAL_SMOKE: dense campus decoration budget exceeded: %d" % environment_count)
			valid = false
		var edge_fog := main.find_child("WorldEdgeFog", true, false) as TextureRect
		if edge_fog == null or edge_fog.modulate.a < 0.22 or edge_fog.modulate.a > 0.28:
			push_error("VISUAL_SMOKE: world edge fog is missing or outside its breathing range")
			valid = false
	if state_name == "dc_context":
		var contract_hint := main.find_child("ContractPowerHint", true, false) as Label
		var contract_cta := main.find_child("ContractCTA", true, false) as Button
		if contract_hint == null or contract_cta == null or str(contract_cta.get_meta("button_role", "")) == "primary":
			push_error("VISUAL_SMOKE: unpowered context does not explain why contracts are unavailable")
			valid = false
	if state_name in ["dc_context", "dc_context_aging_bottom"]:
		var context_sheet := main.find_child("ContextSheet", true, false) as Control
		var context_scroll := main.find_child("ContextSheetScroll", true, false) as ScrollContainer
		var stage_slot := main.find_child("BoardStageSlot", true, false) as Control
		var board_stage := main.find_child("BoardStage", true, false) as Control
		if context_sheet == null or context_scroll == null or stage_slot == null or board_stage == null:
			push_error("VISUAL_SMOKE: data-center context lacks its safe scroll surface or centered board slot")
			valid = false
		else:
			var sheet_rect := context_sheet.get_global_rect()
			var bottom_gap := viewport_rect.end.y - sheet_rect.end.y
			var required_bottom_gap := float(context_sheet.get_meta("safe_bottom_gutter", 18.0))
			var stage_center_x := board_stage.global_position.x + DatacenterBoard.BOARD_SIZE.x * board_stage.scale.x * 0.5
			var slot_center_x := stage_slot.get_global_rect().get_center().x
			var sheet_center_x := sheet_rect.get_center().x
			if not viewport_rect.encloses(sheet_rect) or bottom_gap + 1.0 < required_bottom_gap:
				push_error("VISUAL_SMOKE: context drawer escapes the viewport or bottom safe gutter rect=%s gap=%.1f required=%.1f" % [sheet_rect, bottom_gap, required_bottom_gap])
				valid = false
			if absf(stage_center_x - slot_center_x) > 1.0 or absf(slot_center_x - sheet_center_x) > 2.0:
				push_error("VISUAL_SMOKE: board is not centered stage=%.1f slot=%.1f sheet=%.1f" % [stage_center_x, slot_center_x, sheet_center_x])
				valid = false
			if context_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED or int(context_scroll.scroll_deadzone) != 12 or not bool(context_scroll.get_meta("touch_scroll_enabled", false)):
				push_error("VISUAL_SMOKE: context drawer is not a phone-safe vertical touch scroller")
				valid = false
		if state_name == "dc_context_aging_bottom":
			var aging_cta := main.find_child("ContractCTA", true, false) as Button
			var aging_bar := context_scroll.get_v_scroll_bar() if context_scroll != null else null
			var at_bottom := aging_bar != null and context_scroll.scroll_vertical >= int(aging_bar.max_value - aging_bar.page) - 1
			if aging_cta == null or not aging_cta.is_visible_in_tree() or not context_scroll.get_global_rect().encloses(aging_cta.get_global_rect()) or not at_bottom:
				push_error("VISUAL_SMOKE: aging context cannot scroll its final CTA fully into view")
				valid = false
	if state_name == "dc_board_unpowered":
		var quick_power := main.find_child("PowerSlot", true, false) as Button
		var unpowered_usage := main.find_child("BoardPowerUsage", true, false) as RichTextLabel
		var unpowered_meter := main.find_child("BoardPowerMeter", true, false) as ProgressBar
		if quick_power == null or not "$600" in quick_power.text or unpowered_usage == null or str(unpowered_usage.get_meta("display_copy", "")) != tr("POWER_UNPOWERED_HINT") or bool(unpowered_usage.get_meta("power_pending", true)) or unpowered_meter == null:
			push_error("VISUAL_SMOKE: unpowered board does not expose the price-disclosed one-tap recovery path")
			valid = false
	if state_name in ["dc_board", "dc_board_overheat", "dc_board_placing", "dc_board_set_bonus"]:
		# Page refreshes remove the outgoing board before queue_free runs. Resolve
		# the top-painted authoritative board and scope all preview assertions to
		# it, rather than counting transient siblings elsewhere in MainView.
		var board := main.call("_visible_datacenter_board", str(main.get("selected_datacenter_id"))) as DatacenterBoard
		var power_meter := main.find_child("BoardPowerMeter", true, false)
		if board == null or power_meter == null:
			push_error("VISUAL_SMOKE: %s lacks the board or power meter" % state_name)
			valid = false
		if main.world_host == null or main.world_host.visible:
			push_error("VISUAL_SMOKE: S1 system board still exposes the world through its safe-area edge")
			valid = false
		var coverage_count := board.find_children("CoolingCoverage_*", "", true, false).size() if board != null else 0
		if coverage_count != 3:
			push_error("VISUAL_SMOKE: %s expected three north-cooler coverage tiles, got %d" % [state_name, coverage_count])
			valid = false
		if state_name in ["dc_board_placing", "dc_board_set_bonus"] and (board == null or board.find_children("PlacementState", "", true, false).size() != 9):
			push_error("VISUAL_SMOKE: placement preview does not classify all nine slots")
			valid = false
		var placement_badges := board.find_children("PlacementState", "PanelContainer", true, false) if board != null else []
		for placement_node: Node in placement_badges:
			var placement_state := str(placement_node.get_meta("placement_state", ""))
			var should_show := placement_state in ["ok", "heat", "power", "set_bonus"]
			if placement_state not in ["ok", "heat", "power", "set_bonus", "locked", "occupied"] or (placement_node as Control).visible != should_show:
				push_error("VISUAL_SMOKE: placement preview state is not semantically visible: %s" % placement_state)
				valid = false
		for symbol_node: Node in board.find_children("PlacementSymbol", "Label", true, false) if board != null else []:
			if (symbol_node as Label).text not in ["✓", "⚡", "♨"]:
				push_error("VISUAL_SMOKE: placement preview uses an illegal text badge %s" % (symbol_node as Label).text)
				valid = false
		if state_name not in ["dc_board_placing", "dc_board_set_bonus"] and not placement_badges.is_empty():
			push_error("VISUAL_SMOKE: non-placement board retains placement badges")
			valid = false
		if state_name == "dc_board_set_bonus":
			var selected_dc := Game.find_datacenter(str(main.get("selected_datacenter_id")))
			var authoritative_members := Rules.set_bonus_slots(selected_dc, DataRepository.get_table("racks"), DataRepository.get_table("attachments"))
			var set_preview_visible := false
			for placement_node: Node in placement_badges:
				set_preview_visible = set_preview_visible or str(placement_node.get_meta("placement_state", "")) == "set_bonus"
			if authoritative_members.count(true) != 3 or board == null or board.find_children("SetBonusLine_*", "Line2D", true, false).size() != 1 or board.find_children("SetBonusBadge_*", "PanelContainer", true, false).size() != 1 or not set_preview_visible:
				push_error("VISUAL_SMOKE: set-bonus board must share one authoritative row, one glow/badge, and a visible completion preview")
				valid = false
		if state_name == "dc_board":
			var compute_neutral_floor := {"rack_compute_t1_active": 0.14, "rack_compute_t1_dark": 0.08, "rack_compute_t2_active": 0.17, "rack_compute_t2_dark": 0.12}
			for compute_asset: String in compute_neutral_floor:
				if float(_asset_palette_metrics(compute_asset).get("bright_neutral_ratio", 0.0)) < float(compute_neutral_floor[compute_asset]):
					push_error("VISUAL_SMOKE: F8 compute rack chassis is too dark for the navy board: %s" % compute_asset)
					valid = false
			var install_timer := main.find_child("RackInstallTimer", true, false) as Control
			var install_progress := main.find_child("TimerProgress", true, false) as ProgressBar
			var install_remaining := main.find_child("TimerRemaining", true, false) as Label
			var timer_parent := install_timer.get_parent() as Control if install_timer != null else null
			var timer_inside := install_timer != null and timer_parent != null and timer_parent.get_global_rect().grow(-4.0).encloses(install_timer.get_global_rect())
			var timer_readout := main.find_child("TimerReadout", true, false) as PanelContainer
			var readout_style := timer_readout.get_theme_stylebox("panel") as StyleBoxFlat if timer_readout != null else null
			if not timer_inside or install_progress == null or install_progress.position.y < 30.0 or install_progress.size.y > 12.0 or install_remaining == null or timer_readout == null or install_remaining.get_parent() != timer_readout or install_remaining.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT or not install_remaining.get_theme_color("font_color").is_equal_approx(Color.WHITE) or install_remaining.get_theme_constant("outline_size") < 3 or readout_style == null or readout_style.bg_color.get_luminance() > 0.18:
				push_error("VISUAL_SMOKE: S2 installing rack timer is not a contained white readout above its progress line")
				valid = false
			var power_usage := main.find_child("BoardPowerUsage", true, false) as RichTextLabel
			var power_copy_valid := false
			if power_usage != null:
				var power_installed := bool(power_usage.get_meta("power_installed", false))
				power_copy_valid = (str(power_usage.get_meta("numeric_usage", "")).contains(" / ") if power_installed else (str(power_usage.get_meta("display_copy", "")) == tr("UNPOWERED") and str(power_usage.get_meta("numeric_usage", "")).is_empty()))
			if not power_copy_valid or power_usage.get_meta("numeric_font", null) != ThemeFactory.font_numeric():
				push_error("VISUAL_SMOKE: B5 board power copy does not match its installed state")
				valid = false
		var installed_cooler := main.find_child("Cooler_north", true, false) as Button
		if installed_cooler == null or installed_cooler.icon != null or installed_cooler.find_children("CoolerArt", "TextureRect", true, false).size() != 1:
			push_error("VISUAL_SMOKE: installed cooler is not rendered by exactly one icon branch")
			valid = false
		var locked_coolers := 0
		for cooler_node: Node in main.find_children("Cooler_*", "Button", true, false):
			if str(cooler_node.get_meta("cooler_state", "")) == "locked":
				locked_coolers += 1
		var selected_dc := Game.find_datacenter(str(main.get("selected_datacenter_id")))
		var selected_building := DataRepository.get_entry("buildings", str(selected_dc.get("building_id", "")))
		var expected_locked_coolers := 4 - int(selected_building.get("cooler_slots", 0))
		if locked_coolers != expected_locked_coolers:
			push_error("VISUAL_SMOKE: board expected %d locked cooler slots, got %d" % [expected_locked_coolers, locked_coolers])
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
				if legend_button == null or str(legend_button.get_meta("button_role", "")) == "primary" or not legend_button.get_theme_color("font_color").is_equal_approx(Color.WHITE):
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
	if state_name == "rare_event_banner":
		var rare_banner := main.find_child("RareEventBanner", true, false) as Control
		var rare_card := main.find_child("MarketEventActive", true, false) as Control
		var rare_badge := main.find_child("RareEventBadge", true, false) as Control
		if rare_banner == null or rare_card == null or rare_badge == null or not bool(rare_card.get_meta("rare_event", false)):
			push_error("VISUAL_SMOKE: rare market state lacks its dedicated banner and rare event-card badge")
			valid = false
	if state_name == "tech":
		if main.find_children("EraNode_*", "PanelContainer", true, false).size() != 3 or main.find_child("EraUnlockPreview", true, false) == null or main.find_child("PrestigeProgressBar", true, false) == null:
			push_error("VISUAL_SMOKE: tech page lacks the three-era route or prestige progress")
			valid = false
		if main.find_child("ConstructionBaysCard", true, false) == null:
			push_error("VISUAL_SMOKE: tech page lacks the Engineering expansion path")
			valid = false
		var affordability_count := 0
		for button_node: Node in main.find_children("*", "Button", true, false):
			if button_node.has_meta("purchase_cost"):
				affordability_count += 1
		if affordability_count < 2:
			push_error("VISUAL_SMOKE: tech upgrades do not share the affordability contract")
			valid = false
		for era_node: Node in main.find_children("EraNode_*", "PanelContainer", true, false):
			if (era_node as Control).custom_minimum_size.x < 138.0:
				push_error("VISUAL_SMOKE: tech era node is too narrow for localized names")
				valid = false
	if state_name == "achievements" and main.find_children("AchievementProgress_*", "ProgressBar", true, false).size() != DataRepository.get_table("achievements").get("items", {}).size():
		push_error("VISUAL_SMOKE: achievement cards do not expose per-goal progress")
		valid = false
	if state_name in ["company_roadmap", "company_collection", "board_specialties"]:
		var segments := main.find_children("Segment_*", "Button", true, false)
		if segments.size() != 4:
			push_error("VISUAL_SMOKE: company navigation must expose four complete tabs")
			valid = false
		for segment_node: Node in segments:
			var segment := segment_node as Button
			if segment.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS or segment.text != segment.tooltip_text or segment.get_theme_constant("outline_size") < 3:
				push_error("VISUAL_SMOKE: company tab is clipped or lacks readable high-contrast text: %s" % segment.name)
				valid = false
	if state_name == "contract_comparison":
		var strategic := main.find_child("Choice_strategic", true, false) as Button
		if strategic == null or bool(strategic.get_meta("choice_available", true)) or strategic.icon != AssetCatalog.texture("ic_lock"):
			push_error("VISUAL_SMOKE: relationship-gated strategic term lacks a visible lock cue")
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
			if resume == null or str(resume.get_meta("button_role", "")) != "primary" or str(resume.get_meta("button_surface", "")) != "procedural":
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
				if str(buy_node.get_meta("button_role", "")) != "primary" or str(buy_node.get_meta("button_surface", "")) != "procedural":
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
		if main.find_children("SettingsChevron", "Label", true, false).size() != 4:
			push_error("VISUAL_SMOKE: settings legal rows lack four chevrons")
			valid = false
		var settings_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		var settings_actions := settings_scroll.find_children("*", "Button", true, false) if settings_scroll != null else []
		var full_surface_scroll := settings_scroll != null and bool(settings_scroll.get_meta("full_surface_touch_scroll", false)) and int(settings_scroll.scroll_deadzone) == 12 and not settings_actions.is_empty()
		for settings_action_node: Node in settings_actions:
			var settings_action := settings_action_node as BaseButton
			full_surface_scroll = full_surface_scroll and settings_action.mouse_filter == Control.MOUSE_FILTER_PASS and settings_action.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE and bool(settings_action.get_meta("scroll_drag_passthrough", false))
		if not full_surface_scroll:
			push_error("VISUAL_SMOKE: settings does not route its complete interactive surface through the touch scroller")
			valid = false
	if state_name == "attributions_view":
		var attribution_body := main.find_child("LegalDocumentBody", true, false) as RichTextLabel
		if attribution_body == null or not attribution_body.text.contains("Godot Engine") or not attribution_body.text.contains("FreeType") or not attribution_body.text.contains("zlib"):
			push_error("VISUAL_SMOKE: attribution reader does not expose the complete engine component notices")
			valid = false
	if state_name == "offline_reward":
		if main.find_child("OfflineRewardCard", true, false) == null or main.find_child("OfflineCoinPile", true, false) == null or main.find_child("OfflineDoubleButton", true, false) == null:
			push_error("VISUAL_SMOKE: offline reward lacks animated earnings art or primary ×2 placement")
			valid = false
		var credit_copy := main.find_child("OfflineCreditCopy", true, false) as Label
		if credit_copy == null or credit_copy.text.contains("12.8"):
			push_error("VISUAL_SMOKE: offline reward repeats a final amount while the headline is still rolling")
			valid = false
		var settled_income := main.find_child("OfflineIncome", true, false) as Label
		if settled_income == null or settled_income.text != "$%s" % Game.format_number(12840.0):
			push_error("VISUAL_SMOKE: offline reward amount was captured before its number roll settled")
			valid = false
	if state_name == "arrears":
		var crisis_nodes := [main.find_child("ArrearsBanner", true, false), main.find_child("ArrearsVignette", true, false), main.find_child("ArrearsProgress", true, false), main.find_child("ArrearsRescueButton", true, false), main.find_child("ArrearsCloseButton", true, false)]
		if crisis_nodes.any(func(node: Variant) -> bool: return node == null):
			push_error("VISUAL_SMOKE: arrears state lacks its persistent crisis HUD nodes=%s" % str(crisis_nodes))
			valid = false
		else:
			var arrears_banner := crisis_nodes[0] as PanelContainer
			var arrears_progress := crisis_nodes[2] as ProgressBar
			var arrears_button := crisis_nodes[3] as Button
			var arrears_close := crisis_nodes[4] as Button
			var shell_header := main.find_child("ShellHeader", true, false) as Control
			var banner_rect := arrears_banner.get_global_rect().grow(1.0)
			var content_fits := banner_rect.encloses(arrears_progress.get_global_rect()) and banner_rect.encloses(arrears_button.get_global_rect())
			var clears_hud := shell_header == null or not arrears_banner.get_global_rect().intersects(shell_header.get_global_rect())
			var crisis_style := arrears_banner.get_theme_stylebox("panel") as StyleBoxFlat
			var crisis_is_opaque := crisis_style != null and crisis_style.bg_color.a >= 0.95
			if arrears_banner.size.y + 1.0 < arrears_banner.get_combined_minimum_size().y or arrears_progress.size.y < 40.0 or arrears_button.text != tr("ARREARS_RESCUE") or arrears_close.custom_minimum_size.x < ThemeMaker.TOUCH_MIN or not content_fits or not clears_hud or not crisis_is_opaque:
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
	if state_name == "bank_takeover":
		var stat_count := main.find_children("BankTakeoverStat_*", "", true, false).size()
		var sold_list := main.find_child("BankTakeoverSoldList", true, false)
		if main.find_child("BankTakeoverCard", true, false) == null or stat_count != 4 or main.find_child("BankTakeoverContinue", true, false) == null or sold_list == null or sold_list.get_child_count() != 2:
			push_error("VISUAL_SMOKE: bank settlement lacks retained-assets stats or sold-center details stats=%d sold=%s" % [stat_count, str(sold_list)])
			valid = false
		var takeover_title := main.find_child("BankTakeoverTitle", true, false) as Label
		var takeover_body := main.find_child("BankTakeoverBody", true, false) as Label
		var takeover_continue := main.find_child("BankTakeoverContinue", true, false) as Button
		if takeover_title == null or takeover_title.get_theme_font_size("font_size") < 44 or takeover_body == null or takeover_continue == null or takeover_continue.get_theme_font_size("font_size") != 28 or takeover_continue.get_theme_constant("outline_size") < 4:
			push_error("VISUAL_SMOKE: bank settlement title/continue hierarchy is below the P1 contract")
			valid = false
		var readable_labels: Array[Label] = [takeover_title, takeover_body]
		for contrast_node: Node in main.find_children("BankTakeoverStat*", "Label", true, false):
			readable_labels.append(contrast_node as Label)
		for contrast_node: Node in main.find_children("BankTakeoverSold*", "Label", true, false):
			readable_labels.append(contrast_node as Label)
		for readable: Label in readable_labels:
			if readable == null or readable.get_theme_color("font_color").get_luminance() < 0.52:
				push_error("VISUAL_SMOKE: bank settlement text is too dark on its navy panel: %s color=%s" % [readable.name if readable != null else "missing", readable.get_theme_color("font_color") if readable != null else Color.TRANSPARENT])
				valid = false
	valid = _typography_and_touch_are_safe(main, state_name) and valid
	valid = _typography_roles_are_valid(main, state_name) and valid
	valid = _close_glyphs_are_readable(main, state_name) and valid
	valid = _viewport_bounded_surfaces_are_safe(main, state_name) and valid
	valid = _text_is_within_clipping_ancestors(main, state_name) and valid
	valid = _sibling_labels_do_not_overlap(main, state_name) and valid
	valid = _panel_content_is_not_compressed(main, state_name) and valid
	valid = _button_text_contrast_is_safe(main, state_name) and valid
	return valid

func _close_glyphs_are_readable(main: Node, state_name: String) -> bool:
	var valid := true
	for node: Node in main.find_children("*", "Button", true, false):
		var close := node as Button
		if close == null or not close.is_visible_in_tree() or not close.has_meta("large_close_glyph"):
			continue
		if close.text != "×" or close.get_theme_font_size("font_size") < ThemeFactory.TYPE_SCALE.display or close.get_theme_font("font") != ThemeFactory.font_bold() or not bool(close.get_meta("large_close_glyph", false)):
			push_error("VISUAL_SMOKE: %s close button glyph is not the shared large bold ×" % state_name)
			valid = false
	return valid

func _viewport_bounded_surfaces_are_safe(main: Node, state_name: String) -> bool:
	var viewport_rect := get_viewport().get_visible_rect().grow(1.0)
	var valid := true
	for node: Node in main.find_children("*", "", true, false):
		if not node is Control or not node.has_meta("viewport_bounded_surface"):
			continue
		var surface := node as Control
		if not surface.is_visible_in_tree():
			continue
		var surface_rect := surface.get_global_rect()
		if not viewport_rect.encloses(surface_rect):
			push_error("VISUAL_SMOKE: %s viewport-bounded surface escapes the phone: %s rect=%s viewport=%s" % [state_name, surface.name, surface_rect, viewport_rect])
			valid = false
	if state_name in ["dc_board", "dc_board_overheat", "dc_board_placing", "dc_board_set_bonus", "dc_board_unpowered"]:
		var board_stage := main.find_child("BoardStage", true, false) as Control
		var page_scroll := main.find_child("PageScroll", true, false) as ScrollContainer
		if board_stage == null or page_scroll == null:
			push_error("VISUAL_SMOKE: %s cannot verify responsive board containment" % state_name)
			valid = false
		else:
			var visual_footprint: Vector2 = board_stage.get_meta("visual_footprint", Vector2.ZERO)
			if visual_footprint.x > page_scroll.size.x + 1.0 or visual_footprint.y > board_stage.size.y + 1.0:
				push_error("VISUAL_SMOKE: %s board footprint exceeds its page slot footprint=%s scroll=%s stage=%s" % [state_name, visual_footprint, page_scroll.size, board_stage.size])
				valid = false
	return valid

func _asset_palette_metrics(asset_id: String) -> Dictionary:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return {}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {}
	# E1 scene textures are intentionally VRAM-compressed.  Palette assertions
	# still inspect the decoded pixels; sampling a compressed Image directly
	# emits one error per pixel and returns meaningless black values.
	if image.is_compressed() and image.decompress() != OK:
		push_error("VISUAL_SMOKE: unable to decode texture for palette audit: %s" % asset_id)
		return {}
	var visible := 0
	var bright_neutral := 0
	var blue := 0
	var gold := 0
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y).linear_to_srgb()
			if color.a <= 0.5:
				continue
			visible += 1
			var high := maxf(color.r, maxf(color.g, color.b))
			var low := minf(color.r, minf(color.g, color.b))
			if high > 0.68 and high - low < 0.25:
				bright_neutral += 1
			if color.b > color.r * 1.15 and color.b > color.g * 0.85:
				blue += 1
			if color.r > 0.70 and color.g > 0.35 and color.b < color.r * 0.65:
				gold += 1
	if visible == 0:
		return {}
	return {
		"bright_neutral_ratio": float(bright_neutral) / float(visible),
		"blue_ratio": float(blue) / float(visible),
		"gold_ratio": float(gold) / float(visible),
		"used_aspect": float(image.get_used_rect().size.x) / maxf(1.0, float(image.get_used_rect().size.y)),
	}

func _page_right_edge_is_solid(main: Node, image: Image) -> bool:
	var page_host := main.find_child("PageHost", true, false) as Control
	if page_host == null or image == null or image.is_empty():
		push_error("VISUAL_SMOKE: S1 cannot sample the PageHost right edge")
		return false
	var viewport_rect := get_viewport().get_visible_rect()
	var scale := Vector2(
		float(image.get_width()) / maxf(1.0, viewport_rect.size.x),
		float(image.get_height()) / maxf(1.0, viewport_rect.size.y)
	)
	var page_rect := page_host.get_global_rect()
	var sample_x := clampi(int(round((page_rect.end.x - 2.0) * scale.x)), 0, image.get_width() - 1)
	var first_y := int(round((page_rect.position.y + page_rect.size.y * 0.20) * scale.y))
	var last_y := int(round((page_rect.position.y + page_rect.size.y * 0.80) * scale.y))
	for pixel_y: int in range(first_y, last_y + 1, maxi(1, (last_y - first_y) / 24)):
		var color := image.get_pixel(sample_x, clampi(pixel_y, 0, image.get_height() - 1)).linear_to_srgb()
		var panel_like := color.b > color.r * 1.15 and color.b >= color.g * 0.88 and maxf(color.r, maxf(color.g, color.b)) > 0.10
		if not panel_like:
			push_error("VISUAL_SMOKE: S1 PageHost right edge exposes non-panel pixel at y=%d color=%s" % [pixel_y, str(color)])
			return false
	return true

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
			if scroll_ancestor is ScrollContainer and (scroll_ancestor as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
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
		if button == null or not button.is_visible_in_tree():
			continue
		# Surface validation includes icon-only and custom-content buttons such as
		# the world CTA; these have empty native text but must never escape back to
		# a stretched raster skin.
		var normal_style := button.get_theme_stylebox("normal")
		if normal_style is StyleBoxTexture:
			push_error("VISUAL_SMOKE: %s button still stretches a raster surface: %s" % [state_name, button.name])
			valid = false
		if button.text.is_empty():
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
		var procedural_primary := str(button.get_meta("button_surface", "")) == "procedural" and str(button.get_meta("button_role", "")) == "primary" and not button.text.contains("\n")
		if procedural_primary and (button.get_theme_font_size("font_size") != 28 or not font_color.is_equal_approx(Color.WHITE) or outline_size < 4 or button.get_theme_constant("shadow_offset_y") < 2 or not normal_style is StyleBoxFlat):
			push_error("VISUAL_SMOKE: %s procedural CTA violates the 28u white/4px/shadow contract: %s" % [state_name, button.name])
			valid = false
		if procedural_primary:
			for state_color: String in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				if not button.get_theme_color(state_color).is_equal_approx(Color.WHITE):
					push_error("VISUAL_SMOKE: %s primary CTA %s uses gray state text %s=%s" % [state_name, button.name, state_color, button.get_theme_color(state_color)])
					valid = false
			var primary_style := normal_style as StyleBoxFlat
			if primary_style == null or primary_style.corner_radius_top_left != 22 or primary_style.get_border_width(SIDE_TOP) != 2:
				push_error("VISUAL_SMOKE: %s primary CTA %s does not use the shared 22u procedural surface" % [state_name, button.name])
				valid = false
	return valid

func _typography_and_touch_are_safe(main: Node, state_name: String) -> bool:
	var valid := true
	var physical_scale := minf(float(preview_size.x) / LOGICAL_SIZE.x, float(preview_size.y) / LOGICAL_SIZE.y)
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
		if button == null or not button.is_visible_in_tree():
			continue
		# A disabled control is a silent dead end on touch devices. Restricted
		# gameplay actions must stay tappable and surface their localized reason.
		if button.disabled:
			push_error("VISUAL_SMOKE: %s contains silently disabled action %s" % [state_name, button.name])
			valid = false
			continue
		var minimum_touch := 64.0 if button.toggle_mode else 88.0
		if button.size.x + 1.0 < minimum_touch or button.size.y + 1.0 < minimum_touch:
			push_error("VISUAL_SMOKE: %s undersized touch target %s size=%s" % [state_name, button.name, button.size])
			valid = false
		var physical_touch := minf(button.size.x, button.size.y) * physical_scale
		if physical_touch + 1.0 < 44.0:
			push_error("VISUAL_SMOKE: %s %s touch target falls below 44pt in %s (%.1f)" % [state_name, button.name, capture_profile, physical_touch])
			valid = false
	return valid

func _typography_roles_are_valid(main: Node, state_name: String) -> bool:
	var valid := true
	for node: Node in main.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.has_meta("typography_role"):
			continue
		var role := str(control.get_meta("typography_role", "body"))
		var expected := ThemeFactory.font_regular()
		match role:
			"display": expected = ThemeFactory.font_display()
			"title", "button": expected = ThemeFactory.font_bold()
			"numeric": expected = ThemeFactory.font_numeric()
			"world": expected = ThemeFactory.font_world_heavy()
		if control.get_theme_font("font") != expected:
			push_error("VISUAL_SMOKE: %s typography role %s resolved to the wrong font on %s" % [state_name, role, control.name])
			valid = false
	return valid
