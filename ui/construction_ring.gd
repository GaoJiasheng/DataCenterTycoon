extends ProgressBar

# A clock-like, location-bound indicator. Jobs remain the sole source of time;
# keeping the original duration means rewarded minutes count as completed work.
const ThemeMaker := preload("res://ui/theme_factory.gd")
var job: Dictionary = {}
var icon: Texture2D
var accent := Color("71d9e7")
var job_count := 1
var _refresh_elapsed := 0.0

func configure(item: Dictionary, icon_id: String, tint: Color, count: int = 1) -> void:
	job = item
	icon = AssetCatalog.texture(icon_id)
	accent = tint
	job_count = count
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	max_value = maxf(1.0, float(job.get("install_duration_seconds", job.get("duration_seconds", Game.construction_duration(job)))))
	if job.has("install_complete_at") and not job.has("install_duration_seconds"):
		max_value = maxf(1.0, Game.rack_install_duration(job))
	set_meta("construction_ring", true)
	set_meta("icon_id", icon_id)
	set_meta("duration_seconds", max_value)
	set_meta("job_count", count)
	resized.connect(queue_redraw)
	value_changed.connect(func(_value: float) -> void: queue_redraw())
	refresh_progress()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0.0
		refresh_progress()

func refresh_progress() -> void:
	var complete := float(job.get("install_complete_at", job.get("complete_at", Game.simulation_time())))
	var remaining := maxf(0.0, complete - Game.simulation_time())
	value = clampf(max_value - remaining, 0.0, max_value)
	set_meta("remaining_seconds", remaining)
	tooltip_text = tr("COMPLETE_IN") % Game.format_duration(remaining)
	visible = remaining > 0.0

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	if radius <= 0.0:
		return
	var stroke := maxf(3.0, radius * 0.14)
	draw_circle(center + Vector2(0, 2), radius + 3.0, Color(0.01, 0.04, 0.06, 0.25))
	draw_circle(center, radius + 2.0, Color("173248"))
	draw_arc(center, radius, 0.0, TAU, 64, Color("496277"), stroke, true)
	var fraction := clampf(value / max_value, 0.0, 1.0)
	if fraction > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 64, accent, stroke, true)
		var tip := center + Vector2.from_angle(-PI * 0.5 + TAU * fraction) * radius
		draw_circle(tip, stroke * 0.5, accent)
	# Quarter-hour marks make the ring read like a clock without adding text.
	for quarter: int in range(4):
		var direction := Vector2.from_angle(float(quarter) * PI * 0.5)
		draw_line(center + direction * (radius - stroke - 3.0), center + direction * (radius - stroke - 6.0), Color(1, 1, 1, 0.28), 1.5, true)
	if icon != null:
		var icon_size := Vector2.ONE * radius * 1.25
		var icon_rect := Rect2(center - icon_size * 0.5, icon_size)
		var aspect := icon.get_size().aspect()
		if aspect > 1.0:
			icon_rect.size.y /= aspect
		else:
			icon_rect.size.x *= aspect
		icon_rect.position = center - icon_rect.size * 0.5
		draw_texture_rect(icon, icon_rect, false)
	if job_count > 1:
		var count_center := center + Vector2(radius * 0.70, radius * 0.70)
		draw_circle(count_center, 11.0, Color("173248"))
		var text := str(job_count)
		var font := ThemeMaker.font_numeric()
		draw_string(font, count_center + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

static func icon_for_job(item: Dictionary) -> String:
	if item.has("rack_id"):
		return "rack_compute_t1_active"
	match str(item.get("type", "")):
		"power": return "ic_power"
		"cooler": return "cool_liquid_t1_active" if str(item.get("attachment_id", "")).begins_with("cool_liquid") else "cool_air_t1_active"
	return "ic_build"

static func color_for_job(item: Dictionary) -> Color:
	if item.has("rack_id"):
		return Color("7fd3ff")
	match str(item.get("type", "")):
		"power": return Color("ffc93c")
		"cooler": return Color("bba0ff") if str(item.get("attachment_id", "")).begins_with("cool_liquid") else Color("70ded6")
	return Color("ff8a3d")
