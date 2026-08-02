extends Control

const ThemeMaker := preload("res://ui/theme_factory.gd")
const Widgets := preload("res://ui/widgets.gd")
const ChartScene := preload("res://ui/market_chart.gd")
const ParkMapScene := preload("res://gameplay/map/park_map.gd")
const Rules := preload("res://gameplay/game_rules.gd")
const FxLayerScene := preload("res://ui/fx_layer.gd")

const HAPTIC_LIGHT := 8
const HAPTIC_MEDIUM := 16
const HAPTIC_HEAVY := 24
const HAPTIC_SUCCESS := 32

var cash_label: Label
var gems_label: Label
var date_label: Label
var news_label: Label
var tutorial_panel: PanelContainer
var tutorial_label: Label
var tutorial_icon: TextureRect
var world_host: Control
var park_map: ParkMap
var shell_header: PanelContainer
var news_panel: PanelContainer
var navigation_panel: PanelContainer
var era_icon: TextureRect
var company_label: Label
var primary_action_button: Button
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

func _ready() -> void:
	theme = ThemeMaker.create()
	_build_shell()
	_connect_events()
	AudioService.play_music("music_main")
	call_deferred("_show_pending_offline_report")
	call_deferred("_queue_unseen_era_overlays")
	call_deferred("_show_pending_bankruptcy_state")

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

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1626")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	world_host = Control.new()
	world_host.name = "WorldHost"
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
	topbar.add_theme_constant_override("separation", 8)
	shell_header.add_child(topbar)
	var company_button := Button.new()
	company_button.name = "CompanyButton"
	company_button.custom_minimum_size = Vector2(132, 88)
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
	company_row.add_theme_constant_override("separation", 2)
	company_center.add_child(company_row)
	era_icon = _icon_view("ic_era1", Vector2(46, 46))
	company_row.add_child(era_icon)
	company_label = _label("T1", 21, ThemeMaker.COLORS.cream)
	company_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	company_row.add_child(company_label)
	topbar.add_child(company_button)
	var cash_chip := _resource_chip("ic_cash", ThemeMaker.COLORS.yellow)
	cash_chip.name = "CashResource"
	cash_chip.custom_minimum_size.y = 88
	cash_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_chip.size_flags_stretch_ratio = 1.4
	cash_chip.add_theme_stylebox_override("panel", ThemeMaker.resource_panel())
	cash_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cash_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	cash_chip.gui_input.connect(_on_cash_chip_input)
	cash_label = cash_chip.find_child("Value", true, false) as Label
	topbar.add_child(cash_chip)
	var gem_chip := _resource_chip("ic_diamond", ThemeMaker.COLORS.purple.lightened(0.2))
	gem_chip.name = "GemResource"
	gem_chip.custom_minimum_size.y = 88
	gem_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gem_chip.add_theme_stylebox_override("panel", ThemeMaker.resource_panel())
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
	ThemeMaker.apply_round_button(settings_button, ThemeMaker.COLORS.sky)
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

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "MissionCoach"
	tutorial_panel.position = Vector2(110, 390)
	tutorial_panel.custom_minimum_size = Vector2(540, 112)
	tutorial_panel.size = Vector2(540, 112)
	tutorial_panel.add_theme_stylebox_override("panel", ThemeMaker.dialog_box())
	var tutorial_row := HBoxContainer.new()
	tutorial_row.add_theme_constant_override("separation", 12)
	tutorial_panel.add_child(tutorial_row)
	tutorial_icon = TextureRect.new()
	tutorial_icon.custom_minimum_size = Vector2(68, 68)
	tutorial_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tutorial_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tutorial_row.add_child(tutorial_icon)
	tutorial_label = _label("", 22, ThemeMaker.COLORS.ink)
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.custom_minimum_size.x = 386
	tutorial_label.max_lines_visible = 2
	tutorial_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_row.add_child(tutorial_label)
	stage.add_child(tutorial_panel)

	navigation_panel = PanelContainer.new()
	navigation_panel.name = "WorldActions"
	navigation_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	navigation_panel.offset_top = -116
	navigation_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stage.add_child(navigation_panel)
	var action_layer := Control.new()
	action_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation_panel.add_child(action_layer)
	task_button = Button.new()
	task_button.name = "TaskButton"
	task_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	task_button.offset_left = 0
	task_button.offset_top = -48
	task_button.offset_right = 96
	task_button.offset_bottom = 48
	task_button.tooltip_text = tr("VIEW_QUEUE")
	task_button.pressed.connect(_navigate.bind("build"))
	ThemeMaker.apply_round_button(task_button, ThemeMaker.COLORS.orange)
	_wire_button_motion(task_button)
	_set_button_asset(task_button, "ic_build", 42)
	_add_world_action_caption(task_button, tr("NAV_BUILD"))
	action_layer.add_child(task_button)
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

	operations_button = Button.new()
	operations_button.name = "OperationsButton"
	operations_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	operations_button.offset_left = -96
	operations_button.offset_top = -48
	operations_button.offset_right = 0
	operations_button.offset_bottom = 48
	operations_button.tooltip_text = tr("OPERATIONS_CENTER")
	operations_button.pressed.connect(_show_operations_hub)
	ThemeMaker.apply_round_button(operations_button, ThemeMaker.COLORS.sky)
	_wire_button_motion(operations_button)
	operations_button.text = ""
	var operations_asset := "ic_operations" if AssetCatalog.texture("ic_operations") != null else "ic_network"
	_set_button_asset(operations_button, operations_asset, 42)
	operations_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_world_action_caption(operations_button, tr("OPERATIONS_SHORT"))
	action_layer.add_child(operations_button)
	operations_badge = Widgets.badge(0)
	operations_badge.position = Vector2(62, -6)
	operations_badge_label = operations_badge.find_child("BadgeValue", true, false) as Label
	operations_badge.visible = false
	operations_button.add_child(operations_badge)

	fx_layer = FxLayerScene.new()
	fx_layer.name = "FxLayer"
	add_child(fx_layer)

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
	company_label.text = tr("ERA_SHORT") % int(player.get("era", 1))
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
	_refresh_tutorial()
	var on_map := active_page == "map"
	# The park is the product's persistent spatial anchor. Deep systems open as
	# high-opacity work surfaces above it instead of replacing the world.
	world_host.visible = true
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
			primary_action_button.text = tr("BUILD_DATA_CENTER")
			_set_button_asset(primary_action_button, "ic_build", 40)
			ThemeMaker.apply_button_color(primary_action_button, ThemeMaker.COLORS.green)
			_animate_primary_action_change(previous_kind)
			return
	var queue_size: int = Game.state.get("construction_queue", []).size()
	if queue_size > 0:
		_primary_action_kind = "queue"
		primary_action_button.text = "%s  ·  %d" % [tr("VIEW_QUEUE"), queue_size]
		_set_button_asset(primary_action_button, "ic_clock", 40)
		ThemeMaker.apply_button_color(primary_action_button, ThemeMaker.COLORS.orange)
		_animate_primary_action_change(previous_kind)
		return
	_primary_action_kind = "buy_plot"
	primary_action_button.text = "%s  ·  $%s" % [tr("BUY_NEXT_PLOT"), Game.format_number(Game.next_plot_price())]
	_set_button_asset(primary_action_button, "ic_cash", 40)
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
	fx_layer.fly_coins(source, cash_label.get_parent().get_parent() as Control, 3)
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
	card.add_theme_stylebox_override("normal", ThemeMaker.glass_panel(Color("142a40"), 0.98, 24, Color(accent, 0.42)))
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
	box.add_child(_segmented_control([
		{"id": "racks", "label": tr("RACKS"), "asset": "slot_empty"},
		{"id": "infrastructure", "label": tr("INFRASTRUCTURE"), "asset": "ic_power"},
		{"id": "contracts", "label": tr("SIGN_CONTRACT"), "asset": "ic_contract"},
	], _detail_focus, _set_detail_focus))
	match _detail_focus:
		"infrastructure": box.add_child(_build_infrastructure_management(dc, progress))
		"contracts": box.add_child(_build_contract_management(dc))
		_: box.add_child(_build_rack_management(dc, building))
	return _wrap_scroll(box)

