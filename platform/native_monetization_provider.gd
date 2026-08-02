extends Node

signal reward_result(placement: String, success: bool)
signal purchase_result(product_id: String, success: bool, message: String, transaction_id: String)
signal product_info_updated(info: Dictionary)

var in_app_store: Object
var ads_bridge: Object
var pending_reward_placement := ""
var valid_products: Dictionary = {}

func _ready() -> void:
	if Engine.has_singleton("InAppStore"):
		in_app_store = Engine.get_singleton("InAppStore")
		if in_app_store.has_method("set_auto_finish_transaction"):
			in_app_store.call("set_auto_finish_transaction", false)
	if Engine.has_singleton("DataCenterAdsBridge"):
		ads_bridge = Engine.get_singleton("DataCenterAdsBridge")
		if ads_bridge.has_signal("rewarded_completed"):
			ads_bridge.connect("rewarded_completed", _on_rewarded_completed)
	set_process(true)

func request_product_info(product_ids: Array) -> void:
	if in_app_store == null or not in_app_store.has_method("request_product_info"):
		product_info_updated.emit({})
		return
	var error := int(in_app_store.call("request_product_info", {"product_ids": product_ids}))
	if error != OK:
		product_info_updated.emit({})

func _process(_delta: float) -> void:
	if in_app_store == null or not in_app_store.has_method("get_pending_event_count"):
		return
	while int(in_app_store.call("get_pending_event_count")) > 0:
		var event: Variant = in_app_store.call("pop_pending_event")
		if event is Dictionary:
			_process_store_event(event)

func request_reward(placement: String) -> void:
	if ads_bridge == null or not ads_bridge.has_method("show_rewarded"):
		reward_result.emit(placement, false)
		return
	if not pending_reward_placement.is_empty():
		reward_result.emit(placement, false)
		return
	pending_reward_placement = placement
	var accepted: Variant = ads_bridge.call("show_rewarded", placement)
	if accepted is bool and not accepted:
		pending_reward_placement = ""
		reward_result.emit(placement, false)
		return
	get_tree().create_timer(180.0).timeout.connect(_on_reward_timeout.bind(placement))

func purchase(product_id: String) -> void:
	if in_app_store == null or not in_app_store.has_method("purchase"):
		purchase_result.emit(product_id, false, "iap_plugin_unavailable", "")
		return
	var error := int(in_app_store.call("purchase", {"product_id": product_id}))
	if error != OK:
		purchase_result.emit(product_id, false, "purchase_request_%d" % error, "")

func restore_purchases() -> void:
	if in_app_store == null or not in_app_store.has_method("restore_purchases"):
		purchase_result.emit("restore", false, "iap_plugin_unavailable", "")
		return
	var error := int(in_app_store.call("restore_purchases"))
	if error != OK:
		purchase_result.emit("restore", false, "restore_request_%d" % error, "")

func is_product_available(product_id: String) -> bool:
	return valid_products.has(product_id)

func _process_store_event(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type == "product_info":
		_process_product_info(event)
		return
	if type not in ["purchase", "restore"]:
		return
	var product_id := str(event.get("product_id", ""))
	var success := str(event.get("result", "")) == "ok"
	var transaction_id := str(event.get("transaction_id", event.get("transaction_identifier", "")))
	purchase_result.emit(product_id, success, "restore" if type == "restore" else "purchase", transaction_id)
	if type == "purchase" and success and in_app_store.has_method("finish_transaction"):
		in_app_store.call("finish_transaction", product_id)

func _process_product_info(event: Dictionary) -> void:
	valid_products.clear()
	if str(event.get("result", "")) != "ok":
		product_info_updated.emit(valid_products)
		return
	var ids: Array = event.get("ids", [])
	var localized_prices: Array = event.get("localized_prices", [])
	for index: int in range(ids.size()):
		valid_products[str(ids[index])] = {
			"localized_price": str(localized_prices[index]) if index < localized_prices.size() else "",
		}
	product_info_updated.emit(valid_products)

func _on_rewarded_completed(placement: String, earned: bool) -> void:
	if placement != pending_reward_placement:
		return
	pending_reward_placement = ""
	reward_result.emit(placement, earned)

func _on_reward_timeout(placement: String) -> void:
	if placement != pending_reward_placement:
		return
	pending_reward_placement = ""
	reward_result.emit(placement, false)
