extends Control

const ThemeMaker := preload("res://ui/theme_factory.gd")
const DutyLogScene := preload("res://ui/duty_log.gd")
const PersonaSystemScene := preload("res://gameplay/persona_system.gd")

const Widgets := preload("res://ui/widgets.gd")
const ChartScene := preload("res://ui/market_chart.gd")
const ParkMapScene := preload("res://gameplay/map/park_map.gd")
const Rules := preload("res://gameplay/game_rules.gd")
const FxLayerScene := preload("res://ui/fx_layer.gd")
const DatacenterBoardScene := preload("res://ui/datacenter_board.gd")
const TutorialOverlayScene := preload("res://ui/tutorial_overlay.gd")
const SparklineScene := preload("res://ui/sparkline.gd")

const HAPTIC_LIGHT := 8
const HAPTIC_MEDIUM := 16
const HAPTIC_HEAVY := 24
const HAPTIC_SUCCESS := 32
const RETIRE_WARNING_PROGRESS := 0.87
const LEGAL_DOCUMENTS := {
	"privacy": "res://docs/public/privacy.html",
	"terms": "res://docs/public/terms.html",
	"support": "res://docs/public/support.html",
}
const FX_EXTENT_LIMITS := {
	"fx_confetti_set": 240.0,
	"fx_dust_puff": 120.0,
	"fx_spark": 100.0,
	"fx_snowflake": 100.0,
	"fx_frost_patch": 100.0,
	"fx_wind_streak": 100.0,
	"fx_smoke_puff": 100.0,
	"fx_coin": 100.0,
	"fx_glow_ring": 100.0,
}

var cash_label: Label
var gems_label: Label
var date_label: Label
var news_label: Label
var tutorial_overlay: TutorialOverlay
var tutorial_hint_button: Button
var world_host: Control
var park_map: ParkMap
var shell_header: PanelContainer
var news_panel: PanelContainer
var navigation_panel: PanelContainer
var campus_switcher: PanelContainer
var campus_tab_scroll: ScrollContainer
var campus_tab_row: HBoxContainer
var _campus_tab_signature := ""
var era_icon: TextureRect
var company_label: Label
var primary_action_button: Button
var primary_action_icon: TextureRect
var primary_action_text: Label
var primary_action_text_fill: Label
var primary_action_text_stack: Control
var task_button: Button
var operations_button: Button
var operations_badge: PanelContainer
var operations_badge_label: Label
var queue_badge_label: Label
var fx_layer: FxLayer
var page_host: Control
var feedback_layer: CanvasLayer
var toast_label: Label
var _toast_tween: Tween
var nav_buttons: Dictionary = {}
var active_page := "map"
var selected_datacenter_id := ""
var _detail_focus := "racks"
var _tech_section := "upgrades"
var _primary_action_kind := ""
var _primary_action_target := ""
var _last_primary_action_kind := ""
var _needs_refresh := true
var _needs_page_refresh := true
var _refresh_cooldown := 0.0
var _page_scroll_cache: Dictionary = {}
var _era_overlay_queue: Array[int] = []
var _era_overlay_open := false
var _pending_market_banner: Dictionary = {}
var _news_notice_message := ""
var _news_notice_rare := false
var _news_notice_token := 0
var _news_gesture := {"active": false, "start_x": 0.0}
var _last_map_signature := ""
var _rendered_page := ""
var _display_cash := NAN
var _display_gems := NAN
var _cash_target := NAN
var _gems_target := NAN
var _cash_tween: Tween
var _gems_tween: Tween
var _last_observed_cash := NAN
var _last_income_fly_at := -INF
var _primary_pulse_tween: Tween
var _last_tutorial_step := -1
var _tutorial_protocol_step := -1
var _tutorial_visual_mode := "actionable"
var _tutorial_world_focus_id := ""
var _retire_tutorial_awake := false
var _retire_notice_collapsed := false
var _retire_notice_token := 0
var _arrears_banner_dismissed := false
var _music_target := ""
var _music_fade_tween: Tween
var _night_amb_countdown := 0.0

func _ready() -> void:
	_fit_desktop_window()
	theme = ThemeMaker.create()
	_build_shell()
	_connect_events()
	_play_music("music_main", false)
	call_deferred("_show_pending_offline_report")
	call_deferred("_queue_unseen_era_overlays")
	call_deferred("_show_pending_bankruptcy_state")

# Desktop preview only: use half of the iPhone 17 Pro Max physical 1320x2868
# resolution. The 804x1748 layout canvas remains the device-independent design
# space and Godot scales it with aspect=keep. iOS ignores this desktop override.
func _fit_desktop_window() -> void:
	if not OS.has_feature("pc"):
		return
	if not Game.persistence_enabled:
		return  # The visual harness owns its larger 990x2151 capture size.
	var usable := DisplayServer.screen_get_usable_rect()
	var preview_size := Vector2i(660, 1434)
	DisplayServer.window_set_size(preview_size)
	var centered := usable.position + (usable.size - preview_size) / 2
	# Keep the title bar reachable on a scaled desktop without silently changing
	# the owner's requested half-native preview size.
	centered.x = maxi(usable.position.x, centered.x)
	centered.y = maxi(usable.position.y, centered.y)
	DisplayServer.window_set_position(centered)

func _process(delta: float) -> void:
	_refresh_cooldown -= delta
	if (_needs_refresh or _needs_page_refresh) and _refresh_cooldown <= 0.0:
		_refresh_cooldown = 0.25
		var refresh_page := _needs_page_refresh
		_needs_refresh = false
		_needs_page_refresh = false
		_refresh_hud()
		if refresh_page:
			_refresh_page()
	_sync_tutorial_target_geometry()
	_update_night_ambience(delta)

func _update_night_ambience(delta: float) -> void:
	if park_map == null or not is_instance_valid(park_map) or not park_map.is_night_grade():
		_night_amb_countdown = 0.0
		return
	_night_amb_countdown -= delta
	if _night_amb_countdown <= 0.0:
		AudioService.play_sfx("sfx_night_amb")
		_night_amb_countdown = 7.8

func _input(event: InputEvent) -> void:
	if park_map == null or event is InputEventMouseMotion:
		return
	if event is InputEventKey and not event.pressed:
		return
	park_map.notify_user_input()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = ThemeMaker.SURFACE
	# Reserve the lowest canvas band for the solid fallback, then keep the
	# depth-sorted world between it and every HUD/page/overlay layer.
	background.z_index = -4096
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	world_host = Control.new()
	world_host.name = "WorldHost"
	# Plot buttons use a local depth sort based on their world Y coordinate. Keep
	# that entire sorted canvas behind system pages: without a parent offset, a
	# late/southern plot can overdraw the page frame even though PageHost is a
	# later sibling in the scene tree.
	world_host.z_index = -2048
	world_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(world_host)
	park_map = ParkMapScene.new()
	park_map.name = "ParkWorld"
	park_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	park_map.datacenter_selected.connect(_open_datacenter)
	park_map.empty_plot_selected.connect(_show_building_picker)
	park_map.buy_plot_requested.connect(_show_plot_purchase)
	world_host.add_child(park_map)
	park_map.alert_selected.connect(_on_world_alert_selected)
	park_map.campus_changed.connect(_on_campus_changed)

	# Keep the safe-area shell as a plain Control. A MarginContainer propagates
	# the minimum height of long scroll pages back into the entire shell, which
	# can push the global HUD and tab bar off-screen on a phone-sized viewport.
	var safe := Control.new()
	safe.name = "SafeArea"
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_margins := _safe_area_margins()
	add_child(safe)

	var stage := Control.new()
	stage.name = "ShellStage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = safe_margins.x
	stage.offset_top = safe_margins.y
	stage.offset_right = -safe_margins.z
	stage.offset_bottom = -safe_margins.w
	safe.add_child(stage)

	page_host = Control.new()
	page_host.name = "PageHost"
	page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_host.offset_top = 108
	page_host.offset_bottom = -8
	page_host.clip_contents = true
	stage.add_child(page_host)

	shell_header = PanelContainer.new()
	shell_header.name = "ShellHeader"
	shell_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shell_header.offset_bottom = 88
	shell_header.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stage.add_child(shell_header)
	var topbar := HBoxContainer.new()
	topbar.alignment = BoxContainer.ALIGNMENT_CENTER
	topbar.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	shell_header.add_child(topbar)
	var company_button := Button.new()
	company_button.name = "CompanyButton"
	company_button.custom_minimum_size = Vector2(96, 88)
	company_button.tooltip_text = tr("COMPANY_OVERVIEW")
	company_button.pressed.connect(_navigate.bind("tech"))
	ThemeMaker.apply_button_color(company_button, ThemeMaker.COLORS.sky)
	_wire_button_motion(company_button)
	var company_center := CenterContainer.new()
	company_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	company_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	company_button.add_child(company_center)
	era_icon = _icon_view("ic_era1", Vector2(46, 46))
	company_center.add_child(era_icon)
	company_label = _label("1", 20, Color.WHITE)
	company_label.name = "EraCornerBadge"
	company_label.position = Vector2(58, 50)
	company_label.size = Vector2(30, 28)
	company_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeMaker.world_text(company_label)
	company_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var era_badge_style := ThemeMaker.panel(Color("173252"), Color.WHITE, 2, 14)
	era_badge_style.content_margin_left = 4
	era_badge_style.content_margin_right = 4
	era_badge_style.content_margin_top = 2
	era_badge_style.content_margin_bottom = 2
	company_label.add_theme_stylebox_override("normal", era_badge_style)
	company_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	company_button.add_child(company_label)
	topbar.add_child(company_button)
	var cash_chip := _resource_chip("ic_cash", ThemeMaker.COLORS.yellow)
	cash_chip.name = "CashResource"
	cash_chip.custom_minimum_size.y = 88
	cash_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cash_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_chip.size_flags_stretch_ratio = 1.4
	cash_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cash_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	cash_chip.gui_input.connect(_on_cash_chip_input)
	cash_label = cash_chip.find_child("Value", true, false) as Label
	topbar.add_child(cash_chip)
	var gem_chip := _resource_chip("ic_diamond", ThemeMaker.COLORS.purple.lightened(0.2))
	gem_chip.name = "GemResource"
	gem_chip.custom_minimum_size.y = 88
	gem_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gem_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gem_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	gem_chip.gui_input.connect(_on_gem_chip_input)
	gems_label = gem_chip.find_child("Value", true, false) as Label
	topbar.add_child(gem_chip)
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.custom_minimum_size = Vector2(88, 88)
	settings_button.tooltip_text = tr("NAV_SETTINGS")
	settings_button.pressed.connect(_navigate.bind("settings"))
	ThemeMaker.apply_round_button(settings_button, Color("263d59"))
	_wire_button_motion(settings_button)
	_set_button_asset(settings_button, "ic_settings", 42)
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topbar.add_child(settings_button)

	news_panel = PanelContainer.new()
	news_panel.name = "WorldNews"
	news_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	news_panel.offset_left = 150
	news_panel.offset_top = 98
	news_panel.offset_bottom = 154
	news_panel.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("2e2419"), 0.90, 20, ThemeMaker.COLORS.orange))
	news_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	news_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	news_panel.gui_input.connect(_on_news_input)
	stage.add_child(news_panel)
	news_label = _label("", 22, ThemeMaker.COLORS.cream)
	news_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	news_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	news_panel.add_child(news_label)
	_build_campus_switcher(stage)

	navigation_panel = PanelContainer.new()
	navigation_panel.name = "WorldActions"
	navigation_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	navigation_panel.offset_top = -168
	navigation_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stage.add_child(navigation_panel)
	var action_layer := Control.new()
	action_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation_panel.add_child(action_layer)
	task_button = Button.new()
	task_button.name = "TaskButton"
	task_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	task_button.offset_left = 0
	task_button.offset_top = -64
	task_button.offset_right = 112
	task_button.offset_bottom = 64
	task_button.tooltip_text = tr("VIEW_QUEUE")
	task_button.pressed.connect(_navigate.bind("build"))
	ThemeMaker.apply_world_hud_button(task_button)
	_wire_button_motion(task_button)
	_set_world_action_content(task_button, "ic_build", tr("NAV_BUILD"))
	action_layer.add_child(task_button)
	queue_badge_label = _label("", 19, Color.WHITE)
	queue_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_badge_label.position = Vector2(78, -6)
	queue_badge_label.size = Vector2(42, 42)
	queue_badge_label.add_theme_stylebox_override("normal", ThemeMaker.panel(ThemeMaker.COLORS.red, Color.WHITE, 2, 21))
	queue_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_button.add_child(queue_badge_label)

	primary_action_button = _button(tr("BUILD_DATA_CENTER"), _run_primary_action, ThemeMaker.COLORS.green)
	primary_action_button.name = "PrimaryWorldAction"
	primary_action_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	primary_action_button.offset_left = -218
	primary_action_button.offset_top = -104
	primary_action_button.offset_right = 218
	primary_action_button.offset_bottom = -8
	primary_action_button.add_theme_font_size_override("font_size", 28)
	action_layer.add_child(primary_action_button)
	_build_primary_action_content()

	operations_button = Button.new()
	operations_button.name = "OperationsButton"
	operations_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	operations_button.offset_left = -112
	operations_button.offset_top = -64
	operations_button.offset_right = 0
	operations_button.offset_bottom = 64
	operations_button.tooltip_text = tr("OPERATIONS_CENTER")
	operations_button.pressed.connect(_show_operations_hub)
	ThemeMaker.apply_world_hud_button(operations_button)
	_wire_button_motion(operations_button)
	var operations_asset := "ic_operations" if AssetCatalog.texture("ic_operations") != null else "ic_network"
	_set_world_action_content(operations_button, operations_asset, tr("OPERATIONS_SHORT"))
	action_layer.add_child(operations_button)
	operations_badge = Widgets.badge(0)
	operations_badge.position = Vector2(78, -6)
	operations_badge_label = operations_badge.find_child("BadgeValue", true, false) as Label
	operations_badge.visible = false
	operations_button.add_child(operations_badge)

	fx_layer = FxLayerScene.new()
	fx_layer.name = "FxLayer"
	add_child(fx_layer)
	tutorial_overlay = TutorialOverlayScene.new()
	tutorial_overlay.target_activated.connect(_on_tutorial_target_activated)
	add_child(tutorial_overlay)
	_build_tutorial_dormant_hint()

	# A separate canvas guarantees operational feedback paints above every world
	# drawer and modal. z_index alone is not a cross-canvas ordering contract.
	feedback_layer = CanvasLayer.new()
	feedback_layer.name = "OperationFeedbackLayer"
	feedback_layer.layer = 40
	add_child(feedback_layer)
	toast_label = _label("", 25, Color.WHITE)
	toast_label.name = "OperationFeedback"
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.max_lines_visible = 2
	toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Operational feedback must remain readable above drawers, action sheets and
	# tutorial dimming.  The old z=0 label sat behind the building picker, making
	# a correctly rejected third construction look like a dead button.
	toast_label.z_index = 220
	toast_label.size = Vector2(700, 112)
	toast_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_label.position = Vector2(52, 1320)
	toast_label.add_theme_stylebox_override("normal", ThemeMaker.panel(Color(0.05, 0.08, 0.13, 0.94), ThemeMaker.COLORS.sky, 2, 20))
	feedback_layer.add_child(toast_label)

func _build_campus_switcher(stage: Control) -> void:
	campus_switcher = PanelContainer.new()
	campus_switcher.name = "CampusSwitcher"
	campus_switcher.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	campus_switcher.offset_left = 106
	campus_switcher.offset_top = 178
	campus_switcher.offset_right = -106
	campus_switcher.offset_bottom = 274
	campus_switcher.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("162b40"), 0.94, 24, Color(ThemeMaker.COLORS.ivory, 0.34)))
	campus_switcher.mouse_filter = Control.MOUSE_FILTER_STOP
	campus_switcher.visible = false
	stage.add_child(campus_switcher)
	campus_tab_scroll = ScrollContainer.new()
	campus_tab_scroll.name = "CampusTabScroll"
	campus_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	campus_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	campus_tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campus_switcher.add_child(campus_tab_scroll)
	var horizontal_bar := campus_tab_scroll.get_h_scroll_bar()
	horizontal_bar.modulate.a = 0.0
	horizontal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_bar.custom_minimum_size.y = 0.0
	campus_tab_row = HBoxContainer.new()
	campus_tab_row.name = "CampusTabs"
	campus_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	campus_tab_row.add_theme_constant_override("separation", 8)
	campus_tab_scroll.add_child(campus_tab_row)

func _on_campus_changed(_index: int, _count: int) -> void:
	_refresh_campus_switcher()
	call_deferred("_reflow_market_banners")

func _refresh_campus_switcher() -> void:
	if campus_switcher == null or campus_tab_row == null or park_map == null:
		return
	var count := park_map.campus_count()
	var index := park_map.active_campus_index()
	campus_switcher.visible = active_page == "map"
	var summaries := park_map.campus_summaries()
	var signature := "%s:%d:%s" % [TranslationServer.get_locale(), count, ",".join(summaries.map(func(summary: Dictionary) -> String: return str(summary.get("type_id", ""))))]
	if signature != _campus_tab_signature:
		_campus_tab_signature = signature
		for child: Node in campus_tab_row.get_children():
			campus_tab_row.remove_child(child)
			child.queue_free()
		for summary: Dictionary in summaries:
			var campus_index := int(summary.get("index", 0))
			var tab := Button.new()
			tab.name = "CampusTab_%d" % campus_index
			tab.text = tr("CAMPUS_TAB_FORMAT") % (campus_index + 1)
			tab.tooltip_text = "%s · %s" % [tr(str(summary.get("type_name_key", "CAMPUS_TYPE_STANDARD"))), tr("CAMPUS_CAPACITY_DETAIL") % [int(summary.get("capacity", 6)), int(round((float(summary.get("land_price_multiplier", 1.0)) - 1.0) * 100.0))]]
			tab.custom_minimum_size = Vector2(174, 88)
			tab.pressed.connect(_select_campus_tab.bind(campus_index))
			campus_tab_row.add_child(tab)
		var overview_button := Button.new()
		overview_button.name = "CampusOverviewButton"
		overview_button.text = ""
		overview_button.icon = AssetCatalog.texture("ic_operations")
		overview_button.expand_icon = true
		overview_button.add_theme_constant_override("icon_max_width", 44)
		overview_button.tooltip_text = tr("CAMPUS_OVERVIEW")
		overview_button.custom_minimum_size = Vector2(88, 88)
		overview_button.pressed.connect(_show_campus_overview)
		ThemeMaker.apply_compact_button(overview_button, ThemeMaker.COLORS.sky)
		campus_tab_row.add_child(overview_button)
		# One and two-campus states center naturally; only 3+ campuses overflow
		# into a swipeable strip. No permanently visible desktop-style scrollbar.
		campus_tab_row.custom_minimum_size.x = float(count) * 174.0 + float(count) * 8.0 + 88.0
	for child: Node in campus_tab_row.get_children():
		if child is Button and child.name.begins_with("CampusTab_"):
			var tab_index := int(str(child.name).trim_prefix("CampusTab_"))
			ThemeMaker.apply_tab_style(child as Button, tab_index == index)
			(child as Button).add_theme_font_override("font", ThemeMaker.font_bold())
			(child as Button).add_theme_font_size_override("font_size", 22)
			(child as Button).add_theme_color_override("font_color", Color.WHITE)
			(child as Button).add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
			(child as Button).add_theme_constant_override("outline_size", 3)
			if tab_index == index:
				call_deferred("_ensure_campus_tab_visible", tab_index)

func _ensure_campus_tab_visible(index: int) -> void:
	if campus_tab_scroll == null or not is_instance_valid(campus_tab_scroll):
		return
	var tab := campus_tab_row.find_child("CampusTab_%d" % index, false, false) as Control
	if tab != null and campus_tab_scroll.is_ancestor_of(tab):
		campus_tab_scroll.ensure_control_visible(tab)

func _select_campus_tab(index: int) -> void:
	if park_map == null:
		return
	park_map.focus_campus(index)
	_haptic(HAPTIC_LIGHT)

func _show_campus_overview() -> void:
	if park_map == null:
		return
	var active_index := park_map.active_campus_index()
	var choices: Array[Dictionary] = [{
		"id": "strategy_%d" % active_index,
		"text": tr("CAMPUS_STRATEGY"),
		"asset": "campus_strategy",
		"color": ThemeMaker.COLORS.sky,
	}]
	for summary: Dictionary in park_map.campus_summaries():
		var campus_index := int(summary.get("index", 0))
		var alert_count := int(summary.get("alert_count", 0))
		var text := tr("CAMPUS_OVERVIEW_CARD") % [
			campus_index + 1,
			tr(str(summary.get("type_name_key", "CAMPUS_TYPE_STANDARD"))),
			int(summary.get("building_count", 0)),
			int(summary.get("capacity", 6)),
			Game.format_number(float(summary.get("income", 0.0))),
			alert_count,
			int(round((float(summary.get("land_price_multiplier", 1.0)) - 1.0) * 100.0)),
		]
		choices.append({
			"id": "campus_%d" % campus_index,
			"text": text,
			"color": ThemeMaker.COLORS.green.darkened(0.20) if campus_index == active_index else Color("29445c"),
		})
	_present_action_sheet(tr("CAMPUS_OVERVIEW"), tr("CAMPUS_OVERVIEW_SUBTITLE"), choices, func(choice: String) -> void:
		if choice.begins_with("strategy_"):
			_show_campus_strategy(int(choice.trim_prefix("strategy_")))
		elif choice.begins_with("campus_"):
			park_map.focus_campus(int(choice.trim_prefix("campus_")))
	)

func _show_campus_strategy(campus_index: int) -> void:
	var specializations: Dictionary = DataRepository.get_table("meta_progression").get("campus_specializations", {})
	var selected_id := str(Game.state.get("meta", {}).get("campus_specializations", {}).get(str(campus_index), ""))
	var choices: Array[Dictionary] = []
	for specialization_id: String in specializations:
		var specialization: Dictionary = specializations[specialization_id]
		var status := Rules.campus_specialization_status(campus_index, specialization_id, Game.state, Game.data)
		var selected := specialization_id == selected_id
		var active := selected and bool(status.get("active", false))
		var bonus := int(round((float(specialization.get("income_multiplier", 1.0)) - 1.0) * 100.0))
		var state_text := tr("CAMPUS_STRATEGY_ACTIVE_SHORT") % bonus if active else (tr("CAMPUS_STRATEGY_SELECTED_SHORT") if selected else tr("CAMPUS_STRATEGY_FREE_SHORT") % bonus)
		choices.append({
			"id": specialization_id,
			"asset": str(specialization.get("asset_id", "campus_strategy")),
			"height": 104,
			"text": "%s · %s" % [tr(str(specialization.get("name_key", ""))), state_text],
			"color": ThemeMaker.COLORS.green if active else (ThemeMaker.COLORS.sky if selected else Color("29445c")),
		})
	_present_action_sheet(tr("CAMPUS_STRATEGY"), tr("CAMPUS_STRATEGY_SUBTITLE"), choices, func(choice: String) -> void:
		_handle_result(Game.set_campus_specialization(campus_index, choice))
	, ThemeMaker.COLORS.cyan)

func _connect_events() -> void:
	EventBus.state_changed.connect(_on_state_changed)
	EventBus.toast_requested.connect(_on_toast_requested)
	EventBus.offline_settled.connect(_on_offline_settled)
	EventBus.era_unlocked.connect(_on_era_unlocked)
	EventBus.bankruptcy_state_changed.connect(_on_bankruptcy_state_changed)
	EventBus.purchase_completed.connect(_on_purchase_completed)
	EventBus.locale_changed.connect(_on_locale_changed)
	Monetization.product_info_changed.connect(_request_full_refresh)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.rack_fault_occurred.connect(_on_rack_fault_occurred)
	EventBus.contract_auto_renewed.connect(_on_contract_auto_renewed)
	EventBus.relationship_level_changed.connect(_on_relationship_level_changed)
	EventBus.datacenter_entered_aging.connect(_on_datacenter_entered_aging)
	EventBus.market_event_started.connect(_on_market_event_started)
	EventBus.market_event_ended.connect(_on_market_event_ended)
	EventBus.reward_granted.connect(_on_reward_granted)

func _refresh() -> void:
	# Manual refreshes (visual tests, overlays, and immediate navigation) should
	# consume the pending flag too; otherwise the process loop can rebuild the
	# same page during its next layout frame and produce a visibly incomplete UI.
	_needs_refresh = false
	_needs_page_refresh = false
	_refresh_hud()
	_refresh_page()

func _refresh_hud() -> void:
	var player: Dictionary = Game.state.get("player", {})
	var cash := float(player.get("cash", 0.0))
	var gems := float(player.get("gems", 0))
	_maybe_show_periodic_income(cash)
	_animate_hud_number(cash_label, cash, true)
	_animate_hud_number(gems_label, gems, false)
	var era: Dictionary = DataRepository.get_entry("eras", str(int(player.get("era", 1))))
	company_label.text = str(int(player.get("era", 1)))
	var company_button := find_child("CompanyButton", true, false) as Button
	if company_button != null:
		company_button.tooltip_text = "%s · %s" % [tr(era.get("name_key", "ERA_1")), GameClock.format_game_date(Game.simulation_time())]
	era_icon.texture = AssetCatalog.texture("ic_era%d" % int(player.get("era", 1)))
	news_label.text = _news_text()
	var market: Dictionary = Game.state.get("market", {})
	var has_news: bool = not _news_notice_message.is_empty() or not market.get("active", []).is_empty() or not market.get("previews", []).is_empty()
	news_panel.visible = active_page == "map" and has_news
	news_panel.set_meta("destination", "market")
	news_panel.set_meta("swipe_dismiss_enabled", true)
	news_panel.set_meta("transient_market_notice", not _news_notice_message.is_empty())
	var rare_headline := _news_notice_rare or _headline_event_is_rare()
	var news_accent := ThemeMaker.COLORS.purple if rare_headline else (ThemeMaker.COLORS.orange if not _news_notice_message.is_empty() else Color(ThemeMaker.COLORS.ivory, 0.34))
	var news_surface := Color("271a3a") if rare_headline else Color("2e2419")
	news_panel.set_meta("rare_event", rare_headline)
	news_panel.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(news_surface, 0.94, 20, news_accent))
	_refresh_campus_switcher()
	var queue_size: int = Game.state.get("construction_queue", []).size()
	queue_badge_label.text = "%d/%d" % [queue_size, Game.queue_capacity()]
	queue_badge_label.visible = queue_size > 0
	var operations_count := _operations_attention_count()
	operations_badge_label.text = str(operations_count)
	operations_badge.visible = operations_count > 0
	var fault_attention := _has_fault_attention()
	operations_badge.set_meta("attention_tone", "fault" if fault_attention else "normal")
	operations_badge.add_theme_stylebox_override("panel", ThemeMaker.notification_badge(ThemeMaker.COLORS.red if fault_attention else Color("9a6a18")))
	_refresh_primary_action()
	_refresh_arrears_hud()
	_refresh_tutorial()
	park_map.set_cat_suppressed(not bool(Game.state.get("tutorial", {}).get("completed", false)))
	var on_map := active_page == "map"
	# System pages are opaque work surfaces. Keeping the depth-sorted park alive
	# behind their safe-area gutters allowed southern plots and their price rails
	# to peek through the right edge of the board.
	world_host.visible = on_map
	navigation_panel.visible = on_map
	page_host.visible = not on_map
	_sync_market_banner()
	_refresh_live_page()

func _refresh_page() -> void:
	var on_map := active_page == "map"
	if on_map:
		_refresh_park_world()
		# The world target dictionary is rebuilt here, after the HUD/tutorial pass.
		# Re-resolve on the next frame so a just-completed data center can become
		# the first stage of a drawer tutorial immediately.
		call_deferred("_refresh_tutorial")
		_cache_page_scroll(_rendered_page)
		_clear_page_host()
		_rendered_page = "map"
		return
	var page_changed := _rendered_page != active_page
	if page_changed and fx_layer != null:
		fx_layer.clear()
	_cache_page_scroll(_rendered_page)
	for child: Node in page_host.get_children():
		page_host.remove_child(child)
		child.queue_free()
	var next_page: Control
	match active_page:
		"build": next_page = _build_construction_page()
		"market": next_page = _build_market_page()
		"tech": next_page = _build_tech_page()
		"store": next_page = _build_store_page()
		"settings": next_page = _build_settings_page()
		"detail": next_page = _build_datacenter_page()
		_: next_page = _build_construction_page()
	page_host.add_child(next_page)
	next_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_restore_page_scroll", active_page, next_page)
	if page_changed:
		_animate_page_in(next_page)
	_rendered_page = active_page

func _request_hud_refresh() -> void:
	_needs_refresh = true

func _request_full_refresh() -> void:
	_needs_refresh = true
	_needs_page_refresh = true

func _refresh_live_page() -> void:
	if page_host != null and page_host.get_child_count() > 0:
		_refresh_live_region(page_host.get_child(0))
	var context := find_child("DatacenterContext", true, false)
	if context != null and context is CanvasItem and (context as CanvasItem).is_visible_in_tree():
		_refresh_live_region(context)

func _refresh_live_region(root: Node) -> void:
	var live_nodes: Array[Node] = [root]
	live_nodes.append_array(root.find_children("*", "", true, false))
	for node: Node in live_nodes:
		if node.has_meta("live_update"):
			var update: Callable = node.get_meta("live_update")
			if update.is_valid():
				update.call()

func _cache_page_scroll(page_id: String) -> void:
	if page_id.is_empty() or page_id == "map" or page_host == null:
		return
	var scroll := page_host.find_child("PageScroll", true, false) as ScrollContainer
	if scroll != null:
		_page_scroll_cache[page_id] = scroll.scroll_vertical

func _restore_page_scroll(page_id: String, page: Control) -> void:
	if not is_instance_valid(page):
		return
	var scroll := page.find_child("PageScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = int(_page_scroll_cache.get(page_id, 0))

func _refresh_primary_action() -> void:
	var previous_kind := _primary_action_kind
	_set_primary_affordability_pulse(false)
	_primary_action_kind = ""
	_primary_action_target = ""
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("status", "")) == "empty":
			_primary_action_kind = "build"
			_primary_action_target = str(plot.get("id", ""))
			_set_primary_action_content(tr("BUILD_DATA_CENTER"), "ic_build")
			ThemeMaker.apply_button_color(primary_action_button, ThemeMaker.COLORS.green)
			_animate_primary_action_change(previous_kind)
			return
	var queue_size: int = Game.state.get("construction_queue", []).size()
	if queue_size > 0:
		_primary_action_kind = "queue"
		_set_primary_action_content("%s  ·  %d" % [tr("VIEW_QUEUE"), queue_size], "ic_clock")
		ThemeMaker.apply_button_color(primary_action_button, ThemeMaker.COLORS.orange)
		_animate_primary_action_change(previous_kind)
		return
	_primary_action_kind = "buy_plot"
	_set_primary_action_content("%s  ·  $%s" % [tr("BUY_NEXT_PLOT"), Game.format_number(Game.next_plot_price())], "ic_cash")
	ThemeMaker.apply_button_color(primary_action_button, ThemeMaker.COLORS.green)
	_set_primary_affordability_pulse(float(Game.state.get("player", {}).get("cash", 0.0)) >= Game.next_plot_price())
	_animate_primary_action_change(previous_kind)

func _animate_hud_number(label: Label, value: float, cash: bool) -> void:
	var current_target := _cash_target if cash else _gems_target
	if is_nan(current_target):
		if cash:
			_display_cash = value
			_cash_target = value
		else:
			_display_gems = value
			_gems_target = value
		_set_hud_number_text(label, value, cash)
		return
	if is_equal_approx(current_target, value):
		return
	var from_value := _display_cash if cash else _display_gems
	var old_tween := _cash_tween if cash else _gems_tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var delta := absf(value - from_value)
	var large_threshold := maxf(1.0, Game.monthly_income() * 10.0)
	var duration := 1.2 if delta > large_threshold else 0.4
	var tween := label.create_tween()
	tween.tween_method(func(animated: float) -> void:
		if cash:
			_display_cash = animated
		else:
			_display_gems = animated
		_set_hud_number_text(label, animated, cash)
	, from_value, value, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if cash:
		_cash_target = value
		_cash_tween = tween
	else:
		_gems_target = value
		_gems_tween = tween

func _set_hud_number_text(label: Label, value: float, cash: bool) -> void:
	label.text = tr("CASH_FORMAT") % Game.format_number(value) if cash else Game.format_number(roundf(value))

func _maybe_show_periodic_income(cash: float) -> void:
	if is_nan(_last_observed_cash):
		_last_observed_cash = cash
		_last_income_fly_at = Game.simulation_time()
		return
	var increased := cash > _last_observed_cash + 0.01
	_last_observed_cash = cash
	if not increased or active_page != "map" or Game.simulation_time() - _last_income_fly_at < 30.0:
		return
	_last_income_fly_at = Game.simulation_time()
	var source_id := _highest_income_datacenter_id()
	var source := park_map.world_position_of(source_id) if park_map != null else Vector2.ZERO
	_fly_cash_reward(source, 3)
	AudioService.play_sfx("sfx_cash")

func _highest_income_datacenter_id() -> String:
	var best_id := ""
	var best_income := 0.0
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary:
			var income := Game.datacenter_monthly_income(dc)
			if income > best_income:
				best_income = income
				best_id = str(dc.get("id", ""))
	return best_id

func _operations_attention_count() -> int:
	return _operations_tasks(false).size()

func _has_fault_attention() -> bool:
	return _fault_attention_count() > 0

func _fault_attention_count() -> int:
	var count := 0
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary:
			continue
		for rack: Variant in dc.get("racks", []):
			if rack is Dictionary and str(rack.get("status", "")) == "faulted":
				count += 1
	return count

func _operations_tasks(include_market: bool = true) -> Array[Dictionary]:
	var tasks: Array[Dictionary] = []
	var now := Game.simulation_time()
	var buildings := DataRepository.get_table("buildings")
	var racks := DataRepository.get_table("racks")
	var fault_config := DataRepository.get_table("economy").get("faults", {}) as Dictionary
	var aging_start := float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6))
	for plot: Dictionary in Game.state.get("plots", []):
		var dc_variant: Variant = plot.get("datacenter")
		if not dc_variant is Dictionary:
			continue
		var dc := dc_variant as Dictionary
		if str(dc.get("status", "")) != "operational":
			continue
		var dc_id := str(dc.get("id", ""))
		var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
		var building_name := tr(building.get("name_key", "DC_DETAIL"))
		var installed_racks: Array = dc.get("racks", [])
		for slot: int in range(installed_racks.size()):
			var installed: Variant = installed_racks[slot]
			if installed is Dictionary and str(installed.get("status", "")) == "faulted":
				var rack := racks.get("items", {}).get(str(installed.get("rack_id", "")), {}) as Dictionary
				var auto_at := float(installed.get("auto_repair_at", now + float(fault_config.get("auto_repair_seconds", 14400.0))))
				tasks.append({
					"id": "fault:%s:%d" % [dc_id, slot], "type": "fault", "priority": 0,
					"datacenter_id": dc_id, "slot": slot, "asset": "ic_wrench", "accent": ThemeMaker.COLORS.red,
					"title": tr("TASK_FAULT_TITLE") % [tr(rack.get("name_key", "RACKS")), building_name],
					"subtitle": tr("TASK_FAULT_SUBTITLE") % Game.format_duration(maxf(0.0, auto_at - now)), "action": tr("TASK_GO_REPAIR"),
				})
		if bool(dc.get("free_switch_available", false)):
			var customer := DataRepository.get_entry("customers", str(dc.get("customer_id", "")))
			tasks.append({
				"id": "renewal:%s" % dc_id, "type": "renewal", "priority": 1,
				"datacenter_id": dc_id, "slot": -1, "asset": "ic_contract", "accent": ThemeMaker.COLORS.yellow,
				"title": tr("TASK_RENEWAL_TITLE"),
				"subtitle": tr("TASK_RENEWAL_SUBTITLE") % [tr(customer.get("name_key", "CONTRACT_NONE")), building_name],
				"action": tr("TASK_GO_RENEW"),
			})
		var progress := Rules.age_progress(dc, now, buildings)
		if progress >= aging_start:
			tasks.append({
				"id": "retire:%s" % dc_id, "type": "retire", "priority": 2,
				"datacenter_id": dc_id, "slot": -1, "asset": "ic_retire", "accent": ThemeMaker.COLORS.orange,
				"title": tr("TASK_RETIRE_TITLE") % building_name,
				"subtitle": tr("TASK_RETIRE_SUBTITLE") % [Game.format_number(Rules.retirement_value(dc, now, Game.data)), Game.format_number(Game.datacenter_monthly_income(dc))],
				"action": tr("TASK_GO_DECIDE"),
			})
	var open_inquiries: Array = Game.state.get("inquiries", {}).get("open", [])
	if not open_inquiries.is_empty():
		tasks.append({
			"id": "inquiry", "type": "inquiry", "priority": 3,
			"datacenter_id": "", "slot": -1, "asset": "ic_contract", "accent": ThemeMaker.COLORS.yellow,
			"title": tr("INQUIRY_NEW_TASK"),
			"subtitle": tr("INQUIRY_NEW_TASK_SUBTITLE") % open_inquiries.size(), "action": tr("INQUIRY_NEW_TASK_ACTION"),
		})
	if include_market:
		for active: Dictionary in Game.state.get("market", {}).get("active", []):
			var event := DataRepository.get_entry("events", str(active.get("event_id", "")))
			tasks.append({
				"id": "market:%s" % str(active.get("event_id", "")), "type": "market", "priority": 4,
				"datacenter_id": "", "slot": -1, "asset": "ic_market_up", "accent": ThemeMaker.COLORS.green,
				"title": tr("TASK_MARKET_TITLE") % tr(event.get("name_key", "NAV_MARKET")),
				"subtitle": tr("TASK_MARKET_SUBTITLE"), "action": tr("TASK_VIEW_MARKET"),
			})
	tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 99)) == int(b.get("priority", 99)):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return int(a.get("priority", 99)) < int(b.get("priority", 99))
	)
	return tasks

