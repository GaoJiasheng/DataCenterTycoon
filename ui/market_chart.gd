class_name MarketChart
extends Control

const CUSTOMER_COLORS := {
	"internet": Color("3aa7f0"),
	"mining": Color("ffc93c"),
	"cloud": Color("7bc94c"),
	"gpu_company": Color("9b6bf3"),
}

var series: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 330)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_series(value: Dictionary) -> void:
	series = value
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(12, 12), size - Vector2(24, 24))
	draw_rect(rect, Color("1d2c46"), true)
	for index: int in range(5):
		var y := rect.position.y + rect.size.y * float(index) / 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.09), 2)
	var visible_count := 0
	for customer_id: String in series:
		var values: Array = series[customer_id]
		if values.size() < 2:
			continue
		visible_count += 1
		var recent: Array = values.slice(maxi(0, values.size() - 180))
		var points := PackedVector2Array()
		for index: int in range(recent.size()):
			var value := clampf(float(recent[index].get("value", 1.0)), 0.0, 3.2)
			points.append(Vector2(rect.position.x + rect.size.x * float(index) / maxf(1.0, recent.size() - 1), rect.end.y - rect.size.y * value / 3.2))
		draw_polyline(points, CUSTOMER_COLORS.get(customer_id, Color.WHITE), 5.0, true)
	if visible_count == 0:
		draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Color(1, 1, 1, 0.22), 4)
