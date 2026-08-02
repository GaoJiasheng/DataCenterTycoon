extends Node

signal reward_result(placement: String, success: bool)
signal purchase_result(product_id: String, success: bool, message: String, transaction_id: String)
signal product_info_updated(info: Dictionary)

var valid_products: Dictionary = {}

func request_product_info(product_ids: Array) -> void:
	valid_products.clear()
	var store: Dictionary = DataRepository.get_table("store").get("items", {})
	for product_id: String in product_ids:
		var product: Dictionary = store.get(product_id, {})
		if not product.is_empty():
			valid_products[product_id] = {"localized_price": "US$ %.2f" % float(product.get("price_usd", 0.0))}
	product_info_updated.emit(valid_products)

func request_reward(placement: String) -> void:
	await get_tree().create_timer(0.15).timeout
	reward_result.emit(placement, true)

func purchase(product_id: String) -> void:
	await get_tree().create_timer(0.15).timeout
	if OS.is_debug_build():
		purchase_result.emit(product_id, true, "mock_purchase", "mock:%s:%d" % [product_id, Time.get_ticks_usec()])
	else:
		purchase_result.emit(product_id, false, "native_provider_not_configured", "")

func restore_purchases() -> void:
	await get_tree().create_timer(0.15).timeout
	purchase_result.emit("restore", OS.is_debug_build(), "mock_restore", "")

func is_product_available(product_id: String) -> bool:
	return OS.is_debug_build() and valid_products.has(product_id)
