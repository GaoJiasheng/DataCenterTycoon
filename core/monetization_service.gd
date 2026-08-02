extends Node

signal reward_result(placement: String, success: bool)
signal purchase_result(product_id: String, success: bool, message: String, transaction_id: String)
signal product_info_changed

var provider: Node
var debug_rewards_enabled := true
var product_info: Dictionary = {}

func _ready() -> void:
	if OS.get_name() == "iOS" and (Engine.has_singleton("InAppStore") or Engine.has_singleton("DataCenterAdsBridge")):
		provider = preload("res://platform/native_monetization_provider.gd").new()
	else:
		provider = preload("res://platform/mock_monetization_provider.gd").new()
	add_child(provider)
	provider.reward_result.connect(_on_reward_result)
	provider.purchase_result.connect(_on_purchase_result)
	provider.product_info_updated.connect(_on_product_info_updated)
	provider.request_product_info(DataRepository.get_table("store").get("items", {}).keys())

func request_reward(placement: String) -> void:
	if Game.has_entitlement("noads"):
		_on_reward_result(placement, true)
		return
	provider.request_reward(placement)

func purchase(product_id: String) -> void:
	provider.purchase(product_id)

func restore_purchases() -> void:
	provider.restore_purchases()

func is_product_available(product_id: String) -> bool:
	return provider.is_product_available(product_id)

func localized_price(product_id: String, fallback: String) -> String:
	return str(product_info.get(product_id, {}).get("localized_price", fallback))

func _on_reward_result(placement: String, success: bool) -> void:
	reward_result.emit(placement, success)

func _on_purchase_result(product_id: String, success: bool, message: String, transaction_id: String) -> void:
	purchase_result.emit(product_id, success, message, transaction_id)

func _on_product_info_updated(info: Dictionary) -> void:
	product_info = info.duplicate(true)
	product_info_changed.emit()
