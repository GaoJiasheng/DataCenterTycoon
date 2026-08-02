class_name ThemeFactory
extends RefCounted

const COLORS := {
	"sky": Color("3aa7f0"),
	"navy": Color("2b3a55"),
	"navy_dark": Color("16263d"),
	"green": Color("7bc94c"),
	"yellow": Color("ffc93c"),
	"orange": Color("ff8a3d"),
	"red": Color("ff5a5a"),
	"purple": Color("9b6bf3"),
	"cyan": Color("9fe8ff"),
	"cream": Color("fff6e8"),
	"brown": Color("b07b4f"),
	"ink": Color("18304a"),
	"ivory": Color("fff4d8"),
	"steel": Color("46749a"),
}

const SEMANTIC := {
	"primary": Color("7bc94c"),
	"action": Color("3aa7f0"),
	"premium": Color("9b6bf3"),
	"warning": Color("ff8a3d"),
	"danger": Color("ff5a5a"),
	"success": Color("7bc94c"),
	"locked": Color("8a97a8"),
}
const TYPE_SCALE := {"display": 44, "title": 36, "heading": 28, "body": 24, "caption": 20, "micro": 18}
const SPACE := [4, 8, 12, 16, 24, 32]
const RADIUS := {"chip": 14, "button": 18, "card": 22, "sheet": 28}
const TOUCH_MIN := 88.0
const FONT_LATIN_PATH := "res://assets/fonts/Baloo2-Variable.ttf"
const FONT_CJK_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"

static var _font_cache: Dictionary = {}

static func create() -> Theme:
	var result := Theme.new()
	result.default_font = font_regular()
	result.default_font_size = 26
	result.set_font("font", "Button", font_bold())
	result.set_color("font_color", "Label", COLORS.cream)
	result.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	result.set_constant("shadow_offset_x", "Label", 0)
	result.set_constant("shadow_offset_y", "Label", 0)
	# Nested containers remain quiet by default. Deliberate work surfaces and
	# cards opt into the illustrated nine-slice through Widgets.panel().
	result.set_stylebox("panel", "PanelContainer", glass_panel(Color("102236"), 0.96, 22))
	result.set_stylebox("normal", "Button", art_button_box("btn_secondary"))
	result.set_stylebox("hover", "Button", art_button_box("btn_secondary", Color("fff4d6")))
	result.set_stylebox("pressed", "Button", art_button_box("btn_secondary", Color("c9d7df")))
	result.set_stylebox("disabled", "Button", art_button_box("btn_disabled"))
	result.set_color("font_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("9aa9ba"))
	result.set_font_size("font_size", "Button", 24)
	result.set_constant("outline_size", "Button", 4)
	result.set_color("font_outline_color", "Button", COLORS.ink)
	result.set_stylebox("normal", "LineEdit", panel(Color("fff6e8"), COLORS.sky, 2, 14))
	result.set_color("font_color", "LineEdit", COLORS.navy)
	result.set_stylebox("normal", "OptionButton", button_box(COLORS.navy, 16))
	result.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	var progress_background := texture_box("progress_frame", Vector4(44, 30, 44, 30), Vector4(12, 8, 12, 8))
	var progress_fill := texture_box("progress_fill", Vector4(44, 30, 44, 30), Vector4(8, 6, 8, 6))
	result.set_stylebox("background", "ProgressBar", progress_background)
	result.set_stylebox("fill", "ProgressBar", progress_fill)
	result.set_color("font_color", "ProgressBar", COLORS.cream)
	return result

static func font_regular() -> Font:
	return _font_variation("regular", 520, true)

static func font_bold() -> Font:
	return _font_variation("bold", 720, true)

static func font_numeric() -> Font:
	var font := _font_variation("numeric", 650, true)
	if font is FontVariation:
		(font as FontVariation).opentype_features = {"tnum": 1}
	return font

static func _font_variation(cache_key: String, weight: int, include_cjk: bool) -> Font:
	if _font_cache.has(cache_key):
		return _font_cache[cache_key] as Font
	var latin := load(FONT_LATIN_PATH) as Font
	var cjk := load(FONT_CJK_PATH) as Font
	if latin == null or cjk == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["SF Pro Rounded", "PingFang SC", "Arial Rounded MT Bold", "Arial"])
		fallback.font_weight = weight
		_font_cache[cache_key] = fallback
		return fallback
	var cjk_variation := FontVariation.new()
	cjk_variation.base_font = cjk
	cjk_variation.variation_opentype = {"wght": weight}
	var variation := FontVariation.new()
	variation.base_font = latin
	variation.variation_opentype = {"wght": weight}
	if include_cjk:
		variation.fallbacks = [cjk_variation]
	_font_cache[cache_key] = variation
	return variation

