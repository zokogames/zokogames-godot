extends Node
## Minimal purchase flow. Attach to any Node. In the editor and on desktop the simulator answers with a
## three-item test catalogue; in a web export the portal's real checkout opens.

func _ready() -> void:
	await ZokoGames.init_async()
	if not ZokoGames.is_store_available:
		return  # hide your shop button on hosts without purchases

	ZokoGames.purchase_completed.connect(func(item_id): print("paid for ", item_id, " (verify ownership on your server)"))
	ZokoGames.purchase_failed.connect(_on_purchase_failed)

	var catalog := await ZokoGames.store_get_catalog_items_async(20)
	if not catalog.ok or catalog.result.is_empty():
		return
	for item in catalog.result:
		print(item.sku, "  ", item.name, "  ", item.price)

	var first: Dictionary = catalog.result[0]
	await ZokoGames.store_buy_item_async(first.sku)  # signals report the outcome
	if first.consumable:
		await ZokoGames.store_consume_item_async(first.sku, 1)

	var token := await ZokoGames.store_get_purchase_token_async()  # send to your server to verify what the player owns
	if token.ok:
		print("purchase token: ", token.result)

	var inventory := await ZokoGames.store_get_player_inventory_async()
	if inventory.ok:
		for owned in inventory.result:
			print(owned.sku, " x", owned.quantity)


func _on_purchase_failed(error: Dictionary) -> void:
	match error.code:
		"purchaseCancelled":
			print("player closed the checkout")
		"userNotAuthenticated":
			ZokoGames.show_auth_prompt()
		_:
			push_warning("purchase failed: %s" % error.message)
