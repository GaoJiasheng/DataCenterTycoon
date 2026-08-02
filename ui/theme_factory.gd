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
}

static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SF Pro Rounded", "PingFang SC", "Arial Rounded MT Bold", "Arial"])
	font.font_weight = 500
	result.default_font = font
	result.default_font_size = 28
	result.set_color("font_color", "Label", COLORS.cream)
	result.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.28))
	result.set_constant("shadow_offset_x", "Label", 1)
	result.set_constant("shadow_offset_y", "Label", 2)
	result.set_stylebox("panel", "PanelContainer", panel(COLORS.navy, Color(1, 1, 1, 0.08), 1, 24))
	result.set_stylebox("normal", "Button", button_box(COLORS.sky, 22))
	result.set_stylebox("hover", "Button", button_box(COLORS.sky.lightened(0.09), 22))
	result.set_stylebox("pressed", "Button", button_box(COLORS.sky.darkened(0.15), 22, true))
	result.set_stylebox("disabled", "Button", button_box(Color("64748b"), 22))
	result.set_color("font_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("cbd5e1"))
	result.set_font_size("font_size", "Button", 26)
	result.set_constant("outline_size", "Button", 2)
	result.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.2))
	result.set_stylebox("normal", "LineEdit", panel(Color("fff6e8"), COLORS.sky, 2, 14))
	result.set_color("font_color", "LineEdit", COLORS.navy)
	result.set_stylebox("normal", "OptionButton", button_box(COLORS.navy, 16))
	result.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	return result

static func panel(fill: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	return box

static func button_box(color: Color, radius: int = 18, pressed: bool = false) -> StyleBoxFlat:
	var box := panel(color, color.lightened(0.16), 1, radius)
	box.border_width_bottom = 2 if pressed else 4
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 14 if pressed else 12
	box.content_margin_bottom = 14 if pressed else 16
	return box

static func apply_button_color(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", button_box(color))
	button.add_theme_stylebox_override("hover", button_box(color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", button_box(color.darkened(0.15), 18, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func apply_tab_style(button: Button, selected: bool) -> void:
	var normal_fill := Color("294562") if selected else Color(0, 0, 0, 0)
	var pressed_fill := Color("203a56") if selected else Color(1, 1, 1, 0.06)
	var normal := panel(normal_fill, Color(1, 1, 1, 0.08) if selected else Color.TRANSPARENT, 1 if selected else 0, 22)
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
