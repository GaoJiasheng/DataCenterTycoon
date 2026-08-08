extends Node

# Mid-game interaction audit: builds a developed save (tutorial done, several
# operating datacenters) and walks the daily-loop moments a returning player
# actually lives in — fault repair, contract renewal, market events, retirement
# decisions, offline return. Assertions make it suitable for CI and screenshots
# remain available for manual visual review:
#   godot --headless --path . tests/midgame_audit.tscn
const MAIN_SCENE := preload("res://main.tscn")
const OUT := "/tmp/dct_mid_"

var main: Node
var failures: Array[String] = []

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(990, 2151))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	_build_developed_state()
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _shot("m0_daily_map_overview")
	_assert_building_variants()
	# --- fault flow ---
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var dc_id := str(dc.get("id", ""))
	dc["racks"][0]["status"] = "faulted"
	dc["racks"][0]["fault_at"] = -1.0
	EventBus.rack_fault_occurred.emit(dc_id, 0)
	main.call("_refresh")
	await _shot("m1_fault_on_map")
	_assert_alert_badge("fault", "fault", true)
	_assert_operations_fault_tone()
	main.call("_open_datacenter", dc_id)
	await _shot("m1_fault_drawer")
	main.call("_show_rack_actions", dc_id, 0)
	await _shot("m1_fault_actions_sheet")
	_assert_fault_action_quotes()
	_close("ActionSheetOverlay")
	Game.dispatch_repair(dc_id, 0)
	await _shot("m1_fault_repairing")
	_close("DatacenterContext")
	# --- automatic renewal and saved free-switch flow ---
	var dc2: Dictionary = Game.state["plots"][1]["datacenter"]
	var dc2_id := str(dc2.get("id", ""))
	dc2["contract_end_at"] = Game.simulation_time() + 43200.0
	dc2["free_switch_available"] = true
	EventBus.contract_auto_renewed.emit(dc2_id, str(dc2.get("customer_id", "")), dc2["contract_end_at"])
	main.call("_refresh")
	await _shot("m2_renewal_on_map")
	_assert_alert_badge("contract", "contract", false)
	main.call("_open_datacenter", dc2_id)
	await _shot("m2_renewal_drawer")
	_assert_renewal_drawer(dc2)
	var renewal_cta := main.find_child("ContractCTA", true, false) as Button
	var renewal_copy_before := renewal_cta.text if renewal_cta != null else ""
	Game.advance_time(60.0, false)
	main.call("_refresh")
	await get_tree().process_frame
	_expect(renewal_cta != null and renewal_cta.text == renewal_copy_before and bool(dc2.get("free_switch_available", false)), "M4 free-switch eligibility must remain visible without a countdown")
	_close("DatacenterContext")
	await get_tree().process_frame
	main.call("_on_world_alert_selected", dc2_id, "contract", -1)
	await _shot("m2_renewal_direct_contracts")
	_assert_contract_deep_link(dc2_id)
	main.call("_navigate", "map")
	await get_tree().process_frame
	# The task center must aggregate simultaneous actionable work and make every
	# row a direct route rather than another informational dead end.
	dc["racks"][1]["status"] = "faulted"
	dc["racks"][1]["fault_at"] = -1.0
	main.call("_refresh")
	main.call("_show_operations_hub")
	await _shot("m2_task_center")
	_assert_task_center(2)
	var fault_task := main.find_child("TaskAction_fault_mid_dc_0_1", true, false) as Button
	if fault_task != null:
		fault_task.pressed.emit()
		await get_tree().create_timer(0.4).timeout
	_expect(main.find_child("ActionSheetOverlay", true, false) != null, "M2 fault task must deep-link to its repair action sheet")
	_close("ActionSheetOverlay")
	_close("OperationsHub")
	dc["racks"][1]["status"] = "active"
	dc["racks"][1]["fault_at"] = -1.0
	main.call("_navigate", "map")
	await get_tree().process_frame
	# The free switch remains visible through the task-center test, then returns to a
	# normal term so the same mining site can surface its market benefit badge.
	dc2["contract_end_at"] = Game.simulation_time() + 20000.0
	dc2["free_switch_available"] = false
	# --- market event flow ---
	Game.state["market"]["active"] = [{"event_id": "coin_boom", "start_at": Game.simulation_time() - 600.0, "end_at": Game.simulation_time() + 13800.0}]
	EventBus.market_event_started.emit("coin_boom")
	main.call("_refresh")
	await _shot("m3_event_banner_map")
	_assert_no_context_free_coin_fx()
	_assert_alert_badge("market", "market", false)
	main.call("_on_world_alert_selected", dc2_id, "market", -1)
	await _shot("m3_event_benefit_drawer")
	_assert_market_benefit_drawer("coin_boom", 2.5)
	_close("DatacenterContext")
	await get_tree().process_frame
	await _assert_market_banner_route_and_swipe()
	main.call("_navigate", "market")
	await _shot("m3_event_market_page")
	main.call("_navigate", "map")
	# --- aging / retirement decision ---
	var dc3: Dictionary = Game.state["plots"][2]["datacenter"]
	var buildings: Dictionary = DataRepository.get_table("buildings")
	var lifespan := float(buildings.get("items", {}).get(str(dc3.get("building_id", "")), {}).get("lifespan_seconds", 432000.0))
	dc3["built_at"] = Game.simulation_time() - lifespan * 0.87
	Game.advance_time(1.0, false)
	main.call("_refresh")
	await _shot("m4_aging_on_map")
	_assert_alert_badge("retire", "retire", false)
	main.call("_open_datacenter", str(dc3.get("id", "")))
	await _shot("m4_aging_drawer_decision")
	_assert_retirement_decision(dc3)
	_close("DatacenterContext")
	# --- offline return ---
	dc["racks"][1]["status"] = "faulted"
	dc["racks"][1]["fault_at"] = -1.0
	Game.last_offline_report = {"elapsed_seconds": 21600.0, "credited_seconds": 21600.0, "income": 5200.0, "balance_before": 20800.0, "completed": [], "faults": [{"datacenter_id": dc_id, "slot": 1}], "events": [{"type": "event_started", "event_id": "coin_boom"}], "aging": [{"datacenter_id": str(dc3.get("id", "")), "stage": "aging"}]}
	main.call("_show_offline_dialog", Game.last_offline_report)
	await _shot("m5_offline_return")
	_assert_offline_routes()
	var major_offline := main.find_child("OfflineOverlay", true, false)
	_expect(major_offline != null and bool(major_offline.get_meta("confetti_enabled", false)) and main.find_child("EraConfetti", true, false) != null, "M10 offline celebration must remain for income above twenty percent of the previous balance")
	var fault_route := main.find_child("OfflineEvent_fault", true, false) as Button
	if fault_route != null:
		fault_route.pressed.emit()
		await get_tree().create_timer(0.32).timeout
	_expect(main.find_child("OfflineOverlay", true, false) == null and main.find_child("ActionSheetOverlay", true, false) != null, "M9 fault milestone must close offline summary and deep-link to repair choices")
	_close("ActionSheetOverlay")
	_close("OfflineOverlay")
	main.call("_show_offline_dialog", {"elapsed_seconds": 21600.0, "credited_seconds": 21600.0, "income": 100.0, "balance_before": 26000.0, "completed": [], "faults": [], "events": [], "aging": []})
	await _shot("m5_offline_modest_no_confetti")
	var modest_offline := main.find_child("OfflineOverlay", true, false)
	_expect(modest_offline != null and not bool(modest_offline.get_meta("confetti_enabled", true)) and modest_offline.find_child("EraConfetti", true, false) == null, "M10 routine offline income must not spray confetti")
	_close("OfflineOverlay")
	# --- era 2 progress moment (mid raise toward next goal) ---
	main.call("_navigate", "tech")
	await _shot("m6_tech_progress")
	AudioService.stop_all()
	if failures.is_empty():
		print("MIDGAME_AUDIT: PASS -> %s*.png" % OUT)
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("MIDGAME_AUDIT: %s" % failure)
		print("MIDGAME_AUDIT: FAIL (%d assertion(s))" % failures.size())
		get_tree().quit(1)