func _set_detail_focus(focus: String) -> void:
	if _detail_focus == focus:
		return
	_detail_focus = focus
	_request_full_refresh()

func _build_rack_management(dc: Dictionary, building: Dictionary) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 14)
	section.add_child(_section_title(tr("RACKS"), tr("RACKS_SUBTITLE")))
	var interior := Control.new()
	interior.custom_minimum_size.y = 560
	interior.clip_contents = true
	var interior_fill := ColorRect.new()
	interior_fill.color = Color("111b2b")
	interior_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interior_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interior.add_child(interior_fill)
	var interior_texture := AssetCatalog.texture("dc_interior_bg")
	if interior_texture != null:
		var interior_view := TextureRect.new()
		interior_view.texture = interior_texture
		interior_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		interior_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		interior_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		interior_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		interior.add_child(interior_view)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 18
	grid.offset_top = 18
	grid.offset_right = -18
	grid.offset_bottom = -18
	interior.add_child(grid)
	section.add_child(interior)
	var unlocked: Array = building.get("unlocked_slots", [])
	for slot: int in range(9):
		var slot_open := false
		for raw_slot: Variant in unlocked:
			if int(raw_slot) == slot: slot_open = true
		var rack_button := Button.new()
		rack_button.custom_minimum_size = Vector2(0, 150)
		rack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not slot_open:
			rack_button.text = tr("LOCKED")
			rack_button.disabled = true
			ThemeMaker.apply_button_color(rack_button, Color("566578"))
			_set_button_asset(rack_button, "slot_locked", 86)
		elif dc["racks"][slot] == null:
			rack_button.text = tr("EMPTY_SLOT")
			rack_button.pressed.connect(_show_rack_picker.bind(str(dc.get("id", "")), slot))
			ThemeMaker.apply_button_color(rack_button, ThemeMaker.COLORS.green)
			_set_button_asset(rack_button, "slot_empty", 86)
		else:
			var installed: Dictionary = dc["racks"][slot]
			var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
			var runtime := Rules.rack_runtime_status(dc, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
			var status_text := _rack_status_text(installed, runtime)
			rack_button.text = "%s\n%s" % [tr(rack.get("name_key", "")), status_text]
			rack_button.pressed.connect(_show_rack_actions.bind(str(dc.get("id", "")), slot))
			var color := ThemeMaker.COLORS.red if bool(runtime.get("faulted", false)) else (ThemeMaker.COLORS.orange if bool(runtime.get("overheated", false)) else ThemeMaker.COLORS.sky)
			if not bool(installed.get("enabled", true)): color = Color("566578")
			if not bool(runtime.get("powered", false)): color = Color("566578")
			ThemeMaker.apply_button_color(rack_button, color)
			var suffix := "_active"
			if installed.get("status", "") == "installing":
				suffix = "_installing"
			elif installed.get("status", "") in ["faulted", "repairing"]:
				suffix = "_fault"
			elif not bool(runtime.get("powered", false)):
				suffix = "_dark"
			_set_button_asset(rack_button, str(rack.get("asset_prefix", "")) + suffix, 86)
		grid.add_child(rack_button)
	return section

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
	section.add_theme_constant_override("separation", 14)
	var current_customer := str(dc.get("customer_id", ""))
	var subtitle := tr("CONTRACT_CURRENT") % tr(DataRepository.get_entry("customers", current_customer).get("name_key", "CONTRACT_NONE"))
	if not current_customer.is_empty():
		var renewal_end := float(dc.get("renewal_window_end_at", 0.0))
		if renewal_end > Game.simulation_time():
			subtitle += "\n" + tr("CONTRACT_RENEWAL_WINDOW") % Game.format_duration(renewal_end - Game.simulation_time())
		else:
			subtitle += "\n" + tr("CONTRACT_REMAINING") % Game.format_duration(maxf(0.0, float(dc.get("contract_end_at", 0.0)) - Game.simulation_time()))
	section.add_child(_section_title(tr("SIGN_CONTRACT"), subtitle))
	var contracts := GridContainer.new()
	contracts.columns = 2
	contracts.add_theme_constant_override("h_separation", 10)
	contracts.add_theme_constant_override("v_separation", 10)
	section.add_child(contracts)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		var available := int(customer.get("unlock_era", 1)) <= int(Game.state["player"].get("era", 1)) and int(customer.get("minimum_network_level", 1)) <= int(Game.state["player"].get("network_level", 1))
		var fee := Game.contract_switch_fee(str(dc.get("id", "")), customer_id)
		var contract_text := "%s\n×%.2f" % [tr(customer.get("name_key", "")), Game.market_multiplier(customer_id)]
		if not available:
			contract_text = "%s\n%s" % [tr(customer.get("name_key", "")), tr("LOCKED")]
		elif not current_customer.is_empty() and customer_id != current_customer:
			contract_text += " · " + (tr("CONTRACT_FREE_SWITCH") if fee <= 0.0 else "$%s" % Game.format_number(fee))
		var contract_button := _button(contract_text, _sign_contract.bind(str(dc.get("id", "")), customer_id), ThemeMaker.COLORS.green)
		contract_button.disabled = not available
		_set_button_asset(contract_button, str(customer.get("asset_id", "")), 54)
		contracts.add_child(contract_button)
	return section

func _build_market_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_MARKET"), tr("MARKET_CALM") if Game.state.get("market", {}).get("active", []).is_empty() else _news_text(), "ic_market_up"))
	var chart_card := _card()
	var chart_box := VBoxContainer.new()
	chart_box.add_theme_constant_override("separation", 10)
	chart_card.add_child(chart_box)
	var chart_header := HBoxContainer.new()
	chart_header.add_theme_constant_override("separation", 12)
	chart_box.add_child(chart_header)
	chart_header.add_child(_icon_view("ic_market_up", Vector2(54, 54)))
	var chart_copy := VBoxContainer.new()
	chart_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_header.add_child(chart_copy)
	chart_copy.add_child(_label(tr("NAV_MARKET"), 27, ThemeMaker.COLORS.cream))
	chart_copy.add_child(_label(_news_text(), 20, ThemeMaker.COLORS.cyan))
	var chart := ChartScene.new()
	chart.set_series(Game.state.get("market", {}).get("history", {}))
	chart_box.add_child(chart)
	box.add_child(chart_card)
	var customers := GridContainer.new()
	customers.columns = 2
	customers.add_theme_constant_override("h_separation", 12)
	customers.add_theme_constant_override("v_separation", 12)
	box.add_child(customers)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		customers.add_child(_customer_market_card(customer_id, customer))
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
	if not any_event:
		box.add_child(_status_card("ic_market_up", tr("MARKET_CALM"), ThemeMaker.COLORS.green))
	return _wrap_scroll(box)

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
	var era_card := _card()
	var era_row := HBoxContainer.new()
	era_row.add_theme_constant_override("separation", 20)
	era_card.add_child(era_row)
	era_row.add_child(_icon_view("ic_era%d" % era_id, Vector2(132, 132)))
	var era_box := VBoxContainer.new()
	era_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	era_row.add_child(era_box)
	era_box.add_child(_label(tr(era.get("name_key", "")), 36, ThemeMaker.COLORS.yellow))
	if not next_era.is_empty():
		var required := float(next_era.get("revenue_required", 1.0))
		var progress := ProgressBar.new()
		progress.max_value = required
		progress.value = float(player.get("total_revenue", 0.0))
		progress.show_percentage = false
		progress.custom_minimum_size.y = 42
		era_box.add_child(progress)
		era_box.add_child(_label("$%s / $%s → %s" % [Game.format_number(float(player.get("total_revenue", 0.0))), Game.format_number(required), tr(next_era.get("name_key", ""))], 23))
	box.add_child(era_card)
	var network_level := int(player.get("network_level", 1))
	var network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_level), {})
	var network_card := _card()
	var network_box := VBoxContainer.new()
	network_box.add_theme_constant_override("separation", 10)
	network_card.add_child(network_box)
	network_box.add_child(_feature_heading("ic_network", "%s · %s" % [tr("NETWORK"), tr(network.get("name_key", ""))], "×%.2f" % float(network.get("income_multiplier", 1.0)), ThemeMaker.COLORS.cyan))
	var next_network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_level + 1), {})
	if not next_network.is_empty():
		var network_button := _button("%s %s · $%s" % [tr("UPGRADE"), tr(next_network.get("name_key", "")), Game.format_number(float(next_network.get("cost", 0.0)))], _upgrade_network, ThemeMaker.COLORS.sky)
		network_button.disabled = not Game.is_unlocked(next_network)
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
		var repair_button := _button("%s · $%s" % [tr("UPGRADE"), Game.format_number(float(next_repair.get("cost", 0.0)))], _upgrade_repair, ThemeMaker.COLORS.green)
		repair_button.disabled = not Game.is_unlocked(next_repair)
		repair_box.add_child(repair_button)
	box.add_child(repair_card)
	var min_dc := int(DataRepository.get_table("economy").get("prestige", {}).get("minimum_datacenters", 20))
	var prestige_button := _button("%s\n%s" % [tr("PRESTIGE"), tr("PRESTIGE_LOCKED") % min_dc], _confirm_prestige, ThemeMaker.COLORS.purple)
	_set_button_asset(prestige_button, "ic_prestige", 48)
	prestige_button.disabled = int(player.get("total_datacenters_built", 0)) < min_dc
	box.add_child(prestige_button)
	return _wrap_scroll(box)

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
		var achievement_card := PanelContainer.new()
		achievement_card.custom_minimum_size.y = 104
		achievement_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		achievement_card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("102033"), 0.97, 20, ThemeMaker.COLORS.green if done else Color("6b7e91")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		achievement_card.add_child(row)
		row.add_child(_icon_view("ic_check" if done else "ic_lock", Vector2(42, 42)))
		var achievement_label := _label("%s\n%d %s" % [tr(achievement.get("name_key", "")), int(achievement.get("reward_gems", 0)), tr("GEMS_REWARD_SHORT")], 20, ThemeMaker.COLORS.green if done else ThemeMaker.COLORS.cream)
		achievement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		achievement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(achievement_label)
		achievements.add_child(achievement_card)
	return section

