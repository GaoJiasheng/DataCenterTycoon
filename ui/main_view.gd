extends Control

const ThemeMaker := preload("res://ui/theme_factory.gd")
const ChartScene := preload("res://ui/market_chart.gd")
const ParkMapScene := preload("res://gameplay/map/park_map.gd")
const Rules := preload("res://gameplay/game_rules.gd")

var cash_label: Label
var gems_label: Label
var date_label: Label
var news_label: Label
var tutorial_panel: PanelContainer
var tutorial_label: Label
var tutorial_icon: TextureRect
var page_host: Control
var toast_label: Label
var nav_buttons: Dictionary = {}
var active_page := "map"
var selected_datacenter_id := ""
var _needs_refresh := true
var _refresh_cooldown := 0.0
var _era_overlay_queue: Array[int] = []
var _era_overlay_open := false

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
	if _needs_refresh and _refresh_cooldown <= 0.0:
		_refresh_cooldown = 0.25
		_needs_refresh = false
		_refresh()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("101d30")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var safe := MarginContainer.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_margins := _safe_area_margins()
	safe.add_theme_constant_override("margin_left", int(safe_margins.x))
	safe.add_theme_constant_override("margin_top", int(safe_margins.y))
	safe.add_theme_constant_override("margin_right", int(safe_margins.z))
	safe.add_theme_constant_override("margin_bottom", int(safe_margins.w))
	background.add_child(safe)

	var layout := VBoxContainer.new()
	layout.name = "ShellLayout"
	layout.add_theme_constant_override("separation", 12)
	safe.add_child(layout)

	var header := Control.new()
	header.name = "ShellHeader"
	header.custom_minimum_size.y = 154
	layout.add_child(header)
	var header_box := VBoxContainer.new()
	header_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_box.add_theme_constant_override("separation", 10)
	header.add_child(header_box)
	var topbar := HBoxContainer.new()
	topbar.custom_minimum_size.y = 88
	topbar.add_theme_constant_override("separation", 10)
	header_box.add_child(topbar)
	var cash_chip := _resource_chip("ic_cash", ThemeMaker.COLORS.yellow)
	cash_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_chip.size_flags_stretch_ratio = 1.4
	cash_label = cash_chip.find_child("Value", true, false) as Label
	topbar.add_child(cash_chip)
	var gem_chip := _resource_chip("ic_diamond", ThemeMaker.COLORS.purple.lightened(0.2))
	gem_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gems_label = gem_chip.find_child("Value", true, false) as Label
	topbar.add_child(gem_chip)
	var date_chip := PanelContainer.new()
	date_chip.custom_minimum_size = Vector2(190, 88)
	date_chip.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("1b304a"), Color(1, 1, 1, 0.08), 1, 22))
	date_label = _label("", 22, ThemeMaker.COLORS.cream)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	date_chip.add_child(date_label)
	topbar.add_child(date_chip)
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.custom_minimum_size = Vector2(88, 88)
	settings_button.tooltip_text = tr("NAV_SETTINGS")
	settings_button.pressed.connect(_navigate.bind("settings"))
	ThemeMaker.apply_button_color(settings_button, Color("263d59"))
	_set_button_asset(settings_button, "ic_settings", 44)
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topbar.add_child(settings_button)

	var news_panel := PanelContainer.new()
	news_panel.custom_minimum_size.y = 54
	news_panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("152943"), Color(1, 1, 1, 0.07), 1, 18))
	header_box.add_child(news_panel)
	news_label = _label("", 22, ThemeMaker.COLORS.cyan)
	news_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	news_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	news_panel.add_child(news_label)

	tutorial_panel = PanelContainer.new()
	tutorial_panel.custom_minimum_size.y = 94
	tutorial_panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("263e58"), Color(1.0, 0.79, 0.24, 0.55), 1, 20))
	var tutorial_row := HBoxContainer.new()
	tutorial_row.add_theme_constant_override("separation", 12)
	tutorial_panel.add_child(tutorial_row)
	tutorial_icon = TextureRect.new()
	tutorial_icon.custom_minimum_size = Vector2(62, 64)
	tutorial_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tutorial_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tutorial_row.add_child(tutorial_icon)
	tutorial_label = _label("", 23, ThemeMaker.COLORS.cream)
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_row.add_child(tutorial_label)
	layout.add_child(tutorial_panel)

	page_host = Control.new()
	page_host.name = "PageHost"
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.clip_contents = true
	layout.add_child(page_host)

	var navigation_panel := PanelContainer.new()
	navigation_panel.name = "BottomNav"
	navigation_panel.custom_minimum_size.y = 132
	navigation_panel.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("172a43"), Color(1, 1, 1, 0.1), 1, 28))
	layout.add_child(navigation_panel)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	navigation_panel.add_child(navigation)
	var pages := [
		["map", "NAV_MAP"], ["build", "NAV_BUILD"], ["market", "NAV_MARKET"],
		["tech", "NAV_TECH"], ["store", "NAV_STORE"],
	]
	var nav_assets := {"map": "ic_era1", "build": "ic_build", "market": "ic_market_up", "tech": "ic_tech", "store": "ic_shop"}
	for item: Array in pages:
		var page_id := str(item[0])
		var button := _tab_button(page_id, str(item[1]), str(nav_assets.get(page_id, "")))
		nav_buttons[page_id] = button
		navigation.add_child(button)

	toast_label = _label("", 25, Color.WHITE)
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(-360, -238)
	toast_label.size = Vector2(720, 88)
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
	Monetization.product_info_changed.connect(func() -> void: _needs_refresh = true)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.rack_fault_occurred.connect(_on_rack_fault_occurred)
	EventBus.market_event_started.connect(_on_market_event_started)
	EventBus.reward_granted.connect(_on_reward_granted)

