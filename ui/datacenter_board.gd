class_name DatacenterBoard
extends VBoxContainer

const Rules := preload("res://gameplay/game_rules.gd")
const ThemeMaker := preload("res://ui/theme_factory.gd")

signal rack_slot_selected(datacenter_id: String, slot: int)
signal cooler_slot_selected(datacenter_id: String, edge: String)
signal power_slot_selected(datacenter_id: String)

const BOARD_SIZE := Vector2(660, 660)
const CELL_SIZE := Vector2(144, 144)
const GRID_ORIGIN := Vector2(108, 108)
const CELL_STEP := 150.0
const EDGE_LAYOUT := {
	"north": Rect2(212, 10, 236, 88),
	"east": Rect2(562, 246, 88, 168),
	"south": Rect2(212, 562, 236, 88),
	"west": Rect2(10, 246, 88, 168),
}

var datacenter_id := ""
var preview_rack_id := ""
var preview_slot := -1
var _press_started: Dictionary = {}
var _tooltip: PanelContainer
var _stage: Control

func setup(value: String) -> void:
	datacenter_id = value
	if is_node_ready():
		_rebuild()

func _ready() -> void:
	name = "DatacenterBoard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", ThemeMaker.SPACE[2])
	EventBus.state_changed.connect(_on_state_changed)
	resized.connect(_update_stage_scale)
	_rebuild()

# The board stage is authored in a fixed 660x660 coordinate space, but the page
# content area is only 740 minus the sheet's frame insets. The stage minimum must
# never reach layout negotiation at full size, or it widens the whole page and
# pushes the header past the clip rect — so it is capped at build time and only
# shrinks further on narrower parents.
const STAGE_MAX_SCALE := 0.95

func _update_stage_scale() -> void:
	if _stage == null or not is_instance_valid(_stage):
		return
	var board_scale := STAGE_MAX_SCALE
	if size.x > 0.0:
		board_scale = clampf(size.x / BOARD_SIZE.x, 0.5, STAGE_MAX_SCALE)
	_stage.scale = Vector2.ONE * board_scale
	# scale is visual-only; layout must reserve the scaled footprint, otherwise
	# SHRINK_CENTER still centers the unscaled 660u box and overflows the clip.
	_stage.custom_minimum_size = BOARD_SIZE * board_scale

func set_placement_preview(slot: int, rack_id: String) -> void:
	preview_slot = slot
	preview_rack_id = rack_id
	_rebuild()

func clear_placement_preview() -> void:
	if preview_rack_id.is_empty():
		return
	preview_slot = -1
	preview_rack_id = ""
	_rebuild()

func placement_state_for_slot(slot: int, rack_id: String = "") -> Dictionary:
	var dc := Game.find_datacenter(datacenter_id)
	var chosen_rack := rack_id if not rack_id.is_empty() else preview_rack_id
	if dc.is_empty() or chosen_rack.is_empty():
		return {}
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	if slot not in _unlocked_slots(building):
		return {"state": "locked", "symbol": "", "hint": tr("LOCKED"), "color": Color("718096")}
	var racks: Array = dc.get("racks", [])
	if slot < racks.size() and racks[slot] is Dictionary and not racks[slot].is_empty():
		return {"state": "occupied", "symbol": "", "hint": tr("REASON_IN_PROGRESS"), "color": Color("718096")}
	var simulated := dc.duplicate(true)
	var simulated_racks: Array = simulated.get("racks", []).duplicate(true)
	while simulated_racks.size() < 9:
		simulated_racks.append(null)
	simulated_racks[slot] = {"rack_id": chosen_rack, "status": "active", "enabled": true}
	simulated["racks"] = simulated_racks
	var runtime := Rules.rack_runtime_status(simulated, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	if not bool(runtime.get("powered", false)):
		return {"state": "power", "symbol": "⚡", "hint": tr("BOARD_NEED_POWER"), "color": ThemeMaker.SEMANTIC.get("danger", ThemeMaker.COLORS.red)}
	if bool(runtime.get("overheated", false)):
		return {"state": "heat", "symbol": "heat", "hint": tr("BOARD_OVERHEAT_HINT"), "color": ThemeMaker.SEMANTIC.get("warning", ThemeMaker.COLORS.orange)}
	return {"state": "ok", "symbol": "✓", "hint": tr("BOARD_PLACE_OK"), "color": ThemeMaker.SEMANTIC.get("success", ThemeMaker.COLORS.green)}

func tutorial_target_rect(focus: String) -> Rect2:
	if focus == "rack_slot_0":
		var slot := find_child("RackSlot0", true, false) as Control
		return slot.get_global_rect() if slot != null else Rect2()
	if focus == "install_power":
		var power := find_child("PowerSlot", true, false) as Control
		return power.get_global_rect() if power != null else Rect2()
	if focus == "install_cooler":
		for edge: String in ["north", "east", "south", "west"]:
			var cooler := find_child("Cooler_%s" % edge, true, false) as Control
			if cooler != null:
				return cooler.get_global_rect()
	return Rect2()

func _on_state_changed(reason: String) -> void:
	if reason not in ["tick", "offline_advance"] and is_inside_tree():
		call_deferred("_rebuild")

func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_tooltip = null
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		return
	var stage := Control.new()
	stage.name = "BoardStage"
	stage.custom_minimum_size = BOARD_SIZE
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(stage)
	_stage = stage
	_update_stage_scale()
	_add_interior(stage)
	_add_coverage(stage, dc)
	_add_slots(stage, dc)
	_add_coolers(stage, dc)
	_add_power_meter(dc)

func _add_interior(stage: Control) -> void:
	var frame := PanelContainer.new()
	frame.position = Vector2(98, 98)
	frame.size = Vector2(464, 464)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("0c1c2c"), Color(ThemeMaker.COLORS.sky, 0.48), 2, 24))
	stage.add_child(frame)
	var texture := AssetCatalog.texture("dc_interior_bg")
	if texture != null:
		var view := TextureRect.new()
		view.texture = texture
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_child(view)