func _build_developed_state() -> void:
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 26000.0
	Game.state["player"]["total_revenue"] = 41000.0
	var now := Game.simulation_time()
	for index: int in range(4):
		if index >= 1:
			Game.state["plots"].append({"id": "plot_%d" % (index + 1), "index": index + 1, "purchase_price": 775.0, "purchased": true, "status": "empty", "datacenter": null})
	var configs := [
		{"building": "dc_t1", "power": "power_t2", "customer": "internet", "racks": ["rack_compute_t1", "rack_compute_t1", "rack_storage_t1"], "age": 0.25},
		{"building": "dc_t1", "power": "power_t2", "customer": "mining", "racks": ["rack_compute_t1", "rack_compute_t1"], "age": 0.45},
		{"building": "dc_t1", "power": "power_t1", "customer": "internet", "racks": ["rack_compute_t1", "rack_storage_t1"], "age": 0.1},
		{"building": "dc_t0", "power": "power_t1", "customer": "internet", "racks": ["rack_compute_t1"], "age": 0.3},
	]
	for index: int in range(configs.size()):
		var config: Dictionary = configs[index]
		var racks: Array = []
		racks.resize(9)
		racks.fill(null)
		var rack_list: Array = config["racks"]
		for slot: int in range(rack_list.size()):
			racks[slot] = {"rack_id": rack_list[slot], "status": "active", "installed_at": now, "fault_at": -1.0, "enabled": true}
		var lifespan := float(DataRepository.get_table("buildings").get("items", {}).get(config["building"], {}).get("lifespan_seconds", 432000.0))
		Game.state["plots"][index]["datacenter"] = {
			"id": "mid_dc_%d" % index,
			"building_id": config["building"],
			"status": "operational",
			"built_at": now - lifespan * float(config["age"]),
			"power_unit": config["power"],
			"coolers": {"north": "cool_air_t1"},
			"racks": racks,
			"customer_id": config["customer"],
			"contract_end_at": now + 20000.0,
			"aging_notices": [],
		}
		Game.state["plots"][index]["status"] = "operational"
	Game.state["player"]["total_datacenters_built"] = 5

