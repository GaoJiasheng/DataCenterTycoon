extends Node

const ROLLBACK_TOLERANCE_SECONDS := 2

func wall_time() -> int:
	return int(Time.get_unix_time_from_system())

func monotonic_msec() -> int:
	return Time.get_ticks_msec()

func elapsed_since(saved_wall_time: int, highest_wall_time: int) -> Dictionary:
	var now := wall_time()
	var guard := maxi(saved_wall_time, highest_wall_time)
	if now + ROLLBACK_TOLERANCE_SECONDS < guard:
		return {
			"elapsed": 0,
			"now": now,
			"highest": guard,
			"rollback": true,
			"rollback_seconds": guard - now,
		}
	return {
		"elapsed": maxi(0, now - saved_wall_time),
		"now": now,
		"highest": maxi(guard, now),
		"rollback": false,
		"rollback_seconds": 0,
	}

func real_seconds_to_game_days(real_seconds: float) -> float:
	var seconds_per_day := float(DataRepository.get_table("economy").get("time", {}).get("real_seconds_per_game_day", 240.0))
	return real_seconds / seconds_per_day

func format_game_date(simulation_seconds: float) -> String:
	var time_data: Dictionary = DataRepository.get_table("economy").get("time", {})
	var day_seconds := float(time_data.get("real_seconds_per_game_day", 240.0))
	var total_days := maxi(0, int(floor(simulation_seconds / day_seconds)))
	var year := total_days / 360 + 1
	var month := (total_days % 360) / 30 + 1
	var day := total_days % 30 + 1
	return tr("DATE_FORMAT") % [year, month, day]