static func apply_numeric_text(label: Label) -> void:
	label.add_theme_font_override("font", font_numeric())

static func world_text(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", COLORS.ink)
	label.add_theme_constant_override("outline_size", 3)

static func panel(fill: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	return box

static func button_box(color: Color, radius: int = 18, pressed: bool = false) -> StyleBoxFlat:
	var box := panel(color, Color(1, 1, 1, 0.10), 1, radius)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.12 if not pressed else 0.05)
	box.shadow_size = 2 if not pressed else 1
	box.shadow_offset = Vector2(0, 1)
	return box

static func glass_panel(fill: Color, opacity: float = 0.94, radius: int = 24, accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var border := Color(accent, 0.5) if accent.a > 0.0 else Color(1, 1, 1, 0.10)
	var box := panel(Color(fill, opacity), border, 1, radius)
	box.shadow_color = Color(0, 0, 0, 0.16)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	return box

static func texture_box(asset_id: String, texture_margins: Vector4, content_margins: Vector4, tint: Color = Color.WHITE) -> StyleBox:
	var texture := AssetCatalog.texture(asset_id)
	if texture == null:
		return panel(COLORS.navy, Color(1, 1, 1, 0.10), 1, 22)
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = texture_margins.x
	box.texture_margin_top = texture_margins.y
	box.texture_margin_right = texture_margins.z
	box.texture_margin_bottom = texture_margins.w
	box.content_margin_left = content_margins.x
	box.content_margin_top = content_margins.y
	box.content_margin_right = content_margins.z
	box.content_margin_bottom = content_margins.w
	box.modulate_color = tint
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box

static func art_panel(dark: bool = true, compact: bool = false) -> StyleBox:
	var asset_id := "panel_dark" if dark else "panel_main"
	var edge := 32.0 if compact else 52.0
	var inset := 22.0 if compact else 38.0
	var box := texture_box(asset_id, Vector4(edge, edge, edge, edge), Vector4(inset, inset, inset, inset))
	if box is StyleBoxFlat:
		return glass_panel(Color("0d2135") if dark else Color("f7f1e4"), 0.985, 28, Color("4b718b") if dark else Color("d8cdb7"))
	return box

static func resource_panel() -> StyleBox:
	# HUD chips are only 88u high. Their slice edges must stay below half that
	# height or StyleBoxTexture folds the frame over its content.
	var box := texture_box("panel_main", Vector4(22, 22, 22, 22), Vector4(12, 8, 12, 8))
	if box is StyleBoxFlat:
		var fallback := panel(Color("f8f3e9"), Color("d8d0c2"), 1, 18)
		fallback.content_margin_left = 12
		fallback.content_margin_right = 12
		fallback.content_margin_top = 8
		fallback.content_margin_bottom = 8
		return fallback
	return box

static func dialog_box() -> StyleBox:
	var box := texture_box("dialog_bubble", Vector4(48, 34, 48, 54), Vector4(28, 20, 28, 34))
	if box is StyleBoxFlat:
		var fallback := panel(Color("fffaf0"), Color("dfd4c1"), 1, 22)
		fallback.shadow_color = Color(0, 0, 0, 0.18)
		fallback.shadow_size = 4
		fallback.shadow_offset = Vector2(0, 2)
		return fallback
	return box

static func art_button_box(asset_id: String, tint: Color = Color.WHITE) -> StyleBox:
	var box := texture_box(asset_id, Vector4(46, 24, 46, 24), Vector4(20, 12, 20, 14), tint)
	# Button renders include generous transparent export padding. Crop that
	# padding before nine-slicing so a 44pt control still looks 44pt tall.
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).region_rect = Rect2(0, 46, 512, 166)
	return box

static func world_badge(accent: Color, compact: bool = false) -> StyleBox:
	var box := panel(Color("10283d", 0.94), Color(accent, 0.78), 2, 28 if compact else 18)
	box.content_margin_left = 10 if compact else 12
	box.content_margin_right = 10 if compact else 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.shadow_color = Color(0, 0, 0, 0.18)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	return box

static func apply_button_color(button: Button, color: Color) -> void:
	apply_button_role(button, button_role_for_color(color))

static func apply_button_role(button: Button, role: String) -> void:
	var asset_id := {
		"primary": "btn_primary",
		"secondary": "btn_secondary",
		"warning": "btn_warning",
		"danger": "btn_danger",
		"premium": "btn_ad",
		"ad": "btn_ad",
		"disabled": "btn_disabled",
	}.get(role, "btn_secondary") as String
	button.add_theme_stylebox_override("normal", art_button_box(asset_id))
	button.add_theme_stylebox_override("hover", art_button_box(asset_id, Color("fff4dc")))
	button.add_theme_stylebox_override("pressed", art_button_box(asset_id, Color("c8d4dc")))
	button.add_theme_stylebox_override("disabled", art_button_box("btn_disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("9aa9ba"))
	button.add_theme_color_override("font_outline_color", COLORS.ink)
	button.add_theme_constant_override("outline_size", 4)

static func button_role_for_color(color: Color) -> String:
	if color.r > 0.78 and color.g < 0.45:
		return "danger"
	if color.r > 0.72 and color.g >= 0.45 and color.b < 0.42:
		return "warning"
	if color.b > color.r and color.b > color.g and color.r > 0.35:
		return "premium"
	if color.g > color.r and color.g > color.b:
		return "primary"
	return "secondary"

static func _button_asset_for_color(color: Color) -> String:
	return {
		"danger": "btn_danger",
		"warning": "btn_warning",
		"premium": "btn_ad",
		"primary": "btn_primary",
	}.get(button_role_for_color(color), "btn_secondary") as String

static func apply_icon_button(button: Button) -> void:
	var normal := panel(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 22)
	var hover := panel(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.10), 1, 22)
	var pressed := panel(Color(1, 1, 1, 0.16), Color.TRANSPARENT, 0, 22)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func apply_round_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", round_button_box(color))
	button.add_theme_stylebox_override("hover", round_button_box(color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", round_button_box(color.darkened(0.13), true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", COLORS.cream)

static func round_button_box(color: Color, pressed: bool = false) -> StyleBoxFlat:
	var box := panel(color.darkened(0.16), Color(1, 1, 1, 0.42), 2, 26)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(0, 0, 0, 0.24)
	box.shadow_size = 3 if not pressed else 1
	box.shadow_offset = Vector2(0, 1)
	return box

static func apply_compact_button(button: Button, accent: Color) -> void:
	var normal := glass_panel(Color("18344d"), 0.94, 20, Color(COLORS.ivory, 0.36))
	var hover := glass_panel(Color("214c68"), 0.98, 20, accent)
	var pressed := glass_panel(Color("11283e"), 0.98, 20, accent)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", COLORS.cream)
	button.add_theme_font_size_override("font_size", 22)

static func apply_tab_style(button: Button, selected: bool) -> void:
	var normal_fill := Color("244968") if selected else Color(0, 0, 0, 0)
	var pressed_fill := Color("173650") if selected else Color(1, 1, 1, 0.06)
	var normal := panel(normal_fill, Color(0.30, 0.72, 1.0, 0.34) if selected else Color.TRANSPARENT, 1 if selected else 0, 22)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed_fill
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