func _close(node_name: String) -> void:
	var overlay := main.find_child(node_name, true, false)
	if overlay != null:
		overlay.queue_free()

func _alert_badge(alert_type: String) -> PanelContainer:
	for node: Node in main.find_children("StatusBadge", "PanelContainer", true, false):
		if str(node.get_meta("alert_type", "")) == alert_type:
			return node as PanelContainer
	return null

func _assert_building_variants() -> void:
	var seen: Dictionary = {}
	for node: Node in main.find_children("WorldArt", "TextureRect", true, false):
		var art := node as TextureRect
		if art == null or str(art.get_meta("world_asset_id", "")) != "dc_t1_active":
			continue
		seen[int(art.get_meta("building_variant", -1))] = {
			"flip": art.flip_h,
			"hue": float(art.get_meta("hue_shift_degrees", 0.0)),
			"material": art.material,
		}
	_expect(seen.has(0) and seen.has(1), "M12 repeated same-tier buildings must alternate between two stable presentation variants")
	if seen.has(0) and seen.has(1):
		var first: Dictionary = seen[0]
		var second: Dictionary = seen[1]
		_expect(bool(first.get("flip", false)) != bool(second.get("flip", false)) and absf(float(first.get("hue", 0.0)) - float(second.get("hue", 0.0))) >= 9.9 and first.get("material") is ShaderMaterial and second.get("material") is ShaderMaterial, "M12 variants must combine mirroring with a subtle ten-degree hue spread")

