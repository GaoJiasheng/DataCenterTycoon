extends Node

const Rules := preload("res://gameplay/game_rules.gd")
const Market := preload("res://gameplay/market_system.gd")
const MAIN_SCENE := preload("res://main.tscn")

var passed := 0
var failed := 0

func _ready() -> void:
	await get_tree().process_frame
	_run_data_tests()
	await _run_asset_integration_tests()
	AudioService.apply_settings({"music_enabled": false, "sfx_enabled": false})
	await _run_ui_refresh_test()
	_run_rule_tests()
	_run_gameplay_optimization_tests()
	_run_initial_state_test()
	_run_core_loop_test()
	_run_construction_controls_test()
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
	_expect(DataRepository.get_table("events").get("items", {}).size() == 16, "market includes the four network-gated major contracts")
	_expect(Monetization.is_product_available("noads") and Monetization.localized_price("noads", "") == "US$ 5.99", "mock StoreKit catalog exposes localized product prices")

func _run_asset_integration_tests() -> void:
	var art_items: Dictionary = AssetCatalog.manifest.get("items", {})
	var art_loads := art_items.size() == 134
	for item: Dictionary in art_items.values():
		var path := str(item.get("path", ""))
		art_loads = art_loads and ResourceLoader.exists(path) and load(path) is Texture2D
	_expect(art_loads, "all 134 production textures import and load")
	var audio_items: Dictionary = AudioService.manifest.get("items", {})
	var audio_loads := audio_items.size() == 16
	for cue_id: String in audio_items:
		audio_loads = audio_loads and AudioService._load_stream(cue_id) != null
	_expect(audio_loads, "all 16 production audio cues import and load")
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
	var campus_grid_ok := is_equal_approx(left_top.y, right_top.y) and is_equal_approx(left_bottom.y, right_bottom.y) and right_top.x - left_top.x >= ParkMap.PLOT_SIZE.x and is_equal_approx(next_sale.x, (804.0 - ParkMap.PLOT_SIZE.x) * 0.5) and next_sale.y > left_bottom.y
	_expect(campus_grid_ok, "campus parcels share row baselines and the expansion parcel stays centered")
	park_map.queue_free()
	await get_tree().process_frame

