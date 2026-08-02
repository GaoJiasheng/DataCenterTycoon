class_name Widgets
extends RefCounted

const ThemeMaker := preload("res://ui/theme_factory.gd")

static func button(text: String, action: Callable, role: String = "secondary") -> Button:
	var control := Button.new()
	control.text = text
	control.custom_minimum_size.y = ThemeMaker.TOUCH_MIN
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	control.clip_text = true
	ThemeMaker.apply_button_role(control, role)
	wire_button_motion(control)
	if action.is_valid():
		control.pressed.connect(action)
	return control

static func close_button(action: Callable) -> Button:
	var control := button("×", action, "secondary")
	control.custom_minimum_size = Vector2(ThemeMaker.TOUCH_MIN, ThemeMaker.TOUCH_MIN)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.title)
	control.add_theme_stylebox_override("normal", ThemeMaker.round_button_box(Color("263d59")))
	control.add_theme_stylebox_override("hover", ThemeMaker.round_button_box(Color("365572")))
	control.add_theme_stylebox_override("pressed", ThemeMaker.round_button_box(Color("1c3047"), true))
	return control

static func panel(dark: bool = true) -> PanelContainer:
	var control := PanelContainer.new()
	control.add_theme_stylebox_override("panel", ThemeMaker.art_panel(dark, true))
	return control

static func chip(text: String, accent: Color = Color.WHITE) -> PanelContainer:
	var control := PanelContainer.new()
	control.custom_minimum_size.y = 64
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := ThemeMaker.panel(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, int(ThemeMaker.RADIUS.get("chip", 14)))
	style.content_margin_left = ThemeMaker.SPACE[3]
	style.content_margin_right = ThemeMaker.SPACE[3]
	style.content_margin_top = ThemeMaker.SPACE[1]
	style.content_margin_bottom = ThemeMaker.SPACE[1]
	control.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Value"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
	label.add_theme_color_override("font_color", accent)
	control.add_child(label)
	return control

static func badge(count: int) -> PanelContainer:
	var control := PanelContainer.new()
	control.name = "Badge"
	control.custom_minimum_size = Vector2(42, 42)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.COLORS.red, Color.WHITE, 2, 21))
	var label := Label.new()
	label.name = "BadgeValue"
	label.text = str(count)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.micro)
	label.add_theme_color_override("font_color", Color.WHITE)
	control.add_child(label)
	return control

static func timer_bar(complete_at: float, duration: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "TimerBar"
	box.add_theme_constant_override("separation", ThemeMaker.SPACE[1])
	var progress := ProgressBar.new()
	progress.name = "TimerProgress"
	progress.show_percentage = false
	progress.custom_minimum_size.y = 34
	progress.max_value = maxf(1.0, duration)
	box.add_child(progress)
	var remaining := Label.new()
	remaining.name = "TimerRemaining"
	remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
	remaining.add_theme_color_override("font_color", ThemeMaker.COLORS.cyan)
	box.add_child(remaining)
	var update := func() -> void:
		var left := maxf(0.0, complete_at - Game.simulation_time())
		progress.value = clampf(duration - left, 0.0, duration)
		remaining.text = Game.format_duration(left)
	update.call()
	box.set_meta("live_update", update)
	return box

static func round_entry(icon: Texture2D, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.custom_minimum_size = Vector2(96, 96)
	control.icon = icon
	control.expand_icon = true
	control.add_theme_constant_override("icon_max_width", 42)
	control.tooltip_text = text
	ThemeMaker.apply_round_button(control, ThemeMaker.COLORS.sky)
	wire_button_motion(control)
	if action.is_valid():
		control.pressed.connect(action)
	return control

static func section_header(title_text: String, subtitle_text: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeMaker.SPACE[0])
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.add_theme_font_override("font", ThemeMaker.font_bold())
	title.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.title)
	title.add_theme_color_override("font_color", ThemeMaker.COLORS.cream)
	box.add_child(title)
	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.name = "Subtitle"
		subtitle.text = subtitle_text
		subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		subtitle.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
		subtitle.add_theme_color_override("font_color", ThemeMaker.COLORS.cyan)
		box.add_child(subtitle)
	return box

static func empty_state(title_text: String, body_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", ThemeMaker.SPACE[2])
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ThemeMaker.font_bold())
	title.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.heading)
	box.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.body)
	box.add_child(body)
	return box

static func animate_number(label: Label, from_value: float, to_value: float, formatter: Callable, duration: float = 0.4) -> Tween:
	var tween := label.create_tween()
	tween.tween_method(func(value: float) -> void:
		if is_instance_valid(label):
			label.text = str(formatter.call(value))
	, from_value, to_value, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return tween

static func wire_button_motion(control: Button) -> void:
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)
	control.button_down.connect(func() -> void:
		control.create_tween().tween_property(control, "scale", Vector2.ONE * 0.96, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	control.button_up.connect(func() -> void:
		control.create_tween().tween_property(control, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
