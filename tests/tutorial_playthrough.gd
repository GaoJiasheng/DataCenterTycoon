extends Node

# Touch-only tutorial playthrough. Every earlier harness drove the game by
# calling internal methods, which is exactly why they stayed green while the
# device build dead-ended: they never checked that tapping where the coach
# points actually does anything. This one may only synthesise real touch
# events at the spotlight's own target and must reach the end of the tutorial.
#   godot --headless --path . tests/tutorial_playthrough.tscn
const MAIN_SCENE := preload("res://main.tscn")
const OUT := "/tmp/dct_play_"
const MAX_TAPS_PER_STEP := 6
const SETTLE_FRAMES := 6

var main: Node
var failures: Array[String] = []
var waits: Array[String] = []
var _shot_index := 0

func _ready() -> void:
	TranslationServer.set_locale("zh_CN")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(990, 2151))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	main = MAIN_SCENE.instantiate()
	add_child(main)
	await _settle()
	await _play_tutorial()
	_verify_shortened_timings_are_tutorial_only()
	await _verify_install_in_progress_is_announced()
	await _verify_drawer_reflects_completed_installs()
	await _verify_orphaned_step_recovers()
	await _verify_standard_step_clears_stale_drawer()
	_verify_completed_actions_reconcile()
	await _verify_countdown_shows_full_units()
	AudioService.stop_all()
	for wait: String in waits:
		print("PLAYTHROUGH: wait  %s" % wait)
	if failures.is_empty():
		print("PLAYTHROUGH: PASS -> %s*.png" % OUT)
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("PLAYTHROUGH: %s" % failure)
		print("PLAYTHROUGH: FAIL (%d issue(s))" % failures.size())
		get_tree().quit(1)

func _play_tutorial() -> void:
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var guard := 0
	while guard < 40:
		guard += 1
		var tutorial: Dictionary = Game.state.get("tutorial", {})
		if bool(tutorial.get("completed", false)):
			await _shot("done")
			return
		var index := int(tutorial.get("step", 0))
		if index >= steps.size():
			await _shot("done")
			return
		var step_id := str(steps[index].get("id", ""))
		var overlay := _overlay()
		if overlay == null:
			_fail("no tutorial overlay while step %s is active" % step_id)
			return
		await _shot("step%d_%s" % [index, step_id])
		var mode := str(overlay.get_meta("tutorial_mode", ""))
		if mode == "waiting" or mode == "dormant" or mode == "dormant_hint":
			# The coach is deliberately idle. Advance the world the way a waiting
			# player would rather than tapping a target that does not exist.
			if not await _resolve_idle_state(step_id, index):
				return
			continue
		if not overlay.is_actionable():
			_fail("step %s is neither actionable nor an explained idle state (mode=%s)" % [step_id, mode])
			return
		if not await _tap_until_step_changes(index, step_id):
			return
	_fail("tutorial did not finish within the step guard")

