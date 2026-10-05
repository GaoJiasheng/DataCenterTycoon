extends Node

const MAIN_SCENE := preload("res://main.tscn")
const DutyLogScene := preload("res://ui/duty_log.gd")
var failures := 0

func _ready() -> void:
	if get_parent() == get_tree().root:
		await run_k1()
		await run_k23()
		await run_k4()
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

func run_k4() -> void:
	Game.reset_for_tests()
	Game.set_process(false)
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["era"] = 3
	Game.state["flags"]["last_presented_era"] = 3
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	Game.state["market"]["previews"] = [{"event_id": "sovereign_ai", "start_at": Game.simulation_time() + 1.0}]
	Game.advance_time(2.0, true)
	check(main.find_child("RareEventOverlay", true, false) == null and not Game.processing_offline, "K4 offline rare start does not replay a headline and restores signal context")
	Game.state["market"]["previews"] = [{"event_id": "compute_famine", "start_at": Game.simulation_time() + 1.0}]
	Game.advance_time(2.0, false)
	await get_tree().process_frame
	var rare: Node = main.find_child("RareEventOverlay", true, false)
	check(rare != null, "K4 the actual online market signal opens a rare headline")
	var rare_ref: WeakRef = weakref(rare)
	var button := main.find_child("RareEventConfirm", true, false) as Button
	check(button != null and button.visible and not button.disabled, "K4 headline is immediately skippable")
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(rare_ref.get_ref() == null, "K4 skipped rare headline releases its entire tree")
	var cash := float(Game.state["player"]["cash"])
	var rng: Variant = Game.state["market"]["rng_state"]
	main.call("_show_ipo_ceremony", Game.company_legacy_summary())
	var ipo: Node = main.find_child("IPOCeremony", true, false)
	var ipo_ref: WeakRef = weakref(ipo)
	var confetti: Node = ipo.find_child("IPOConfetti", true, false)
	var confetti_ref: WeakRef = weakref(confetti)
	check(ipo.find_children("IPOConfetti", "", true, false).size() == 1, "K4 ceremony creates exactly one confetti set")
	await get_tree().create_timer(1.7).timeout
	check(confetti_ref.get_ref() == null, "K4 confetti self-destructs while the ceremony remains open")
	(main.find_child("IPOConfirm", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(ipo_ref.get_ref() == null and main.find_child("IPOConfetti", true, false) == null, "K4 closed ceremony leaves no overlay or FX nodes")
	main.call("_show_ipo_ceremony", Game.company_legacy_summary())
	var early_fx: WeakRef = weakref(main.find_child("IPOConfetti", true, false))
	(main.find_child("IPOConfirm", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(early_fx.get_ref() == null, "K4 skipping early also destroys confetti immediately")
	check(Game.state["player"]["cash"] == cash and Game.state["market"]["rng_state"] == rng, "K4 presentation consumes no cash or random stream")
	main.queue_free()
	await get_tree().process_frame
	Game.set_process(true)

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run_k23() -> void:
	Game.reset_for_tests()
	Game.set_process(false)
	AudioService.apply_settings({"music_enabled": false, "sfx_enabled": false})
	var counters := ["strategic_contracts_signed", "rare_events_locked", "datacenters_built_t2", "datacenters_built_t3", "max_set_groups_in_one_datacenter", "inquiries_declined", "liquid_cooling_installed"]
	for key: String in counters:
		check(int(Game.state["stats"].get(key, -1)) == 0, "K2 new statistic starts at zero: " + key)
	Game.state["stats"].clear()
	Game._ensure_state_shape()
	for key: String in counters:
		check(int(Game.state["stats"].get(key, -1)) == 0, "K2 old saves backfill statistic: " + key)
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["cash"] = 1000000.0
	Game.state["player"]["era"] = 3
	Game.state["player"]["network_level"] = 4
	Game.start_datacenter_construction("plot_1", "dc_t2")
	check(Game.state["stats"]["datacenters_built_t2"] == 0, "K2 starting a shell does not count a completed tier")
	Game.advance_time(15000.0, false)
	check(Game.state["stats"]["datacenters_built_t2"] == 1 and Game.state["stats"]["datacenters_built_t3"] == 0, "K2 completing T2 counts only T2")
	Game.buy_next_plot()
	Game.start_datacenter_construction("plot_2", "dc_t3")
	Game.advance_time(float(DataRepository.get_entry("buildings", "dc_t3").get("build_seconds")) + 1.0, false)
	check(Game.state["stats"]["datacenters_built_t3"] == 1, "K2 completing T3 counts T3")
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var id := str(dc["id"])
	dc["power_unit"] = "power_t3"
	Game.state["meta"]["customer_service_seconds"]["internet"] = 43200.0
	Game.sign_contract(id, "internet", "standard")
	check(Game.state["stats"]["strategic_contracts_signed"] == 0, "K2 a standard contract does not count as strategic")
	Game.sign_contract(id, "internet", "strategic")
	Game.sign_contract(id, "internet", "strategic")
	check(Game.state["stats"]["strategic_contracts_signed"] == 1, "K2 only a real strategic signing increments; unchanged taps do not")
	var now := Game.simulation_time()
	Game.state["market"]["active"] = [{"event_id": "sovereign_ai", "started_at": now + 1.0, "end_at": now + 7200.0}]
	Game.sign_contract(id, "internet", "flexible")
	check(Game.state["stats"]["rare_events_locked"] == 0, "K2 a future rare event is not in the lock input")
	Game.state["market"]["active"][0]["started_at"] = now
	Game.sign_contract(id, "internet", "standard")
	check(Game.state["stats"]["rare_events_locked"] == 1 and Game._meta_metric("distinct_rare_events_locked") == 1.0, "K2 signing in an active rare event records one lock and its identity")
	Game.state["market"]["active"] = []
	Game.install_cooler(id, "north", "cool_liquid_t1")
	check(Game.state["stats"]["liquid_cooling_installed"] == 0, "K2 installing is not yet liquid cooling completed")
	Game.advance_time(3601.0, false)
	check(Game.state["stats"]["liquid_cooling_installed"] == 1, "K2 liquid cooling counts on completion")
	for edge: String in ["north", "south", "east", "west"]: dc["coolers"][edge] = "cool_liquid_t2"
	for slot: int in range(9):
		dc["racks"][slot] = {"rack_id": ["rack_compute_t1", "rack_storage_t1", "rack_gpu_t1"][slot / 3], "status": "installing", "enabled": true}
	Game._check_achievements()
	check(Game.state["stats"]["max_set_groups_in_one_datacenter"] == 0, "K2 incomplete racks do not form counted sets")
	for installed: Dictionary in dc["racks"]: installed["status"] = "active"
	Game._check_achievements()
	check(Game.state["stats"]["max_set_groups_in_one_datacenter"] == 3, "K2 three different completed rows count three groups in one facility")
	Game.state["inquiries"]["open"] = [{"id": "decline_probe", "template_id": "hosting_overflow", "slot": 0}]
	Game.decline_inquiry("missing")
	check(Game.state["stats"]["inquiries_declined"] == 0, "K2 unavailable inquiry does not count as declined")
	Game.decline_inquiry("decline_probe")
	check(Game.state["stats"]["inquiries_declined"] == 1, "K2 an actual decline counts once")
	check(DataRepository.get_table("achievements").get("items", {}).size() >= 20, "K2 at least twenty achievements are authored")
	var old_locale := TranslationServer.get_locale()
	var migrated := SaveManager.migrate({"save_version": 4, "settings": {"locale": "en"}})
	check(migrated["save_version"] == 5 and migrated["company_name"] == "Northstar Networks" and TranslationServer.get_locale() == old_locale, "K3 v4 migration fills localized name and preserves runtime locale")
	var kept := SaveManager.migrate({"save_version": 5, "company_name": "Atlas Data"})
	check(kept["company_name"] == "Atlas Data", "K3 v5 migration preserves the chosen name")
	var cash := float(Game.state["player"]["cash"])
	var market_rng: Variant = Game.state["market"]["rng_state"]
	check(not Game.rename_company(-1, 0).get("ok", true), "K3 naming rejects words outside the library")
	check(Game.rename_company(15, 15).get("ok", false) and float(Game.state["player"]["cash"]) == cash and Game.state["market"]["rng_state"] == market_rng, "K3 a word-library rename costs no cash and consumes no market randomness")
	Game.state["company_name_confirmed"] = false
	Game.state["tutorial"]["completed"] = false
	Game.state["flags"]["last_presented_era"] = 3
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.call("_show_first_encounter_if_needed")
	check(main.find_child("CompanyNaming", true, false) == null, "K3 tutorial never opens company naming")
	Game.state["tutorial"]["completed"] = true
	main.call("_show_first_encounter_if_needed")
	await get_tree().process_frame
	var naming := main.find_child("CompanyNaming", true, false)
	check(naming != null and naming.find_children("CompanyWord_*", "OptionButton", true, false).size() == 2 and not (naming.find_child("CompanyWord_prefixes", true, false) as OptionButton).get_popup().allow_search and not (naming.find_child("CompanyWord_suffixes", true, false) as OptionButton).get_popup().allow_search, "K3 first naming uses two word selectors, never free text")
	check(main.park_map.campus_cat == null or not main.park_map.campus_cat.visible, "K3 cat waits for the first company name")
	var confirm := naming.find_child("CompanyNameConfirm", true, false) as Button
	confirm.pressed.emit()
	await get_tree().create_timer(0.4).timeout
	check(bool(Game.state["company_name_confirmed"]) and main.find_child("CompanyNaming", true, false) == null, "K3 confirmation enters the named company")
	var campaign := preload("res://tests/full_campaign.gd").new()
	campaign.main = main
	await campaign._verify_milestone_density()
	check(campaign.failures.is_empty(), "K2 reference days 12–19 receive three new milestones through Game")
	for note: String in campaign.milestones: print(note)
	campaign.free()
	main.queue_free()
	await get_tree().process_frame
	Game.set_process(true)