func _assert_alert_badge(alert_type: String, expected_tone: String, breathing: bool) -> void:
	var badge := _alert_badge(alert_type)
	_expect(badge != null, "M1 %s world alert badge must exist" % alert_type)
	if badge == null:
		return
	var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
	_expect(str(badge.get_meta("alert_tone", "")) == expected_tone, "M1 %s badge must expose its semantic tone" % alert_type)
	_expect(bool(badge.get_meta("breathing", false)) == breathing, "M1 only urgent fault badges should breathe (%s)" % alert_type)
	_expect(style != null and style.bg_color != Color("14283d"), "M1 %s badge must use a semantic fill instead of the generic navy fill" % alert_type)

func _assert_operations_fault_tone() -> void:
	var badge := main.find_child("Badge", true, false) as PanelContainer
	_expect(badge != null and badge.visible, "M1 a fault must surface on the operations HUD badge")
	if badge != null:
		var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(str(badge.get_meta("attention_tone", "")) == "fault" and style != null and style.bg_color.r > style.bg_color.g, "M1 fault attention must turn the operations badge red")

func _assert_fault_action_quotes() -> void:
	var repair := main.find_child("Choice_repair", true, false) as Button
	var ad := main.find_child("Choice_ad", true, false) as Button
	var gems := main.find_child("Choice_gems", true, false) as Button
	var dismantle := main.find_child("Choice_uninstall", true, false) as Button
	_expect(repair != null and repair.text.contains("$") and (repair.text.contains("约") or repair.text.to_lower().contains("about")), "M3 repair action must disclose cash cost and approximate duration")
	_expect(ad != null and ad.text.contains("/") and (ad.text.contains("立即") or ad.text.to_lower().contains("now")), "M3 rewarded repair must disclose immediacy and quota")
	_expect(gems != null and (gems.text.contains("钻石") or gems.text.to_lower().contains("gem")), "M3 instant repair must disclose its gem cost")
	_expect(dismantle != null and dismantle.text.contains("$") and (dismantle.text.contains("回收") or dismantle.text.to_lower().contains("recover")), "M3 rack removal must disclose its recovery value and avoid data-center retirement wording")

func _assert_no_context_free_coin_fx() -> void:
	var fx := main.find_child("FxLayer", true, false)
	var found_coin := false
	if fx != null:
		for child: Node in fx.get_children():
			if str(child.get_meta("fx_asset_id", "")) == "fx_coin":
				found_coin = true
	_expect(not found_coin, "M7 coin_boom must not leave a context-free giant coin in the world")

func _assert_market_benefit_drawer(event_id: String, multiplier: float) -> void:
	var label := main.find_child("MarketBenefitStatus", true, false) as Label
	var event := DataRepository.get_entry("events", event_id)
	_expect(label != null and label.visible and label.text.contains(tr(event.get("name_key", ""))), "M8 benefited data-center drawer must name the active event")
	_expect(label != null and is_equal_approx(float(label.get_meta("market_multiplier", 1.0)), multiplier) and label.text.contains("×%.1f" % multiplier), "M8 drawer must disclose the exact active income multiplier")
	_expect(label != null and (label.text.contains("剩") or label.text.to_lower().contains("left")), "M8 drawer benefit feedback must include a live remaining-time cue")

func _assert_market_banner_route_and_swipe() -> void:
	var banner := main.find_child("MarketEventBanner", true, false) as Button
	_expect(banner != null and str(banner.get_meta("destination", "")) == "market", "M11 event banner must explicitly route to the market page")
	_expect(banner != null and bool(banner.get_meta("swipe_dismiss_enabled", false)) and not banner.gui_input.get_connections().is_empty(), "M11 event banner must expose a connected right-swipe dismiss gesture")
	if banner == null:
		return
	main.call("_dismiss_market_banner", banner)
	await get_tree().create_timer(0.3).timeout
	_expect(not is_instance_valid(banner), "M11 dismissed event banner must leave the scene instead of blocking the map")

