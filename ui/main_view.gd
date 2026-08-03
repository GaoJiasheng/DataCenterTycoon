extends Control

const ThemeMaker := preload("res://ui/theme_factory.gd")
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
const LEGAL_DOCUMENTS := {
	"privacy": "res://docs/public/privacy.html",
	"terms": "res://docs/public/terms.html",
	"support": "res://docs/public/support.html",
}

var cash_label: Label
var gems_label: Label
var date_label: Label
var news_label: Label
var tutorial_overlay: TutorialOverlay
var world_host: Control
var park_map: ParkMap
var shell_header: PanelContainer
var news_panel: PanelContainer
var navigation_panel: PanelContainer
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
var toast_label: Label
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
	var company_row := HBoxContainer.new()
	company_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	company_row.add_theme_constant_override("separation", 4)
	company_center.add_child(company_row)
	era_icon = _icon_view("ic_era1", Vector2(46, 46))
	company_row.add_child(era_icon)
	company_label = _label("1", 24, Color.WHITE)
	ThemeMaker.world_text(company_label)
	company_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	company_row.add_child(company_label)
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

	navigation_panel = PanelContainer.new()
	navigation_panel.name = "WorldActions"
	navigation_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# Include the two external captions in the bottom safe-area contract. Keeping
	# them above their icon buttons makes the labels readable even on the dense
	# campus framing and leaves an explicit 8u breathing strip below the CTA.
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
	task_button.offset_top = -50
	task_button.offset_right = 96
	task_button.offset_bottom = 46
	task_button.tooltip_text = tr("VIEW_QUEUE")
	task_button.pressed.connect(_navigate.bind("build"))
	ThemeMaker.apply_round_button(task_button, ThemeMaker.COLORS.orange)
	_wire_button_motion(task_button)
	_set_button_asset(task_button, "ic_build", 42)
	action_layer.add_child(task_button)
	_add_world_action_caption(action_layer, tr("NAV_BUILD"), false)
	queue_badge_label = _label("", 19, Color.WHITE)
	queue_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_badge_label.position = Vector2(62, -6)
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
	operations_button.offset_left = -96
	operations_button.offset_top = -50
	operations_button.offset_right = 0
	operations_button.offset_bottom = 46
	operations_button.tooltip_text = tr("OPERATIONS_CENTER")
	operations_button.pressed.connect(_show_operations_hub)
	ThemeMaker.apply_round_button(operations_button, ThemeMaker.COLORS.sky)
	_wire_button_motion(operations_button)
	operations_button.text = ""
	var operations_asset := "ic_operations" if AssetCatalog.texture("ic_operations") != null else "ic_network"
	_set_button_asset(operations_button, operations_asset, 42)
	operations_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_layer.add_child(operations_button)
	_add_world_action_caption(action_layer, tr("OPERATIONS_SHORT"), true)
	operations_badge = Widgets.badge(0)
	operations_badge.position = Vector2(62, -6)
	operations_badge_label = operations_badge.find_child("BadgeValue", true, false) as Label
	operations_badge.visible = false
	operations_button.add_child(operations_badge)

	fx_layer = FxLayerScene.new()
	fx_layer.name = "FxLayer"
	add_child(fx_layer)
	tutorial_overlay = TutorialOverlayScene.new()
	tutorial_overlay.target_activated.connect(_on_tutorial_target_activated)
	add_child(tutorial_overlay)

	toast_label = _label("", 25, Color.WHITE)
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-330, -230)
	toast_label.size = Vector2(660, 84)
	toast_label.add_theme_stylebox_override("normal", ThemeMaker.panel(Color(0.05, 0.08, 0.13, 0.94), ThemeMaker.COLORS.sky, 2, 20))
	add_child(toast_label)

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
	EventBus.contract_renewal_opened.connect(_on_contract_renewal_opened)
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
	var era: Dictionary = DataRepository.get_entry("eras", str(player.get("era", 1)))
	company_label.text = str(int(player.get("era", 1)))
	var company_button := find_child("CompanyButton", true, false) as Button
	if company_button != null:
		company_button.tooltip_text = "%s · %s" % [tr(era.get("name_key", "ERA_1")), GameClock.format_game_date(Game.simulation_time())]
	era_icon.texture = AssetCatalog.texture("ic_era%d" % int(player.get("era", 1)))
	news_label.text = _news_text()
	var market: Dictionary = Game.state.get("market", {})
	var has_news: bool = not market.get("active", []).is_empty() or not market.get("previews", []).is_empty()
	news_panel.visible = active_page == "map" and has_news
	var queue_size: int = Game.state.get("construction_queue", []).size()
	queue_badge_label.text = str(queue_size)
	queue_badge_label.visible = queue_size > 0
	var operations_count := _operations_attention_count()
	operations_badge_label.text = str(operations_count)
	operations_badge.visible = operations_count > 0
	_refresh_primary_action()
	_refresh_arrears_hud()
	_refresh_tutorial()
	var on_map := active_page == "map"
	# System pages are opaque work surfaces. Keeping the depth-sorted park alive
	# behind their safe-area gutters allowed southern plots and their price rails
	# to peek through the right edge of the board.
	world_host.visible = on_map
	navigation_panel.visible = on_map
	page_host.visible = not on_map
	_refresh_live_page()

func _refresh_page() -> void:
	var on_map := active_page == "map"
	if on_map:
		_refresh_park_world()
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
	if page_host == null or page_host.get_child_count() == 0:
		return
	var page := page_host.get_child(0)
	var live_nodes: Array[Node] = [page]
	live_nodes.append_array(page.find_children("*", "", true, false))
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
	fx_layer.fly_coins(source, _cash_chip_target(), 3)
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
	var result: int = Game.state.get("market", {}).get("active", []).size()
	var cash := float(Game.state.get("player", {}).get("cash", 0.0))
	var technology: Dictionary = DataRepository.get_table("technology")
	var network_level := int(Game.state.get("player", {}).get("network_level", 1))
	var next_network: Dictionary = technology.get("network", {}).get(str(network_level + 1), {})
	if not next_network.is_empty() and Game.is_unlocked(next_network) and cash >= float(next_network.get("cost", INF)):
		result += 1
	var repair_level := int(Game.state.get("technology", {}).get("repair_team", 1))
	var next_repair: Dictionary = technology.get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(str(repair_level + 1), {})
	if not next_repair.is_empty() and Game.is_unlocked(next_repair) and cash >= float(next_repair.get("cost", INF)):
		result += 1
	return result

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
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_navigate("market")