func _refresh() -> void:
	var player: Dictionary = Game.state.get("player", {})
	cash_label.text = tr("CASH_FORMAT") % Game.format_number(float(player.get("cash", 0.0)))
	gems_label.text = tr("GEMS_FORMAT") % Game.format_number(float(player.get("gems", 0)))
	var era: Dictionary = DataRepository.get_entry("eras", str(player.get("era", 1)))
	date_label.text = "%s\n%s" % [tr(era.get("name_key", "ERA_1")), GameClock.format_game_date(Game.simulation_time())]
	news_label.text = _news_text()
	_refresh_tutorial()
	_update_nav_styles()
	for child: Node in page_host.get_children():
		page_host.remove_child(child)
		child.queue_free()
	var next_page: Control
	match active_page:
		"map": next_page = _build_map_page()
		"build": next_page = _build_construction_page()
		"market": next_page = _build_market_page()
		"tech": next_page = _build_tech_page()
		"store": next_page = _build_store_page()
		"settings": next_page = _build_settings_page()
		"detail": next_page = _build_datacenter_page()
		_: next_page = _build_map_page()
	page_host.add_child(next_page)
	next_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_map_page() -> Control:
	var box := _page_box()
	box.add_child(_section_title(tr("NAV_MAP"), ""))
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	metrics.add_child(_metric_chip(tr("INCOME_RATE") % Game.format_number(Game.monthly_income()), ThemeMaker.COLORS.green))
	metrics.add_child(_metric_chip(tr("MAINTENANCE") % Game.format_number(Game.monthly_maintenance()), ThemeMaker.COLORS.orange))
	box.add_child(metrics)
	var park_map := ParkMapScene.new()
	park_map.datacenter_selected.connect(_open_datacenter)
	park_map.empty_plot_selected.connect(_show_building_picker)
	park_map.buy_plot_requested.connect(func() -> void: _handle_result(Game.buy_next_plot()))
	box.add_child(park_map)
	park_map.setup(Game.state.get("plots", []))
	var action_card := _card()
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 16)
	action_card.add_child(action_row)
	var action_copy := VBoxContainer.new()
	action_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_copy)
	action_copy.add_child(_label(tr("PLOT_FOR_SALE") % [Game.state.get("plots", []).size() + 1, Game.format_number(Game.next_plot_price())], 25, ThemeMaker.COLORS.cream))
	action_copy.add_child(_label("%d %s · %d %s" % [Game.state.get("plots", []).size(), tr("NAV_MAP"), Game.state.get("construction_queue", []).size(), tr("NAV_BUILD")], 21, ThemeMaker.COLORS.cyan))
	var buy_button := _button(tr("BUY_NEXT_PLOT"), _run_action.bind(Callable(Game, "buy_next_plot")), ThemeMaker.COLORS.green)
	buy_button.custom_minimum_size.x = 250
	action_row.add_child(buy_button)
	box.add_child(action_card)
	return _wrap_scroll(box)

func _plot_card(plot: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 330)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status := str(plot.get("status", "empty"))
	var border := ThemeMaker.COLORS.orange if status == "building" else ThemeMaker.COLORS.sky
	if status == "ruined":
		border = ThemeMaker.COLORS.red
	card.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("2b4564"), border, 3, 20))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_label("#%d" % int(plot.get("index", 0)), 22, ThemeMaker.COLORS.cyan))
	if status == "empty":
		box.add_child(_label(tr("PLOT_EMPTY") % int(plot.get("index", 0)), 27))
		for building_id: String in DataRepository.get_table("buildings").get("items", {}):
			var building: Dictionary = DataRepository.get_entry("buildings", building_id)
			if not Game.is_unlocked(building):
				continue
			if bool(building.get("tutorial_only", false)) and bool(Game.state.get("flags", {}).get("standard_built", false)):
				continue
			var text := "%s · $%s" % [tr(building.get("name_key", "")), Game.format_number(float(building.get("cost", 0.0)))]
			box.add_child(_button(text, _start_building.bind(str(plot.get("id", "")), building_id), ThemeMaker.COLORS.green))
	elif status == "building":
		var item := Game.find_construction(str(plot.get("construction_id", "")))
		var building := DataRepository.get_entry("buildings", str(item.get("building_id", "")))
		box.add_child(_asset_preview(str(building.get("asset_prefix", "")) + "_construction", tr(building.get("name_key", "BUILDING_T0")), ThemeMaker.COLORS.orange, 150))
		box.add_child(_progress_for_job(item))
	else:
		var dc: Dictionary = plot.get("datacenter", {})
		var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
		var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
		var stage := Rules.aging_stage(progress)
		var suffix := "_ruin" if status == "ruined" else ("_dark" if str(dc.get("power_unit", "")).is_empty() else "_active")
		if status != "ruined" and not str(dc.get("power_unit", "")).is_empty():
			if stage == "aging": suffix = "_aged"
			if stage == "decline": suffix = "_decayed"
		box.add_child(_asset_preview(str(building.get("asset_prefix", "")) + suffix, tr(building.get("name_key", "")), border, 155))
		box.add_child(_label("%s · %d%%" % [tr("LIFESPAN"), int(progress * 100.0)], 22, ThemeMaker.COLORS.cream))
		if status == "ruined":
			box.add_child(_button("%s · $%s" % [tr("DEMOLISH"), Game.format_number(Rules.demolition_cost(dc, Game.data))], _demolish.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.red))
		else:
			box.add_child(_label(tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc)), 22, ThemeMaker.COLORS.yellow))
			box.add_child(_button(tr("DC_DETAIL"), _open_datacenter.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.sky))
	return card

