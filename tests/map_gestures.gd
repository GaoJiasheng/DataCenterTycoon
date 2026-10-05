extends Node

# Exercise real viewport routing, including moving plot hit targets and HUDs.
var map: ParkMap
var failures := 0
var selections := 0
var alerts := 0

func _ready() -> void:
	Game.reset_for_tests()
	map = ParkMap.new()
	map.size = Vector2(804, 1748)
	add_child(map)
	map.setup(Game.state.get("plots", []))
	map.empty_plot_selected.connect(func(_id: String) -> void: selections += 1)
	await get_tree().process_frame
	var home := map.camera_offset
	var start := Vector2(400, 1000)
	_touch(start, true)
	_drag(start + Vector2(220, 0), Vector2(220, 0))
	_check(map.camera_offset.is_equal_approx(home + Vector2(220, 0)), "grass swipe follows a 220px finger movement exactly")
	_drag(start, Vector2(-220, 0))
	_check(map.camera_offset.is_equal_approx(home), "reverse swipe follows immediately without a dead region")
	_touch(start, false)
	_check(map.touch_points.is_empty(), "release clears touch capture")
	for test_zoom: float in [0.7, 1.45]:
		map.zoom = test_zoom
		map.camera_offset = home
		map.call("_apply_camera")
		var plot := map.target_control_of("plot_1")
		start = plot.get_global_rect().get_center()
		var taps_before := selections
		_touch(start, true)
		_touch(start, false)
		var taps := selections
		_check(taps == taps_before + 1, "stationary building tap works at zoom %.2f" % test_zoom)
		_touch(start, true)
		_drag(start + Vector2(150, 40), Vector2(150, 40))
		_check(map.camera_offset.is_equal_approx(home + Vector2(150, 40)), "building drag uses screen distance at zoom %.2f" % test_zoom)
		_touch(start + Vector2(150, 40), false)
		_check(selections == taps, "releasing a moving building does not activate it")
		_check(map.touch_points.is_empty(), "building release clears gesture")
	map.zoom = 1.0
	map.camera_offset = home
	map.call("_apply_camera")
	start = map.target_control_of("plot_1").get_global_rect().get_center()
	_mouse(start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(-140, 30)
	motion.global_position = motion.position
	motion.relative = Vector2(-140, 30)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	var taps := selections
	_mouse(motion.position, false)
	_check(map.camera_offset.is_equal_approx(home + Vector2(-140, 30)) and selections == taps, "mouse drag from building follows without a click")
	# A GUI overlay owns gestures that begin on it.
	var hud := Button.new()
	hud.position = Vector2(10, 10)
	hud.size = Vector2(300, 100)
	add_child(hud)
	var before := map.camera_offset
	_touch(Vector2(100, 50), true)
	_drag(Vector2(180, 50), Vector2(80, 0))
	_touch(Vector2(180, 50), false)
	_check(map.camera_offset.is_equal_approx(before), "HUD gesture cannot move the map")
	hud.queue_free()
	# Pinch and transition back to one finger without a position discontinuity.
	start = Vector2(300, 1050)
	_touch(start, true, 0)
	_touch(start + Vector2(200, 0), true, 1)
	var anchored_world := (start + Vector2(100, 0) - map.camera_offset) / map.zoom
	_drag(start + Vector2(240, 0), Vector2(40, 0), 1)
	_check((map.camera_offset + anchored_world * map.zoom).is_equal_approx(start + Vector2(120, 0)), "pinch preserves world point under the moving midpoint")
	_touch(start + Vector2(240, 0), false, 1)
	before = map.camera_offset
	_drag(start + Vector2(24, 0), Vector2(24, 0), 0)
	_check(map.camera_offset.is_equal_approx(before + Vector2(24, 0)), "lifting one pinch finger continues a seamless pan")
	_touch(start + Vector2(24, 0), false, 0)
	before = map.camera_offset
	var before_zoom := map.zoom
	map.setup(Game.state.get("plots", []))
	_check(map.camera_offset.is_equal_approx(before) and is_equal_approx(map.zoom, before_zoom), "world refresh preserves the player's camera")
	# Alert badges also wait for a release, so a swipe can start on a badge.
	var plot_button := map.target_control_of("plot_1") as Button
	map.call("_wire_alert_badge", plot_button, "test_dc", "power", -1)
	map.alert_selected.connect(func(_id: String, _kind: String, _slot: int) -> void: alerts += 1)
	await get_tree().create_timer(0.35).timeout
	var badge := plot_button.find_child("StatusBadge", true, false) as Control
	start = badge.get_global_rect().get_center()
	_touch(start, true)
	_check(alerts == 0, "alert does not open on finger down")
	_touch(start, false)
	_check(alerts == 1, "alert opens exactly once on a stationary release")
	before = map.camera_offset
	_touch(start, true)
	_drag(start + Vector2(-60, 0), Vector2(-60, 0))
	_touch(start + Vector2(-60, 0), false)
	_check(alerts == 1 and map.camera_offset.is_equal_approx(before + Vector2(-60, 0)), "dragging an alert badge moves the map without opening it")
	map.reset_camera()
	await get_tree().create_timer(0.07).timeout
	var visible_pose := map.content.position
	_touch(Vector2(400, 1050), true)
	_check(map.camera_offset.is_equal_approx(visible_pose), "touch interrupts recentering at the visible position")
	_drag(Vector2(490, 1050), Vector2(90, 0))
	before = map.content.position
	await get_tree().create_timer(0.35).timeout
	_check(map.content.position.is_equal_approx(before), "canceled camera animation cannot pull against the drag")
	_touch(Vector2(490, 1050), false)
	# Grass features must share the world's transform, including tile wrapping.
	var ground := map.find_child("CampusGroundTexture", false, false) as TextureRect
	var tile := ground.texture.get_size() * map.zoom
	var phase := map.content.position - ground.position
	_check(is_equal_approx(phase.x / tile.x, roundf(phase.x / tile.x)) and is_equal_approx(phase.y / tile.y, roundf(phase.y / tile.y)) and ground.scale.is_equal_approx(map.content.scale), "grass stays anchored to buildings")
	var boundary := map.content.get_node("CampusBoundary_0") as PanelContainer
	_check(boundary.get_theme_stylebox("panel") is StyleBoxEmpty, "campus capacity does not draw a closed UI frame")
	_touch(Vector2(400, 1050), true)
	map.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(map.touch_points.is_empty() and not map.dragging, "app interruption cancels held gestures")
	map.queue_free()
	await get_tree().process_frame
	await _check_headline_interruptions()
	print("MAP_GESTURES: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _check_headline_interruptions() -> void:
	Game.reset_for_tests()
	Game.set_process(false)
	Game.state["tutorial"]["completed"] = true
	Game.state["flags"]["last_presented_era"] = 1
	var main := preload("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.4).timeout
	map = main.park_map
	for overlay_kind: String in ["rare", "ipo"]:
		for pinch: bool in [false, true]:
			var start := Vector2(400, 1150)
			_touch(start, true, 0)
			_drag(start + Vector2(70, 0), Vector2(70, 0), 0)
			if pinch: _touch(start + Vector2(160, 0), true, 1)
			_check(not map.touch_points.is_empty(), "%s fixture really holds %s" % [overlay_kind, "pinch" if pinch else "pan"])
			if overlay_kind == "rare": main.call("_show_rare_event_overlay", "compute_famine")
			else: main.call("_show_ipo_ceremony", Game.company_legacy_summary())
			_check(map.touch_points.is_empty() and not map.dragging and not map._gesture_panning, "%s cancels held pan/pinch on the same frame" % overlay_kind)
			var before := map.camera_offset
			_drag(start + Vector2(150, 0), Vector2(80, 0), 0)
			_check(map.camera_offset.is_equal_approx(before), "%s overlay rejects the stale captured drag" % overlay_kind)
			var close := main.find_child("RareEventConfirm" if overlay_kind == "rare" else "IPOConfirm", true, false) as Button
			close.pressed.emit()
			await get_tree().create_timer(0.4).timeout
			_touch(start, false, 0)
			if pinch: _touch(start + Vector2(160, 0), false, 1)
			before = map.camera_offset
			_touch(start, true, 0)
			_drag(start + Vector2(90, 0), Vector2(90, 0), 0)
			_check(map.camera_offset.is_equal_approx(before + Vector2(90, 0)), "%s close permits a fresh exact-distance pan" % overlay_kind)
			_touch(start + Vector2(90, 0), false, 0)
	main.queue_free()
	await get_tree().process_frame
	Game.set_process(true)

func _touch(point: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _drag(point: Vector2, relative: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.relative = relative
	event.index = index
	get_viewport().push_input(event, true)

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = point
	event.global_position = point
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("MAP_GESTURES: " + message)