func _show_operations_hub() -> void:
	var parts := _create_world_sheet("OperationsHub", 680)
	var overlay := parts["overlay"] as ColorRect
	var box := parts["box"] as VBoxContainer
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	box.add_child(heading)
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_copy)
	heading_copy.add_child(_label(tr("OPERATIONS_CENTER"), 38, ThemeMaker.COLORS.cream))
	heading_copy.add_child(_label(tr("OPERATIONS_SUBTITLE"), 22, ThemeMaker.COLORS.cyan))
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	heading.add_child(close_button)

	var queue_size: int = Game.state.get("construction_queue", []).size()
	var era_id := int(Game.state.get("player", {}).get("era", 1))
	var era := DataRepository.get_entry("eras", str(era_id))
	var modules: Array[Dictionary] = [
		{"id": "build", "title": tr("CONSTRUCTION_QUEUE"), "subtitle": tr("QUEUE_CAPACITY") % [queue_size, int(DataRepository.get_table("economy").get("construction", {}).get("base_queue_capacity", 2))], "asset": "ic_build", "accent": ThemeMaker.COLORS.orange if queue_size > 0 else ThemeMaker.COLORS.sky},
		{"id": "market", "title": tr("NAV_MARKET"), "subtitle": _news_text(), "asset": "ic_market_up", "accent": ThemeMaker.COLORS.orange if not Game.state.get("market", {}).get("active", []).is_empty() else ThemeMaker.COLORS.sky},
		{"id": "tech", "title": tr("NAV_TECH"), "subtitle": tr(era.get("name_key", "ERA_1")), "asset": "ic_tech", "accent": ThemeMaker.COLORS.purple},
		{"id": "store", "title": tr("NAV_STORE"), "subtitle": tr("GEMS_FORMAT") % Game.format_number(float(Game.state.get("player", {}).get("gems", 0))), "asset": "ic_shop", "accent": ThemeMaker.COLORS.green},
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for module: Dictionary in modules:
		var module_id := str(module["id"])
		var card := _operation_module_card(module, func() -> void:
			_dismiss_world_sheet(overlay, _navigate.bind(module_id))
		)
		grid.add_child(card)

func _operation_module_card(module: Dictionary, action: Callable) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 214)
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
	top.add_child(_icon_view(str(module.get("asset", "ic_build")), Vector2(72, 72)))
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
	content.add_child(_label(str(module.get("title", "")), 28, ThemeMaker.COLORS.cream))
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
	box.add_child(_system_page_header(tr("CONSTRUCTION_QUEUE"), tr("QUEUE_CAPACITY") % [Game.state.get("construction_queue", []).size(), int(DataRepository.get_table("economy").get("construction", {}).get("base_queue_capacity", 2))], "ic_build"))
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
		ad_button.disabled = int(item.get("ad_uses", 0)) >= max_ads
		actions.add_child(ad_button)
		box.add_child(card)
	return _wrap_scroll(box)

func _build_datacenter_page() -> Control:
	var dc := Game.find_datacenter(selected_datacenter_id)
	if dc.is_empty():
		active_page = "map"
		return Control.new()
	var box := _page_box()
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	box.add_child(_system_page_header(tr(building.get("name_key", "")), _datacenter_status_text(dc), _datacenter_context_asset(dc, building)))
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	var detail_metrics := HBoxContainer.new()
	detail_metrics.add_theme_constant_override("separation", 10)
	detail_metrics.add_child(_metric_chip("%s  %d%%" % [tr("LIFESPAN"), int(progress * 100.0)], ThemeMaker.COLORS.yellow))
	detail_metrics.add_child(_metric_chip(tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc)), ThemeMaker.COLORS.green))
	box.add_child(detail_metrics)
	if dc.get("status", "") == "ruined":
		box.add_child(_asset_preview(str(building.get("asset_prefix", "")) + "_ruin", tr("DEMOLISH"), ThemeMaker.COLORS.red, 300))
		box.add_child(_button("%s · $%s" % [tr("DEMOLISH"), Game.format_number(Rules.demolition_cost(dc, Game.data))], _demolish.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.red))
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
	board.power_slot_selected.connect(func(dc_id: String) -> void: _show_attachment_picker(dc_id, "power", ""))
	return board

func _on_board_rack_slot_selected(datacenter_id: String, slot: int) -> void:
	var dc := Game.find_datacenter(datacenter_id)
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
	var power_button := _button(power_text, _show_attachment_picker.bind(str(dc.get("id", "")), "power", ""), ThemeMaker.COLORS.yellow.darkened(0.2))
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
		var refund := Rules.retirement_value(dc, Game.simulation_time(), Game.data)
		section.add_child(_button("%s · +$%s" % [tr("RETIRE"), Game.format_number(refund)], _retire.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.orange))
	return section

func _build_contract_management(dc: Dictionary) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	var current_customer := str(dc.get("customer_id", ""))
	var client_name := tr(DataRepository.get_entry("customers", current_customer).get("name_key", "CONTRACT_NONE"))
	var timing_text := ""
	if not current_customer.is_empty():
		var renewal_end := float(dc.get("renewal_window_end_at", 0.0))
		if renewal_end > Game.simulation_time():
			timing_text = tr("CONTRACT_RENEWAL_WINDOW") % Game.format_duration(renewal_end - Game.simulation_time())
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
		var timing_label := _label(timing_text, ThemeMaker.TYPE_SCALE.caption, ThemeMaker.COLORS.cyan)
		timing_label.max_lines_visible = 1
		timing_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary_box.add_child(timing_label)
	section.add_child(summary)
	var contracts := VBoxContainer.new()
	contracts.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	section.add_child(contracts)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		var available := int(customer.get("unlock_era", 1)) <= int(Game.state["player"].get("era", 1)) and int(customer.get("minimum_network_level", 1)) <= int(Game.state["player"].get("network_level", 1))
		contracts.add_child(_contract_customer_card(dc, customer_id, customer, current_customer, available))
	return section

func _contract_customer_card(dc: Dictionary, customer_id: String, customer: Dictionary, current_customer: String, available: bool) -> Button:
	var serving := customer_id == current_customer
	var action := _sign_contract.bind(str(dc.get("id", "")), customer_id) if available else _show_toast.bind(_customer_unlock_text(customer))
	var card := Button.new()
	card.name = "Contract_%s" % customer_id
	card.focus_mode = Control.FOCUS_NONE
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
		var trend := _market_trend(customer_id)
		var trend_percent := float(trend.get("percent", 0.0))
		var value := _label("×%.2f  %s %+.1f%%" % [Game.market_multiplier(customer_id), str(trend.get("arrow", "→")), trend_percent], 32, ThemeMaker.COLORS.red if trend_percent > 0.05 else ThemeMaker.COLORS.green)
		ThemeMaker.apply_numeric_text(value)
		copy.add_child(value)
		var projected := _label(tr("CONTRACT_PROJECTED") % Game.format_number(_projected_datacenter_income(dc, customer_id)), ThemeMaker.TYPE_SCALE.body, ThemeMaker.COLORS.yellow)
		projected.max_lines_visible = 1
		projected.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		copy.add_child(projected)
		var fit: Dictionary = customer.get("fit", {})
		card.tooltip_text = tr("CONTRACT_FIT_TOOLTIP") % [float(fit.get("compute", 0.0)), float(fit.get("storage", 0.0)), float(fit.get("gpu", 0.0))]
		var fee := Game.contract_switch_fee(str(dc.get("id", "")), customer_id)
		if not current_customer.is_empty() and not serving:
			card.tooltip_text += "\n" + (tr("CONTRACT_FREE_SWITCH") if fee <= 0.0 else tr("CONTRACT_BREACH_FEE") % Game.format_number(fee))
	else:
		var locked := _label("🔒 %s" % _customer_unlock_text(customer), ThemeMaker.TYPE_SCALE.body, Color("aeb8c4"))
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