func _build_construction_page() -> Control:
	var box := _page_box()
	box.add_child(_section_title(tr("CONSTRUCTION_QUEUE"), "%d / %d" % [Game.state.get("construction_queue", []).size(), int(DataRepository.get_table("economy").get("construction", {}).get("base_queue_capacity", 2))]))
	if Game.state.get("construction_queue", []).is_empty():
		box.add_child(_empty_state(tr("QUEUE_EMPTY")))
	for item: Dictionary in Game.state.get("construction_queue", []):
		var card := _card()
		var inner := VBoxContainer.new()
		card.add_child(inner)
		inner.add_child(_label(_construction_name(item), 28, ThemeMaker.COLORS.cream))
		inner.add_child(_progress_for_job(item))
		var actions := GridContainer.new()
		actions.columns = 2
		actions.add_theme_constant_override("h_separation", 10)
		actions.add_theme_constant_override("v_separation", 10)
		inner.add_child(actions)
		var remaining := maxf(0.0, float(item.get("complete_at", 0.0)) - Game.simulation_time())
		var gems := maxi(1, int(ceil(remaining / 600.0)) * int(DataRepository.get_table("economy").get("construction", {}).get("gems_per_600_seconds", 1)))
		actions.add_child(_button("%s · %d 💎" % [tr("SPEED_UP"), gems], _speedup_job.bind(str(item.get("id", ""))), ThemeMaker.COLORS.purple))
		var tickets := int(Game.state.get("inventory", {}).get("instant_build_tickets", 0))
		if tickets > 0:
			actions.add_child(_button("%s · %d" % [tr("INSTANT_TICKET"), tickets], _use_ticket.bind(str(item.get("id", ""))), ThemeMaker.COLORS.yellow.darkened(0.25)))
		var max_ads := int(DataRepository.get_table("economy").get("construction", {}).get("max_ads_per_project", 2))
		var ad_button := _button("%s · -30m (%d/%d)" % [tr("WATCH_AD"), int(item.get("ad_uses", 0)), max_ads], _reward_job.bind(str(item.get("id", ""))), ThemeMaker.COLORS.purple)
		ad_button.disabled = int(item.get("ad_uses", 0)) >= max_ads
		actions.add_child(ad_button)
		box.add_child(card)
	return _wrap_scroll(box)