func _build_store_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_STORE"), tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0))), "ic_shop"))
	var wallet := _card()
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 18)
	wallet.add_child(wallet_row)
	wallet_row.add_child(_icon_view("ic_diamond", Vector2(92, 92)))
	var wallet_copy := VBoxContainer.new()
	wallet_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet_row.add_child(wallet_copy)
	wallet_copy.add_child(_label(tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0))), 34, ThemeMaker.COLORS.purple.lightened(0.18)))
	wallet_copy.add_child(_label(tr("NAV_STORE"), 22, ThemeMaker.COLORS.cyan))
	box.add_child(wallet)
	for product_id: String in DataRepository.get_table("store").get("items", {}):
		var product := DataRepository.get_entry("store", product_id)
		if int(product.get("unlock_era", 1)) > int(Game.state["player"].get("era", 1)):
			continue
		if int(product.get("unlock_prestige", 0)) > int(Game.state["stats"].get("prestige_count", 0)):
			continue
		var card := _card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		card.add_child(row)
		var product_art := _asset_preview(str(product.get("asset_id", "")), tr(product.get("name_key", "")), ThemeMaker.COLORS.purple, 136)
		product_art.custom_minimum_size.x = 190
		product_art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(product_art)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		copy.add_child(_label(tr(product.get("name_key", "")), 29, ThemeMaker.COLORS.cream))
		if product.has("description_key"):
			var description := _label(tr(product.get("description_key", "")), 21, ThemeMaker.COLORS.cyan)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			copy.add_child(description)
		var fallback_price := "US$ %.2f" % float(product.get("price_usd", 0.0))
		var buy_button := _button(Monetization.localized_price(product_id, fallback_price), _purchase.bind(product_id), ThemeMaker.COLORS.green)
		buy_button.custom_minimum_size.x = 210
		var purchase_state := Game.can_purchase_product(product_id)
		if not bool(purchase_state.get("ok", false)) and str(purchase_state.get("reason", "")) in ["already_owned", "purchase_limit"]:
			buy_button.text = ""
			_set_button_asset(buy_button, "ic_check", 42)
			buy_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			buy_button.disabled = true
		elif OS.get_name() == "iOS" and not Monetization.is_product_available(product_id):
			buy_button.text = "…"
			buy_button.disabled = true
		row.add_child(buy_button)
		box.add_child(card)
	box.add_child(_button(tr("RESTORE_PURCHASES"), Callable(Monetization, "restore_purchases"), ThemeMaker.COLORS.navy))
	return _wrap_scroll(box)

