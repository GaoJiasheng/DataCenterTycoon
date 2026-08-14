extends Node

# Full-campaign soak: plays a whole run from a fresh save, month by month, with
# the real UI mounted and refreshing the entire time. tutorial_playthrough
# proves the first ninety seconds; this proves the game a beta tester actually
# keeps playing — expansion, cooling, faults, renewals, retirement, era
# unlocks, prestige — never dead-ends, desyncs, lies, or crashes.
#   godot --headless --path . tests/full_campaign.tscn
const MAIN_SCENE := preload("res://main.tscn")
const Rules := preload("res://gameplay/game_rules.gd")
const OUT := "/tmp/dct_camp_"
const MAX_MONTHS := 400
const RACK_ORDER := ["rack_gpu_t2", "rack_compute_t2", "rack_storage_t2", "rack_gpu_t1", "rack_compute_t1", "rack_storage_t1"]

var main: Node
var failures: Array[String] = []
var milestones: Array[String] = []
var _shot_index := 0
var _month := 0
var _month_seconds := 7200.0
var _era_overlays_seen := 0

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(990, 2151))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	_month_seconds = float(DataRepository.get_table("economy").get("time", {}).get("real_seconds_per_game_month", 7200.0))
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _settle()
	await _finish_tutorial_fast()
	await _shot("a_tutorial_done")
	await _run_campaign()
	await _verify_offline_return()
	await _verify_prestige()
	AudioService.stop_all()
	for note: String in milestones:
		print("CAMPAIGN: . %s" % note)
	if failures.is_empty():
		print("CAMPAIGN: PASS -> %s*.png" % OUT)
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("CAMPAIGN: %s" % failure)
		print("CAMPAIGN: FAIL (%d issue(s))" % failures.size())
		get_tree().quit(1)

# The tutorial has its own harness; here it only has to leave the world in the
# state a real player carries forward into the loop below.
func _finish_tutorial_fast() -> void:
	_expect(bool(Game.start_datacenter_construction("plot_1", "dc_t0").get("ok", false)), "the opening build must be affordable from a fresh save")
	Game.advance_time(600.0, false)
	var dc_id := _first_datacenter_id()
	_expect(not dc_id.is_empty(), "the tutorial build must produce a data center")
	Game.install_power(dc_id, "power_t1")
	Game.install_cooler(dc_id, "north", "cool_air_t1")
	Game.advance_time(600.0, false)
	Game.install_rack(dc_id, 0, "rack_compute_t1")
	Game.advance_time(600.0, false)
	Game.sign_contract(dc_id, "internet")
	Game.state["tutorial"]["completed"] = true
	main.call("_refresh")
	await _settle()
	_expect(Game.monthly_income() > 0.0, "a kitted-out data center under contract must earn something")