func _build_datacenter_page() -> Control:
	var dc := Game.find_datacenter(selected_datacenter_id)
	if dc.is_empty():
		active_page = "map"
		return _build_map_page()
	var box := _page_box()
	var building := DataRepository.get_entry("buildings", str(dc.get("building_id", "")))
	var top := HBoxContainer.new()
	var back_button := _button("‹ %s" % tr("NAV_MAP"), _navigate.bind("map"), Color("263d59"))
	back_button.custom_minimum_size.x = 190
	top.add_child(back_button)
	var title := _label(tr(building.get("name_key", "")), 38, ThemeMaker.COLORS.cream)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	box.add_child(top)
	var progress := Rules.age_progress(dc, Game.simulation_time(), DataRepository.get_table("buildings"))
	box.add_child(_label("%s %d%% · %s" % [tr("LIFESPAN"), int(progress * 100.0), tr("INCOME_RATE") % Game.format_number(Game.datacenter_monthly_income(dc))], 25, ThemeMaker.COLORS.yellow))
	if dc.get("status", "") == "ruined":
		box.add_child(_asset_preview(str(building.get("asset_prefix", "")) + "_ruin", tr("DEMOLISH"), ThemeMaker.COLORS.red, 300))
		box.add_child(_button("%s · $%s" % [tr("DEMOLISH"), Game.format_number(Rules.demolition_cost(dc, Game.data))], _demolish.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.red))
		return _wrap_scroll(box)
	var interior := Control.new()
	interior.custom_minimum_size.y = 510
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
	box.add_child(interior)
	var unlocked: Array = building.get("unlocked_slots", [])
	for slot: int in range(9):
		var slot_open := false
		for raw_slot: Variant in unlocked:
			if int(raw_slot) == slot: slot_open = true
		var rack_button := Button.new()
		rack_button.custom_minimum_size = Vector2(0, 150)
		rack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not slot_open:
			rack_button.text = "🔒\n%s" % tr("LOCKED")
			rack_button.disabled = true
			ThemeMaker.apply_button_color(rack_button, Color("566578"))
			_set_button_asset(rack_button, "slot_locked", 72)
		elif dc["racks"][slot] == null:
			rack_button.text = "+\n%s" % tr("EMPTY_SLOT")
			rack_button.pressed.connect(_show_rack_picker.bind(str(dc.get("id", "")), slot))
			ThemeMaker.apply_button_color(rack_button, ThemeMaker.COLORS.green)
			_set_button_asset(rack_button, "slot_empty", 72)
		else:
			var installed: Dictionary = dc["racks"][slot]
			var rack := DataRepository.get_entry("racks", str(installed.get("rack_id", "")))
			var runtime := Rules.rack_runtime_status(dc, slot, DataRepository.get_table("racks"), DataRepository.get_table("attachments"), DataRepository.get_table("economy"))
			var status_text := _rack_status_text(installed, runtime)
			rack_button.text = "%s\n%s" % [tr(rack.get("name_key", "")), status_text]
			rack_button.pressed.connect(_show_rack_actions.bind(str(dc.get("id", "")), slot))
			var color := ThemeMaker.COLORS.red if bool(runtime.get("faulted", false)) else (ThemeMaker.COLORS.orange if bool(runtime.get("overheated", false)) else ThemeMaker.COLORS.sky)
			if not bool(runtime.get("powered", false)): color = Color("566578")
			ThemeMaker.apply_button_color(rack_button, color)
			var suffix := "_active"
			if installed.get("status", "") == "installing":
				suffix = "_installing"
			elif installed.get("status", "") in ["faulted", "repairing"]:
				suffix = "_fault"
			elif not bool(runtime.get("powered", false)):
				suffix = "_dark"
			_set_button_asset(rack_button, str(rack.get("asset_prefix", "")) + suffix, 72)
		grid.add_child(rack_button)

	box.add_child(_section_title(tr("POWERED"), ""))
	var attachments := GridContainer.new()
	attachments.columns = 2
	attachments.add_theme_constant_override("separation", 10)
	box.add_child(attachments)
	var power_text := tr(DataRepository.get_entry("attachments", str(dc.get("power_unit", ""))).get("name_key", "UNPOWERED"))
	var power_button := _button("⚡ %s" % power_text, _show_attachment_picker.bind(str(dc.get("id", "")), "power", ""), ThemeMaker.COLORS.yellow.darkened(0.2))
	if not str(dc.get("power_unit", "")).is_empty():
		_set_button_asset(power_button, str(dc.get("power_unit", "")) + "_active", 60)
	attachments.add_child(power_button)
	for edge: String in ["north", "east", "south", "west"]:
		var cooler_id := str(dc.get("coolers", {}).get(edge, ""))
		var cooler_name := tr(DataRepository.get_entry("attachments", cooler_id).get("name_key", "INSTALL"))
		var cooler_button := _button("❄ %s\n%s" % [edge.capitalize(), cooler_name], _show_attachment_picker.bind(str(dc.get("id", "")), "cooler", edge), ThemeMaker.COLORS.sky.darkened(0.1))
		if not cooler_id.is_empty():
			_set_button_asset(cooler_button, cooler_id + "_active", 54)
		attachments.add_child(cooler_button)

	box.add_child(_section_title(tr("SIGN_CONTRACT"), tr("CONTRACT_CURRENT") % tr(DataRepository.get_entry("customers", str(dc.get("customer_id", ""))).get("name_key", "CONTRACT_NONE"))))
	var contracts := GridContainer.new()
	contracts.columns = 2
	contracts.add_theme_constant_override("h_separation", 10)
	contracts.add_theme_constant_override("v_separation", 10)
	box.add_child(contracts)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		var available := int(customer.get("unlock_era", 1)) <= int(Game.state["player"].get("era", 1)) and int(customer.get("minimum_network_level", 1)) <= int(Game.state["player"].get("network_level", 1))
		var contract_button := _button("%s\n×%.2f" % [tr(customer.get("name_key", "")), Game.market_multiplier(customer_id)], _sign_contract.bind(str(dc.get("id", "")), customer_id), ThemeMaker.COLORS.green)
		contract_button.disabled = not available
		_set_button_asset(contract_button, str(customer.get("asset_id", "")), 54)
		contracts.add_child(contract_button)
	if progress >= float(DataRepository.get_table("economy").get("aging", {}).get("aging_start", 0.6)):
		var refund := Rules.retirement_value(dc, Game.simulation_time(), Game.data)
		box.add_child(_button("%s · +$%s" % [tr("RETIRE"), Game.format_number(refund)], _retire.bind(str(dc.get("id", ""))), ThemeMaker.COLORS.orange))
	return _wrap_scroll(box)

func _build_market_page() -> Control:
	var box := _page_box()
	box.add_child(_section_title(tr("NAV_MARKET"), ""))
	var chart := ChartScene.new()
	chart.set_series(Game.state.get("market", {}).get("history", {}))
	box.add_child(chart)
	var customers := GridContainer.new()
	customers.columns = 2
	customers.add_theme_constant_override("h_separation", 12)
	customers.add_theme_constant_override("v_separation", 12)
	box.add_child(customers)
	for customer_id: String in DataRepository.get_table("customers").get("items", {}):
		var customer := DataRepository.get_entry("customers", customer_id)
		var label := _label("%s\n× %.2f" % [tr(customer.get("name_key", "")), Game.market_multiplier(customer_id)], 29, ChartScene.CUSTOMER_COLORS.get(customer_id, Color.WHITE))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_stylebox_override("normal", ThemeMaker.panel(Color("263e5d"), ChartScene.CUSTOMER_COLORS.get(customer_id, Color.WHITE), 2, 18))
		customers.add_child(label)
	box.add_child(_section_title(tr("MARKET_ACTIVE"), ""))
	var any_event := false
	for active: Dictionary in Game.state.get("market", {}).get("active", []):
		any_event = true
		box.add_child(_event_card(active, false))
	for preview: Dictionary in Game.state.get("market", {}).get("previews", []):
		any_event = true
		box.add_child(_event_card(preview, true))
	if not any_event:
		box.add_child(_empty_state(tr("MARKET_CALM")))
	return _wrap_scroll(box)