func _build_settings_page() -> Control:
	var box := _page_box()
	box.add_child(_system_page_header(tr("NAV_SETTINGS"), tr("APP_TITLE"), "ic_settings"))
	box.add_child(_label(tr("SETTINGS_LANGUAGE"), 27, ThemeMaker.COLORS.cyan))
	var language_card := _card()
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", 10)
	language_card.add_child(languages)
	box.add_child(language_card)
	var current_locale := TranslationServer.get_locale()
	var english_active := current_locale.begins_with("en")
	var english_button := _button(tr("LANGUAGE_ENGLISH"), Game.set_locale.bind("en"), ThemeMaker.COLORS.sky if english_active else Color("263d59"))
	if english_active:
		_set_button_asset(english_button, "ic_check", 34)
	languages.add_child(english_button)
	var chinese_button := _button(tr("LANGUAGE_CHINESE"), Game.set_locale.bind("zh_CN"), ThemeMaker.COLORS.sky if not english_active else Color("263d59"))
	if not english_active:
		_set_button_asset(chinese_button, "ic_check", 34)
	languages.add_child(chinese_button)
	var preferences := VBoxContainer.new()
	preferences.add_theme_constant_override("separation", 10)
	box.add_child(preferences)
	for setting: Array in [["music_enabled", "SETTINGS_MUSIC"], ["sfx_enabled", "SETTINGS_SFX"], ["haptics_enabled", "SETTINGS_HAPTICS"]]:
		preferences.add_child(_settings_toggle_row(str(setting[0]), str(setting[1])))
	box.add_child(_button(tr("SETTINGS_RESET"), _confirm_reset, ThemeMaker.COLORS.red))
	return _wrap_scroll(box)

