class_name CampusCat
extends Node2D

signal interacted(item_id: String)

const COLLECTION_SOURCE := "campus_life"
const BODY_SIZE := 112.0
const HIT_RADIUS := 44.0
const WALK_FRAME_SECONDS := 0.28

var current_state := "sleep"
var last_discovered_item := ""
var interaction_count := 0

var _config: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _sprite: Sprite2D
var _hit_area: Area2D
var _state_remaining := 0.0
var _interaction_cooldown := 0.0
var _walk_frame_remaining := WALK_FRAME_SECONDS
var _walk_frame := false
var _rare_market_active := false
var _roof_anchor := Vector2.ZERO
var _roam_bounds := Rect2()
var _stroll_start := Vector2.ZERO
var _stroll_end := Vector2.ZERO
var _stroll_progress := 0.0
var _roll_tween: Tween

func _ready() -> void:
	name = "CampusCat"
	z_index = 1080
	set_meta("campus_cat", true)
	_sprite = Sprite2D.new()
	_sprite.name = "CampusCatSprite"
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	_hit_area = Area2D.new()
	_hit_area.name = "CampusCatHitArea"
	_hit_area.input_pickable = true
	_hit_area.collision_layer = 1
	_hit_area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, -4)
	_hit_area.add_child(shape)
	_hit_area.input_event.connect(_on_input_event)
	add_child(_hit_area)
	set_process(true)

func configure(game_state: Dictionary, data: Dictionary, campus_index: int, roof_anchor: Vector2, roam_bounds: Rect2) -> void:
	_config = data.get("campus_cat", {})
	set_meta("campus_index", campus_index)
	_roof_anchor = roof_anchor
	_roam_bounds = roam_bounds
	_rare_market_active = is_rare_market_active(game_state, data)
	var unlocked := is_unlocked(game_state, _config)
	visible = unlocked
	if _hit_area != null:
		_hit_area.input_pickable = unlocked
	if not unlocked:
		return
	# This generator belongs only to the transient sprite. Its seed is derived
	# from visible state and never reads or advances any persistent gameplay RNG.
	var total_built := int(game_state.get("player", {}).get("total_datacenters_built", 0))
	var sim_bucket := int(float(game_state.get("clock", {}).get("total_seconds", 0.0)) / 60.0)
	_rng.seed = int(("campus-cat:%d:%d:%d" % [campus_index, total_built, sim_bucket]).hash()) & 0x7fffffff
	_choose_next_state()

func set_suppressed(suppressed: bool) -> void:
	visible = not suppressed and is_unlocked(Game.state, _config)
	if _hit_area != null:
		_hit_area.input_pickable = visible

func force_state_for_tests(state_id: String, rare_active: bool = false) -> void:
	_rare_market_active = rare_active
	_enter_state(state_id)
	visible = true
	if _hit_area != null:
		_hit_area.input_pickable = true

func interact_for_tests() -> String:
	return _interact()

func hit_radius() -> float:
	return HIT_RADIUS

func _process(delta: float) -> void:
	if not visible:
		return
	_interaction_cooldown = maxf(0.0, _interaction_cooldown - delta)
	_state_remaining -= delta
	if current_state == "stroll":
		_update_stroll(delta)
	if _state_remaining <= 0.0:
		_choose_next_state()

func _choose_next_state() -> void:
	var weights: Dictionary = _config.get("state_weights", {"sleep": 0.52, "stroll": 0.30, "sit": 0.18})
	var roll := _rng.randf()
	var cursor := 0.0
	var selected := "sleep"
	for state_id: String in ["sleep", "stroll", "sit"]:
		cursor += float(weights.get(state_id, 0.0))
		if roll <= cursor:
			selected = state_id
			break
	_enter_state(selected)

func _enter_state(state_id: String) -> void:
	current_state = state_id if state_id in ["sleep", "stroll", "sit"] else "sleep"
	var interval: Dictionary = _config.get("switch_interval_seconds", {})
	_state_remaining = _rng.randf_range(float(interval.get("minimum", 14.0)), float(interval.get("maximum", 28.0)))
	_stroll_progress = 0.0
	_walk_frame = false
	_walk_frame_remaining = WALK_FRAME_SECONDS
	_stroll_start = Vector2(_roam_bounds.position.x + 72.0, _roam_bounds.end.y - 34.0)
	_stroll_end = Vector2(_roam_bounds.end.x - 72.0, _roam_bounds.end.y - 34.0)
	match current_state:
		"sleep": position = _roof_anchor
		"sit": position = Vector2(_roam_bounds.end.x - 82.0, _roam_bounds.position.y + 36.0)
		"stroll": position = _stroll_start
	_refresh_texture()

func _update_stroll(delta: float) -> void:
	var distance := maxf(1.0, _stroll_start.distance_to(_stroll_end))
	var speed := float(_config.get("walk_speed", 20.0))
	_stroll_progress = fposmod(_stroll_progress + delta * speed / distance, 2.0)
	var travel := _stroll_progress if _stroll_progress <= 1.0 else 2.0 - _stroll_progress
	position = _stroll_start.lerp(_stroll_end, travel)
	_sprite.flip_h = _stroll_progress > 1.0
	_walk_frame_remaining -= delta
	if _walk_frame_remaining <= 0.0:
		_walk_frame = not _walk_frame
		_walk_frame_remaining = WALK_FRAME_SECONDS
		_refresh_texture()

