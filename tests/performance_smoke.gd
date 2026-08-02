extends Node

const MAIN_SCENE := preload("res://main.tscn")

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(402, 874))
	Game.reset_for_tests()
	Game.last_offline_report = {}
	Game.state["tutorial"]["completed"] = true
	Game.state["plots"] = _dense_campus()
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for _frame: int in range(12):
		await get_tree().process_frame
	main.call("_refresh")
	await get_tree().process_frame
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for plot: Dictionary in Game.state["plots"]:
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
	var node_delta := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - baseline_nodes
	# Run uncapped or at 240 fps: a 16.67 ms p95 demonstrates real 60 fps
	# headroom without measuring the sleep jitter introduced by a 60 fps cap.
	# The iPhone Instruments pass remains the authoritative device measurement.
	var valid := peak_particles == 30 and remaining_particles == 0 and node_delta <= 5 and average <= 8.0 and p95 <= 16.67
	print("PERFORMANCE_SMOKE: %s six_dc+30_coins average=%.2fms p90=%.2fms p95=%.2fms peak_particles=%d remaining=%d node_delta=%d" % ["PASS" if valid else "FAIL", average, p90, p95, peak_particles, remaining_particles, node_delta])
	AudioService.stop_all()
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if valid else 1)

func _dense_campus() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(6):
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
