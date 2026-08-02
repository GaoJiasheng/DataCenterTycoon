class_name Sparkline
extends Control

var values: Array = []
var line_color := Color.WHITE

func _ready() -> void:
	custom_minimum_size = Vector2(0, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(history: Array, color: Color) -> void:
	values = history.slice(maxi(0, history.size() - 24))
	line_color = color
	queue_redraw()

func _draw() -> void:
	if values.size() < 2:
		return
	var minimum := INF
	var maximum := -INF
	for point: Dictionary in values:
		var value := float(point.get("value", 1.0))
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	var span := maxf(0.08, maximum - minimum)
	var points := PackedVector2Array()
	for index: int in range(values.size()):
		var value := float(values[index].get("value", 1.0))
		points.append(Vector2(size.x * float(index) / maxf(1.0, values.size() - 1), size.y - 5.0 - (value - minimum) / span * (size.y - 10.0)))
	draw_polyline(points, line_color, 4.0, true)