func _run_campaign() -> void:
	var seen := {2: false, 3: false}
	var handled_fault := false
	var handled_renewal := false
	var handled_inquiry := false
	var retired := false
	for month: int in range(MAX_MONTHS):
		_month = month + 1
		for _slice: int in range(4):
			Game.advance_time(_month_seconds * 0.25, false)
			await get_tree().process_frame
		main.call("_refresh")
		await get_tree().process_frame
		_assert_invariants()
		await _dismiss_modals()
		if not handled_fault:
			handled_fault = await _handle_any_fault()
			if handled_fault:
				_note("month %d: repaired a fault through the rack sheet" % _month)
				await _shot("b_fault_repaired")
		if not handled_renewal:
			handled_renewal = await _handle_any_renewal()
			if handled_renewal:
				_note("month %d: used a saved free switch after automatic renewal" % _month)
		retired = _play_one_month() or retired
		if not handled_inquiry:
			handled_inquiry = _handle_any_inquiry()
			if handled_inquiry:
				_note("month %d: accepted a persistent inquiry at its exact displayed premium" % _month)
		main.call("_refresh")
		await get_tree().process_frame
		if _month % 12 == 0:
			var live := 0
			for plot: Dictionary in Game.state.get("plots", []):
				if plot.get("datacenter") is Dictionary and str((plot["datacenter"] as Dictionary).get("status", "")) == "operational":
					live += 1
			print("CAMPAIGN: year %d — era %d, built %d, live %d/%d, cash $%s, income $%s/mo, upkeep $%s/mo, revenue $%s" % [
				_month / 12, int(Game.state["player"].get("era", 1)), int(Game.state["player"].get("total_datacenters_built", 0)),
				live, Game.state.get("plots", []).size(), Game.format_number(_cash()), Game.format_number(Game.monthly_income()),
				Game.format_number(Game.monthly_maintenance()), Game.format_number(float(Game.state["player"].get("total_revenue", 0.0))),
			])
		var era := int(Game.state["player"].get("era", 1))
		for milestone: int in [2, 3]:
			if era >= milestone and not bool(seen[milestone]):
				seen[milestone] = true
				_note("month %d: era %d (cumulative revenue $%s, net worth $%s)" % [_month, milestone, Game.format_number(float(Game.state["player"].get("total_revenue", 0.0))), Game.format_number(Game.net_worth())])
				await _shot("c_era%d_announcement" % milestone)
				await _dismiss_modals()
				await _shot("c_era%d_world" % milestone)
		if bool(seen[3]) and int(Game.state["player"].get("total_datacenters_built", 0)) >= _prestige_minimum():
			_note("month %d: %d data centers built, prestige unlocked" % [_month, int(Game.state["player"].get("total_datacenters_built", 0))])
			break
	_expect(bool(seen[2]), "a played campaign must reach era 2 within %d game months" % MAX_MONTHS)
	_expect(bool(seen[3]), "a played campaign must reach era 3 within %d game months" % MAX_MONTHS)
	_expect(handled_fault, "no fault ever surfaced across the whole campaign — the repair loop is unreachable")
	_expect(handled_renewal, "no automatic renewal or free-switch opportunity ever surfaced — the contract loop is unreachable")
	_expect(handled_inquiry, "no eligible persistent inquiry was accepted across the whole campaign")
	_expect(retired, "no site ever became old enough to retire — the rebuild loop is unreachable")
	_expect(str(Game.state.get("bankruptcy", {}).get("status", "normal")) in ["normal", "arrears"], "a reasonably played campaign never enters an unreachable failure state")
	_expect(_era_overlays_seen >= 2, "both era unlocks must announce themselves (saw %d)" % _era_overlays_seen)
	_verify_construction_bays_in_run()
	await _tour_pages()

func _verify_construction_bays_in_run() -> void:
	# Let any natural campaign work finish, then use the earned late-game cash to
	# exercise the same three-lane path a solvent Era-2+ player can purchase.
	Game.advance_time(43200.0, false)
	while _empty_plot_ids().size() < 3 and _cash() >= Game.next_plot_price():
		if not bool(Game.buy_next_plot().get("ok", false)):
			break
	var upgrade := Game.purchase_construction_bays()
	_expect(bool(upgrade.get("ok", false)) and Game.queue_capacity() == 3, "a cash-rich campaign must be able to expand Engineering to three lanes")
	var started := 0
	for plot_id: String in _empty_plot_ids():
		if started >= 3:
			break
		if bool(Game.start_datacenter_construction(plot_id, "dc_t1").get("ok", false)):
			started += 1
	_expect(started == 3 and Game.state.get("construction_queue", []).size() == 3, "engineering expansion must run three real construction projects concurrently")
	_note("month %d: Engineering expanded to %d lanes and admitted %d concurrent projects" % [_month, Game.queue_capacity(), started])

func _empty_plot_ids() -> Array[String]:
	var result: Array[String] = []
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("status", "")) == "empty":
			result.append(str(plot.get("id", "")))
	return result

