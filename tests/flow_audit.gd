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
	_assert_sale_focus(false)
	main.call("_show_building_picker", "plot_1")
	await _shot("s0_welcome_picker")
	_assert_sheet_reward_uses_hud_pulse()
	_close("BuildingPicker")
	var tutorial_build := Game.start_datacenter_construction("plot_1", "dc_t0")
	var tutorial_job: Dictionary = tutorial_build.get("construction", {})
	_expect(float(tutorial_job.get("complete_at", 0.0)) - float(tutorial_job.get("started_at", 0.0)) <= 30.0, "FT4 tutorial T0 construction must complete within 30 seconds")
	await _shot("s1_power_step_during_construction")
	_assert_no_started_celebration("construction start")
	_assert_tutorial_target("power", "drawer", "construction_wait", true)
	_assert_tutorial_orphan_guard()
	_assert_construction_timer_capsule()
	Game.advance_time(30.0, false)
	await _shot("s1_power_step_dc_built_map")
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var dc_id := str(dc.get("id", ""))
	_assert_tutorial_target("power", "drawer", "world_building")
	_assert_world_target_matches_building(dc_id)
	_assert_world_fx_extent(dc_id)
	_assert_tutorial_suppresses_world_coins()
	main.call("_open_datacenter", dc_id)
	await _shot("s1_power_step_drawer_open")
	_assert_tutorial_target("power", "drawer", "control")
	_assert_unpowered_copy_and_drawer_lock()
	_assert_sheet_blocks_world_fx(dc_id)
	main.call("_show_attachment_picker", dc_id, "power", "")
	await _shot("s1_power_picker_sheet")
	_assert_sheet_reward_uses_hud_pulse()
	_assert_sheet_spotlight("power", "Choice_power_t1")
	_close("ActionSheetOverlay")
	Game.install_power(dc_id, "power_t1")
	Game.advance_time(301.0, false)
	await _shot("s2_rack_step_after_power")
	_assert_tutorial_target("first_rack", "drawer", "control")
	_assert_datacenter_header(dc_id)
	main.call("_show_rack_picker", dc_id, 0)
	await _shot("s2_rack_picker_sheet")
	_assert_sheet_spotlight("first_rack", "Choice_rack_compute_t1")
	_assert_no_repeat_open_loop("first_rack")
	_close("ActionSheetOverlay")
	Game.install_rack(dc_id, 0, "rack_compute_t1")
	Game.advance_time(150.0, false)
	await _shot("s3_contract_step")
	Game.sign_contract(dc_id, "internet")
	await _shot("s4_cooling_step")
	_assert_tutorial_target("cooling", "drawer", "control")
	_assert_datacenter_header(dc_id)
	Game.install_cooler(dc_id, "north", "cool_air_t1")
	Game.advance_time(301.0, false)
	await _shot("s5_buy_plot_step")
	_assert_tutorial_target("buy_land", "map", "control")
	_expect(main.find_child("DatacenterContext", true, false) == null, "B1 map context must clear the previous data-center drawer")
	_assert_sale_focus(true)
	Game.buy_next_plot()
	await _shot("s6_retire_step_too_new")
	_assert_tutorial_target("retire", "dormant", "none", true)
	var retire_message := main.find_child("TutorialMessage", true, false) as Label
	_expect(retire_message != null and retire_message.text == tr("TUTORIAL_RETIRE_WAIT"), "B4 dormant retire step must explain why no action is available")
	await get_tree().create_timer(3.1).timeout
	await _shot("s6_retire_step_dormant_hint")
	var dormant_hint := main.find_child("TutorialDormantHint", true, false) as Button
	var dormant_overlay := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	_expect(dormant_hint != null and dormant_hint.visible and dormant_overlay != null and not dormant_overlay.visible, "B4 dormant lesson must collapse to the corner coach hint")
	Game.advance_time(0.7 * 86400.0, false)
	await _shot("s6_retire_step_aged")
	_assert_tutorial_target("retire", "drawer", "world_building")
	main.call("_open_datacenter", dc_id)
	await _shot("s6_retire_drawer")
	_assert_tutorial_target("retire", "drawer", "control")
	Game.retire_datacenter(dc_id)
	await _shot("s7_standard_step")
	Game.start_datacenter_construction("plot_1", "dc_t1")
	Game.advance_time(3600.0, false)
	await _shot("s8_tutorial_done_map")
	_assert_sale_focus(true)
	await _assert_fx_ttl()
	_assert_standard_t0_duration()
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

func _assert_standard_t0_duration() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	var standard_build := Game.start_datacenter_construction("plot_1", "dc_t0")
	var standard_job: Dictionary = standard_build.get("construction", {})
	_expect(is_equal_approx(float(standard_job.get("complete_at", 0.0)) - float(standard_job.get("started_at", 0.0)), 300.0), "FT4 T0 construction must restore its normal 300-second duration after tutorial completion")

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

