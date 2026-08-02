class_name TutorialOverlay
extends Control

const ThemeMaker := preload("res://ui/theme_factory.gd")

signal target_activated

var target_rect := Rect2()
var target_action := Callable()
var mask_panes: Array[ColorRect] = []
var hole_border: PanelContainer
var pointer: TextureRect
var bubble: PanelContainer
var guide: TextureRect
var message: Label
var _pointer_base := Vector2.ZERO
var _pointer_tween: Tween
var _border_tween: Tween

func _ready() -> void:
	name = "TutorialSpotlight"
	z_index = 98
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_mask()
	_build_callout()

func present(rect: Rect2, copy: String, guide_asset: String, action: Callable) -> void:
	visible = true
	target_rect = rect.grow(14.0).intersection(get_viewport_rect()) if rect.size != Vector2.ZERO else Rect2()
	target_action = action
	message.text = copy
	guide.texture = AssetCatalog.texture(guide_asset)
	var actionable := target_rect.size.x > 1.0 and target_rect.size.y > 1.0 and target_action.is_valid()
	mouse_filter = Control.MOUSE_FILTER_STOP if actionable else Control.MOUSE_FILTER_IGNORE
	pointer.visible = actionable
	_layout_mask(actionable)
	_position_callout()
	_start_motion(actionable)

func dismiss() -> void:
	visible = false
	target_rect = Rect2()
	target_action = Callable()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _pointer_tween != null and _pointer_tween.is_valid(): _pointer_tween.kill()
	if _border_tween != null and _border_tween.is_valid(): _border_tween.kill()

func is_actionable() -> bool:
	return visible and mouse_filter == Control.MOUSE_FILTER_STOP and target_rect.size != Vector2.ZERO

func _build_mask() -> void:
	for index: int in range(4):
		var pane := ColorRect.new()
		pane.name = "TutorialMask%d" % index
		pane.color = Color(0, 0, 0, 0.55)
		pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pane)
		mask_panes.append(pane)
	hole_border = PanelContainer.new()
	hole_border.name = "TutorialHoleBorder"
	hole_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := ThemeMaker.panel(Color.TRANSPARENT, Color(1, 1, 1, 0.72), 4, int(ThemeMaker.RADIUS.get("button", 18)))
	border_style.content_margin_left = 0
	border_style.content_margin_right = 0
	border_style.content_margin_top = 0
	border_style.content_margin_bottom = 0
	hole_border.add_theme_stylebox_override("panel", border_style)
	add_child(hole_border)

func _build_callout() -> void:
	pointer = TextureRect.new()
	pointer.name = "TutorialPointer"
	var pointer_texture := AssetCatalog.texture("ic_pointer_hand")
	if pointer_texture == null:
		var guide_texture := AssetCatalog.texture("guide_normal")
		if guide_texture != null:
			var hand_crop := AtlasTexture.new()
			hand_crop.atlas = guide_texture
			hand_crop.region = Rect2(500, 420, 268, 360)
			pointer_texture = hand_crop
	pointer.texture = pointer_texture
	pointer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pointer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.size = Vector2(82, 82)
	pointer.pivot_offset = pointer.size * 0.5
	add_child(pointer)

	bubble = PanelContainer.new()
	bubble.name = "TutorialCallout"
	bubble.custom_minimum_size = Vector2(620, 156)
	bubble.size = Vector2(620, 156)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", ThemeMaker.dialog_box())
	add_child(bubble)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ThemeMaker.SPACE[2])
	bubble.add_child(row)
	guide = TextureRect.new()
	guide.name = "TutorialGuide"
	guide.custom_minimum_size = Vector2(104, 104)
	guide.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guide.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(guide)
	message = Label.new()
	message.name = "TutorialMessage"
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_override("font", ThemeMaker.font_regular())
	message.add_theme_font_size_override("font_size", ThemeMaker.TYPE_SCALE.body)
	message.add_theme_color_override("font_color", ThemeMaker.COLORS.ink)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(message)

func _layout_mask(actionable: bool) -> void:
	for pane: ColorRect in mask_panes:
		pane.visible = actionable
	hole_border.visible = actionable
	if not actionable:
		return
	var viewport := size
	mask_panes[0].position = Vector2.ZERO
	mask_panes[0].size = Vector2(viewport.x, maxf(0.0, target_rect.position.y))
	mask_panes[1].position = Vector2(0, target_rect.end.y)
	mask_panes[1].size = Vector2(viewport.x, maxf(0.0, viewport.y - target_rect.end.y))
	mask_panes[2].position = Vector2(0, target_rect.position.y)
	mask_panes[2].size = Vector2(maxf(0.0, target_rect.position.x), target_rect.size.y)
	mask_panes[3].position = Vector2(target_rect.end.x, target_rect.position.y)
	mask_panes[3].size = Vector2(maxf(0.0, viewport.x - target_rect.end.x), target_rect.size.y)
	hole_border.position = target_rect.position
	hole_border.size = target_rect.size

func _start_motion(actionable: bool) -> void:
	if _pointer_tween != null and _pointer_tween.is_valid(): _pointer_tween.kill()
	if _border_tween != null and _border_tween.is_valid(): _border_tween.kill()
	if not actionable:
		return
	pointer.position = _pointer_base
	_pointer_tween = pointer.create_tween().set_loops()
	_pointer_tween.tween_property(pointer, "position:y", _pointer_base.y + 12.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pointer_tween.tween_property(pointer, "position:y", _pointer_base.y - 12.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_border_tween = hole_border.create_tween().set_loops()
	_border_tween.tween_property(hole_border, "modulate:a", 0.45, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_border_tween.tween_property(hole_border, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _gui_input(event: InputEvent) -> void:
	if not is_actionable():
		return
	var point := _event_position(event)
	var released: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	var pressed: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed or released:
		accept_event()
	if released and target_rect.has_point(point):
		var action := target_action
		target_activated.emit()
		if action.is_valid():
			action.call()
	elif pressed and not target_rect.has_point(point):
		var origin := target_rect.position
		var shake := hole_border.create_tween()
		shake.tween_property(hole_border, "position:x", origin.x - 8.0, 0.05)
		shake.tween_property(hole_border, "position:x", origin.x + 8.0, 0.08)
		shake.tween_property(hole_border, "position:x", origin.x, 0.05)

func _event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return event.position
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.position
	return Vector2.ZERO

func _position_callout() -> void:
	var viewport := get_viewport_rect().size
	var bubble_size := bubble.size
	if target_rect.size == Vector2.ZERO:
		bubble.position = Vector2((viewport.x - bubble_size.x) * 0.5, viewport.y - bubble_size.y - 210.0)
		pointer.visible = false
		return
	var above_y := target_rect.position.y - bubble_size.y - 42.0
	var below_y := target_rect.end.y + 42.0
	var y := above_y if above_y >= 120.0 else minf(viewport.y - bubble_size.y - 80.0, below_y)
	bubble.position = Vector2(clampf(target_rect.get_center().x - bubble_size.x * 0.5, 28.0, viewport.x - bubble_size.x - 28.0), y)
	_pointer_base = Vector2(target_rect.get_center().x - pointer.size.x * 0.5, target_rect.position.y - pointer.size.y + 20.0)
	pointer.position = _pointer_base