# Buy land, build, kit out, retire, upgrade — the loop a tester repeats.
# Returns true if anything was retired this month.
func _play_one_month() -> bool:
	var retired := false
	var empty_plots := 0
	# Repairs first: a faulted rack earns nothing and paying for it is always
	# cheaper than the income it is losing.
	_repair_faults()
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			if str(plot.get("status", "")) == "empty":
				empty_plots += 1
			continue
		var entry: Dictionary = dc
		var dc_id := str(entry.get("id", ""))
		match str(entry.get("status", "")):
			"ruined":
				Game.demolish_ruin(dc_id)
			"operational":
				# Retire just before the site ruins itself; a ruin refunds nothing
				# and costs money to clear.
				if _age_progress(entry) >= 0.92 and bool(Game.retire_datacenter(dc_id).get("ok", false)):
					retired = true
				else:
					_operate(dc_id, entry)
	# In arrears the priority is digging out, not spending.
	if str(Game.state.get("bankruptcy", {}).get("status", "normal")) != "normal":
		return retired
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("status", "")) == "empty" and _build_on(str(plot.get("id", ""))):
			empty_plots -= 1
	# Only expand once the land already owned is working and paid for itself.
	if empty_plots <= 0 and _spare_cash() > Game.next_plot_price() * 3.0:
		Game.buy_next_plot()
	_upgrade_network()
	return retired

# Cash a player would consider free to spend: what is left after keeping a
# year of upkeep in the bank.
func _spare_cash() -> float:
	return _cash() - Game.monthly_maintenance() * 12.0

func _repair_faults() -> void:
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var racks: Array = (dc as Dictionary).get("racks", [])
		for slot: int in range(racks.size()):
			if racks[slot] is Dictionary and str((racks[slot] as Dictionary).get("status", "")) == "faulted":
				Game.dispatch_repair(str((dc as Dictionary).get("id", "")), slot)

# A player does not start a shell they cannot fit out — an empty building is
# pure upkeep. Budget the whole site before breaking ground.
func _build_on(plot_id: String) -> bool:
	for building_id: String in ["dc_t3", "dc_t2", "dc_t1", "dc_t0"]:
		var building := DataRepository.get_entry("buildings", building_id)
		if building.is_empty() or not Game.is_unlocked(building):
			continue
		if _spare_cash() < _fit_out_estimate(building):
			continue
		if bool(Game.start_datacenter_construction(plot_id, building_id).get("ok", false)):
			return true
	return false

# The cheapest kit that makes a site earn: the shell, entry-level power, one
# cooler and enough racks to fill what that cooler covers. Everything above
# that gets bought later out of the site's own income.
func _fit_out_estimate(building: Dictionary) -> float:
	return float(building.get("cost", 0.0)) \
		+ float(DataRepository.get_entry("attachments", "power_t1").get("cost", 0.0)) \
		+ float(DataRepository.get_entry("attachments", "cool_air_t1").get("cost", 0.0)) \
		+ 300.0 * 3.0

func _operate(dc_id: String, dc: Dictionary) -> void:
	_ensure_cooling(dc_id, dc)
	_ensure_power(dc_id, dc)
	_ensure_racks(dc_id, dc)
	_ensure_contract(dc_id, dc)

# Buys headroom only when there is a slot waiting to use it — an oversized
# transformer earns nothing, and an unpowered rack is money set on fire.
func _ensure_power(dc_id: String, dc: Dictionary) -> void:
	var current := DataRepository.get_entry("attachments", str(dc.get("power_unit", "")))
	if float(current.get("capacity", 0.0)) >= _planned_demand(dc):
		return
	for power_id: String in ["power_t1", "power_t2", "power_t3"]:
		var item := DataRepository.get_entry("attachments", power_id)
		if item.is_empty() or not Game.is_unlocked(item) or int(item.get("tier", 0)) <= int(current.get("tier", 0)):
			continue
		if _spare_cash() < float(item.get("cost", 0.0)):
			continue
		if bool(Game.install_power(dc_id, power_id).get("ok", false)):
			return

# What the site would draw once every unlocked slot holds the best rack its
# cooling can carry.
func _planned_demand(dc: Dictionary) -> float:
	var total := 0.0
	var racks: Array = dc.get("racks", [])
	for raw_slot: Variant in DataRepository.get_entry("buildings", str(dc.get("building_id", ""))).get("unlocked_slots", []):
		var slot := int(raw_slot)
		if slot < racks.size() and racks[slot] is Dictionary:
			total += float(DataRepository.get_entry("racks", str((racks[slot] as Dictionary).get("rack_id", ""))).get("power", 0.0))
			continue
		var wanted := _rack_for_slot(dc, slot)
		if not wanted.is_empty():
			total += float(DataRepository.get_entry("racks", wanted).get("power", 0.0))
	return total