func _build_tech_page() -> Control:
	var box := _page_box()
	box.add_child(_section_title(tr("NAV_TECH"), ""))
	var player: Dictionary = Game.state.get("player", {})
	var era_id := int(player.get("era", 1))
	var era := DataRepository.get_entry("eras", str(era_id))
	var next_era := DataRepository.get_entry("eras", str(era_id + 1))
	var era_card := _card()
	var era_box := VBoxContainer.new()
	era_card.add_child(era_box)
	era_box.add_child(_label(tr(era.get("name_key", "")), 34, ThemeMaker.COLORS.yellow))
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
	network_card.add_child(network_box)
	network_box.add_child(_label("%s · %s · ×%.2f" % [tr("NETWORK"), tr(network.get("name_key", "")), float(network.get("income_multiplier", 1.0))], 29, ThemeMaker.COLORS.cyan))
	var next_network: Dictionary = DataRepository.get_table("technology").get("network", {}).get(str(network_level + 1), {})
	if not next_network.is_empty():
		var network_button := _button("%s %s · $%s" % [tr("UPGRADE"), tr(next_network.get("name_key", "")), Game.format_number(float(next_network.get("cost", 0.0)))], _upgrade_network, ThemeMaker.COLORS.sky)
		network_button.disabled = not Game.is_unlocked(next_network)
		network_box.add_child(network_button)
	box.add_child(network_card)
	var repair_level := int(Game.state.get("technology", {}).get("repair_team", 1))
	var repair_card := _card()
	var repair_box := VBoxContainer.new()
	repair_card.add_child(repair_box)
	repair_box.add_child(_label("%s T%d" % [tr("TECH_REPAIR_TEAM"), repair_level], 29))
	repair_box.add_child(_label(tr("TECH_REPAIR_TEAM_DESC"), 23, ThemeMaker.COLORS.cyan))
	var next_repair: Dictionary = DataRepository.get_table("technology").get("upgrades", {}).get("repair_team", {}).get("levels", {}).get(str(repair_level + 1), {})
	if not next_repair.is_empty():
		var repair_button := _button("%s · $%s" % [tr("UPGRADE"), Game.format_number(float(next_repair.get("cost", 0.0)))], _upgrade_repair, ThemeMaker.COLORS.green)
		repair_button.disabled = not Game.is_unlocked(next_repair)
		repair_box.add_child(repair_button)
	box.add_child(repair_card)
	var min_dc := int(DataRepository.get_table("economy").get("prestige", {}).get("minimum_datacenters", 20))
	var prestige_button := _button("%s\n%s" % [tr("PRESTIGE"), tr("PRESTIGE_LOCKED") % min_dc], _confirm_prestige, ThemeMaker.COLORS.purple)
	prestige_button.disabled = int(player.get("total_datacenters_built", 0)) < min_dc
	box.add_child(prestige_button)
	box.add_child(_section_title(tr("ACHIEVEMENTS"), ""))
	for achievement_id: String in DataRepository.get_table("achievements").get("items", {}):
		var achievement := DataRepository.get_entry("achievements", achievement_id)
		var done := bool(Game.state.get("achievements", {}).get(achievement_id, false))
		box.add_child(_label("%s %s · %d 💎" % ["✓" if done else "○", tr(achievement.get("name_key", "")), int(achievement.get("reward_gems", 0))], 24, ThemeMaker.COLORS.green if done else ThemeMaker.COLORS.cream))
	return _wrap_scroll(box)

func _build_store_page() -> Control:
	var box := _page_box()
	box.add_child(_section_title(tr("NAV_STORE"), tr("GEMS_FORMAT") % Game.format_number(float(Game.state["player"].get("gems", 0)))))
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
		row.add_child(_asset_preview(str(product.get("asset_id", "")), tr(product.get("name_key", "")), ThemeMaker.COLORS.purple, 110))
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
		var purchase_state := Game.can_purchase_product(product_id)
		if not bool(purchase_state.get("ok", false)) and str(purchase_state.get("reason", "")) in ["already_owned", "purchase_limit"]:
			buy_button.text = "✓"
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
	var settings_header := HBoxContainer.new()
	var settings_title := _label(tr("NAV_SETTINGS"), 40, ThemeMaker.COLORS.cream)
	settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_header.add_child(settings_title)
	var close_button := _button(tr("CLOSE"), _navigate.bind("map"), Color("263d59"))
	close_button.custom_minimum_size.x = 180
	settings_header.add_child(close_button)
	box.add_child(settings_header)
	box.add_child(_label(tr("SETTINGS_LANGUAGE"), 29, ThemeMaker.COLORS.cyan))
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", 10)
	box.add_child(languages)
	languages.add_child(_button(tr("LANGUAGE_ENGLISH"), Game.set_locale.bind("en"), ThemeMaker.COLORS.sky))
	languages.add_child(_button(tr("LANGUAGE_CHINESE"), Game.set_locale.bind("zh_CN"), ThemeMaker.COLORS.sky))
	for setting: Array in [["music_enabled", "SETTINGS_MUSIC"], ["sfx_enabled", "SETTINGS_SFX"], ["haptics_enabled", "SETTINGS_HAPTICS"]]:
		var toggle := CheckButton.new()
		toggle.text = tr(setting[1])
		toggle.button_pressed = bool(Game.state.get("settings", {}).get(setting[0], true))
		toggle.custom_minimum_size.y = 88
		toggle.toggled.connect(_on_setting_toggled.bind(str(setting[0])))
		box.add_child(toggle)
	box.add_child(_button(tr("SETTINGS_RESET"), _confirm_reset, ThemeMaker.COLORS.red))
	return _wrap_scroll(box)