func _add_coverage(stage: Control, dc: Dictionary) -> void:
	for edge: String in Rules.COOLER_EDGES:
		if str(dc.get("coolers", {}).get(edge, "")).is_empty():
			continue
		for slot: int in Rules.COOLER_EDGES[edge]:
			var frost := TextureRect.new()
			frost.name = "CoolingCoverage_%s_%d" % [edge, slot]
			frost.texture = AssetCatalog.texture("fx_frost_patch")
			frost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frost.stretch_mode = TextureRect.STRETCH_SCALE
			frost.position = _cell_position(slot)
			frost.size = CELL_SIZE
			frost.modulate = Color(0.48, 0.90, 1.0, 0.25)
			frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frost.pivot_offset = Vector2(0, CELL_SIZE.y * 0.5)
			frost.scale.x = 0.0
			stage.add_child(frost)
			frost.create_tween().tween_property(frost, "scale:x", 1.0, 0.30).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _add_slots(stage: Control, dc: Dictionary) -> void:
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var unlocked := _unlocked_slots(building)
	var racks: Array = dc.get("racks", [])
	for slot: int in range(9):
		var button := Button.new()
		button.name = "RackSlot%d" % slot
		button.position = _cell_position(slot)
		button.size = CELL_SIZE
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = tr("EMPTY_SLOT")
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var open := slot in unlocked
		var installed: Variant = racks[slot] if slot < racks.size() else null
		var fill := Color("18293c", 0.82)
		var border := Color("8db8d5", 0.54)
		if not open:
			fill = Color("14202d", 0.84)
			border = Color("677687", 0.45)
		var runtime: Dictionary = {}
		if installed is Dictionary and not installed.is_empty():
			runtime = Rules.rack_runtime_status(dc, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
			if bool(runtime.get("faulted", false)):
				fill = Color(ThemeMaker.SEMANTIC.get("danger", ThemeMaker.COLORS.red), 0.32)
				border = ThemeMaker.SEMANTIC.get("danger", ThemeMaker.COLORS.red)
			elif bool(runtime.get("overheated", false)):
				fill = Color(ThemeMaker.SEMANTIC.get("warning", ThemeMaker.COLORS.orange), 0.35)
				border = ThemeMaker.SEMANTIC.get("warning", ThemeMaker.COLORS.orange)
		elif open:
			fill = Color("18293c", 0.82)
			border = Color("8db8d5", 0.54)
		if not preview_rack_id.is_empty():
			var placement := placement_state_for_slot(slot)
			if not placement.is_empty():
				if str(placement.get("state", "")) in ["locked", "occupied"]:
					button.modulate = Color(0.58, 0.62, 0.68, 0.78)
				else:
					border = Color(placement.get("color", ThemeMaker.COLORS.sky), 0.90)
					fill = Color(placement.get("color", ThemeMaker.COLORS.sky), 0.16)
		if not preview_rack_id.is_empty() and slot == preview_slot:
			border = Color.WHITE
		var overheat_border: bool = installed is Dictionary and not installed.is_empty() and bool(runtime.get("overheated", false))
		var normal := ThemeMaker.panel(fill, border, 4 if overheat_border else (3 if slot == preview_slot else 2), 18)
		normal.content_margin_left = 6
		normal.content_margin_right = 6
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", ThemeMaker.panel(fill.lightened(0.08), border, 3, 18))
		button.add_theme_stylebox_override("pressed", ThemeMaker.panel(fill.darkened(0.08), border, 3, 18))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		stage.add_child(button)
		_add_slot_art(button, open, installed, runtime)
		if not preview_rack_id.is_empty():
			_add_preview_badge(button, placement_state_for_slot(slot))
		button.gui_input.connect(_on_slot_input.bind(slot, open, installed, button))

func _add_slot_art(button: Button, open: bool, installed: Variant, runtime: Dictionary) -> void:
	var asset_id := "slot_empty" if open else "slot_locked"
	if installed is Dictionary and not installed.is_empty():
		var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
		var suffix := "_active"
		if str(installed.get("status", "")) == "installing":
			suffix = "_installing"
		elif bool(runtime.get("faulted", false)) or bool(runtime.get("repairing", false)):
			suffix = "_fault"
		elif not bool(runtime.get("powered", false)) or not bool(installed.get("enabled", true)):
			suffix = "_dark"
		asset_id = str(rack.get("asset_prefix", "")) + suffix
		button.tooltip_text = "%s · %s" % [tr(rack.get("name_key", "")), _runtime_text(installed, runtime)]
	var view := TextureRect.new()
	view.name = "RackArt"
	view.texture = AssetCatalog.texture(asset_id)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_left = 8
	view.offset_top = 8
	view.offset_right = -8
	view.offset_bottom = -8
	button.add_child(view)
	if installed is Dictionary and not installed.is_empty() and str(installed.get("status", "")) == "installing":
		var complete_at := float(installed.get("install_complete_at", Game.simulation_time()))
		var rack_data := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
		var duration := maxf(1.0, float(rack_data.get("install_seconds", complete_at - float(installed.get("started_at", Game.simulation_time())))))
		var timer := Widgets.timer_bar(complete_at, duration)
		timer.name = "RackInstallTimer"
		timer.position = Vector2(8, 82)
		timer.size = Vector2(CELL_SIZE.x - 16, 54)
		timer.z_index = 4
		var progress := timer.find_child("TimerProgress", true, false) as ProgressBar
		if progress != null:
			progress.custom_minimum_size.y = 16
		var remaining := timer.find_child("TimerRemaining", true, false) as Label
		if remaining != null:
			remaining.add_theme_font_size_override("font_size", 18)
			remaining.add_theme_color_override("font_color", Color.WHITE)
			remaining.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
			remaining.add_theme_constant_override("outline_size", 3)
		button.add_child(timer)
	if installed is Dictionary and not installed.is_empty() and (bool(runtime.get("overheated", false)) or bool(runtime.get("faulted", false)) or not bool(runtime.get("powered", true))):
		var icon := TextureRect.new()
		icon.name = "RackStatus"
		icon.texture = AssetCatalog.texture("ic_wrench" if bool(runtime.get("faulted", false)) else ("ic_heat" if bool(runtime.get("overheated", false)) else "ic_power"))
		icon.position = Vector2(96, 6)
		icon.size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)