# Drives one step purely through touch. Returns false when the step refuses to
# advance, which is the exact failure a player experiences as "nothing happens".
func _tap_until_step_changes(index: int, step_id: String) -> bool:
	for attempt: int in range(MAX_TAPS_PER_STEP):
		var overlay := _overlay()
		if overlay == null or not overlay.is_actionable():
			break
		# Compare the resolved rect, not just its source label: two consecutive
		# stages (world CTA then the card inside the picker) are both "control".
		var before_source := "%s@%s" % [str(overlay.get_meta("target_source", "")), overlay.target_rect]
		var target: Rect2 = overlay.target_rect
		if target.size.x <= 1.0 or target.size.y <= 1.0:
			_fail("step %s exposes an empty spotlight target" % step_id)
			return false
		var cash_before := float(Game.state.get("player", {}).get("cash", 0.0))
		var sheets_before := main.find_children("ActionSheetOverlay", "", true, false).size()
		_touch(target.get_center())
		await _settle()
		if int(Game.state.get("tutorial", {}).get("step", 0)) != index or bool(Game.state.get("tutorial", {}).get("completed", false)):
			return true
		# The tap may have committed an action that only completes on a timer
		# (power and rack installs queue work). Let that finish before deciding
		# the step is stuck, and record how long a real player would be waiting.
		var spent := cash_before - float(Game.state.get("player", {}).get("cash", 0.0))
		if spent > 0.0 or _has_pending_work():
			var waited := await _wait_for_pending_work(index)
			if waited >= 0.0:
				_note_wait(step_id, waited)
				return true
		var after := _overlay()
		var after_source := "%s@%s" % [str(after.get_meta("target_source", "")), after.target_rect] if after != null else ""
		if after_source == before_source and attempt >= 1:
			# Two identical taps with no progress and no change of target is the
			# signature of a guided dead end.
			_fail("step %s does not advance on tap (target=%s sheets %d->%d, tapped %d times)" % [step_id, str(overlay.get_meta("target_node", "?")), sheets_before, main.find_children("ActionSheetOverlay", "", true, false).size(), attempt + 1])
			await _shot("stuck_%s" % step_id)
			return false
	if int(Game.state.get("tutorial", {}).get("step", 0)) == index and not bool(Game.state.get("tutorial", {}).get("completed", false)):
		_fail("step %s still active after %d taps" % [step_id, MAX_TAPS_PER_STEP])
		await _shot("stuck_%s" % step_id)
		return false
	return true

# Waiting and dormant states are legitimate, but only if the thing they wait on
# actually arrives. Advance the clock and re-check instead of tapping.
func _resolve_idle_state(step_id: String, index: int) -> bool:
	# The retirement lesson deliberately sleeps until the container ages past 60%
	# of a one-day lifespan, so the clock has to move in hours, not minutes.
	for attempt: int in range(24):
		Game.advance_time(3600.0, false)
		main.call("_refresh")
		await _settle()
		var overlay := _overlay()
		if overlay == null:
			_fail("overlay vanished while waiting on step %s" % step_id)
			return false
		var mode := str(overlay.get_meta("tutorial_mode", ""))
		if int(Game.state.get("tutorial", {}).get("step", 0)) != index:
			return true
		if mode != "waiting" and mode != "dormant" and mode != "dormant_hint":
			return true
	_fail("step %s stayed idle after 24 game-hours of waiting" % step_id)
	await _shot("idle_%s" % step_id)
	return false

# Rects come from get_global_rect(), i.e. viewport-canvas space. The window is
# 990x2151 while the design canvas is 804x1748, so feeding these straight to
# Input.parse_input_event would land the tap ~23% off. push_input with
# in_local_coords keeps the two in the same space.
func _has_pending_work() -> bool:
	if not Game.state.get("construction_queue", []).is_empty():
		return true
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		for installed: Variant in (dc as Dictionary).get("racks", []):
			if installed is Dictionary and str((installed as Dictionary).get("status", "")) == "installing":
				return true
	return false

# Returns the in-game seconds a player would wait, or -1 if the step never
# advanced. Advances in one-minute slices so the wait is measured, not guessed.
func _wait_for_pending_work(index: int) -> float:
	var waited := 0.0
	while waited < 1800.0:
		Game.advance_time(60.0, false)
		waited += 60.0
		main.call("_refresh")
		await get_tree().process_frame
		if int(Game.state.get("tutorial", {}).get("step", 0)) != index or bool(Game.state.get("tutorial", {}).get("completed", false)):
			return waited
		if not _has_pending_work():
			await _settle()
			if int(Game.state.get("tutorial", {}).get("step", 0)) != index:
				return waited
			return -1.0
	return -1.0

func _note_wait(step_id: String, seconds: float) -> void:
	waits.append("%s waited %ds" % [step_id, int(seconds)])

func _touch(point: Vector2) -> void:
	# One event source only: emulate_mouse_from_touch would turn a synthetic
	# touch into a second mouse click and split the press/release pairing.
	var viewport := get_viewport()
	for pressed: bool in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = pressed
		viewport.push_input(mouse, true)

func _overlay() -> TutorialOverlay:
	return main.find_child("TutorialSpotlight", true, false) as TutorialOverlay

func _settle() -> void:
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	# Sheet hand-off costs ~0.5s (0.2s exit + 0.28s entry + layout pass).
	await get_tree().create_timer(0.9).timeout

