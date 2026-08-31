class_name LegalView
extends Control

signal closed

const ThemeMaker := preload("res://ui/theme_factory.gd")
const Widgets := preload("res://ui/widgets.gd")

const LEGAL_DOCUMENTS := {
	"privacy": "res://assets/legal/privacy.txt",
	"terms": "res://assets/legal/terms.txt",
	"support": "res://assets/legal/support.txt",
}
const TITLE_KEYS := {
	"privacy": "LEGAL_PRIVACY_TITLE",
	"terms": "LEGAL_TERMS_TITLE",
	"support": "LEGAL_SUPPORT_TITLE",
}
const RELEASE_IDENTITY_PATH := "res://data/release_identity.json"

var document_id := ""
var document_body := ""
var body_view: RichTextLabel

static func document_path(target_id: String) -> String:
	return str(LEGAL_DOCUMENTS.get(target_id, ""))

static func load_document_text(target_id: String) -> String:
	var path := document_path(target_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

static func release_identity() -> Dictionary:
	if not FileAccess.file_exists(RELEASE_IDENTITY_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RELEASE_IDENTITY_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}

static func display_identity_value(field: String) -> String:
	var value := str(release_identity().get(field, ""))
	if value.is_empty() or value.contains("REPLACE_WITH_"):
		return TranslationServer.translate("LEGAL_COMING_SOON")
	return value

func open_document(target_id: String) -> bool:
	document_id = target_id
	document_body = load_document_text(target_id)
	if document_body.is_empty():
		return false
	_build_view()
	return true

func scroll_to_middle_for_tests() -> void:
	if body_view == null:
		return
	var bar := body_view.get_v_scroll_bar()
	body_view.scroll_to_line(maxi(0, body_view.get_line_count() / 2))
	if bar != null and bar.max_value > bar.page:
		bar.value = (bar.max_value - bar.page) * 0.5

func _build_view() -> void:
	for child: Node in get_children():
		child.queue_free()
	name = "LegalView"
	set_meta("legal_document_id", document_id)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 400

	var backdrop := ColorRect.new()
	backdrop.color = ThemeMaker.SURFACE
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "LegalDocumentPanel"
	panel.set_meta("viewport_bounded_surface", true)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 20
	panel.offset_top = 20
	panel.offset_right = -20
	panel.offset_bottom = -20
	panel.add_theme_stylebox_override("panel", ThemeMaker.art_panel(false))
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", ThemeMaker.GROUP_GAP)
	panel.add_child(layout)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", ThemeMaker.ITEM_GAP)
	layout.add_child(heading)

	var title := Label.new()
	title.name = "LegalDocumentTitle"
	title.text = tr(str(TITLE_KEYS.get(document_id, "SETTINGS_LEGAL")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ThemeMaker.font_display())
	title.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.display)
	title.add_theme_color_override("font_color", ThemeMaker.COLORS.ink)
	heading.add_child(title)

	var close_button := Widgets.close_button(_close)
	close_button.name = "LegalCloseButton"
	heading.add_child(close_button)

	body_view = RichTextLabel.new()
	body_view.name = "LegalDocumentBody"
	body_view.bbcode_enabled = false
	body_view.text = document_body
	body_view.fit_content = false
	body_view.scroll_active = true
	body_view.scroll_following = false
	body_view.selection_enabled = true
	body_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_view.add_theme_font_override("normal_font", ThemeMaker.font_regular())
	body_view.add_theme_font_override("bold_font", ThemeMaker.font_bold())
	body_view.add_theme_font_size_override("normal_font_size", ThemeMaker.TYPE_SCALE.body)
	body_view.add_theme_color_override("default_color", ThemeMaker.COLORS.ink)
	body_view.add_theme_constant_override("line_separation", ThemeMaker.TEXT_LINE_SPACING)
	layout.add_child(body_view)

func _close() -> void:
	closed.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