func _set_primary_affordability_pulse(enabled: bool) -> void:
	if enabled and (_primary_pulse_tween == null or not _primary_pulse_tween.is_valid()):
		primary_action_button.pivot_offset = primary_action_button.size * 0.5
		_primary_pulse_tween = primary_action_button.create_tween().set_loops()
		_primary_pulse_tween.tween_property(primary_action_button, "scale", Vector2.ONE * 1.02, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_primary_pulse_tween.tween_property(primary_action_button, "scale", Vector2.ONE, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not enabled and _primary_pulse_tween != null and _primary_pulse_tween.is_valid():
		_primary_pulse_tween.kill()
		primary_action_button.scale = Vector2.ONE

func _animate_primary_action_change(previous_kind: String) -> void:
	if previous_kind == _primary_action_kind or _last_primary_action_kind == _primary_action_kind:
		return
	_last_primary_action_kind = _primary_action_kind
	primary_action_button.pivot_offset = primary_action_button.size * 0.5
	primary_action_button.scale = Vector2(0.94, 0.94)
	create_tween().tween_property(primary_action_button, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _run_primary_action() -> void:
	match _primary_action_kind:
		"build": _show_building_picker(_primary_action_target)
		"queue": _navigate("build")
		"buy_plot": _show_plot_purchase()

func _on_gem_chip_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_navigate("store")

func _on_cash_chip_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_navigate("store")

func _on_news_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	var released: bool = (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
	if pressed:
		_news_gesture["active"] = true
		_news_gesture["start_x"] = _pointer_position(event).x
	elif event is InputEventScreenDrag and bool(_news_gesture.get("active", false)):
		var drag_delta := maxf(0.0, event.position.x - float(_news_gesture.get("start_x", 0.0)))
		news_panel.modulate.a = 1.0 - minf(drag_delta / 520.0, 0.28)
	elif released and bool(_news_gesture.get("active", false)):
		_news_gesture["active"] = false
		var delta := _pointer_position(event).x - float(_news_gesture.get("start_x", 0.0))
		news_panel.modulate.a = 1.0
		if delta >= 80.0 and bool(news_panel.get_meta("transient_market_notice", false)):
			news_panel.accept_event()
			_dismiss_market_notice()
		elif absf(delta) < 18.0:
			_navigate("market")

func _show_operations_hub() -> void:
	var parts := _create_world_sheet("OperationsHub", 1560)
	var overlay := parts["overlay"] as ColorRect
	var box := parts["box"] as VBoxContainer
	var tasks := _operations_tasks(true)
	var actionable_count := _operations_attention_count()
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	box.add_child(heading)
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_copy)
	var operations_title := _label(tr("OPERATIONS_CENTER"), 38, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(operations_title, "display")
	heading_copy.add_child(operations_title)
	var summary_text := tr("OPERATIONS_PENDING_SUMMARY") % actionable_count if actionable_count > 0 else tr("OPERATIONS_ALL_CLEAR")
	heading_copy.add_child(_label(summary_text, 22, ThemeMaker.COLORS.cyan if actionable_count == 0 else ThemeMaker.COLORS.orange))
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	heading.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.name = "OperationsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	scroll.add_child(content)
	var pending_title := _label(tr("OPERATIONS_PENDING"), 27, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(pending_title, "title")
	content.add_child(pending_title)
	if tasks.is_empty():
		var clear_card := Widgets.flat_card(ThemeMaker.COLORS.green)
		clear_card.name = "OperationsClearState"
		var clear_copy := _label(tr("OPERATIONS_ALL_CLEAR_DETAIL"), 22, ThemeMaker.COLORS.cyan)
		clear_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clear_card.add_child(clear_copy)
		content.add_child(clear_card)
	else:
		var task_list := VBoxContainer.new()
		task_list.name = "OperationsTaskList"
		task_list.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		content.add_child(task_list)
		for task: Dictionary in tasks:
			task_list.add_child(_operations_task_row(task, overlay))

	var queue_size: int = Game.state.get("construction_queue", []).size()
	var era_id := int(Game.state.get("player", {}).get("era", 1))
	var era := DataRepository.get_entry("eras", str(era_id))
	var modules: Array[Dictionary] = [
		{"id": "build", "title": tr("CONSTRUCTION_QUEUE"), "subtitle": tr("QUEUE_CAPACITY") % [queue_size, Game.queue_capacity()], "asset": "ic_build", "accent": ThemeMaker.COLORS.orange if queue_size > 0 else ThemeMaker.COLORS.sky},
		{"id": "market", "title": tr("NAV_MARKET"), "subtitle": _news_text(), "asset": "ic_market_up", "accent": ThemeMaker.COLORS.orange if not Game.state.get("market", {}).get("active", []).is_empty() else ThemeMaker.COLORS.sky},
		{"id": "tech", "title": tr("NAV_TECH"), "subtitle": tr(era.get("name_key", "ERA_1")), "asset": "ic_tech", "accent": ThemeMaker.COLORS.purple},
		{"id": "store", "title": tr("NAV_STORE"), "subtitle": tr("GEMS_FORMAT") % Game.format_number(float(Game.state.get("player", {}).get("gems", 0))), "asset": "ic_shop", "accent": ThemeMaker.COLORS.green},
	]
	var tools_title := _label(tr("OPERATIONS_TOOLS"), 27, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(tools_title, "title")
	content.add_child(tools_title)
	var grid := GridContainer.new()
	grid.name = "OperationsToolsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	for module: Dictionary in modules:
		var module_id := str(module["id"])
		var card := _operation_module_card(module, func() -> void:
			_dismiss_world_sheet(overlay, _navigate.bind(module_id))
		, true)
		grid.add_child(card)

func _operations_task_row(task: Dictionary, overlay: ColorRect) -> PanelContainer:
	var accent: Color = task.get("accent", ThemeMaker.COLORS.sky)
	var row := Widgets.flat_card(accent)
	var safe_id := str(task.get("id", "task")).replace(":", "_")
	row.name = "OperationsTask_%s" % safe_id
	row.custom_minimum_size.y = 124
	row.set_meta("task_id", str(task.get("id", "")))
	row.set_meta("task_type", str(task.get("type", "")))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	row.add_child(line)
	line.add_child(_icon_view(str(task.get("asset", "ic_warning")), Vector2(54, 54)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	line.add_child(copy)
	var title := _label(str(task.get("title", "")), 23, ThemeMaker.COLORS.cream)
	title.name = "TaskTitle"
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ThemeMaker.apply_text_role(title, "title")
	copy.add_child(title)
	var subtitle := _label(str(task.get("subtitle", "")), 20, ThemeMaker.COLORS.cyan)
	subtitle.name = "TaskSubtitle"
	subtitle.max_lines_visible = 1
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(subtitle)
	var role := "danger" if str(task.get("type", "")) == "fault" else ("warning" if str(task.get("type", "")) in ["renewal", "retire"] else "secondary")
	var action_button := Widgets.button(str(task.get("action", "")), func() -> void:
		_dismiss_world_sheet(overlay, _run_operations_task.bind(task.duplicate(true)))
	, role)
	action_button.name = "TaskAction_%s" % safe_id
	action_button.custom_minimum_size = Vector2(142, ThemeMaker.TOUCH_MIN)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	action_button.set_meta("task_id", str(task.get("id", "")))
	action_button.set_meta("task_type", str(task.get("type", "")))
	line.add_child(action_button)
	return row

func _run_operations_task(task: Dictionary) -> void:
	var datacenter_id := str(task.get("datacenter_id", ""))
	match str(task.get("type", "")):
		"fault": _show_rack_actions(datacenter_id, int(task.get("slot", -1)))
		"renewal": _open_datacenter_detail(datacenter_id, "contracts")
		"retire": _show_datacenter_context(datacenter_id)
		"market", "inquiry": _navigate("market")
		_: _handle_result({"ok": false, "reason": "unknown"})

func _operation_module_card(module: Dictionary, action: Callable, compact: bool = false) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 164 if compact else 214)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(action)
	ThemeMaker.apply_compact_button(card, Color("243b55"))
	_wire_button_motion(card)
	var accent: Color = module.get("accent", ThemeMaker.COLORS.sky)
	card.add_theme_stylebox_override("normal", ThemeMaker.glass_panel(ThemeMaker.SURFACE, 0.98, 24, Color(accent, 0.42)))
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_top = 16
	content.offset_right = -20
	content.offset_bottom = -16
	content.add_theme_constant_override("separation", 5)
	card.add_child(content)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(top)
	top.add_child(_icon_view(str(module.get("asset", "ic_build")), Vector2(56, 56) if compact else Vector2(72, 72)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var status_dot := PanelContainer.new()
	status_dot.custom_minimum_size = Vector2(18, 18)
	status_dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := ThemeMaker.panel(accent, Color(1, 1, 1, 0.36), 1, 9)
	dot_style.content_margin_left = 0
	dot_style.content_margin_right = 0
	dot_style.content_margin_top = 0
	dot_style.content_margin_bottom = 0
	status_dot.add_theme_stylebox_override("panel", dot_style)
	top.add_child(status_dot)
	var module_title := _label(str(module.get("title", "")), 24 if compact else 28, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(module_title, "title")
	content.add_child(module_title)
	var subtitle := _label(str(module.get("subtitle", "")), 20, ThemeMaker.COLORS.cyan)
	subtitle.max_lines_visible = 2
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(subtitle)
	return card

func _refresh_park_world() -> void:
	var signature := JSON.stringify(Game.state.get("plots", [])) + JSON.stringify(Game.state.get("market", {}).get("active", []))
	if signature == _last_map_signature:
		return
	_last_map_signature = signature
	park_map.setup(Game.state.get("plots", []))
	call_deferred("_reflow_market_banners")

func _clear_page_host() -> void:
	for child: Node in page_host.get_children():
		page_host.remove_child(child)
		child.queue_free()

func _animate_page_in(page: Control) -> void:
	page.modulate.a = 0.0
	page.position.y += 22.0
	var target_y := page.position.y - 22.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(page, "modulate:a", 1.0, 0.18)
	tween.tween_property(page, "position:y", target_y, 0.26).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _build_construction_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("CONSTRUCTION_QUEUE"), tr("QUEUE_CAPACITY") % [Game.state.get("construction_queue", []).size(), Game.queue_capacity()], "ic_build"))
	if Game.state.get("construction_queue", []).is_empty():
		box.add_child(_empty_action_state("ic_build", tr("QUEUE_EMPTY"), tr("TUTORIAL_WELCOME"), tr("NAV_MAP"), _navigate.bind("map"), ThemeMaker.COLORS.sky))
	for item: Dictionary in Game.state.get("construction_queue", []):
		var card := _card()
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 14)
		card.add_child(inner)
		var job_header := HBoxContainer.new()
		job_header.add_theme_constant_override("separation", 18)
		inner.add_child(job_header)
		job_header.add_child(_icon_view(_construction_asset_id(item), Vector2(112, 112)))
		var job_copy := VBoxContainer.new()
		job_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		job_header.add_child(job_copy)
		job_copy.add_child(_label(_construction_name(item), 31, ThemeMaker.COLORS.cream))
		job_copy.add_child(_progress_for_job(item))
		var actions := GridContainer.new()
		actions.columns = 2
		actions.add_theme_constant_override("h_separation", 10)
		actions.add_theme_constant_override("v_separation", 10)
		inner.add_child(actions)
		var remaining := maxf(0.0, float(item.get("complete_at", 0.0)) - Game.simulation_time())
		var gems := maxi(1, int(ceil(remaining / 600.0)) * int(DataRepository.get_table("economy").get("construction", {}).get("gems_per_600_seconds", 1)))
		var speed_button := _button("%s · %d" % [tr("SPEED_UP"), gems], _speedup_job.bind(str(item.get("id", ""))), ThemeMaker.COLORS.purple)
		_set_button_asset(speed_button, "ic_diamond", 38)
		actions.add_child(speed_button)
		var tickets := int(Game.state.get("inventory", {}).get("instant_build_tickets", 0))
		if tickets > 0:
			actions.add_child(_button("%s · %d" % [tr("INSTANT_TICKET"), tickets], _use_ticket.bind(str(item.get("id", ""))), ThemeMaker.COLORS.yellow.darkened(0.25)))
		var max_ads := int(DataRepository.get_table("economy").get("construction", {}).get("max_ads_per_project", 2))
		var ad_button := _button("%s\n-30m · %d/%d" % [tr("WATCH_AD"), int(item.get("ad_uses", 0)), max_ads], _reward_job.bind(str(item.get("id", ""))), ThemeMaker.COLORS.purple)
		if int(item.get("ad_uses", 0)) >= max_ads:
			_mark_explained_unavailable(ad_button, "reward_limit")
		actions.add_child(ad_button)
		box.add_child(card)
	return _wrap_scroll(box)

func _build_datacenter_page() -> Control:
	var dc := Game.find_datacenter(selected_datacenter_id)
	if dc.is_empty():
		active_page = "map"
		call_deferred("_handle_result", {"ok": false, "reason": "datacenter_missing"})
		call_deferred("_request_full_refresh")
		return Control.new()
	var box := _page_box()
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	box.add_child(_system_page_header(tr(building.get("name_key", "")), _datacenter_status_text(dc), _datacenter_context_asset(dc, building)))
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	var detail_metrics := HBoxContainer.new()
	detail_metrics.add_theme_constant_override("separation", 10)
	detail_metrics.add_child(_metric_chip(_lifespan_metric_text(progress), ThemeMaker.COLORS.yellow))
	detail_metrics.add_child(_metric_chip(tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc)), ThemeMaker.COLORS.green))
	box.add_child(detail_metrics)
	if dc.get("status", "") == "ruined":
		box.add_child(_asset_preview(str(building.get("asset_prefix", "")) + "_ruin", tr("DEMOLISH"), ThemeMaker.COLORS.red, 300))
		box.add_child(_button(tr("CLEAR_SCRAP_QUOTE") % Game.format_number(Rules.ruin_scrap_value(dc, Game.data)), _demolish.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.green))
		return _wrap_scroll(box)
	if _detail_focus == "infrastructure":
		_detail_focus = "board"
	box.add_child(_segmented_control([
		{"id": "board", "label": tr("RACKS"), "asset": "slot_empty"},
		{"id": "contracts", "label": tr("SIGN_CONTRACT"), "asset": "ic_contract"},
	], _detail_focus, _set_detail_focus))
	box.add_child(_build_contract_management(dc) if _detail_focus == "contracts" else _build_rack_management(dc, building))
	return _wrap_scroll(box)

func _set_detail_focus(focus: String) -> void:
	if _detail_focus == focus:
		return
	_detail_focus = focus
	_request_full_refresh()

func _lifespan_metric_text(progress: float) -> String:
	var text := "%s  %d%%" % [tr("LIFESPAN"), int(progress * 100.0)]
	if bool(Game.state.get("technology", {}).get("auto_retirement", false)):
		text += " · " + (tr("AUTO_RETIRE_MARKER") % int(round(float(DataRepository.get_table("economy").get("aging", {}).get("auto_retire_progress", 0.95)) * 100.0)))
	return text

func _build_rack_management(dc: Dictionary, building: Dictionary) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(_create_datacenter_board(str(dc.get("id", ""))))
	return section

func _create_datacenter_board(datacenter_id: String) -> DatacenterBoard:
	var board := DatacenterBoardScene.new()
	board.setup(datacenter_id)
	board.rack_slot_selected.connect(_on_board_rack_slot_selected)
	board.cooler_slot_selected.connect(func(dc_id: String, edge: String) -> void: _show_attachment_picker(dc_id, "cooler", edge))
	board.power_slot_selected.connect(_on_power_slot_selected)
	return board

func _on_board_rack_slot_selected(datacenter_id: String, slot: int) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	var racks: Array = dc.get("racks", [])
	if slot < racks.size() and racks[slot] is Dictionary and not racks[slot].is_empty():
		_show_rack_actions(datacenter_id, slot)
	else:
		_show_rack_picker(datacenter_id, slot)

func _build_infrastructure_management(dc: Dictionary, progress: float) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 14)
	section.add_child(_section_title(tr("INFRASTRUCTURE"), tr("INFRASTRUCTURE_SUBTITLE")))
	var attachments := GridContainer.new()
	attachments.columns = 2
	attachments.add_theme_constant_override("h_separation", 10)
	attachments.add_theme_constant_override("v_separation", 10)
	section.add_child(attachments)
	var power_text := tr(DataRepository.get_entry("attachments", str(dc.get("power_unit", ""))).get("name_key", "UNPOWERED"))
	var power_button := _button(power_text, _on_power_slot_selected.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.yellow.darkened(0.2))
	power_button.custom_minimum_size.y = 118
	if str(dc.get("power_unit", "")).is_empty():
		_set_button_asset(power_button, "ic_power", 54)
	else:
		_set_button_asset(power_button, str(dc.get("power_unit", "")) + "_active", 60)
	attachments.add_child(power_button)
	for edge: String in ["north", "east", "south", "west"]:
		var cooler_id := str(dc.get("coolers", {}).get(edge, ""))
		var cooler_name := tr(DataRepository.get_entry("attachments", cooler_id).get("name_key", "INSTALL"))
		var cooler_button := _button("%s\n%s" % [edge.capitalize(), cooler_name], _show_attachment_picker.bind(str(dc.get("id", "")), "cooler", edge), ThemeMaker.COLORS.sky.darkened(0.1))
		cooler_button.custom_minimum_size.y = 118
		if cooler_id.is_empty():
			_set_button_asset(cooler_button, "ic_cooling", 48)
		else:
			_set_button_asset(cooler_button, cooler_id + "_active", 54)
		attachments.add_child(cooler_button)
	if progress >= float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6)):
		section.add_child(_retirement_decision(dc, progress))
	return section

func _retirement_decision(dc: Dictionary, progress: float) -> VBoxContainer:
	var decision := VBoxContainer.new()
	decision.name = "RetirementDecision"
	decision.add_theme_constant_override("separation", 6)
	var refund := Rules.retirement_value(dc, Game.simulation_time(), Game.data)
	var warning := progress >= RETIRE_WARNING_PROGRESS
	var button_color := ThemeMaker.COLORS.orange if warning else Color("3b536c")
	var retire_button := _button("%s · +$%s" % [tr("RETIRE"), Game.format_number(refund)], _retire.bind(str(dc.get("id", ""))), button_color)
	retire_button.name = "RetireButton"
	retire_button.set_meta("retirement_progress", progress)
	retire_button.set_meta("warning_active", warning)
	decision.add_child(retire_button)
	var tradeoff := _label(tr("RETIRE_TRADEOFF") % Game.format_number(Game.datacenter_monthly_income(dc)), 20, Color("b8c2cc"))
	tradeoff.name = "RetireTradeoff"
	tradeoff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tradeoff.max_lines_visible = 1
	tradeoff.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	decision.add_child(tradeoff)
	return decision

func _build_contract_management(dc: Dictionary) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	var capacity_state := _contract_capacity_state(dc)
	var current_customer := str(dc.get("customer_id", ""))
	var client_name := tr(DataRepository.get_entry("customers", current_customer).get("name_key", "CONTRACT_NONE"))
	var timing_text := ""
	if not current_customer.is_empty():
		if bool(dc.get("free_switch_available", false)):
			timing_text = tr("CONTRACT_RENEWAL_WINDOW")
		else:
			timing_text = tr("CONTRACT_REMAINING") % Game.format_duration(maxf(0.0, float(dc.get("contract_end_at", 0.0)) - Game.simulation_time()))
	var summary := Widgets.flat_card()
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	summary.add_child(summary_box)
	var current_label := _label(tr("CONTRACT_CURRENT") % client_name, ThemeMaker.TYPE_SCALE.body, Color.WHITE)
	current_label.max_lines_visible = 1
	current_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary_box.add_child(current_label)
	if not timing_text.is_empty():
		var timing_label := _label(timing_text, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.green if bool(dc.get("free_switch_available", false)) else ThemeMaker.COLORS.cyan)
		timing_label.max_lines_visible = 1
		timing_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary_box.add_child(timing_label)
	if not current_customer.is_empty():
		var rates := HBoxContainer.new()
		rates.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		rates.add_child(Widgets.chip(tr("CONTRACT_LOCKED_RATE") % float(dc.get("locked_market_multiplier", Game.contract_market_multiplier(current_customer))), ThemeMaker.COLORS.green))
		rates.add_child(Widgets.chip(tr("CONTRACT_MARKET_RATE") % Game.market_multiplier(current_customer), ThemeMaker.COLORS.cyan))
		summary_box.add_child(rates)
		var event_seconds := float(dc.get("contract_prorated_event_seconds", 0.0))
		if event_seconds > 0.0:
			var month_seconds := float(DataRepository.get_table("economy").get("time", {}).get("real_seconds_per_game_month", 7200.0))
			summary_box.add_child(_label(tr("CONTRACT_PRORATED_EVENT") % (event_seconds / month_seconds), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan))
		var cap := float(DataRepository.get_table("economy").get("contracts", {}).get("strategic_lock_cap", 2.5))
		if str(dc.get("contract_duration_id", "standard")) == "strategic" and Game.contract_market_multiplier(current_customer) > cap and is_equal_approx(float(dc.get("locked_market_multiplier", 0.0)), cap):
			summary_box.add_child(_label(tr("CONTRACT_STRATEGIC_CAP") % cap, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.purple))
		var relationship := Rules.relationship_level(current_customer, Game.state, Game.data)
		if int(relationship.get("index", 0)) >= 1:
			var persona := PersonaSystemScene.persona_for_contract(dc, DataRepository.tables)
			if not persona.is_empty():
				summary_box.add_child(_contract_contact_row(persona, str(dc.get("id", ""))))
	section.add_child(summary)
	if capacity_state != "ready":
		section.add_child(_contract_capacity_guide(dc, capacity_state))
	var contracts := VBoxContainer.new()
	contracts.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(contracts)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		var available := int(customer.get("unlock_era", 1)) <= int(Game.state["player"].get("era", 1)) and int(customer.get("minimum_network_level", 1)) <= int(Game.state["player"].get("network_level", 1))
		contracts.add_child(_contract_customer_card(dc, customer_id, customer, current_customer, available))
	return section

func _contract_contact_row(persona: Dictionary, datacenter_id: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "ContractPersonaContact"
	row.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	var portrait := Button.new()
	portrait.name = "ContractPersonaPortrait"
	portrait.custom_minimum_size = Vector2(88, 88)
	portrait.focus_mode = Control.FOCUS_NONE
	portrait.icon = AssetCatalog.texture(str(persona.get("asset_id", "")))
	portrait.expand_icon = true
	portrait.add_theme_constant_override("icon_max_width", 80)
	portrait.add_theme_stylebox_override("normal", ThemeMaker.panel(Color("18334f"), Color(ThemeMaker.COLORS.sky, 0.65), 2, 18))
	portrait.add_theme_stylebox_override("hover", ThemeMaker.panel(Color("20486a"), ThemeMaker.COLORS.sky, 2, 18))
	portrait.add_theme_stylebox_override("pressed", ThemeMaker.panel(Color("122a43"), ThemeMaker.COLORS.sky, 2, 18))
	portrait.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	portrait.pressed.connect(_show_persona_chat.bind(persona.duplicate(true), datacenter_id))
	Widgets.wire_button_motion(portrait)
	row.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	copy.add_child(_label(tr("PERSONA_CONTACT") % tr(str(persona.get("name_key", ""))), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.cream))
	var line_key := PersonaSystemScene.line_key(persona, "chat", datacenter_id)
	var chat_hint := _label(tr(line_key), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
	chat_hint.max_lines_visible = 1
	chat_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(chat_hint)
	return row

func _show_persona_chat(persona: Dictionary, context: String) -> void:
	var line_key := PersonaSystemScene.line_key(persona, "chat", context)
	if not line_key.is_empty():
		_show_persona_toast(persona, tr(line_key))

func _contract_capacity_state(dc: Dictionary) -> String:
	var racks: Array = dc.get("racks", [])
	var powered := Rules.powered_slots(dc, Game.data.get("racks", {}), Game.data.get("attachments", {}))
	var has_rack := false
	var installing := false
	for slot: int in range(mini(racks.size(), powered.size())):
		var installed: Variant = racks[slot]
		if not installed is Dictionary or installed.is_empty():
			continue
		has_rack = true
		var status := str((installed as Dictionary).get("status", "active"))
		if status == "installing":
			installing = true
		elif status in ["active", "faulted"] and powered[slot]:
			return "ready"
	if installing:
		return "pending"
	return "offline" if has_rack else "empty"

func _contract_capacity_guide(dc: Dictionary, capacity_state: String) -> PanelContainer:
	var guide := Widgets.flat_card(Color(ThemeMaker.COLORS.cyan, 0.55))
	guide.name = "ContractCapacityGuide"
	guide.set_meta("capacity_state", capacity_state)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	guide.add_child(box)
	var title := _label(tr("CONTRACT_CAPACITY_TITLE"), ThemeMaker.TYPE_SCALE.heading, ThemeMaker.COLORS.cream)
	title.name = "ContractCapacityTitle"
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var message_key := "CONTRACT_CAPACITY_PENDING" if capacity_state == "pending" else ("CONTRACT_CAPACITY_OFFLINE" if capacity_state == "offline" else "CONTRACT_CAPACITY_EMPTY")
	var message := _label(tr(message_key), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
	message.name = "ContractCapacityMessage"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	var configure := _button(tr("CONTRACT_CONFIGURE_RACKS"), _open_datacenter_detail.bind(str(dc.get("id", "")), "board"), ThemeMaker.COLORS.sky)
	configure.name = "ContractConfigureRacks"
	box.add_child(configure)
	return guide

func _contract_customer_card(dc: Dictionary, customer_id: String, customer: Dictionary, current_customer: String, available: bool) -> Button:
	var serving := customer_id == current_customer
	var action := _sign_contract.bind(str(dc.get("id", "")), customer_id) if available else _show_toast.bind(_customer_unlock_text(customer))
	var card := Button.new()
	card.name = "Contract_%s" % customer_id
	card.focus_mode = Control.FOCUS_NONE
	# Contract cards live inside PageScroll.  The default Button mouse filter
	# consumes ScreenDrag before ScrollContainer can see it, which makes the
	# customer list look scrollable while remaining frozen on iOS.  PASS keeps
	# the release-to-select behaviour and hands an actual drag to the parent.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	card.set_meta("scroll_drag_passthrough", true)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(action)
	card.set_meta("glossy_button", false)
	var accent := ThemeMaker.COLORS.green if serving else Color.TRANSPARENT
	card.add_theme_stylebox_override("normal", ThemeMaker.flat_group_box(accent))
	card.add_theme_stylebox_override("hover", ThemeMaker.flat_group_box(Color(ThemeMaker.COLORS.sky, 0.65)))
	card.add_theme_stylebox_override("pressed", ThemeMaker.flat_group_box(Color(ThemeMaker.COLORS.sky, 0.85)))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	Widgets.wire_button_motion(card)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = ThemeMaker.GROUP_PADDING
	content.offset_top = ThemeMaker.GROUP_PADDING
	content.offset_right = -ThemeMaker.GROUP_PADDING
	content.offset_bottom = -ThemeMaker.GROUP_PADDING
	content.add_theme_constant_override("separation", ThemeMaker.GROUP_PADDING)
	card.add_child(content)
	content.add_child(_icon_view(str(customer.get("asset_id", "")), Vector2(64, 64)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	content.add_child(copy)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	copy.add_child(top)
	var title := _label(tr(customer.get("name_key", "")), ThemeMaker.TYPE_SCALE.heading, Color.WHITE)
	ThemeMaker.apply_text_role(title, "title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	if serving:
		var badge := Widgets.chip(tr("CONTRACT_IN_SERVICE"), Color.WHITE)
		badge.custom_minimum_size = Vector2(128, 40)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		badge.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("31593f"), Color(ThemeMaker.COLORS.green, 0.45), 1, 12))
		var badge_label := badge.find_child("Value", true, false) as Label
		badge_label.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.caption)
		top.add_child(badge)
	if available:
		var relationship := Rules.relationship_level(customer_id, Game.state, Game.data)
		var relationship_label := _label(tr("RELATIONSHIP_STATUS") % [tr(str(relationship.get("name_key", "RELATIONSHIP_NEW"))), float(relationship.get("income_multiplier", 1.0))], ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
		relationship_label.max_lines_visible = 1
		relationship_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(relationship_label)
		var trend := _market_trend(customer_id)
		var trend_percent := float(trend.get("percent", 0.0))
		var value := _label("×%.2f  %s %+.1f%%" % [Game.market_multiplier(customer_id), str(trend.get("arrow", "→")), trend_percent], 32, ThemeMaker.COLORS.red if trend_percent > 0.05 else ThemeMaker.COLORS.green)
		value.name = "MarketRate_%s" % customer_id
		ThemeMaker.apply_numeric_text(value)
		copy.add_child(value)
		var capacity_ready := _contract_capacity_state(dc) == "ready"
		var projection_copy := tr("CONTRACT_PROJECTED") % Game.format_number(_projected_datacenter_income(dc, customer_id)) if capacity_ready else tr("CONTRACT_PROJECTED_AFTER_RACK")
		var projected := _label(projection_copy, ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.yellow)
		projected.name = "ContractProjection_%s" % customer_id
		projected.max_lines_visible = 1
		projected.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(projected)
		var fit: Dictionary = customer.get("fit", {})
		card.tooltip_text = tr("CONTRACT_FIT_TOOLTIP") % [float(fit.get("compute", 0.0)), float(fit.get("storage", 0.0)), float(fit.get("gpu", 0.0))]
		var fee := Game.contract_switch_fee(str(dc.get("id", "")), customer_id)
		if not current_customer.is_empty() and not serving:
			card.tooltip_text += "\n" + (tr("CONTRACT_FREE_SWITCH") if fee <= 0.0 else tr("CONTRACT_BREACH_FEE") % Game.format_number(fee))
	else:
		var locked := _label(_customer_unlock_text(customer), ThemeMaker.TYPE_SCALE.body, Color("aeb8c4"))
		locked.max_lines_visible = 1
		locked.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(locked)
	card.custom_minimum_size.y = 216 if available else 144
	call_deferred("_fit_contract_card_height", card, content)
	if serving:
		var rail := ColorRect.new()
		rail.color = ThemeMaker.COLORS.green
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		rail.offset_right = 6
		card.add_child(rail)
	return card

func _fit_contract_card_height(card: Button, content: Control) -> void:
	if not is_instance_valid(card) or not is_instance_valid(content):
		return
	card.custom_minimum_size.y = maxf(ThemeMaker.TOUCH_MIN, content.get_combined_minimum_size().y + ThemeMaker.GROUP_PADDING * 2.0)

func _projected_datacenter_income(dc: Dictionary, customer_id: String, duration_id: String = "standard") -> float:
	var simulated := dc.duplicate(true)
	simulated["customer_id"] = customer_id
	simulated["locked_market_multiplier"] = Game.contract_market_multiplier(customer_id)
	var duration: Dictionary = DataRepository.get_table("meta_progression").get("contract_durations", {}).get(duration_id, {})
	simulated["contract_income_multiplier"] = float(duration.get("income_multiplier", 1.0))
	return Rules.datacenter_income_per_month(simulated, Game.state, Game.data, func(id: String) -> float: return Game.market_multiplier(id))

func _market_trend(customer_id: String) -> Dictionary:
	var history: Array = Game.state.get("market", {}).get("history", {}).get(customer_id, [])
	if history.size() < 2:
		return {"arrow": "→", "percent": 0.0}
	var previous := float(history[-2].get("value", 1.0))
	var current := float(history[-1].get("value", 1.0))
	var percent := (current / maxf(0.001, previous) - 1.0) * 100.0
	return {"arrow": "↑" if percent > 0.05 else ("↓" if percent < -0.05 else "→"), "percent": percent}

func _customer_unlock_text(customer: Dictionary) -> String:
	var era_required := int(customer.get("unlock_era", 1))
	if era_required > int(Game.state.get("player", {}).get("era", 1)):
		return tr("UNLOCK_AT_ERA") % era_required
	var network_required := int(customer.get("minimum_network_level", 1))
	var network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_required), {})
	return tr("UNLOCK_AT_NETWORK") % tr(network.get("name_key", "NETWORK"))

func _build_market_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_MARKET"), tr("MARKET_SIGNING_ADVISOR"), "ic_market_up"))
	box.add_child(_meta_hero("market_review", tr("MARKET_REVIEW"), tr("MARKET_REVIEW_SUBTITLE")))
	for active: Dictionary in Game.state.get("market", {}).get("active", []):
		var active_event := DataRepository.get_entry("events", str(active.get("event_id", "")))
		if bool(active_event.get("rare", false)):
			var rare_banner := Widgets.flat_card(ThemeMaker.COLORS.purple)
			rare_banner.name = "RareEventBanner"
			rare_banner.custom_minimum_size.y = ThemeMaker.TOUCH_MIN
			var rare_row := HBoxContainer.new()
			rare_row.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
			rare_banner.add_child(rare_row)
			rare_row.add_child(_icon_view("ic_market_up", Vector2(48, 48)))
			var rare_copy := _label("%s · %s" % [tr("EVENT_RARE_BADGE"), tr(active_event.get("name_key", ""))], ThemeMaker.TYPE_SCALE.body, Color.WHITE)
			rare_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rare_copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rare_copy.max_lines_visible = 1
			rare_copy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			rare_row.add_child(rare_copy)
			box.add_child(rare_banner)
			break
	if _inquiries_enabled():
		box.add_child(_build_inquiry_section())
	var chart_card := _card()
	var chart_box := VBoxContainer.new()
	chart_box.add_theme_constant_override("separation", 10)
	chart_card.add_child(chart_box)
	var chart := ChartScene.new()
	chart.name = "MarketChart"
	chart.set_series(Game.state.get("market", {}).get("history", {}))
	chart.set_events(Game.state.get("market", {}).get("active", []))
	chart_box.add_child(chart)
	var legend := GridContainer.new()
	legend.name = "MarketLegend"
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 10)
	legend.add_theme_constant_override("v_separation", 8)
	chart_box.add_child(legend)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		legend.add_child(_market_legend_button(chart, customer_id, DataRepository.get_entry("customers", customer_id)))
	box.add_child(chart_card)
	var any_event := false
	for active: Dictionary in Game.state.get("market", {}).get("active", []):
		if not any_event:
			box.add_child(_section_title(tr("MARKET_ACTIVE"), ""))
		any_event = true
		box.add_child(_event_card(active, false))
	for preview: Dictionary in Game.state.get("market", {}).get("previews", []):
		if not any_event:
			box.add_child(_section_title(tr("MARKET_PREVIEW"), ""))
		any_event = true
		box.add_child(_event_card(preview, true))
	box.add_child(_section_title(tr("MARKET_CUSTOMERS"), tr("MARKET_CUSTOMERS_HINT")))
	var customers := GridContainer.new()
	# Contract names are product concepts, not abbreviations. One column preserves
	# full names in both locales and lets the signal cards breathe on a phone.
	customers.columns = 1
	customers.add_theme_constant_override("h_separation", 12)
	customers.add_theme_constant_override("v_separation", 12)
	box.add_child(customers)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		customers.add_child(_customer_market_card(customer_id, customer))
	box.add_child(_build_market_review_section())
	return _wrap_scroll(box)

func _inquiries_enabled() -> bool:
	var minimum := int(DataRepository.get_table("inquiries").get("settings", {}).get("min_datacenters_built", 2))
	return bool(Game.state.get("tutorial", {}).get("completed", false)) and int(Game.state.get("player", {}).get("total_datacenters_built", 0)) >= minimum

func _build_inquiry_section() -> Control:
	var section := VBoxContainer.new()
	section.name = "InquiryBoard"
	section.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(_section_title(tr("INQUIRY_BOARD"), tr("INQUIRY_BOARD_HINT")))
	var open: Array = Game.state.get("inquiries", {}).get("open", [])
	if open.is_empty():
		section.add_child(_status_card("ic_contract", tr("INQUIRY_EMPTY"), ThemeMaker.COLORS.cyan, true))
		return section
	var cards := VBoxContainer.new()
	cards.name = "InquiryCards"
	cards.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(cards)
	for inquiry: Dictionary in open:
		cards.add_child(_inquiry_card(inquiry))
	return section

func _inquiry_card(inquiry: Dictionary) -> Control:
	var template := DataRepository.get_table("inquiries").get("items", {}).get(str(inquiry.get("template_id", "")), {}) as Dictionary
	var customer := DataRepository.get_entry("customers", str(template.get("customer_id", "")))
	var persona := PersonaSystemScene.persona_for_inquiry(inquiry, DataRepository.tables)
	var card := Widgets.flat_card(ThemeMaker.COLORS.yellow)
	card.name = "InquiryCard_%s" % str(inquiry.get("id", ""))
	card.set_meta("inquiry_id", str(inquiry.get("id", "")))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	box.add_child(top)
	var persona_portrait := _icon_view(str(persona.get("asset_id", customer.get("asset_id", "ic_contract"))), Vector2(92, 92))
	persona_portrait.name = "InquiryPersonaPortrait"
	top.add_child(persona_portrait)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	top.add_child(copy)
	var title := _label(tr(str(persona.get("name_key", template.get("name_key", "INQUIRY_BOARD")))), ThemeMaker.TYPE_SCALE.heading, ThemeMaker.COLORS.cream)
	title.name = "InquiryTitle"
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ThemeMaker.apply_text_role(title, "title")
	copy.add_child(title)
	var offer_name := _label(tr(str(template.get("name_key", "INQUIRY_BOARD"))), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.yellow)
	offer_name.name = "InquiryOfferName"
	offer_name.max_lines_visible = 1
	offer_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(offer_name)
	var description := _label(tr(str(template.get("description_key", ""))), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
	description.max_lines_visible = 1
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(description)
	var best_quote := _best_inquiry_offer(str(inquiry.get("id", "")))
	var requirement := _label(_inquiry_requirement_text(template, best_quote.get("evaluation", {})), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.green if bool(best_quote.get("eligible", false)) else ThemeMaker.COLORS.orange)
	requirement.name = "InquiryRequirement"
	requirement.max_lines_visible = 1
	requirement.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(requirement)
	var duration := DataRepository.get_table("meta_progression").get("contract_durations", {}).get(str(template.get("duration_id", "standard")), {}) as Dictionary
	var bonus_text := "$%s" % Game.format_number(float(best_quote.get("bonus", 0.0))) if bool(best_quote.get("eligible", false)) else "—"
	var terms := _label(tr("INQUIRY_TERMS") % [tr(str(duration.get("name_key", "CONTRACT_DURATION_STANDARD"))), int(round((float(template.get("premium", 1.0)) - 1.0) * 100.0)), bonus_text], ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.yellow)
	terms.name = "InquiryTerms"
	terms.max_lines_visible = 1
	terms.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(terms)
	var inquiry_line_key := PersonaSystemScene.line_key(persona, "inquiry", str(inquiry.get("id", "")))
	if not inquiry_line_key.is_empty():
		var persona_line := _label('"%s"' % tr(inquiry_line_key), ThemeMaker.TYPE_SCALE.caption, Color("d9e7f2"))
		persona_line.name = "InquiryPersonaLine"
		persona_line.max_lines_visible = 1
		persona_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(persona_line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	box.add_child(actions)
	var review := Widgets.button(tr("INQUIRY_VIEW_DATACENTERS"), _show_inquiry_datacenter_picker.bind(str(inquiry.get("id", ""))), "secondary")
	review.name = "InquiryReview_%s" % str(inquiry.get("id", ""))
	review.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review.mouse_filter = Control.MOUSE_FILTER_PASS
	review.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	actions.add_child(review)
	var decline := Widgets.button(tr("INQUIRY_DECLINE"), _decline_inquiry.bind(str(inquiry.get("id", ""))), "ghost")
	decline.name = "InquiryDecline_%s" % str(inquiry.get("id", ""))
	decline.custom_minimum_size.x = 184
	decline.mouse_filter = Control.MOUSE_FILTER_PASS
	decline.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	actions.add_child(decline)
	return card

func _best_inquiry_offer(inquiry_id: String) -> Dictionary:
	var best: Dictionary = {}
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or str((dc as Dictionary).get("status", "")) != "operational":
			continue
		var quote := Game.inquiry_offer(inquiry_id, str((dc as Dictionary).get("id", "")))
		if bool(quote.get("eligible", false)) and (best.is_empty() or float(quote.get("projected", 0.0)) > float(best.get("projected", 0.0))):
			best = quote
		elif best.is_empty():
			best = quote
	return best

func _inquiry_requirement_text(template: Dictionary, evaluation: Dictionary) -> String:
	var requirements: Dictionary = template.get("requirements", {})
	var current := 0
	var target := 0
	for check: Dictionary in evaluation.get("checks", []):
		if str(check.get("kind", "")) == "operational":
			continue
		current = int(check.get("current", 0))
		target = int(check.get("target", 0))
		break
	if requirements.has("rack_kind"):
		var kind := str(requirements.get("rack_kind", "compute"))
		var kind_key: String = {"compute": "RACK_KIND_COMPUTE", "storage": "RACK_KIND_STORAGE", "gpu": "RACK_KIND_GPU"}.get(kind, "RACK_KIND_COMPUTE")
		return tr("INQUIRY_REQUIREMENT_RACK") % [tr(kind_key), current, int(requirements.get("rack_count", 0))]
	if requirements.has("unique_rack_kinds"):
		return tr("INQUIRY_REQUIREMENT_UNIQUE") % [current, int(requirements.get("unique_rack_kinds", 0))]
	if requirements.has("network_level"):
		return tr("INQUIRY_REQUIREMENT_NETWORK") % [current, int(requirements.get("network_level", 1))]
	if requirements.has("relationship_level"):
		return tr("INQUIRY_REQUIREMENT_RELATIONSHIP") % [current, int(requirements.get("relationship_level", 0))]
	if requirements.has("specialization"):
		var specialization_id := str(requirements.get("specialization", ""))
		var specialization := DataRepository.get_table("meta_progression").get("campus_specializations", {}).get(specialization_id, {}) as Dictionary
		return tr("INQUIRY_REQUIREMENT_SPECIALIZATION") % [tr(str(specialization.get("name_key", "CAMPUS_STRATEGY_UNSET"))), tr("INQUIRY_REQUIREMENT_READY") if current >= 1 else tr("INQUIRY_REQUIREMENT_PENDING")]
	return tr("INQUIRY_REQUIREMENT_READY")

func _show_inquiry_datacenter_picker(inquiry_id: String) -> void:
	var choices: Array[Dictionary] = []
	var quotes := {}
	var inquiry: Dictionary = {}
	for item: Dictionary in Game.state.get("inquiries", {}).get("open", []):
		if str(item.get("id", "")) == inquiry_id:
			inquiry = item
			break
	var persona := PersonaSystemScene.persona_for_inquiry(inquiry, DataRepository.tables)
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if not dc is Dictionary or str((dc as Dictionary).get("status", "")) != "operational":
			continue
		var dc_id := str((dc as Dictionary).get("id", ""))
		var building := DataRepository.get_entry("buildings", str((dc as Dictionary).get("building_id", "")))
		var quote := Game.inquiry_offer(inquiry_id, dc_id)
		quotes[dc_id] = quote
		var label := tr("INQUIRY_DC_READY") % [tr(str(building.get("name_key", "DC_DETAIL"))), Game.format_number(float(quote.get("projected", 0.0))), Game.format_number(float(quote.get("bonus", 0.0)))] if bool(quote.get("eligible", false)) else tr("INQUIRY_DC_BLOCKED") % [tr(str(building.get("name_key", "DC_DETAIL"))), _inquiry_requirement_text(DataRepository.get_table("inquiries").get("items", {}).get(str(quote.get("template_id", "")), {}), quote.get("evaluation", {}))]
		choices.append({"id": dc_id, "text": label, "asset": str(building.get("asset_prefix", "dc_t0")) + "_active", "available": bool(quote.get("eligible", false)), "color": ThemeMaker.COLORS.green if bool(quote.get("eligible", false)) else Color("40516a")})
	if choices.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_unavailable"})
		return
	_present_action_sheet(tr("INQUIRY_ACCEPT_TITLE"), tr("INQUIRY_BOARD_HINT"), choices, func(datacenter_id: String) -> void:
		var quote: Dictionary = quotes.get(datacenter_id, {})
		if not bool(quote.get("eligible", false)):
			_handle_result({"ok": false, "reason": "inquiry_requirements"})
			return
		var result := Game.accept_inquiry(inquiry_id, datacenter_id, quote)
		if bool(result.get("ok", false)):
			var line_key := PersonaSystemScene.line_key(persona, "accept", inquiry_id)
			_show_persona_toast(persona, tr(line_key) if not line_key.is_empty() else tr("INQUIRY_ACCEPTED") % Game.format_number(float(result.get("bonus", 0.0))), "sfx_success_chime")
		else:
			_handle_result(result)
	)

func _decline_inquiry(inquiry_id: String) -> void:
	var inquiry: Dictionary = {}
	for item: Dictionary in Game.state.get("inquiries", {}).get("open", []):
		if str(item.get("id", "")) == inquiry_id:
			inquiry = item
			break
	var persona := PersonaSystemScene.persona_for_inquiry(inquiry, DataRepository.tables)
	var result := Game.decline_inquiry(inquiry_id)
	if bool(result.get("ok", false)):
		var line_key := PersonaSystemScene.line_key(persona, "decline", inquiry_id)
		_show_persona_toast(persona, tr(line_key) if not line_key.is_empty() else tr("INQUIRY_DECLINED"))
	else:
		_handle_result(result)

func _build_market_review_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(_section_title(tr("MARKET_REVIEW"), tr("MARKET_REVIEW_SUBTITLE")))
	var decisions: Array = Game.state.get("meta", {}).get("market_decisions", [])
	if decisions.is_empty():
		section.add_child(_status_card("market_review", tr("MARKET_REVIEW_EMPTY"), ThemeMaker.COLORS.cyan, true))
		return section
	for index: int in range(mini(5, decisions.size())):
		var decision: Dictionary = decisions[index]
		var customer := DataRepository.get_entry("customers", str(decision.get("customer_id", "")))
		var row := Widgets.flat_card()
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		row.add_child(box)
		box.add_child(_icon_view(str(customer.get("asset_id", "customer_portfolio")), Vector2(58, 58)))
		var copy := _label(tr("MARKET_REVIEW_ROW") % [tr(str(customer.get("name_key", ""))), float(decision.get("locked_market_multiplier", 1.0)), float(decision.get("latest_market_multiplier", decision.get("locked_market_multiplier", 1.0))), Game.format_number(float(decision.get("signed_monthly", 0.0)))], ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.cream)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(copy)
		section.add_child(row)
	return section

func _market_legend_button(chart: MarketChart, customer_id: String, customer: Dictionary) -> Button:
	var color: Color = ChartScene.CUSTOMER_COLORS.get(customer_id, ThemeMaker.COLORS.sky)
	var control := Widgets.button(tr(customer.get("name_key", "")), Callable(), "secondary")
	control.name = "Legend_%s" % customer_id
	control.custom_minimum_size.y = 88
	control.set_meta("legend_color", color)
	# Series identity comes from a color dot + border on a dark chip; saturated
	# chip fills swallow the label text.
	var dot := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	dot.fill(color)
	control.icon = ImageTexture.create_from_image(dot)
	control.add_theme_constant_override("h_separation", 10)
	var normal := ThemeMaker.panel(Color(0, 0, 0, 0.30), Color(color, 0.62), 1, 18)
	var hover := ThemeMaker.panel(Color(color, 0.18), Color(color, 0.80), 1, 18)
	var pressed := ThemeMaker.panel(Color(0, 0, 0, 0.42), Color(color, 0.62), 1, 18)
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("hover", hover)
	control.add_theme_stylebox_override("pressed", pressed)
	control.pressed.connect(func() -> void:
		chart.toggle_series(customer_id)
		var visible := bool(chart.visible_series.get(customer_id, true))
		control.modulate = Color.WHITE if visible else Color(1, 1, 1, 0.38)
	)
	return control

func _build_tech_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_TECH"), tr("COMPANY_OVERVIEW"), "ic_tech"))
	box.add_child(_segmented_control([
		{"id": "roadmap", "label": tr("META_TAB_ROADMAP"), "asset": "company_roadmap"},
		{"id": "upgrades", "label": tr("UPGRADE"), "asset": "ic_tech"},
		{"id": "collection", "label": tr("META_TAB_COLLECTION"), "asset": "company_collection"},
		{"id": "board", "label": tr("META_TAB_BOARD"), "asset": "board_specialties"},
	], _tech_section, _set_tech_section))
	if _tech_section == "roadmap":
		box.add_child(_build_roadmap_section())
		return _wrap_scroll(box)
	if _tech_section in ["collection", "achievements"]:
		box.add_child(_build_collection_section())
		return _wrap_scroll(box)
	if _tech_section == "board":
		box.add_child(_build_board_section())
		return _wrap_scroll(box)
	var player: Dictionary = Game.state.get("player", {})
	var era_id := int(player.get("era", 1))
	var era := DataRepository.get_entry("eras", str(era_id))
	var next_era := DataRepository.get_entry("eras", str(era_id + 1))
	box.add_child(_build_era_route_card(era_id, era, next_era, player))
	var network_level := int(player.get("network_level", 1))
	var network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_level), {})
	var network_card := _card()
	var network_box := VBoxContainer.new()
	network_box.add_theme_constant_override("separation", 10)
	network_card.add_child(network_box)
	network_box.add_child(_feature_heading("ic_network", "%s · %s" % [tr("NETWORK"), tr(network.get("name_key", ""))], "×%.2f" % float(network.get("income_multiplier", 1.0)), ThemeMaker.COLORS.cyan))
	var next_network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_level + 1), {})
	if not next_network.is_empty():
		var network_cost := float(next_network.get("cost", 0.0))
		var network_button := _button("%s %s · $%s" % [tr("UPGRADE"), tr(next_network.get("name_key", "")), Game.format_number(network_cost)], _upgrade_network.bind(int(next_network.get("unlock_era", era_id))), ThemeMaker.COLORS.sky)
		if not Game.is_unlocked(next_network):
			_mark_explained_unavailable(network_button, "locked", {"unlock_era": int(next_network.get("unlock_era", era_id))})
		Widgets.affordable_style(network_button, network_cost)
		network_box.add_child(network_button)
	box.add_child(network_card)
	var repair_level := int(Game.state.get("technology", {}).get("repair_team", 1))
	var repair_card := _card()
	var repair_box := VBoxContainer.new()
	repair_box.add_theme_constant_override("separation", 10)
	repair_card.add_child(repair_box)
	repair_box.add_child(_feature_heading("ic_wrench", "%s T%d" % [tr("TECH_REPAIR_TEAM"), repair_level], tr("TECH_REPAIR_TEAM_DESC"), ThemeMaker.COLORS.green))
	var next_repair: Dictionary = DataRepository.get_table("technology").get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(str(repair_level + 1), {})
	if not next_repair.is_empty():
		var repair_cost := float(next_repair.get("cost", 0.0))
		var repair_unlock_era := int(next_repair.get("unlock_era", era_id))
		var repair_button := _button("%s · $%s" % [tr("UPGRADE"), Game.format_number(repair_cost)], _upgrade_repair.bind(repair_unlock_era), ThemeMaker.COLORS.green)
		if not Game.is_unlocked(next_repair):
			_mark_explained_unavailable(repair_button, "locked", {"unlock_era": repair_unlock_era})
		Widgets.affordable_style(repair_button, repair_cost)
		repair_box.add_child(repair_button)
	box.add_child(repair_card)
	var bays_config: Dictionary = DataRepository.get_table("technology").get("upgrades", {}).get("construction_bays", {})
	var bays_level := int(Game.state.get("technology", {}).get("construction_bays", 1))
	var bays_card := _card()
	bays_card.name = "ConstructionBaysCard"
	var bays_box := VBoxContainer.new()
	bays_box.add_theme_constant_override("separation", 10)
	bays_card.add_child(bays_box)
	bays_box.add_child(_feature_heading("ic_build", tr(bays_config.get("name_key", "TECH_CONSTRUCTION_BAYS")), tr("TECH_CONSTRUCTION_BAYS_STATUS") % Game.queue_capacity(), ThemeMaker.COLORS.orange))
	var next_bays: Dictionary = bays_config.get("levels", {}).get(str(bays_level + 1), {})
	if next_bays.is_empty():
		bays_box.add_child(_label(tr("STORE_OWNED"), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.green))
	else:
		var bays_cost := float(next_bays.get("cost", 0.0))
		var bays_unlock_era := int(next_bays.get("unlock_era", era_id))
		var bays_minimum_prestige := int(next_bays.get("minimum_prestige", 0))
		var bays_button := _button("%s · $%s · %s" % [tr("UPGRADE"), Game.format_number(bays_cost), tr("TECH_CONSTRUCTION_BAYS_STATUS") % int(next_bays.get("queue_capacity", Game.queue_capacity()))], _purchase_construction_bays.bind(bays_unlock_era, bays_minimum_prestige), ThemeMaker.COLORS.orange)
		if not Game.is_unlocked(next_bays):
			_mark_explained_unavailable(bays_button, "locked", {"unlock_era": bays_unlock_era, "minimum_prestige": bays_minimum_prestige})
		Widgets.affordable_style(bays_button, bays_cost)
		bays_box.add_child(bays_button)
	box.add_child(bays_card)
	var auto_config: Dictionary = DataRepository.get_table("technology").get("upgrades", {}).get("auto_retirement", {})
	var auto_level: Dictionary = auto_config.get("levels", {}).get("1", {})
	var auto_owned := bool(Game.state.get("technology", {}).get("auto_retirement", false))
	var auto_card := _card()
	var auto_box := VBoxContainer.new()
	auto_box.add_theme_constant_override("separation", 10)
	auto_card.add_child(auto_box)
	auto_box.add_child(_feature_heading("ic_retire", tr(auto_config.get("name_key", "TECH_AUTO_RETIREMENT")), tr(auto_config.get("description_key", "TECH_AUTO_RETIREMENT_DESC")), ThemeMaker.COLORS.yellow))
	if auto_owned:
		auto_box.add_child(_label(tr("STORE_OWNED"), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.green))
	else:
		var auto_cost := float(auto_level.get("cost", 15000.0))
		var auto_unlock_era := int(auto_level.get("unlock_era", era_id))
		var auto_button := _button("%s · $%s" % [tr("BUY"), Game.format_number(auto_cost)], _purchase_auto_retirement.bind(auto_unlock_era), ThemeMaker.COLORS.green)
		if not Game.is_unlocked(auto_level):
			_mark_explained_unavailable(auto_button, "locked", {"unlock_era": auto_unlock_era})
		Widgets.affordable_style(auto_button, auto_cost)
		auto_box.add_child(auto_button)
	box.add_child(auto_card)
	box.add_child(_build_prestige_card(player))
	return _wrap_scroll(box)

func _meta_hero(asset_id: String, title_text: String, body_text: String) -> Control:
	var card := Widgets.flat_card(Color(ThemeMaker.COLORS.sky, 0.32))
	card.name = "MetaHero_%s" % asset_id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeMaker.GROUP_PADDING)
	card.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(188, 188)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	row.add_child(copy)
	var title := _label(title_text, ThemeMaker.TYPE_SCALE.heading, ThemeMaker.COLORS.cream)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title)
	var body := _label(body_text, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(body)
	return card

func _build_roadmap_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	section.add_child(_meta_hero("company_roadmap", tr("COMPANY_ROADMAP"), tr("COMPANY_ROADMAP_SUBTITLE")))
	for item_id: String in DataRepository.get_table("meta_progression").get("roadmap", {}).get("items", {}):
		var item: Dictionary = DataRepository.get_table("meta_progression")["roadmap"]["items"][item_id]
		var current := Game.call("_meta_metric", str(item.get("metric", ""))) as float
		var target := float(item.get("target", 1.0))
		var claimed := bool(Game.state.get("meta", {}).get("roadmap_claimed", {}).get(item_id, false))
		var card := Widgets.flat_card(ThemeMaker.COLORS.green if claimed else Color(ThemeMaker.COLORS.sky, 0.34))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		card.add_child(box)
		box.add_child(_feature_heading(str(item.get("asset_id", "company_roadmap")), tr(str(item.get("name_key", ""))), tr(str(item.get("description_key", ""))), ThemeMaker.COLORS.green if claimed else ThemeMaker.COLORS.cyan))
		var progress := ProgressBar.new()
		progress.max_value = target
		progress.value = minf(current, target)
		progress.show_percentage = false
		progress.custom_minimum_size.y = 26
		box.add_child(progress)
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		box.add_child(footer)
		var progress_label := _label(tr("ROADMAP_PROGRESS") % [int(minf(current, target)), int(target)], ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
		progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(progress_label)
		if claimed:
			footer.add_child(Widgets.chip(tr("ROADMAP_CLAIMED"), ThemeMaker.COLORS.green))
		elif current >= target:
			var claim := _button(tr("ROADMAP_CLAIM") % int(item.get("reward_gems", 0)), _claim_roadmap.bind(item_id), ThemeMaker.COLORS.green)
			claim.custom_minimum_size = Vector2(250, 88)
			footer.add_child(claim)
		section.add_child(card)
	return section

func _claim_roadmap(item_id: String) -> void:
	_handle_result(Game.claim_roadmap_reward(item_id))
	_request_full_refresh()

func _build_collection_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	section.add_child(_meta_hero("company_collection", tr("COMPANY_COLLECTION"), tr("COMPANY_COLLECTION_SUBTITLE")))
	var groups: Dictionary = DataRepository.get_table("meta_progression").get("collection", {}).get("groups", {})
	for group_id: String in groups:
		section.add_child(_collection_group_card(group_id, groups[group_id]))
	section.add_child(_build_achievements_section())
	return section

func _collection_group_card(group_id: String, group: Dictionary) -> Control:
	var status := Game.collection_group_status(group_id)
	var card := Widgets.flat_card(ThemeMaker.COLORS.green if bool(status.get("complete", false)) else Color(ThemeMaker.COLORS.sky, 0.28))
	card.name = "Collection_%s" % group_id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	card.add_child(box)
	box.add_child(_section_title(tr(str(group.get("name_key", ""))), tr("COLLECTION_PROGRESS") % [int(status.get("discovered", 0)), int(status.get("total", 0))]))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for source_variant: Variant in group.get("sources", []):
		var source := str(source_variant)
		for item_id: String in DataRepository.get_table(source).get("items", {}):
			var item := DataRepository.get_entry(source, item_id)
			var discovered := Game.call("_collection_item_discovered", source, item_id) as bool
			var asset_id := str(item.get("asset_id", item.get("asset_prefix", "")))
			if item.has("asset_prefix"):
				asset_id += "_active"
			grid.add_child(_collection_tile(asset_id, tr(str(item.get("name_key", ""))), discovered))
	for legacy_variant: Variant in group.get("items", []):
		if legacy_variant is Dictionary:
			var legacy: Dictionary = legacy_variant
			var source := str(legacy.get("source", ""))
			var discovered := Game.call("_collection_item_discovered", source, str(legacy.get("id", ""))) as bool if not source.is_empty() else Game.call("_legacy_collection_item_discovered", str(legacy.get("id", ""))) as bool
			grid.add_child(_collection_tile(str(legacy.get("asset_id", "legacy_memorial")), tr(str(legacy.get("name_key", ""))), discovered))
	if bool(status.get("complete", false)) and not bool(status.get("claimed", false)):
		box.add_child(_button(tr("COLLECTION_CLAIM") % int(status.get("reward_gems", 0)), _claim_collection.bind(group_id), ThemeMaker.COLORS.green))
	elif bool(status.get("claimed", false)):
		box.add_child(_status_card("ic_check", tr("COLLECTION_COMPLETE"), ThemeMaker.COLORS.green, true))
	return card

func _collection_tile(asset_id: String, title_text: String, discovered: bool) -> Control:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(0, 126)
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := _icon_view(asset_id, Vector2(70, 70))
	icon.modulate = Color.WHITE if discovered else Color(0.28, 0.33, 0.40, 0.78)
	tile.add_child(icon)
	var label := _label(title_text if discovered else "?", 16, ThemeMaker.COLORS.cream if discovered else Color("8090a0"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.max_lines_visible = 1
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(label)
	return tile

func _claim_collection(group_id: String) -> void:
	_handle_result(Game.claim_collection_reward(group_id))
	_request_full_refresh()

func _build_board_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	section.add_child(_meta_hero("board_specialties", tr("BOARD_SPECIALTIES"), tr("BOARD_SPECIALTIES_SUBTITLE")))
	section.add_child(_status_card("ic_prestige", tr("BOARD_POINTS_AVAILABLE") % Game.board_points_available(), ThemeMaker.COLORS.purple, true))
	var config: Dictionary = DataRepository.get_table("meta_progression").get("board_specialties", {})
	var max_rank := int(config.get("max_rank", 5))
	for specialty_id: String in config.get("items", {}):
		var item: Dictionary = config["items"][specialty_id]
		var rank := int(Game.state.get("meta", {}).get("board_allocations", {}).get(specialty_id, 0))
		var card := Widgets.flat_card(Color(ThemeMaker.COLORS.purple, 0.32))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		card.add_child(box)
		box.add_child(_feature_heading(str(item.get("asset_id", "board_specialties")), tr(str(item.get("name_key", ""))), tr(str(item.get("description_key", ""))), ThemeMaker.COLORS.purple.lightened(0.18)))
		box.add_child(_label(tr("BOARD_RANK") % [rank, max_rank], ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.cyan))
		var invest := _button(tr("BOARD_ADD_POINT"), _allocate_board_point.bind(specialty_id), ThemeMaker.COLORS.purple)
		invest.custom_minimum_size.y = 88
		box.add_child(invest)
		section.add_child(card)
	if int(Game.state.get("stats", {}).get("prestige_count", 0)) > 0:
		section.add_child(_button(tr("BOARD_RESET"), _reset_board_points, Color("29445c")))
	section.add_child(_build_company_history())
	return section

func _allocate_board_point(specialty_id: String) -> void:
	_handle_result(Game.allocate_board_point(specialty_id))
	_request_full_refresh()

func _reset_board_points() -> void:
	_handle_result(Game.reset_board_points())
	_request_full_refresh()

func _build_company_history() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(_section_title(tr("COMPANY_HISTORY"), ""))
	var history: Array = Game.state.get("meta", {}).get("company_history", [])
	if history.is_empty():
		section.add_child(_status_card("legacy_memorial", tr("COMPANY_HISTORY_EMPTY"), ThemeMaker.COLORS.cyan, true))
		return section
	for summary: Dictionary in history:
		section.add_child(_status_card("legacy_memorial", tr("COMPANY_HISTORY_ROW") % [int(summary.get("prestige_number", 1)), Game.format_number(float(summary.get("total_revenue", 0.0))), int(summary.get("datacenters_built", 0))], ThemeMaker.COLORS.yellow, true))
	return section

func _build_era_route_card(era_id: int, era: Dictionary, next_era: Dictionary, player: Dictionary) -> Control:
	var card := _card()
	card.name = "EraRouteCard"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	box.add_child(_section_title(tr("ERA_PROGRESS"), tr(era.get("name_key", ""))))
	var route := HBoxContainer.new()
	route.alignment = BoxContainer.ALIGNMENT_CENTER
	route.add_theme_constant_override("separation", 4)
	box.add_child(route)
	for node_era: int in range(1, 4):
		if node_era > 1:
			var connector := _label(">", 34, ThemeMaker.COLORS.yellow if node_era <= era_id + 1 else Color("718096"))
			connector.custom_minimum_size.x = 18
			connector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			route.add_child(connector)
		var node := PanelContainer.new()
		node.name = "EraNode_%d" % node_era
		node.custom_minimum_size = Vector2(138, 178)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE.lightened(0.08) if node_era == era_id else ThemeMaker.SURFACE, ThemeMaker.COLORS.yellow if node_era == era_id else Color(1, 1, 1, 0.12), 3 if node_era == era_id else 1, 20))
		route.add_child(node)
		var node_box := VBoxContainer.new()
		node_box.alignment = BoxContainer.ALIGNMENT_CENTER
		node.add_child(node_box)
		node_box.add_child(_icon_view("ic_era%d" % node_era, Vector2(86, 86)))
		var node_data := DataRepository.get_entry("eras", str(node_era))
		var node_label := _label(tr(node_data.get("name_key", "")), 18, ThemeMaker.COLORS.yellow if node_era == era_id else ThemeMaker.COLORS.cream)
		node_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node_label.max_lines_visible = 2
		node_box.add_child(node_label)
		var state_label := _label(tr("ERA_DONE") if node_era < era_id else (tr("ERA_CURRENT") if node_era == era_id else tr("ERA_LOCKED")), 18, ThemeMaker.COLORS.green if node_era <= era_id else Color("8a97a8"))
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node_box.add_child(state_label)
	if next_era.is_empty():
		box.add_child(_label(tr("ERA_ROUTE_COMPLETE"), 22, ThemeMaker.COLORS.green))
		return card
	var required := float(next_era.get("revenue_required", 1.0))
	var progress := ProgressBar.new()
	progress.name = "EraProgressBar"
	progress.max_value = required
	progress.value = float(player.get("total_revenue", 0.0))
	progress.show_percentage = false
	progress.custom_minimum_size.y = 38
	box.add_child(progress)
	box.add_child(_label("$%s / $%s → %s" % [Game.format_number(float(player.get("total_revenue", 0.0))), Game.format_number(required), tr(next_era.get("name_key", ""))], 22, ThemeMaker.COLORS.cyan))
	var unlocks := _era_unlock_items(era_id + 1)
	box.add_child(_label(tr("ERA_NEXT_UNLOCKS") % tr(next_era.get("name_key", "")), 24, ThemeMaker.COLORS.yellow))
	var unlock_row := HBoxContainer.new()
	unlock_row.name = "EraUnlockPreview"
	unlock_row.add_theme_constant_override("separation", 8)
	box.add_child(unlock_row)
	for index: int in range(mini(4, unlocks.size())):
		var item: Dictionary = unlocks[index]
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(0, 108)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE_GROUP, Color.TRANSPARENT, 0, 16))
		var chip_box := VBoxContainer.new()
		chip_box.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(chip_box)
		chip_box.add_child(_icon_view(str(item.get("asset_id", "")), Vector2(58, 58)))
		var item_label := _label(tr(item.get("name_key", "")), 17, ThemeMaker.COLORS.cream)
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chip_box.add_child(item_label)
		unlock_row.add_child(chip)
	if unlocks.size() > 4:
		box.add_child(_label(tr("ERA_MORE_ITEMS") % (unlocks.size() - 4), 19, ThemeMaker.COLORS.cyan))
	return card

