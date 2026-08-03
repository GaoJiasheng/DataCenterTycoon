class_name ParkMap
extends Control

const Rules := preload("res://gameplay/game_rules.gd")
const ThemeMaker := preload("res://ui/theme_factory.gd")

signal datacenter_selected(datacenter_id: String)
signal empty_plot_selected(plot_id: String)
signal buy_plot_requested
signal alert_selected(datacenter_id: String, alert_type: String, slot: int)

const MIN_ZOOM := 0.7
const MAX_ZOOM := 1.45
const PLOT_SIZE := Vector2(344, 260)
const PLOT_LANE := 40.0
const CAMPUS_LEFT := 38.0
const CAMPUS_TOP := 18.0
const COLUMN_STEP := 384.0 # PLOT_SIZE.x + PLOT_LANE
const ISO_RISE := 192.0 # 2:1 axis rise for one column step
const ROW_STEP := 384.0
const CAMPUS_SAFE_TOP := 360.0
const CAMPUS_SAFE_BOTTOM := 420.0
const ISO_ANGLE := 0.463648 # atan(0.5), the shared world-art perspective.
const DAY_TINT := Color(1.0, 0.97, 0.90)
const EVENING_TINT := Color(1.0, 0.88, 0.78)
const NIGHT_TINT := Color(0.72, 0.78, 0.95)
const CAMERA_BREATH_DELAY := 8.0
const CAMERA_BREATH_ZOOM := 0.02
const CAMPUS_PROP_IDS := [
	"prop_flagpole",
	"prop_lamp",
	"prop_bush_row",
	"prop_parking",
	"prop_transformer_yard",
]
const CAMPUS_PROP_SIZES := [
	Vector2(96, 126),
	Vector2(78, 118),
	Vector2(142, 90),
	Vector2(160, 132),
	Vector2(156, 140),
]

var content: Control
var zoom := 1.02
var camera_offset := Vector2(-8, 300)
var dragging := false
var last_pointer := Vector2.ZERO
var touch_points: Dictionary = {}
var last_pinch_distance := 0.0
var world_size := Vector2(804, 1748)
var target_buttons: Dictionary = {}
var _ambient_time := 0.0
var _active_art: Array[TextureRect] = []
var _sway_art: Array[TextureRect] = []
var _glow_art: Array[TextureRect] = []
var _construction_labels: Array[Dictionary] = []
var _countdown_accumulator := 0.0
var _campus_bounds := Rect2()
var _default_zoom := 1.02
var _default_camera_offset := Vector2(-8, 300)
var _world_texture_cache: Dictionary = {}
var _grade_refresh_accumulator := 0.0
var _window_light_boost := 1.0
var _preview_hour := -1.0
var _edge_fog: TextureRect
var _idle_seconds := 0.0
var _camera_breath_phase := 0.0
var _camera_breathing := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_apply_camera)
	var ground_fill := ColorRect.new()
	ground_fill.color = Color("7bc94c")
	ground_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground_fill)
	var ground_texture := AssetCatalog.texture("ground_tile_grass")
	if ground_texture == null:
		ground_texture = AssetCatalog.texture("ground_tile")
	if ground_texture != null:
		var ground_view := TextureRect.new()
		ground_view.name = "CampusGroundTexture"
		ground_view.texture = ground_texture
		ground_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ground_view.stretch_mode = TextureRect.STRETCH_TILE
		ground_view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ground_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(ground_view)
	var top_shade := TextureRect.new()
	var shade_gradient := Gradient.new()
	shade_gradient.colors = PackedColorArray([Color(0.02, 0.06, 0.10, 0.20), Color(0.02, 0.06, 0.10, 0.0)])
	shade_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = shade_gradient
	shade_texture.fill_from = Vector2(0.5, 0.0)
	shade_texture.fill_to = Vector2(0.5, 1.0)
	top_shade.texture = shade_texture
	top_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_shade.offset_bottom = 360
	add_child(top_shade)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)
	var fog_texture := AssetCatalog.texture("world_edge_fog")
	if fog_texture != null:
		_edge_fog = TextureRect.new()
		_edge_fog.name = "WorldEdgeFog"
		_edge_fog.texture = fog_texture
		_edge_fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_edge_fog.stretch_mode = TextureRect.STRETCH_SCALE
		_edge_fog.modulate = Color(1, 1, 1, 0.25)
		_edge_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_edge_fog)
	_refresh_day_grade(true)
	_apply_camera()
	set_process(true)