func _rack_for_slot(dc: Dictionary, slot: int) -> String:
	var cooling := Rules.cooling_at(dc, slot, DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	for rack_id: String in RACK_ORDER:
		var rack := DataRepository.get_entry("racks", rack_id)
		if not rack.is_empty() and Game.is_unlocked(rack) and float(rack.get("heat", 0.0)) <= cooling:
			return rack_id
	return ""

func _ensure_cooling(dc_id: String, dc: Dictionary) -> void:
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var coolers: Dictionary = dc.get("coolers", {})
	for edge: String in ["north", "west", "east", "south"]:
		if coolers.size() >= int(building.get("cooler_slots", 0)) and not coolers.has(edge):
			continue
		var current := DataRepository.get_entry("attachments", str(coolers.get(edge, "")))
		for cooler_id: String in ["cool_liquid_t2", "cool_liquid_t1", "cool_air_t2", "cool_air_t1"]:
			var item := DataRepository.get_entry("attachments", cooler_id)
			if item.is_empty() or not Game.is_unlocked(item) or int(item.get("tier", 0)) <= int(current.get("tier", 0)):
				continue
			if int(item.get("requires_building_tier", 0)) > int(building.get("tier", 0)):
				continue
			if _spare_cash() < float(item.get("cost", 0.0)):
				continue
			if bool(Game.install_cooler(dc_id, edge, cooler_id).get("ok", false)):
				return

# Fills empty slots with the best rack the slot's cooling can carry and the
# transformer can actually feed. An overheating rack earns half; an unpowered
# one earns nothing at all.
func _ensure_racks(dc_id: String, dc: Dictionary) -> void:
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var racks: Array = dc.get("racks", [])
	var headroom := float(DataRepository.get_entry("attachments", str(dc.get("power_unit", ""))).get("capacity", 0.0))
	for installed: Variant in racks:
		if installed is Dictionary:
			headroom -= float(DataRepository.get_entry("racks", str((installed as Dictionary).get("rack_id", ""))).get("power", 0.0))
	for raw_slot: Variant in building.get("unlocked_slots", []):
		var slot := int(raw_slot)
		if slot >= racks.size() or racks[slot] != null:
			continue
		var rack_id := _rack_for_slot(dc, slot)
		if rack_id.is_empty():
			continue
		var rack := DataRepository.get_entry("racks", rack_id)
		if float(rack.get("power", 0.0)) > headroom or _spare_cash() < Game.rack_purchase_cost(rack_id):
			continue
		if bool(Game.install_rack(dc_id, slot, rack_id).get("ok", false)):
			headroom -= float(rack.get("power", 0.0))

func _ensure_contract(dc_id: String, dc: Dictionary) -> void:
	var current := str(dc.get("customer_id", ""))
	var best := _best_customer(dc)
	if best.is_empty() or best == current:
		return
	# Existing terms stay locked. Rebalance only on first signing or when an
	# automatic renewal has banked a non-expiring free switch.
	if current.is_empty() or bool(dc.get("free_switch_available", false)):
		Game.sign_contract(dc_id, best)

func _best_customer(dc: Dictionary) -> String:
	var best := ""
	var best_income := -1.0
	var probe: Dictionary = dc.duplicate(true)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		if not Game.is_unlocked(customer) or int(customer.get("minimum_network_level", 1)) > int(Game.state["player"].get("network_level", 1)):
			continue
		probe["customer_id"] = customer_id
		probe["locked_market_multiplier"] = Game.contract_market_multiplier(customer_id)
		var income := Game.datacenter_monthly_income(probe)
		if income > best_income:
			best_income = income
			best = customer_id
	return best

func _upgrade_network() -> void:
	var next_level := int(Game.state["player"].get("network_level", 1)) + 1
	var level: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(next_level), {})
	if level.is_empty() or not Game.is_unlocked(level):
		return
	if _spare_cash() > float(level.get("cost", 0.0)) * 2.0:
		Game.upgrade_network()