func _era_unlock_items(era_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for table_name: String in ["buildings", "racks", "customers", "attachments"]:
		for item_id: String in DataRepository.get_table(table_name).get("items", {}):
			var item := DataRepository.get_entry(table_name, item_id)
			if int(item.get("unlock_era", 1)) != era_id:
				continue
			var asset_id := str(item.get("asset_id", item.get("asset_prefix", "")))
			if item.has("asset_prefix"):
				asset_id += "_active"
			result.append({"name_key": str(item.get("name_key", "")), "asset_id": asset_id})
	return result

func _prestige_projection() -> Dictionary:
	var config: Dictionary = DataRepository.get_table("economy").get("prestige", {})
	var worth := Game.net_worth()
	var raw_gain := 1.0 + float(config.get("log_coefficient", 0.15)) * log(maxf(1.0, worth / float(config.get("net_worth_anchor", 100000.0)))) / log(10.0)
	var gain := clampf(raw_gain, float(config.get("minimum_gain", 1.05)), float(config.get("maximum_gain", 1.6)))
	var current := float(Game.state.get("player", {}).get("brand_multiplier", 1.0))
	return {"worth": worth, "gain": gain, "current": current, "projected": current * gain}

func _build_prestige_card(player: Dictionary) -> Control:
	var config: Dictionary = DataRepository.get_table("economy").get("prestige", {})
	var minimum := int(config.get("minimum_datacenters", 20))
	var built := int(player.get("total_datacenters_built", 0))
	var unlocked := built >= minimum
	var projection := _prestige_projection()
	var card := _card()
	card.name = "PrestigeCard"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	box.add_child(_meta_hero("board_specialties", tr("BOARD_SPECIALTIES"), tr("BOARD_SPECIALTIES_SUBTITLE")))
	box.add_child(_feature_heading("ic_prestige", tr("PRESTIGE"), tr("PRESTIGE_EST_GAIN") % float(projection.get("projected", 1.0)) if unlocked else tr("PRESTIGE_LOCKED") % minimum, ThemeMaker.COLORS.purple))
	var progress := ProgressBar.new()
	progress.name = "PrestigeProgressBar"
	progress.max_value = minimum
	progress.value = mini(built, minimum)
	progress.show_percentage = false
	progress.custom_minimum_size.y = 36
	box.add_child(progress)
	box.add_child(_label(tr("PRESTIGE_PROGRESS") % [built, minimum], 21, ThemeMaker.COLORS.cyan))
	if unlocked:
		box.add_child(_label(tr("PRESTIGE_GAIN_DETAIL") % [float(projection.get("current", 1.0)), float(projection.get("projected", 1.0))], 25, ThemeMaker.COLORS.yellow))
		box.add_child(_label(tr("PRESTIGE_KEEP_LIST"), 20, ThemeMaker.COLORS.green))
		box.add_child(_label(tr("PRESTIGE_LIQUIDATE") % Game.format_number(float(projection.get("worth", 0.0))), 20, ThemeMaker.COLORS.orange))
	var action := _confirm_prestige if unlocked else _show_toast.bind(tr("PRESTIGE_LOCKED") % minimum)
	var button := _button(tr("PRESTIGE") if unlocked else tr("LOCKED"), action, ThemeMaker.COLORS.purple if unlocked else Color(ThemeMaker.SEMANTIC.get("locked", Color("8a97a8"))))
	_set_button_asset(button, "ic_prestige", 44)
	box.add_child(button)
	return card

func _set_tech_section(section: String) -> void:
	if _tech_section == section:
		return
	_tech_section = section
	_request_full_refresh()

func _build_achievements_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 14)
	section.add_child(_section_title(tr("ACHIEVEMENTS"), tr("ACHIEVEMENTS_SUBTITLE")))
	var achievements := GridContainer.new()
	achievements.columns = 2
	achievements.add_theme_constant_override("h_separation", 10)
	achievements.add_theme_constant_override("v_separation", 10)
	section.add_child(achievements)
	for achievement_id: String in DataRepository.get_table("achievements").get("items", {}):
		var achievement := DataRepository.get_entry("achievements", achievement_id)
		var done := bool(Game.state.get("achievements", {}).get(achievement_id, false))
		var metric := str(achievement.get("metric", ""))
		var current := float(Game.state.get("player", {}).get(metric, Game.state.get("stats", {}).get(metric, 0.0)))
		var target := maxf(1.0, float(achievement.get("target", 1.0)))
		current = target if done else minf(current, target)
		var achievement_card := PanelContainer.new()
		achievement_card.custom_minimum_size.y = 168
		achievement_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		achievement_card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(ThemeMaker.SURFACE, 0.97, 20, ThemeMaker.COLORS.green if done else Color("6b7e91")))
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 8)
		achievement_card.add_child(card_box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card_box.add_child(row)
		row.add_child(_icon_view("ic_check" if done else "ic_lock", Vector2(42, 42)))
		var achievement_label := _label(tr(achievement.get("name_key", "")), 20, ThemeMaker.COLORS.green if done else ThemeMaker.COLORS.cream)
		achievement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		achievement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		achievement_label.max_lines_visible = 1
		achievement_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(achievement_label)
		var progress := ProgressBar.new()
		progress.name = "AchievementProgress_%s" % achievement_id
		progress.show_percentage = false
		progress.custom_minimum_size.y = 20
		progress.max_value = target
		progress.value = current
		card_box.add_child(progress)
		var progress_row := HBoxContainer.new()
		card_box.add_child(progress_row)
		var progress_label := _label("%d / %d" % [int(current), int(target)], 18, ThemeMaker.COLORS.cyan)
		progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_row.add_child(progress_label)
		progress_row.add_child(_icon_view("ic_diamond", Vector2(24, 24)))
		progress_row.add_child(_label(str(int(achievement.get("reward_gems", 0))), 18, ThemeMaker.COLORS.purple.lightened(0.18)))
		achievements.add_child(achievement_card)
	return section

func _build_store_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_STORE"), tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0))), "ic_shop"))
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE_GROUP, Color.TRANSPARENT, 0, ThemeMaker.RADIUS.card))
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 18)
	wallet.add_child(wallet_row)
	wallet_row.add_child(_icon_view("ic_diamond", Vector2(92, 92)))
	var wallet_copy := VBoxContainer.new()
	wallet_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet_row.add_child(wallet_copy)
	var wallet_title := _label(tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0))), 34, ThemeMaker.COLORS.purple.lightened(0.18))
	ThemeMaker.apply_text_role(wallet_title, "title")
	wallet_copy.add_child(wallet_title)
	var wallet_hint := _label(tr("STORE_WALLET_HINT"), 22, ThemeMaker.COLORS.cyan)
	wallet_hint.max_lines_visible = 1
	wallet_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wallet_copy.add_child(wallet_hint)
	box.add_child(wallet)
	var sections := {
		"deals": [],
		"gems": [],
		"perks": [],
	}
	for product_id: String in DataRepository.get_table("store").get("items", {}):
		var product := DataRepository.get_entry("store", product_id)
		if int(product.get("unlock_era", 1)) > int(Game.state["player"].get("era", 1)) or int(product.get("unlock_prestige", 0)) > int(Game.state["stats"].get("prestige_count", 0)):
			continue
		var section_id := "deals" if str(product.get("type", "")) == "limited_consumable" else ("gems" if int(product.get("gems", 0)) > 0 else "perks")
		sections[section_id].append(product_id)
	for section_id: String in ["deals", "gems", "perks"]:
		var title_key: String = {"deals": "STORE_SECTION_DEALS", "gems": "STORE_SECTION_GEMS", "perks": "STORE_SECTION_PERKS"}[section_id]
		var section_space := Control.new()
		section_space.custom_minimum_size.y = 8
		section_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(section_space)
		var section_header := _section_title(tr(title_key), tr("STORE_SECTION_%s_HINT" % section_id.to_upper()))
		section_header.name = "StoreSection_%s" % section_id
		box.add_child(section_header)
		if sections[section_id].is_empty():
			var locked_offer := _status_card("ic_lock", tr("STORE_DEALS_LATER"), Color("8a97a8"), true)
			locked_offer.name = "StoreLockedOffer"
			box.add_child(locked_offer)
		else:
			for product_id: String in sections[section_id]:
				box.add_child(_store_product_card(product_id, DataRepository.get_entry("store", product_id)))
	var legal := VBoxContainer.new()
	legal.name = "StoreCompliance"
	legal.add_theme_constant_override("separation", 8)
	box.add_child(legal)
	legal.add_child(_button(tr("RESTORE_PURCHASES"), Callable(Monetization, "restore_purchases"), ThemeMaker.COLORS.navy))
	var legal_links := HBoxContainer.new()
	legal_links.add_theme_constant_override("separation", 8)
	legal.add_child(legal_links)
	legal_links.add_child(_button(tr("SETTINGS_PRIVACY"), _open_public_document.bind("privacy"), Color("263d59")))
	legal_links.add_child(_button(tr("SETTINGS_TERMS"), _open_public_document.bind("terms"), Color("263d59")))
	return _wrap_scroll(box)

