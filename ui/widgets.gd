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
	control.add_theme_constant_override("outline_size", 4)
	control.add_theme_stylebox_override("normal", ThemeMaker.round_button_box(Color("263d59")))
	control.add_theme_stylebox_override("hover", ThemeMaker.round_button_box(Color("365572")))
	control.add_theme_stylebox_override("pressed", ThemeMaker.round_button_box(Color("1c3047"), true))
	return control

static func panel(dark: bool = true) -> PanelContainer:
	var control := PanelContainer.new()
	control.add_theme_stylebox_override("panel", ThemeMaker.flat_group_box() if dark else ThemeMaker.art_panel(false))
	return control

static func flat_card(accent: Color = Color.TRANSPARENT, padding: int = ThemeMaker.GROUP_PADDING) -> PanelContainer:
	var control := PanelContainer.new()
	control.add_theme_stylebox_override("panel", ThemeMaker.flat_group_box(accent, padding))
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
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.add_theme_font_override("font", ThemeMaker.font_bold())
	title.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.heading)
	title.add_theme_color_override("font_color", ThemeMaker.COLORS.cream)
	box.add_child(title)
	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.name = "Subtitle"
		subtitle.text = subtitle_text
		subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		subtitle.max_lines_visible = 1
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
	body.add_theme_constant_override("line_spacing", ThemeMaker.TEXT_LINE_SPACING)
	body.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.body)
	box.add_child(body)
	return box

static func animate_number(label: Label, from_value: float, to_value: float, formatter: Callable, duration: float = 0.4) -> Tween:
	if absf(to_value - from_value) >= 10.0 and duration >= 0.3 and label.is_inside_tree():
		label.set_meta("number_roll_audio", "sfx_coin_tick")
		AudioService.play_sfx("sfx_coin_tick")
		var label_ref: WeakRef = weakref(label)
		for ratio: float in [0.28, 0.56, 0.82]:
			label.get_tree().create_timer(duration * ratio).timeout.connect(func() -> void:
				var live_label: Label = label_ref.get_ref() as Label
				if live_label != null and live_label.is_inside_tree():
					AudioService.play_sfx("sfx_coin_tick")
			)
	var tween := label.create_tween()
	tween.tween_method(func(value: float) -> void:
		if is_instance_valid(label):
			label.text = str(formatter.call(value))
	, from_value, to_value, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return tween

static func affordable_style(button: Button, cost: float) -> void:
	# One affordability contract for every purchase surface. It deliberately
	# leaves the action enabled when cash is short so the gameplay layer can
	# return its localized failure reason; presentation only changes hierarchy.
	if not button.has_meta("affordability_base_text"):
		button.set_meta("affordability_base_text", button.text)
	var base_text := str(button.get_meta("affordability_base_text", button.text))
	var cash := float(Game.state.get("player", {}).get("cash", 0.0))
	var affordable := cash + 0.001 >= cost and not button.disabled
	button.set_meta("affordable", affordable)
	button.set_meta("purchase_cost", cost)
	var old_pulse: Variant = button.get_meta("affordability_pulse") if button.has_meta("affordability_pulse") else null
	if old_pulse is Tween and (old_pulse as Tween).is_valid():
		(old_pulse as Tween).kill()
	button.scale = Vector2.ONE
	button.modulate = Color.WHITE
	var card_surface := bool(button.get_meta("affordable_card", false))
	if card_surface:
		var accent := ThemeMaker.COLORS.green if affordable else Color("6f7b88")
		var normal := ThemeMaker.flat_group_box(accent)
		normal.border_color = Color(accent, 0.78 if affordable else 0.34)
		normal.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", ThemeMaker.flat_group_box(accent.lightened(0.08)))
		button.add_theme_stylebox_override("pressed", ThemeMaker.flat_group_box(accent.darkened(0.08)))
	else:
		button.text = base_text
		if affordable:
			ThemeMaker.apply_button_role(button, "primary")
		else:
			ThemeMaker.apply_button_role(button, "disabled")
			var shortfall := maxf(0.0, cost - cash)
			var shortfall_copy := TranslationServer.translate("AFFORD_SHORTFALL") % Game.format_number(shortfall)
			button.text = "%s\n%s" % [base_text, shortfall_copy]
			var line_count := button.text.count("\n") + 1
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, float(line_count * 30 + 28))
	if affordable:
		var pulse := button.create_tween().set_loops()
		pulse.tween_property(button, "modulate", Color(1.08, 1.08, 1.08, 1.0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(button, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		button.set_meta("affordability_pulse", pulse)

static func wire_button_motion(control: Button) -> void:
	if bool(control.get_meta("button_motion_wired", false)):
		return
	control.set_meta("button_motion_wired", true)
	control.set_meta("tap_audio", "sfx_tap")
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)
	control.button_down.connect(func() -> void:
		AudioService.play_sfx("sfx_tap")
		control.create_tween().tween_property(control, "scale", Vector2.ONE * 0.96, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	control.button_up.connect(func() -> void:
		control.create_tween().tween_property(control, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