func _fail(message: String) -> void:
	failures.append(message)

func _shot(shot_name: String) -> void:
	main.call("_refresh")
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	if not bool(Game.state.get("tutorial", {}).get("completed", false)):
		_expect(main.find_child("InquiryPersonaPortrait", true, false) == null and main.find_child("ContractPersonaContact", true, false) == null and main.find_child("PersonaToast", true, false) == null, "FTUE keeps customer-persona presentation hidden")
		var cat := main.park_map.campus_cat as CampusCat
		var cat_hit := cat.find_child("CampusCatHitArea", true, false) as Area2D if cat != null else null
		_expect(cat == null or (not cat.visible and (cat_hit == null or not cat_hit.input_pickable)), "FTUE keeps the campus cat invisible and non-interactive")
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shot_index += 1
	image.save_png("%s%02d_%s.png" % [OUT, _shot_index, shot_name])
	print("PLAYTHROUGH: %02d_%s" % [_shot_index, shot_name])

# Reproduces the owner's broken save: the tutorial sat on the power step while
# its data center had aged out, and the coach insisted construction was in
# progress with 0s remaining — pointing at nothing the player could act on.
func _verify_orphaned_step_recovers() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"] = {"step": 1, "completed": false, "dismissed_messages": []}
	Game.state["construction_queue"] = []
	main.call("_refresh")
	await _settle()
	var overlay := _overlay()
	if overlay == null:
		_fail("orphan check: overlay missing")
		return
	var message := main.find_child("TutorialMessage", true, false) as Label
	var copy := message.text if message != null else ""
	_expect(not copy.contains(tr("TUTORIAL_BUILDING_WAIT") % "0s"), "orphaned step must not claim construction is in progress (copy=%s)" % copy)
	_expect(str(overlay.get_meta("target_source", "")) == "rebuild", "orphaned step must route the player back to building a site (source=%s)" % str(overlay.get_meta("target_source", "")))
	_expect(overlay.is_actionable(), "orphaned step must offer a tappable recovery")
	await _shot("orphan_recovered")

# Reproduces the device screenshot: the lesson has advanced to the final
# standard-building step, but an aging/faulted container drawer is still open.
# The old one-shot context switch left the real build CTA underneath that
# drawer, so the spotlight framed an apparently empty, unresponsive rectangle.
func _verify_standard_step_clears_stale_drawer() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(400.0, false)
	Game.buy_next_plot()
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	var lifespan := float(DataRepository.get_entry("buildings", "dc_t0").get("lifespan_seconds", 86400.0))
	dc["built_at"] = Game.simulation_time() - lifespan * 0.999
	dc["power_unit"] = "power_t1"
	dc["customer_id"] = "internet"
	dc["contract_end_at"] = Game.simulation_time() + 5400.0
	dc["locked_market_multiplier"] = 1.0
	dc["free_switch_available"] = true
	dc["racks"][0] = {"rack_id": "rack_compute_t1", "status": "faulted", "enabled": true, "auto_repair_at": Game.simulation_time() + 13140.0}
	Game.state["player"]["cash"] = 37100.0
	Game.state["tutorial"] = {"step": 7, "completed": false, "dismissed_messages": []}
	Game.state["flags"]["standard_built"] = false
	main.call("_refresh")
	await _settle()
	main.call("_show_datacenter_context", str(dc.get("id", "")))
	await _settle()
	main.call("_refresh")
	await _settle()
	var stale_drawer := main.find_child("DatacenterContext", true, false) as Control
	_expect(stale_drawer == null or not stale_drawer.is_visible_in_tree(), "standard lesson must clear a stale data-center drawer instead of highlighting the CTA underneath it")
	var overlay := _overlay()
	_expect(overlay != null and overlay.is_actionable() and str(overlay.get_meta("target_node", "")) == "PrimaryWorldAction", "standard lesson must recover to the visible map build CTA")
	if overlay == null or not overlay.is_actionable():
		return
	_touch(overlay.target_rect.get_center())
	await _settle()
	var picker := main.find_child("BuildingPicker", true, false) as Control
	overlay = _overlay()
	_expect(picker != null and picker.is_visible_in_tree(), "standard lesson build CTA must open the building picker")
	_expect(overlay != null and overlay.is_actionable() and str(overlay.get_meta("target_node", "")) == "Building_dc_t1", "standard lesson must retarget to the standard data-center card")
	if overlay == null or not overlay.is_actionable():
		return
	_touch(overlay.target_rect.get_center())
	await _settle()
	_expect(bool(Game.state.get("tutorial", {}).get("completed", false)), "standard data-center card must complete the tutorial through touch")
	await _shot("standard_stale_drawer_recovered")