# Faults must be reachable and repairable through the surfaces a player touches.
func _handle_any_fault() -> bool:
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var entry: Dictionary = dc
		var racks: Array = entry.get("racks", [])
		for slot: int in range(racks.size()):
			if not racks[slot] is Dictionary or str((racks[slot] as Dictionary).get("status", "")) != "faulted":
				continue
			var dc_id := str(entry.get("id", ""))
			main.call("_open_datacenter", dc_id)
			await _settle()
			main.call("_show_rack_actions", dc_id, slot)
			await _settle()
			_expect(main.find_child("ActionSheetOverlay", true, false) != null, "a faulted rack must open its action sheet")
			var repair := main.find_child("Choice_repair", true, false) as Button
			_expect(repair != null, "the action sheet for a faulted rack must offer a cash repair")
			if repair != null:
				_expect(not repair.disabled, "the cash repair option must be usable")
				repair.pressed.emit()
				await _settle()
			_dismiss_overlays()
			var after: Variant = Game.find_datacenter(dc_id).get("racks", [])[slot]
			var status := str((after as Dictionary).get("status", "")) if after is Dictionary else "gone"
			_expect(status in ["repairing", "active"], "repair must move the rack out of 'faulted' (still %s)" % status)
			return true
	return false

func _handle_any_renewal() -> bool:
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var entry: Dictionary = dc
		if not bool(entry.get("free_switch_available", false)):
			continue
		var dc_id := str(entry.get("id", ""))
		main.call("_open_datacenter", dc_id)
		await _settle()
		var cta := main.find_child("ContractCTA", true, false) as Button
		_expect(cta != null, "an open data center must show its contract call to action")
		if cta != null:
			_expect(bool(cta.get_meta("renewal_active", false)), "a saved free switch must be advertised on the contract CTA")
		_dismiss_overlays()
		var target := _best_customer(entry)
		_expect(bool(Game.sign_contract(dc_id, target).get("ok", false)), "using a saved free switch must succeed")
		return true
	return false

func _handle_any_inquiry() -> bool:
	for inquiry: Dictionary in Game.state.get("inquiries", {}).get("open", []):
		var inquiry_id := str(inquiry.get("id", ""))
		for plot: Dictionary in Game.state.get("plots", []):
			var dc: Variant = plot.get("datacenter")
			if not dc is Dictionary or str((dc as Dictionary).get("status", "")) != "operational":
				continue
			var dc_id := str((dc as Dictionary).get("id", ""))
			var quote := Game.inquiry_offer(inquiry_id, dc_id)
			if not bool(quote.get("ok", false)) or not bool(quote.get("eligible", false)):
				continue
			var before_cash := _cash()
			var expected_bonus := float(quote.get("bonus", 0.0))
			var expected_income := float(quote.get("projected", 0.0))
			var result := Game.accept_inquiry(inquiry_id, dc_id, quote)
			_expect(bool(result.get("ok", false)), "an eligible inquiry must accept through the authoritative contract path")
			if not bool(result.get("ok", false)):
				return false
			var signed := Game.find_datacenter(dc_id)
			_expect(is_equal_approx(float(signed.get("locked_market_multiplier", 0.0)), float(quote.get("locked_market_multiplier", -1.0))), "accepted inquiry must lock the displayed market multiplier")
			# The service-time gift can cross a relationship threshold at the same
			# instant as signing, so the authoritative result may be higher than the
			# pre-sign quote; it may never be lower than the promised projection.
			_expect(Game.datacenter_monthly_income(signed) + 1.0 >= expected_income, "accepted inquiry income must include at least its displayed premium forecast")
			_expect(absf(_cash() - before_cash - expected_bonus) <= 1.0, "accepted inquiry must credit its displayed signing bonus exactly once")
			_expect(int(Game.state.get("stats", {}).get("inquiries_accepted", 0)) >= 1, "accepted inquiry must advance its permanent roadmap statistic")
			return true
	return false