func _process(delta: float) -> void:
	_ambient_time += delta
	if _edge_fog != null and is_instance_valid(_edge_fog):
		_edge_fog.modulate.a = 0.25 + sin(_ambient_time * 0.23) * 0.025
	_grade_refresh_accumulator += delta
	if _grade_refresh_accumulator >= 30.0:
		_grade_refresh_accumulator = 0.0
		_refresh_day_grade()
	for index: int in range(_active_art.size()):
		var art := _active_art[index]
		if is_instance_valid(art):
			# Only the powered window light breathes. Scaling the full building every
			# frame fights completion tweens and reads as layout jank.
			var phase := float(art.get_meta("ambient_phase", float(index) * 1.7))
			var light_pulse := 1.03 + sin(_ambient_time * 0.82 + phase) * 0.03
			var brightness := _window_light_boost * light_pulse
			art.self_modulate = Color(brightness, brightness, brightness, 1.0)
	for index: int in range(_sway_art.size()):
		var art := _sway_art[index]
		if is_instance_valid(art):
			art.rotation = sin(_ambient_time * 0.72 + index * 1.31) * 0.012
	for index: int in range(_glow_art.size()):
		var glow := _glow_art[index]
		if is_instance_valid(glow):
			glow.modulate.a = 0.11 + sin(_ambient_time * 1.8 + index) * 0.045
			glow.rotation = _ambient_time * (0.035 if index % 2 == 0 else -0.03)
	_countdown_accumulator += delta
	if _countdown_accumulator >= 1.0:
		_countdown_accumulator = 0.0
		_refresh_construction_labels()
	_update_camera_breath(delta)

func color_grade_for_hour(hour: float) -> Dictionary:
	var wrapped := fposmod(hour, 24.0)
	if wrapped < 6.0:
		return {"tint": NIGHT_TINT, "window_boost": 1.30}
	if wrapped < 9.0:
		var dawn := smoothstep(6.0, 9.0, wrapped)
		return {"tint": NIGHT_TINT.lerp(DAY_TINT, dawn), "window_boost": lerpf(1.30, 1.0, dawn)}
	if wrapped < 16.0:
		return {"tint": DAY_TINT, "window_boost": 1.0}
	if wrapped < 19.0:
		var sunset := smoothstep(16.0, 19.0, wrapped)
		return {"tint": DAY_TINT.lerp(EVENING_TINT, sunset), "window_boost": lerpf(1.0, 1.12, sunset)}
	if wrapped < 22.0:
		var nightfall := smoothstep(19.0, 22.0, wrapped)
		return {"tint": EVENING_TINT.lerp(NIGHT_TINT, nightfall), "window_boost": lerpf(1.12, 1.30, nightfall)}
	return {"tint": NIGHT_TINT, "window_boost": 1.30}

func current_grade_hour() -> float:
	if _preview_hour >= 0.0:
		return _preview_hour
	var clock := Time.get_time_dict_from_system()
	return float(clock.get("hour", 12)) + float(clock.get("minute", 0)) / 60.0 + float(clock.get("second", 0)) / 3600.0

func is_night_grade() -> bool:
	var hour := current_grade_hour()
	return hour < 6.0 or hour >= 22.0

func set_preview_hour(hour: float) -> void:
	_preview_hour = fposmod(hour, 24.0)
	_refresh_day_grade(true)

func clear_preview_hour() -> void:
	_preview_hour = -1.0
	_refresh_day_grade(true)

func _refresh_day_grade(immediate: bool = false) -> void:
	var hour := current_grade_hour()
	var grade := color_grade_for_hour(hour)
	var target_tint: Color = grade.get("tint", DAY_TINT)
	_window_light_boost = float(grade.get("window_boost", 1.0))
	if immediate or not is_inside_tree():
		modulate = target_tint
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate", target_tint, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func setup(plots: Array) -> void:
	if content == null:
		await ready
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	target_buttons.clear()
	_active_art.clear()
	_sway_art.clear()
	_glow_art.clear()
	_construction_labels.clear()
	notify_user_input()
	var owned_count := plots.size()
	var slot_count := owned_count + 1 # Include the next purchasable parcel.
	_campus_bounds = Rect2()
	_add_campus_paths(plots)
	_add_environment_props(plots)
	_add_decorations(slot_count)
	for index: int in range(plots.size()):
		var plot: Dictionary = plots[index]
		var position := _plot_position(index, owned_count)
		var plot_button := _plot_button(plot, position)
		_configure_grid_slot(plot_button, index, position)
		content.add_child(plot_button)
		_include_campus_rect(Rect2(position, PLOT_SIZE))
		target_buttons[str(plot.get("id", ""))] = plot_button
		var raw_dc: Variant = plot.get("datacenter", {})
		if raw_dc is Dictionary and not raw_dc.is_empty():
			var dc: Dictionary = raw_dc
			target_buttons[str(dc.get("id", ""))] = plot_button
	var sale := _world_button(
		"plot_pad_sale" if AssetCatalog.has_asset("plot_pad_sale") else "plot_forsale",
		"$%s" % Game.format_number(Game.next_plot_price()),
		ThemeMaker.COLORS.yellow,
		"ic_cash",
		"price"
	)
	sale.position = _sale_position(owned_count)
	_configure_grid_slot(sale, owned_count, sale.position)
	sale.pressed.connect(func() -> void: buy_plot_requested.emit())
	content.add_child(sale)
	_include_campus_rect(Rect2(sale.position, PLOT_SIZE))
	target_buttons["sale"] = sale
	world_size = Vector2(804, maxf(1748.0, _campus_bounds.end.y + 560.0))
	_frame_campus(false)
	queue_redraw()

func reset_camera() -> void:
	notify_user_input()
	zoom = _default_zoom
	camera_offset = _default_camera_offset
	_animate_camera()