# G1: an open picker is the only surface the player can reach, so the coaching
# spotlight must move into it. Before this guard the resolver kept pointing at
# the drawer control the sheet had just covered, and the dimming panes — drawn
# above the sheet — blacked out the one panel that was actually tappable.
func _assert_sheet_spotlight(step_id: String, expected_choice: String) -> void:
	var overlay := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	var sheet_overlay := main.find_child("ActionSheetOverlay", true, false) as Control
	if overlay == null or sheet_overlay == null:
		_expect(false, "G1 %s needs both the tutorial overlay and an open sheet" % step_id)
		return
	var sheet := sheet_overlay.find_child("ContextSheet", true, false) as Control
	if sheet == null:
		_expect(false, "G1 %s open sheet must expose its ContextSheet panel" % step_id)
		return
	var sheet_rect := sheet.get_global_rect()
	_expect(str(overlay.get_meta("target_source", "")) == "sheet_option", "F1 %s must retarget to a sheet option while a picker is open" % step_id)
	var resolved: Rect2 = overlay.get_meta("resolved_target_rect", Rect2())
	_expect(resolved.size.x > 1.0 and sheet_rect.grow(2.0).encloses(resolved), "G1 %s spotlight target must sit inside the open sheet (target=%s sheet=%s)" % [step_id, resolved, sheet_rect])
	var choice := sheet_overlay.find_child(expected_choice, true, false) as Control
	_expect(choice != null and choice.get_global_rect().intersects(resolved), "G1 %s spotlight must land on %s" % [step_id, expected_choice])
	# F3: dimming may darken the world behind the sheet but never the sheet itself.
	var sheet_area := sheet_rect.get_area()
	for pane_name: String in ["TutorialMask0", "TutorialMask1", "TutorialMask2", "TutorialMask3"]:
		var pane := overlay.find_child(pane_name, true, false) as ColorRect
		if pane == null or not pane.is_visible_in_tree():
			continue
		var covered := pane.get_global_rect().intersection(sheet_rect).get_area()
		_expect(covered <= sheet_area * 0.02, "F3 %s dim pane %s must not cover the open sheet (%.0f%% covered)" % [step_id, pane_name, covered / maxf(1.0, sheet_area) * 100.0])
	# F5: the bubble must clear the sheet heading it would otherwise hide.
	var heading := sheet_overlay.find_child("SheetHeading", true, false) as Control
	var callout := main.find_child("TutorialCallout", true, false) as Control
	if heading != null and callout != null:
		_expect(not callout.get_global_rect().intersects(heading.get_global_rect()), "F5 %s callout must not cover the sheet heading" % step_id)

# G3: the spotlight action must not be the same call that opened the sheet, or
# every guided tap stacks another picker and the tutorial cannot be completed.
func _assert_no_repeat_open_loop(step_id: String) -> void:
	var before := _count_nodes_named("ActionSheetOverlay")
	var overlay := main.find_child("TutorialSpotlight", true, false) as TutorialOverlay
	if overlay == null or not overlay.is_actionable():
		_expect(false, "G3 %s spotlight must stay actionable over the sheet" % step_id)
		return
	if overlay.target_action.is_valid():
		overlay.target_action.call()
	var after := _count_nodes_named("ActionSheetOverlay")
	_expect(after <= before, "G3 %s guided tap must act on the sheet instead of opening another one (%d -> %d)" % [step_id, before, after])

func _count_nodes_named(node_name: String) -> int:
	return main.find_children(node_name, "", true, false).size()

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
		var expected_hole := resolved.grow(20.0).intersection(overlay.get_viewport_rect())
		_expect(overlay.target_rect.position.distance_to(expected_hole.position) < 0.5 and overlay.target_rect.size.distance_to(expected_hole.size) < 0.5, "FT3 %s spotlight must keep a 20u breathing gutter" % step_id)
		var hole_border := overlay.find_child("TutorialHoleBorder", true, false) as PanelContainer
		_expect(hole_border != null and int(hole_border.get_meta("spotlight_corner_radius", 0)) == 28, "FT3 spotlight border must use a 28u corner radius")
		var callout := main.find_child("TutorialCallout", true, false) as Control
		_expect(callout != null and not callout.get_global_rect().intersects(resolved), "E3 %s callout must not cover its tap target" % step_id)

func _assert_tutorial_orphan_guard() -> void:
	var message := main.find_child("TutorialMessage", true, false) as Label
	_expect(message != null and bool(message.get_meta("orphan_guard", false)) and message.custom_minimum_size.x >= 500.0, "FT1 tutorial copy must reserve enough width for clean CJK wrapping")
	if message == null or message.text.is_empty():
		return
	var last_bounds := message.get_character_bounds(message.text.length() - 1)
	var last_line_chars := 0
	for index: int in range(message.text.length()):
		var bounds := message.get_character_bounds(index)
		if bounds.size != Vector2.ZERO and absf(bounds.position.y - last_bounds.position.y) < 1.0 and not message.text.substr(index, 1).strip_edges().is_empty():
			last_line_chars += 1
	_expect(last_line_chars >= 2, "FT1 tutorial bubble last line must contain at least two visible characters")

