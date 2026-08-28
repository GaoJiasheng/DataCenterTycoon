extends Node

const MAIN_SCENE := preload("res://main.tscn")

func _ready() -> void:
	var ci_mode := "--ci" in OS.get_cmdline_user_args()
	DisplayServer.window_set_size(Vector2i(660, 1434))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["player"]["total_datacenters_built"] = 100
	Game.state["plots"] = _dense_campus()
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame: int in range(12):
		await get_tree().process_frame
	main.call("_refresh")
	await get_tree().process_frame
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var cat := main.park_map.campus_cat as CampusCat
	if cat != null:
		cat.call("_spawn_heart")
	var peak_cat_particles: int = main.park_map.find_children("CampusCatHeart", "Sprite2D", true, false).size()
	# World feedback is emitted only for the six visible starter-page centers;
	# hidden pages keep simulating without spawning off-screen particles.
	for plot: Dictionary in Game.state["plots"].slice(0, 6):
		var dc: Dictionary = plot["datacenter"]
		var source: Vector2 = main.park_map.world_position_of(str(dc.get("id", "")))
		main.call("_fly_cash_reward", source, 5)
	await get_tree().process_frame
	var fx_layer := main.find_child("FxLayer", true, false)
	var peak_particles := fx_layer.get_child_count() if fx_layer != null else 0
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _frame: int in range(180):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	samples.sort()
	var p90 := samples[mini(samples.size() - 1, int(floor(float(samples.size()) * 0.90)))]
	var p95 := samples[mini(samples.size() - 1, int(floor(float(samples.size()) * 0.95)))]
	var average := 0.0
	for sample: float in samples:
		average += sample
	average /= maxf(1.0, float(samples.size()))
	await get_tree().create_timer(1.0).timeout
	var remaining_particles := fx_layer.get_child_count() if fx_layer != null else -1
	var remaining_cat_particles: int = main.park_map.find_children("CampusCatHeart", "Sprite2D", true, false).size()
	var node_delta := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - baseline_nodes
	var visible_slots := 0
	for node: Node in main.park_map.content.get_children():
		if node is Button and node.has_meta("grid_slot") and (node as Control).visible:
			visible_slots += 1
	var orientation_consistent := true
	for node: Node in main.find_children("WorldArt", "TextureRect", true, false):
		if str(node.get_meta("world_asset_id", "")).begins_with("dc_"):
			orientation_consistent = orientation_consistent and not (node as TextureRect).flip_h
	# Run uncapped or at 240 fps: a 16.67 ms p95 demonstrates real 60 fps
	# headroom without measuring the sleep jitter introduced by a 60 fps cap.
	# The iPhone Instruments pass remains the authoritative device measurement.
	var cat_valid: bool = cat != null and cat.is_visible_in_tree() and main.park_map.find_children("CampusCat", "Node2D", true, false).size() == 1 and peak_cat_particles == 1 and remaining_cat_particles == 0
	var frame_budget_met: bool = average <= 8.0 and p95 <= 16.67
	var integrity_valid: bool = peak_particles == 30 and remaining_particles == 0 and node_delta <= 5 and main.park_map.campus_count() == 13 and visible_slots == 6 and orientation_consistent and cat_valid
	var valid: bool = integrity_valid and (frame_budget_met or ci_mode)
	var timing_status := "PASS" if frame_budget_met else ("WARN_CI" if ci_mode else "FAIL")
	print("PERFORMANCE_SMOKE: %s hundred_dc_paged+30_coins+cat pages=%d visible=%d orientation=%s cat=%s timing=%s average=%.2fms p90=%.2fms p95=%.2fms peak_particles=%d remaining=%d cat_fx=%d→%d node_delta=%d" % ["PASS" if valid else "FAIL", main.park_map.campus_count(), visible_slots, str(orientation_consistent), str(cat_valid), timing_status, average, p90, p95, peak_particles, remaining_particles, peak_cat_particles, remaining_cat_particles, node_delta])
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if valid else 1)

func _dense_campus() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# A 10×10 player's estate is partitioned across typed campus pages. All one
	# hundred centers remain authoritative while only the active page is visible.
	for index: int in range(100):
		var racks: Array = []
		racks.resize(9)
		racks.fill(null)
		for slot: int in range(6):
			racks[slot] = {"rack_id": "rack_compute_t1" if slot % 2 == 0 else "rack_storage_t1", "status": "active", "enabled": true, "fault_at": -1.0}
		var dc := {
			"id": "perf_dc_%d" % index,
			"building_id": "dc_t%d" % mini(3, maxi(1, index % 4)),
			"status": "operational",
			"built_at": Game.simulation_time(),
			"power_unit": "power_t2",
			"coolers": {"north": "cool_air_t2", "south": "cool_air_t2"},
			"racks": racks,
			"customer_id": "internet",
			"contract_end_at": Game.simulation_time() + 43200.0,
			"aging_notices": [],
		}
		result.append({"id": "perf_plot_%d" % index, "index": index + 1, "purchase_price": 0.0, "purchased": true, "status": "operational", "datacenter": dc})
	return result