func focus_target(target_id: String) -> void:
	notify_user_input()
	var target := target_buttons.get(target_id) as Control
	if target == null:
		return
	zoom = 1.10
	var world_center := target.position + target.size * 0.5
	camera_offset = Vector2(size.x * 0.5, size.y * 0.35) - world_center * zoom
	_clamp_camera_offset()
	_animate_camera()

func target_global_position(target_id: String) -> Vector2:
	var target := target_buttons.get(target_id) as Control
	return target.get_global_rect().get_center() if target != null else Vector2.ZERO

func world_position_of(target_id: String) -> Vector2:
	var target := target_buttons.get(target_id) as Control
	if target == null:
		return Vector2.ZERO
	var art := target.find_child("WorldArt", true, false) as Control
	# Coins originate from the visible building, not the plot button's lower
	# status rail. A slight upward bias keeps the burst over the roofline.
	return art.get_global_rect().get_center() + Vector2(0, -30) if art != null else target.get_global_rect().get_center()

func target_control_of(target_id: String) -> Control:
	return target_buttons.get(target_id) as Control

func celebrate_target(target_id: String) -> void:
	var target := target_buttons.get(target_id) as Control
	if target == null:
		return
	target.pivot_offset = target.size * Vector2(0.5, 0.82)
	target.scale = Vector2(1.0, 0.18)
	var tween := target.create_tween()
	tween.tween_property(target, "scale", Vector2(1.04, 1.08), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func play_construction_completion(plot_id: String) -> void:
	var target := target_buttons.get(plot_id) as Control
	if target == null or not is_instance_valid(target):
		return
	var art := target.find_child("WorldArt", false, false) as TextureRect
	var plot := Game.find_plot(plot_id)
	var dc: Variant = plot.get("datacenter", {})
	if art == null or not dc is Dictionary:
		return
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var scaffold_texture := AssetCatalog.texture(str(building.get("asset_prefix", "")) + "_construction")
	var scaffold := _world_art_overlay(target, art, scaffold_texture, "ConstructionGhost")
	art.modulate.a = 0.0
	art.scale = Vector2.ONE * 0.90
	for index: int in range(3):
		_spawn_local_fx(
			target,
			"fx_dust_puff",
			Vector2(-78.0 + float(index) * 78.0, 74.0 + absf(1.0 - float(index)) * 10.0),
			Vector2(96, 96),
			float(index) * 0.07,
			"CompletionDust%d" % index
		)
	var tween := target.create_tween().set_parallel(true)
	tween.tween_property(art, "modulate:a", 1.0, 0.20)
	tween.tween_property(art, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if scaffold != null:
		tween.tween_property(scaffold, "modulate:a", 0.0, 0.30)
		tween.tween_property(scaffold, "scale", Vector2.ONE * 1.03, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.finished.connect(scaffold.queue_free)

func play_power_on(datacenter_id: String) -> void:
	var target := target_buttons.get(datacenter_id) as Control
	if target == null or not is_instance_valid(target):
		return
	var art := target.find_child("WorldArt", false, false) as TextureRect
	var dc := Game.find_datacenter(datacenter_id)
	if art == null or dc.is_empty():
		return
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var dark_texture := AssetCatalog.texture(str(building.get("asset_prefix", "")) + "_dark")
	var dark_art := _world_art_overlay(target, art, dark_texture, "PowerOnDarkGhost")
	art.modulate.a = 0.0
	var ring := _spawn_local_fx(target, "fx_glow_ring", Vector2.ZERO, Vector2(264, 264), 0.0, "PowerOnGlow")
	if ring != null:
		ring.position = target.size * 0.5 - ring.size * 0.5 + Vector2(0, 10)
	var tween := target.create_tween().set_parallel(true)
	tween.tween_property(art, "modulate:a", 1.0, 0.60).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if dark_art != null:
		tween.tween_property(dark_art, "modulate:a", 0.0, 0.60).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.finished.connect(dark_art.queue_free)

func _world_art_overlay(target: Control, art: TextureRect, texture: Texture2D, node_name: String) -> TextureRect:
	if texture == null:
		return null
	var overlay := TextureRect.new()
	overlay.name = node_name
	overlay.texture = _visible_world_texture(texture)
	overlay.expand_mode = art.expand_mode
	overlay.stretch_mode = art.stretch_mode
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = art.position
	overlay.size = art.size
	overlay.pivot_offset = art.pivot_offset
	target.add_child(overlay)
	target.move_child(overlay, mini(art.get_index() + 1, target.get_child_count() - 1))
	return overlay

func _spawn_local_fx(parent: Control, asset_id: String, offset: Vector2, dimensions: Vector2, delay: float = 0.0, node_name: String = "CompletionFx") -> TextureRect:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return null
	var view := TextureRect.new()
	view.name = node_name
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 4
	view.size = dimensions
	view.position = parent.size * 0.5 - dimensions * 0.5 + offset
	view.pivot_offset = dimensions * 0.5
	view.scale = Vector2.ONE * 0.35
	view.modulate.a = 0.0
	parent.add_child(view)
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE * 1.10, 0.58).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 0.92, 0.10).set_delay(delay)
	tween.tween_property(view, "modulate:a", 0.0, 0.24).set_delay(delay + 0.34)
	tween.finished.connect(view.queue_free)
	return view

func blackout_sequence() -> void:
	var index := 0
	for target: Variant in target_buttons.values():
		if target is Control and is_instance_valid(target):
			var control := target as Control
			var tween := control.create_tween()
			tween.tween_interval(float(index) * 0.15)
			tween.tween_property(control, "modulate", Color(0.14, 0.18, 0.24, 0.42), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			index += 1

func _add_decorations(slot_count: int) -> void:
	# Ambient motion follows the same two 2:1 axes as the explicit parcel grid.
	_add_wind_streak(Vector2(-180, 560), 0.0, 1.0)
	_add_wind_streak(Vector2(820, 910), 4.5, -1.0)
	var last_slot := _plot_position(maxi(0, slot_count - 1), slot_count)
	var campus_bottom := maxf(690.0, last_slot.y + PLOT_SIZE.y)
	var trees: Array[TextureRect] = []
	# Decorations live in reserved outer gutters. They never occupy a parcel slot
	# or become a third column competing with the interactive campus.
	trees.append(_add_decoration("deco_tree", Vector2(-70, 330), Vector2(124, 124)))
	trees.append(_add_decoration("deco_tree", Vector2(700, campus_bottom + 28), Vector2(128, 128)))
	for tree: TextureRect in trees:
		if tree != null:
			tree.pivot_offset = tree.size * Vector2(0.5, 0.92)
			_sway_art.append(tree)
	_add_decoration("deco_bush", Vector2(724, 210), Vector2(80, 80))
	_add_decoration("deco_bush", Vector2(4, campus_bottom + 170), Vector2(86, 86))
	# Repeated bush rows visually close the campus without competing with plots.
	_add_world_prop("prop_bush_row", Vector2(-34, campus_bottom + 68), Vector2(142, 90), "outer_left")
	_add_world_prop("prop_bush_row", Vector2(696, campus_bottom + 132), Vector2(142, 90), "outer_right")

func _add_campus_paths(plots: Array) -> void:
	var fallback_texture := AssetCatalog.texture("ground_path_straight")
	var slot_count := plots.size() + 1
	if slot_count < 2:
		return
	for slot: int in range(slot_count - 1):
		var from := _plot_position(slot, plots.size()) + PLOT_SIZE * 0.5
		var to := _plot_position(slot + 1, plots.size()) + PLOT_SIZE * 0.5
		var direction := to - from
		# road_iso_a is the / axis, road_iso_b is the \\ axis. A road is
		# undirected, so the X sign selects the sprite matching this grid edge.
		var asset_id := "road_iso_b" if direction.x > 0.0 else "road_iso_a"
		var texture := AssetCatalog.texture(asset_id)
		var uses_iso_asset := texture != null
		if texture == null:
			texture = fallback_texture
		if texture != null:
			_add_path_segment(from, to, texture, slot, asset_id, uses_iso_asset)

func _add_path_segment(from: Vector2, to: Vector2, texture: Texture2D, slot: int, asset_id: String = "ground_path_straight", uses_iso_asset: bool = false) -> void:
	var distance := from.distance_to(to)
	if distance < 32.0:
		return
	var view := TextureRect.new()
	var direction := to - from
	var axis := "a" if direction.x > 0.0 else "b"
	view.name = "CampusLane_%s_%d" % [axis, slot]
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if uses_iso_asset:
		# The final road art is already rendered on the shared 2:1 axes. Its
		# transparent square preserves that projection without runtime rotation.
		view.size = Vector2.ONE * (distance + 56.0)
		view.position = (from + to) * 0.5 - view.size * 0.5
		view.rotation = 0.0
	else:
		view.size = Vector2(distance + 40.0, 96.0)
		view.position = (from + to) * 0.5 - view.size * 0.5
		view.rotation = direction.angle()
	view.pivot_offset = view.size * 0.5
	view.modulate = Color(1, 1, 1, 0.94)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_meta("world_environment", true)
	view.set_meta("world_lane", true)
	view.set_meta("lane_axis", axis)
	view.set_meta("lane_from_slot", slot)
	view.set_meta("lane_to_slot", slot + 1)
	view.set_meta("lane_asset_id", asset_id if uses_iso_asset else "ground_path_straight")
	view.set_meta("using_iso_asset", uses_iso_asset)
	content.add_child(view)

func _add_environment_props(plots: Array) -> void:
	for array_index: int in range(plots.size()):
		var plot: Dictionary = plots[array_index]
		var plot_index := int(plot.get("index", array_index + 1))
		var plot_origin := _plot_position(array_index, plots.size())
		var raw_dc: Variant = plot.get("datacenter", {})
		var powered: bool = false
		if raw_dc is Dictionary:
			var dc_data: Dictionary = raw_dc
			powered = not dc_data.is_empty() and not str(dc_data.get("power_unit", "")).is_empty()
		var used_anchors: Array[int] = []
		if powered:
			var pylon_dimensions := Vector2(132, 132)
			var pylon := _add_world_prop("deco_pylon", _plot_deco_position(plot_origin, 1, pylon_dimensions), pylon_dimensions, "%d_power" % plot_index)
			if pylon != null:
				pylon.set_meta("grid_slot", array_index)
				pylon.set_meta("deco_anchor", 1)
				used_anchors.append(1)
		var prop_count := 0 if plot_index % 3 == 0 else (1 if powered else plot_index % 3)
		for slot: int in range(prop_count):
			var prop_type := (plot_index - 1 + slot) % 4
			var anchor := (plot_index - 1 + slot * 2) % 4
			while anchor in used_anchors:
				anchor = (anchor + 1) % 4
			var asset_id: String = CAMPUS_PROP_IDS[prop_type]
			var dimensions: Vector2 = CAMPUS_PROP_SIZES[prop_type]
			var prop := _add_world_prop(asset_id, _plot_deco_position(plot_origin, anchor, dimensions), dimensions, "%d_%d" % [plot_index, slot])
			if prop != null:
				prop.set_meta("grid_slot", array_index)
				prop.set_meta("deco_anchor", anchor)
				used_anchors.append(anchor)

func _plot_deco_position(plot_origin: Vector2, anchor: int, dimensions: Vector2) -> Vector2:
	# Four explicit anchors sit just outside the pad corners. The rear pair are
	# used by powered-campus fixtures; front anchors remain available for future
	# low-profile props without ever entering a 40u vehicle lane.
	var anchor_points := [
		Vector2(-14, 46),
		Vector2(PLOT_SIZE.x + 14, 46),
		Vector2(-14, PLOT_SIZE.y - 36),
		Vector2(PLOT_SIZE.x + 14, PLOT_SIZE.y - 36),
	]
	var point: Vector2 = anchor_points[clampi(anchor, 0, anchor_points.size() - 1)]
	return plot_origin + point - dimensions * Vector2(0.5, 0.72)

func _add_world_prop(asset_id: String, at: Vector2, dimensions: Vector2, suffix: String) -> TextureRect:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return null
	var view := TextureRect.new()
	view.name = "CampusProp_%s_%s" % [asset_id, suffix]
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.position = at
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_meta("world_environment", true)
	view.set_meta("world_prop_type", asset_id)
	content.add_child(view)
	return view

func _add_decoration(asset_id: String, at: Vector2, dimensions: Vector2, preserve_aspect: bool = true) -> TextureRect:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return null
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if preserve_aspect else TextureRect.STRETCH_SCALE
	view.position = at
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(view)
	return view

func _add_wind_streak(at: Vector2, delay: float, direction: float) -> void:
	var texture := AssetCatalog.texture("fx_wind_streak")
	if texture == null:
		return
	var streak := TextureRect.new()
	streak.texture = texture
	streak.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	streak.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	streak.position = at
	streak.size = Vector2(220, 86)
	streak.rotation = ISO_ANGLE * direction
	streak.modulate = Color(1, 1, 1, 0.10)
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(streak)
	var tween := streak.create_tween().set_loops()
	tween.tween_interval(delay)
	var target := Vector2(900 if direction > 0.0 else -260, at.y + 540)
	var origin := at
	tween.tween_property(streak, "position", target, 9.0).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void: streak.position = origin)
	tween.tween_interval(6.0)

func _plot_button(plot: Dictionary, at: Vector2) -> Button:
	var status := str(plot.get("status", "empty"))
	var asset_id := "plot_pad_std" if AssetCatalog.has_asset("plot_pad_std") else "plot_owned"
	var caption := ""
	var caption_asset := ""
	var accent := ThemeMaker.COLORS.green
	var alert_type := ""
	var alert_slot := -1
	match status:
		"empty":
			caption = tr("BUILD")
			caption_asset = ""
		"building":
			var construction := Game.find_construction(str(plot.get("construction_id", "")))
			var remaining := maxf(0.0, float(construction.get("complete_at", 0.0)) - Game.simulation_time())
			caption = Game.format_duration(remaining)
			caption_asset = "ic_clock"
			accent = ThemeMaker.COLORS.orange
			var building := DataRepository.get_entry("buildings", str(construction.get("building_id", "")))
			asset_id = str(building.get("asset_prefix", "")) + "_construction"
		"ruined":
			var dc: Dictionary = plot.get("datacenter", {})
			caption = tr("DEMOLISH")
			caption_asset = "ic_warning"
			accent = ThemeMaker.COLORS.red
			var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
			asset_id = str(building.get("asset_prefix", "")) + "_ruin"
		_:
			var dc: Dictionary = plot.get("datacenter", {})
			var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
			var alert := _datacenter_alert(dc)
			caption = str(alert.get("caption", ""))
			caption_asset = str(alert.get("asset", ""))
			alert_type = str(alert.get("type", ""))
			alert_slot = int(alert.get("slot", -1))
			accent = ThemeMaker.COLORS.sky if not str(dc.get("power_unit", "")).is_empty() else Color("8fa0ad")
			if alert_type in ["fault", "overheat"]:
				accent = ThemeMaker.COLORS.red if alert_type == "fault" else ThemeMaker.COLORS.orange
			elif alert_type in ["contract", "retire"]:
				accent = ThemeMaker.COLORS.yellow if alert_type == "retire" else ThemeMaker.COLORS.sky
			asset_id = _datacenter_asset_id(dc, building)
	var badge_mode := "hidden"
	match status:
		"empty": badge_mode = "add"
		"building": badge_mode = "timer"
		"ruined": badge_mode = "icon"
		_:
			if not caption.is_empty():
				badge_mode = "icon"
	var button := _world_button(asset_id, caption, accent, caption_asset, badge_mode)
	button.position = at
	var world_art := button.find_child("WorldArt", false, false) as TextureRect
	if world_art != null:
		world_art.set_meta("ambient_phase", float(int(plot.get("index", 0))) * 1.73)
	if status == "building":
		var countdown := button.find_child("StatusText", true, false) as Label
		if countdown != null:
			var construction := Game.find_construction(str(plot.get("construction_id", "")))
			_configure_construction_timer(button, countdown, construction)
	match status:
		"empty": button.pressed.connect(func() -> void: empty_plot_selected.emit(str(plot.get("id", ""))))
		"ruined":
			var ruined_dc: Dictionary = plot.get("datacenter", {})
			button.pressed.connect(func() -> void: datacenter_selected.emit(str(ruined_dc.get("id", ""))))
		"building": pass
		_:
			var active_dc: Dictionary = plot.get("datacenter", {})
			button.pressed.connect(func() -> void: datacenter_selected.emit(str(active_dc.get("id", ""))))
			if not alert_type.is_empty():
				_wire_alert_badge(button, str(active_dc.get("id", "")), alert_type, alert_slot)
	return button

func _datacenter_alert(dc: Dictionary) -> Dictionary:
	var racks: Array = dc.get("racks", [])
	for slot: int in range(racks.size()):
		var installed: Variant = racks[slot]
		if installed is Dictionary and str(installed.get("status", "")) == "faulted":
			return {"type": "fault", "slot": slot, "caption": tr("FAULTED"), "asset": "ic_wrench"}
	if str(dc.get("power_unit", "")).is_empty():
		return {"type": "unpowered", "slot": -1, "caption": tr("UNPOWERED"), "asset": "ic_power"}
	for slot: int in range(racks.size()):
		var runtime := Rules.rack_runtime_status(dc, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
		if bool(runtime.get("overheated", false)):
			return {"type": "overheat", "slot": slot, "caption": tr("OVERHEATED"), "asset": "ic_heat"}
	if not str(dc.get("customer_id", "")).is_empty() and float(dc.get("contract_end_at", INF)) <= Game.simulation_time():
		return {"type": "contract", "slot": -1, "caption": tr("CONTRACT_RENEWAL_FREE"), "asset": "ic_contract"}
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	var aging_start := float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6))
	if progress >= aging_start:
		return {"type": "retire", "slot": -1, "caption": tr("RETIRE"), "asset": "ic_retire"}
	return {}