# A save can be interrupted after the world action succeeds but before its
# tutorial step is persisted. Reconciliation must skip only lessons whose
# authoritative outcome already exists, then stop at the first unmet lesson.
func _verify_completed_actions_reconcile() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(400.0, false)
	Game.buy_next_plot()
	var starter: Dictionary = Game.state["plots"][0]["datacenter"]
	starter["power_unit"] = "power_t1"
	starter["racks"][0] = {"rack_id": "rack_compute_t1", "status": "active", "enabled": true}
	starter["customer_id"] = "internet"
	starter["coolers"] = {"north": "cool_air_t1"}
	var secondary := starter.duplicate(true)
	secondary["id"] = "dc_non_tutorial"
	secondary["building_id"] = "dc_t1"
	Game.state["plots"][1]["datacenter"] = secondary
	Game.state["plots"][1]["status"] = "operational"
	main.set("selected_datacenter_id", "dc_non_tutorial")
	_expect(str(main.call("_tutorial_datacenter_id")) == str(starter.get("id", "")), "tutorial must prioritize the starter container over a selected later data center")
	Game.state["tutorial"] = {"step": 0, "completed": false, "dismissed_messages": []}
	_expect(Game.reconcile_tutorial_progress(false), "completed tutorial actions must reconcile forward")
	_expect(int(Game.state["tutorial"].get("step", -1)) == 6 and not bool(Game.state["tutorial"].get("completed", false)), "reconciliation must stop at the still-unmet retirement lesson")
	Game.state["plots"][1]["datacenter"] = null
	Game.state["plots"][1]["status"] = "empty"
	Game.state["plots"][0]["datacenter"] = null
	Game.state["plots"][0]["status"] = "empty"
	_expect(Game.reconcile_tutorial_progress(false), "a starter container already removed must reconcile to the standard-building lesson")
	_expect(int(Game.state["tutorial"].get("step", -1)) == 7 and not bool(Game.state["tutorial"].get("completed", false)), "reconciliation must stop before an unbuilt standard data center")
	Game.state["flags"]["standard_built"] = true
	_expect(Game.reconcile_tutorial_progress(false) and bool(Game.state["tutorial"].get("completed", false)), "an already-built standard data center must close the tutorial")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

# The shortened first-run timings must not leak into normal play, or they would
# quietly rewrite the pacing the economy model was balanced against.
func _verify_shortened_timings_are_tutorial_only() -> void:
	var power := DataRepository.get_entry("attachments", "power_t1")
	var rack := DataRepository.get_entry("racks", "rack_compute_t1")
	var cooler := DataRepository.get_entry("attachments", "cool_air_t1")
	var building := DataRepository.get_entry("buildings", "dc_t0")
	for pair: Array in [[power, 300.0], [cooler, 300.0], [rack, 120.0]]:
		var entry: Dictionary = pair[0]
		_expect(float(entry.get("install_seconds", 0.0)) == float(pair[1]), "shipped install_seconds must stay at its balanced value (got %s)" % str(entry.get("install_seconds")))
		_expect(float(entry.get("tutorial_install_seconds", 0.0)) > 0.0 and float(entry.get("tutorial_install_seconds", 0.0)) < float(entry.get("install_seconds", 0.0)), "tutorial override must be shorter than the real duration")
	_expect(float(building.get("build_seconds", 0.0)) == 300.0 and float(building.get("tutorial_build_seconds", 0.0)) == 30.0, "container build override must remain tutorial-only")
	# With the tutorial finished, the authority must hand back the full duration.
	Game.state["tutorial"]["completed"] = true
	_expect(is_equal_approx(Game.call("_tutorial_duration", power, "tutorial_install_seconds", 300.0), 300.0), "completed tutorial must restore the full install duration")
	Game.state["tutorial"]["completed"] = false
	_expect(is_equal_approx(Game.call("_tutorial_duration", power, "tutorial_install_seconds", 300.0), 20.0), "an active tutorial must use the shortened duration")