func _projected_datacenter_income(dc: Dictionary, customer_id: String) -> float:
	var simulated := dc.duplicate(true)
	simulated["customer_id"] = customer_id
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
	box.add_child(_system_page_header(tr("NAV_MARKET"), _news_text(), "ic_market_up"))
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
	return _wrap_scroll(box)

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
		{"id": "upgrades", "label": tr("UPGRADE"), "asset": "ic_tech"},
		{"id": "achievements", "label": tr("ACHIEVEMENTS"), "asset": "ic_contract"},
	], _tech_section, _set_tech_section))
	if _tech_section == "achievements":
		box.add_child(_build_achievements_section())
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
		var network_button := _button("%s %s · $%s" % [tr("UPGRADE"), tr(next_network.get("name_key", "")), Game.format_number(network_cost)], _upgrade_network, ThemeMaker.COLORS.sky)
		network_button.disabled = not Game.is_unlocked(next_network)
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
		var repair_button := _button("%s · $%s" % [tr("UPGRADE"), Game.format_number(repair_cost)], _upgrade_repair, ThemeMaker.COLORS.green)
		repair_button.disabled = not Game.is_unlocked(next_repair)
		Widgets.affordable_style(repair_button, repair_cost)
		repair_box.add_child(repair_button)
	box.add_child(repair_card)
	box.add_child(_build_prestige_card(player))
	return _wrap_scroll(box)

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
	route.add_theme_constant_override("separation", 6)
	box.add_child(route)
	for node_era: int in range(1, 4):
		if node_era > 1:
			var connector := _label("›", 34, ThemeMaker.COLORS.yellow if node_era <= era_id + 1 else Color("718096"))
			connector.custom_minimum_size.x = 22
			connector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			route.add_child(connector)
		var node := PanelContainer.new()
		node.name = "EraNode_%d" % node_era
		node.custom_minimum_size = Vector2(170, 178)
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
		var state_label := _label("✓" if node_era < era_id else (tr("ERA_CURRENT") if node_era == era_id else "🔒"), 18, ThemeMaker.COLORS.green if node_era <= era_id else Color("8a97a8"))
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
		chip.custom_minimum_size = Vector2(138, 108)
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
	wallet_copy.add_child(_label(tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0))), 34, ThemeMaker.COLORS.purple.lightened(0.18)))
	wallet_copy.add_child(_label(tr("STORE_WALLET_HINT"), 22, ThemeMaker.COLORS.cyan))
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
			box.add_child(_status_card("ic_lock", tr("STORE_DEALS_LATER"), Color("8a97a8")))
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
		var value_text := "$%.4f / 💎" % price_per_gem
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
		buy_button.disabled = true
	elif OS.get_name() == "iOS" and not Monetization.is_product_available(product_id):
		buy_button.text = "…"
		buy_button.disabled = true
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
	return _wrap_scroll(box)

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
	chevron.text = "›"
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

func _refresh_tutorial() -> void:
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	if _last_tutorial_step >= 0 and index > _last_tutorial_step:
		_play_fx("fx_confetti_set", 300)
		AudioService.play_sfx("sfx_tap")
		_haptic(HAPTIC_SUCCESS)
		if index in [1, 4, 7]:
			_fly_cash_reward(Vector2.ZERO, 3)
	_last_tutorial_step = index
	var completed := bool(tutorial.get("completed", false)) or index >= steps.size()
	if completed:
		tutorial_overlay.dismiss()
		_set_tutorial_chrome_visibility(true, "")
		return
	var step: Dictionary = steps[index]
	var focus := str(step.get("focus", ""))
	var target := _resolve_tutorial_target(focus)
	var rect: Rect2 = target.get("rect", Rect2())
	var action: Callable = target.get("action", Callable())
	var guide_assets := ["guide_normal", "guide_thinking", "guide_happy", "guide_alert", "guide_worried", "guide_thinking", "guide_worried", "guide_happy"]
	tutorial_overlay.present(rect, tr(step.get("message_key", "")), guide_assets[mini(index, guide_assets.size() - 1)], action)
	_set_tutorial_chrome_visibility(false, focus)

func _set_tutorial_chrome_visibility(restored: bool, focus: String) -> void:
	if task_button != null:
		task_button.visible = restored
	if operations_button != null:
		operations_button.visible = restored
	if news_panel != null and not restored:
		news_panel.visible = false
	if primary_action_button != null:
		primary_action_button.visible = restored or focus in ["build_dc_t0", "buy_plot", "build_dc_t1"]

func _resolve_tutorial_target(focus: String) -> Dictionary:
	var control: Control = null
	match focus:
		"build_dc_t0":
			control = _visible_control_named("Building_dc_t0")
			if control == null: control = primary_action_button
		"build_dc_t1":
			control = _visible_control_named("Building_dc_t1")
			if control == null: control = primary_action_button
		"install_power": control = _visible_control_named("PowerSlot")
		"rack_slot_0":
			control = _visible_control_named("RackSlot0")
			if control != null:
				var board := _visible_datacenter_board(selected_datacenter_id)
				if board != null:
					return {"rect": control.get_global_rect(), "action": _on_board_rack_slot_selected.bind(board.datacenter_id, 0)}
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
	if control == null or not control.is_visible_in_tree():
		return {"rect": Rect2(), "action": Callable()}
	var action := func() -> void:
		if is_instance_valid(control) and control is Button:
			(control as Button).pressed.emit()
	return {"rect": control.get_global_rect(), "action": action}

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
	var market: Dictionary = Game.state.get("market", {})
	if not market.get("active", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["active"][0].get("event_id", "")))
		return "%s — %s" % [tr(event.get("name_key", "")), tr(event.get("description_key", ""))]
	if not market.get("previews", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["previews"][0].get("event_id", "")))
		return "%s: %s" % [tr("MARKET_PREVIEW"), tr(event.get("name_key", ""))]
	return tr("MARKET_CALM")

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
	copy.add_child(_label(title_text, 28, ThemeMaker.COLORS.cream))
	var sub := _label(subtitle, 21, accent.lightened(0.15))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(sub)
	return row