func _assert_tutorial_suppresses_world_coins() -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	_expect(layer != null and layer.active_coin_count() == 0, "FT2 active tutorial steps must suppress world coin trajectories")

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
	var expected_status := str(main.call("_datacenter_header_status_text", dc))
	var expected_income := tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc))
	_expect(status.text == expected_status, "D1 drawer status must match authoritative data (%s)" % expected_status)
	_expect(income.text == expected_income, "D1 drawer income must match authoritative data (%s)" % expected_income)

func _assert_unpowered_copy_and_drawer_lock() -> void:
	var usage := main.find_child("BoardPowerUsage", true, false) as RichTextLabel
	var hint := main.find_child("ContractPowerHint", true, false) as Label
	var drawer := main.find_child("DatacenterContext", true, false)
	_expect(usage != null and not bool(usage.get_meta("power_installed", true)) and str(usage.get_meta("display_copy", "")) == tr("UNPOWERED"), "B5 an unpowered board must say unpowered instead of 0 / 0")
	_expect(hint != null and hint.text == tr("BOARD_INSTALL_POWER"), "B5 first power instruction must say install, not upgrade")
	_expect(drawer != null and bool(drawer.get_meta("tutorial_lock_close", false)), "E2 tutorial drawer drag-dismiss must be locked")

func _assert_sale_focus(expected: bool) -> void:
	var sale_price := main.find_child("SalePriceBadge", true, false) as CanvasItem
	var sale_tether := main.find_child("SalePriceTether", true, false) as CanvasItem
	_expect(sale_price != null and sale_tether != null and sale_price.visible == expected and sale_tether.visible == expected, "E1 sale price tag visibility must follow the buy-land step (%s)" % expected)

func _assert_construction_timer_capsule() -> void:
	var progress := main.find_child("ConstructionProgress", true, false) as ProgressBar
	var row := progress.get_parent() as Control if progress != null else null
	var badge := row.get_parent() as PanelContainer if row != null else null
	var button := badge.get_parent() as Button if badge != null else null
	var style := badge.get_theme_stylebox("panel") as StyleBoxFlat if badge != null else null
	_expect(badge != null and button != null and style != null and bool(badge.get_meta("construction_timer_flat", false)), "C4 construction countdown must use the flat capsule style")
	if badge != null and button != null and style != null:
		_expect(button.get_global_rect().encloses(badge.get_global_rect()) and style.get_border_width(SIDE_TOP) >= 2 and style.get_border_width(SIDE_RIGHT) >= 2, "C4 construction capsule must be closed and contained on every edge")

func _assert_world_fx_extent(datacenter_id: String) -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	if layer == null:
		_expect(false, "C2 FxLayer must exist")
		return
	layer.clear()
	main.call("_play_fx_at_world", "fx_dust_puff", datacenter_id, 190.0)
	var effect: Control = null
	for child: Node in layer.get_children():
		if str(child.get_meta("fx_asset_id", "")) == "fx_dust_puff":
			effect = child as Control
			break
	_expect(effect != null and float(effect.get_meta("fx_extent", INF)) <= 120.0, "C2 installation dust must be capped at 120u")
	layer.clear()

func _assert_sheet_blocks_world_fx(datacenter_id: String) -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	var drawer := main.find_child("DatacenterContext", true, false) as CanvasItem
	if layer == null or drawer == null:
		_expect(false, "C2 sheet and FxLayer must exist")
		return
	var before := layer.active_effect_count()
	main.call("_play_fx_at_world", "fx_dust_puff", datacenter_id, 190.0)
	_expect(layer.active_effect_count() == before, "C2 an open sheet must drop world FX")
	_expect(layer.z_index < drawer.z_index, "C2 world FX layer must render below sheets")

func _assert_fx_ttl() -> void:
	var layer := main.find_child("FxLayer", true, false) as FxLayer
	if layer == null:
		_expect(false, "C1 FxLayer must exist for TTL audit")
		return
	layer.clear()
	main.call("_play_fx", "fx_smoke_puff", 420.0)
	var effect := layer.get_child(0) as Control if layer.get_child_count() > 0 else null
	_expect(effect != null and float(effect.get_meta("fx_extent", INF)) <= 100.0, "C2 non-celebration global FX must be capped at 100u")
	await get_tree().create_timer(2.55).timeout
	_expect(layer.active_effect_count() == 0, "C1 every managed FX node must self-destruct within 2.5s")

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
