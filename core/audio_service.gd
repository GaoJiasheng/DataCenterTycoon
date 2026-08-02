extends Node

const MANIFEST_PATH := "res://assets/audio/manifest.json"

var manifest: Dictionary = {}
var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var music_enabled := true
var sfx_enabled := true

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	for _index: int in range(6):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	reload_manifest()

func reload_manifest() -> void:
	manifest.clear()
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			manifest = parsed

func play_music(cue_id: String) -> void:
	if not music_enabled:
		return
	var stream := _load_stream(cue_id)
	if stream == null:
		return
	if music_player.stream == stream and music_player.playing:
		return
	music_player.stream = stream
	music_player.volume_db = float(_cue(cue_id).get("volume_db", -8.0))
	music_player.play()

func play_sfx(cue_id: String) -> void:
	if not sfx_enabled:
		return
	var stream := _load_stream(cue_id)
	if stream == null:
		return
	var player: AudioStreamPlayer = sfx_players[0]
	for candidate: AudioStreamPlayer in sfx_players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = stream
	player.volume_db = float(_cue(cue_id).get("volume_db", -4.0))
	player.play()

func apply_settings(settings: Dictionary) -> void:
	music_enabled = bool(settings.get("music_enabled", true))
	sfx_enabled = bool(settings.get("sfx_enabled", true))
	if not music_enabled:
		music_player.stop()

func stop_all() -> void:
	if music_player != null:
		music_player.stop()
		music_player.stream = null
	for player: AudioStreamPlayer in sfx_players:
		player.stop()
		player.stream = null

func _cue(cue_id: String) -> Dictionary:
	return manifest.get("items", {}).get(cue_id, {})

func _load_stream(cue_id: String) -> AudioStream:
	var path := str(_cue(cue_id).get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null and bool(_cue(cue_id).get("loop", false)) and "loop" in stream:
		stream.set("loop", true)
	return stream
