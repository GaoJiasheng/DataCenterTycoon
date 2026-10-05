extends Node

const MAIN_SCENE := preload("res://main.tscn")
const DutyLogScene := preload("res://ui/duty_log.gd")
var failures := 0

func _ready() -> void:
	if get_parent() == get_tree().root:
		await run_k1()
		print("VISIBLE_DECISIONS: %d failures" % failures)
		AudioService.stop_all()
		get_tree().quit(1 if failures else 0)

func run_k1() -> void:
	Game.reset_for_tests()
	Game.set_process(false)
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 1000000.0
	Game.start_datacenter_construction("plot_1", "dc_t1")
	Game.advance_time(3601.0, false)
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var dc_id := str(dc["id"])
	dc["power_unit"] = "power_t1"
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true, "fault_at": -1.0}
	Game.sign_contract(dc_id, "mining")
	var now := Game.simulation_time()
	Game.state["market"]["active"] = [{"event_id": "mining_crash", "started_at": now, "end_at": now + 43200.0}]
	dc["contract_end_at"] = now
	var predicted := Game.contract_renewal_forecast(dc_id)
	var report := {"contracts": [], "events": [], "income": 0.0}
	Game._process_contract_renewals(now, report)
	var renewed: Dictionary = report["contracts"][0]
	check(float(renewed.get("locked_rate", -1.0)) == predicted and is_equal_approx(predicted, 0.2), "K1 forecast equals the real same-tick renewal exactly")
	check(float(renewed.get("baseline_rate", 0.0)) == 1.0, "K1 renewal records the era baseline separately")
	Game.state["market"]["active"] = []
	var rows := DutyLogScene.compose(report, Game.data, Game.state)
	check(rows[0]["type"] == "contract_low_lock" and "#1" in rows[0]["text"] and tr("EVENT_MINING_CRASH") in rows[0]["text"] and "0.20" in rows[0]["text"], "K1 low-lock log retains room event and rate after the event ends")
	check(rows == DutyLogScene.compose(report, Game.data, Game.state), "K1 composing the same report remains deterministic")
	for index: int in [2, 3]:
		var item := renewed.duplicate(true)
		item["plot_index"] = index
		report["contracts"].append(item)
	var normal := renewed.duplicate(true)
	normal["locked_rate"] = 1.0
	report["contracts"].append(normal)
	rows = DutyLogScene.compose(report, Game.data, Game.state)
	var lows := 0
	var normals := 0
	for row: Dictionary in rows:
		if row["type"] == "contract_low_lock":
			lows += 1
			check("#1" in row["text"] and "#2" in row["text"] and "#3" in row["text"], "K1 aggregate names every low renewal")
		if row["type"] == "contract": normals += 1
	check(lows == 1 and normals == 1, "K1 three low renewals form one row and normal renewal stays separate")
	dc["locked_market_multiplier"] = 1.0 / 1.10
	check(Game.free_switch_opportunities().has(dc_id), "K1 improvement equal to configured threshold is actionable")
	dc["locked_market_multiplier"] = 1.0 / 1.099
	check(not Game.free_switch_opportunities().has(dc_id), "K1 below-threshold improvement is not actionable")
	dc["locked_market_multiplier"] = 0.2
	dc["free_switch_available"] = false
	check(Game.free_switch_opportunities().is_empty(), "K1 an improved rate without a free switch is not actionable")
	dc["free_switch_available"] = true
	Game.state["flags"]["last_presented_era"] = 1
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_show_datacenter_context", dc_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var context := main.find_child("DatacenterContext", true, false)
	var board := context.find_child("DatacenterBoard", true, false)
	var slot := board.find_child("RackSlot0", true, false) as Control
	var forecast := context.find_child("ContractRenewalForecast", true, false) as Label
	var held := InputEventScreenTouch.new()
	held.index = 0
	held.pressed = true
	held.position = slot.get_global_rect().get_center()
	slot.gui_input.emit(held)
	check(board.get("_press_started").has(0), "K1 fixture holds the actual rack input slot")
	var identities := [context.get_instance_id(), board.get_instance_id(), slot.get_instance_id(), forecast.get_instance_id()]
	for index: int in range(10):
		Game.state["market"]["active"] = [{"event_id": "coin_boom", "started_at": now, "end_at": now + 7200.0 + index * 100.0}]
		main.call("_refresh_live_page")
		await get_tree().process_frame
	check(identities == [main.find_child("DatacenterContext", true, false).get_instance_id(), context.find_child("DatacenterBoard", true, false).get_instance_id(), board.find_child("RackSlot0", true, false).get_instance_id(), context.find_child("ContractRenewalForecast", true, false).get_instance_id()], "K1 ten live updates retain drawer board touched slot and Label identities")
	check(board.get("_press_started").has(0), "K1 ten live updates preserve the held touch state")
	check(float(forecast.get_meta("forecast_rate")) == Game.contract_renewal_forecast(dc_id), "K1 existing forecast Label tracks the authoritative current-time value")
	held.pressed = false
	slot.gui_input.emit(held)
	main.queue_free()
	await get_tree().process_frame
	Game.set_process(true)

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