# The owner tapped the transformer repeatedly because nothing on screen changed
# during its 20s install: the coach kept issuing the same instruction while the
# site stayed dark. An install already under way must present as a wait, never
# as a fresh action to repeat.
func _verify_install_in_progress_is_announced() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"] = {"step": 0, "completed": false, "dismissed_messages": []}
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(40.0, false)
	var dc_id := str(Game.state["plots"][0]["datacenter"].get("id", ""))
	Game.state["tutorial"]["step"] = 1
	Game.install_power(dc_id, "power_t1")
	main.call("_refresh")
	await _settle()
	var overlay := _overlay()
	if overlay == null:
		_fail("install-wait check: overlay missing")
		return
	_expect(str(overlay.get_meta("target_source", "")) == "install_wait", "an in-flight install must present as a wait (source=%s)" % str(overlay.get_meta("target_source", "")))
	_expect(not overlay.is_actionable(), "an in-flight install must not invite another tap")
	var message := main.find_child("TutorialMessage", true, false) as Label
	var copy := message.text if message != null else ""
	_expect(copy != tr("TUTORIAL_POWER"), "coach must stop repeating the install instruction while it runs (copy=%s)" % copy)
	await _shot("install_in_progress")
	# And once it lands, the lesson moves on by itself.
	Game.advance_time(60.0, false)
	main.call("_refresh")
	await _settle()
	_expect(int(Game.state.get("tutorial", {}).get("step", 0)) != 1, "finished install must advance the lesson")

# The drawer opens while the site is still dark and is never rebuilt, so any
# element created for the unpowered case has to keep tracking the authority.
# Both the board meter and the contract hint used to freeze at "no power" long
# after the transformer was running.
func _verify_drawer_reflects_completed_installs() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(400.0, false)
	var dc_id := str(Game.state["plots"][0]["datacenter"].get("id", ""))
	main.call("_open_datacenter", dc_id)     # opened while unpowered
	await _settle()
	var hint := main.find_child("ContractPowerHint", true, false) as Label
	_expect(hint != null and hint.visible, "unpowered drawer should show the install-power hint")
	Game.install_power(dc_id, "power_t1")
	Game.advance_time(400.0, false)          # completes inside a tick
	main.call("_refresh_hud")
	await _settle()
	_expect(hint == null or not hint.visible, "powered site must drop the install-power hint")
	var usage := main.find_child("BoardPowerUsage", true, false)
	var usage_text: String = usage.get_parsed_text() if usage is RichTextLabel else (usage.text if usage is Label else "")
	_expect(not usage_text.contains(tr("UNPOWERED")), "power meter must not still read unpowered (got %s)" % usage_text)
	await _shot("drawer_after_power")

# Countdown badges are clipped, so a too-narrow label silently drops characters:
# "59m 59s" shipped as "59m 59".
func _verify_countdown_shows_full_units() -> void:
	Game.reset_for_tests()
	Game.state["tutorial"]["completed"] = true
	Game.start_datacenter_construction("plot_1", "dc_t1")
	main.call("_refresh")
	await _settle()
	for node: Node in main.find_children("StatusText", "Label", true, false):
		var label := node as Label
		if label == null or not label.is_visible_in_tree() or label.text.is_empty():
			continue
		if not label.text.contains("m "):
			continue
		_expect(label.get_combined_minimum_size().x <= label.size.x + 1.0, "countdown label must fit its text (text=%s min=%.0f actual=%.0f)" % [label.text, label.get_combined_minimum_size().x, label.size.x])
		_expect(label.text.ends_with("s"), "countdown must keep its unit suffix (got %s)" % label.text)
