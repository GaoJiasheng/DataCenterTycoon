extends Node

const MAIN_SCENE := preload("res://main.tscn")
const OUTPUT_ROOT := "/tmp/data_center_tycoon_visual_"

func _ready() -> void:
	Game.reset_for_tests()
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var pages := ["map", "build", "market", "tech", "store", "settings"]
	var valid := true
	for page: String in pages:
		main.call("_navigate", page)
		valid = (await _capture(main, page)) and valid
	main.call("_navigate", "map")
	main.call("_refresh")
	main.call("_show_building_picker", "plot_1")
	await get_tree().create_timer(0.35).timeout
	valid = (await _capture(main, "action_sheet")) and valid
	var sheet := main.find_child("ActionSheetOverlay", true, false)
	if sheet != null:
		sheet.queue_free()
		await get_tree().process_frame
	Game.start_datacenter_construction("plot_1", "dc_t0")
	Game.advance_time(300.0, false)
	main.call("_navigate", "map")
	valid = (await _capture(main, "map_built")) and valid
	await get_tree().create_timer(0.9).timeout
	var dc: Dictionary = Game.state["plots"][0]["datacenter"]
	main.call("_open_datacenter", str(dc.get("id", "")))
	valid = (await _capture(main, "detail")) and valid
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("VISUAL_SMOKE: %s 9 portrait states -> %s*.png" % ["PASS" if valid else "FAIL", OUTPUT_ROOT])
	get_tree().quit(0 if valid else 1)

func _capture(main: Node, name: String) -> bool:
	main.call("_refresh")
	for _frame: int in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var valid := not image.is_empty() and image.get_width() >= 440 and image.get_height() >= 956
	var output_path := "%s%s.png" % [OUTPUT_ROOT, name]
	var save_error := image.save_png(output_path) if valid else ERR_CANT_CREATE
	if not valid or save_error != OK:
		push_error("VISUAL_SMOKE: %s failed size=%dx%d save_error=%d" % [name, image.get_width(), image.get_height(), save_error])
	return valid and save_error == OK