func _wire_alert_badge(button: Button, datacenter_id: String, alert_type: String, slot: int) -> void:
	var badge := button.find_child("StatusBadge", true, false) as PanelContainer
	if badge == null:
		return
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	badge.set_meta("alert_type", alert_type)
	badge.set_meta("datacenter_id", datacenter_id)
	badge.set_meta("breathing", true)
	var badge_style := badge.get_theme_stylebox("panel") as StyleBoxFlat
	if badge_style != null:
		badge_style = badge_style.duplicate() as StyleBoxFlat
		badge_style.border_color = Color.WHITE
		badge_style.set_border_width_all(2)
		badge.add_theme_stylebox_override("panel", badge_style)
	badge.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			badge.accept_event()
			alert_selected.emit(datacenter_id, alert_type, slot)
	)
	badge.scale = Vector2.ZERO
	badge.pivot_offset = badge.size * 0.5
	var entrance := badge.create_tween()
	entrance.tween_property(badge, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.finished.connect(func() -> void:
		if not is_instance_valid(badge):
			return
		var breath := badge.create_tween().set_loops()
		breath.tween_property(badge, "scale", Vector2.ONE * 1.08, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		breath.tween_property(badge, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	)

func _configure_construction_timer(button: Button, label: Label, construction: Dictionary) -> void:
	var badge := button.find_child("StatusBadge", true, false) as PanelContainer
	var row := button.find_child("StatusRow", true, false) as HBoxContainer
	if badge == null or row == null:
		return
	badge.size.y = 68
	badge.position.y = PLOT_SIZE.y - 72
	label.custom_minimum_size.x = 70
	var progress := ProgressBar.new()
	progress.name = "ConstructionProgress"
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(54, 18)
	row.add_child(progress)
	var started := float(construction.get("started_at", Game.simulation_time()))
	var completed := float(construction.get("complete_at", started + 1.0))
	progress.max_value = maxf(1.0, completed - started)
	progress.value = clampf(Game.simulation_time() - started, 0.0, progress.max_value)
	_construction_labels.append({"label": label, "progress": progress, "construction_id": str(construction.get("id", "")), "started_at": started, "complete_at": completed})

func _plot_position(index: int, _owned_count: int) -> Vector2:
	var column := index % 2
	var row := index / 2
	# The second bay rises by exactly half its horizontal step, so consecutive
	# slots alternate across the two 2:1 isometric axes instead of forming a
	# screen-space rectangle. No odd-row centering exception may break this grid.
	return Vector2(CAMPUS_LEFT + column * COLUMN_STEP, CAMPUS_TOP + row * ROW_STEP + column * ISO_RISE)

func _sale_position(owned_count: int) -> Vector2:
	return _plot_position(owned_count, owned_count + 1)

func _configure_grid_slot(button: Button, slot: int, at: Vector2) -> void:
	# Slot order follows increasing world Y, so it provides the same stable
	# painter's order without leaking unbounded pixel coordinates into the root
	# canvas Z range. The cap guarantees even very large parks stay below pages.
	button.z_index = 10 + mini(slot, 1024)
	button.set_meta("grid_slot", slot)
	button.set_meta("grid_column", slot % 2)
	button.set_meta("grid_row", slot / 2)
	button.set_meta("grid_origin", at)
	button.set_meta("grid_center", at + PLOT_SIZE * 0.5)

func _datacenter_asset_id(dc: Dictionary, building: Dictionary) -> String:
	var suffix := "_dark"
	if not str(dc.get("power_unit", "")).is_empty():
		var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
		match Rules.aging_stage(progress):
			"aging": suffix = "_aged"
			"decline": suffix = "_decayed"
			_: suffix = "_active"
	return str(building.get("asset_prefix", "")) + suffix

func _world_button(asset_id: String, caption: String, accent: Color, caption_asset: String = "", badge_mode: String = "text") -> Button:
	var button := Button.new()
	button.name = "WorldPlotButton"
	button.size = PLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = caption
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.0)
	normal.set_corner_radius_all(42)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.10)
	hover.border_color = Color(accent, 0.5)
	hover.set_border_width_all(2)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.18)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if asset_id.begins_with("dc_"):
		_add_owned_plot_base(button, asset_id)
	var view := TextureRect.new()
	view.name = "WorldArt"
	var texture := AssetCatalog.texture(asset_id)
	view.texture = _visible_world_texture(texture)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = Vector2(12, -2)
	view.size = Vector2(PLOT_SIZE.x - 24, 224)
	view.pivot_offset = Vector2(view.size.x * 0.5, view.size.y * 0.82)
	button.add_child(view)
	if asset_id.ends_with("_active"):
		_active_art.append(view)
		var glow_texture := AssetCatalog.texture("fx_glow_ring")
		if glow_texture != null:
			var glow := TextureRect.new()
			glow.texture = glow_texture
			glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			glow.position = Vector2(64, 108)
			glow.size = Vector2(216, 112)
			glow.pivot_offset = glow.size * 0.5
			glow.modulate = Color(0.55, 0.92, 1.0, 0.13)
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(glow)
			button.move_child(glow, 0)
			_glow_art.append(glow)
	var status_badge := PanelContainer.new()
	status_badge.name = "StatusBadge"
	status_badge.add_theme_stylebox_override("panel", ThemeMaker.world_badge(accent, badge_mode in ["add", "icon"]))
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if badge_mode in ["add", "icon"]:
		status_badge.position = Vector2(PLOT_SIZE.x - 92, 24)
		status_badge.size = Vector2(64, 64)
	else:
		var badge_width := 190.0 if badge_mode == "price" else 176.0
		status_badge.position = Vector2((PLOT_SIZE.x - badge_width) * 0.5, PLOT_SIZE.y - 58)
		status_badge.size = Vector2(badge_width, 54)
	button.add_child(status_badge)
	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	status_badge.add_child(status_row)
	if badge_mode == "add":
		var add_label := Label.new()
		add_label.name = "StatusSymbol"
		add_label.text = "+"
		add_label.custom_minimum_size = Vector2(40, 40)
		add_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_label.add_theme_font_size_override("font_size", 36)
		add_label.add_theme_color_override("font_color", Color.WHITE)
		add_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(add_label)
	elif not caption_asset.is_empty():
		var status_icon := TextureRect.new()
		status_icon.texture = AssetCatalog.texture(caption_asset)
		status_icon.custom_minimum_size = Vector2(36, 36) if badge_mode == "icon" else Vector2(30, 30)
		status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(status_icon)
	if badge_mode in ["text", "timer", "price"]:
		var caption_label := Label.new()
		caption_label.name = "StatusText"
		caption_label.text = caption
		caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption_label.custom_minimum_size.x = 94
		caption_label.add_theme_font_size_override("font_size", 20)
		caption_label.add_theme_color_override("font_color", Color.WHITE)
		caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(caption_label)
	status_badge.visible = badge_mode != "hidden"
	button.pivot_offset = button.size * 0.5
	button.button_down.connect(_animate_button.bind(button, 0.96))
	button.button_up.connect(_animate_button.bind(button, 1.0))
	return button