func _add_preview_badge(button: Button, state: Dictionary) -> void:
	if state.is_empty():
		return
	var badge := PanelContainer.new()
	badge.name = "PlacementState"
	badge.set_meta("placement_state", str(state.get("state", "")))
	badge.position = Vector2(98, 6)
	badge.size = Vector2(40, 40)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	var symbol := str(state.get("symbol", ""))
	if symbol.is_empty():
		badge.visible = false
		return
	var badge_style := ThemeMaker.panel(state.get("color", ThemeMaker.COLORS.sky), Color.WHITE, 2, 20)
	badge_style.content_margin_left = 0
	badge_style.content_margin_top = 0
	badge_style.content_margin_right = 0
	badge_style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	var label := Label.new()
	label.name = "PlacementSymbol"
	label.text = "♨" if symbol == "heat" else symbol
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(label)

func _add_coolers(stage: Control, dc: Dictionary) -> void:
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var cooler_slots := int(building.get("cooler_slots", 0))
	var edges := ["north", "east", "south", "west"]
	for edge_index: int in range(edges.size()):
		var edge := str(edges[edge_index])
		var rect: Rect2 = EDGE_LAYOUT[edge]
		var button := Button.new()
		button.name = "Cooler_%s" % edge
		button.position = rect.position
		button.size = rect.size
		button.focus_mode = Control.FOCUS_NONE
		var slot_available := edge_index < cooler_slots
		var cooler_id := str(dc.get("coolers", {}).get(edge, ""))
		var installed := slot_available and not cooler_id.is_empty()
		button.set_meta("cooler_state", "installed" if installed else ("available" if slot_available else "locked"))
		button.tooltip_text = tr("LOCKED") if not slot_available else (tr("INSTALL") if not installed else tr(DataRepository.get_entry("attachments", cooler_id).get("name_key", "INSTALL")))
		ThemeMaker.apply_icon_button(button)
		var accent := ThemeMaker.COLORS.cyan if installed else Color.TRANSPARENT
		button.add_theme_stylebox_override("normal", ThemeMaker.flat_group_box(accent, 8))
		button.add_theme_stylebox_override("hover", ThemeMaker.flat_group_box(ThemeMaker.COLORS.sky if slot_available else Color.TRANSPARENT, 8))
		button.add_theme_stylebox_override("pressed", ThemeMaker.flat_group_box(ThemeMaker.COLORS.sky if slot_available else Color.TRANSPARENT, 8))
		# Exactly one branch owns the icon. Keeping the art in a dedicated child
		# avoids Button's inherited icon being drawn under an installed cooler.
		button.icon = null
		var cooler_art := TextureRect.new()
		cooler_art.name = "CoolerArt"
		cooler_art.texture = AssetCatalog.texture("ic_lock" if not slot_available else ("ic_cooling" if cooler_id.is_empty() else cooler_id + "_active"))
		cooler_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cooler_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cooler_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cooler_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cooler_art.offset_left = 12
		cooler_art.offset_top = 12
		cooler_art.offset_right = -12
		cooler_art.offset_bottom = -12
		button.add_child(cooler_art)
		button.modulate = Color(1, 1, 1, 0.38) if not slot_available else (Color.WHITE if installed else Color(1, 1, 1, 0.78))
		button.pressed.connect(func() -> void:
			if slot_available:
				cooler_slot_selected.emit(datacenter_id, edge)
			else:
				EventBus.toast_requested.emit("LOCKED", {})
		)
		stage.add_child(button)