func _event_card(event_state: Dictionary, preview: bool) -> Control:
	var event := DataRepository.get_entry("events", str(event_state.get("event_id", "")))
	var card := _card()
	card.name = "MarketEventPreview" if preview else "MarketEventActive"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_label("%s · %s" % [tr("MARKET_PREVIEW") if preview else tr("MARKET_ACTIVE"), tr(event.get("name_key", ""))], 27, ThemeMaker.COLORS.orange if preview else ThemeMaker.COLORS.green))
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
	_show_toast(tr("CONTRACT_NO_DC"))

func _show_rack_picker(datacenter_id: String, slot: int) -> void:
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
				"text": "%s · $%s\n⚡ %s   ♨ %s   $ %s/%s\n%s" % [
					tr(rack.get("name_key", "")), Game.format_number(rack_cost),
					Game.format_number(float(rack.get("power", 0.0))), Game.format_number(float(rack.get("heat", 0.0))),
					Game.format_number(float(rack.get("income_per_month", 0.0))), tr("MONTH_SHORT"),
					_rack_trait_label(float(rack.get("market_sensitivity", 1.0))),
				],
			})
	_show_choice(tr("INSTALL"), choices, func(rack_id: String) -> void: _preview_rack_install(datacenter_id, slot, rack_id))

func _preview_rack_install(datacenter_id: String, slot: int, rack_id: String) -> void:
	var board := _visible_datacenter_board(datacenter_id)
	if board != null:
		board.set_placement_preview(slot, rack_id)
	var rack := DataRepository.get_entry("racks", rack_id)
	var state := board.placement_state_for_slot(slot, rack_id) if board != null else {}
	var hint := str(state.get("hint", ""))
	var body := "%s\n%s\n%s: %s   %s: %s   %s: $%s/%s" % [
		tr(rack.get("name_key", "")), hint,
		tr("RACK_STAT_POWER"), Game.format_number(float(rack.get("power", 0.0))),
		tr("RACK_STAT_HEAT"), Game.format_number(float(rack.get("heat", 0.0))),
		tr("RACK_STAT_OUTPUT"), Game.format_number(float(rack.get("income_per_month", 0.0))), tr("MONTH_SHORT"),
	]
	_present_action_sheet(tr("INSTALL"), body, [{"id": "confirm", "text": "%s · $%s" % [tr("CONFIRM"), Game.format_number(Game.rack_purchase_cost(rack_id))], "color": ThemeMaker.COLORS.green}], func(choice: String) -> void:
		if choice == "confirm":
			_handle_result(Game.install_rack(datacenter_id, slot, rack_id))
	)
	var overlay := find_child("ActionSheetOverlay", true, false)
	if overlay != null and board != null:
		overlay.tree_exiting.connect(board.clear_placement_preview)

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
	var parts := _create_world_sheet("BuildingPicker", 620)
	var overlay := parts["overlay"] as ColorRect
	var sheet_box := parts["box"] as VBoxContainer
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	sheet_box.add_child(heading)
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_copy)
	heading_copy.add_child(_label(tr("BUILD_DATA_CENTER"), 36, ThemeMaker.COLORS.cream))
	var plot_index := 1
	for plot: Dictionary in Game.state.get("plots", []):
		if str(plot.get("id", "")) == plot_id:
			plot_index = int(plot.get("index", 1))
			break
	heading_copy.add_child(_label(tr("PLOT_EMPTY") % plot_index, 22, ThemeMaker.COLORS.cyan))
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	heading.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_box.add_child(scroll)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	scroll.add_child(cards)
	for building_id: String in DataRepository.get_table("buildings").get("items", {}):
		var building := DataRepository.get_entry("buildings", building_id)
		if not Game.is_unlocked(building):
			continue
		if bool(building.get("tutorial_only", false)) and bool(Game.state.get("flags", {}).get("standard_built", false)):
			continue
		var card := Button.new()
		card.name = "Building_%s" % building_id
		card.custom_minimum_size = Vector2(322, 418)
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

func _create_world_sheet(node_name: String, sheet_height: float) -> Dictionary:
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
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 20
	sheet.offset_top = -sheet_height
	sheet.offset_right = -20
	sheet.offset_bottom = -18
	sheet.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	sheet.set_meta("open_audio", "sfx_sheet_open")
	overlay.add_child(sheet)
	var box := VBoxContainer.new()
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
	sheet.modulate.a = 0.0
	sheet.position.y += 54
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.18)
	tween.tween_property(sheet, "position:y", sheet.position.y - 54, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_wire_sheet_interactions(overlay, sheet, handle_center, true)
	AudioService.play_sfx("sfx_sheet_open")
	return {"overlay": overlay, "sheet": sheet, "box": box}

func _dismiss_world_sheet(overlay: CanvasItem, after: Callable = Callable()) -> void:
	_animate_sheet_dismiss(overlay, after, true)

func _dismiss_action_sheet(overlay: CanvasItem, after: Callable = Callable()) -> void:
	_animate_sheet_dismiss(overlay, after, false)

func _animate_sheet_dismiss(overlay: CanvasItem, after: Callable, reset_world: bool) -> void:
	if not is_instance_valid(overlay) or bool(overlay.get_meta("dismissing", false)):
		return
	overlay.set_meta("dismissing", true)
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
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if pressed and not sheet.get_global_rect().has_point(_pointer_position(event)):
			_animate_sheet_dismiss(overlay, Callable(), reset_world)
			overlay.accept_event()
	)
	var drag := {"active": false, "start_y": 0.0, "base_y": 0.0, "last_y": 0.0, "last_ms": 0}
	handle_area.gui_input.connect(func(event: InputEvent) -> void:
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
		return
	selected_datacenter_id = datacenter_id
	park_map.focus_target(datacenter_id)
	var parts := _create_world_sheet("DatacenterContext", 1380)
	var overlay := parts["overlay"] as ColorRect
	var sheet_box := parts["box"] as VBoxContainer
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	sheet_box.add_child(header)
	header.add_child(_icon_view(_datacenter_context_asset(dc, building), Vector2(124, 124)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(copy)
	copy.add_child(_label(tr(building.get("name_key", "")), 34, ThemeMaker.COLORS.cream))
	copy.add_child(_label(_datacenter_status_text(dc), 23, _datacenter_status_color(dc)))
	var close_button := Widgets.close_button(_dismiss_world_sheet.bind(overlay))
	header.add_child(close_button)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	sheet_box.add_child(metrics)
	metrics.add_child(_metric_chip(tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc)), ThemeMaker.COLORS.green))
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	metrics.add_child(_metric_chip("%s  %d%%" % [tr("LIFESPAN"), int(progress * 100.0)], ThemeMaker.COLORS.yellow))
	if str(dc.get("status", "")) == "ruined":
		sheet_box.add_child(_button(tr("DEMOLISH"), func() -> void:
			_dismiss_world_sheet(overlay, _demolish.bind(datacenter_id))
		, ThemeMaker.COLORS.red))
		return
	var board := _create_datacenter_board(datacenter_id)
	sheet_box.add_child(board)
	var powered := not str(dc.get("power_unit", "")).is_empty()
	var contract_action := func() -> void:
		if powered:
			_dismiss_world_sheet(overlay, _open_datacenter_detail.bind(datacenter_id, "contracts"))
		else:
			_show_toast(tr("BOARD_NEED_POWER"))
	var contract_button := _button(tr("SIGN_CONTRACT"), contract_action, ThemeMaker.COLORS.sky if powered else Color("6f7b88"))
	contract_button.name = "ContractCTA"
	_set_button_asset(contract_button, "ic_contract", 42)
	sheet_box.add_child(contract_button)
	if not powered:
		var power_hint := _label(tr("BOARD_NEED_POWER"), 20, Color("b8c2cc"))
		power_hint.name = "ContractPowerHint"
		power_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		power_hint.max_lines_visible = 1
		power_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sheet_box.add_child(power_hint)
	if progress >= float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6)):
		var refund := Rules.retirement_value(dc, Game.simulation_time(), Game.data)
		var retire_button := _button("%s · +$%s" % [tr("RETIRE"), Game.format_number(refund)], _retire.bind(datacenter_id), ThemeMaker.COLORS.orange)
		retire_button.name = "RetireButton"
		sheet_box.add_child(retire_button)

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
	_present_action_sheet(
		tr("BUY_NEXT_PLOT"),
		tr("PLOT_FOR_SALE") % [Game.state.get("plots", []).size() + 1, Game.format_number(Game.next_plot_price())],
		choices,
		func(choice: String) -> void:
			if choice == "buy":
				_handle_result(Game.buy_next_plot())
	)