func _add_owned_plot_base(button: Button, building_asset_id: String) -> void:
	var base := TextureRect.new()
	base.name = "PlotFoundation"
	var large := building_asset_id.begins_with("dc_t2") or building_asset_id.begins_with("dc_t3")
	var pad_asset_id := "plot_pad_large" if large else "plot_pad_std"
	var pad_texture := AssetCatalog.texture(pad_asset_id)
	if pad_texture == null:
		pad_asset_id = "plot_owned"
		pad_texture = AssetCatalog.texture(pad_asset_id)
	base.texture = _visible_world_texture(pad_texture)
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.position = Vector2(-13, 18) if large else Vector2(7, 28)
	base.size = Vector2(PLOT_SIZE.x + 26, 244) if large else Vector2(PLOT_SIZE.x - 14, 226)
	base.modulate = Color.WHITE
	base.set_meta("plot_pad_class", "large" if large else "standard")
	base.set_meta("plot_pad_asset_id", pad_asset_id)
	button.add_child(base)

func _visible_world_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := texture.resource_path
	if _world_texture_cache.has(cache_key):
		return _world_texture_cache[cache_key] as Texture2D
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	used = used.grow(12).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(used)
	_world_texture_cache[cache_key] = cropped
	return cropped

func _include_campus_rect(rect: Rect2) -> void:
	_campus_bounds = rect if _campus_bounds.size == Vector2.ZERO else _campus_bounds.merge(rect)

