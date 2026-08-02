extends Node

const Rules := preload("res://gameplay/game_rules.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	await get_tree().process_frame
	_run_data_tests()
	await _run_asset_integration_tests()
	AudioService.apply_settings({"music_enabled": false, "sfx_enabled": false})
	_run_rule_tests()
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
	_expect(DataRepository.get_table("events").get("items", {}).size() == 12, "market has twelve documented events")
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
		button_layout_ok = plot_button.icon != null and plot_button.get_theme_constant("icon_max_width") == 150
	_expect(button_layout_ok, "production map art renders through Godot 4.7 button layout")
	park_map.queue_free()
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