func _refresh_tutorial() -> void:
	var tutorial: Dictionary = Game.state.get("tutorial", {})
	var steps: Array = DataRepository.get_table("tutorial").get("steps", [])
	var index := int(tutorial.get("step", 0))
	tutorial_panel.visible = not bool(tutorial.get("completed", false)) and index < steps.size()
	if tutorial_panel.visible:
		tutorial_label.text = tr(steps[index].get("message_key", ""))
		var guide_assets := ["guide_normal", "guide_thinking", "guide_happy", "guide_alert", "guide_worried", "guide_thinking", "guide_worried", "guide_happy"]
		tutorial_icon.texture = AssetCatalog.texture(guide_assets[mini(index, guide_assets.size() - 1)])

func _news_text() -> String:
	var market: Dictionary = Game.state.get("market", {})
	if not market.get("active", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["active"][0].get("event_id", "")))
		return "● %s — %s" % [tr(event.get("name_key", "")), tr(event.get("description_key", ""))]
	if not market.get("previews", []).is_empty():
		var event := DataRepository.get_entry("events", str(market["previews"][0].get("event_id", "")))
		return "◌ %s: %s" % [tr("MARKET_PREVIEW"), tr(event.get("name_key", ""))]
	return tr("MARKET_CALM")

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
			choices.append({"id": rack_id, "text": "%s · $%s" % [tr(rack.get("name_key", "")), Game.format_number(Game.rack_purchase_cost(rack_id))]})
	_show_choice(tr("INSTALL"), choices, func(rack_id: String) -> void: _handle_result(Game.install_rack(datacenter_id, slot, rack_id)))

func _show_building_picker(plot_id: String) -> void:
	var choices: Array[Dictionary] = []
	for building_id: String in DataRepository.get_table("buildings").get("items", {}):
		var building := DataRepository.get_entry("buildings", building_id)
		if not Game.is_unlocked(building):
			continue
		if bool(building.get("tutorial_only", false)) and bool(Game.state.get("flags", {}).get("standard_built", false)):
			continue
		choices.append({"id": building_id, "text": "%s · $%s" % [tr(building.get("name_key", "")), Game.format_number(float(building.get("cost", 0.0)))]})
	_show_choice(tr("BUILD"), choices, func(building_id: String) -> void: _handle_result(Game.start_datacenter_construction(plot_id, building_id)))

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
	var choices: Array[Dictionary] = []
	if installed.get("status", "") == "faulted":
		choices.append({"id": "repair", "text": tr("REPAIR")})
		choices.append({"id": "ad", "text": tr("WATCH_AD")})
		choices.append({"id": "gems", "text": "%s · 2 💎" % tr("REPAIR")})
	choices.append({"id": "uninstall", "text": tr("RETIRE")})
	_show_choice(tr("DC_DETAIL"), choices, func(action: String) -> void:
		match action:
			"repair": _handle_result(Game.dispatch_repair(datacenter_id, slot))
			"ad": _handle_result(Game.request_reward("repair:%s:%d" % [datacenter_id, slot]))
			"gems": _handle_result(Game.instant_repair_with_gems(datacenter_id, slot))
			"uninstall": _handle_result(Game.uninstall_rack(datacenter_id, slot))
	)

func _show_choice(title_text: String, choices: Array[Dictionary], callback: Callable) -> void:
	_present_action_sheet(title_text, "", choices, callback)