func _store_product_card(product_id: String, product: Dictionary) -> Control:
	var card := _card()
	card.name = "StoreProduct_%s" % product_id
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	card.add_child(card_box)
	var product_row := HBoxContainer.new()
	product_row.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	card_box.add_child(product_row)
	var product_art := _asset_preview(str(product.get("asset_id", "")), tr(product.get("name_key", "")), ThemeMaker.COLORS.purple, 80)
	product_art.custom_minimum_size = Vector2(80, 80)
	product_art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	product_row.add_child(product_art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 6)
	product_row.add_child(copy)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	copy.add_child(title_row)
	var title := _label(tr(product.get("name_key", "")), ThemeMaker.TYPE_SCALE.heading, Color.WHITE)
	ThemeMaker.apply_text_role(title, "title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	if product_id == "gems_m":
		var ribbon := PanelContainer.new()
		ribbon.name = "BestValueRibbon"
		ribbon.size_flags_horizontal = Control.SIZE_SHRINK_END
		var ribbon_style := ThemeMaker.panel(Color("b87917"), Color.WHITE, 1, 13)
		ribbon_style.content_margin_left = 12
		ribbon_style.content_margin_right = 12
		ribbon_style.content_margin_top = 6
		ribbon_style.content_margin_bottom = 6
		ribbon.add_theme_stylebox_override("panel", ribbon_style)
		var ribbon_label := _label(tr("STORE_BEST_VALUE"), 18, Color.WHITE)
		ribbon_label.name = "BestValueLabel"
		ribbon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ribbon_label.max_lines_visible = 1
		ribbon_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		ribbon_label.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
		ribbon_label.add_theme_constant_override("outline_size", 3)
		ribbon.add_child(ribbon_label)
		# PanelContainer normally forwards this minimum, but making it explicit
		# protects the longer English badge when the title row negotiates width.
		ribbon.custom_minimum_size.x = maxf(128.0, ribbon_label.get_combined_minimum_size().x + 24.0)
		title_row.add_child(ribbon)
	var bonus := _store_bonus_percent(product_id)
	if bonus > 0:
		var bonus_label := _label(tr("STORE_BONUS_PCT") % bonus, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.yellow)
		bonus_label.max_lines_visible = 1
		title_row.add_child(bonus_label)
	if product.has("description_key"):
		var description := _label(tr(product.get("description_key", "")), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
		description.max_lines_visible = 1
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(description)
	if str(product.get("type", "")) == "limited_consumable":
		var contents := _label(tr("STORE_PACK_CONTENTS") % [int(product.get("gems", 0)), Game.format_number(float(product.get("cash", 0.0))), int(product.get("tickets", 0))], ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.yellow)
		contents.max_lines_visible = 1
		contents.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(contents)
	var gems := int(product.get("gems", 0))
	if gems > 0:
		var price_per_gem := float(product.get("price_usd", 0.0)) / float(gems)
		var value_text := "$%.4f / %s" % [price_per_gem, tr("GEMS_REWARD_SHORT")]
		copy.add_child(_label(value_text, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.green))
	var fallback_price := "US$ %.2f" % float(product.get("price_usd", 0.0))
	var buy_button := Widgets.button(Monetization.localized_price(product_id, fallback_price), _purchase.bind(product_id), "primary")
	buy_button.name = "StoreBuy_%s" % product_id
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var purchase_state := Game.can_purchase_product(product_id)
	var owned := not bool(purchase_state.get("ok", false)) and str(purchase_state.get("reason", "")) in ["already_owned", "purchase_limit"]
	if owned:
		card.modulate = Color(0.62, 0.66, 0.70, 0.90)
		buy_button.text = tr("STORE_OWNED")
		_set_button_asset(buy_button, "ic_check", 38)
		_mark_explained_unavailable(buy_button, str(purchase_state.get("reason", "already_owned")))
	elif OS.get_name() == "iOS" and not Monetization.is_product_available(product_id):
		buy_button.text = tr("STORE_UNAVAILABLE")
		_mark_explained_unavailable(buy_button, "product_unavailable")
	card_box.add_child(buy_button)
	return card

func _store_bonus_percent(product_id: String) -> int:
	return {"gems_s": 0, "gems_m": 10, "gems_l": 20}.get(product_id, 0)

func _build_settings_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_SETTINGS"), tr("APP_TITLE"), "ic_settings"))
	box.add_child(_section_title(tr("SETTINGS_LANGUAGE"), ""))
	var language_card := Widgets.flat_card(Color.TRANSPARENT, ThemeMaker.GROUP_PADDING)
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	language_card.add_child(languages)
	box.add_child(language_card)
	var current_locale := TranslationServer.get_locale()
	var english_active := current_locale.begins_with("en")
	var english_button := _settings_segment_button(tr("LANGUAGE_ENGLISH"), english_active, Game.set_locale.bind("en"))
	languages.add_child(english_button)
	var chinese_button := _settings_segment_button(tr("LANGUAGE_CHINESE"), not english_active, Game.set_locale.bind("zh_CN"))
	languages.add_child(chinese_button)
	var preferences_panel := Widgets.flat_card(Color.TRANSPARENT, 0)
	var preferences := VBoxContainer.new()
	preferences.add_theme_constant_override("separation", 0)
	preferences_panel.add_child(preferences)
	box.add_child(preferences_panel)
	var preference_index := 0
	var preference_items := [["music_enabled", "SETTINGS_MUSIC"], ["sfx_enabled", "SETTINGS_SFX"], ["haptics_enabled", "SETTINGS_HAPTICS"]]
	for setting: Array in preference_items:
		if preference_index > 0:
			preferences.add_child(_settings_divider())
		preferences.add_child(_settings_toggle_row(str(setting[0]), str(setting[1])))
		preference_index += 1
	var legal_title := _section_title(tr("SETTINGS_LEGAL"), tr("SETTINGS_LEGAL_HINT"))
	legal_title.name = "SettingsCompliance"
	box.add_child(legal_title)
	var legal_panel := Widgets.flat_card(Color.TRANSPARENT, 0)
	var legal_rows := VBoxContainer.new()
	legal_rows.add_theme_constant_override("separation", 0)
	legal_panel.add_child(legal_rows)
	var legal_actions: Array = [[tr("SETTINGS_PRIVACY"), "privacy"], [tr("SETTINGS_TERMS"), "terms"], ["%s · support@datacentertycoon.app" % tr("SETTINGS_SUPPORT"), "support"]]
	for index: int in range(legal_actions.size()):
		if index > 0:
			legal_rows.add_child(_settings_divider())
		legal_rows.add_child(_settings_row_button(str(legal_actions[index][0]), _open_public_document.bind(str(legal_actions[index][1]))))
	box.add_child(legal_panel)
	var version_card := Widgets.flat_card()
	version_card.name = "SettingsVersion"
	var version_label := _label(tr("SETTINGS_VERSION") % str(ProjectSettings.get_setting("application/config/version", "1.0.0")), ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_card.add_child(version_label)
	box.add_child(version_card)
	var destructive_gap := Control.new()
	destructive_gap.custom_minimum_size.y = 24
	box.add_child(destructive_gap)
	box.add_child(_button(tr("SETTINGS_RESET"), _confirm_reset, ThemeMaker.COLORS.red))
	return _wrap_scroll(box, true)

func _settings_segment_button(text: String, selected: bool, action: Callable) -> Button:
	var button := Widgets.button(text, action, "secondary")
	var normal := ThemeMaker.panel(Color("244968") if selected else Color.TRANSPARENT, Color(1, 1, 1, 0.08), 1, 16)
	var pressed := ThemeMaker.panel(Color("173650"), Color(1, 1, 1, 0.10), 1, 16)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	if selected:
		_set_button_asset(button, "ic_check", 32)
	return button

func _settings_divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.06)
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider

func _settings_row_button(text: String, action: Callable) -> Button:
	var button := Widgets.button(text, action, "secondary")
	button.custom_minimum_size.y = 88
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var normal := ThemeMaker.panel(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0)
	normal.content_margin_left = ThemeMaker.GROUP_PADDING
	normal.content_margin_right = 64
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.05)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var chevron := Label.new()
	chevron.name = "SettingsChevron"
	chevron.text = ">"
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	chevron.offset_left = -48
	chevron.offset_top = -24
	chevron.offset_right = -16
	chevron.offset_bottom = 24
	chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.add_theme_font_size_override("font_size", 20)
	chevron.add_theme_color_override("font_color", ThemeMaker.COLORS.cyan)
	button.add_child(chevron)
	return button

func _open_public_document(document_id: String) -> void:
	var resource_path := str(LEGAL_DOCUMENTS.get(document_id, ""))
	if resource_path.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	OS.shell_open("file://%s" % absolute_path.uri_encode())

func _build_tutorial_dormant_hint() -> void:
	tutorial_hint_button = Button.new()
	tutorial_hint_button.name = "TutorialDormantHint"
	tutorial_hint_button.visible = false
	tutorial_hint_button.z_index = 97
	tutorial_hint_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tutorial_hint_button.offset_left = -148
	tutorial_hint_button.offset_top = -184
	tutorial_hint_button.offset_right = -36
	tutorial_hint_button.offset_bottom = -72
	tutorial_hint_button.tooltip_text = tr("TUTORIAL_RETIRE_WAIT")
	tutorial_hint_button.pressed.connect(_expand_retire_dormant_notice)
	ThemeMaker.apply_world_hud_button(tutorial_hint_button)
	_wire_button_motion(tutorial_hint_button)
	_set_button_asset(tutorial_hint_button, "guide_worried", 72)
	var badge := PanelContainer.new()
	badge.name = "TutorialDormantBadge"
	badge.position = Vector2(76, -4)
	badge.size = Vector2(40, 40)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := ThemeMaker.panel(ThemeMaker.COLORS.red, Color.WHITE, 2, 20)
	badge_style.content_margin_left = 0
	badge_style.content_margin_right = 0
	badge_style.content_margin_top = 0
	badge_style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	tutorial_hint_button.add_child(badge)
	add_child(tutorial_hint_button)

func _refresh_tutorial() -> void:
	Game.reconcile_tutorial_progress()
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	if _last_tutorial_step >= 0 and index > _last_tutorial_step:
		if fx_layer != null:
			fx_layer.clear()
		AudioService.play_sfx("sfx_tap")
		_haptic(HAPTIC_LIGHT)
	_last_tutorial_step = index
	var completed := bool(tutorial.get("completed", false)) or index >= steps.size()
	if completed:
		tutorial_overlay.dismiss()
		tutorial_hint_button.visible = false
		if park_map != null:
			park_map.set_tutorial_sale_focus(true)
		_set_tutorial_chrome_visibility(true, "")
		_tutorial_visual_mode = "completed"
		return
	var step: Dictionary = steps[index]
	var step_id := str(step.get("id", ""))
	var focus := str(step.get("focus", ""))
	if park_map != null:
		park_map.set_tutorial_sale_focus(focus == "buy_plot")
	if step_id == "retire" and _retire_tutorial_is_ready():
		_retire_tutorial_awake = true
	if step_id != "retire":
		tutorial_hint_button.visible = false
	_apply_tutorial_context(index, step)
	var context := _effective_tutorial_context(step)
	var tutorial_drawer := find_child("DatacenterContext", true, false)
	if tutorial_drawer != null:
		tutorial_drawer.set_meta("tutorial_lock_close", context == "drawer")
	if step_id == "retire" and context == "dormant" and _retire_notice_collapsed:
		tutorial_overlay.set_meta("tutorial_step_id", step_id)
		tutorial_overlay.set_meta("tutorial_context", context)
		tutorial_overlay.set_meta("tutorial_mode", "dormant_hint")
		tutorial_overlay.set_meta("target_source", "none")
		tutorial_overlay.set_meta("resolved_target_rect", Rect2())
		tutorial_overlay.dismiss()
		tutorial_hint_button.visible = true
		_set_tutorial_chrome_visibility(false, focus)
		return
	var target := _resolve_tutorial_target(focus) if context != "dormant" else {"rect": Rect2(), "action": Callable(), "source": "none", "mode": "dormant"}
	var rect: Rect2 = target.get("rect", Rect2())
	var action: Callable = target.get("action", Callable())
	var copy := tr(step.get("message_key", ""))
	_tutorial_visual_mode = "rebuild" if str(target.get("source", "")) in ["rebuild", "rebuild_unavailable"] else str(target.get("mode", "dormant" if context == "dormant" else "actionable"))
	var copy_key := str(target.get("copy_key", ""))
	if not copy_key.is_empty():
		copy = tr(copy_key)
	elif _tutorial_visual_mode == "waiting":
		copy = tr("TUTORIAL_INSTALL_WAIT") % Game.format_duration(float(target.get("install_remaining", 0.0))) if str(target.get("source", "")) == "install_wait" else _tutorial_waiting_copy()
	elif step_id == "retire" and context == "dormant":
		copy = tr("TUTORIAL_RETIRE_WAIT")
	elif bool(target.get("world_stage", false)):
		copy = tr("TUTORIAL_OPEN_DC_PREFIX") % copy
	var guide_assets := ["guide_normal", "guide_thinking", "guide_happy", "guide_alert", "guide_worried", "guide_thinking", "guide_worried", "guide_happy"]
	tutorial_overlay.set_meta("tutorial_step_id", str(step.get("id", "")))
	tutorial_overlay.set_meta("tutorial_context", context)
	tutorial_overlay.set_meta("tutorial_mode", _tutorial_visual_mode)
	tutorial_overlay.set_meta("target_source", str(target.get("source", "none")))
	tutorial_overlay.set_meta("resolved_target_rect", rect)
	tutorial_overlay.set_meta("target_node", str(target.get("target_node", "")))
	# World sheets are created after the persistent tutorial overlay. Godot GUI
	# picking follows sibling order before visual z-index, so a later drawer could
	# swallow a tap inside the highlighted section even though the cyan guide was
	# visibly above it. Keep the coach last while it is actionable so the whole
	# spotlight aperture routes to the one authoritative tutorial action.
	move_child(tutorial_overlay, get_child_count() - 1)
	tutorial_overlay.present(rect, copy, guide_assets[mini(index, guide_assets.size() - 1)], action, target.get("foreground", Rect2()))
	tutorial_hint_button.visible = false
	_set_tutorial_chrome_visibility(false, focus)

func _sync_tutorial_target_geometry() -> void:
	if tutorial_overlay == null or not tutorial_overlay.visible:
		return
	if str(tutorial_overlay.get_meta("target_source", "")) != "control":
		return
	var target_name := str(tutorial_overlay.get_meta("target_node", ""))
	if target_name.is_empty():
		return
	var live := _visible_control_named(target_name)
	if live == null:
		return
	var live_rect := live.get_global_rect()
	var resolved: Rect2 = tutorial_overlay.get_meta("resolved_target_rect", Rect2())
	if resolved.position.distance_to(live_rect.position) < 0.5 and resolved.size.distance_to(live_rect.size) < 0.5:
		return
	tutorial_overlay.set_meta("resolved_target_rect", live_rect)
	tutorial_overlay.retarget(live_rect)

func _apply_tutorial_context(index: int, step: Dictionary) -> void:
	var step_changed := _tutorial_protocol_step != index
	if step_changed:
		_tutorial_protocol_step = index
		_tutorial_world_focus_id = ""
		if fx_layer != null:
			fx_layer.clear()
	var context := _effective_tutorial_context(step)
	var focus := str(step.get("focus", ""))
	_close_incompatible_tutorial_surfaces(context, focus)
	match context:
		"map", "dormant":
			if active_page != "map":
				_navigate("map")
		"drawer":
			var dc_id := _tutorial_datacenter_id()
			var drawer := find_child("DatacenterContext", true, false) as CanvasItem
			if drawer != null and str(drawer.get_meta("datacenter_id", "")) != dc_id:
				drawer.visible = false
				drawer.queue_free()
			if active_page == "detail" and selected_datacenter_id != dc_id:
				_navigate("map")
			elif active_page not in ["map", "detail"]:
				_navigate("map")
	if step_changed and str(step.get("id", "")) == "retire" and context == "dormant":
		_schedule_retire_notice_collapse()

func _effective_tutorial_context(step: Dictionary) -> String:
	if str(step.get("id", "")) == "retire" and _retire_tutorial_awake:
		return "drawer"
	return str(step.get("context", "map"))

func _retire_tutorial_is_ready() -> bool:
	var dc_id := _tutorial_datacenter_id()
	var dc := Game.find_datacenter(dc_id)
	if dc.is_empty():
		return false
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	var threshold := float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6))
	return progress >= threshold

func _schedule_retire_notice_collapse() -> void:
	_retire_notice_collapsed = false
	_retire_notice_token += 1
	get_tree().create_timer(3.0).timeout.connect(_collapse_retire_notice.bind(_retire_notice_token))

func _collapse_retire_notice(token: int) -> void:
	if token != _retire_notice_token or _retire_tutorial_awake:
		return
	_retire_notice_collapsed = true
	_request_hud_refresh()

func _expand_retire_dormant_notice() -> void:
	_retire_notice_collapsed = false
	_retire_notice_token += 1
	get_tree().create_timer(3.0).timeout.connect(_collapse_retire_notice.bind(_retire_notice_token))
	_refresh_tutorial()

func _close_incompatible_tutorial_surfaces(context: String, focus: String) -> void:
	var allowed: Array[String] = []
	if context == "drawer":
		allowed = ["ActionSheetOverlay", "DatacenterContext"]
	elif context == "map":
		if focus in ["build_dc_t0", "build_dc_t1"]:
			allowed = ["BuildingPicker"]
		elif focus == "buy_plot":
			allowed = ["ActionSheetOverlay"]
	for surface_name: String in ["ActionSheetOverlay", "BuildingPicker", "OperationsHub", "DatacenterContext"]:
		for surface: Node in find_children(surface_name, "", true, false):
			var allowed_surface := surface_name in allowed
			if allowed_surface and surface_name == "ActionSheetOverlay":
				allowed_surface = str(surface.get_meta("tutorial_focus", "")) == focus
			if allowed_surface:
				continue
			if surface is CanvasItem:
				(surface as CanvasItem).visible = false
			surface.queue_free()

func _tutorial_datacenter_id() -> String:
	# Tutorial actions belong to the starter container even if a notification or
	# a restored drawer left another data center selected in a larger park.
	for plot: Dictionary in Game.state.get("plots", []):
		var tutorial_value: Variant = plot.get("datacenter")
		if tutorial_value is Dictionary and str((tutorial_value as Dictionary).get("building_id", "")) == "dc_t0":
			return str((tutorial_value as Dictionary).get("id", ""))
	if not selected_datacenter_id.is_empty() and not Game.find_datacenter(selected_datacenter_id).is_empty():
		return selected_datacenter_id
	for plot: Dictionary in Game.state.get("plots", []):
		var value: Variant = plot.get("datacenter")
		if value is Dictionary and not (value as Dictionary).is_empty():
			return str((value as Dictionary).get("id", ""))
	return ""

# True only while a tutorial data center is genuinely queued. Everything else —
# aged out, demolished, never started — must not be described as "building".
func _tutorial_site_under_construction() -> bool:
	for item: Dictionary in Game.state.get("construction_queue", []):
		if str(item.get("type", "")) == "datacenter":
			return true
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("status", "")) == "building":
			return true
	return false

func _tutorial_waiting_copy() -> String:
	var remaining := 0.0
	for item: Dictionary in Game.state.get("construction_queue", []):
		if str(item.get("type", "")) == "datacenter":
			remaining = maxf(0.0, float(item.get("complete_at", 0.0)) - Game.simulation_time())
			break
	return tr("TUTORIAL_BUILDING_WAIT") % Game.format_duration(remaining)

func _set_tutorial_chrome_visibility(restored: bool, focus: String) -> void:
	if task_button != null:
		task_button.visible = restored
	if operations_button != null:
		operations_button.visible = restored
	if news_panel != null and not restored:
		news_panel.visible = false
	if primary_action_button != null:
		# A lesson whose site vanished routes the player back to the build CTA, so
		# that button has to be visible even though this focus normally hides it.
		var needs_rebuild := _tutorial_visual_mode == "rebuild"
		primary_action_button.visible = restored or needs_rebuild or focus in ["build_dc_t0", "buy_plot", "build_dc_t1"]

# Stage three of the coaching target chain: world building -> drawer control ->
# open sheet option. A picker covers the drawer control that spawned it, so the
# resolver has to follow the player onto the sheet; otherwise it keeps returning
# a control that is occluded and, worse, an action that re-opens the same sheet.
const TUTORIAL_SHEET_CHOICES := {
	"install_power": "Choice_power_t1",
	"rack_slot_0": "Choice_rack_compute_t1",
	"install_cooler": "Choice_cool_air_t1",
}

func _tutorial_sheet_target(focus: String) -> Dictionary:
	var sheet_overlay := _topmost_action_sheet()
	if sheet_overlay == null:
		return {}
	var option: Control = null
	# A confirm sheet is the terminal step of any pick, so it outranks the
	# per-focus mapping: once it is up, "confirm" is the only way forward.
	option = sheet_overlay.find_child("Choice_confirm", true, false) as Control
	var preferred := str(TUTORIAL_SHEET_CHOICES.get(focus, ""))
	if option == null and not preferred.is_empty():
		option = sheet_overlay.find_child(preferred, true, false) as Control
	if option == null or not option.is_visible_in_tree() or (option is Button and (option as Button).disabled):
		option = _first_enabled_choice(sheet_overlay)
	if option == null:
		# An unmapped sheet is still the player's foreground. Never leave the
		# spotlight behind it — fall back to copy only.
		return {"rect": Rect2(), "action": Callable(), "source": "sheet_unmapped", "mode": "dormant", "foreground": _sheet_foreground_rect(sheet_overlay)}
	# Resolve by name at tap time. Capturing the button meant a sheet that had
	# been re-laid-out since the resolve left the guided tap pointing at a freed
	# node, so the highlight stayed lit while nothing happened.
	var option_name := option.name
	var action := func() -> void:
		var sheet := _topmost_action_sheet()
		if sheet == null:
			return
		var live := sheet.find_child(option_name, true, false) as Button
		if live != null and not live.disabled:
			live.pressed.emit()
	return {"rect": option.get_global_rect(), "action": action, "source": "sheet_option", "mode": "actionable", "foreground": _sheet_foreground_rect(sheet_overlay), "target_node": option_name}

# Sheets can overlap: dismissing one plays a 0.2s exit while its replacement is
# already on screen (choosing a rack opens a confirm sheet). find_child returns
# the *first* match, i.e. the sheet on its way out, which pinned the spotlight
# to a panel the player can no longer use. Always take the newest live sheet.
func _topmost_action_sheet() -> Control:
	var newest: Control = null
	for node: Node in find_children("ActionSheetOverlay", "", true, false):
		var overlay := node as Control
		if overlay == null or not overlay.is_visible_in_tree():
			continue
		if bool(overlay.get_meta("dismissing", false)):
			continue
		newest = overlay
	return newest

func _first_enabled_choice(sheet_overlay: Control) -> Control:
	for node: Node in sheet_overlay.find_children("Choice_*", "Button", true, false):
		var button := node as Button
		if button != null and button.is_visible_in_tree() and not button.disabled:
			return button
	return null

func _sheet_foreground_rect(sheet_overlay: Control) -> Rect2:
	var sheet := sheet_overlay.find_child("ContextSheet", true, false) as Control
	if sheet == null:
		return Rect2()
	# Prefer the settled geometry: during the slide-in the live rect sits lower
	# than where the panel ends up, which would let the shade creep over it.
	var settled: Rect2 = sheet.get_meta("settled_rect", Rect2())
	return settled if settled.size != Vector2.ZERO else sheet.get_global_rect()

# Each drawer step lives on a specific tab. Without this the cooling lesson
# inherited the contracts tab left over from the previous step, so the slot it
# asked for was not even on screen and the spotlight silently went dormant.
const TUTORIAL_DRAWER_TABS := {
	"install_power": "board",
	"rack_slot_0": "board",
	"install_cooler": "board",
	"retire_dc": "board",
	"contract_internet": "contracts",
}

func _ensure_tutorial_drawer_tab(focus: String) -> void:
	var wanted := str(TUTORIAL_DRAWER_TABS.get(focus, ""))
	if wanted.is_empty() or _detail_focus == wanted:
		return
	# The tab belongs to whichever detail surface is up — the world drawer or the
	# full page — so switch it unconditionally; the value is inert elsewhere.
	_detail_focus = wanted
	_request_full_refresh()

# A guided install that is already under way must say so. Without this the coach
# kept repeating its instruction through the whole 20s timer while the site
# stayed dark, so the natural read was "that did nothing" and players tapped
# again — only to be refused because the work was already queued.
func _tutorial_install_wait(focus: String) -> float:
	var dc_id := _tutorial_datacenter_id()
	if dc_id.is_empty():
		return -1.0
	if focus == "rack_slot_0":
		var dc := Game.find_datacenter(dc_id)
		var racks: Array = dc.get("racks", [])
		for installed: Variant in racks:
			if installed is Dictionary and str((installed as Dictionary).get("status", "")) == "installing":
				return maxf(0.0, float((installed as Dictionary).get("install_complete_at", 0.0)) - Game.simulation_time())
		return -1.0
	var wanted := str({"install_power": "power", "install_cooler": "cooler"}.get(focus, ""))
	if wanted == "":
		return -1.0
	for item: Dictionary in Game.state.get("construction_queue", []):
		if str(item.get("type", "")) == wanted and str(item.get("datacenter_id", "")) == dc_id:
			return maxf(0.0, float(item.get("complete_at", 0.0)) - Game.simulation_time())
	return -1.0

