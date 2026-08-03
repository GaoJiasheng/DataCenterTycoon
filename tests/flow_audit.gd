extends Node

# One-off interaction-flow audit harness: walks the full FTUE from a fresh
# profile and captures every step plus the interstitial states players actually
# see. Assertions make this suitable for CI as well as visual review:
#   godot --headless --path . tests/flow_audit.tscn
const MAIN_SCENE := preload("res://main.tscn")
const OUT := "/tmp/dct_flow_"

var main: Node
var failures: Array[String] = []

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(990, 2151))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _shot("s0_welcome_map")
	_assert_batch_one_shell()
	main.call("_show_building_picker", "plot_1")
	await _shot("s0_welcome_picker")
	_assert_sheet_reward_uses_hud_pulse()
	_close("BuildingPicker")
	Game.start_datacenter_construction("plot_1", "dc_t0")
	await _shot("s1_power_step_during_construction")
	_assert_no_started_celebration("construction start")
	_assert_tutorial_target("power", "drawer", "construction_wait", true)
	Game.advance_time(300.0, false)
	await _shot("s1_power_step_dc_built_map")
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var dc_id := str(dc.get("id", ""))
	_assert_tutorial_target("power", "drawer", "world_building")
	_assert_world_target_matches_building(dc_id)
	main.call("_open_datacenter", dc_id)
	await _shot("s1_power_step_drawer_open")
	_assert_tutorial_target("power", "drawer", "control")
	main.call("_show_attachment_picker", dc_id, "power", "")
	await _shot("s1_power_picker_sheet")
	_assert_sheet_reward_uses_hud_pulse()
	_close("ActionSheetOverlay")
	Game.install_power(dc_id, "power_t1")
	Game.advance_time(300.0, false)
	await _shot("s2_rack_step_after_power")
	_assert_tutorial_target("first_rack", "drawer", "control")
	_assert_datacenter_header(dc_id)
	main.call("_show_rack_picker", dc_id, 0)
	await _shot("s2_rack_picker_sheet")
	_close("ActionSheetOverlay")
	Game.install_rack(dc_id, 0, "rack_compute_t1")
	Game.advance_time(150.0, false)
	await _shot("s3_contract_step")
	Game.sign_contract(dc_id, "internet")
	await _shot("s4_cooling_step")
	_assert_tutorial_target("cooling", "drawer", "control")
	_assert_datacenter_header(dc_id)
	Game.install_cooler(dc_id, "north", "cool_air_t1")
	Game.advance_time(300.0, false)
	await _shot("s5_buy_plot_step")
	_assert_tutorial_target("buy_land", "map", "control")
	_expect(main.find_child("DatacenterContext", true, false) == null, "B1 map context must clear the previous data-center drawer")
	Game.buy_next_plot()
	await _shot("s6_retire_step_too_new")
	_assert_tutorial_target("retire", "dormant", "none", true)
	Game.advance_time(0.7 * 86400.0, false)
	await _shot("s6_retire_step_aged")
	main.call("_open_datacenter", dc_id)
	await _shot("s6_retire_drawer")
	Game.retire_datacenter(dc_id)
	await _shot("s7_standard_step")
	Game.start_datacenter_construction("plot_1", "dc_t1")
	Game.advance_time(3600.0, false)
	await _shot("s8_tutorial_done_map")
	AudioService.stop_all()
	if failures.is_empty():
		print("FLOW_AUDIT: PASS -> %s*.png" % OUT)
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLOW_AUDIT: %s" % failure)
		print("FLOW_AUDIT: FAIL (%d assertion(s))" % failures.size())
		get_tree().quit(1)

func _close(node_name: String) -> void:
	var overlay := main.find_child(node_name, true, false)
	if overlay != null:
		overlay.queue_free()