# Coming back after a night away must pay out and must not corrupt anything.
func _verify_offline_return() -> void:
	var before := _cash()
	var report := Game.advance_time(Game.offline_income_cap_seconds() + 3600.0, true)
	main.call("_refresh")
	await _settle()
	_expect(not report.is_empty(), "an offline return must produce a report")
	_expect(_cash() >= before, "an offline return must never take cash away")
	_assert_invariants()
	_note("offline return paid $%s over the %s cap" % [Game.format_number(_cash() - before), Game.format_duration(Game.offline_income_cap_seconds())])
	await _shot("d_offline_return")

func _verify_prestige() -> void:
	var built := int(Game.state["player"].get("total_datacenters_built", 0))
	_note("campaign end: month %d, %d built, era %d, net worth $%s" % [_month, built, int(Game.state["player"].get("era", 1)), Game.format_number(Game.net_worth())])
	main.call("_navigate", "tech")
	await _settle()
	await _shot("e_prestige_card")
	_expect(main.find_child("PrestigeCard", true, false) != null, "the tech page must show the prestige card")
	_expect(built >= _prestige_minimum(), "the campaign only built %d sites; prestige needs %d" % [built, _prestige_minimum()])
	if built < _prestige_minimum():
		return
	var before_brand := float(Game.state["player"].get("brand_multiplier", 1.0))
	var before_era := int(Game.state["player"].get("era", 1))
	var result := Game.prestige()
	_expect(bool(result.get("ok", false)), "prestige must succeed at the documented threshold (got %s)" % str(result.get("reason", "")))
	main.call("_navigate", "map")
	main.call("_refresh")
	await _settle()
	_expect(float(Game.state["player"].get("brand_multiplier", 1.0)) > before_brand, "prestige must raise the brand multiplier")
	_expect(int(Game.state["player"].get("era", 1)) == before_era, "prestige must keep era progress")
	_expect(_cash() > 0.0, "prestige must hand back the liquidated net worth as cash")
	_expect(Game.state.get("plots", []).size() == 1, "prestige must reset the campus to a single plot")
	_expect(Game.queue_capacity() == 2 and int(Game.state.get("technology", {}).get("construction_bays", 0)) == 1, "prestige must reset Engineering to its two-lane base")
	_note("prestige: brand x%.3f, restart cash $%s" % [float(Game.state["player"].get("brand_multiplier", 1.0)), Game.format_number(_cash())])
	await _shot("f_after_prestige")
	# The restarted run must still be playable, not a soft-locked empty map.
	var rebuilt := bool(Game.start_datacenter_construction("plot_1", "dc_t1").get("ok", false))
	if not rebuilt:
		rebuilt = bool(Game.start_datacenter_construction("plot_1", "dc_t0").get("ok", false))
	_expect(rebuilt, "the post-prestige run must be able to build again")
	Game.advance_time(_month_seconds, false)
	main.call("_refresh")
	await _settle()
	_assert_invariants()

# Every page must survive a fully built-out save without erroring or going blank.
func _tour_pages() -> void:
	for page: String in ["map", "market", "tech", "store", "map"]:
		main.call("_navigate", page)
		await _settle()
		_expect(str(main.get("active_page")) == page, "navigating to %s must stick" % page)
		if page != "map":
			_expect(_live_market_banners().is_empty(), "the market banner must not sit on top of the %s page" % page)
		await _shot("g_page_%s" % page)
	var dc_id := _first_datacenter_id()
	if not dc_id.is_empty():
		main.call("_open_datacenter", dc_id)
		await _settle()
		_expect(main.find_child("ContractCTA", true, false) != null, "opening a data center must present its drawer")
		await _shot("g_page_drawer")
		_dismiss_overlays()
		await _settle()