func _show_attachment_picker(datacenter_id: String, kind: String, edge: String) -> void:
	var choices: Array[Dictionary] = []
	for attachment_id: String in DataRepository.get_table("attachments").get("items", {}):
		var item := DataRepository.get_entry("attachments", attachment_id)
		if item.get("kind", "") == kind and Game.is_unlocked(item):
			var stat := "⚡ %s" % Game.format_number(float(item.get("capacity", 0.0))) if kind == "power" else "❄ %s · ▦ 3" % Game.format_number(float(item.get("cooling", 0.0)))
			choices.append({"id": attachment_id, "height": 108, "cost": float(item.get("cost", 0.0)), "text": "%s · $%s\n%s" % [tr(item.get("name_key", "")), Game.format_number(float(item.get("cost", 0.0))), stat]})
	_show_choice(tr("INSTALL"), choices, func(attachment_id: String) -> void:
		var result: Dictionary = Game.install_power(datacenter_id, attachment_id) if kind == "power" else Game.install_cooler(datacenter_id, edge, attachment_id)
		_handle_result(result)
		if bool(result.get("ok", false)) and kind == "cooler":
			_play_fx_at_world("fx_snowflake", datacenter_id, 170)
	)

func _show_rack_actions(datacenter_id: String, slot: int) -> void:
	var installed: Dictionary = Game.find_datacenter(datacenter_id).get("racks", [])[slot]
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
		choices.append({"id": "install_ad", "text": "%s · −%s" % [tr("WATCH_AD"), Game.format_duration(ad_reduction)]})
		choices.append({"id": "install_gems", "text": "%s · %d %s" % [tr("SPEED_UP"), gem_cost, tr("GEMS_REWARD_SHORT")]})
	elif installed.get("status", "") == "faulted":
		body = tr("FAULTED")
		status_color = ThemeMaker.COLORS.red
		choices.append({"id": "repair", "text": tr("REPAIR"), "color": ThemeMaker.COLORS.green})
		choices.append({"id": "ad", "text": tr("WATCH_AD")})
		choices.append({"id": "gems", "text": "%s · 2 %s" % [tr("REPAIR"), tr("GEMS_REWARD_SHORT")]})
	else:
		var enabled := bool(installed.get("enabled", true))
		body = tr("RACK_DISABLED") if not enabled else tr("POWERED")
		status_color = Color("aeb8c4") if not enabled else ThemeMaker.COLORS.green
		choices.append({"id": "power", "text": tr("RACK_TURN_ON") if not enabled else tr("RACK_TURN_OFF"), "color": ThemeMaker.COLORS.green if not enabled else ThemeMaker.COLORS.sky})
	if installed.get("status", "") != "installing":
		choices.append({"id": "uninstall", "text": tr("RETIRE")})
	_present_action_sheet(tr(rack.get("name_key", "RACKS")), body, choices, func(action: String) -> void:
		match action:
			"install_ad": _handle_result(Game.request_reward("rack_install:%s:%d" % [datacenter_id, slot]))
			"install_gems": _handle_result(Game.speed_up_rack_install_with_gems(datacenter_id, slot))
			"repair": _handle_result(Game.dispatch_repair(datacenter_id, slot))
			"ad": _handle_result(Game.request_reward("repair:%s:%d" % [datacenter_id, slot]))
			"gems": _handle_result(Game.instant_repair_with_gems(datacenter_id, slot))
			"power": _handle_result(Game.set_rack_enabled(datacenter_id, slot, not bool(installed.get("enabled", true))))
			"uninstall": _handle_result(Game.uninstall_rack(datacenter_id, slot))
	, true, status_color)

func _show_choice(title_text: String, choices: Array[Dictionary], callback: Callable) -> void:
	_present_action_sheet(title_text, "", choices, callback)