func _add_power_meter(dc: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeMaker.flat_group_box(ThemeMaker.COLORS.yellow))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeMaker.SPACE[2])
	panel.add_child(row)
	var power := Button.new()
	power.name = "PowerSlot"
	power.custom_minimum_size = Vector2(170, 88)
	power.focus_mode = Control.FOCUS_NONE
	ThemeMaker.apply_compact_button(power, ThemeMaker.COLORS.yellow)
	var power_id := str(dc.get("power_unit", ""))
	power.icon = AssetCatalog.texture("ic_power" if power_id.is_empty() else power_id + "_active")
	power.expand_icon = true
	power.add_theme_constant_override("icon_max_width", 48)
	power.text = tr("INSTALL") if power_id.is_empty() else tr(DataRepository.get_entry("attachments", power_id).get("name_key", "POWERED"))
	power.pressed.connect(func() -> void: power_slot_selected.emit(datacenter_id))
	row.add_child(power)
	var meter_box := VBoxContainer.new()
	meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_box.add_theme_constant_override("separation", ThemeMaker.SPACE[1])
	row.add_child(meter_box)
	var capacity := float(DataRepository.get_entry("attachments", power_id).get("capacity", 0.0))
	var used := _power_demand(dc)
	var label := Label.new()
	label.text = tr("BOARD_POWER_USAGE") % [Game.format_number(used), Game.format_number(capacity)]
	label.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
	label.add_theme_color_override("font_color", ThemeMaker.COLORS.cream)
	meter_box.add_child(label)
	var progress := ProgressBar.new()
	progress.name = "BoardPowerMeter"
	progress.show_percentage = false
	progress.custom_minimum_size.y = 40
	var meter_background := ThemeMaker.panel(Color("0a1725"), Color(1, 1, 1, 0.12), 1, 20)
	meter_background.content_margin_left = 0
	meter_background.content_margin_right = 0
	meter_background.content_margin_top = 0
	meter_background.content_margin_bottom = 0
	var meter_fill := ThemeMaker.panel(ThemeMaker.COLORS.yellow, Color(1, 1, 1, 0.22), 1, 20)
	meter_fill.content_margin_left = 0
	meter_fill.content_margin_right = 0
	meter_fill.content_margin_top = 0
	meter_fill.content_margin_bottom = 0
	progress.add_theme_stylebox_override("background", meter_background)
	progress.add_theme_stylebox_override("fill", meter_fill)
	progress.max_value = maxf(1.0, maxf(capacity, used))
	progress.value = used
	if used > capacity:
		progress.modulate = ThemeMaker.COLORS.red
		var warning_tween := progress.create_tween().set_loops()
		warning_tween.tween_property(progress, "modulate:a", 0.48, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		warning_tween.tween_property(progress, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	meter_box.add_child(progress)

func _power_demand(dc: Dictionary) -> float:
	var result := 0.0
	for installed: Variant in dc.get("racks", []):
		if installed is Dictionary and not installed.is_empty() and str(installed.get("status", "")) != "installing" and bool(installed.get("enabled", true)):
			result += float(DataRepository.get_entry("racks", str(installed.get("rack_id", ""))).get("power", 0.0))
	return result

func _on_slot_input(event: InputEvent, slot: int, open: bool, installed: Variant, button: Button) -> void:
	var pressed := false
	var released := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
	if pressed:
		_press_started[slot] = Time.get_ticks_msec()
		button.accept_event()
	elif released:
		var duration := Time.get_ticks_msec() - int(_press_started.get(slot, Time.get_ticks_msec()))
		_press_started.erase(slot)
		button.accept_event()
		if duration >= 450 and installed is Dictionary and not installed.is_empty():
			_show_rack_tooltip(slot, button)
		elif open:
			rack_slot_selected.emit(datacenter_id, slot)

func _show_rack_tooltip(slot: int, anchor: Control) -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
	var dc := Game.find_datacenter(datacenter_id)
	var installed: Dictionary = dc.get("racks", [])[slot]
	var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
	var runtime := Rules.rack_runtime_status(dc, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
	_tooltip = PanelContainer.new()
	_tooltip.name = "RackTooltip"
	_tooltip.position = anchor.position + Vector2(-12, -116)
	_tooltip.custom_minimum_size.x = 320
	_tooltip.z_index = 20
	_tooltip.add_theme_stylebox_override("panel", ThemeMaker.flat_group_box(ThemeMaker.COLORS.cyan))
	var label := Label.new()
	label.text = "%s\n⚡%s  ♨%s  ❄%s  $%s" % [tr(rack.get("name_key", "")), Game.format_number(float(rack.get("power", 0.0))), Game.format_number(float(rack.get("heat", 0.0))), Game.format_number(float(runtime.get("cooling", 0.0))), Game.format_number(float(rack.get("income_per_month", 0.0)))]
	label.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
	label.add_theme_constant_override("line_spacing", ThemeMaker.TEXT_LINE_SPACING)
	_tooltip.add_child(label)
	anchor.get_parent().add_child(_tooltip)
	_tooltip.size = _tooltip.get_combined_minimum_size()
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(_tooltip):
			_tooltip.queue_free()
	)

func _unlocked_slots(building: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in building.get("unlocked_slots", []):
		result.append(int(value))
	return result

func _cell_position(slot: int) -> Vector2:
	return GRID_ORIGIN + Vector2(slot % 3, slot / 3) * CELL_STEP

func _runtime_text(installed: Dictionary, runtime: Dictionary) -> String:
	if str(installed.get("status", "")) == "installing": return tr("INSTALLING")
	if bool(runtime.get("faulted", false)): return tr("FAULTED")
	if bool(runtime.get("repairing", false)): return tr("REPAIR")
	if not bool(installed.get("enabled", true)): return tr("RACK_DISABLED")
	if not bool(runtime.get("powered", false)): return tr("UNPOWERED")
	if bool(runtime.get("overheated", false)): return tr("OVERHEATED")
	return tr("POWERED")