# A tester must never meet a screen that cannot be left or that lies.
func _assert_invariants() -> void:
	_expect(is_instance_valid(main), "the main view must survive the campaign")
	_expect(is_finite(_cash()), "month %d: cash must stay finite" % _month)
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		var entry: Dictionary = dc
		var status := str(entry.get("status", ""))
		_expect(status in ["operational", "ruined"], "month %d: unexpected data center status '%s'" % [_month, status])
		if status != "operational":
			continue
		var income := Game.datacenter_monthly_income(entry)
		_expect(is_finite(income) and income >= 0.0, "month %d: income must stay finite and non-negative (got %s)" % [_month, str(income)])
		var racks: Array = entry.get("racks", [])
		for slot: int in range(racks.size()):
			if not racks[slot] is Dictionary:
				continue
			var rack_status := str((racks[slot] as Dictionary).get("status", ""))
			_expect(rack_status in ["installing", "active", "faulted", "repairing"], "month %d: unexpected rack status '%s'" % [_month, rack_status])
	for item: Dictionary in Game.state.get("construction_queue", []):
		_expect(float(item.get("complete_at", 0.0)) >= float(item.get("started_at", 0.0)), "month %d: a queued job finishes before it starts" % _month)
	_assert_top_strip_does_not_stack()

# Market transitions must reuse the permanent safe-band news surface.  A second
# banner would stack below it and cover the first row of campus buildings.
func _assert_top_strip_does_not_stack() -> void:
	var banners := _live_market_banners()
	_expect(banners.is_empty(), "month %d: a legacy market banner is covering the campus" % _month)
	var notice := main.find_child("WorldNews", true, false) as Control
	if notice == null or not notice.is_visible_in_tree():
		return
	for other_name: String in ["CampusSwitcher", "CampusMarker_0"]:
		var other := main.find_child(other_name, true, false) as Control
		if other == null or not other.is_visible_in_tree():
			continue
		_expect(not notice.get_global_rect().intersects(other.get_global_rect()), "month %d: the unified market notice overlaps %s" % [_month, other_name])

func _live_market_banners() -> Array[Control]:
	var live: Array[Control] = []
	for node: Node in main.find_children("MarketEventBanner", "", true, false):
		var banner := node as Control
		if banner != null and banner.is_visible_in_tree():
			live.append(banner)
	return live

func _prestige_minimum() -> int:
	return int(DataRepository.get_table("economy").get("prestige", {}).get("minimum_datacenters", 20))

func _cash() -> float:
	return float(Game.state["player"].get("cash", 0.0))

func _age_progress(dc: Dictionary) -> float:
	return Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))

func _first_datacenter_id() -> String:
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and str((dc as Dictionary).get("status", "")) == "operational":
			return str((dc as Dictionary).get("id", ""))
	return ""

# Era and offline dialogs are modal; a player taps through them. Leaving one up
# would hide every later screen, so clear them the way the button does — and
# count them, because an era that never announces itself is a defect too.
func _dismiss_modals() -> void:
	for _guard: int in range(8):
		var overlay := main.find_child("EraOverlay", true, false) as Control
		var era := main.find_child("EraConfirmButton", true, false) as Button
		if overlay != null and overlay.is_visible_in_tree() and (era == null or not era.is_visible_in_tree()):
			# The celebration holds the button back for a couple of seconds; a
			# player who does not want to wait taps the card to skip ahead.
			var tap := InputEventMouseButton.new()
			tap.button_index = MOUSE_BUTTON_LEFT
			tap.pressed = true
			tap.position = overlay.get_global_rect().get_center()
			overlay.gui_input.emit(tap)
			await _settle()
			continue
		if era != null and era.is_visible_in_tree():
			_era_overlays_seen += 1
			era.pressed.emit()
			await _settle()
			continue
		var claim := main.find_child("OfflineClaimButton", true, false) as Button
		if claim != null and claim.is_visible_in_tree():
			claim.pressed.emit()
			await _settle()
			continue
		return

func _dismiss_overlays() -> void:
	for node_name: String in ["ActionSheetOverlay", "DatacenterContext"]:
		for node: Node in main.find_children(node_name, "", true, false):
			node.queue_free()

func _settle() -> void:
	for _i: int in range(4):
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _note(message: String) -> void:
	milestones.append(message)

func _shot(shot_name: String) -> void:
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shot_index += 1
	image.save_png("%s%02d_%s.png" % [OUT, _shot_index, shot_name])
	print("CAMPAIGN: shot %02d_%s" % [_shot_index, shot_name])
