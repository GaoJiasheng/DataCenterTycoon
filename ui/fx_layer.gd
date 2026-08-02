class_name FxLayer
extends Control

const MAX_COINS := 8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 95

func fly_coins(world_position: Vector2, target: Control, count: int = 3) -> void:
	var texture := AssetCatalog.texture("fx_coin")
	if texture == null or target == null or not is_instance_valid(target):
		return
	var start := _to_local_point(world_position)
	if start == Vector2.ZERO:
		start = size * Vector2(0.5, 0.56)
	var destination := _to_local_point(target.get_global_rect().get_center())
	var amount := clampi(count, 1, MAX_COINS)
	for index: int in range(amount):
		_spawn_coin(texture, start, destination, index, amount, target)

func clear() -> void:
	for child: Node in get_children():
		if child.name == "FlyingCoin":
			child.queue_free()

func pulse_target(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	target.pivot_offset = target.size * 0.5
	var tween := target.create_tween()
	tween.tween_property(target, "scale", Vector2.ONE * 1.06, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_coin(texture: Texture2D, start: Vector2, destination: Vector2, index: int, amount: int, target: Control) -> void:
	var coin := TextureRect.new()
	coin.name = "FlyingCoin"
	coin.texture = texture
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.size = Vector2(42, 42)
	coin.pivot_offset = coin.size * 0.5
	coin.position = start - coin.size * 0.5 + Vector2((index - amount * 0.5) * 10.0, sin(index * 2.1) * 12.0)
	coin.scale = Vector2.ONE * 0.68
	coin.modulate.a = 0.0
	add_child(coin)
	var origin := coin.position
	var finish := destination - coin.size * 0.5
	var arc := Vector2((index - amount * 0.5) * 18.0, -120.0 - index % 3 * 18.0)
	var delay := index * 0.04
	var tween := coin.create_tween()
	tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.tween_property(coin, "modulate:a", 1.0, 0.08)
	tween.tween_property(coin, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(progress: float) -> void:
		if not is_instance_valid(coin):
			return
		var one_minus := 1.0 - progress
		coin.position = one_minus * one_minus * origin + 2.0 * one_minus * progress * (origin + arc) + progress * progress * finish
		coin.rotation = progress * TAU * (1.0 + float(index % 2))
	, 0.0, 1.0, 0.60).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(coin):
			coin.queue_free()
		if index == amount - 1:
			pulse_target(target)
	)

func _to_local_point(global_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_point