func _present_action_sheet(title_text: String, body: String, choices: Array[Dictionary], callback: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.name = "ActionSheetOverlay"
	overlay.color = Color(0.015, 0.03, 0.06, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	add_child(overlay)

	var sheet_height := mini(1180, 300 + choices.size() * 104 + (110 if not body.is_empty() else 0))
	var sheet := PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 32
	sheet.offset_top = -sheet_height
	sheet.offset_right = -32
	sheet.offset_bottom = -24
	sheet.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("172a43"), Color(1, 1, 1, 0.14), 1, 32))
	overlay.add_child(sheet)

	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 12)
	sheet.add_child(sheet_box)
	var handle_center := CenterContainer.new()
	handle_center.custom_minimum_size.y = 20
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
	var close_button := _button("×", overlay.queue_free, Color("263d59"))
	close_button.custom_minimum_size = Vector2(88, 88)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.add_theme_font_size_override("font_size", 36)
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
			overlay.queue_free()
			callback.call(choice_id)
		, choice_color)
		choice_button.custom_minimum_size.y = 92
		choice_box.add_child(choice_button)
	var cancel_button := _button(tr("CANCEL"), overlay.queue_free, Color("263d59"))
	cancel_button.custom_minimum_size.y = 92
	sheet_box.add_child(cancel_button)

	sheet.modulate.a = 0.0
	sheet.position.y += 64
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sheet, "modulate:a", 1.0, 0.2)
	tween.tween_property(sheet, "position:y", sheet.position.y - 64, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

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
	active_page = page
	if page != "detail": selected_datacenter_id = ""
	AudioService.play_sfx("sfx_tap")
	if Game.state.get("bankruptcy", {}).get("status", "normal") == "normal":
		AudioService.play_music("music_market" if page == "market" else "music_main")
	_needs_refresh = true

func _open_datacenter(datacenter_id: String) -> void:
	selected_datacenter_id = datacenter_id
	active_page = "detail"
	_needs_refresh = true

func _start_building(plot_id: String, building_id: String) -> void:
	_handle_result(Game.start_datacenter_construction(plot_id, building_id))

func _demolish(datacenter_id: String) -> void:
	_handle_result(Game.demolish_ruin(datacenter_id))

func _retire(datacenter_id: String) -> void:
	_confirm(tr("RETIRE"), tr("RETIRE"), func() -> void:
		_handle_result(Game.retire_datacenter(datacenter_id))
		_navigate("map")
	)

func _sign_contract(datacenter_id: String, customer_id: String) -> void:
	var fee := Game.contract_switch_fee(datacenter_id, customer_id)
	if fee > 0.0:
		_confirm(tr("SWITCH_CONTRACT"), tr("CONTRACT_BREACH_FEE") % Game.format_number(fee), func() -> void: _handle_result(Game.sign_contract(datacenter_id, customer_id)))
	else:
		_handle_result(Game.sign_contract(datacenter_id, customer_id))

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
		_show_toast(tr("TOAST_CONSTRUCTION_STARTED") if result.has("construction") else tr("CONFIRM"))
	else:
		_show_toast(_reason_text(str(result.get("reason", "unknown"))))
	_needs_refresh = true

func _reason_text(reason: String) -> String:
	var keys := {
		"not_enough_cash": "NOT_ENOUGH_CASH", "not_enough_gems": "NOT_ENOUGH_GEMS", "locked": "LOCKED",
		"queue_full": "REASON_QUEUE_FULL", "slot_locked": "LOCKED", "slot_occupied": "INSTALLING",
		"too_new_to_retire": "LIFESPAN", "cooler_slots_full": "LOCKED", "building_tier_too_low": "LOCKED",
		"construction_in_progress": "REASON_IN_PROGRESS", "not_an_upgrade": "REASON_NOT_UPGRADE",
		"reward_unavailable": "LOCKED", "reward_limit": "REASON_REWARD_LIMIT", "ticket_unavailable": "REASON_TICKET",
		"reward_pending": "REASON_IN_PROGRESS",
		"already_owned": "REASON_ALREADY_OWNED", "purchase_limit": "REASON_ALREADY_OWNED", "purchase_pending": "REASON_PURCHASE_PENDING",
		"product_unavailable": "LOCKED",
	}
	return tr(keys.get(reason, reason))

func _on_state_changed(_reason: String) -> void:
	_needs_refresh = true

func _on_toast_requested(key: String, values: Dictionary) -> void:
	var text := tr(key)
	if values.has("name"):
		text = text % values["name"]
	_show_toast(text)

func _on_offline_settled(report: Dictionary) -> void:
	if is_node_ready() and _offline_report_is_material(report):
		if float(report.get("income", 0.0)) >= 1.0:
			AudioService.play_sfx("sfx_cash")
			_play_fx("fx_coin")
		_show_offline_dialog(report)

func _on_construction_completed(_item: Dictionary) -> void:
	_show_toast(tr("TOAST_CONSTRUCTION_COMPLETE"))
	_play_fx("fx_dust_puff", 260)

func _on_rack_fault_occurred(_datacenter_id: String, _slot: int) -> void:
	_play_fx("fx_spark")

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
	_play_fx("fx_coin", 260)

func _offline_report_is_material(report: Dictionary) -> bool:
	if float(report.get("elapsed_seconds", 0.0)) < 60.0:
		return false
	return float(report.get("income", 0.0)) >= 1.0 or not report.get("completed", []).is_empty() or not report.get("faults", []).is_empty() or not report.get("events", []).is_empty() or not report.get("aging", []).is_empty()

func _on_era_unlocked(era_id: int) -> void:
	_play_fx("fx_confetti_set", 680)
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
		var arrears_dialog := ConfirmationDialog.new()
		arrears_dialog.theme = theme
		arrears_dialog.title = tr("BANKRUPTCY_WARNING")
		arrears_dialog.dialog_text = "%s\n$%s" % [tr("BANKRUPTCY_BODY") % Game.format_duration(float(DataRepository.get_table("economy").get("bankruptcy", {}).get("game_over_after_online_seconds", 21600.0))), Game.format_number(debt)]
		arrears_dialog.ok_button_text = tr("ARREARS_RESCUE")
		arrears_dialog.cancel_button_text = tr("CLOSE")
		arrears_dialog.confirmed.connect(func() -> void: _handle_result(Game.request_reward("arrears_rescue")))
		arrears_dialog.confirmed.connect(arrears_dialog.queue_free)
		arrears_dialog.canceled.connect(arrears_dialog.queue_free)
		add_child(arrears_dialog)
		arrears_dialog.popup_centered(Vector2i(820, 560))
	elif status == "normal":
		AudioService.play_music("music_main")
	elif status == "game_over":
		_play_fx("fx_smoke_puff", 420)
		var game_over_dialog := AcceptDialog.new()
		game_over_dialog.theme = theme
		game_over_dialog.title = tr("GAME_OVER")
		var survival := float(GameClock.wall_time() - int(Game.state.get("clock", {}).get("created_at", GameClock.wall_time())))
		game_over_dialog.dialog_text = "%s\n\n%s: $%s\n%s: %s\n%s: $%s\n%s: %d" % [tr("GAME_OVER"), tr("HIGHEST_NET_WORTH"), Game.format_number(float(Game.state["stats"].get("highest_net_worth", 0.0))), tr("STAT_SURVIVAL"), Game.format_duration(survival), tr("TOTAL_REVENUE"), Game.format_number(float(Game.state["player"].get("total_revenue", 0.0))), tr("BUILD"), int(Game.state["player"].get("total_datacenters_built", 0))]
		game_over_dialog.ok_button_text = tr("NEW_COMPANY")
		game_over_dialog.confirmed.connect(func() -> void: Game.start_new_company(); _navigate("map"))
		add_child(game_over_dialog)
		game_over_dialog.popup_centered(Vector2i(820, 560))

func _on_locale_changed(_locale: String) -> void:
	var nav_keys := {"map": "NAV_MAP", "build": "NAV_BUILD", "market": "NAV_MARKET", "tech": "NAV_TECH", "store": "NAV_STORE"}
	for page_id: String in nav_keys:
		var button: Button = nav_buttons.get(page_id) as Button
		if button != null and button.has_node("Content/Items/Text"):
			(button.get_node("Content/Items/Text") as Label).text = tr(nav_keys[page_id])
	var settings_button := find_child("SettingsButton", true, false) as Button
	if settings_button != null:
		settings_button.tooltip_text = tr("NAV_SETTINGS")
	_needs_refresh = true

func _on_purchase_completed(_product_id: String, success: bool, _message: String) -> void:
	_show_toast(tr("TOAST_PURCHASE_COMPLETE") if success else tr("TOAST_PURCHASE_FAILED"))
	if success:
		_play_fx("fx_coin")
	_needs_refresh = true

func _show_toast(message: String) -> void:
	toast_label.text = message
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

func _show_era_overlay(era_id: int, era: Dictionary) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.05, 0.11, 0.94)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 720)
	card.add_theme_stylebox_override("panel", ThemeMaker.panel(ThemeMaker.COLORS.navy, ThemeMaker.COLORS.yellow, 5, 34))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	card.add_child(box)
	box.add_child(_asset_preview("ic_era%d" % era_id, tr(era.get("name_key", "")), ThemeMaker.COLORS.purple, 260))
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
	chip.custom_minimum_size.y = 88
	chip.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("1b304a"), Color(1, 1, 1, 0.08), 1, 22))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	row.add_child(_icon_view(asset_id, Vector2(38, 38)))
	var value := _label("", 26, accent)
	value.name = "Value"
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return chip

