class_name ThemeFactory
extends RefCounted

const SURFACE := Color("122438")
const SURFACE_GROUP := Color(0, 0, 0, 0.22)
const TEXT_SECONDARY := Color("9fb8cc")

const COLORS := {
	"sky": Color("3aa7f0"),
	"navy": Color("2b3a55"),
	"navy_dark": SURFACE,
	"green": Color("7bc94c"),
	"yellow": Color("ffc93c"),
	"orange": Color("ff8a3d"),
	"red": Color("ff5a5a"),
	"purple": Color("9b6bf3"),
	"cyan": TEXT_SECONDARY,
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
const TYPE_SCALE := {"display": 44, "title": 28, "heading": 28, "body": 24, "caption": 20, "micro": 20}
const SPACE := [4, 8, 12, 16, 24, 32]
const RADIUS := {"chip": 14, "button": 18, "card": 22, "sheet": 28}
const TOUCH_MIN := 88.0
const PAGE_PADDING := 32
const GROUP_PADDING := 24
const GROUP_GAP := 24
const ITEM_GAP := 12
const TEXT_LINE_SPACING := 6
const FONT_LATIN_PATH := "res://assets/fonts/Baloo2-Variable.ttf"
const FONT_CJK_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"

static var _font_cache: Dictionary = {}
static var _scaled_texture_cache: Dictionary = {}

# Painted nine-slice sources are high-res (1024²) with thick decorated frames.
# Rendering their border strips 1:1 would eat 100u+ per edge, and using smaller
# slice margins cuts through the painted frame (the "folded border" artifacts).
# Downscaling once at load keeps the painted frame proportional on phone UI.
static func scaled_texture(asset_id: String, scale: float) -> Texture2D:
	var cache_key := "%s@%.2f" % [asset_id, scale]
	if _scaled_texture_cache.has(cache_key):
		return _scaled_texture_cache[cache_key] as Texture2D
	var source := AssetCatalog.texture(asset_id)
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.resize(int(image.get_width() * scale), int(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	var scaled := ImageTexture.create_from_image(image)
	_scaled_texture_cache[cache_key] = scaled
	return scaled

static func create() -> Theme:
	var result := Theme.new()
	result.default_font = font_regular()
	result.default_font_size = 26
	result.set_font("font", "Button", font_bold())
	result.set_color("font_color", "Label", COLORS.cream)
	result.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	result.set_constant("shadow_offset_x", "Label", 0)
	result.set_constant("shadow_offset_y", "Label", 0)
	# Only a page/sheet opts into an illustrated frame. Nested groups remain flat.
	result.set_stylebox("panel", "PanelContainer", glass_panel(SURFACE, 0.96, 22))
	result.set_stylebox("normal", "Button", flat_button_box("secondary"))
	result.set_stylebox("hover", "Button", flat_button_box("secondary", true))
	result.set_stylebox("pressed", "Button", flat_button_box("secondary", false, true))
	result.set_stylebox("disabled", "Button", flat_button_box("disabled"))
	result.set_color("font_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("9aa9ba"))
	result.set_font_size("font_size", "Button", 24)
	result.set_constant("outline_size", "Button", 3)
	result.set_color("font_outline_color", "Button", COLORS.ink)
	result.set_stylebox("normal", "LineEdit", panel(Color("fff6e8"), COLORS.sky, 2, 14))
	result.set_color("font_color", "LineEdit", COLORS.navy)
	result.set_stylebox("normal", "OptionButton", button_box(COLORS.navy, 16))
	result.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	# Bars render 34-42u tall; the painted progress_frame needs 60u of slices and
	# folds over itself at that size. Flat styles scale cleanly at any height.
	var progress_background := panel(SURFACE_GROUP, Color(1, 1, 1, 0.14), 1, 12)
	progress_background.content_margin_left = 5
	progress_background.content_margin_right = 5
	progress_background.content_margin_top = 5
	progress_background.content_margin_bottom = 5
	var progress_fill := panel(COLORS.green, Color.TRANSPARENT, 0, 8)
	progress_fill.content_margin_left = 0
	progress_fill.content_margin_right = 0
	progress_fill.content_margin_top = 0
	progress_fill.content_margin_bottom = 0
	result.set_stylebox("background", "ProgressBar", progress_background)
	result.set_stylebox("fill", "ProgressBar", progress_fill)
	result.set_color("font_color", "ProgressBar", COLORS.cream)
	return result

static func font_regular() -> Font:
	return _font_variation("regular", 520, true)

static func font_bold() -> Font:
	return _font_variation("bold", 720, true)

static func font_heavy() -> Font:
	# World CTAs keep a 4px ink outline for contrast. The heavier CJK master
	# preserves a genuinely white interior instead of letting that outline swallow
	# the thin strokes at 28u.
	return _font_variation("heavy", 900, true)

static func font_world_heavy() -> Font:
	# Godot does not consistently propagate a variation axis from a Latin master
	# into its CJK fallback. Use the CJK variable face as the primary font in
	# Chinese so 900-weight strokes survive the required world-text outline.
	if not TranslationServer.get_locale().begins_with("zh"):
		return font_heavy()
	var cache_key := "world_heavy_cjk"
	if _font_cache.has(cache_key):
		return _font_cache[cache_key] as Font
	var cjk := load(FONT_CJK_PATH) as Font
	if cjk == null:
		return font_heavy()
	var variation := FontVariation.new()
	variation.base_font = cjk
	variation.variation_opentype = {"wght": 900}
	_font_cache[cache_key] = variation
	return variation

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
	label.add_theme_constant_override("outline_size", 4)

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

static func flat_group_box(accent: Color = Color.TRANSPARENT, padding: int = GROUP_PADDING) -> StyleBoxFlat:
	var border := Color(accent, 0.34) if accent.a > 0.0 else Color(1, 1, 1, 0.06)
	var box := panel(SURFACE_GROUP, border, 1, RADIUS.card)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	box.shadow_color = Color.TRANSPARENT
	box.shadow_size = 0
	return box

static func flat_button_box(role: String = "secondary", hovered: bool = false, pressed: bool = false) -> StyleBoxFlat:
	var fill := {
		"primary": Color("31593f"),
		"warning": Color("5b4937"),
		"danger": Color("603a43"),
		"premium": Color("4a3f60"),
		"ad": Color("4a3f60"),
		"disabled": Color("344354"),
	}.get(role, Color("243b55")) as Color
	if hovered:
		fill = fill.lightened(0.08)
	elif pressed:
		fill = fill.darkened(0.10)
	var box := panel(fill, Color(1, 1, 1, 0.10), 1, RADIUS.button)
	box.content_margin_left = GROUP_PADDING
	box.content_margin_right = GROUP_PADDING
	box.content_margin_top = ITEM_GAP
	box.content_margin_bottom = ITEM_GAP
	box.shadow_color = Color(0, 0, 0, 0.10)
	box.shadow_size = 1 if pressed else 2
	box.shadow_offset = Vector2(0, 1)
	return box

static func glass_panel(fill: Color, opacity: float = 0.94, radius: int = 24, accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var border := Color(accent, 0.5) if accent.a > 0.0 else Color(1, 1, 1, 0.10)
	var box := panel(Color(fill, opacity), border, 1, radius)
	box.shadow_color = Color(0, 0, 0, 0.16)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	return box

static func texture_box(asset_id: String, texture_margins: Vector4, content_margins: Vector4, tint: Color = Color.WHITE, texture_scale: float = 1.0) -> StyleBox:
	var texture: Texture2D = scaled_texture(asset_id, texture_scale) if texture_scale != 1.0 else AssetCatalog.texture(asset_id)
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
	# Source frames measure ~60-70px thick with corner screws out to ~95px (1024²).
	# At 0.5x that means slices must be ≥48 to keep screws whole, and content must
	# clear the ~35px painted frame plus breathing room — anything less draws text
	# on top of the frame.
	var edge := 52.0
	var inset := 48.0 if compact else 56.0
	var box := texture_box(asset_id, Vector4(edge, edge, edge, edge), Vector4(inset, inset, inset, inset), Color.WHITE, 0.5)
	if box is StyleBoxFlat:
		return glass_panel(SURFACE if dark else Color("f7f1e4"), 0.985, 28, Color("4b718b") if dark else Color("d8cdb7"))
	return box

static func resource_panel() -> StyleBox:
	# HUD chips are too small for the painted frame — slicing panel_main at chip
	# scale cuts through its 60px frame and smears it. Small controls stay flat.
	var box := panel(Color("f8f3e9"), Color("d8d0c2"), 1, 24)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.shadow_color = Color(0, 0, 0, 0.14)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 1)
	return box

static func dialog_box() -> StyleBox:
	# Content margins must exceed the slice margins, otherwise text sits on the
	# painted bubble frame.
	var box := texture_box("dialog_bubble", Vector4(48, 34, 48, 54), Vector4(56, 40, 56, 62))
	if box is StyleBoxFlat:
		var fallback := panel(Color("fffaf0"), Color("dfd4c1"), 1, 22)
		fallback.shadow_color = Color(0, 0, 0, 0.18)
		fallback.shadow_size = 4
		fallback.shadow_offset = Vector2(0, 2)
		return fallback
	return box

static func art_button_box(asset_id: String, tint: Color = Color.WHITE) -> StyleBox:
	# A1 matte pill geometry (512x256 source): opaque 19..494 x 41..207.
	# The cap tangent is 70-72px in from the painted edge, the top rim is 6px,
	# and the lower rim + bevel is 20-21px. Crop the export gutter first, then
	# slice outside those features. The previous 80/22/80/34 margins cut inside
	# the cap and over-preserved the lower bevel, producing leaf-like ends and a
	# stretched dark seam on short controls.
	var box := texture_box(asset_id, Vector4(74, 12, 74, 22), Vector4(56, 16, 56, 24), tint)
	# Keep 3-7px of transparent breathing room around the measured alpha bounds.
	if box is StyleBoxTexture:
		(box as StyleBoxTexture).region_rect = Rect2(16, 36, 480, 180)
	return box

static func world_badge(accent: Color, compact: bool = false) -> StyleBox:
	var box := panel(Color(SURFACE, 0.94), Color(accent, 0.78), 2, 28 if compact else 18)
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
	var glossy := role == "primary" and not button.text.contains("\n")
	button.set_meta("glossy_button", glossy)
	if glossy:
		button.add_theme_stylebox_override("normal", art_button_box("btn_primary"))
		button.add_theme_stylebox_override("hover", art_button_box("btn_primary", Color("fff4dc")))
		button.add_theme_stylebox_override("pressed", art_button_box("btn_primary", Color("c8d4dc")))
		# The glossy pill is reserved for large CTAs; 28u is the size where white
		# text with a 4px ink outline stays crisp on the bright highlight band.
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_font_override("font", font_world_heavy())
		button.add_theme_color_override("font_shadow_color", COLORS.ink)
		button.add_theme_constant_override("shadow_offset_x", 0)
		button.add_theme_constant_override("shadow_offset_y", 2)
		button.add_theme_constant_override("shadow_outline_size", 2)
	else:
		button.add_theme_stylebox_override("normal", flat_button_box(role))
		button.add_theme_stylebox_override("hover", flat_button_box(role, true))
		button.add_theme_stylebox_override("pressed", flat_button_box(role, false, true))
		button.add_theme_font_size_override("font_size", TYPE_SCALE.body)
		button.add_theme_font_override("font", font_regular())
	button.add_theme_stylebox_override("disabled", flat_button_box("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("9aa9ba"))
	button.add_theme_color_override("font_outline_color", COLORS.ink)
	# 4px outlines swallow CJK stroke interiors below 26u; keep the heavy outline
	# for the large glossy CTA and use 3px on standard 24u buttons.
	button.add_theme_constant_override("outline_size", 4 if glossy else 3)

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

static func apply_prominent_danger(button: Button) -> void:
	button.set_meta("glossy_button", false)
	button.add_theme_stylebox_override("normal", button_box(Color("b7444f"), RADIUS.button))
	button.add_theme_stylebox_override("hover", button_box(Color("c9505a"), RADIUS.button))
	button.add_theme_stylebox_override("pressed", button_box(Color("923640"), RADIUS.button, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_override("font", font_bold())
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", COLORS.ink)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_color_override("font_shadow_color", COLORS.ink)
	button.add_theme_constant_override("shadow_offset_y", 2)

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