func _assert_batch_one_shell() -> void:
	var stage := main.find_child("ShellStage", true, false) as Control
	_expect(stage != null, "A1 ShellStage must exist")
	if stage != null:
		_expect(stage.get_global_rect().position.y <= 32.0, "A1 desktop HUD top gap must be <= 32u (actual %.1f)" % stage.get_global_rect().position.y)
	var company := main.find_child("CompanyButton", true, false) as Button
	var badge := main.find_child("EraCornerBadge", true, false) as Label
	_expect(company != null and badge != null, "A2 company era corner badge must exist")
	if company != null and badge != null:
		var company_rect := company.get_global_rect()
		var badge_rect := badge.get_global_rect()
		_expect(company_rect.encloses(badge_rect), "A2 era number badge must remain inside company chip (company=%s badge=%s)" % [company_rect, badge_rect])
		_expect(badge_rect.get_center().x > company_rect.get_center().x and badge_rect.get_center().y > company_rect.get_center().y, "A2 era number must sit at the icon's lower-right corner")
	for button_name: String in ["TaskButton", "OperationsButton"]:
		var button := main.find_child(button_name, true, false) as Button
		var label := button.find_child("WorldActionLabel", true, false) as Label if button != null else null
		_expect(button != null and label != null, "A3 %s must own its caption" % button_name)
		if button != null and label != null:
			_expect(button.is_ancestor_of(label), "A3 %s caption must be inside the clickable button" % button_name)
			_expect(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "A3 %s caption must pass clicks to its button" % button_name)
	_expect(main.find_child("TaskCaption", true, false) == null and main.find_child("OperationsCaption", true, false) == null, "A3 no independent world-action caption may remain")

func _assert_no_started_celebration(context: String) -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	_expect(layer != null, "C1 FxLayer must exist")
	if layer != null:
		_expect(layer.active_effect_count() == 0, "C1 %s must not create celebration FX" % context)

func _assert_sheet_reward_uses_hud_pulse() -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	if layer == null:
		_expect(false, "C3 FxLayer must exist")
		return
	var before := layer.active_coin_count()
	main.call("_fly_cash_reward", Vector2(220, 520), 3)
	_expect(layer.active_coin_count() == before, "C3 open sheets must pulse the HUD instead of spawning world coins")

func _assert_tutorial_target(step_id: String, context: String, source: String, allow_zero: bool = false) -> void:
	var overlay := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	_expect(overlay != null and overlay.visible, "B1 tutorial overlay must be visible for %s" % step_id)
	if overlay == null:
		return
	_expect(str(overlay.get_meta("tutorial_step_id", "")) == step_id, "B1 active step must be %s" % step_id)
	_expect(str(overlay.get_meta("tutorial_context", "")) == context, "B1 %s context must be %s" % [step_id, context])
	_expect(str(overlay.get_meta("target_source", "")) == source, "B2 %s target source must be %s" % [step_id, source])
	var resolved: Rect2 = overlay.get_meta("resolved_target_rect", Rect2())
	if allow_zero:
		_expect(resolved.size == Vector2.ZERO and not overlay.is_actionable(), "B1 %s must be a non-actionable explained state" % step_id)
	else:
		_expect(resolved.size.x > 1.0 and resolved.size.y > 1.0 and overlay.is_actionable(), "B2 %s must expose one actionable target" % step_id)
		_expect(overlay.target_rect.intersects(resolved), "D2 %s spotlight must intersect its current resolved target" % step_id)

func _assert_world_target_matches_building(datacenter_id: String) -> void:
	var overlay := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	var park_map := main.get("park_map") as ParkMap
	var expected: Rect2 = park_map.building_rect(datacenter_id) if park_map != null else Rect2()
	var resolved: Rect2 = overlay.get_meta("resolved_target_rect", Rect2()) if overlay != null else Rect2()
	_expect(expected.size != Vector2.ZERO and resolved.intersects(expected), "B2 first-stage target must overlap the visible world building")

func _assert_datacenter_header(datacenter_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	var status := main.find_child("DatacenterStatus", true, false) as Label
	var income := main.find_child("DatacenterIncomeValue", true, false) as Label
	_expect(status != null and income != null, "D1 live data-center header fields must exist")
	if status == null or income == null or dc.is_empty():
		return
	var expected_status := str(main.call("_datacenter_status_text", dc))
	var expected_income := tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc))
	_expect(status.text == expected_status, "D1 drawer status must match authoritative data (%s)" % expected_status)
	_expect(income.text == expected_income, "D1 drawer income must match authoritative data (%s)" % expected_income)

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("FLOW_ASSERT: PASS %s" % message)
	else:
		failures.append(message)
		print("FLOW_ASSERT: FAIL %s" % message)

func _shot(shot_name: String) -> bool:
	main.call("_refresh")
	for _i in range(4):
		await get_tree().process_frame
	await get_tree().create_timer(0.38).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s%s.png" % [OUT, shot_name])
	print("FLOW_AUDIT: %s" % shot_name)
	return true