func _present_action_sheet(title_text: String, body: String, choices: Array[Dictionary], callback: Callable, show_cancel: bool = true, body_color: Color = ThemeMaker.COLORS.cyan) -> void:
	var overlay := ColorRect.new()
	overlay.name = "ActionSheetOverlay"
	overlay.color = Color(0.015, 0.03, 0.06, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.tree_exiting.connect(_request_hud_refresh)
	add_child(overlay)
	call_deferred("_refresh_tutorial")

	var sheet := PanelContainer.new()
	sheet.name = "ContextSheet"
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
	sheet_box.add_child(heading)
	var title_label := _label(title_text, 36, ThemeMaker.COLORS.cream)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title_label)
	var close_button := Widgets.close_button(_dismiss_action_sheet.bind(overlay))
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
	if show_cancel:
		var cancel_button := _button(tr("CANCEL"), _dismiss_action_sheet.bind(overlay), Color("263d59"))
		cancel_button.custom_minimum_size.y = 92
		sheet_box.add_child(cancel_button)

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
	sheet.position.y += 64
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.2)
	tween.tween_property(sheet, "position:y", sheet.position.y - 64, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

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
	_add_era_confetti(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "OfflineRewardCard"
	card.custom_minimum_size = Vector2(710, 980)
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_coin_pile())
	var income := float(report.get("income", 0.0))
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
			var event_row := HBoxContainer.new()
			event_row.add_theme_constant_override("separation", 10)
			event_row.add_child(_icon_view(str(item.get("icon", "ic_check")), Vector2(38, 38)))
			event_row.add_child(_label("%d · %s" % [int(item.get("count", 0)), tr(item.get("key", ""))], 20, ThemeMaker.COLORS.ink))
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
	if not report.get("completed", []).is_empty(): rows.append({"icon": "ic_check", "count": report["completed"].size(), "key": "TOAST_CONSTRUCTION_COMPLETE"})
	if not report.get("faults", []).is_empty(): rows.append({"icon": "ic_warning", "count": report["faults"].size(), "key": "FAULTED"})
	if not report.get("events", []).is_empty(): rows.append({"icon": "ic_market_up", "count": report["events"].size(), "key": "NAV_MARKET"})
	if not report.get("aging", []).is_empty(): rows.append({"icon": "ic_retire", "count": report["aging"].size(), "key": "LIFESPAN"})
	return rows

func _dismiss_full_overlay(overlay: CanvasItem) -> void:
	if not is_instance_valid(overlay) or bool(overlay.get_meta("dismissing", false)):
		return
	overlay.set_meta("dismissing", true)
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 0.20)
	tween.tween_callback(overlay.queue_free)

func _offline_events_summary(report: Dictionary) -> String:
	var lines: Array[String] = []
	if not report.get("completed", []).is_empty(): lines.append("✓ %d %s" % [report["completed"].size(), tr("TOAST_CONSTRUCTION_COMPLETE")])
	if not report.get("faults", []).is_empty(): lines.append("⚠ %d %s" % [report["faults"].size(), tr("FAULTED")])
	if not report.get("events", []).is_empty(): lines.append("● %d %s" % [report["events"].size(), tr("NAV_MARKET")])
	if not report.get("contracts", []).is_empty(): lines.append("◆ %d %s" % [report["contracts"].size(), tr("SIGN_CONTRACT")])
	return "\n".join(lines)