func _resolve_tutorial_target(focus: String) -> Dictionary:
	var install_remaining := _tutorial_install_wait(focus)
	if install_remaining >= 0.0:
		return {"rect": Rect2(), "action": Callable(), "source": "install_wait", "mode": "waiting", "install_remaining": install_remaining}
	var sheet_target := _tutorial_sheet_target(focus)
	if not sheet_target.is_empty():
		return sheet_target
	_ensure_tutorial_drawer_tab(focus)
	var control: Control = null
	match focus:
		"build_dc_t0":
			control = _visible_control_named("Building_dc_t0")
			if control == null and _primary_action_kind == "build": control = primary_action_button
		"build_dc_t1":
			control = _visible_control_named("Building_dc_t1")
			if control == null and _primary_action_kind == "build": control = primary_action_button
		"install_power":
			var power_button := _visible_control_named("PowerSlot") as Button
			var power_section := _visible_control_named("BoardPowerSection")
			if power_button != null and power_section != null:
				var install_action := func() -> void:
					var live := _visible_control_named("PowerSlot") as Button
					if live != null and not live.disabled:
						live.pressed.emit()
				return {"rect": power_section.get_global_rect(), "action": install_action, "source": "control", "mode": "actionable", "target_node": power_section.name, "action_node": power_button.name}
			control = power_button
		"rack_slot_0":
			control = _visible_control_named("RackSlot0")
			if control != null:
				var board := _visible_datacenter_board(selected_datacenter_id)
				if board != null:
					return {"rect": control.get_global_rect(), "action": _on_board_rack_slot_selected.bind(board.datacenter_id, 0), "source": "control", "mode": "actionable", "target_node": control.name}
		"contract_internet":
			control = _visible_control_named("Contract_internet")
			if control == null: control = _visible_control_named("ContractCTA")
		"install_cooler":
			for edge: String in ["north", "east", "south", "west"]:
				control = _visible_control_named("Cooler_%s" % edge)
				if control != null: break
		"buy_plot":
			control = park_map.target_control_of("sale") if park_map != null else null
		"retire_dc": control = _visible_control_named("RetireButton")
	if control != null and control.is_visible_in_tree():
		# Look the control up again at tap time instead of capturing it. Pages and
		# drawers rebuild between the resolve and the tap, and a captured node that
		# has since been freed makes the guided tap do nothing at all — the player
		# just sees an unresponsive highlight.
		var control_name := control.name
		var action := func() -> void:
			var live := _visible_control_named(control_name)
			if live is Button and not (live as Button).disabled:
				(live as Button).pressed.emit()
		return {"rect": control.get_global_rect(), "action": action, "source": "control", "mode": "actionable", "target_node": control_name}
	if focus in ["install_power", "rack_slot_0", "contract_internet", "install_cooler", "retire_dc"]:
		var dc_id := _tutorial_datacenter_id()
		if dc_id.is_empty():
			# Distinguish "still building" from "there is no data center at all".
			# A site that aged out, was demolished, or never got built used to fall
			# into the same waiting branch and claim construction was in progress
			# with 0s left, leaving the lesson stranded on a step whose subject no
			# longer exists. Point the player at rebuilding instead.
			if not _tutorial_site_under_construction():
				var rebuild_target := primary_action_button
				if rebuild_target != null:
					var rebuild := func() -> void:
						if is_instance_valid(primary_action_button):
							primary_action_button.pressed.emit()
					return {"rect": rebuild_target.get_global_rect(), "action": rebuild, "source": "rebuild", "mode": "actionable", "target_node": rebuild_target.name, "copy_key": "TUTORIAL_REBUILD_SITE"}
				return {"rect": Rect2(), "action": Callable(), "source": "rebuild_unavailable", "mode": "dormant", "copy_key": "TUTORIAL_REBUILD_SITE"}
			return {"rect": Rect2(), "action": Callable(), "source": "construction_wait", "mode": "waiting"}
		if park_map != null:
			_focus_tutorial_world_target(dc_id)
			var building_target := park_map.building_rect(dc_id)
			if building_target.size != Vector2.ZERO:
				return {"rect": building_target, "action": _open_datacenter.bind(dc_id), "source": "world_building", "mode": "actionable", "world_stage": true}
	return {"rect": Rect2(), "action": Callable(), "source": "none", "mode": "dormant"}

func _focus_tutorial_world_target(datacenter_id: String) -> void:
	if _tutorial_world_focus_id == datacenter_id or park_map == null:
		return
	_tutorial_world_focus_id = datacenter_id
	park_map.focus_target(datacenter_id)
	get_tree().create_timer(0.32).timeout.connect(_refresh_tutorial_after_focus.bind(datacenter_id))

func _refresh_tutorial_after_focus(datacenter_id: String) -> void:
	if is_instance_valid(tutorial_overlay) and _tutorial_world_focus_id == datacenter_id:
		_refresh_tutorial()

func _visible_control_named(node_name: String) -> Control:
	for node: Node in find_children(node_name, "", true, false):
		var control := node as Control
		if control != null and control.is_visible_in_tree():
			return control
	return null

func _on_tutorial_target_activated() -> void:
	get_tree().create_timer(0.18).timeout.connect(func() -> void:
		if is_instance_valid(tutorial_overlay):
			_refresh_tutorial()
	)

func _news_text() -> String:
	if not _news_notice_message.is_empty():
		return _news_notice_message
	var market: Dictionary = Game.state.get("market", {})
	if not market.get("active", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["active"][0].get("event_id", "")))
		return "%s — %s" % [tr(event.get("name_key", "")), tr(event.get("description_key", ""))]
	if not market.get("previews", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["previews"][0].get("event_id", "")))
		return "%s: %s" % [tr("MARKET_PREVIEW"), tr(event.get("name_key", ""))]
	return tr("MARKET_CALM")

func _headline_event_is_rare() -> bool:
	var market: Dictionary = Game.state.get("market", {})
	for collection: Array in [market.get("active", []), market.get("previews", [])]:
		if not collection.is_empty():
			var event := DataRepository.get_entry("events", str(collection[0].get("event_id", "")))
			return bool(event.get("rare", false))
	return false

func _customer_market_card(customer_id: String, customer: Dictionary) -> Control:
	var player: Dictionary = Game.state.get("player", {})
	var unlock_era := int(customer.get("unlock_era", 1))
	var network_required := int(customer.get("minimum_network_level", 1))
	var available := unlock_era <= int(player.get("era", 1)) and network_required <= int(player.get("network_level", 1))
	var accent: Color = ChartScene.CUSTOMER_COLORS.get(customer_id, ThemeMaker.COLORS.sky) if available else Color("8a97a8")
	var card := Widgets.flat_card(accent)
	card.name = "MarketCustomer_%s" % customer_id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	card.add_child(card_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card_box.add_child(row)
	row.add_child(_icon_view(str(customer.get("asset_id", "")), Vector2(64, 64)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var customer_name := _label(tr(customer.get("name_key", "")), ThemeMaker.TYPE_SCALE.heading, Color.WHITE)
	ThemeMaker.apply_text_role(customer_name, "title")
	customer_name.max_lines_visible = 1
	customer_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(customer_name)
	var trend := _market_trend(customer_id)
	var trend_color := ThemeMaker.COLORS.green if float(trend.get("percent", 0.0)) > 0.05 else (ThemeMaker.COLORS.red if float(trend.get("percent", 0.0)) < -0.05 else ThemeMaker.COLORS.cyan)
	var market_text := "× %.2f  %s %+.1f%%" % [Game.market_multiplier(customer_id), str(trend.get("arrow", "→")), float(trend.get("percent", 0.0))]
	if not available:
		if unlock_era > int(player.get("era", 1)):
			market_text = tr("UNLOCK_AT_ERA") % unlock_era
		else:
			var network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_required), {})
			market_text = tr("UNLOCK_AT_NETWORK") % tr(network.get("name_key", "NETWORK"))
	copy.add_child(_label(market_text, ThemeMaker.TYPE_SCALE.body, accent.lightened(0.12) if not available else trend_color))
	if available:
		var history: Array = Game.state.get("market", {}).get("history", {}).get(customer_id, [])
		var sparkline := SparklineScene.new()
		sparkline.name = "Sparkline_%s" % customer_id
		sparkline.setup(history, accent)
		card_box.add_child(sparkline)
	return card

func _feature_heading(asset_id: String, title_text: String, subtitle: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_icon_view(asset_id, Vector2(66, 66)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var feature_title := _label(title_text, 28, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(feature_title, "title")
	copy.add_child(feature_title)
	var sub := _label(subtitle, 21, accent.lightened(0.15))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(sub)
	return row

func _event_card(event_state: Dictionary, preview: bool) -> Control:
	var event := DataRepository.get_entry("events", str(event_state.get("event_id", "")))
	var rare := bool(event.get("rare", false))
	var card := Widgets.flat_card(ThemeMaker.COLORS.purple) if rare else _card()
	card.name = "MarketEventPreview" if preview else "MarketEventActive"
	card.set_meta("rare_event", rare)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	box.add_child(title_row)
	var event_title := _label("%s · %s" % [tr("MARKET_PREVIEW") if preview else tr("MARKET_ACTIVE"), tr(event.get("name_key", ""))], 27, ThemeMaker.COLORS.purple if rare else (ThemeMaker.COLORS.orange if preview else ThemeMaker.COLORS.green))
	ThemeMaker.apply_text_role(event_title, "title")
	event_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_title.max_lines_visible = 1
	event_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(event_title)
	if rare:
		var rare_badge := Widgets.chip(tr("EVENT_RARE_BADGE"), ThemeMaker.COLORS.purple)
		rare_badge.name = "RareEventBadge"
		title_row.add_child(rare_badge)
	var description := _label(tr(event.get("description_key", "")), 22, ThemeMaker.COLORS.cream)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	var impacts := HBoxContainer.new()
	impacts.name = "EventImpacts"
	impacts.add_theme_constant_override("separation", 8)
	box.add_child(impacts)
	var multipliers: Dictionary = event.get("customer_multipliers", {}).duplicate(true)
	if event.has("all_customer_multiplier"):
		for customer_id: String in DataRepository.get_table("customers").get("items", {}):
			multipliers[customer_id] = float(event.get("all_customer_multiplier", 1.0))
	for customer_id: String in multipliers:
		var customer := DataRepository.get_entry("customers", customer_id)
		var multiplier := float(multipliers.get(customer_id, 1.0))
		var impact := PanelContainer.new()
		impact.custom_minimum_size = Vector2(126, 68)
		impact.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE_GROUP, Color.TRANSPARENT, 0, 14))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		impact.add_child(row)
		row.add_child(_icon_view(str(customer.get("asset_id", "")), Vector2(38, 38)))
		row.add_child(_label("×%.1f" % multiplier, 19, ThemeMaker.COLORS.green if multiplier >= 1.0 else ThemeMaker.COLORS.red))
		impacts.add_child(impact)
	var target_at := float(event_state.get("start_at" if preview else "end_at", Game.simulation_time()))
	var duration := float(DataRepository.get_table("economy").get("market", {}).get("preview_seconds", 7200.0)) if preview else maxf(1.0, float(event_state.get("end_at", target_at)) - float(event_state.get("start_at", Game.simulation_time())))
	var timer := Widgets.timer_bar(target_at, duration)
	timer.name = "EventTimer"
	box.add_child(timer)
	if preview:
		box.add_child(_label(tr("EVENT_STARTS_IN") % Game.format_duration(maxf(0.0, target_at - Game.simulation_time())), 20, ThemeMaker.COLORS.orange))
	var cta := _button(tr("EVENT_CHECK_MY_DC"), _open_first_datacenter_contracts, ThemeMaker.COLORS.sky)
	_set_button_asset(cta, "ic_contract", 40)
	box.add_child(cta)
	return card

func _open_first_datacenter_contracts() -> void:
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and not (dc as Dictionary).is_empty() and str((dc as Dictionary).get("status", "")) != "ruined":
			_open_datacenter_detail(str((dc as Dictionary).get("id", "")), "contracts")
			return
	_handle_result({"ok": false, "reason": "datacenter_missing"})

func _show_rack_picker(datacenter_id: String, slot: int) -> void:
	var validation := _rack_slot_install_entry_result(datacenter_id, slot)
	if not bool(validation.get("ok", false)):
		_handle_result(validation, {"datacenter_id": datacenter_id, "slot": slot, "operation": "rack"})
		return
	var choices: Array[Dictionary] = []
	for rack_id: String in DataRepository.get_table("racks").get("items", {}):
		var rack := DataRepository.get_entry("racks", rack_id)
		if Game.is_unlocked(rack):
			var rack_cost := Game.rack_purchase_cost(rack_id)
			choices.append({
				"id": rack_id,
				"height": 132,
				"cost": rack_cost,
				"asset": str(rack.get("asset_prefix", "")) + "_active",
				"text": "%s · $%s\n%s %s · %s %s · $%s/%s\n%s" % [
					tr(rack.get("name_key", "")), Game.format_number(rack_cost),
					tr("STAT_POWER_DRAW"), Game.format_number(float(rack.get("power", 0.0))),
					tr("STAT_HEAT_OUTPUT"), Game.format_number(float(rack.get("heat", 0.0))),
					Game.format_number(float(rack.get("income_per_month", 0.0))), tr("MONTH_SHORT"),
					_rack_trait_label(float(rack.get("market_sensitivity", 1.0))),
				],
			})
	if choices.is_empty():
		_handle_result({"ok": false, "reason": "locked"})
		return
	_show_choice(tr("INSTALL"), choices, func(rack_id: String) -> void: _preview_rack_install(datacenter_id, slot, rack_id), "rack_slot_0")

func _preview_rack_install(datacenter_id: String, slot: int, rack_id: String) -> void:
	var validation := _rack_slot_install_entry_result(datacenter_id, slot)
	if not bool(validation.get("ok", false)):
		_handle_result(validation, {"datacenter_id": datacenter_id, "slot": slot, "operation": "rack"})
		return
	var rack := DataRepository.get_entry("racks", rack_id)
	if rack.is_empty() or not Game.is_unlocked(rack):
		_handle_result({"ok": false, "reason": "locked"})
		return
	var board := _visible_datacenter_board(datacenter_id)
	if board != null:
		board.set_placement_preview(slot, rack_id)
	var state := board.placement_state_for_slot(slot, rack_id) if board != null else {}
	var hint := str(state.get("hint", ""))
	var body := "%s\n%s\n%s: %s   %s: %s   %s: $%s/%s" % [
		tr(rack.get("name_key", "")), hint,
		tr("RACK_STAT_POWER"), Game.format_number(float(rack.get("power", 0.0))),
		tr("RACK_STAT_HEAT"), Game.format_number(float(rack.get("heat", 0.0))),
		tr("RACK_STAT_OUTPUT"), Game.format_number(float(rack.get("income_per_month", 0.0))), tr("MONTH_SHORT"),
	]
	var confirm_install := func(choice: String) -> void:
		if choice == "confirm":
			_handle_result(Game.install_rack(datacenter_id, slot, rack_id), {"datacenter_id": datacenter_id, "slot": slot, "operation": "rack"})
	_present_action_sheet(tr("INSTALL"), body, [{"id": "confirm", "text": "%s · $%s" % [tr("CONFIRM"), Game.format_number(Game.rack_purchase_cost(rack_id))], "color": ThemeMaker.COLORS.green}], confirm_install, ThemeMaker.COLORS.cyan, "rack_slot_0")
	var overlay := find_child("ActionSheetOverlay", true, false)
	if overlay != null and board != null:
		overlay.tree_exiting.connect(board.clear_placement_preview)

func _rack_slot_install_entry_result(datacenter_id: String, slot: int) -> Dictionary:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		return {"ok": false, "reason": "datacenter_missing"}
	if str(dc.get("status", "")) != "operational":
		return {"ok": false, "reason": "datacenter_unavailable"}
	var racks: Array = dc.get("racks", [])
	if slot < 0 or slot >= racks.size():
		return {"ok": false, "reason": "invalid_slot"}
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var unlocked := false
	for unlocked_slot: Variant in building.get("unlocked_slots", []):
		if int(unlocked_slot) == slot:
			unlocked = true
			break
	if not unlocked:
		return {"ok": false, "reason": "slot_locked"}
	if racks[slot] is Dictionary and not (racks[slot] as Dictionary).is_empty():
		return {"ok": false, "reason": "slot_occupied"}
	return {"ok": true}

func _visible_datacenter_board(datacenter_id: String) -> DatacenterBoard:
	for node: Node in find_children("*", "", true, false):
		if node is DatacenterBoard and str(node.get("datacenter_id")) == datacenter_id and node.is_visible_in_tree():
			return node as DatacenterBoard
	return null

func _rack_trait_label(sensitivity: float) -> String:
	if sensitivity < 0.7:
		return tr("RACK_TRAIT_STABLE")
	if sensitivity > 1.1:
		return tr("RACK_TRAIT_VOLATILE")
	return tr("RACK_TRAIT_BALANCED")

func _show_building_picker(plot_id: String) -> void:
	park_map.focus_target(plot_id)
	# The picker owns an 88u drag target, an 88u heading, a 418u card and the
	# painted frame's 112u content inset. A 620u sheet let the cards paint through
	# the bottom frame on iPhone. Reserve about 46% of the portrait viewport so
	# the complete card remains visible while more than half the world stays in
	# view above it.
	var picker_height := clampf(get_viewport_rect().size.y * 0.46, 760.0, 820.0)
	var parts := _create_world_sheet("BuildingPicker", picker_height)
	var overlay := parts["overlay"] as ColorRect
	overlay.set_meta("content_fits_viewport", true)
	overlay.set_meta("requested_sheet_height", picker_height)
	var sheet := parts["sheet"] as PanelContainer
	sheet.clip_contents = true
	var sheet_box := parts["box"] as VBoxContainer
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	sheet_box.add_child(heading)
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_copy)
	var picker_title := _label(tr("BUILD_DATA_CENTER"), 36, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(picker_title, "display")
	heading_copy.add_child(picker_title)
	var plot_index := 1
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("id", "")) == plot_id:
			plot_index = int(plot.get("index", 1))
			break
	heading_copy.add_child(_label(tr("PLOT_EMPTY") % plot_index, 22, ThemeMaker.COLORS.cyan))
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	heading.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.name = "BuildingPickerScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_box.add_child(scroll)
	var cards := HBoxContainer.new()
	cards.name = "BuildingPickerCards"
	cards.add_theme_constant_override("separation", 16)
	scroll.add_child(cards)
	var panel_style := sheet.get_theme_stylebox("panel")
	var cards_width := get_viewport_rect().size.x - 40.0 - panel_style.get_content_margin(SIDE_LEFT) - panel_style.get_content_margin(SIDE_RIGHT)
	var two_up_card_width := floorf((cards_width - 16.0) * 0.5)
	for building_id: String in DataRepository.get_table("buildings").get("items", {}):
		var building := DataRepository.get_entry("buildings", building_id)
		if not Game.is_unlocked(building):
			continue
		if bool(building.get("tutorial_only", false)) and bool(Game.state.get("flags", {}).get("standard_built", false)):
			continue
		var card := Button.new()
		card.name = "Building_%s" % building_id
		# Two starter choices fit edge-to-edge without the second card being
		# clipped by a few pixels. Additional tiers remain horizontally scrollable.
		card.custom_minimum_size = Vector2(maxf(300.0, two_up_card_width), 418)
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("affordable_card", true)
		ThemeMaker.apply_button_color(card, Color("1c3850"))
		_wire_button_motion(card)
		card.pressed.connect(func() -> void:
			_dismiss_world_sheet(overlay, func() -> void: _handle_result(Game.start_datacenter_construction(plot_id, building_id)))
		)
		cards.add_child(card)
		var card_content := VBoxContainer.new()
		card_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_content.offset_left = 18
		card_content.offset_top = 16
		card_content.offset_right = -18
		card_content.offset_bottom = -16
		card_content.alignment = BoxContainer.ALIGNMENT_CENTER
		card_content.add_theme_constant_override("separation", 8)
		card.add_child(card_content)
		card_content.add_child(_icon_view(str(building.get("asset_prefix", "")) + "_active", Vector2(252, 238)))
		var building_name := _label(tr(building.get("name_key", "")), 28, ThemeMaker.COLORS.cream)
		ThemeMaker.apply_text_role(building_name, "title")
		building_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_content.add_child(building_name)
		var building_cost := float(building.get("cost", 0.0))
		var building_cash := float(Game.state.get("player", {}).get("cash", 0.0))
		var cost_copy := "$%s" % Game.format_number(building_cost)
		if building_cash < building_cost:
			cost_copy += " · " + (tr("AFFORD_SHORTFALL") % Game.format_number(building_cost - building_cash))
		var cost := _label(cost_copy, 23 if building_cash < building_cost else 27, ThemeMaker.COLORS.green if building_cash >= building_cost else Color("b8c2cc"))
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_content.add_child(cost)
		var duration := _label(tr("COMPLETE_IN") % Game.format_duration(float(building.get("build_seconds", 0.0))), 20, ThemeMaker.COLORS.cyan)
		duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_content.add_child(duration)
		Widgets.affordable_style(card, building_cost)

func _create_world_sheet(node_name: String, sheet_height: float, scroll_content: bool = false) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.name = node_name
	overlay.color = Color(0.015, 0.03, 0.05, 0.32)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.tree_exiting.connect(_request_hud_refresh)
	add_child(overlay)
	call_deferred("_refresh_tutorial")
	var sheet := PanelContainer.new()
	sheet.name = "ContextSheet"
	sheet.set_meta("viewport_bounded_surface", true)
	sheet.clip_contents = true
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var safe_area := _safe_area_margins()
	var bottom_gutter := maxf(18.0, safe_area.w)
	var available_height := maxf(0.0, get_viewport_rect().size.y - safe_area.y - bottom_gutter)
	var resolved_height := minf(sheet_height, available_height)
	sheet.offset_left = 20
	sheet.offset_top = -(bottom_gutter + resolved_height)
	sheet.offset_right = -20
	sheet.offset_bottom = -bottom_gutter
	sheet.set_meta("safe_bottom_gutter", bottom_gutter)
	sheet.set_meta("resolved_sheet_height", resolved_height)
	sheet.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	sheet.set_meta("open_audio", "sfx_sheet_open")
	overlay.add_child(sheet)
	var box := VBoxContainer.new()
	box.name = "ContextSheetRoot"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	sheet.add_child(box)
	var handle_center := CenterContainer.new()
	handle_center.name = "SheetDragHandle"
	handle_center.custom_minimum_size.y = 88
	handle_center.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(handle_center)
	var handle := PanelContainer.new()
	handle.custom_minimum_size = Vector2(88, 8)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var handle_style := ThemeMaker.panel(Color(1, 1, 1, 0.28), Color.TRANSPARENT, 0, 4)
	handle_style.content_margin_left = 0
	handle_style.content_margin_right = 0
	handle_style.content_margin_top = 0
	handle_style.content_margin_bottom = 0
	handle.add_theme_stylebox_override("panel", handle_style)
	handle_center.add_child(handle)
	var content_box := box
	var scroll: ScrollContainer = null
	if scroll_content:
		scroll = ScrollContainer.new()
		scroll.name = "ContextSheetScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.scroll_deadzone = 12
		scroll.set_meta("touch_scroll_enabled", true)
		ThemeMaker.apply_system_scrollbar(scroll)
		box.add_child(scroll)
		content_box = VBoxContainer.new()
		content_box.name = "ContextSheetContent"
		content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_box.add_theme_constant_override("separation", 14)
		scroll.add_child(content_box)
	sheet.modulate.a = 0.0
	sheet.position.y += 54
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.18)
	tween.tween_property(sheet, "position:y", sheet.position.y - 54, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_wire_sheet_interactions(overlay, sheet, handle_center, true)
	AudioService.play_sfx("sfx_sheet_open")
	return {"overlay": overlay, "sheet": sheet, "root_box": box, "box": content_box, "scroll": scroll}

func _dismiss_world_sheet(overlay: CanvasItem, after: Callable = Callable()) -> void:
	_animate_sheet_dismiss(overlay, after, true)

func _dismiss_action_sheet(overlay: CanvasItem, after: Callable = Callable()) -> void:
	_animate_sheet_dismiss(overlay, after, false)

func _animate_sheet_dismiss(overlay: CanvasItem, after: Callable, reset_world: bool) -> void:
	if not is_instance_valid(overlay) or bool(overlay.get_meta("dismissing", false)):
		return
	overlay.set_meta("dismissing", true)
	# Yield the name immediately. A replacement sheet (picking a rack opens a
	# confirm sheet) is added while this one is still animating out, and Godot
	# silently renames the newcomer on a name collision — which made every
	# lookup by name, the tutorial's target resolution included, keep finding
	# the sheet on its way out instead of the live one.
	if overlay is Node:
		(overlay as Node).name = "Dismissed%s" % (overlay as Node).name
	var sheet := overlay.find_child("ContextSheet", true, false) as Control
	if sheet == null:
		overlay.queue_free()
		if reset_world and park_map != null:
			park_map.reset_camera()
		if after.is_valid():
			after.call()
		return
	AudioService.play_sfx("sfx_sheet_close")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "position:y", sheet.position.y + 80.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sheet, "modulate:a", 0.0, 0.16)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.20)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
		if reset_world and park_map != null:
			park_map.reset_camera()
		if after.is_valid():
			after.call()
	)

func _wire_sheet_interactions(overlay: ColorRect, sheet: Control, handle_area: Control, reset_world: bool) -> void:
	var backdrop := {"armed": false}
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		var released: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
		var outside := not sheet.get_global_rect().has_point(_pointer_position(event))
		if pressed:
			backdrop["armed"] = outside
			if outside:
				overlay.accept_event()
		elif released and bool(backdrop["armed"]):
			backdrop["armed"] = false
			if outside:
				_animate_sheet_dismiss(overlay, Callable(), reset_world)
			overlay.accept_event()
		elif released:
			backdrop["armed"] = false
	)
	var drag := {"active": false, "start_y": 0.0, "base_y": 0.0, "last_y": 0.0, "last_ms": 0}
	handle_area.gui_input.connect(func(event: InputEvent) -> void:
		if bool(overlay.get_meta("tutorial_lock_close", false)):
			drag["active"] = false
			handle_area.accept_event()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_sheet_drag(drag, sheet, _pointer_position(event).y)
			else:
				_end_sheet_drag(drag, overlay, sheet, reset_world, _pointer_position(event).y)
			handle_area.accept_event()
		elif event is InputEventMouseMotion and bool(drag["active"]):
			_update_sheet_drag(drag, sheet, _pointer_position(event).y)
			handle_area.accept_event()
		elif event is InputEventScreenTouch:
			if event.pressed:
				_begin_sheet_drag(drag, sheet, event.position.y)
			else:
				_end_sheet_drag(drag, overlay, sheet, reset_world, event.position.y)
			handle_area.accept_event()
		elif event is InputEventScreenDrag and bool(drag["active"]):
			_update_sheet_drag(drag, sheet, event.position.y)
			handle_area.accept_event()
	)

func _pointer_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.global_position
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.position
	return Vector2.ZERO

func _begin_sheet_drag(drag: Dictionary, sheet: Control, pointer_y: float) -> void:
	drag["active"] = true
	drag["start_y"] = pointer_y
	drag["base_y"] = sheet.position.y
	drag["last_y"] = pointer_y
	drag["last_ms"] = Time.get_ticks_msec()

func _update_sheet_drag(drag: Dictionary, sheet: Control, pointer_y: float) -> void:
	var distance := clampf(pointer_y - float(drag["start_y"]), 0.0, 160.0)
	sheet.position.y = float(drag["base_y"]) + distance
	sheet.modulate.a = 1.0 - distance / 480.0
	drag["last_y"] = pointer_y
	drag["last_ms"] = Time.get_ticks_msec()

func _end_sheet_drag(drag: Dictionary, overlay: CanvasItem, sheet: Control, reset_world: bool, pointer_y: float) -> void:
	if not bool(drag["active"]):
		return
	drag["active"] = false
	var distance := maxf(0.0, pointer_y - float(drag["start_y"]))
	var elapsed := maxf(1.0, float(Time.get_ticks_msec() - int(drag["last_ms"])))
	var velocity := maxf(0.0, pointer_y - float(drag["last_y"])) * 1000.0 / elapsed
	if distance >= 90.0 or velocity >= 900.0:
		_animate_sheet_dismiss(overlay, Callable(), reset_world)
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "position:y", float(drag["base_y"]), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.16)

func _show_datacenter_context(datacenter_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	selected_datacenter_id = datacenter_id
	park_map.focus_target(datacenter_id)
	var parts := _create_world_sheet("DatacenterContext", 1380, true)
	var overlay := parts["overlay"] as ColorRect
	overlay.set_meta("datacenter_id", datacenter_id)
	var sheet_box := parts["box"] as VBoxContainer
	var sheet_root := parts["root_box"] as VBoxContainer
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var header := HBoxContainer.new()
	header.name = "DatacenterContextHeader"
	header.add_theme_constant_override("separation", 14)
	# Keep identity and close affordance fixed while the variable-height board,
	# retirement decision, and CTA scroll underneath. This prevents the sheet from
	# looking severed when a player inspects an aging room near the bottom.
	sheet_root.add_child(header)
	sheet_root.move_child(header, 1)
	var context_icon := _icon_view(_datacenter_context_asset(dc, building), Vector2(124, 124))
	context_icon.name = "DatacenterContextIcon"
	header.add_child(context_icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(copy)
	var context_title := _label(tr(building.get("name_key", "")), 34, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(context_title, "display")
	copy.add_child(context_title)
	var context_status := _label(_datacenter_header_status_text(dc), 23, _datacenter_status_color(dc))
	context_status.name = "DatacenterStatus"
	copy.add_child(context_status)
	var market_benefit := _label("", 20, ThemeMaker.COLORS.green)
	market_benefit.name = "MarketBenefitStatus"
	market_benefit.max_lines_visible = 1
	market_benefit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(market_benefit)
	_refresh_market_benefit_status(market_benefit, dc)
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	header.add_child(close_button)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	sheet_box.add_child(metrics)
	var income_chip := _metric_chip(tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc)), ThemeMaker.COLORS.green)
	var income_value := income_chip.find_child("Value", true, false) as Label
	income_value.name = "DatacenterIncomeValue"
	metrics.add_child(income_chip)
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	var lifespan_chip := _metric_chip(_lifespan_metric_text(progress), ThemeMaker.COLORS.yellow)
	var lifespan_value := lifespan_chip.find_child("Value", true, false) as Label
	lifespan_value.name = "DatacenterLifespanValue"
	metrics.add_child(lifespan_chip)
	overlay.set_meta("live_update", func() -> void:
		var live_dc := Game.find_datacenter(datacenter_id)
		if live_dc.is_empty():
			return
		var live_building := DataRepository.get_entry("buildings", str(live_dc.get("building_id", "")))
		context_icon.texture = AssetCatalog.texture(_datacenter_context_asset(live_dc, live_building))
		context_status.text = _datacenter_header_status_text(live_dc)
		context_status.add_theme_color_override("font_color", _datacenter_status_color(live_dc))
		_refresh_market_benefit_status(market_benefit, live_dc)
		income_value.text = tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(live_dc))
		var live_progress := Rules.age_progress(live_dc, Game.simulation_time(), DataRepository.get_table("buildings"))
		lifespan_value.text = _lifespan_metric_text(live_progress)
		var live_contract_button := overlay.find_child("ContractCTA", true, false) as Button
		if live_contract_button != null:
			_refresh_contract_cta(live_contract_button, live_dc)
		var live_hint := overlay.find_child("ContractPowerHint", true, false) as Label
		if live_hint != null:
			live_hint.visible = str(live_dc.get("power_unit", "")).is_empty()
	)
	if str(dc.get("status", "")) == "ruined":
		sheet_box.add_child(_button(tr("CLEAR_SCRAP_QUOTE") % Game.format_number(Rules.ruin_scrap_value(dc, Game.data)), func() -> void:
			_dismiss_world_sheet(overlay, _demolish.bind(datacenter_id))
		, ThemeMaker.COLORS.green))
		return
	if progress >= float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6)):
		sheet_box.add_child(_retirement_decision(dc, progress))
	var board := _create_datacenter_board(datacenter_id)
	sheet_box.add_child(board)
	var powered := not str(dc.get("power_unit", "")).is_empty()
	var contract_action := func() -> void:
		var live_dc := Game.find_datacenter(datacenter_id)
		if live_dc.is_empty():
			_handle_result({"ok": false, "reason": "datacenter_missing"})
		elif not str(live_dc.get("power_unit", "")).is_empty():
			_dismiss_world_sheet(overlay, _open_datacenter_detail.bind(datacenter_id, "contracts"))
		else:
			_handle_result({"ok": false, "reason": "power_required"}, {"datacenter_id": datacenter_id, "operation": "contract"})
	var contract_button := _button(tr("SIGN_CONTRACT"), contract_action, ThemeMaker.COLORS.sky if powered else Color("6f7b88"))
	contract_button.name = "ContractCTA"
	_set_button_asset(contract_button, "ic_contract", 42)
	_refresh_contract_cta(contract_button, dc)
	sheet_box.add_child(contract_button)
	# Built unconditionally: the drawer opens before the transformer exists and is
	# never rebuilt, so a hint created only for the unpowered case used to sit
	# there telling a powered site to install power.
	var power_hint := _label(tr("BOARD_INSTALL_POWER"), 20, Color("b8c2cc"))
	power_hint.name = "ContractPowerHint"
	power_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_hint.max_lines_visible = 1
	power_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	power_hint.visible = not powered
	sheet_box.add_child(power_hint)

func _datacenter_context_asset(dc: Dictionary, building: Dictionary) -> String:
	if str(dc.get("status", "")) == "ruined":
		return str(building.get("asset_prefix", "")) + "_ruin"
	return _datacenter_asset_id_for_context(dc, building)

func _datacenter_asset_id_for_context(dc: Dictionary, building: Dictionary) -> String:
	var suffix := "_dark" if str(dc.get("power_unit", "")).is_empty() else "_active"
	return str(building.get("asset_prefix", "")) + suffix

func _datacenter_status_text(dc: Dictionary) -> String:
	if str(dc.get("status", "")) == "ruined":
		return tr("DEMOLISH")
	for rack: Variant in dc.get("racks", []):
		if rack is Dictionary and str(rack.get("status", "")) == "faulted":
			return tr("FAULTED")
	if str(dc.get("power_unit", "")).is_empty():
		return tr("UNPOWERED")
	return tr("POWERED")

func _datacenter_header_status_text(dc: Dictionary) -> String:
	var status := _datacenter_status_text(dc)
	var customer_id := str(dc.get("customer_id", ""))
	if customer_id.is_empty():
		return status
	var customer := DataRepository.get_entry("customers", customer_id)
	return tr("DATACENTER_CLIENT_STATUS") % [tr(customer.get("name_key", "CONTRACT_NONE")), status]

func _datacenter_market_benefit(dc: Dictionary) -> Dictionary:
	var customer_id := str(dc.get("customer_id", ""))
	if customer_id.is_empty():
		return {}
	var best: Dictionary = {}
	for active: Variant in Game.state.get("market", {}).get("active", []):
		if not active is Dictionary or float(active.get("end_at", 0.0)) <= Game.simulation_time():
			continue
		var event_id := str(active.get("event_id", ""))
		var event := DataRepository.get_entry("events", event_id)
		var multiplier := float(event.get("all_customer_multiplier", 1.0))
		multiplier *= float(event.get("customer_multipliers", {}).get(customer_id, 1.0))
		if multiplier <= 1.0 or multiplier <= float(best.get("multiplier", 1.0)):
			continue
		best = {
			"event_id": event_id,
			"multiplier": multiplier,
			"end_at": float(active.get("end_at", 0.0)),
		}
	return best

func _refresh_market_benefit_status(label: Label, dc: Dictionary) -> void:
	var benefit := _datacenter_market_benefit(dc)
	label.visible = not benefit.is_empty()
	if benefit.is_empty():
		label.text = ""
		return
	var event := DataRepository.get_entry("events", str(benefit.get("event_id", "")))
	label.text = tr("MARKET_BENEFIT_STATUS") % [
		tr(event.get("name_key", "")),
		float(benefit.get("multiplier", 1.0)),
		Game.format_duration(maxf(0.0, float(benefit.get("end_at", 0.0)) - Game.simulation_time())),
	]
	label.set_meta("event_id", str(benefit.get("event_id", "")))
	label.set_meta("market_multiplier", float(benefit.get("multiplier", 1.0)))