func _run_ui_refresh_test() -> void:
	Game.reset_for_tests()
	Game.last_offline_report = {}
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
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
	var overlay := main.find_child("ActionSheetOverlay", true, false) as CanvasItem
	var drag_handle := main.find_child("SheetDragHandle", true, false) as Control
	var sheet_routes_ok: bool = overlay != null and drag_handle != null and drag_handle.size.y >= 88.0 and not overlay.gui_input.get_connections().is_empty() and not drag_handle.gui_input.get_connections().is_empty()
	_expect(sheet_routes_ok, "action sheet exposes backdrop and 44pt drag-dismiss input routes")
	main.call("_dismiss_action_sheet", overlay)
	await get_tree().create_timer(0.24).timeout
	_expect(not is_instance_valid(overlay), "action sheet dismissal waits for its exit animation before freeing")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _run_rule_tests() -> void:
	var economy: Dictionary = DataRepository.get_table("economy")
	_expect(is_equal_approx(Rules.land_price(2, economy), 775.0), "second plot price follows formula")
	_expect(is_equal_approx(Rules.land_price(5, economy), 2886.0), "fifth plot price follows formula")
	_expect(is_equal_approx(Rules.aging_efficiency(0.75), 0.85), "aging efficiency interpolates")
	_expect(is_equal_approx(Rules.aging_efficiency(0.95), 0.55), "decline efficiency interpolates")
	var ambient_dc := {"power_unit": "power_t1", "coolers": {}, "racks": [null, null, null, null, {"rack_id": "rack_storage_t1", "status": "active"}, null, null, null, null]}
	var ambient_status: Dictionary = Rules.rack_runtime_status(ambient_dc, 4, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_expect(not bool(ambient_status.get("overheated", true)), "ambient cooling keeps a center storage rack healthy")
	var future := GameClock.wall_time() + 100
	_expect(bool(GameClock.elapsed_since(future, future).get("rollback", false)), "wall-clock rollback is rejected")
	_expect(int(SaveManager.migrate({"save_version": 0}).get("save_version", 0)) == SaveManager.SAVE_VERSION, "legacy save migrates to current schema")

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
	_expect(Game.sign_contract(dc["id"], "internet").get("ok", false), "contract starts a fixed initial term")
	var term_end := float(dc.get("contract_end_at", 0.0))
	var renewal_report := Game.advance_time(term_end - Game.simulation_time(), false)
	_expect(float(dc.get("renewal_window_end_at", 0.0)) == term_end + 7200.0 and Game.contract_switch_fee(dc["id"], "mining") == 0.0 and not renewal_report.get("contracts", []).is_empty(), "term expiry opens and reports a one-month free-switch renewal window")
	var cash_before_switch := float(Game.state["player"]["cash"])
	_expect(Game.sign_contract(dc["id"], "mining").get("ok", false) and is_equal_approx(float(Game.state["player"]["cash"]), cash_before_switch), "switching clients during renewal does not charge a breach fee")
	Game.sign_contract(dc["id"], "internet")
	term_end = float(dc.get("contract_end_at", 0.0))
	Game.advance_time(term_end + 7200.0 - Game.simulation_time(), false)
	_expect(not dc.has("renewal_window_end_at") and float(dc.get("contract_end_at", 0.0)) > Game.simulation_time(), "an unused renewal window automatically renews the contract")

func _test_datacenter(id: String, building_id: String) -> Dictionary:
	var racks: Array = []
	racks.resize(9)
	racks.fill(null)
	return {"id": id, "building_id": building_id, "status": "operational", "built_at": Game.simulation_time(), "power_unit": "", "coolers": {}, "racks": racks, "customer_id": "", "contract_end_at": 0.0, "aging_notices": []}

func _run_initial_state_test() -> void:
	Game.reset_for_tests()
	_expect(is_equal_approx(float(Game.state["player"]["cash"]), 40000.0), "new company starts with tuned cash")
	_expect(int(Game.state["player"]["gems"]) == 20, "new company starts with documented gems")
	_expect(Game.state["plots"].size() == 1 and is_equal_approx(Game.next_plot_price(), 775.0), "new company starts with one free plot")

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
	_expect(is_equal_approx(Game.datacenter_monthly_income(dc), 216.0 * Game.market_multiplier("internet")), "two cooled compute racks earn documented income")
	_expect(Game.contract_switch_fee(dc["id"], "mining") >= 25.0, "contract switch exposes the breach fee before confirmation")
	var runtime: Dictionary = Rules.rack_runtime_status(dc, 0, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_expect(bool(runtime.get("powered", false)) and not bool(runtime.get("overheated", true)), "north cooler covers north rack")
	var cash_before := float(Game.state["player"]["cash"])
	Game.advance_time(7200.0, false)
	_expect(float(Game.state["player"]["total_revenue"]) > 200.0, "one month accrues contract revenue")
	_expect(float(Game.state["player"]["cash"]) < cash_before + 216.1, "maintenance is deducted at month boundary")

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
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active"}
	_expect(not bool(Game.retire_datacenter(dc["id"]).get("ok", true)), "ruin cannot be retired for salvage value")
	_expect(not bool(Game.uninstall_rack(dc["id"], 0).get("ok", true)), "rack cannot be salvaged from a ruin")

func _run_bankruptcy_test() -> void:
	Game.reset_for_tests()
	Game.state["bankruptcy"] = {"status": "arrears", "debt": 100.0, "arrears_online_seconds": 21599.0, "rescue_uses": 0, "rescue_day": -1}
	Game.state["player"]["cash"] = 0.0
	Game.advance_time(2.0, false)
	_expect(Game.state["bankruptcy"]["status"] == "game_over", "arrears timeout causes game over")

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