func _refresh_tutorial() -> void:
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	var modal_open := find_child("ActionSheetOverlay", true, false) != null or find_child("BuildingPicker", true, false) != null or find_child("DatacenterContext", true, false) != null
	tutorial_panel.visible = active_page == "map" and not modal_open and not bool(tutorial.get("completed", false)) and index < steps.size()
	if tutorial_panel.visible:
		tutorial_label.text = tr(steps[index].get("message_key", ""))
		var guide_assets := ["guide_normal", "guide_thinking", "guide_happy", "guide_alert", "guide_worried", "guide_thinking", "guide_worried", "guide_happy"]
		tutorial_icon.texture = AssetCatalog.texture(guide_assets[mini(index, guide_assets.size() - 1)])
		call_deferred("_position_tutorial_callout")

func _position_tutorial_callout() -> void:
	if not tutorial_panel.visible or active_page != "map":
		return
	var stage := tutorial_panel.get_parent() as Control
	# Mission copy belongs to the HUD rather than the world projection. A stable
	# bottom safe zone keeps it from covering the building it is explaining.
	tutorial_panel.position = Vector2(
		(stage.size.x - tutorial_panel.size.x) * 0.5,
		stage.size.y - 286.0
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
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 128
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("14283c"), 0.97, 22, accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(_icon_view(str(customer.get("asset_id", "")), Vector2(70, 70)))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var customer_name := _label(tr(customer.get("name_key", "")), 22, ThemeMaker.COLORS.cream)
	customer_name.max_lines_visible = 1
	customer_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(customer_name)
	var market_text := "× %.2f" % Game.market_multiplier(customer_id)
	if not available:
		if unlock_era > int(player.get("era", 1)):
			market_text = tr("UNLOCK_AT_ERA") % unlock_era
		else:
			var network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_required), {})
			market_text = tr("UNLOCK_AT_NETWORK") % tr(network.get("name_key", "NETWORK"))
	copy.add_child(_label(market_text, 22 if not available else 27, accent.lightened(0.12)))
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
	var box := VBoxContainer.new()
	card.add_child(box)
	box.add_child(_label("%s · %s" % [tr("MARKET_PREVIEW") if preview else tr("MARKET_ACTIVE"), tr(event.get("name_key", ""))], 27, ThemeMaker.COLORS.orange if preview else ThemeMaker.COLORS.green))
	box.add_child(_label(tr(event.get("description_key", "")), 23, ThemeMaker.COLORS.cream))
	var end_key := "start_at" if preview else "end_at"
	box.add_child(_label(Game.format_duration(maxf(0.0, float(event_state.get(end_key, 0.0)) - Game.simulation_time())), 21, ThemeMaker.COLORS.cyan))
	return card

func _show_rack_picker(datacenter_id: String, slot: int) -> void:
	var choices: Array[Dictionary] = []
	for rack_id: String in DataRepository.get_table("racks").get("items", {}):
		var rack := DataRepository.get_entry("racks", rack_id)
		if Game.is_unlocked(rack):
			choices.append({"id": rack_id, "text": "%s · $%s\n%s" % [tr(rack.get("name_key", "")), Game.format_number(Game.rack_purchase_cost(rack_id)), _rack_market_label(float(rack.get("market_sensitivity", 1.0)))]})
	_show_choice(tr("INSTALL"), choices, func(rack_id: String) -> void: _handle_result(Game.install_rack(datacenter_id, slot, rack_id)))

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
		card.custom_minimum_size = Vector2(322, 418)
		card.focus_mode = Control.FOCUS_NONE
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
		var cost := _label("$%s" % Game.format_number(float(building.get("cost", 0.0))), 27, ThemeMaker.COLORS.yellow)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_content.add_child(cost)
		var duration := _label(tr("COMPLETE_IN") % Game.format_duration(float(building.get("build_seconds", 0.0))), 20, ThemeMaker.COLORS.cyan)
		duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_content.add_child(duration)