func _metric_chip(text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = 64
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("182d47"), Color(accent, 0.42), 1, 18))
	var value := _label(text, 21, accent.lightened(0.18))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	chip.add_child(value)
	return chip

func _tab_button(page_id: String, label_key: String, asset_id: String) -> Button:
	var button := Button.new()
	button.name = "Nav_%s" % page_id
	button.custom_minimum_size.y = 104
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.0
	button.pressed.connect(_navigate.bind(page_id))
	ThemeMaker.apply_tab_style(button, page_id == active_page)
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
	var icon := _icon_view(asset_id, Vector2(42, 42))
	icon.name = "Icon"
	items.add_child(icon)
	var text_label := _label(tr(label_key), 20, ThemeMaker.COLORS.cyan)
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

func _wrap_scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll

func _section_title(title_text: String, subtitle: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := _label(title_text, 40, ThemeMaker.COLORS.cream)
	box.add_child(title)
	if not subtitle.is_empty():
		var sub := _label(subtitle, 22, ThemeMaker.COLORS.cyan)
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(sub)
	return box

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ThemeMaker.panel(Color("1d334d"), Color(1, 1, 1, 0.09), 1, 22))
	return card

func _empty_state(text: String) -> Control:
	var label := _label(text, 27, ThemeMaker.COLORS.cyan)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 180
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

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
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 88
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeMaker.apply_button_color(button, color)
	if action.is_valid():
		button.pressed.connect(action)
	return button

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
	panel.add_theme_stylebox_override("panel", ThemeMaker.panel(color.darkened(0.55), color, 2, 16))
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
	box.add_child(_label(tr("COMPLETE_IN") % Game.format_duration(maxf(0.0, completed - Game.simulation_time())), 20, ThemeMaker.COLORS.cyan))
	return box

func _construction_name(item: Dictionary) -> String:
	match item.get("type", ""):
		"datacenter": return tr(DataRepository.get_entry("buildings", str(item.get("building_id", ""))).get("name_key", "BUILD"))
		"rack": return tr(DataRepository.get_entry("racks", str(item.get("rack_id", ""))).get("name_key", "INSTALL"))
		"power", "cooler": return tr(DataRepository.get_entry("attachments", str(item.get("attachment_id", ""))).get("name_key", "INSTALL"))
		"network": return tr(DataRepository.get_table("technology").get("network", {}).get(str(item.get("level", 1)), {}).get("name_key", "NETWORK"))
	return tr("BUILD")

func _rack_status_text(installed: Dictionary, runtime: Dictionary) -> String:
	if installed.get("status", "") == "installing": return tr("INSTALLING")
	if bool(runtime.get("faulted", false)): return tr("FAULTED")
	if bool(runtime.get("repairing", false)): return tr("REPAIR")
	if not bool(runtime.get("powered", false)): return tr("UNPOWERED")
	if bool(runtime.get("overheated", false)): return tr("OVERHEATED")
	return tr("POWERED")