func _refresh_contract_cta(button: Button, dc: Dictionary) -> void:
	var renewal_active := bool(dc.get("free_switch_available", false))
	button.text = tr("CONTRACT_RENEWAL_CTA") if renewal_active else tr("SIGN_CONTRACT")
	button.set_meta("renewal_active", renewal_active)
	button.set_meta("free_switch_available", renewal_active)
	var visual_state := "renewal" if renewal_active else ("ready" if not str(dc.get("power_unit", "")).is_empty() else "disabled")
	if str(button.get_meta("contract_visual_state", "")) == visual_state:
		return
	button.set_meta("contract_visual_state", visual_state)
	ThemeMaker.apply_button_color(button, ThemeMaker.COLORS.yellow if renewal_active else (ThemeMaker.COLORS.sky if visual_state == "ready" else Color("6f7b88")))
	if renewal_active:
		button.add_theme_stylebox_override("normal", ThemeMaker.renewal_button_box())
		button.add_theme_stylebox_override("hover", ThemeMaker.renewal_button_box(true))
		button.add_theme_stylebox_override("pressed", ThemeMaker.renewal_button_box(false, true))

func _datacenter_status_color(dc: Dictionary) -> Color:
	if str(dc.get("status", "")) == "ruined":
		return ThemeMaker.COLORS.red
	for rack: Variant in dc.get("racks", []):
		if rack is Dictionary and str(rack.get("status", "")) == "faulted":
			return ThemeMaker.COLORS.red
	return ThemeMaker.COLORS.orange if str(dc.get("power_unit", "")).is_empty() else ThemeMaker.COLORS.green

func _show_plot_purchase() -> void:
	var choices: Array[Dictionary] = [{
		"id": "buy",
		"text": "%s · $%s" % [tr("BUY_NEXT_PLOT"), Game.format_number(Game.next_plot_price())],
		"color": ThemeMaker.COLORS.green,
	}]
	var purchase_plot := func(choice: String) -> void:
		if choice == "buy":
			_handle_result(Game.buy_next_plot())
	_present_action_sheet(
		tr("BUY_NEXT_PLOT"),
		tr("PLOT_FOR_SALE") % [Game.state.get("plots", []).size() + 1, Game.format_number(Game.next_plot_price())],
		choices,
		purchase_plot,
		ThemeMaker.COLORS.cyan,
		"buy_plot"
	)