func _create_world_sheet(node_name: String, sheet_height: float) -> Dictionary:
	tutorial_panel.visible = false
	var overlay := ColorRect.new()
	overlay.name = node_name
	overlay.color = Color(0.015, 0.03, 0.05, 0.32)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.tree_exiting.connect(_request_hud_refresh)
	add_child(overlay)
	var sheet := PanelContainer.new()
	sheet.name = "ContextSheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 20
	sheet.offset_top = -sheet_height
	sheet.offset_right = -20
	sheet.offset_bottom = -18
	sheet.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
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
	var parts := _create_world_sheet("DatacenterContext", 582)
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
	var tutorial_state: Dictionary = Game.state.get("tutorial", {})
	var tutorial_index := int(tutorial_state.get("step", 0))
	var tutorial_steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	if not bool(tutorial_state.get("completed", false)) and tutorial_index in [1, 2, 3, 4] and tutorial_index < tutorial_steps.size():
		var coach := PanelContainer.new()
		coach.custom_minimum_size.y = 68
		coach.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("1a3045"), Color(ThemeMaker.COLORS.yellow, 0.55), 1, 18))
		var coach_row := HBoxContainer.new()
		coach_row.add_theme_constant_override("separation", 10)
		coach.add_child(coach_row)
		coach_row.add_child(_icon_view("guide_thinking", Vector2(48, 48)))
		var coach_text := _label(tr(tutorial_steps[tutorial_index].get("message_key", "")), 20, ThemeMaker.COLORS.cream)
		coach_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		coach_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		coach_text.max_lines_visible = 2
		coach_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		coach_row.add_child(coach_text)
		sheet_box.add_child(coach)
	var actions := GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 10)
	sheet_box.add_child(actions)
	var action_defs := [
		["racks", "RACKS", "slot_empty", Color("29445d")],
		["infrastructure", "INFRASTRUCTURE", "ic_power", ThemeMaker.COLORS.orange if str(dc.get("power_unit", "")).is_empty() else Color("29445d")],
		["contracts", "SIGN_CONTRACT", "ic_contract", Color("29445d")],
	]
	for definition: Array in action_defs:
		var focus := str(definition[0])
		var action := _button(tr(str(definition[1])), func() -> void:
			_dismiss_world_sheet(overlay, _open_datacenter_detail.bind(datacenter_id, focus))
		, definition[3])
		action.custom_minimum_size.y = 98
		_set_button_asset(action, str(definition[2]), 42)
		actions.add_child(action)
	var details := _button(tr("DC_DETAIL"), func() -> void:
		_dismiss_world_sheet(overlay, _open_datacenter_detail.bind(datacenter_id))
	, Color("263d59"))
	details.custom_minimum_size.y = 88
	sheet_box.add_child(details)

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
			choices.append({"id": attachment_id, "text": "%s · $%s" % [tr(item.get("name_key", "")), Game.format_number(float(item.get("cost", 0.0)))]})
	_show_choice(tr("INSTALL"), choices, func(attachment_id: String) -> void:
		var result: Dictionary = Game.install_power(datacenter_id, attachment_id) if kind == "power" else Game.install_cooler(datacenter_id, edge, attachment_id)
		_handle_result(result)
	)

func _show_rack_actions(datacenter_id: String, slot: int) -> void:
	var installed: Dictionary = Game.find_datacenter(datacenter_id).get("racks", [])[slot]
	var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
	var choices: Array[Dictionary] = []
	var body := ""
	if installed.get("status", "") == "installing":
		var remaining := maxf(0.0, float(installed.get("install_complete_at", 0.0)) - Game.simulation_time())
		body = tr("COMPLETE_IN") % Game.format_duration(remaining)
		var gem_cost := maxi(1, int(ceil(remaining / 600.0)) * int(DataRepository.get_table("economy").get("construction", {}).get("gems_per_600_seconds", 1)))
		var ad_reduction := minf(remaining, float(DataRepository.get_table("economy").get("construction", {}).get("ad_reduction_seconds", 1800.0)))
		choices.append({"id": "install_ad", "text": "%s · −%s" % [tr("WATCH_AD"), Game.format_duration(ad_reduction)]})
		choices.append({"id": "install_gems", "text": "%s · %d %s" % [tr("SPEED_UP"), gem_cost, tr("GEMS_REWARD_SHORT")]})
	elif installed.get("status", "") == "faulted":
		choices.append({"id": "repair", "text": tr("REPAIR")})
		choices.append({"id": "ad", "text": tr("WATCH_AD")})
		choices.append({"id": "gems", "text": "%s · 2 %s" % [tr("REPAIR"), tr("GEMS_REWARD_SHORT")]})
	else:
		body = tr("RACK_DISABLED") if not bool(installed.get("enabled", true)) else tr("POWERED")
		choices.append({"id": "power", "text": tr("RACK_TURN_ON") if not bool(installed.get("enabled", true)) else tr("RACK_TURN_OFF")})
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
	)

func _show_choice(title_text: String, choices: Array[Dictionary], callback: Callable) -> void:
	_present_action_sheet(title_text, "", choices, callback)