func _assert_retirement_decision(dc: Dictionary) -> void:
	var button := main.find_child("RetireButton", true, false) as Button
	var tradeoff := main.find_child("RetireTradeoff", true, false) as Label
	var monthly := Game.format_number(Game.datacenter_monthly_income(dc))
	_expect(button != null and bool(button.get_meta("warning_active", false)) and float(button.get_meta("retirement_progress", 0.0)) >= 0.87, "M6 retirement CTA must switch to warning priority at the 87% decision point")
	_expect(tradeoff != null and tradeoff.text.contains(monthly) and (tradeoff.text.contains("更高") or tradeoff.text.to_lower().contains("better")), "M6 retirement decision must disclose that retiring beats ruin and show current monthly income")

func _assert_offline_routes() -> void:
	for route_type: String in ["fault", "market", "aging"]:
		var row := main.find_child("OfflineEvent_%s" % route_type, true, false) as Button
		_expect(row != null and str(row.get_meta("offline_action", "")) == route_type and not row.pressed.get_connections().is_empty(), "M9 offline %s milestone must be a connected one-tap route" % route_type)

func _assert_renewal_drawer(dc: Dictionary) -> void:
	var cta := main.find_child("ContractCTA", true, false) as Button
	var status := main.find_child("DatacenterStatus", true, false) as Label
	var customer := DataRepository.get_entry("customers", str(dc.get("customer_id", "")))
	var customer_name := tr(customer.get("name_key", "CONTRACT_NONE"))
	_expect(cta != null and bool(cta.get_meta("renewal_active", false)) and (cta.text.contains("免费") or cta.text.to_lower().contains("free")), "M4 renewal drawer CTA must be gold and explicitly say free switching")
	_expect(cta != null and bool(cta.get_meta("free_switch_available", false)), "M4 renewal CTA must carry non-expiring free-switch eligibility")
	_expect(status != null and status.text.contains(customer_name), "M5 drawer header must identify the current client")

func _assert_contract_deep_link(datacenter_id: String) -> void:
	var expected_card := main.find_child("Contract_%s" % str(Game.find_datacenter(datacenter_id).get("customer_id", "")), true, false)
	_expect(str(main.get("active_page")) == "detail" and str(main.get("_detail_focus")) == "contracts" and expected_card != null, "M4 renewal world badge must deep-link straight to the contract tab")

func _assert_task_center(expected_count: int) -> void:
	var hub := main.find_child("OperationsHub", true, false)
	var list := main.find_child("OperationsTaskList", true, false) as VBoxContainer
	var operations := main.find_child("OperationsButton", true, false) as Button
	var badge := operations.find_child("Badge", true, false) as PanelContainer if operations != null else null
	var badge_value := badge.find_child("BadgeValue", true, false) as Label if badge != null else null
	_expect(hub != null and list != null and list.get_child_count() == expected_count, "M2 task center must aggregate every actionable fault and renewal")
	_expect(badge_value != null and int(badge_value.text) == expected_count and str(badge.get_meta("attention_tone", "")) == "fault", "M2 operations badge must equal actionable count and stay red while a fault exists")
	if list != null:
		for row: Node in list.get_children():
			var task_id := str(row.get_meta("task_id", "")).replace(":", "_")
			var action := main.find_child("TaskAction_%s" % task_id, true, false) as Button
			_expect(action != null and not action.pressed.get_connections().is_empty(), "M2 task %s must expose a connected one-tap action" % task_id)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MIDGAME_ASSERT: PASS %s" % message)
		return
	failures.append(message)

func _shot(shot_name: String) -> bool:
	main.call("_refresh")
	for _i in range(4):
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s%s.png" % [OUT, shot_name])
	print("MID_AUDIT: %s" % shot_name)
	return true