func _frame_campus(animate: bool) -> void:
	if _campus_bounds.size == Vector2.ZERO:
		_apply_camera()
		return
	var viewport_size := size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		viewport_size = Vector2(804, 1748)
	var safe_height := maxf(560.0, viewport_size.y - CAMPUS_SAFE_TOP - CAMPUS_SAFE_BOTTOM)
	var fit_x := (viewport_size.x - 64.0) / _campus_bounds.size.x
	var fit_y := safe_height / _campus_bounds.size.y
	zoom = clampf(minf(fit_x, fit_y), 0.82, 1.06)
	var safe_center := Vector2(viewport_size.x * 0.5, CAMPUS_SAFE_TOP + safe_height * 0.5)
	camera_offset = safe_center - _campus_bounds.get_center() * zoom
	_default_zoom = zoom
	_default_camera_offset = camera_offset
	_clamp_camera_offset()
	_default_camera_offset = camera_offset
	if animate:
		_animate_camera()
	else:
		_apply_camera()

func _refresh_construction_labels() -> void:
	for entry: Dictionary in _construction_labels:
		var label := entry.get("label") as Label
		if label == null or not is_instance_valid(label):
			continue
		var completed := float(entry.get("complete_at", Game.simulation_time()))
		var started := float(entry.get("started_at", Game.simulation_time()))
		var remaining := maxf(0.0, completed - Game.simulation_time())
		label.text = Game.format_duration(remaining)
		var progress := entry.get("progress") as ProgressBar
		if progress != null and is_instance_valid(progress):
			progress.value = clampf(Game.simulation_time() - started, 0.0, maxf(1.0, completed - started))