func _present_action_sheet(title_text: String, body: String, choices: Array[Dictionary], callback: Callable, show_cancel: bool = true) -> void:
	if active_page == "map":
		tutorial_panel.visible = false
	var overlay := ColorRect.new()
	overlay.name = "ActionSheetOverlay"
	overlay.color = Color(0.015, 0.03, 0.06, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.tree_exiting.connect(_request_hud_refresh)
	add_child(overlay)

	var body_height := 0
	if not body.is_empty():
		body_height = mini(360, 64 + (body.count("\n") + 1) * 42)
	var sheet_height := mini(1180, 300 + choices.size() * 104 + body_height)
	var sheet := PanelContainer.new()
	sheet.name = "ContextSheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 32
	sheet.offset_top = -sheet_height
	sheet.offset_right = -32
	sheet.offset_bottom = -24
	sheet.add_theme_stylebox_override("panel", ThemeMaker.art_panel(true))
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
		var body_label := _label(body, 25, ThemeMaker.COLORS.cyan)
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
		var choice_button := _button(str(choice.get("text", choice_id)), func() -> void:
			_dismiss_action_sheet(overlay, callback.bind(choice_id))
		, choice_color)
		choice_button.custom_minimum_size.y = 92
		choice_box.add_child(choice_button)
	if show_cancel:
		var cancel_button := _button(tr("CANCEL"), _dismiss_action_sheet.bind(overlay), Color("263d59"))
		cancel_button.custom_minimum_size.y = 92
		sheet_box.add_child(cancel_button)

	sheet.modulate.a = 0.0
	sheet.position.y += 64
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.2)
	tween.tween_property(sheet, "position:y", sheet.position.y - 64, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_wire_sheet_interactions(overlay, sheet, handle_center, false)

func _show_pending_offline_report() -> void:
	if _offline_report_is_material(Game.last_offline_report):
		_show_offline_dialog(Game.last_offline_report)

func _show_offline_dialog(report: Dictionary) -> void:
	var body := "%s\n\n%s" % [tr("OFFLINE_EARNED") % Game.format_number(float(report.get("income", 0.0))), _offline_events_summary(report)]
	var choices: Array[Dictionary] = [
		{"id": "double", "text": tr("OFFLINE_DOUBLE"), "color": ThemeMaker.COLORS.purple},
		{"id": "claim", "text": tr("CLAIM"), "color": ThemeMaker.COLORS.green},
	]
	_present_action_sheet(tr("OFFLINE_TITLE"), body, choices, func(choice: String) -> void:
		if choice == "double":
			_handle_result(Game.request_reward("offline_double"))
	)

func _offline_events_summary(report: Dictionary) -> String:
	var lines: Array[String] = []
	if not report.get("completed", []).is_empty(): lines.append("✓ %d %s" % [report["completed"].size(), tr("TOAST_CONSTRUCTION_COMPLETE")])
	if not report.get("faults", []).is_empty(): lines.append("⚠ %d %s" % [report["faults"].size(), tr("FAULTED")])
	if not report.get("events", []).is_empty(): lines.append("● %d %s" % [report["events"].size(), tr("NAV_MARKET")])
	if not report.get("contracts", []).is_empty(): lines.append("◆ %d %s" % [report["contracts"].size(), tr("SIGN_CONTRACT")])
	return "\n".join(lines)

func _confirm_prestige() -> void:
	_confirm(tr("PRESTIGE"), "%s\n$%s" % [tr("PRESTIGE"), Game.format_number(Game.net_worth())], func() -> void: _handle_result(Game.prestige()))

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
	if page == active_page:
		if page == "map" and park_map != null:
			park_map.reset_camera()
		return
	active_page = page
	if page != "detail": selected_datacenter_id = ""
	if page == "map" and park_map != null:
		park_map.reset_camera()
	AudioService.play_sfx("sfx_tap")
	_haptic(HAPTIC_LIGHT)
	if Game.state.get("bankruptcy", {}).get("status", "normal") == "normal":
		AudioService.play_music("music_market" if page == "market" else "music_main")
	_request_full_refresh()

func _open_datacenter(datacenter_id: String) -> void:
	_show_datacenter_context(datacenter_id)

func _open_datacenter_detail(datacenter_id: String, focus: String = "racks") -> void:
	selected_datacenter_id = datacenter_id
	_detail_focus = focus
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
	var fee := Game.contract_switch_fee(datacenter_id, customer_id)
	if fee > 0.0:
		_confirm(tr("SWITCH_CONTRACT"), tr("CONTRACT_BREACH_FEE") % Game.format_number(fee), func() -> void: _complete_contract_signing(datacenter_id, customer_id))
	else:
		_complete_contract_signing(datacenter_id, customer_id)

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
	_handle_result(Game.purchase(product_id))

func _on_setting_toggled(enabled: bool, setting_key: String) -> void:
	Game.set_audio_setting(setting_key, enabled)

func _run_action(action: Callable) -> void:
	_handle_result(action.call())

func _handle_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_haptic(HAPTIC_MEDIUM)
		_show_toast(tr("TOAST_CONSTRUCTION_STARTED") if result.has("construction") or result.has("rack_installation") else tr("CONFIRM"))
	else:
		_show_toast(_reason_text(str(result.get("reason", "unknown"))))
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
	_play_fx_at_world("fx_dust_puff", str(item.get("plot_id", "")), 190)
	var target_id := str(item.get("plot_id", item.get("datacenter_id", "")))
	_fly_cash_reward(park_map.world_position_of(target_id) if park_map != null else Vector2.ZERO, 8)
	_haptic(HAPTIC_MEDIUM)
	get_tree().create_timer(0.38).timeout.connect(func() -> void:
		if is_instance_valid(park_map):
			park_map.celebrate_target(target_id)
	)

func _on_rack_fault_occurred(datacenter_id: String, _slot: int) -> void:
	_play_fx_at_world("fx_spark", datacenter_id, 170)
	_haptic(HAPTIC_HEAVY)

func _on_contract_renewal_opened(_datacenter_id: String, _customer_id: String, _window_end_at: float) -> void:
	_show_toast(tr("TOAST_CONTRACT_RENEWAL"))
	_request_full_refresh()

func _on_market_event_started(event_id: String) -> void:
	match event_id:
		"industry_winter":
			_play_fx("fx_frost_patch")
			_play_fx("fx_snowflake", 250)
		"digital_wave": _play_fx("fx_wind_streak")
		"mining_crash", "policy_tightening": _play_fx("fx_smoke_puff")
		"coin_boom": _play_fx("fx_coin")
		"ai_model_boom": _play_fx("fx_glow_ring")
		_: _play_fx("fx_glow_ring", 260)

func _on_reward_granted(_placement: String, _payload: Dictionary) -> void:
	AudioService.play_sfx("sfx_cash")
	_fly_cash_reward(Vector2.ZERO, 8)
	_haptic(HAPTIC_SUCCESS)

func _fly_cash_reward(source: Vector2, count: int) -> void:
	if fx_layer == null or cash_label == null:
		return
	var chip := cash_label.get_parent().get_parent() as Control
	fx_layer.fly_coins(source, chip, count)

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
		AudioService.play_music("music_crisis")
		var debt := float(Game.state.get("bankruptcy", {}).get("debt", 0.0))
		_present_action_sheet(
			tr("BANKRUPTCY_WARNING"),
			"%s\n$%s" % [tr("BANKRUPTCY_BODY") % Game.format_duration(float(DataRepository.get_table("economy").get("bankruptcy", {}).get("game_over_after_online_seconds", 21600.0))), Game.format_number(debt)],
			[{"id": "rescue", "text": tr("ARREARS_RESCUE"), "color": ThemeMaker.COLORS.orange}],
			func(choice: String) -> void:
				if choice == "rescue":
					_handle_result(Game.request_reward("arrears_rescue"))
		)
	elif status == "normal":
		AudioService.play_music("music_main")
	elif status == "game_over":
		_play_fx("fx_smoke_puff", 420)
		var survival := float(GameClock.wall_time() - int(Game.state.get("clock", {}).get("created_at", GameClock.wall_time())))
		var summary := "%s: $%s\n%s: %s\n%s: $%s\n%s: %d" % [tr("HIGHEST_NET_WORTH"), Game.format_number(float(Game.state["stats"].get("highest_net_worth", 0.0))), tr("STAT_SURVIVAL"), Game.format_duration(survival), tr("TOTAL_REVENUE"), Game.format_number(float(Game.state["player"].get("total_revenue", 0.0))), tr("BUILD"), int(Game.state["player"].get("total_datacenters_built", 0))]
		_present_action_sheet(
			tr("GAME_OVER"),
			summary,
			[{"id": "restart", "text": tr("NEW_COMPANY"), "color": ThemeMaker.COLORS.red}],
			func(choice: String) -> void:
				if choice == "restart":
					Game.start_new_company()
					_navigate("map"),
			false
		)

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
	_show_toast(tr("TOAST_PURCHASE_COMPLETE") if success else tr("TOAST_PURCHASE_FAILED"))
	if success:
		_play_fx("fx_coin")
	_request_full_refresh()

func _show_toast(message: String) -> void:
	toast_label.text = message
	toast_label.position.y = -352.0 if tutorial_panel.visible else -230.0
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
	var overlay := ColorRect.new()
	overlay.name = "EraOverlay"
	overlay.color = Color(0.02, 0.05, 0.11, 0.94)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(720, 660)
	card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("102236"), 0.99, 30, Color(ThemeMaker.COLORS.yellow, 0.58)))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	card.add_child(box)
	box.add_child(_icon_view("ic_era%d" % era_id, Vector2(300, 250)))
	var headline := _label(tr("TOAST_ERA_UNLOCKED"), 48, ThemeMaker.COLORS.yellow)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(headline)
	var era_name := _label(tr(era.get("name_key", "")), 38, ThemeMaker.COLORS.cream)
	era_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(era_name)
	var reward := _label(tr("GEMS_FORMAT") % int(era.get("reward_gems", 0)), 28, ThemeMaker.COLORS.purple.lightened(0.2))
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(reward)
	box.add_child(_button(tr("CONFIRM"), func() -> void:
		Game.mark_era_presented(era_id)
		overlay.queue_free()
		_era_overlay_open = false
		call_deferred("_present_next_era_overlay")
	, ThemeMaker.COLORS.green))
	card.modulate.a = 0.0
	card.scale = Vector2(0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.28)
	tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _page_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	return box

