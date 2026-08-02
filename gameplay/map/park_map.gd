class_name ParkMap
extends Control

const Rules := preload("res://gameplay/game_rules.gd")

signal datacenter_selected(datacenter_id: String)
signal empty_plot_selected(plot_id: String)
signal buy_plot_requested

const MIN_ZOOM := 0.7
const MAX_ZOOM := 1.45

var content: Control
var zoom := 1.0
var camera_offset := Vector2(90, 70)
var dragging := false
var last_pointer := Vector2.ZERO
var touch_points: Dictionary = {}
var last_pinch_distance := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(0, 900)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var ground_fill := ColorRect.new()
	ground_fill.color = Color("7bc94c")
	ground_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground_fill)
	var ground_texture := AssetCatalog.texture("ground_tile")
	if ground_texture != null:
		var ground_view := TextureRect.new()
		ground_view.texture = ground_texture
		ground_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ground_view.stretch_mode = TextureRect.STRETCH_SCALE
		ground_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(ground_view)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)
	_apply_camera()

func setup(plots: Array) -> void:
	if content == null:
		await ready
	for child: Node in content.get_children():
		child.queue_free()
	_add_decorations()
	for index: int in range(plots.size()):
		var plot: Dictionary = plots[index]
		var position := _plot_position(index)
		content.add_child(_plot_button(plot, position))
	var sale := Button.new()
	sale.text = "+\n%s" % tr("BUY_NEXT_PLOT")
	sale.position = _plot_position(plots.size())
	sale.size = Vector2(360, 215)
	sale.add_theme_font_size_override("font_size", 24)
	sale.pressed.connect(func() -> void: buy_plot_requested.emit())
	_apply_icon(sale, "plot_forsale")
	_apply_style(sale, Color("6b4d38"), Color("ffc93c"))
	content.add_child(sale)
	queue_redraw()

func _add_decorations() -> void:
	_add_decoration("deco_road", Vector2(220, 310), Vector2(500, 105), false)
	_add_decoration("deco_tree", Vector2(20, 385), Vector2(130, 130))
	_add_decoration("deco_bush", Vector2(700, 475), Vector2(90, 90))
	_add_decoration("deco_pylon", Vector2(785, 315), Vector2(120, 120))

func _add_decoration(asset_id: String, at: Vector2, dimensions: Vector2, preserve_aspect: bool = true) -> void:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if preserve_aspect else TextureRect.STRETCH_SCALE
	view.position = at
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(view)

func _plot_button(plot: Dictionary, at: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = Vector2(360, 215)
	button.add_theme_font_size_override("font_size", 24)
	var status := str(plot.get("status", "empty"))
	var color := Color("577b45")
	var border := Color("7bc94c")
	match status:
		"empty":
			button.text = "%s\n#%d" % [tr("PLOT_EMPTY") % int(plot.get("index", 0)), int(plot.get("index", 0))]
			button.pressed.connect(func() -> void: empty_plot_selected.emit(str(plot.get("id", ""))))
			_apply_icon(button, "plot_owned")
		"building":
			button.text = "🏗\n%s" % tr("INSTALLING")
			color = Color("8d5d32")
			border = Color("ff8a3d")
			var construction := Game.find_construction(str(plot.get("construction_id", "")))
			var building := DataRepository.get_entry("buildings", str(construction.get("building_id", "")))
			_apply_icon(button, str(building.get("asset_prefix", "")) + "_construction")
		"ruined":
			var dc: Dictionary = plot.get("datacenter", {})
			button.text = "⚠\n%s" % tr("DEMOLISH")
			button.pressed.connect(func() -> void: datacenter_selected.emit(str(dc.get("id", ""))))
			color = Color("653d46")
			border = Color("ff5a5a")
			var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
			_apply_icon(button, str(building.get("asset_prefix", "")) + "_ruin")
		_:
			var dc: Dictionary = plot.get("datacenter", {})
			var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
			button.text = "%s\n%s" % [tr(building.get("name_key", "")), tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc))]
			button.pressed.connect(func() -> void: datacenter_selected.emit(str(dc.get("id", ""))))
			color = Color("315b7e") if not str(dc.get("power_unit", "")).is_empty() else Color("3d4857")
			border = Color("3aa7f0")
			_apply_icon(button, _datacenter_asset_id(dc, building))
	_apply_style(button, color, border)
	return button

func _plot_position(index: int) -> Vector2:
	var column := index % 2
	var row := index / 2
	return Vector2(column * 410 + (45 if row % 2 else 0), row * 255)

func _datacenter_asset_id(dc: Dictionary, building: Dictionary) -> String:
	var suffix := "_dark"
	if not str(dc.get("power_unit", "")).is_empty():
		var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
		match Rules.aging_stage(progress):
			"aging": suffix = "_aged"
			"decline": suffix = "_decayed"
			_: suffix = "_active"
	return str(building.get("asset_prefix", "")) + suffix

func _apply_style(button: Button, fill: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.border_color = border
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(34)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 18
	normal.content_margin_bottom = 18
	button.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.darkened(0.18)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover", normal)

func _apply_icon(button: Button, asset_id: String) -> void:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 150)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, zoom + 0.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, zoom - 0.1)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			last_pointer = event.position
	elif event is InputEventMouseMotion and dragging:
		camera_offset += event.position - last_pointer
		last_pointer = event.position
		_apply_camera()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
		else:
			touch_points.erase(event.index)
		last_pinch_distance = _pinch_distance()
	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position
		if touch_points.size() == 1:
			camera_offset += event.relative
			_apply_camera()
		else:
			var distance := _pinch_distance()
			if last_pinch_distance > 0.0:
				_zoom_at(_touch_center(), zoom * distance / last_pinch_distance)
			last_pinch_distance = distance
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, zoom * event.factor)
		accept_event()

func _zoom_at(local_point: Vector2, target_zoom: float) -> void:
	var old_zoom := zoom
	zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, zoom):
		return
	var world_point := (local_point - camera_offset) / old_zoom
	camera_offset = local_point - world_point * zoom
	_apply_camera()

func _apply_camera() -> void:
	if content == null:
		return
	content.position = camera_offset
	content.scale = Vector2.ONE * zoom

func _pinch_distance() -> float:
	if touch_points.size() < 2:
		return 0.0
	var points: Array = touch_points.values()
	return (Vector2(points[0]) - Vector2(points[1])).length()

func _touch_center() -> Vector2:
	var points: Array = touch_points.values()
	return (Vector2(points[0]) + Vector2(points[1])) * 0.5 if points.size() >= 2 else Vector2.ZERO