func _on_power_slot_selected(datacenter_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	if str(dc.get("status", "")) != "operational":
		_handle_result({"ok": false, "reason": "datacenter_unavailable"})
		return
	# Upgrades still need a choice.  The FTUE also deliberately teaches the
	# attachment picker, so only a normal player's first transformer is the
	# low-friction, one-tap path.
	if not str(dc.get("power_unit", "")).is_empty() or _tutorial_requires_power_picker():
		_show_attachment_picker(datacenter_id, "power", "")
		return
	var pending := _pending_attachment_job(datacenter_id, "power")
	if not pending.is_empty():
		_show_power_install_blocker("construction_in_progress", pending)
		return
	var starter := DataRepository.get_entry("attachments", "power_t1")
	if starter.is_empty() or not Game.is_unlocked(starter):
		_handle_result({"ok": false, "reason": "locked"}, {"unlock_era": int(starter.get("unlock_era", 1))})
		return
	var result: Dictionary = Game.install_power(datacenter_id, "power_t1")
	var reason := str(result.get("reason", ""))
	if not bool(result.get("ok", false)) and reason in ["queue_full", "construction_in_progress"]:
		_show_power_install_blocker(reason, _pending_attachment_job(datacenter_id, "power"))
		return
	_handle_result(result, {"datacenter_id": datacenter_id, "kind": "power", "operation": "attachment"})

func _tutorial_requires_power_picker() -> bool:
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	if bool(tutorial.get("completed", false)):
		return false
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	return index >= 0 and index < steps.size() and str((steps[index] as Dictionary).get("id", "")) == "power"

func _pending_attachment_job(datacenter_id: String, kind: String, edge: String = "") -> Dictionary:
	for queued: Dictionary in Game.state.get("construction_queue", []):
		if str(queued.get("datacenter_id", "")) != datacenter_id or str(queued.get("type", "")) != kind:
			continue
		if kind != "cooler" or str(queued.get("edge", "")) == edge:
			return queued
	return {}

func _show_power_install_blocker(reason: String, pending: Dictionary = {}) -> void:
	var body := _failure_message(reason)
	if not pending.is_empty():
		var remaining := maxf(0.0, float(pending.get("complete_at", Game.simulation_time())) - Game.simulation_time())
		body = tr("POWER_INSTALL_PENDING") % Game.format_duration(remaining)
	var choices: Array[Dictionary] = [{
		"id": "queue",
		"text": tr("VIEW_QUEUE"),
		"color": ThemeMaker.COLORS.orange,
		"asset": "ic_clock",
	}]
	_present_action_sheet(tr("POWER_INSTALL_BLOCKED"), body, choices, func(choice: String) -> void:
		if choice == "queue":
			_open_build_queue_from_context()
	, ThemeMaker.COLORS.orange)

func _open_build_queue_from_context() -> void:
	var context := find_child("DatacenterContext", true, false) as CanvasItem
	if context != null:
		_dismiss_world_sheet(context, _navigate.bind("build"))
	else:
		_navigate("build")

func _show_attachment_picker(datacenter_id: String, kind: String, edge: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	if str(dc.get("status", "")) != "operational":
		_handle_result({"ok": false, "reason": "datacenter_unavailable"})
		return
	if kind not in ["power", "cooler"]:
		_handle_result({"ok": false, "reason": "unknown"})
		return
	if kind == "cooler" and not Rules.COOLER_EDGES.has(edge):
		_handle_result({"ok": false, "reason": "invalid_edge"})
		return
	var choices: Array[Dictionary] = []
	for attachment_id: String in DataRepository.get_table("attachments").get("items", {}):
		var item := DataRepository.get_entry("attachments", attachment_id)
		if item.get("kind", "") == kind and Game.is_unlocked(item):
			# Stat rows spell their units out: the packaged font subsets carry no
			# glyphs for ⚡ ❄ ▦, so on device those symbols rendered as blanks and
			# left bare numbers with no way to tell capacity from cooling.
			var stat := "%s %s" % [tr("STAT_CAPACITY"), Game.format_number(float(item.get("capacity", 0.0)))] if kind == "power" else "%s %s · %s" % [tr("STAT_COOLING_OUTPUT"), Game.format_number(float(item.get("cooling", 0.0))), tr("STAT_COVERAGE") % 3]
			choices.append({"id": attachment_id, "height": 108, "cost": float(item.get("cost", 0.0)), "text": "%s · $%s\n%s" % [tr(item.get("name_key", "")), Game.format_number(float(item.get("cost", 0.0))), stat]})
	if choices.is_empty():
		_handle_result({"ok": false, "reason": "locked"})
		return
	var install_attachment := func(attachment_id: String) -> void:
		var result: Dictionary = Game.install_power(datacenter_id, attachment_id) if kind == "power" else Game.install_cooler(datacenter_id, edge, attachment_id)
		_handle_result(result, {"datacenter_id": datacenter_id, "kind": kind, "edge": edge, "operation": "attachment"})
		if bool(result.get("ok", false)) and kind == "cooler":
			_play_fx_at_world("fx_snowflake", datacenter_id, 170)
	_show_choice(tr("INSTALL"), choices, install_attachment, "install_power" if kind == "power" else "install_cooler")

func _show_rack_actions(datacenter_id: String, slot: int) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	if str(dc.get("status", "")) != "operational":
		_handle_result({"ok": false, "reason": "datacenter_unavailable"})
		return
	var racks: Array = dc.get("racks", [])
	if slot < 0 or slot >= racks.size():
		_handle_result({"ok": false, "reason": "invalid_slot"})
		return
	if not racks[slot] is Dictionary or (racks[slot] as Dictionary).is_empty():
		_handle_result({"ok": false, "reason": "slot_empty"})
		return
	var installed: Dictionary = racks[slot]
	var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
	var choices: Array[Dictionary] = []
	var body := ""
	var status_color := ThemeMaker.COLORS.cyan
	if installed.get("status", "") == "installing":
		var remaining := maxf(0.0, float(installed.get("install_complete_at", 0.0)) - Game.simulation_time())
		body = "%s · %s" % [tr("INSTALLING"), tr("COMPLETE_IN") % Game.format_duration(remaining)]
		status_color = ThemeMaker.COLORS.orange
		var gem_cost := maxi(1, int(ceil(remaining / 600.0)) * int(DataRepository.get_table("economy").get("construction", {}).get("gems_per_600_seconds", 1)))
		var ad_reduction := minf(remaining, float(DataRepository.get_table("economy").get("construction", {}).get("ad_reduction_seconds", 1800.0)))
		choices.append({"id": "install_ad", "text": "%s · -%s" % [tr("WATCH_AD"), Game.format_duration(ad_reduction)]})
		choices.append({"id": "install_gems", "text": "%s · %d %s" % [tr("SPEED_UP"), gem_cost, tr("GEMS_REWARD_SHORT")]})
	elif installed.get("status", "") == "faulted":
		var faults: Dictionary = DataRepository.get_table("economy").get("faults", {})
		var auto_remaining := maxf(0.0, float(installed.get("auto_repair_at", Game.simulation_time() + float(faults.get("auto_repair_seconds", 14400.0)))) - Game.simulation_time())
		body = tr("FAULTED_AUTO_REPAIR") % [int(round(float(faults.get("faulted_income_multiplier", 0.4)) * 100.0)), Game.format_duration(auto_remaining)]
		status_color = ThemeMaker.COLORS.red
		var repair_cost: float = ceil(float(rack.get("cost", 0.0)) * float(faults.get("repair_cost_ratio", 0.05)))
		var repair_seconds := (float(faults.get("repair_seconds_min", 600.0)) + float(faults.get("repair_seconds_max", 1800.0))) * 0.5
		var repair_level := str(Game.state.get("technology", {}).get("repair_team", 1))
		repair_seconds *= float(DataRepository.get_table("technology").get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(repair_level, {}).get("repair_time_multiplier", 1.0))
		var repair_uses := int(Game.state.get("reward_limits", {}).get("repair_uses", 0))
		var repair_limit := int(faults.get("rewarded_repairs_per_hour", 4))
		var instant_gems := int(faults.get("instant_repair_gems", 2))
		choices.append({"id": "repair", "text": tr("REPAIR_QUOTE") % [Game.format_number(repair_cost), Game.format_duration(repair_seconds)], "color": ThemeMaker.COLORS.green})
		choices.append({"id": "ad", "text": tr("REPAIR_AD_QUOTE") % [repair_uses, repair_limit]})
		choices.append({"id": "gems", "text": tr("REPAIR_GEMS_QUOTE") % instant_gems})
	else:
		var enabled := bool(installed.get("enabled", true))
		body = tr("RACK_DISABLED") if not enabled else tr("POWERED")
		status_color = Color("aeb8c4") if not enabled else ThemeMaker.COLORS.green
		choices.append({"id": "power", "text": tr("RACK_TURN_ON") if not enabled else tr("RACK_TURN_OFF"), "color": ThemeMaker.COLORS.green if not enabled else ThemeMaker.COLORS.sky})
	if installed.get("status", "") != "installing":
		var refund: float = round(float(rack.get("cost", 0.0)) * float(DataRepository.get_table("economy").get("aging", {}).get("rack_refund_ratio", 0.5)))
		choices.append({"id": "uninstall", "text": tr("DISMANTLE_RACK_QUOTE") % Game.format_number(refund), "color": Color("263d59")})
	_present_action_sheet(tr(rack.get("name_key", "RACKS")), body, choices, func(action: String) -> void:
		match action:
			"install_ad": _handle_result(Game.request_reward("rack_install:%s:%d" % [datacenter_id, slot]))
			"install_gems": _handle_result(Game.speed_up_rack_install_with_gems(datacenter_id, slot))
			"repair": _handle_result(Game.dispatch_repair(datacenter_id, slot))
			"ad": _handle_result(Game.request_reward("repair:%s:%d" % [datacenter_id, slot]))
			"gems": _handle_result(Game.instant_repair_with_gems(datacenter_id, slot))
			"power": _handle_result(Game.set_rack_enabled(datacenter_id, slot, not bool(installed.get("enabled", true))))
			"uninstall": _handle_result(Game.uninstall_rack(datacenter_id, slot))
		, status_color)

func _show_choice(title_text: String, choices: Array[Dictionary], callback: Callable, tutorial_focus: String = "") -> void:
	_present_action_sheet(title_text, "", choices, callback, ThemeMaker.COLORS.cyan, tutorial_focus)

func _present_action_sheet(title_text: String, body: String, choices: Array[Dictionary], callback: Callable, body_color: Color = ThemeMaker.COLORS.cyan, tutorial_focus: String = "") -> void:
	var overlay := ColorRect.new()
	overlay.name = "ActionSheetOverlay"
	overlay.set_meta("tutorial_focus", tutorial_focus)
	overlay.set_meta("backdrop_dismiss_enabled", true)
	overlay.set_meta("explicit_close_count", 1)
	overlay.color = Color(0.015, 0.03, 0.06, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.tree_exiting.connect(_request_hud_refresh)
	add_child(overlay)
	call_deferred("_refresh_tutorial")

	var sheet := PanelContainer.new()
	sheet.name = "ContextSheet"
	sheet.set_meta("viewport_bounded_surface", true)
	sheet.clip_contents = true
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 32
	sheet.offset_top = -get_viewport_rect().size.y * 0.88 - 24.0
	sheet.offset_right = -32
	sheet.offset_bottom = -24
	sheet.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	sheet.set_meta("open_audio", "sfx_sheet_open")
	overlay.add_child(sheet)

	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 12)
	sheet.add_child(sheet_box)
	var handle_center := CenterContainer.new()
	handle_center.name = "SheetDragHandle"
	handle_center.custom_minimum_size.y = 88
	handle_center.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet_box.add_child(handle_center)
	var handle := ColorRect.new()
	handle.color = Color(1, 1, 1, 0.26)
	handle.custom_minimum_size = Vector2(92, 8)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle_center.add_child(handle)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	heading.name = "SheetHeading"
	sheet_box.add_child(heading)
	var title_label := _label(title_text, 36, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(title_label, "display")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title_label)
	var close_button := Widgets.close_button(_dismiss_action_sheet.bind(overlay))
	close_button.name = "SheetCloseButton"
	heading.add_child(close_button)
	if not body.is_empty():
		var body_label := _label(body, 25, body_color)
		body_label.name = "ActionSheetStatus"
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_box.add_child(body_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_box.add_child(scroll)
	var choice_box := VBoxContainer.new()
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_box.add_theme_constant_override("separation", 10)
	scroll.add_child(choice_box)
	for choice: Dictionary in choices:
		var choice_id := str(choice.get("id", ""))
		var choice_color: Color = choice.get("color", ThemeMaker.COLORS.sky)
		var hold_seconds := float(choice.get("hold_seconds", 0.0))
		var choice_button := _button(str(choice.get("text", choice_id)), Callable() if hold_seconds > 0.0 else func() -> void:
			_dismiss_action_sheet(overlay, callback.bind(choice_id))
		, choice_color)
		choice_button.name = "Choice_%s" % choice_id
		choice_button.set_meta("choice_id", choice_id)
		choice_button.set_meta("choice_available", bool(choice.get("available", true)))
		if choice.has("asset"):
			_set_button_asset(choice_button, str(choice.get("asset", "")), 64)
		if hold_seconds > 0.0:
			choice_button.name = "HoldConfirmButton"
			var hold_state := {"tween": null, "completed": false}
			choice_button.button_down.connect(func() -> void:
				hold_state["completed"] = false
				var hold_tween := choice_button.create_tween()
				hold_state["tween"] = hold_tween
				hold_tween.tween_property(choice_button, "modulate", Color(1.28, 1.28, 1.28, 1.0), hold_seconds)
				hold_tween.tween_callback(func() -> void:
					hold_state["completed"] = true
					_dismiss_action_sheet(overlay, callback.bind(choice_id))
				)
			)
			choice_button.button_up.connect(func() -> void:
				if not bool(hold_state["completed"]):
					var active_tween: Variant = hold_state["tween"]
					if active_tween is Tween and (active_tween as Tween).is_valid():
						(active_tween as Tween).kill()
					choice_button.create_tween().tween_property(choice_button, "modulate", Color.WHITE, 0.14)
			)
		choice_button.custom_minimum_size.y = float(choice.get("height", 92.0))
		if choice.has("cost"):
			Widgets.affordable_style(choice_button, float(choice.get("cost", 0.0)))
		choice_box.add_child(choice_button)
	# Autowrapped labels only know their true height after the sheet has a width.
	# Measure and animate on the next layout frame instead of guessing from lines.
	sheet.modulate.a = 0.0
	call_deferred("_finalize_action_sheet_layout", sheet, sheet_box, scroll, choice_box)
	_wire_sheet_interactions(overlay, sheet, handle_center, false)

func _finalize_action_sheet_layout(sheet: PanelContainer, sheet_box: VBoxContainer, scroll: ScrollContainer, choice_box: VBoxContainer) -> void:
	if not is_instance_valid(sheet):
		return
	if not bool(sheet.get_meta("open_audio_played", false)):
		sheet.set_meta("open_audio_played", true)
		AudioService.play_sfx("sfx_sheet_open")
	var max_sheet_height := get_viewport_rect().size.y * 0.88
	var natural_choices_height := choice_box.get_combined_minimum_size().y
	var fixed_content_height := float(sheet_box.get_theme_constant("separation")) * float(maxi(0, sheet_box.get_child_count() - 1))
	for child: Node in sheet_box.get_children():
		if child is Control and child != scroll:
			fixed_content_height += (child as Control).get_combined_minimum_size().y
	var sheet_style := sheet.get_theme_stylebox("panel")
	var frame_insets := sheet_style.get_content_margin(SIDE_TOP) + sheet_style.get_content_margin(SIDE_BOTTOM)
	var available_choices_height := maxf(ThemeMaker.TOUCH_MIN, max_sheet_height - fixed_content_height - frame_insets)
	scroll.custom_minimum_size.y = minf(natural_choices_height, available_choices_height)
	var desired_sheet_height := minf(max_sheet_height, fixed_content_height + scroll.custom_minimum_size.y + frame_insets)
	sheet.offset_top = sheet.offset_bottom - desired_sheet_height
	# Record where the panel comes to rest. The coaching overlay sizes its dimming
	# against this rect, and reading the live one mid-slide leaves the shade
	# sitting over the settled sheet.
	var viewport_size := get_viewport_rect().size
	sheet.set_meta("settled_rect", Rect2(
		Vector2(sheet.offset_left, viewport_size.y + sheet.offset_top),
		Vector2(viewport_size.x + sheet.offset_right - sheet.offset_left, desired_sheet_height)
	))
	sheet.position.y += 64
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.2)
	tween.tween_property(sheet, "position:y", sheet.position.y - 64, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Re-resolve once the panel has settled. Resolving mid-slide leaves the
	# spotlight 64u low — straddling two options instead of framing one.
	tween.chain().tween_callback(_refresh_tutorial)

func _show_pending_offline_report() -> void:
	if _offline_report_is_material(Game.last_offline_report):
		_show_offline_dialog(Game.last_offline_report)

func _show_offline_dialog(report: Dictionary) -> void:
	var existing := find_child("OfflineOverlay", true, false)
	if existing != null:
		existing.queue_free()
	var overlay := ColorRect.new()
	overlay.name = "OfflineOverlay"
	overlay.color = Color(0.015, 0.03, 0.06, 0.84)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "OfflineRewardCard"
	card.custom_minimum_size = _safe_modal_size(Vector2(710, 980))
	card.set_meta("viewport_bounded_surface", true)
	card.add_theme_stylebox_override("panel", ThemeMaker.art_panel(false))
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_bottom", 46)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	var title := _label(tr("OFFLINE_TITLE"), 43, ThemeMaker.COLORS.ink)
	ThemeMaker.apply_text_role(title, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var duty_rows := DutyLogScene.compose(report, DataRepository.tables, Game.state)
	if not duty_rows.is_empty():
		var duty_panel := PanelContainer.new()
		duty_panel.name = "DutyLogPanel"
		duty_panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("f5eddd"), Color("d9c69d"), 1, 18))
		var duty_margin := MarginContainer.new()
		duty_margin.add_theme_constant_override("margin_left", 18)
		duty_margin.add_theme_constant_override("margin_top", 12)
		duty_margin.add_theme_constant_override("margin_right", 18)
		duty_margin.add_theme_constant_override("margin_bottom", 12)
		duty_panel.add_child(duty_margin)
		var duty_box := VBoxContainer.new()
		duty_box.add_theme_constant_override("separation", 6)
		duty_margin.add_child(duty_box)
		for index: int in range(duty_rows.size()):
			var row_data: Dictionary = duty_rows[index]
			var row := HBoxContainer.new()
			row.name = "DutyLogRow_%d" % index
			row.custom_minimum_size.y = 42
			row.add_theme_constant_override("separation", 10)
			row.set_meta("duty_log_type", str(row_data.get("type", "")))
			row.set_meta("authoritative_income", float(row_data.get("authoritative_income", -1.0)))
			row.add_child(_icon_view(str(row_data.get("icon_asset", "ic_check")), Vector2(34, 34)))
			var copy := _label(str(row_data.get("text", "")), 20, ThemeMaker.COLORS.ink)
			copy.name = "DutyLogText_%d" % index
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			copy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(copy)
			duty_box.add_child(row)
		box.add_child(duty_panel)
	box.add_child(_coin_pile())
	var income := float(report.get("income", 0.0))
	var prior_balance := float(report.get("balance_before", maxf(0.0, float(Game.state.get("player", {}).get("cash", 0.0)) - income)))
	var celebrate := income > maxf(1.0, prior_balance * 0.20)
	overlay.set_meta("confetti_enabled", celebrate)
	overlay.set_meta("offline_income_ratio", income / maxf(1.0, prior_balance))
	if celebrate:
		_add_era_confetti(overlay)
	var income_label := _label("$0", 48, Color("a96b05"))
	income_label.name = "OfflineIncome"
	income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeMaker.apply_numeric_text(income_label)
	box.add_child(income_label)
	var elapsed := float(report.get("elapsed_seconds", 0.0))
	var credited := float(report.get("credited_seconds", minf(elapsed, Game.offline_income_cap_seconds())))
	var earned := _label(tr("OFFLINE_CREDITED_TIME") % Game.format_duration(credited), 22, ThemeMaker.COLORS.ink)
	earned.name = "OfflineCreditCopy"
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	earned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(earned)
	if elapsed > credited + 1.0:
		var cap_hint := _label(tr("OFFLINE_CAP_NOTICE") % Game.format_duration(credited), 20, Color("725a36"))
		cap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(cap_hint)
	var event_rows := _offline_event_rows(report)
	if not event_rows.is_empty():
		var events_box := VBoxContainer.new()
		events_box.name = "OfflineMilestones"
		events_box.add_theme_constant_override("separation", 6)
		box.add_child(events_box)
		for item: Dictionary in event_rows:
			var event_row := Button.new()
			event_row.name = "OfflineEvent_%s" % str(item.get("type", "unknown"))
			event_row.custom_minimum_size.y = ThemeMaker.TOUCH_MIN
			event_row.focus_mode = Control.FOCUS_NONE
			event_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			event_row.set_meta("offline_action", str(item.get("type", "")))
			event_row.add_theme_stylebox_override("normal", ThemeMaker.panel(Color("f2ead9"), Color("d6c8aa"), 1, 14))
			event_row.add_theme_stylebox_override("hover", ThemeMaker.panel(Color("fff7e7"), ThemeMaker.COLORS.yellow, 2, 14))
			event_row.add_theme_stylebox_override("pressed", ThemeMaker.panel(Color("e8dcc5"), ThemeMaker.COLORS.yellow, 2, 14))
			event_row.pressed.connect(_dismiss_full_overlay.bind(overlay, _run_offline_event.bind(item.duplicate(true))))
			var event_content := HBoxContainer.new()
			event_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
			event_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
			event_content.add_theme_constant_override("separation", 10)
			event_content.add_child(_icon_view(str(item.get("icon", "ic_check")), Vector2(38, 38)))
			var event_text := str(item.get("label", tr(item.get("key", ""))))
			var event_copy := _label("%d · %s" % [int(item.get("count", 0)), event_text], 20, ThemeMaker.COLORS.ink)
			event_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			event_copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			event_content.add_child(event_copy)
			var chevron := _label(">", 28, Color("725a36"))
			chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			event_content.add_child(chevron)
			event_row.add_child(event_content)
			events_box.add_child(event_row)
	var double_button := Widgets.button("%s  ×2" % tr("OFFLINE_DOUBLE"), func() -> void:
		var result := Game.request_reward("offline_double")
		_dismiss_full_overlay(overlay)
		_handle_result(result)
	, "ad")
	double_button.name = "OfflineDoubleButton"
	_set_button_asset(double_button, "ic_play_ad", 44)
	box.add_child(double_button)
	var claim_button := Widgets.button(tr("CLAIM"), _dismiss_full_overlay.bind(overlay), "primary")
	claim_button.name = "OfflineClaimButton"
	box.add_child(claim_button)
	card.pivot_offset = card.custom_minimum_size * 0.5
	card.scale = Vector2.ONE * 0.88
	card.modulate.a = 0.0
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(card, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(card, "modulate:a", 1.0, 0.20)
	Widgets.animate_number(income_label, 0.0, income, func(value: float) -> String: return "$%s" % Game.format_number(value), 1.2)

func _coin_pile() -> Control:
	var pile := Control.new()
	pile.name = "OfflineCoinPile"
	pile.custom_minimum_size = Vector2(0, 150)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index: int in range(7):
		var coin := _icon_view("fx_coin", Vector2(100, 100))
		coin.position = Vector2(220 + float(index % 4) * 52.0 + (26.0 if index >= 4 else 0.0), 50.0 - float(index / 4) * 38.0)
		coin.rotation = -0.22 + float(index) * 0.075
		pile.add_child(coin)
	return pile

func _offline_event_rows(report: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not report.get("completed", []).is_empty():
		var completed: Dictionary = report["completed"][0]
		rows.append({"type": "completed", "icon": "ic_check", "count": report["completed"].size(), "key": "TOAST_CONSTRUCTION_COMPLETE", "datacenter_id": str(completed.get("datacenter_id", "")), "plot_id": str(completed.get("plot_id", ""))})
	if not report.get("faults", []).is_empty():
		var fault: Dictionary = report["faults"][0]
		rows.append({"type": "fault", "icon": "ic_warning", "count": report["faults"].size(), "key": "FAULTED", "datacenter_id": str(fault.get("datacenter_id", "")), "slot": int(fault.get("slot", -1))})
	if not report.get("events", []).is_empty():
		rows.append({"type": "market", "icon": "ic_market_up", "count": report["events"].size(), "key": "NAV_MARKET"})
	if not report.get("inquiries", []).is_empty():
		rows.append({"type": "inquiry", "icon": "ic_contract", "count": report["inquiries"].size(), "label": tr("INQUIRY_OFFLINE_MILESTONE") % report["inquiries"].size()})
	if not report.get("aging", []).is_empty():
		var auto_entries: Array[Dictionary] = []
		var regular_entries: Array[Dictionary] = []
		for aging: Dictionary in report["aging"]:
			if str(aging.get("type", "")) == "datacenter_auto_retired":
				auto_entries.append(aging)
			else:
				regular_entries.append(aging)
		if not auto_entries.is_empty():
			var recovered := 0.0
			for entry: Dictionary in auto_entries:
				recovered += float(entry.get("refund", 0.0)) + float(entry.get("job_refund", 0.0))
			rows.append({"type": "auto_retired", "icon": "ic_retire", "count": auto_entries.size(), "label": tr("OFFLINE_AUTO_RETIRED") % Game.format_number(recovered)})
		if not regular_entries.is_empty():
			var aging: Dictionary = regular_entries[0]
			rows.append({"type": "aging", "icon": "ic_retire", "count": regular_entries.size(), "key": "LIFESPAN", "datacenter_id": str(aging.get("datacenter_id", ""))})
	return rows

func _run_offline_event(item: Dictionary) -> void:
	match str(item.get("type", "")):
		"fault":
			var dc_id := str(item.get("datacenter_id", ""))
			var slot := int(item.get("slot", -1))
			var dc := Game.find_datacenter(dc_id)
			var racks: Array = dc.get("racks", [])
			if slot >= 0 and slot < racks.size() and racks[slot] is Dictionary and str(racks[slot].get("status", "")) == "faulted":
				_show_rack_actions(dc_id, slot)
			else:
				_show_datacenter_context(dc_id)
		"market", "inquiry": _navigate("market")
		"auto_retired": _navigate("map")
		"aging": _show_datacenter_context(str(item.get("datacenter_id", "")))
		_:
			_navigate("map")
			var target_id := str(item.get("datacenter_id", item.get("plot_id", "")))
			if park_map != null and not target_id.is_empty():
				park_map.focus_target(target_id)

func _dismiss_full_overlay(overlay: CanvasItem, after: Callable = Callable()) -> void:
	if not is_instance_valid(overlay) or bool(overlay.get_meta("dismissing", false)):
		return
	overlay.set_meta("dismissing", true)
	# Yield the name immediately. A replacement sheet (picking a rack opens a
	# confirm sheet) is added while this one is still animating out, and Godot
	# silently renames the newcomer on a name collision — which made every
	# lookup by name, the tutorial's target resolution included, keep finding
	# the sheet on its way out instead of the live one.
	if overlay is Node:
		(overlay as Node).name = "Dismissed%s" % (overlay as Node).name
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 0.20)
	tween.tween_callback(func() -> void:
		overlay.queue_free()
		if after.is_valid():
			after.call()
	)

func _offline_events_summary(report: Dictionary) -> String:
	var lines: Array[String] = []
	if not report.get("completed", []).is_empty(): lines.append("%d %s" % [report["completed"].size(), tr("TOAST_CONSTRUCTION_COMPLETE")])
	if not report.get("faults", []).is_empty(): lines.append("%d %s" % [report["faults"].size(), tr("FAULTED")])
	if not report.get("events", []).is_empty(): lines.append("%d %s" % [report["events"].size(), tr("NAV_MARKET")])
	if not report.get("inquiries", []).is_empty(): lines.append(tr("INQUIRY_OFFLINE_MILESTONE") % report["inquiries"].size())
	var renewed_count := 0
	var has_free_switch := false
	for contract: Dictionary in report.get("contracts", []):
		if str(contract.get("type", "")) == "contract_auto_renewed":
			renewed_count += 1
			has_free_switch = has_free_switch or bool(contract.get("free_switch_available", false))
	if renewed_count > 0: lines.append(tr("OFFLINE_AUTO_RENEWED") % renewed_count)
	if has_free_switch: lines.append(tr("OFFLINE_FREE_SWITCH_READY"))
	return "\n".join(lines)

func _confirm_prestige() -> void:
	var projection := _prestige_projection()
	var summary := Game.company_legacy_summary()
	var body := "%s\n%s\n%s\n%s" % [
		tr("LEGACY_RECAP_BODY") % [Game.format_number(float(summary.get("total_revenue", 0.0))), Game.format_number(float(summary.get("net_worth", 0.0))), int(summary.get("datacenters_built", 0))],
		tr("PRESTIGE_GAIN_DETAIL") % [float(projection.get("current", 1.0)), float(projection.get("projected", 1.0))],
		tr("PRESTIGE_KEEP_LIST"),
		tr("PRESTIGE_LIQUIDATE") % Game.format_number(float(projection.get("worth", 0.0))),
	]
	_present_action_sheet(tr("LEGACY_RECAP"), body, [{"id": "continue", "text": tr("PRESTIGE_CONTINUE"), "color": ThemeMaker.COLORS.purple, "asset": "legacy_memorial"}], func(choice: String) -> void:
		if choice == "continue":
			_present_action_sheet(tr("PRESTIGE_FINAL_TITLE"), tr("PRESTIGE_FINAL_WARNING"), [{"id": "confirm", "text": tr("PRESTIGE_HOLD_CONFIRM"), "color": ThemeMaker.COLORS.red, "hold_seconds": 1.2}], func(final_choice: String) -> void:
				if final_choice == "confirm":
					_handle_result(Game.prestige())
			)
	)

func _confirm_reset() -> void:
	_confirm(tr("SETTINGS_RESET"), tr("SETTINGS_RESET_WARNING"), func() -> void:
		Game.start_new_company()
		_navigate("map")
	)

func _confirm(title_text: String, body: String, callback: Callable, tutorial_focus: String = "") -> void:
	var choices: Array[Dictionary] = [{"id": "confirm", "text": tr("CONFIRM"), "color": ThemeMaker.COLORS.red}]
	var confirm_action := func(choice: String) -> void:
		if choice == "confirm":
			callback.call()
	_present_action_sheet(title_text, body, choices, confirm_action, ThemeMaker.COLORS.cyan, tutorial_focus)

func _navigate(page: String) -> void:
	if fx_layer != null:
		fx_layer.clear()
	if page == active_page:
		if page == "map" and park_map != null:
			park_map.reset_camera()
		return
	active_page = page
	if page != "detail": selected_datacenter_id = ""
	if page == "map" and park_map != null:
		park_map.reset_camera()
	_haptic(HAPTIC_LIGHT)
	if Game.state.get("bankruptcy", {}).get("status", "normal") == "normal":
		_play_music("music_market" if page == "market" else "music_main")
	_request_full_refresh()

func _desired_music_cue() -> String:
	if Game.state.get("bankruptcy", {}).get("status", "normal") == "arrears":
		return "music_crisis"
	return "music_market" if active_page == "market" else "music_main"

func _play_music(cue_id: String, crossfade: bool = true) -> void:
	if not AudioService.music_enabled or AudioService.music_player == null:
		return
	var items: Dictionary = AudioService.manifest.get("items", {})
	var cue: Dictionary = items.get(cue_id, {})
	var path := str(cue.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer = AudioService.music_player
	if _music_target == cue_id and player.playing:
		return
	var target_db: float = float(cue.get("volume_db", -8.0))
	if _music_fade_tween != null and _music_fade_tween.is_valid():
		_music_fade_tween.kill()
	if not crossfade or player.stream == null or not player.playing:
		AudioService.play_music(cue_id)
		_music_target = cue_id
		return
	_music_target = cue_id
	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(player, "volume_db", -40.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_music_fade_tween.tween_callback(func() -> void:
		AudioService.play_music(cue_id)
		if player.stream != null:
			player.volume_db = -40.0
	)
	_music_fade_tween.tween_property(player, "volume_db", target_db, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _open_datacenter(datacenter_id: String) -> void:
	_show_datacenter_context(datacenter_id)

func _open_datacenter_detail(datacenter_id: String, focus: String = "racks") -> void:
	if Game.find_datacenter(datacenter_id).is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	selected_datacenter_id = datacenter_id
	_detail_focus = "board" if focus in ["racks", "infrastructure"] else focus
	active_page = "detail"
	_request_full_refresh()

func _demolish(datacenter_id: String) -> void:
	_handle_result(Game.demolish_ruin(datacenter_id))

func _retire(datacenter_id: String) -> void:
	var complete_retirement := func() -> void:
		var source := park_map.world_position_of(datacenter_id) if park_map != null else Vector2.ZERO
		var result := Game.retire_datacenter(datacenter_id)
		_handle_result(result)
		if bool(result.get("ok", false)):
			_fly_cash_reward(source, 8)
		_navigate("map")
	_confirm(tr("RETIRE"), tr("RETIRE"), complete_retirement, "retire_dc")

func _sign_contract(datacenter_id: String, customer_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	if str(dc.get("power_unit", "")).is_empty():
		_handle_result({"ok": false, "reason": "power_required"}, {"datacenter_id": datacenter_id, "operation": "contract"})
		return
	if _contract_capacity_state(dc) != "ready":
		_handle_result({"ok": false, "reason": "contract_capacity_required"}, {"datacenter_id": datacenter_id, "operation": "contract"})
		return
	if not bool(Game.state.get("tutorial", {}).get("completed", false)):
		_confirm_contract_duration(datacenter_id, customer_id, "standard")
		return
	var relationship := Rules.relationship_level(customer_id, Game.state, Game.data)
	var relationship_index := int(relationship.get("index", 0))
	var choices: Array[Dictionary] = []
	for duration_id: String in DataRepository.get_table("meta_progression").get("contract_durations", {}):
		var duration: Dictionary = DataRepository.get_table("meta_progression")["contract_durations"][duration_id]
		var forecast := Game.contract_forecast(datacenter_id, customer_id, duration_id)
		var available := relationship_index >= int(duration.get("relationship_level_required", 0))
		var term_value := float(forecast.get("projected", 0.0)) * float(forecast.get("months", 0.0)) - float(forecast.get("fee", 0.0))
		var choice_text := "%s\n%s\n%s" % [tr(str(duration.get("name_key", ""))), tr(str(duration.get("description_key", ""))), tr("CONTRACT_TERM_PROJECTION") % [Game.format_number(float(forecast.get("projected", 0.0))), Game.format_number(term_value)]]
		var event_seconds := float(forecast.get("prorated_event_seconds", 0.0))
		if event_seconds > 0.0:
			var month_seconds := float(DataRepository.get_table("economy").get("time", {}).get("real_seconds_per_game_month", 7200.0))
			choice_text += "\n" + tr("CONTRACT_PRORATED_EVENT") % (event_seconds / month_seconds)
		if bool(forecast.get("lock_cap_applied", false)):
			choice_text += "\n" + tr("CONTRACT_STRATEGIC_CAP") % float(forecast.get("strategic_lock_cap", 2.5))
		choices.append({
			"id": duration_id,
			"height": 126 + (24 if event_seconds > 0.0 else 0) + (24 if bool(forecast.get("lock_cap_applied", false)) else 0),
			"asset": "customer_portfolio" if available else "ic_lock",
			"available": available,
			"text": choice_text,
			"color": Color("29445c") if available else Color("475466"),
		})
	_present_action_sheet(tr("CONTRACT_CHOOSE_DURATION"), tr("RELATIONSHIP_STATUS") % [tr(str(relationship.get("name_key", "RELATIONSHIP_NEW"))), float(relationship.get("income_multiplier", 1.0))], choices, func(duration_id: String) -> void:
		var duration: Dictionary = DataRepository.get_table("meta_progression").get("contract_durations", {}).get(duration_id, {})
		if relationship_index < int(duration.get("relationship_level_required", 0)):
			_handle_result({"ok": false, "reason": "relationship_required"})
			return
		_confirm_contract_duration(datacenter_id, customer_id, duration_id)
	, ThemeMaker.COLORS.cyan, "contract_internet")

func _confirm_contract_duration(datacenter_id: String, customer_id: String, duration_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		_handle_result({"ok": false, "reason": "datacenter_missing"})
		return
	var forecast := Game.contract_forecast(datacenter_id, customer_id, duration_id)
	var current := float(forecast.get("current", 0.0))
	var projected := float(forecast.get("projected", 0.0))
	var fee := float(forecast.get("fee", 0.0))
	var percent := (projected / maxf(0.01, current) - 1.0) * 100.0 if current > 0.0 else 100.0
	var body := tr("CONTRACT_CONFIRM_DELTA") % [Game.format_number(current), Game.format_number(projected), percent]
	body += "\n" + (tr("CONTRACT_FREE_SWITCH") if fee <= 0.0 else tr("CONTRACT_BREACH_FEE") % Game.format_number(fee))
	body += "\n" + tr("CONTRACT_TERM_GAIN") % Game.format_number(float(forecast.get("term_gain", 0.0)))
	var event_seconds := float(forecast.get("prorated_event_seconds", 0.0))
	if event_seconds > 0.0:
		var month_seconds := float(DataRepository.get_table("economy").get("time", {}).get("real_seconds_per_game_month", 7200.0))
		body += "\n" + tr("CONTRACT_PRORATED_EVENT") % (event_seconds / month_seconds)
	if bool(forecast.get("lock_cap_applied", false)):
		body += "\n" + tr("CONTRACT_STRATEGIC_CAP") % float(forecast.get("strategic_lock_cap", 2.5))
	var confirm_contract := func(choice: String) -> void:
		if choice == "confirm":
			_complete_contract_signing(datacenter_id, customer_id, duration_id)
	_present_action_sheet(tr("SWITCH_CONTRACT"), body, [{"id": "confirm", "text": "%s · %s" % [tr("CONFIRM"), tr("CONTRACT_PROJECTED") % Game.format_number(projected)], "color": ThemeMaker.COLORS.green}], confirm_contract, ThemeMaker.COLORS.cyan, "contract_internet")

func _complete_contract_signing(datacenter_id: String, customer_id: String, duration_id: String = "standard") -> void:
	var result := Game.sign_contract(datacenter_id, customer_id, duration_id)
	_handle_result(result)
	if bool(result.get("ok", false)):
		var source := park_map.world_position_of(datacenter_id) if park_map != null else Vector2.ZERO
		_fly_cash_reward(source, 5)

func _speedup_job(construction_id: String) -> void:
	_handle_result(Game.speed_up_construction_with_gems(construction_id))

func _reward_job(construction_id: String) -> void:
	_handle_result(Game.request_reward("construction:%s" % construction_id))

func _use_ticket(construction_id: String) -> void:
	_handle_result(Game.use_instant_build_ticket(construction_id))

func _upgrade_network(unlock_era: int = 0) -> void:
	_handle_result(Game.upgrade_network(), {"unlock_era": unlock_era})

func _upgrade_repair(unlock_era: int = 0) -> void:
	_handle_result(Game.upgrade_repair_team(), {"unlock_era": unlock_era})

func _purchase_construction_bays(unlock_era: int = 0, minimum_prestige: int = 0) -> void:
	_handle_result(Game.purchase_construction_bays(), {"unlock_era": unlock_era, "minimum_prestige": minimum_prestige})

func _purchase_auto_retirement(unlock_era: int = 0) -> void:
	_handle_result(Game.purchase_auto_retirement(), {"unlock_era": unlock_era})

func _purchase(product_id: String) -> void:
	# StoreKit completion owns the final success/failure toast and its semantic
	# sound. Avoid a second generic success chime while the transaction is pending.
	if OS.get_name() == "iOS" and not Monetization.is_product_available(product_id):
		_handle_result({"ok": false, "reason": "product_unavailable"})
		return
	var result := Game.purchase(product_id)
	if not bool(result.get("ok", false)):
		_handle_result(result)
	else:
		_request_hud_refresh()

func _on_setting_toggled(enabled: bool, setting_key: String) -> void:
	Game.set_audio_setting(setting_key, enabled)
	if setting_key == "music_enabled":
		if enabled:
			_music_target = ""
			_play_music(_desired_music_cue(), false)
		elif _music_fade_tween != null and _music_fade_tween.is_valid():
			_music_fade_tween.kill()
			_music_target = ""

func _run_action(action: Callable) -> void:
	_handle_result(action.call())

func _mark_explained_unavailable(button: Button, reason: String, context: Dictionary = {}) -> void:
	# Never use Button.disabled for a gameplay restriction on mobile.  A muted
	# button remains an 88u touch target and its existing action can surface the
	# authoritative gameplay failure through _handle_result.
	button.set_meta("availability_locked", true)
	button.set_meta("unavailable_reason", reason)
	button.set_meta("unavailable_context", context.duplicate(true))
	ThemeMaker.apply_button_role(button, "disabled")
	button.modulate = Color(0.82, 0.86, 0.90, 1.0)

func _handle_result(result: Dictionary, context: Dictionary = {}) -> void:
	if bool(result.get("ok", false)):
		_haptic(HAPTIC_MEDIUM)
		_show_toast(tr("TOAST_CONSTRUCTION_STARTED") if result.has("construction") or result.has("rack_installation") else tr("CONFIRM"), "sfx_success_chime")
		if result.has("plot_id"):
			_deferred_focus_world_target(str(result.get("plot_id", "")))
	else:
		_haptic(HAPTIC_LIGHT)
		var reason := str(result.get("reason", "unknown"))
		_show_toast(_failure_message(reason, context), "sfx_error_thud")
		if reason == "queue_full":
			_pulse_queue_feedback()
	_request_hud_refresh()

func _deferred_focus_world_target(target_id: String) -> void:
	# Plot purchase schedules a full state refresh. Wait for the rebuilt target
	# dictionary, then reveal the campus that owns the newly purchased parcel.
	await get_tree().process_frame
	await get_tree().process_frame
	if active_page == "map" and park_map != null and not target_id.is_empty():
		park_map.focus_target(target_id)

func _reason_text(reason: String) -> String:
	var keys := {
		"not_enough_cash": "REASON_NOT_ENOUGH_CASH", "not_enough_gems": "REASON_NOT_ENOUGH_GEMS", "locked": "REASON_LOCKED",
		"power_required": "REASON_POWER_REQUIRED", "contract_capacity_required": "REASON_CONTRACT_CAPACITY_REQUIRED",
		"queue_full": "REASON_QUEUE_FULL", "plot_unavailable": "REASON_PLOT_UNAVAILABLE",
		"tutorial_building_retired": "REASON_TUTORIAL_BUILDING_RETIRED",
		"datacenter_missing": "REASON_DATACENTER_MISSING", "datacenter_unavailable": "REASON_DATACENTER_UNAVAILABLE",
		"slot_locked": "REASON_SLOT_LOCKED", "slot_occupied": "REASON_SLOT_OCCUPIED", "slot_empty": "REASON_SLOT_EMPTY",
		"invalid_slot": "REASON_INVALID_SLOT", "invalid_edge": "REASON_INVALID_EDGE",
		"rack_install_limit": "REASON_RACK_INSTALL_LIMIT", "rack_unavailable": "REASON_RACK_UNAVAILABLE",
		"too_new_to_retire": "REASON_TOO_NEW_TO_RETIRE", "cooler_slots_full": "REASON_COOLER_SLOTS_FULL", "building_tier_too_low": "REASON_BUILDING_TIER_TOO_LOW",
		"construction_in_progress": "REASON_IN_PROGRESS", "not_an_upgrade": "REASON_NOT_UPGRADE",
		"construction_missing": "REASON_CONSTRUCTION_MISSING", "not_faulted": "REASON_NOT_FAULTED", "not_ruined": "REASON_NOT_RUINED",
		"prestige_locked": "REASON_PRESTIGE_LOCKED",
		"relationship_required": "REASON_RELATIONSHIP_REQUIRED", "board_points_empty": "REASON_BOARD_POINTS_EMPTY",
		"board_rank_max": "REASON_BOARD_RANK_MAX", "already_claimed": "REASON_ALREADY_CLAIMED",
		"collection_incomplete": "REASON_COLLECTION_INCOMPLETE",
		"reward_unavailable": "REASON_REWARD_UNAVAILABLE", "reward_limit": "REASON_REWARD_LIMIT", "ticket_unavailable": "REASON_TICKET",
		"reward_pending": "REASON_IN_PROGRESS",
		"already_owned": "REASON_ALREADY_OWNED", "purchase_limit": "REASON_ALREADY_OWNED", "purchase_pending": "REASON_PURCHASE_PENDING",
		"product_unavailable": "REASON_PRODUCT_UNAVAILABLE", "unknown": "REASON_UNKNOWN",
		"inquiry_unavailable": "REASON_INQUIRY_UNAVAILABLE", "inquiry_requirements": "REASON_INQUIRY_REQUIREMENTS",
		"inquiry_quote_stale": "REASON_INQUIRY_QUOTE_STALE",
	}
	return tr(keys.get(reason, "REASON_UNKNOWN"))

func _failure_message(reason: String, context: Dictionary = {}) -> String:
	if reason == "locked" and int(context.get("unlock_era", 0)) > 0:
		if int(context.get("minimum_prestige", 0)) > int(Game.state.get("stats", {}).get("prestige_count", 0)):
			return tr("REASON_LOCKED_PRESTIGE") % int(context.get("minimum_prestige", 0))
		return tr("REASON_LOCKED_ERA") % int(context.get("unlock_era", 0))
	if reason == "queue_full":
		var queue: Array = Game.state.get("construction_queue", [])
		var capacity := Game.queue_capacity()
		var earliest := INF
		for item: Dictionary in queue:
			earliest = minf(earliest, float(item.get("complete_at", INF)))
		var remaining := maxf(0.0, earliest - Game.simulation_time()) if earliest < INF else 0.0
		return tr("REASON_QUEUE_FULL_DETAIL") % [queue.size(), capacity, Game.format_duration(remaining)]
	if reason == "rack_install_limit":
		var dc := Game.find_datacenter(str(context.get("datacenter_id", "")))
		var earliest := INF
		for installed: Variant in dc.get("racks", []):
			if installed is Dictionary and str((installed as Dictionary).get("status", "")) == "installing":
				earliest = minf(earliest, float((installed as Dictionary).get("install_complete_at", INF)))
		if earliest < INF:
			return tr("REASON_RACK_INSTALL_LIMIT_DETAIL") % Game.format_duration(maxf(0.0, earliest - Game.simulation_time()))
	return _reason_text(reason)

func _pulse_queue_feedback() -> void:
	if task_button == null or not is_instance_valid(task_button) or not task_button.is_visible_in_tree():
		return
	task_button.pivot_offset = task_button.size * 0.5
	var tween := task_button.create_tween()
	tween.tween_property(task_button, "scale", Vector2.ONE * 1.08, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(task_button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_state_changed(reason: String) -> void:
	if reason in ["tick", "offline_advance"]:
		_request_hud_refresh()
	else:
		_request_full_refresh()

func _on_toast_requested(key: String, values: Dictionary) -> void:
	var text := tr(key)
	if values.has("name"):
		text = text % values["name"]
	_show_toast(text)

func _on_offline_settled(report: Dictionary) -> void:
	if is_node_ready() and _offline_report_is_material(report):
		if float(report.get("income", 0.0)) >= 1.0:
			AudioService.play_sfx("sfx_cash")
			_fly_cash_reward(Vector2.ZERO, 8)
		_show_offline_dialog(report)

func _on_construction_completed(item: Dictionary) -> void:
	_show_toast(tr("TOAST_CONSTRUCTION_COMPLETE"))
	var target_id := str(item.get("plot_id", item.get("datacenter_id", "")))
	_fly_cash_reward(park_map.world_position_of(target_id) if park_map != null else Vector2.ZERO, 8)
	_haptic(HAPTIC_MEDIUM)
	# Tick-only refreshes intentionally preserve the world tree. Completion is
	# the exception: rebuild once, then stage the transition against the new art.
	_request_full_refresh()
	var completed := item.duplicate(true)
	get_tree().create_timer(0.30).timeout.connect(_present_construction_completion.bind(completed))

func _present_construction_completion(item: Dictionary) -> void:
	if park_map == null or not is_instance_valid(park_map):
		return
	var item_type := str(item.get("type", ""))
	var target_id := str(item.get("plot_id", item.get("datacenter_id", "")))
	match item_type:
		"datacenter": park_map.play_construction_completion(target_id)
		"power": park_map.play_power_on(target_id)
		_:
			_play_fx_at_world("fx_dust_puff", target_id, 190)
			park_map.celebrate_target(target_id)

func _on_rack_fault_occurred(datacenter_id: String, _slot: int) -> void:
	_play_fx_at_world("fx_spark", datacenter_id, 170)
	_haptic(HAPTIC_HEAVY)

func _on_contract_auto_renewed(_datacenter_id: String, _customer_id: String, _contract_end_at: float) -> void:
	_show_toast(tr("TOAST_CONTRACT_RENEWAL"))
	_request_full_refresh()

func _on_relationship_level_changed(customer_id: String, level_index: int) -> void:
	if not bool(Game.state.get("tutorial", {}).get("completed", false)):
		return
	var persona := PersonaSystemScene.default_persona(customer_id, DataRepository.tables)
	for plot: Dictionary in Game.state.get("plots", []):
		var dc: Variant = plot.get("datacenter")
		if dc is Dictionary and str((dc as Dictionary).get("customer_id", "")) == customer_id:
			persona = PersonaSystemScene.persona_for_contract(dc, DataRepository.tables)
	if persona.is_empty():
		return
	var levels: Array = DataRepository.get_table("meta_progression").get("relationships", {}).get("levels", [])
	if level_index < 0 or level_index >= levels.size():
		return
	var level: Dictionary = levels[level_index]
	var headline := tr("PERSONA_LEVEL_TOAST") % [tr(str(persona.get("name_key", ""))), tr(str(level.get("name_key", "RELATIONSHIP_NEW")))]
	var line_key := PersonaSystemScene.line_key(persona, "level_up", str(level_index))
	var message := "%s\n%s" % [headline, tr(line_key)] if not line_key.is_empty() else headline
	_show_persona_toast(persona, message, "sfx_success_chime")

func _on_datacenter_entered_aging(datacenter_id: String) -> void:
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	if index < 0 or index >= steps.size() or str((steps[index] as Dictionary).get("id", "")) != "retire":
		return
	_retire_tutorial_awake = true
	_retire_notice_collapsed = false
	_retire_notice_token += 1
	_tutorial_protocol_step = -1
	selected_datacenter_id = datacenter_id
	_show_toast(tr("TUTORIAL_RETIRE_READY"), "sfx_success_chime")
	_request_full_refresh()

func _on_market_event_started(event_id: String) -> void:
	_show_market_banner(event_id, true)
	match event_id:
		"industry_winter":
			_play_fx("fx_frost_patch")
			_play_fx("fx_snowflake", 250)
		"digital_wave": _play_fx("fx_wind_streak")
		"mining_crash", "policy_tightening": _play_fx("fx_smoke_puff")
		# A coin_boom used to spawn a 100u rack coin in the middle of the road.
		# The event banner, market page and per-building benefit badge are the
		# semantic feedback; a context-free world coin is actively misleading.
		"coin_boom": pass
		# Market news already owns the semantic feedback.  A context-free neon
		# ring over the campus looked like a second construction explosion.
		"ai_model_boom": pass
		_: pass

func _on_market_event_ended(event_id: String) -> void:
	_show_market_banner(event_id, false)

# The banner is a map-level alert. A system page or a modal owns the whole
# screen while it is open, so raising the banner there would clip the page's own
# header; hold the newest one and raise it when the player is back on the map.
func _show_market_banner(event_id: String, started: bool) -> void:
	if _market_banner_would_be_buried():
		_pending_market_banner = {"event_id": event_id, "started": started}
		return
	_present_market_banner(event_id, started)

# Only the surfaces that own the entire screen. Sheets and the data-center
# drawer sit below the band and leave the banner readable.
func _market_banner_would_be_buried() -> bool:
	if active_page != "map":
		return true
	for overlay_name: String in ["OfflineOverlay", "EraOverlay", "BankTakeoverOverlay"]:
		var overlay := find_child(overlay_name, true, false) as CanvasItem
		if overlay != null and overlay.is_visible_in_tree():
			return true
	return false

# A system page owns the canvas.  Clear the temporary wording there; the market
# state itself remains available when the player comes back to the map.
func _sync_market_banner() -> void:
	if _market_banner_would_be_buried():
		# A full-screen modal will pass; the banner is only retired when the
		# player has actually navigated off the map.
		if active_page != "map":
			_dismiss_market_notice(false)
		return
	if _pending_market_banner.is_empty():
		return
	var pending := _pending_market_banner
	_pending_market_banner = {}
	_present_market_banner(str(pending.get("event_id", "")), bool(pending.get("started", false)))

func _reflow_market_banners() -> void:
	# The unified notice is permanently anchored in the safe top band.
	pass

func _retire_market_banners() -> void:
	_dismiss_market_notice(false)

func _present_market_banner(event_id: String, started: bool) -> void:
	var event := DataRepository.get_entry("events", event_id)
	_news_notice_token += 1
	var token := _news_notice_token
	_news_notice_rare = bool(event.get("rare", false)) and started
	_news_notice_message = tr("MARKET_RARE_EVENT_STARTED" if _news_notice_rare else ("MARKET_EVENT_STARTED" if started else "MARKET_EVENT_ENDED")) % tr(event.get("name_key", ""))
	_refresh_hud()
	if news_panel != null:
		news_panel.modulate.a = 0.74
		var pulse := news_panel.create_tween()
		pulse.tween_property(news_panel, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(4.0).timeout.connect(_expire_market_notice.bind(token))

func _expire_market_notice(token: int) -> void:
	if token == _news_notice_token:
		_dismiss_market_notice()

func _dismiss_market_notice(refresh: bool = true) -> void:
	_news_notice_token += 1
	_news_notice_message = ""
	_news_notice_rare = false
	if news_panel != null:
		news_panel.modulate.a = 1.0
		news_panel.scale = Vector2.ONE
		news_panel.set_meta("transient_market_notice", false)
	if refresh and is_node_ready():
		_refresh_hud()

# Kept as a compatibility route for older audit helpers; there is no longer a
# separate banner node to remove.
func _dismiss_market_banner(_banner: Control = null) -> void:
	_dismiss_market_notice()

func _on_reward_granted(_placement: String, _payload: Dictionary) -> void:
	AudioService.play_sfx("sfx_cash")
	_fly_cash_reward(Vector2.ZERO, 8)
	_haptic(HAPTIC_SUCCESS)

func _fly_cash_reward(source: Vector2, count: int) -> void:
	if fx_layer == null or cash_label == null:
		return
	var chip := _cash_chip_target()
	if _world_reward_fx_available(source):
		fx_layer.fly_coins(source, chip, count)
	else:
		fx_layer.pulse_target(chip)

func _world_reward_fx_available(source: Vector2) -> bool:
	if active_page != "map" or source == Vector2.ZERO:
		return false
	if tutorial_overlay != null and tutorial_overlay.visible:
		return false
	return not _blocking_surface_visible()

func _blocking_surface_visible() -> bool:
	for overlay_name: String in ["ActionSheetOverlay", "BuildingPicker", "DatacenterContext", "OperationsHub", "OfflineOverlay", "EraOverlay", "BankTakeoverOverlay"]:
		var overlay := find_child(overlay_name, true, false) as CanvasItem
		if overlay != null and overlay.is_visible_in_tree():
			return true
	return false

func _cash_chip_target() -> Control:
	var chip := find_child("CashResource", true, false) as Control
	return chip if chip != null else cash_label

func _on_world_alert_selected(datacenter_id: String, alert_type: String, slot: int) -> void:
	match alert_type:
		"fault": _show_rack_actions(datacenter_id, slot)
		"unpowered": _show_attachment_picker(datacenter_id, "power", "")
		"contract": _open_datacenter_detail(datacenter_id, "contracts")
		"overheat": _open_datacenter_detail(datacenter_id, "racks")
		"market": _show_datacenter_context(datacenter_id)
		_: _show_datacenter_context(datacenter_id)

func _offline_report_is_material(report: Dictionary) -> bool:
	if float(report.get("elapsed_seconds", 0.0)) < 60.0:
		return false
	return float(report.get("income", 0.0)) >= 1.0 or not report.get("completed", []).is_empty() or not report.get("faults", []).is_empty() or not report.get("events", []).is_empty() or not report.get("inquiries", []).is_empty() or not report.get("contracts", []).is_empty() or not report.get("aging", []).is_empty()

func _on_era_unlocked(era_id: int) -> void:
	_play_fx("fx_confetti_set", 680)
	_haptic(HAPTIC_SUCCESS)
	if era_id not in _era_overlay_queue:
		_era_overlay_queue.append(era_id)
	_present_next_era_overlay()

func _queue_unseen_era_overlays() -> void:
	var seen := int(Game.state.get("flags", {}).get("last_presented_era", 1))
	var current := int(Game.state.get("player", {}).get("era", 1))
	for era_id: int in range(seen + 1, current + 1):
		if era_id not in _era_overlay_queue:
			_era_overlay_queue.append(era_id)
	_present_next_era_overlay()

func _present_next_era_overlay() -> void:
	if _era_overlay_open or _era_overlay_queue.is_empty():
		return
	var era_id: int = int(_era_overlay_queue.pop_front())
	_era_overlay_open = true
	_show_era_overlay(era_id, DataRepository.get_entry("eras", str(era_id)))

func _show_pending_bankruptcy_state() -> void:
	var status := str(Game.state.get("bankruptcy", {}).get("status", "normal"))
	if bool(Game.state.get("bankruptcy", {}).get("takeover_notice_pending", false)):
		_on_bankruptcy_state_changed("takeover")
	elif status == "arrears":
		_on_bankruptcy_state_changed(status)

func _on_bankruptcy_state_changed(status: String) -> void:
	if status == "arrears":
		# A new arrears episode may alert the player once.  Refreshes inside the
		# same episode must respect an explicit dismissal and never rebuild the
		# blocking banner over whichever management page they are using.
		_arrears_banner_dismissed = false
		_show_toast(tr("BANKRUPTCY_WARNING"))
		_play_music("music_crisis")
		_show_arrears_hud()
	elif status == "normal":
		_arrears_banner_dismissed = false
		_clear_crisis_hud()
		_play_music("music_main")
	elif status == "takeover":
		_arrears_banner_dismissed = false
		_clear_crisis_hud()
		_play_music("music_main")
		_show_bank_takeover_overlay()

func _refresh_arrears_hud() -> void:
	var status := str(Game.state.get("bankruptcy", {}).get("status", "normal"))
	if status != "arrears":
		if status == "normal":
			_clear_crisis_hud()
		return
	if _arrears_banner_dismissed:
		_clear_crisis_hud()
		return
	var banner := find_child("ArrearsBanner", true, false) as PanelContainer
	if banner == null:
		_show_arrears_hud()
		banner = find_child("ArrearsBanner", true, false) as PanelContainer
	if banner == null:
		return
	var bankruptcy: Dictionary = Game.state.get("bankruptcy", {})
	var limit := float(DataRepository.get_table("economy").get("bankruptcy", {}).get("takeover_after_online_seconds", 21600.0))
	var elapsed := float(bankruptcy.get("arrears_online_seconds", 0.0))
	var debt_label := banner.find_child("DebtValue", true, false) as Label
	var time_label := banner.find_child("ArrearsTime", true, false) as Label
	var progress := banner.find_child("ArrearsProgress", true, false) as ProgressBar
	if debt_label != null:
		debt_label.text = tr("ARREARS_BANNER") % Game.format_number(float(bankruptcy.get("debt", 0.0)))
	if time_label != null:
		time_label.text = tr("ARREARS_TIME_LEFT") % Game.format_duration(maxf(0.0, limit - elapsed))
	if progress != null:
		progress.max_value = limit
		progress.value = elapsed

func _show_arrears_hud() -> void:
	if _arrears_banner_dismissed or find_child("ArrearsBanner", true, false) != null:
		return
	var vignette := PanelContainer.new()
	vignette.name = "ArrearsVignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = 84
	var vignette_style := ThemeMaker.panel(Color.TRANSPARENT, Color(ThemeMaker.COLORS.red, 0.80), 8, 0)
	vignette_style.content_margin_left = 0
	vignette_style.content_margin_top = 0
	vignette_style.content_margin_right = 0
	vignette_style.content_margin_bottom = 0
	vignette.add_theme_stylebox_override("panel", vignette_style)
	add_child(vignette)
	var pulse := vignette.create_tween().set_loops()
	pulse.tween_property(vignette, "modulate:a", 0.42, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(vignette, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	var banner := PanelContainer.new()
	banner.name = "ArrearsBanner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 32
	# This is a global emergency layer, so its top must include the desktop/mobile
	# safe area and the persistent resource rail. It may cover page content, but
	# never the HUD that explains the player's remaining resources.
	var banner_top := _safe_area_margins().y + 108.0
	banner.offset_top = banner_top
	banner.offset_right = -32
	banner.offset_bottom = banner_top
	banner.z_index = 86
	var crisis_style := ThemeMaker.panel(Color("171c27", 0.98), Color(ThemeMaker.COLORS.red, 0.72), 2, ThemeMaker.RADIUS.card)
	crisis_style.content_margin_left = ThemeMaker.GROUP_PADDING
	crisis_style.content_margin_top = ThemeMaker.GROUP_PADDING
	crisis_style.content_margin_right = ThemeMaker.GROUP_PADDING
	crisis_style.content_margin_bottom = ThemeMaker.GROUP_PADDING
	banner.add_theme_stylebox_override("panel", crisis_style)
	add_child(banner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	banner.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	top.add_child(_icon_view("ic_bankrupt", Vector2(54, 54)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(copy)
	var debt := _label("", 24, Color.WHITE)
	debt.name = "DebtValue"
	copy.add_child(debt)
	var time_left := _label("", ThemeMaker.TYPE_SCALE.caption, Color("ffe7bf"))
	time_left.name = "ArrearsTime"
	copy.add_child(time_left)
	var close := Widgets.close_button(_dismiss_arrears_hud)
	close.name = "ArrearsCloseButton"
	close.tooltip_text = tr("CLOSE")
	top.add_child(close)
	var progress := ProgressBar.new()
	progress.name = "ArrearsProgress"
	progress.show_percentage = false
	progress.custom_minimum_size.y = 40
	var progress_background := ThemeMaker.panel(Color("1a202a"), Color(1, 1, 1, 0.12), 1, 20)
	progress_background.content_margin_left = 0
	progress_background.content_margin_right = 0
	progress_background.content_margin_top = 0
	progress_background.content_margin_bottom = 0
	var progress_fill := ThemeMaker.panel(ThemeMaker.COLORS.red, Color(1, 1, 1, 0.20), 1, 20)
	progress_fill.content_margin_left = 0
	progress_fill.content_margin_right = 0
	progress_fill.content_margin_top = 0
	progress_fill.content_margin_bottom = 0
	progress.add_theme_stylebox_override("background", progress_background)
	progress.add_theme_stylebox_override("fill", progress_fill)
	box.add_child(progress)
	var rescue := Widgets.button(tr("ARREARS_RESCUE"), _claim_arrears_rescue, "primary")
	rescue.name = "ArrearsRescueButton"
	_set_button_asset(rescue, "ic_play_ad", 36)
	box.add_child(rescue)
	call_deferred("_fit_arrears_banner", banner)
	_refresh_arrears_hud()
	var final_y := banner.position.y
	banner.position.y = final_y - 240.0
	banner.create_tween().tween_property(banner, "position:y", final_y, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _fit_arrears_banner(banner: PanelContainer) -> void:
	if not is_instance_valid(banner):
		return
	banner.offset_bottom = banner.offset_top + banner.get_combined_minimum_size().y

func _claim_arrears_rescue() -> void:
	var result := Game.request_reward("arrears_rescue")
	_handle_result(result)
	# Once the daily route is exhausted, the explanation toast is the useful
	# feedback.  Keeping the emergency card pinned above the page only traps the
	# player behind an action that cannot succeed, so collapse it immediately.
	if not bool(result.get("ok", false)) and str(result.get("reason", "")) == "reward_limit":
		_dismiss_arrears_hud()

func _dismiss_arrears_hud() -> void:
	_arrears_banner_dismissed = true
	_clear_crisis_hud()

func _clear_crisis_hud() -> void:
	for node_name: String in ["ArrearsBanner", "ArrearsVignette"]:
		var node := find_child(node_name, true, false)
		if node != null:
			if node is Control:
				(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
				(node as Control).visible = false
			node.queue_free()

func _show_bank_takeover_overlay() -> void:
	if find_child("BankTakeoverOverlay", true, false) != null:
		return
	_clear_crisis_hud()
	var settlement: Dictionary = Game.state.get("bankruptcy", {}).get("last_takeover", {})
	var overlay := ColorRect.new()
	overlay.name = "BankTakeoverOverlay"
	overlay.color = Color(0.005, 0.01, 0.02, 0.48)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 110
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "BankTakeoverCard"
	card.custom_minimum_size.x = _safe_modal_size(Vector2(760, 0)).x
	card.set_meta("viewport_bounded_surface", true)
	card.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 50)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_right", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	margin.add_child(box)
	box.add_child(_icon_view("ic_bankrupt", Vector2(128, 128)))
	var title := _label(tr("BANK_TAKEOVER_TITLE"), 48, ThemeMaker.COLORS.cream)
	title.name = "BankTakeoverTitle"
	ThemeMaker.apply_text_role(title, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := _label(tr("BANK_TAKEOVER_BODY") % Game.format_number(float(settlement.get("debt_before", 0.0))), 24, Color("c7d8e5"))
	body.name = "BankTakeoverBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	var stats := [
		{"key": "BANK_TAKEOVER_DEBT_PAID", "value": "$%s" % Game.format_number(float(settlement.get("debt_paid", 0.0))), "accent": ThemeMaker.COLORS.yellow},
		{"key": "BANK_TAKEOVER_FORGIVEN", "value": "$%s" % Game.format_number(float(settlement.get("debt_forgiven", 0.0))), "accent": Color("dce8f0")},
		{"key": "BANK_TAKEOVER_RELIEF", "value": "$%s" % Game.format_number(float(settlement.get("relief_grant", 0.0))), "accent": ThemeMaker.COLORS.green.lightened(0.08)},
		{"key": "BANK_TAKEOVER_REMAINING", "value": str(int(settlement.get("remaining_datacenters", 0))), "accent": ThemeMaker.COLORS.cream},
	]
	for stat_index: int in range(stats.size()):
		var stat: Dictionary = stats[stat_index]
		var stat_panel := PanelContainer.new()
		stat_panel.name = "BankTakeoverStat_%d" % stat_index
		stat_panel.custom_minimum_size.y = 64
		stat_panel.add_theme_stylebox_override("panel", ThemeMaker.flat_group_box(Color(stat.get("accent", ThemeMaker.COLORS.sky)), 16))
		box.add_child(stat_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
		stat_panel.add_child(row)
		var key_label := _label(tr(stat.get("key", "")), 22, ThemeMaker.TEXT_SECONDARY)
		key_label.name = "BankTakeoverStatKey_%d" % stat_index
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_label)
		var value_label := _label(str(stat.get("value", "")), 26, Color(stat.get("accent", ThemeMaker.COLORS.cream)))
		value_label.name = "BankTakeoverStatValue_%d" % stat_index
		ThemeMaker.apply_numeric_text(value_label)
		row.add_child(value_label)
	var sold_title := _label(tr("BANK_TAKEOVER_SOLD") % int(settlement.get("sold_count", 0)), 24, ThemeMaker.COLORS.cream)
	sold_title.name = "BankTakeoverSoldTitle"
	ThemeMaker.apply_text_role(sold_title, "title")
	box.add_child(sold_title)
	var sold_scroll := ScrollContainer.new()
	sold_scroll.name = "BankTakeoverSoldScroll"
	sold_scroll.custom_minimum_size.y = 180
	sold_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sold_scroll)
	var sold_list := VBoxContainer.new()
	sold_list.name = "BankTakeoverSoldList"
	sold_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sold_list.add_theme_constant_override("separation", 8)
	sold_scroll.add_child(sold_list)
	var sold_entries: Array = settlement.get("sold", [])
	if sold_entries.is_empty():
		sold_list.add_child(_label(tr("BANK_TAKEOVER_NONE_SOLD"), 21, ThemeMaker.COLORS.cyan))
	else:
		for sold_index: int in range(sold_entries.size()):
			var sold_entry: Dictionary = sold_entries[sold_index]
			var sold_label := _label(tr("BANK_TAKEOVER_SOLD_ROW") % [str(sold_entry.get("datacenter_id", "")), Game.format_number(float(sold_entry.get("proceeds", 0.0)))], 21, Color("c7d8e5"))
			sold_label.name = "BankTakeoverSoldEntry_%d" % sold_index
			sold_list.add_child(sold_label)
	var restart := Widgets.button(tr("BANK_TAKEOVER_CONTINUE"), func() -> void:
		Game.acknowledge_bank_takeover()
		overlay.queue_free()
		_navigate("map")
	, "primary")
	restart.name = "BankTakeoverContinue"
	box.add_child(restart)
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * 0.84
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(overlay, "color", Color(0.005, 0.01, 0.02, 0.82), 0.4)
	reveal.tween_property(card, "modulate:a", 1.0, 0.28)
	reveal.tween_property(card, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_locale_changed(_locale: String) -> void:
	_last_map_signature = ""
	var nav_keys := {"map": "NAV_MAP", "build": "NAV_BUILD", "market": "NAV_MARKET", "tech": "NAV_TECH", "store": "NAV_STORE"}
	for page_id: String in nav_keys:
		var button: Button = nav_buttons.get(page_id) as Button
		if button != null and button.has_node("Content/Items/Text"):
			(button.get_node("Content/Items/Text") as Label).text = tr(nav_keys[page_id])
	var settings_button := find_child("SettingsButton", true, false) as Button
	if settings_button != null:
		settings_button.tooltip_text = tr("NAV_SETTINGS")
	if tutorial_hint_button != null:
		tutorial_hint_button.tooltip_text = tr("TUTORIAL_RETIRE_WAIT")
	_set_world_action_label(task_button, tr("NAV_BUILD"))
	_set_world_action_label(operations_button, tr("OPERATIONS_SHORT"))
	_request_full_refresh()

func _on_purchase_completed(_product_id: String, success: bool, _message: String) -> void:
	_show_toast(tr("TOAST_PURCHASE_COMPLETE") if success else tr("TOAST_PURCHASE_FAILED"), "sfx_success_chime" if success else "sfx_error_thud")
	if success:
		_play_fx("fx_coin")
	_request_full_refresh()

func _show_persona_toast(persona: Dictionary, message: String, cue_id: String = "") -> void:
	if persona.is_empty() or feedback_layer == null:
		_show_toast(message, cue_id)
		return
	var existing := feedback_layer.find_child("PersonaToast", true, false)
	if existing != null:
		existing.queue_free()
	if not cue_id.is_empty():
		AudioService.play_sfx(cue_id)
	var panel := PanelContainer.new()
	panel.name = "PersonaToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = Vector2(700, 142)
	var viewport_size := get_viewport_rect().size
	panel.position = Vector2((viewport_size.x - panel.size.x) * 0.5, viewport_size.y - 340.0)
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color(0.04, 0.10, 0.17, 0.97), ThemeMaker.COLORS.sky, 2, 24))
	feedback_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	row.add_child(_icon_view(str(persona.get("asset_id", "")), Vector2(104, 104)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	var name := _label(tr(str(persona.get("name_key", ""))), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.yellow)
	name.max_lines_visible = 1
	copy.add_child(name)
	var body := _label(message, ThemeMaker.TYPE_SCALE.caption, Color.WHITE)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.max_lines_visible = 2
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	body.add_theme_constant_override("outline_size", 3)
	copy.add_child(body)
	panel.modulate.a = 0.0
	panel.position.y += 18.0
	var tween := panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.tween_property(panel, "position:y", panel.position.y - 18.0, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(2.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.30)
	tween.tween_callback(panel.queue_free)

func _show_toast(message: String, cue_id: String = "") -> void:
	if not cue_id.is_empty():
		AudioService.play_sfx(cue_id)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	var is_error := cue_id == "sfx_error_thud"
	toast_label.text = message
	var viewport_size := get_viewport_rect().size
	toast_label.position.x = (viewport_size.x - toast_label.size.x) * 0.5
	# Errors belong in the open middle safe band: above bottom drawers and below
	# the HUD/tutorial copy. Success confirmations stay near the primary action.
	toast_label.position.y = viewport_size.y * 0.42 if is_error or (tutorial_overlay != null and tutorial_overlay.visible) else viewport_size.y - 300.0
	toast_label.add_theme_font_size_override("font_size", 23 if is_error else 25)
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	toast_label.add_theme_constant_override("outline_size", 3)
	toast_label.add_theme_stylebox_override("normal", ThemeMaker.panel(
		Color("3b2516") if is_error else Color(0.05, 0.08, 0.13, 0.96),
		ThemeMaker.COLORS.orange if is_error else ThemeMaker.COLORS.sky,
		3 if is_error else 2,
		22
	))
	toast_label.modulate = Color.WHITE
	toast_label.pivot_offset = toast_label.size * 0.5
	toast_label.scale = Vector2.ONE * 0.97
	toast_label.visible = true
	_toast_tween = toast_label.create_tween()
	_toast_tween.tween_property(toast_label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(3.2 if is_error else 1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func() -> void: toast_label.visible = false)

func _play_fx(asset_id: String, extent: float = -1.0) -> void:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null or not is_inside_tree() or fx_layer == null:
		return
	extent = _bounded_fx_extent(asset_id, extent)
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 0
	view.set_meta("fx_asset_id", asset_id)
	view.set_meta("fx_extent", extent)
	fx_layer.add_effect(view)
	view.set_anchors_preset(Control.PRESET_CENTER)
	view.offset_left = -extent * 0.5
	view.offset_top = -extent * 0.5
	view.offset_right = extent * 0.5
	view.offset_bottom = extent * 0.5
	view.pivot_offset = Vector2(extent, extent) * 0.5
	view.scale = Vector2.ONE * 0.45
	view.modulate.a = 0.0
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE * 1.15, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, 0.12)
	tween.tween_property(view, "modulate:a", 0.0, 0.35).set_delay(0.5)
	tween.finished.connect(view.queue_free)

func _play_fx_at_world(asset_id: String, target_id: String, extent: float = -1.0) -> void:
	if active_page != "map" or park_map == null or fx_layer == null or _blocking_surface_visible():
		return
	extent = _bounded_fx_extent(asset_id, extent)
	var target := park_map.target_global_position(target_id)
	var texture := AssetCatalog.texture(asset_id)
	if target == Vector2.ZERO or texture == null:
		return
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 0
	view.set_meta("fx_asset_id", asset_id)
	view.set_meta("fx_extent", extent)
	view.size = Vector2.ONE * extent
	fx_layer.add_effect(view)
	view.global_position = target - view.size * 0.5
	view.pivot_offset = view.size * 0.5
	view.scale = Vector2.ONE * 0.35
	view.modulate.a = 0.0
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, 0.10)
	tween.tween_property(view, "modulate:a", 0.0, 0.28).set_delay(0.34)
	tween.finished.connect(view.queue_free)

func _bounded_fx_extent(asset_id: String, requested: float) -> float:
	var limit := float(FX_EXTENT_LIMITS.get(asset_id, 100.0))
	return limit if requested <= 0.0 else minf(requested, limit)

func _show_era_overlay(era_id: int, era: Dictionary) -> void:
	var existing := find_child("EraOverlay", true, false)
	if existing != null:
		existing.queue_free()
	var overlay := ColorRect.new()
	overlay.name = "EraOverlay"
	overlay.color = Color(0.02, 0.05, 0.11, 0.90)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	AudioService.play_sfx("sfx_unlock_fanfare")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "EraNewspaper"
	card.custom_minimum_size = _safe_modal_size(Vector2(720, 1120))
	card.set_meta("viewport_bounded_surface", true)
	card.add_theme_stylebox_override("panel", ThemeMaker.art_panel(false))
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_bottom", 56)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)
	var masthead := _label(tr("ERA_NEWSPAPER_MASTHEAD"), 22, Color("725a36"))
	masthead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(masthead)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 8)
	box.add_child(rule)
	var headline := _label((tr("ERA_ARRIVAL") % tr(era.get("name_key", ""))).strip_edges(), 46, ThemeMaker.COLORS.ink)
	ThemeMaker.apply_text_role(headline, "display")
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)
	box.add_child(_icon_view("ic_era%d" % era_id, Vector2(250, 230)))
	var unlock_title := _label(tr("ERA_UNLOCK_SUMMARY"), 26, Color("a96b05"))
	ThemeMaker.apply_text_role(unlock_title, "title")
	unlock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(unlock_title)
	var unlocks := _era_unlock_items(era_id)
	var unlock_box := VBoxContainer.new()
	unlock_box.name = "EraUnlockSummary"
	unlock_box.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	box.add_child(unlock_box)
	for index: int in range(mini(3, unlocks.size())):
		var item: Dictionary = unlocks[index]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		unlock_box.add_child(row)
		row.add_child(_icon_view(str(item.get("asset_id", "")), Vector2(44, 44)))
		row.add_child(_label("✓  %s" % tr(item.get("name_key", "")), 21, ThemeMaker.COLORS.ink))
	var reward_chip := PanelContainer.new()
	reward_chip.name = "EraRewardChip"
	var reward_style := ThemeMaker.panel(Color("6f4bb8"), Color("bda6ee"), 2, 22)
	reward_style.content_margin_left = 20
	reward_style.content_margin_right = 20
	reward_style.content_margin_top = 10
	reward_style.content_margin_bottom = 10
	reward_chip.add_theme_stylebox_override("panel", reward_style)
	box.add_child(reward_chip)
	var reward_row := HBoxContainer.new()
	reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_row.add_theme_constant_override("separation", 10)
	reward_chip.add_child(reward_row)
	reward_row.add_child(_icon_view("ic_diamond", Vector2(40, 40)))
	var reward := _label("0", 34, Color.WHITE)
	reward.name = "EraRewardValue"
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeMaker.apply_numeric_text(reward)
	ThemeMaker.world_text(reward)
	reward_row.add_child(reward)
	var confirm := Widgets.button(tr("ERA_ENTER"), _complete_era_overlay.bind(overlay, era_id), "primary")
	confirm.name = "EraConfirmButton"
	confirm.visible = false
	box.add_child(confirm)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if pressed and is_instance_valid(confirm):
			confirm.visible = true
	)
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * 1.4
	card.rotation = deg_to_rad(-8.0)
	card.pivot_offset = card.custom_minimum_size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.16)
	tween.tween_property(card, "scale", Vector2.ONE, 0.50).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", 0.0, 0.50).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var reward_target := int(era.get("reward_gems", 0))
	var reward_tween := Widgets.animate_number(reward, 0.0, float(reward_target), func(value: float) -> String: return str(int(round(value))), 1.2)
	reward_tween.finished.connect(func() -> void:
		if is_instance_valid(reward):
			reward.text = str(reward_target)
	)
	var confirm_ref: WeakRef = weakref(confirm)
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		var live_confirm: Button = confirm_ref.get_ref() as Button
		if live_confirm != null:
			live_confirm.visible = true
	)

func _add_era_confetti(overlay: Control) -> void:
	var texture := AssetCatalog.texture("fx_confetti_set")
	if texture == null:
		return
	for index: int in range(2):
		var view := TextureRect.new()
		view.name = "EraConfetti"
		view.texture = texture
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.size = Vector2(430, 430)
		view.position = Vector2(-110 if index == 0 else 484, 230 if index == 0 else 1010)
		view.pivot_offset = view.size * 0.5
		view.rotation = -0.22 if index == 0 else 0.28
		view.scale = Vector2.ONE * 0.35
		view.modulate.a = 0.0
		overlay.add_child(view)
		var tween := view.create_tween().set_parallel(true)
		tween.tween_property(view, "scale", Vector2.ONE, 0.72).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(float(index) * 0.20)
		tween.tween_property(view, "modulate:a", 0.92, 0.18).set_delay(float(index) * 0.20)

func _complete_era_overlay(overlay: CanvasItem, era_id: int) -> void:
	Game.mark_era_presented(era_id)
	_era_overlay_open = false
	_dismiss_full_overlay(overlay)
	get_tree().create_timer(0.24).timeout.connect(func() -> void: call_deferred("_present_next_era_overlay"))

func _page_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	return box

func _resource_chip(asset_id: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = ThemeMaker.TOUCH_MIN
	chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var visual_margin := MarginContainer.new()
	visual_margin.add_theme_constant_override("margin_top", 8)
	visual_margin.add_theme_constant_override("margin_bottom", 8)
	chip.add_child(visual_margin)
	var capsule := PanelContainer.new()
	capsule.custom_minimum_size.y = 72
	var chip_style := ThemeMaker.panel(Color(ThemeMaker.SURFACE, 0.94), Color(1, 1, 1, 0.08), 1, 18)
	chip_style.content_margin_left = 12
	chip_style.content_margin_right = 12
	chip_style.content_margin_top = 8
	chip_style.content_margin_bottom = 8
	capsule.add_theme_stylebox_override("panel", chip_style)
	visual_margin.add_child(capsule)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	capsule.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(40, 40)))
	var value := _label("", 28, Color.WHITE)
	value.name = "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeMaker.apply_numeric_text(value)
	ThemeMaker.world_text(value)
	row.add_child(value)
	var affordance := _label("+", ThemeMaker.TYPE_SCALE.heading, Color.WHITE)
	affordance.name = "AddAffordance"
	affordance.custom_minimum_size.x = 28
	affordance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	affordance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	affordance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeMaker.world_text(affordance)
	row.add_child(affordance)
	return chip

func _set_world_action_content(button: Button, asset_id: String, text: String) -> void:
	button.text = ""
	button.icon = null
	var center := CenterContainer.new()
	center.name = "WorldActionContent"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)
	var icon := _icon_view(asset_id, Vector2(42, 42))
	icon.name = "WorldActionIcon"
	column.add_child(icon)
	var label := _label(text, 20, Color.WHITE)
	label.name = "WorldActionLabel"
	label.custom_minimum_size = Vector2(92, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeMaker.apply_text_role(label, "world")
	label.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	label.add_theme_constant_override("outline_size", 3)
	column.add_child(label)

func _set_world_action_label(button: Button, text: String) -> void:
	if button == null:
		return
	var label := button.find_child("WorldActionLabel", true, false) as Label
	if label != null:
		label.text = text

func _metric_chip(text: String, accent: Color) -> PanelContainer:
	return Widgets.chip(text, accent.lightened(0.18))

func _tab_button(page_id: String, label_key: String, asset_id: String) -> Button:
	var button := Button.new()
	button.name = "Nav_%s" % page_id
	button.custom_minimum_size.y = 110
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.0
	button.pressed.connect(_navigate.bind(page_id))
	ThemeMaker.apply_tab_style(button, page_id == active_page)
	_wire_button_motion(button)
	var center := CenterContainer.new()
	center.name = "Content"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(center)
	var items := VBoxContainer.new()
	items.name = "Items"
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.alignment = BoxContainer.ALIGNMENT_CENTER
	items.add_theme_constant_override("separation", 2)
	center.add_child(items)
	var icon := _icon_view(asset_id, Vector2(52, 52))
	icon.name = "Icon"
	items.add_child(icon)
	var text_label := _label(tr(label_key), 22, ThemeMaker.COLORS.cyan)
	text_label.name = "Text"
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.add_child(text_label)
	return button

func _update_nav_styles() -> void:
	var selected_page := "map" if active_page == "detail" else active_page
	for page_id: String in nav_buttons:
		var button: Button = nav_buttons[page_id] as Button
		var selected := page_id == selected_page
		ThemeMaker.apply_tab_style(button, selected)
		var label := button.get_node("Content/Items/Text") as Label
		label.add_theme_color_override("font_color", ThemeMaker.COLORS.cream if selected else Color("8fb6cf"))
		var icon := button.get_node("Content/Items/Icon") as TextureRect
		icon.modulate = Color.WHITE if selected else Color(0.68, 0.78, 0.86, 0.72)

func _safe_area_margins() -> Vector4:
	# Desktop safe-area rectangles can use global display coordinates (for
	# example when the game window is on a secondary monitor). Only mobile
	# platforms should translate the display safe area into viewport margins.
	if OS.get_name() not in ["iOS", "Android"]:
		return Vector4(32, 24, 32, 24)
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var viewport := get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4(32, 116, 32, 68)
	var scale := Vector2(viewport.x / screen.x, viewport.y / screen.y)
	var left := maxf(32.0, float(safe.position.x) * scale.x)
	var top := maxf(116.0, float(safe.position.y) * scale.y)
	var right := maxf(32.0, float(screen.x - safe.end.x) * scale.x)
	var bottom := maxf(68.0, float(screen.y - safe.end.y) * scale.y)
	return Vector4(left, top, right, bottom)

func _safe_modal_size(preferred: Vector2, gutter: Vector2 = Vector2(32, 32)) -> Vector2:
	# CenterContainer honors a child's combined minimum even when that minimum is
	# wider than the phone. Clamp authored modal sizes before layout negotiation so
	# localization or future content can never push a frame beyond the viewport.
	var viewport := get_viewport_rect().size
	return Vector2(
		minf(preferred.x, maxf(0.0, viewport.x - gutter.x * 2.0)) if preferred.x > 0.0 else 0.0,
		minf(preferred.y, maxf(0.0, viewport.y - gutter.y * 2.0)) if preferred.y > 0.0 else 0.0
	)

func _wrap_scroll(content: Control, full_surface_touch: bool = false) -> Control:
	var surface := PanelContainer.new()
	surface.name = "SystemSurface"
	surface.set_meta("viewport_bounded_surface", true)
	surface.clip_contents = true
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A short deadzone distinguishes a deliberate card tap from a vertical swipe
	# without making the phone list feel sticky.
	scroll.scroll_deadzone = 12
	scroll.set_meta("touch_scroll_enabled", true)
	ThemeMaker.apply_system_scrollbar(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	if full_surface_touch:
		_enable_full_surface_touch_scroll(scroll, content)
	var margin := MarginContainer.new()
	margin.name = "SystemSurfaceMargin"
	# The nine-slice's nominal inset includes transparent export padding. Keep a
	# real 24u breathing gutter so text never sits beneath the illustrated flange.
	# Narrow content such as store products must adapt vertically instead of
	# borrowing this protected space.
	margin.add_theme_constant_override("margin_left", ThemeMaker.GROUP_PADDING)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", ThemeMaker.GROUP_PADDING)
	# Keep scrollable rows above the page frame's illustrated bottom hardware.
	# A partially visible row is acceptable only when the scroll viewport clips it,
	# never when decorative pixels paint over its text.
	margin.add_theme_constant_override("margin_bottom", 88)
	margin.add_child(scroll)
	surface.add_child(margin)
	return surface

func _enable_full_surface_touch_scroll(scroll: ScrollContainer, content: Control) -> void:
	# iOS sends a drag to the deepest Control under the finger. Buttons and
	# container panels default to STOP, so a settings page made almost entirely of
	# toggles and rows left only its narrow gaps/scrollbar draggable. Decorative
	# controls now ignore hit testing, while actions PASS their events upward and
	# fire only on release. ScrollContainer's deadzone then arbitrates the gesture:
	# a short release remains a tap; a 12u movement becomes a page drag.
	scroll.set_meta("full_surface_touch_scroll", true)
	var touch_controls: Array[Control] = [content]
	for node: Node in content.find_children("*", "Control", true, false):
		touch_controls.append(node as Control)
	for control: Control in touch_controls:
		if control is BaseButton:
			var action := control as BaseButton
			action.mouse_filter = Control.MOUSE_FILTER_PASS
			action.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			action.set_meta("scroll_drag_passthrough", true)
			_wire_full_surface_scroll_action(scroll, action)
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _wire_full_surface_scroll_action(scroll: ScrollContainer, action: BaseButton) -> void:
	if bool(action.get_meta("full_surface_scroll_wired", false)):
		return
	action.set_meta("full_surface_scroll_wired", true)
	var gesture := {
		"active": false,
		"dragging": false,
		"start_y": 0.0,
		"base_scroll": 0,
		"pressed_before": false,
	}
	action.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				gesture["active"] = true
				gesture["dragging"] = false
				gesture["start_y"] = touch.position.y
				gesture["base_scroll"] = scroll.scroll_vertical
				gesture["pressed_before"] = action.button_pressed
			elif bool(gesture.get("active", false)):
				if bool(gesture.get("dragging", false)):
					if action.toggle_mode:
						action.set_pressed_no_signal(bool(gesture.get("pressed_before", false)))
					action.accept_event()
				gesture["active"] = false
		elif event is InputEventScreenDrag and bool(gesture.get("active", false)):
			var drag := event as InputEventScreenDrag
			var travel := drag.position.y - float(gesture.get("start_y", drag.position.y))
			if absf(travel) >= float(scroll.scroll_deadzone):
				gesture["dragging"] = true
			if bool(gesture.get("dragging", false)):
				var bar := scroll.get_v_scroll_bar()
				var maximum := maxi(0, int(bar.max_value - bar.page))
				scroll.scroll_vertical = clampi(int(round(float(gesture.get("base_scroll", 0)) - travel)), 0, maximum)
				if action.toggle_mode:
					action.set_pressed_no_signal(bool(gesture.get("pressed_before", false)))
				action.accept_event()
	)

func _system_page_header(title_text: String, subtitle: String, asset_id: String) -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 96
	header.add_theme_constant_override("separation", 14)
	header.add_child(_icon_view(asset_id, Vector2(64, 64)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	header.add_child(copy)
	var title := _label(title_text, 34, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(title, "display")
	title.max_lines_visible = 1
	copy.add_child(title)
	if not subtitle.is_empty():
		var sub := _label(subtitle, 20, ThemeMaker.COLORS.cyan)
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.max_lines_visible = 1
		copy.add_child(sub)
	var close_button := Widgets.close_button(_navigate.bind("map"))
	header.add_child(close_button)
	return header

func _segmented_control(items: Array, selected_id: String, callback: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE, Color(1, 1, 1, 0.08), 1, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	for item: Dictionary in items:
		var item_id := str(item.get("id", ""))
		var selected := item_id == selected_id
		var button := _button(str(item.get("label", item_id)), callback.bind(item_id), ThemeMaker.COLORS.sky if selected else Color("1b3046"))
		button.name = "Segment_%s" % item_id
		button.custom_minimum_size.y = 88
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18 if items.size() >= 4 else 20)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(item.get("label", item_id))
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
		button.add_theme_constant_override("outline_size", 3)
		# Four-way company navigation is intentionally typographic. Repeating a
		# rendered icon beside every short label made the phone-width control busy
		# and consumed the exact space English needs; the selected page hero owns
		# the illustration instead.
		if item.has("asset") and items.size() < 4:
			_set_button_asset(button, str(item.get("asset", "")), 36)
		if selected:
			var indicator := ColorRect.new()
			indicator.name = "SelectedTabIndicator"
			indicator.color = ThemeMaker.COLORS.sky
			indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			indicator.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			indicator.offset_top = -4
			button.add_child(indicator)
		row.add_child(button)
	return panel

func _section_title(title_text: String, subtitle: String) -> Control:
	return Widgets.section_header(title_text, subtitle)

func _card() -> PanelContainer:
	return Widgets.panel(true)

func _empty_state(text: String) -> Control:
	var label := _label(text, 27, ThemeMaker.COLORS.cyan)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 180
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _empty_action_state(asset_id: String, title_text: String, body_text: String, action_text: String, action: Callable, accent: Color) -> Control:
	var card := Widgets.panel(true)
	card.custom_minimum_size.y = 560
	var center := CenterContainer.new()
	card.add_child(center)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	box.add_child(_icon_view(asset_id, Vector2(176, 176)))
	var title := _label(title_text, 34, ThemeMaker.COLORS.cream)
	ThemeMaker.apply_text_role(title, "title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := _label(body_text, 25, ThemeMaker.COLORS.cyan)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var action_button := _button(action_text, action, accent)
	action_button.custom_minimum_size.y = 96
	box.add_child(action_button)
	return card

func _status_card(asset_id: String, text: String, accent: Color, compact: bool = false) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 96 if compact else 144
	card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(ThemeMaker.SURFACE, 0.96, 18 if compact else 24))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14 if compact else 18)
	card.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(48, 48) if compact else Vector2(76, 76)))
	var status := _label(text, 24 if compact else 27, accent.lightened(0.16))
	status.name = "CompactStatusText" if compact else "StatusText"
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.max_lines_visible = 1
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if compact:
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(status)
	return card

func _settings_toggle_row(setting_key: String, label_key: String) -> Control:
	var card := MarginContainer.new()
	card.custom_minimum_size.y = 96
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", ThemeMaker.GROUP_PADDING)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", ThemeMaker.GROUP_PADDING)
	margin.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var title := _label(tr(label_key), 28, ThemeMaker.COLORS.cream)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var toggle := Button.new()
	toggle.name = "SettingsToggle_%s" % setting_key
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = bool(Game.state.get("settings", {}).get(setting_key, true))
	toggle.custom_minimum_size = Vector2(112, 88)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var knob := PanelContainer.new()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.size = Vector2(44, 44)
	var knob_style := ThemeMaker.panel(Color.WHITE, Color(1, 1, 1, 0.32), 1, 22)
	knob_style.content_margin_left = 0
	knob_style.content_margin_right = 0
	knob_style.content_margin_top = 0
	knob_style.content_margin_bottom = 0
	knob_style.shadow_color = Color(0, 0, 0, 0.24)
	knob_style.shadow_size = 5
	knob.add_theme_stylebox_override("panel", knob_style)
	toggle.add_child(knob)
	_style_switch(toggle, toggle.button_pressed)
	toggle.resized.connect(func() -> void: _position_switch_knob(toggle, knob, toggle.button_pressed, false))
	toggle.toggled.connect(func(enabled: bool) -> void:
		_style_switch(toggle, enabled)
		_position_switch_knob(toggle, knob, enabled, true)
		_on_setting_toggled(enabled, setting_key)
	)
	row.add_child(toggle)
	return card

func _style_switch(toggle: Button, enabled: bool) -> void:
	var fill := ThemeMaker.COLORS.green if enabled else Color("4b5d70")
	var normal := ThemeMaker.panel(fill, Color(1, 1, 1, 0.12), 1, 32)
	var hover := ThemeMaker.panel(fill.lightened(0.07), Color(1, 1, 1, 0.18), 1, 32)
	var pressed := ThemeMaker.panel(fill.darkened(0.08), Color(1, 1, 1, 0.12), 1, 32)
	for style_name: String in ["normal", "hover_pressed"]:
		toggle.add_theme_stylebox_override(style_name, normal)
	toggle.add_theme_stylebox_override("hover", hover)
	toggle.add_theme_stylebox_override("pressed", pressed)
	toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _position_switch_knob(toggle: Button, knob: PanelContainer, enabled: bool, animate: bool) -> void:
	var target := Vector2(toggle.size.x - knob.size.x - 10.0 if enabled else 10.0, (toggle.size.y - knob.size.y) * 0.5)
	if animate:
		var tween := knob.create_tween()
		tween.tween_property(knob, "position", target, 0.18).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		knob.position = target

func _label(text: String, font_size: int = 28, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	ThemeMaker.apply_text_role(label, "body")
	return label

func _icon_view(asset_id: String, dimensions: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = AssetCatalog.texture(asset_id)
	view.custom_minimum_size = dimensions
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view

func _button(text: String, action: Callable, color: Color = Color("3aa7f0")) -> Button:
	return Widgets.button(text, action, ThemeMaker.button_role_for_color(color))

func _wire_button_motion(button: Button) -> void:
	if bool(button.get_meta("button_motion_wired", false)):
		return
	button.set_meta("button_motion_wired", true)
	button.set_meta("tap_audio", "sfx_tap")
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func() -> void:
		AudioService.play_sfx("sfx_tap")
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE * 0.975, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	button.button_up.connect(func() -> void:
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

func _haptic(duration_ms: int) -> void:
	if not bool(Game.state.get("settings", {}).get("haptics_enabled", true)):
		return
	if OS.get_name() in ["iOS", "Android"]:
		Input.vibrate_handheld(duration_ms)

func _set_button_asset(button: Button, asset_id: String, max_width: int) -> void:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

func _build_primary_action_content() -> void:
	# Native Button text draws a 4px CJK outline so far inward at 28u that the
	# nominally-white fill becomes visually gray. Keep the Button itself as the
	# accessible 88u target, but render its icon and text as a deterministic stack.
	primary_action_button.text = ""
	primary_action_button.icon = null
	var center := CenterContainer.new()
	center.name = "PrimaryWorldActionContent"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	primary_action_button.add_child(center)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)
	primary_action_icon = TextureRect.new()
	primary_action_icon.name = "PrimaryWorldActionIcon"
	primary_action_icon.custom_minimum_size = Vector2(40, 40)
	primary_action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	primary_action_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	primary_action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(primary_action_icon)
	primary_action_text_stack = Control.new()
	primary_action_text_stack.name = "PrimaryWorldActionTextStack"
	primary_action_text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(primary_action_text_stack)
	primary_action_text = _label("", 28, Color.WHITE)
	primary_action_text.name = "PrimaryWorldActionText"
	primary_action_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	primary_action_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ThemeMaker.apply_text_role(primary_action_text, "world")
	primary_action_text.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	primary_action_text.add_theme_constant_override("outline_size", 4)
	primary_action_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	primary_action_text_stack.add_child(primary_action_text)
	primary_action_text_fill = _label("", 28, Color.WHITE)
	primary_action_text_fill.name = "PrimaryWorldActionTextFill"
	primary_action_text_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	primary_action_text_fill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ThemeMaker.apply_text_role(primary_action_text_fill, "world")
	# A 1u white expansion pass restores stroke interiors while the 4u ink pass
	# below it remains the outer contrast rim.
	primary_action_text_fill.add_theme_color_override("font_outline_color", Color.WHITE)
	primary_action_text_fill.add_theme_constant_override("outline_size", 1)
	primary_action_text_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	primary_action_text.add_child(primary_action_text_fill)
	_set_primary_action_content(tr("BUILD_DATA_CENTER"), "ic_build")

func _set_primary_action_content(text: String, asset_id: String) -> void:
	if primary_action_text == null or primary_action_text_fill == null or primary_action_icon == null or primary_action_text_stack == null:
		return
	primary_action_button.set_meta("primary_action_text", text)
	primary_action_button.tooltip_text = text
	primary_action_icon.texture = AssetCatalog.texture(asset_id)
	primary_action_text.text = text
	primary_action_text_fill.text = text
	var font := ThemeMaker.font_world_heavy()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
	primary_action_text_stack.custom_minimum_size = Vector2(ceilf(text_size.x) + 8.0, maxf(44.0, ceilf(font.get_height(28)) + 4.0))

func _asset_preview(asset_id: String, fallback_text: String, color: Color, height: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.SURFACE, Color(color, 0.36), 1, 18))
	var texture := AssetCatalog.texture(asset_id)
	if texture != null:
		var view := TextureRect.new()
		view.texture = texture
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(view)
	else:
		var label := _label(fallback_text, 24, Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
	return panel

func _progress_for_job(item: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var progress := ProgressBar.new()
	progress.name = "QueueConstructionProgress"
	progress.show_percentage = false
	progress.custom_minimum_size.y = 34
	var duration := Game.construction_duration(item)
	progress.max_value = duration
	var remaining := maxf(0.0, float(item.get("complete_at", Game.simulation_time())) - Game.simulation_time())
	progress.value = clampf(duration - remaining, 0.0, duration)
	progress.set_meta("duration_seconds", duration)
	progress.set_meta("remaining_seconds", remaining)
	box.add_child(progress)
	var remaining_label := _label(tr("COMPLETE_IN") % Game.format_duration(remaining), 20, ThemeMaker.COLORS.cyan)
	box.add_child(remaining_label)
	box.set_meta("live_update", func() -> void:
		if not is_instance_valid(progress) or not is_instance_valid(remaining_label):
			return
		var live_remaining := maxf(0.0, float(item.get("complete_at", Game.simulation_time())) - Game.simulation_time())
		progress.value = clampf(duration - live_remaining, 0.0, duration)
		progress.set_meta("remaining_seconds", live_remaining)
		remaining_label.text = tr("COMPLETE_IN") % Game.format_duration(live_remaining)
	)
	return box

func _construction_name(item: Dictionary) -> String:
	match item.get("type", ""):
		"datacenter": return tr(DataRepository.get_entry("buildings", str(item.get("building_id", ""))).get("name_key", "BUILD"))
		"rack": return tr(DataRepository.get_entry("racks", str(item.get("rack_id", ""))).get("name_key", "INSTALL"))
		"power", "cooler": return tr(DataRepository.get_entry("attachments", str(item.get("attachment_id", ""))).get("name_key", "INSTALL"))
		"network": return tr(DataRepository.get_table("technology").get("network", {}).get(str(item.get("level", 1)), {}).get("name_key", "NETWORK"))
	return tr("BUILD")

func _construction_asset_id(item: Dictionary) -> String:
	match item.get("type", ""):
		"datacenter":
			var building := DataRepository.get_entry("buildings", str(item.get("building_id", "")))
			return str(building.get("asset_prefix", "")) + "_construction"
		"rack":
			var rack := DataRepository.get_entry("racks", str(item.get("rack_id", "")))
			return str(rack.get("asset_prefix", "")) + "_installing"
		"power", "cooler": return str(item.get("attachment_id", "")) + "_active"
		"network": return "ic_network"
	return "ic_build"

func _rack_status_text(installed: Dictionary, runtime: Dictionary) -> String:
	if installed.get("status", "") == "installing": return tr("INSTALLING")
	if bool(runtime.get("faulted", false)): return tr("FAULTED")
	if bool(runtime.get("repairing", false)): return tr("REPAIR")
	if not bool(installed.get("enabled", true)): return tr("RACK_DISABLED")
	if not bool(runtime.get("powered", false)): return tr("UNPOWERED")
	if bool(runtime.get("overheated", false)): return tr("OVERHEATED")
	return tr("POWERED")

func _rack_market_label(sensitivity: float) -> String:
	if sensitivity < 0.7:
		return tr("RACK_MARKET_STEADY")
	if sensitivity > 1.1:
		return tr("RACK_MARKET_VOLATILE")
	return tr("RACK_MARKET_BALANCED")