func _animate_button(button: Button, target_scale: float) -> void:
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or dragging:
		notify_user_input()
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
	_clamp_camera_offset()
	content.position = camera_offset
	content.scale = Vector2.ONE * zoom

func notify_user_input() -> void:
	_idle_seconds = 0.0
	_camera_breath_phase = 0.0
	if not _camera_breathing or content == null:
		return
	_camera_breathing = false
	# Input must feel immediate; do not leave a slow cinematic tween fighting
	# the user's drag, pinch or button press.
	content.position = camera_offset
	content.scale = Vector2.ONE * zoom

func _update_camera_breath(delta: float) -> void:
	if content == null or dragging or not touch_points.is_empty():
		return
	_idle_seconds += delta
	if _idle_seconds < CAMERA_BREATH_DELAY:
		return
	_camera_breathing = true
	_camera_breath_phase += delta
	var entrance := smoothstep(CAMERA_BREATH_DELAY, CAMERA_BREATH_DELAY + 2.0, _idle_seconds)
	var cycle := (sin(_camera_breath_phase * 0.24 - PI * 0.5) + 1.0) * 0.5
	var factor := 1.0 + CAMERA_BREATH_ZOOM * cycle * entrance
	var viewport_center := size * 0.5
	var drift := Vector2(sin(_camera_breath_phase * 0.17) * 5.0, cos(_camera_breath_phase * 0.13) * 4.0) * entrance
	content.scale = Vector2.ONE * zoom * factor
	content.position = camera_offset + (viewport_center - camera_offset) * (1.0 - factor) + drift

func _clamp_camera_offset() -> void:
	var scaled := world_size * zoom
	var min_x := minf(30.0, size.x - scaled.x - 30.0)
	var min_y := minf(180.0, size.y - scaled.y - 180.0)
	camera_offset.x = clampf(camera_offset.x, min_x, 60.0)
	# A compact early campus needs room to sit between the HUD and the bottom
	# actions. The former 300px ceiling pinned every layout to the top edge and
	# left most of the useful phone canvas as empty grass.
	camera_offset.y = clampf(camera_offset.y, min_y, 620.0)

func _animate_camera() -> void:
	if content == null:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(content, "position", camera_offset, 0.30).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(content, "scale", Vector2.ONE * zoom, 0.30).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _pinch_distance() -> float:
	if touch_points.size() < 2:
		return 0.0
	var points: Array = touch_points.values()
	return (Vector2(points[0]) - Vector2(points[1])).length()

func _touch_center() -> Vector2:
	var points: Array = touch_points.values()
	return (Vector2(points[0]) + Vector2(points[1])) * 0.5 if points.size() >= 2 else Vector2.ZERO