func _resource_chip(asset_id: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = 76
	chip.add_theme_stylebox_override("panel", ThemeMaker.panel(Color(1, 1, 1, 0.035), Color.TRANSPARENT, 0, 18))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(44, 44)))
	var value := _label("", 28, ThemeMaker.COLORS.ink)
	value.name = "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeMaker.apply_numeric_text(value)
	row.add_child(value)
	var affordance := _label("+", ThemeMaker.TYPE_SCALE.heading, ThemeMaker.COLORS.ink)
	affordance.name = "AddAffordance"
	affordance.custom_minimum_size.x = 28
	affordance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	affordance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	affordance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(affordance)
	return chip

func _add_world_action_caption(button: Button, text: String) -> void:
	var caption := _label(text, 18, Color.WHITE)
	caption.name = "EntryCaption"
	caption.position = Vector2(-8, 66)
	caption.size = Vector2(112, 28)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_outline_color", ThemeMaker.COLORS.ink)
	caption.add_theme_constant_override("outline_size", 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)

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
	surface.add_child(scroll)
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
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("091827"), Color(1, 1, 1, 0.08), 1, 22))
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
	card.add_theme_stylebox_override("panel", ThemeMaker.glass_panel(Color("102236"), 0.96, 24))
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
	var card := Widgets.panel(true)
	card.custom_minimum_size.y = 100
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var title := _label(tr(label_key), 28, ThemeMaker.COLORS.cream)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.button_pressed = bool(Game.state.get("settings", {}).get(setting_key, true))
	toggle.custom_minimum_size = Vector2(112, 64)
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
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func() -> void:
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

func _asset_preview(asset_id: String, fallback_text: String, color: Color, height: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("102236"), Color(color, 0.36), 1, 18))
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