func _refresh_texture() -> void:
	var asset_id := "cat_sleep"
	if _rare_market_active:
		asset_id = "cat_sunglasses"
	elif current_state == "sit":
		asset_id = "cat_sit"
	elif current_state == "stroll":
		asset_id = "cat_walk_b" if _walk_frame else "cat_walk_a"
	_sprite.texture = AssetCatalog.texture(asset_id)
	if _sprite.texture != null:
		var texture_size := _sprite.texture.get_size()
		var fit := BODY_SIZE / maxf(1.0, maxf(texture_size.x, texture_size.y))
		_sprite.scale = Vector2.ONE * fit
	_sprite.flip_h = current_state == "stroll" and _stroll_progress > 1.0

func _on_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if not visible:
		return
	var pressed: bool = (event is InputEventMouseButton or event is InputEventScreenTouch) and bool(event.get("pressed"))
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_interact()

func _interact() -> String:
	if not visible:
		return ""
	interaction_count += 1
	Input.vibrate_handheld(18)
	var item_id := collection_item_for_context(current_state, _rare_market_active)
	if not item_id.is_empty() and not bool(Game.call("_collection_item_discovered", COLLECTION_SOURCE, item_id)):
		Game.call("_discover", COLLECTION_SOURCE, item_id)
		last_discovered_item = item_id
		interacted.emit(item_id)
	_play_roll(_interaction_cooldown > 0.0)
	if _interaction_cooldown <= 0.0:
		_interaction_cooldown = float(_config.get("interaction_cooldown_seconds", 1.6))
		if _rng.randf() <= float(_config.get("heart_chance", 0.32)):
			_spawn_heart()
	return item_id

func _play_roll(short_version: bool) -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	var previous_texture := _sprite.texture
	var previous_scale := _sprite.scale
	var roll_texture := AssetCatalog.texture("cat_roll")
	if roll_texture != null:
		_sprite.texture = roll_texture
		var texture_size := roll_texture.get_size()
		_sprite.scale = Vector2.ONE * (BODY_SIZE / maxf(1.0, maxf(texture_size.x, texture_size.y)))
	var duration := 0.18 if short_version else 0.34
	_sprite.rotation = -0.08
	_roll_tween = create_tween()
	_roll_tween.tween_property(_sprite, "rotation", 0.10, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_roll_tween.parallel().tween_property(_sprite, "scale", _sprite.scale * 1.08, duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_property(_sprite, "rotation", 0.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_roll_tween.parallel().tween_property(_sprite, "scale", previous_scale, duration * 0.5)
	_roll_tween.finished.connect(func() -> void:
		if not is_instance_valid(_sprite):
			return
		_sprite.texture = previous_texture
		_refresh_texture()
	)

func _spawn_heart() -> void:
	var texture := AssetCatalog.texture("fx_cat_heart")
	if texture == null:
		return
	var heart := Sprite2D.new()
	heart.name = "CampusCatHeart"
	heart.texture = texture
	heart.position = Vector2(20, -58)
	heart.modulate.a = 0.0
	heart.scale = Vector2.ONE * 0.045
	add_child(heart)
	var tween := heart.create_tween().set_parallel(true)
	tween.tween_property(heart, "position:y", -94.0, 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(heart, "scale", Vector2.ONE * 0.07, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(heart, "modulate:a", 1.0, 0.12)
	tween.tween_property(heart, "modulate:a", 0.0, 0.24).set_delay(0.48)
	tween.finished.connect(heart.queue_free)

static func is_unlocked(game_state: Dictionary, config: Dictionary) -> bool:
	if not bool(game_state.get("tutorial", {}).get("completed", false)):
		return false
	var unlock: Dictionary = config.get("unlock", {})
	if bool(unlock.get("standard_built", true)) and bool(game_state.get("flags", {}).get("standard_built", false)):
		return true
	return int(game_state.get("player", {}).get("total_datacenters_built", 0)) >= int(unlock.get("minimum_datacenters_built", 2))

static func is_rare_market_active(game_state: Dictionary, data: Dictionary) -> bool:
	var now := float(game_state.get("clock", {}).get("total_seconds", 0.0))
	for active_variant: Variant in game_state.get("market", {}).get("active", []):
		if not active_variant is Dictionary:
			continue
		var active: Dictionary = active_variant
		if float(active.get("end_at", 0.0)) <= now:
			continue
		var event: Dictionary = data.get("events", {}).get("items", {}).get(str(active.get("event_id", "")), {})
		if bool(event.get("rare", false)):
			return true
	return false

static func collection_item_for_context(state_id: String, rare_active: bool) -> String:
	if rare_active:
		return "cat_festival"
	match state_id:
		"sleep": return "cat_nap"
		"stroll": return "cat_parade"
		"sit": return "cat_watch"
	return ""