func _confirm_prestige() -> void:
	var projection := _prestige_projection()
	var body := "%s\n%s\n%s" % [
		tr("PRESTIGE_GAIN_DETAIL") % [float(projection.get("current", 1.0)), float(projection.get("projected", 1.0))],
		tr("PRESTIGE_KEEP_LIST"),
		tr("PRESTIGE_LIQUIDATE") % Game.format_number(float(projection.get("worth", 0.0))),
	]
	_present_action_sheet(tr("PRESTIGE"), body, [{"id": "continue", "text": tr("PRESTIGE_CONTINUE"), "color": ThemeMaker.COLORS.purple}], func(choice: String) -> void:
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

func _confirm(title_text: String, body: String, callback: Callable) -> void:
	var choices: Array[Dictionary] = [{"id": "confirm", "text": tr("CONFIRM"), "color": ThemeMaker.COLORS.red}]
	_present_action_sheet(title_text, body, choices, func(choice: String) -> void:
		if choice == "confirm":
			callback.call()
	)

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
	selected_datacenter_id = datacenter_id
	_detail_focus = "board" if focus in ["racks", "infrastructure"] else focus
	active_page = "detail"
	_request_full_refresh()

func _demolish(datacenter_id: String) -> void:
	_handle_result(Game.demolish_ruin(datacenter_id))

func _retire(datacenter_id: String) -> void:
	_confirm(tr("RETIRE"), tr("RETIRE"), func() -> void:
		var source := park_map.world_position_of(datacenter_id) if park_map != null else Vector2.ZERO
		var result := Game.retire_datacenter(datacenter_id)
		_handle_result(result)
		if bool(result.get("ok", false)):
			_fly_cash_reward(source, 8)
		_navigate("map")
	)

func _sign_contract(datacenter_id: String, customer_id: String) -> void:
	var dc := Game.find_datacenter(datacenter_id)
	if dc.is_empty():
		return
	if str(dc.get("power_unit", "")).is_empty():
		_show_toast(tr("BOARD_NEED_POWER"))
		return
	var fee := Game.contract_switch_fee(datacenter_id, customer_id)
	var current := Game.datacenter_monthly_income(dc)
	var projected := _projected_datacenter_income(dc, customer_id)
	var percent := (projected / maxf(0.01, current) - 1.0) * 100.0 if current > 0.0 else 100.0
	var body := tr("CONTRACT_CONFIRM_DELTA") % [Game.format_number(current), Game.format_number(projected), percent]
	body += "\n" + (tr("CONTRACT_FREE_SWITCH") if fee <= 0.0 else tr("CONTRACT_BREACH_FEE") % Game.format_number(fee))
	body += "\n" + tr("CONTRACT_TERM_INFO")
	_present_action_sheet(tr("SWITCH_CONTRACT"), body, [{"id": "confirm", "text": "%s · %s" % [tr("CONFIRM"), tr("CONTRACT_PROJECTED") % Game.format_number(projected)], "color": ThemeMaker.COLORS.green}], func(choice: String) -> void:
		if choice == "confirm":
			_complete_contract_signing(datacenter_id, customer_id)
	)

func _complete_contract_signing(datacenter_id: String, customer_id: String) -> void:
	var result := Game.sign_contract(datacenter_id, customer_id)
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

func _upgrade_network() -> void:
	_handle_result(Game.upgrade_network())

func _upgrade_repair() -> void:
	_handle_result(Game.upgrade_repair_team())

func _purchase(product_id: String) -> void:
	# StoreKit completion owns the final success/failure toast and its semantic
	# sound. Avoid a second generic success chime while the transaction is pending.
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

func _handle_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_haptic(HAPTIC_MEDIUM)
		_show_toast(tr("TOAST_CONSTRUCTION_STARTED") if result.has("construction") or result.has("rack_installation") else tr("CONFIRM"), "sfx_success_chime")
	else:
		_show_toast(_reason_text(str(result.get("reason", "unknown"))), "sfx_error_thud")
	_request_hud_refresh()

func _reason_text(reason: String) -> String:
	var keys := {
		"not_enough_cash": "NOT_ENOUGH_CASH", "not_enough_gems": "NOT_ENOUGH_GEMS", "locked": "LOCKED",
		"queue_full": "REASON_QUEUE_FULL", "slot_locked": "LOCKED", "slot_occupied": "INSTALLING",
		"rack_install_limit": "REASON_RACK_INSTALL_LIMIT", "rack_unavailable": "LOCKED",
		"too_new_to_retire": "LIFESPAN", "cooler_slots_full": "LOCKED", "building_tier_too_low": "LOCKED",
		"construction_in_progress": "REASON_IN_PROGRESS", "not_an_upgrade": "REASON_NOT_UPGRADE",
		"reward_unavailable": "LOCKED", "reward_limit": "REASON_REWARD_LIMIT", "ticket_unavailable": "REASON_TICKET",
		"reward_pending": "REASON_IN_PROGRESS",
		"already_owned": "REASON_ALREADY_OWNED", "purchase_limit": "REASON_ALREADY_OWNED", "purchase_pending": "REASON_PURCHASE_PENDING",
		"product_unavailable": "LOCKED",
	}
	return tr(keys.get(reason, reason))

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

func _on_contract_renewal_opened(_datacenter_id: String, _customer_id: String, _window_end_at: float) -> void:
	_show_toast(tr("TOAST_CONTRACT_RENEWAL"))
	_request_full_refresh()

func _on_market_event_started(event_id: String) -> void:
	_show_market_banner(event_id, true)
	match event_id:
		"industry_winter":
			_play_fx("fx_frost_patch")
			_play_fx("fx_snowflake", 250)
		"digital_wave": _play_fx("fx_wind_streak")
		"mining_crash", "policy_tightening": _play_fx("fx_smoke_puff")
		"coin_boom": _play_fx("fx_coin")
		"ai_model_boom": _play_fx("fx_glow_ring")
		_: _play_fx("fx_glow_ring", 260)

func _on_market_event_ended(event_id: String) -> void:
	_show_market_banner(event_id, false)

func _show_market_banner(event_id: String, started: bool) -> void:
	var existing := find_child("MarketEventBanner", true, false)
	if existing != null:
		existing.queue_free()
	var event := DataRepository.get_entry("events", event_id)
	var message := tr("MARKET_EVENT_STARTED" if started else "MARKET_EVENT_ENDED") % tr(event.get("name_key", ""))
	var banner := _button(message, _navigate.bind("market"), ThemeMaker.COLORS.orange if started else ThemeMaker.COLORS.sky)
	banner.name = "MarketEventBanner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 44
	banner.offset_top = -110
	banner.offset_right = -44
	banner.offset_bottom = -18
	banner.z_index = 96
	_set_button_asset(banner, "ic_market_up", 42)
	add_child(banner)
	var tween := create_tween()
	tween.tween_property(banner, "position:y", 130.0, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(4.0)
	tween.tween_property(banner, "position:y", -120.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(banner.queue_free)

func _on_reward_granted(_placement: String, _payload: Dictionary) -> void:
	AudioService.play_sfx("sfx_cash")
	_fly_cash_reward(Vector2.ZERO, 8)
	_haptic(HAPTIC_SUCCESS)

func _fly_cash_reward(source: Vector2, count: int) -> void:
	if fx_layer == null or cash_label == null:
		return
	var chip := _cash_chip_target()
	fx_layer.fly_coins(source, chip, count)

func _cash_chip_target() -> Control:
	var chip := find_child("CashResource", true, false) as Control
	return chip if chip != null else cash_label

func _on_world_alert_selected(datacenter_id: String, alert_type: String, slot: int) -> void:
	match alert_type:
		"fault": _show_rack_actions(datacenter_id, slot)
		"unpowered": _show_attachment_picker(datacenter_id, "power", "")
		"contract": _open_datacenter_detail(datacenter_id, "contracts")
		"overheat": _open_datacenter_detail(datacenter_id, "racks")
		_: _show_datacenter_context(datacenter_id)

func _offline_report_is_material(report: Dictionary) -> bool:
	if float(report.get("elapsed_seconds", 0.0)) < 60.0:
		return false
	return float(report.get("income", 0.0)) >= 1.0 or not report.get("completed", []).is_empty() or not report.get("faults", []).is_empty() or not report.get("events", []).is_empty() or not report.get("contracts", []).is_empty() or not report.get("aging", []).is_empty()

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
	if status in ["arrears", "game_over"]:
		_on_bankruptcy_state_changed(status)

func _on_bankruptcy_state_changed(status: String) -> void:
	if status == "arrears":
		_show_toast(tr("BANKRUPTCY_WARNING"))
		_play_music("music_crisis")
		_show_arrears_hud()
	elif status == "normal":
		_clear_crisis_hud()
		_play_music("music_main")
	elif status == "game_over":
		_show_game_over_overlay()

func _refresh_arrears_hud() -> void:
	var status := str(Game.state.get("bankruptcy", {}).get("status", "normal"))
	if status != "arrears":
		if status == "normal":
			_clear_crisis_hud()
		return
	var banner := find_child("ArrearsBanner", true, false) as PanelContainer
	if banner == null:
		_show_arrears_hud()
		banner = find_child("ArrearsBanner", true, false) as PanelContainer
	if banner == null:
		return
	var bankruptcy: Dictionary = Game.state.get("bankruptcy", {})
	var limit := float(DataRepository.get_table("economy").get("bankruptcy", {}).get("game_over_after_online_seconds", 21600.0))
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
	if find_child("ArrearsBanner", true, false) != null:
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
	var rescue := Widgets.button(tr("ARREARS_RESCUE"), func() -> void: _handle_result(Game.request_reward("arrears_rescue")), "primary")
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

func _clear_crisis_hud() -> void:
	for node_name: String in ["ArrearsBanner", "ArrearsVignette"]:
		var node := find_child(node_name, true, false)
		if node != null:
			node.queue_free()

func _show_game_over_overlay() -> void:
	if find_child("GameOverOverlay", true, false) != null:
		return
	_clear_crisis_hud()
	if park_map != null:
		park_map.blackout_sequence()
	_play_fx("fx_smoke_puff", 420)
	var overlay := ColorRect.new()
	overlay.name = "GameOverOverlay"
	overlay.color = Color(0.005, 0.01, 0.02, 0.48)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 110
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.name = "GameOverStatsCard"
	card.custom_minimum_size = Vector2(700, 900)
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
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)
	box.add_child(_icon_view("ic_bankrupt", Vector2(180, 180)))
	var title := _label(tr("GAME_OVER"), 48, ThemeMaker.COLORS.red.lightened(0.16))
	title.name = "GameOverTitle"
	title.add_theme_font_override("font", ThemeMaker.font_bold())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var survival := float(GameClock.wall_time() - int(Game.state.get("clock", {}).get("created_at", GameClock.wall_time())))
	var stats := [
		{"key": "STAT_SURVIVAL", "value": Game.format_duration(survival)},
		{"key": "TOTAL_REVENUE", "value": "$%s" % Game.format_number(float(Game.state["player"].get("total_revenue", 0.0)))},
		{"key": "GAME_OVER_BUILT", "value": str(int(Game.state["player"].get("total_datacenters_built", 0)))},
		{"key": "HIGHEST_NET_WORTH", "value": "$%s" % Game.format_number(float(Game.state["stats"].get("highest_net_worth", 0.0)))},
	]
	for stat_index: int in range(stats.size()):
		var stat: Dictionary = stats[stat_index]
		var row := HBoxContainer.new()
		row.name = "GameOverStat_%d" % stat_index
		box.add_child(row)
		var key_label := _label(tr(stat.get("key", "")), 22, ThemeMaker.COLORS.cyan)
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_label)
		row.add_child(_label(str(stat.get("value", "")), 25, ThemeMaker.COLORS.cream))
	var restart := Widgets.button(tr("GAME_OVER_RESTART"), func() -> void:
		Game.start_new_company()
		overlay.queue_free()
		_navigate("map")
	, "danger")
	restart.name = "GameOverRestart"
	ThemeMaker.apply_prominent_danger(restart)
	box.add_child(restart)
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * 0.84
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(overlay, "color", Color(0.005, 0.01, 0.02, 0.96), 1.0)
	reveal.tween_property(card, "modulate:a", 1.0, 0.34).set_delay(0.72)
	reveal.tween_property(card, "scale", Vector2.ONE, 0.46).set_delay(0.72).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	_request_full_refresh()

func _on_purchase_completed(_product_id: String, success: bool, _message: String) -> void:
	_show_toast(tr("TOAST_PURCHASE_COMPLETE") if success else tr("TOAST_PURCHASE_FAILED"), "sfx_success_chime" if success else "sfx_error_thud")
	if success:
		_play_fx("fx_coin")
	_request_full_refresh()

func _show_toast(message: String, cue_id: String = "") -> void:
	if not cue_id.is_empty():
		AudioService.play_sfx(cue_id)
	toast_label.text = message
	toast_label.position.y = -352.0 if tutorial_overlay != null and tutorial_overlay.visible else -230.0
	toast_label.modulate = Color.WHITE
	toast_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(toast_label, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void: toast_label.visible = false)

func _play_fx(asset_id: String, extent: float = 340.0) -> void:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null or not is_inside_tree():
		return
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 120
	view.set_anchors_preset(Control.PRESET_CENTER)
	view.offset_left = -extent * 0.5
	view.offset_top = -extent * 0.5
	view.offset_right = extent * 0.5
	view.offset_bottom = extent * 0.5
	view.pivot_offset = Vector2(extent, extent) * 0.5
	view.scale = Vector2.ONE * 0.45
	view.modulate.a = 0.0
	add_child(view)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE * 1.15, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, 0.12)
	tween.tween_property(view, "modulate:a", 0.0, 0.35).set_delay(0.5)
	tween.finished.connect(view.queue_free)

