class_name MarketChart
extends Control

const CUSTOMER_COLORS := {
	"internet": Color("3aa7f0"),
	"mining": Color("ffc93c"),
	"cloud": Color("7bc94c"),
	"gpu_company": Color("9b6bf3"),
}

var series: Dictionary = {}
var visible_series: Dictionary = {}
var events: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, 330)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_series(value: Dictionary) -> void:
	series = value
	for customer_id: String in series:
		if not visible_series.has(customer_id):
			visible_series[customer_id] = true
	queue_redraw()

func set_events(value: Array) -> void:
	events = value
	queue_redraw()

func toggle_series(customer_id: String) -> void:
	visible_series[customer_id] = not bool(visible_series.get(customer_id, true))
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(12, 12), size - Vector2(24, 24))
	var background := StyleBoxFlat.new()
	background.bg_color = Color("101f31")
	background.border_color = Color(1, 1, 1, 0.08)
	background.set_border_width_all(1)
	background.set_corner_radius_all(18)
	draw_style_box(background, rect)
	var visible_count := 0
	for customer_id: String in series:
		var values: Array = series[customer_id]
		if values.size() >= 2 and bool(visible_series.get(customer_id, true)):
			visible_count += 1
	if visible_count == 0:
		var empty_icon := AssetCatalog.texture("ic_market_up")
		if empty_icon != null:
			draw_texture_rect(empty_icon, Rect2(rect.get_center() - Vector2(52, 76), Vector2(104, 104)), false, Color(1, 1, 1, 0.22))
		var font := get_theme_default_font()
		draw_string(font, Vector2(rect.position.x + 32, rect.get_center().y + 74), tr("MARKET_NO_HISTORY"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 64, 22, Color(0.72, 0.84, 0.91, 0.72))
		return
	for index: int in range(5):
		var y := rect.position.y + rect.size.y * float(index) / 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.09), 2)
	var font := get_theme_default_font()
	for reference: float in [0.5, 1.0, 2.0, 3.0]:
		var y := rect.end.y - rect.size.y * reference / 3.2
		draw_string(font, Vector2(rect.position.x + 8, y - 5), "×%.1f" % reference, HORIZONTAL_ALIGNMENT_LEFT, 68, 18, Color(0.72, 0.84, 0.91, 0.70))
	var latest_at := _latest_history_time()
	var earliest_at := _earliest_visible_time()
	if latest_at > earliest_at:
		for state: Dictionary in events:
			var start := float(state.get("start_at", state.get("started_at", earliest_at)))
			var finish := float(state.get("end_at", latest_at))
			var x0 := remap(clampf(start, earliest_at, latest_at), earliest_at, latest_at, rect.position.x, rect.end.x)
			var x1 := remap(clampf(finish, earliest_at, latest_at), earliest_at, latest_at, rect.position.x, rect.end.x)
			draw_rect(Rect2(Vector2(x0, rect.position.y), Vector2(maxf(3.0, x1 - x0), rect.size.y)), Color(1.0, 0.55, 0.24, 0.08))
	draw_line(Vector2(rect.end.x - 2, rect.position.y), Vector2(rect.end.x - 2, rect.end.y), Color(1, 1, 1, 0.42), 2)
	draw_string(font, Vector2(rect.end.x - 90, rect.position.y + 24), tr("MARKET_NOW"), HORIZONTAL_ALIGNMENT_RIGHT, 78, 18, Color(0.82, 0.92, 1.0, 0.84))
	for customer_id: String in series:
		var values: Array = series[customer_id]
		if values.size() < 2 or not bool(visible_series.get(customer_id, true)):
			continue
		var recent: Array = values.slice(maxi(0, values.size() - 180))
		var points := PackedVector2Array()
		for index: int in range(recent.size()):
			var value := clampf(float(recent[index].get("value", 1.0)), 0.0, 3.2)
			points.append(Vector2(rect.position.x + rect.size.x * float(index) / maxf(1.0, recent.size() - 1), rect.end.y - rect.size.y * value / 3.2))
		draw_polyline(points, CUSTOMER_COLORS.get(customer_id, Color.WHITE), 5.0, true)

func _latest_history_time() -> float:
	var result := -INF
	for values: Array in series.values():
		if not values.is_empty():
			result = maxf(result, float(values[-1].get("at", 0.0)))
	return result

func _earliest_visible_time() -> float:
	var result := INF
	for values: Array in series.values():
		if not values.is_empty():
			var index := maxi(0, values.size() - 180)
			result = minf(result, float(values[index].get("at", 0.0)))
	return result
