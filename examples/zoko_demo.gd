extends Node
## Attach to any Node. Keys: A midgame ad, R rewarded ad, G gameplay start/stop, H happytime, U user, F friends,
## T token, E encrypt a score, S save, M room message and state, B buy the first store item.
## Press G (gameplay start) before the first A: since SDK 1.6.4 a web build refuses a midgame ad with adCooldown until the game has called gameplay start (or 30 s of visible time passed).

var _playing := false


func _ready() -> void:
	var res := await ZokoGames.init_async()
	if not res.ok:
		push_warning("ZokoGames init failed: %s" % res.error.code)
		return
	print("ZokoGames ready in ", ZokoGames.environment, " (simulated: ", ZokoGames.is_simulated, ")")
	ZokoGames.settings_changed.connect(func(s: Dictionary) -> void: AudioServer.set_bus_mute(0, bool(s.muteAudio)))
	ZokoGames.auth_changed.connect(func(u: Dictionary) -> void: print("signed in as ", u.get("username", "(signed out)")))
	ZokoGames.ad_started.connect(func() -> void: get_tree().paused = true)
	ZokoGames.ad_finished.connect(func() -> void: get_tree().paused = false)
	ZokoGames.ad_error.connect(func(_e: Dictionary) -> void: get_tree().paused = false)
	ZokoGames.room_message.connect(func(m: Dictionary) -> void: print("room message from ", m.from, ": ", m.data))
	ZokoGames.room_state.connect(func(state: Dictionary, _change: Dictionary) -> void: print("room state: ", state))
	process_mode = Node.PROCESS_MODE_ALWAYS

	var plays := int(ZokoGames.data_get_item("plays", "0")) + 1
	ZokoGames.data_set_item("plays", str(plays))
	print("Cloud save says this is play #", plays)


func _unhandled_key_input(event: InputEvent) -> void:
	if not ZokoGames.is_initialized or not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_A:
			ZokoGames.request_ad("midgame")
		KEY_R:
			ZokoGames.request_ad("rewarded")
		KEY_G:
			_playing = not _playing
			if _playing:
				ZokoGames.gameplay_start()
			else:
				ZokoGames.gameplay_stop()
		KEY_H:
			ZokoGames.happytime()
		KEY_U:
			var user := await ZokoGames.get_user_async()
			print(user.result.username if user.ok and user.result != null else "logged out")
		KEY_F:
			var page := await ZokoGames.list_friends_async(1, 10)
			print(page.result.total if page.ok else page.error.code, " friends")
		KEY_T:
			var token := await ZokoGames.get_user_token_async()
			print(token.result if token.ok else token.error.code)
		KEY_E:
			var enc := await ZokoGames.encrypt_score_async(100.0, "demo-key")
			print(enc.result if enc.ok else enc.error.code)
		KEY_S:
			ZokoGames.set_game_context({"level": 3, "hard": true})
			ZokoGames.track_order("xsolla", {"sku": "gems_100", "price": 0.99})
		KEY_M:
			# Room data channel: the simulator loops these back to this instance.
			ZokoGames.room_send({"type": "ping", "t": Time.get_ticks_msec()})
			if ZokoGames.room_is_host():
				ZokoGames.room_set_state({"lastPing": Time.get_ticks_msec()})
		KEY_B:
			if ZokoGames.is_store_available:
				var catalog := await ZokoGames.store_get_catalog_items_async()
				if catalog.ok and catalog.result.size() > 0:
					var bought := await ZokoGames.store_buy_item_async(catalog.result[0].sku)
					print("purchase: ", bought, " (verify ownership on your server)")