func _play_fx_at_world(asset_id: String, target_id: String, extent: float = 190.0) -> void:
	if active_page != "map" or park_map == null:
		return
	var target := park_map.target_global_position(target_id)
	var texture := AssetCatalog.texture(asset_id)
	if target == Vector2.ZERO or texture == null:
		return
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 120
	view.size = Vector2.ONE * extent
	view.global_position = target - view.size * 0.5
	view.pivot_offset = view.size * 0.5
	view.scale = Vector2.ONE * 0.35
	view.modulate.a = 0.0
	add_child(view)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(view, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, 0.10)
	tween.tween_property(view, "modulate:a", 0.0, 0.28).set_delay(0.34)
	tween.finished.connect(view.queue_free)

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
	card.custom_minimum_size = Vector2(720, 1120)
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
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)
	box.add_child(_icon_view("ic_era%d" % era_id, Vector2(250, 230)))
	var unlock_title := _label(tr("ERA_UNLOCK_SUMMARY"), 26, Color("a96b05"))
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

func _add_world_action_caption(parent: Control, text: String, align_right: bool) -> void:
	var caption := _label(text, 20, Color.WHITE)
	caption.name = "OperationsCaption" if align_right else "TaskCaption"
	caption.set_anchors_preset(Control.PRESET_TOP_RIGHT if align_right else Control.PRESET_TOP_LEFT)
	caption.offset_left = -104 if align_right else -8
	caption.offset_top = 0
	caption.offset_right = 8 if align_right else 104
	caption.offset_bottom = 28
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", ThemeMaker.font_world_heavy())
	caption.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	caption.add_theme_constant_override("outline_size", 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(caption)
	# A second fill-only pass keeps the 20u Chinese interiors actually white. The
	# outlined parent remains the contrast and geometry contract; making the fill a
	# child avoids presenting two independent labels to layout/overlap gates.
	var fill := _label(text, 20, Color.WHITE)
	fill.name = "%sFill" % caption.name
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fill.add_theme_font_override("font", ThemeMaker.font_world_heavy())
	fill.add_theme_color_override("font_outline_color", Color.WHITE)
	fill.add_theme_constant_override("outline_size", 1)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_child(fill)

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
		return Vector4(32, 116, 32, 68)
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

func _wrap_scroll(content: Control) -> Control:
	var surface := PanelContainer.new()
	surface.name = "SystemSurface"
	surface.clip_contents = true
	surface.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
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
		button.custom_minimum_size.y = 88
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		if item.has("asset"):
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
	box.custom_minimum_size.x = 650
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	box.add_child(_icon_view(asset_id, Vector2(176, 176)))
	var title := _label(title_text, 34, ThemeMaker.COLORS.cream)
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

func _status_card(asset_id: String, text: String, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 144
	card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(ThemeMaker.SURFACE, 0.96, 24))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(76, 76)))
	var status := _label(text, 27, accent.lightened(0.16))
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	primary_action_text.add_theme_font_override("font", ThemeMaker.font_world_heavy())
	primary_action_text.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	primary_action_text.add_theme_constant_override("outline_size", 4)
	primary_action_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	primary_action_text_stack.add_child(primary_action_text)
	primary_action_text_fill = _label("", 28, Color.WHITE)
	primary_action_text_fill.name = "PrimaryWorldActionTextFill"
	primary_action_text_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	primary_action_text_fill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	primary_action_text_fill.add_theme_font_override("font", ThemeMaker.font_world_heavy())
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
	progress.show_percentage = false
	progress.custom_minimum_size.y = 34
	var started := float(item.get("started_at", Game.simulation_time()))
	var completed := float(item.get("complete_at", started + 1.0))
	progress.max_value = maxf(1.0, completed - started)
	progress.value = clampf(Game.simulation_time() - started, 0.0, progress.max_value)
	box.add_child(progress)
	var remaining_label := _label(tr("COMPLETE_IN") % Game.format_duration(maxf(0.0, completed - Game.simulation_time())), 20, ThemeMaker.COLORS.cyan)
	box.add_child(remaining_label)
	box.set_meta("live_update", func() -> void:
		if not is_instance_valid(progress) or not is_instance_valid(remaining_label):
			return
		progress.value = clampf(Game.simulation_time() - started, 0.0, progress.max_value)
		remaining_label.text = tr("COMPLETE_IN") % Game.format_duration(maxf(0.0, completed - Game.simulation_time()))
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
