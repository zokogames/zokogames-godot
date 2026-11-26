extends Node
## ZokoGames SDK autoload (Godot 4, HTML5 export).
##
## Every method has a callback form `name(..., callback := Callable())` and an awaitable
## `name_async(...)` form. Both deliver a Dictionary: `{"ok": true, "result": <value>}` or
## `{"ok": false, "error": {"code": String, "message": String}}`.
## Ads additionally raise the signals below. Outside a browser (editor, desktop) a simulator answers;
## tune it under Project Settings > zokogames/simulator.
## JS name mapping: camelCase becomes snake_case (`game.gameplayStart()` -> `gameplay_start()`).

signal initialized(ok: bool)
signal ad_started
signal ad_finished
signal ad_error(error: Dictionary)
signal auth_changed(user: Dictionary)
signal settings_changed(settings: Dictionary)
signal join_room(params: Dictionary)
## Emitted with the new value when the player goes offline or back online (SDK 1.2.0+).
signal offline_changed(offline: bool)
## Raised after every store_buy_item / store_buy_item_async: the item id once paid, or the error (read error.code).
signal purchase_completed(item_id: String)
signal purchase_failed(error: Dictionary)
## Emitted with the achievement Dictionary when the player unlocks one (including via achievements_unlock).
signal achievement_unlocked(achievement: Dictionary)
## Room data channel (SDK 1.3.0). A message from another player: {"from", "data", "direct", "seq", "ts"}. Never emitted for your own messages on the portal.
signal room_message(message: Dictionary)
## The shared room state changed: the whole new state plus {"by", "keys", "rev"} describing the change.
signal room_state(state: Dictionary, change: Dictionary)
## A player joined or left (or their profile changed): Array of {"id", "username", "profilePictureUrl"}, including this player.
signal room_members(members: Array)
## The host changed (also the first assignment). host_id is "" when there is no host; is_host is true when it is this player.
signal room_host_changed(host_id: String, is_host: bool)
## A failure the platform reports after a room call returned, such as rateLimited or notHost: {"code", "message"}.
signal room_error(error: Dictionary)
## SDK 1.7.0: reason is "left", "kicked", "closed" or "disconnected"; room_id is "" when unknown.
signal room_left(reason: String, room_id: String)
## A mirrored localStorage key could not be saved (SDK 1.4.0), for example dataLimitExceeded: {"code", "message"}.
signal mirror_error(error: Dictionary)

## Wrapper version; matches the JavaScript SDK release it was written against.
const VERSION := "1.8.1"
const BRIDGE_NAME := "ZokoBridge"
const STATIC_BANNER_SIZES: Array[String] = ["728x90", "300x250", "320x50", "468x60", "320x100"]
const DATA_LIMIT_BYTES := 1048576
## Longest side, in pixels, of the picture sent for the feedback form (the SDK scales to 1280 anyway).
const SCREENSHOT_MAX_EDGE := 1280
## JPG quality of the built-in encoder (0.0 to 1.0).
const SCREENSHOT_JPG_QUALITY := 0.8
## Every error code an SDK call can raise, grouped by module (the JS SDK's ERROR_CODES).
const ERROR_CODES := {
	"ad": ["adsDisabled", "unfilled", "adblock", "adCooldown", "other"],
	"banner": ["bannersDisabled", "unfilled", "missingId", "notVisible", "noAvailableSizes", "notCreated", "videoAdPlaying", "invalidSize", "bannerCooldown", "maxRefreshReached", "other"],
	"user": ["userNotAuthenticated", "userAlreadySignedIn", "userCancelled", "showAuthPromptInProgress", "showAccountLinkPromptInProgress", "rateLimited", "requestInProgress", "unexpectedError"],
	"data": ["dataLimitExceeded", "dataModuleDisabled", "other"],
	"store": ["catalogFetchFailed", "inventoryFetchFailed", "purchaseInitFailed", "purchaseInProgress", "purchaseCancelled", "consumeItemFailed", "itemNotConsumable", "itemNotInInventory", "insufficientItemQuantity", "userNotAuthenticated", "invalidArgument", "requestInProgress", "unexpectedError", "other"],
	"achievements": ["invalidArgument", "other"],
	"room": ["notInRoom", "notHost", "payloadTooLarge", "stateTooLarge", "unknownMember", "rateLimited", "roomUnavailable", "invalidArgument"],
	"general": ["sdkNotInitialized", "sdkNotLoaded", "sdkDisabled", "invalidArgument", "timeout"],
}
const SIM_SAVE_PATH := "user://zoko_sim_data.json"
const ROOM_MAX_PAYLOAD_BYTES := 8192
const ROOM_MAX_STATE_BYTES := 65536
const SIM_ROOM_SELF_ID := "sim-player"

class _Req extends RefCounted:
	signal completed

## "local", "zokogames" or "disabled" ("disabled" until init completes).
var environment := "disabled"
var is_qa_tool := false
var is_initialized := false
var is_user_account_available := false
var is_instant_multiplayer := false
## Deprecated alias of `is_instant_multiplayer` (JS: isInstantJoin).
var is_instant_join := false
## True while the player has no connection (JS: game.isOffline). False on older SDKs and portals.
var is_offline := false
## True when this host offers purchases. Says nothing about sign-in.
var is_store_available := false
## Read-only id the portal sends at init (JS: game.gameId). Empty before init or when the portal does not send it.
var game_id := ""
## Portal settings: `disableChat`, `muteAudio` and, from SDK 1.5.0, `kidsMode` (absent on older portals: read it with
## `settings.get("kidsMode", false)` and keep honouring `disableChat`).
var settings := {"disableChat": false, "kidsMode": false, "muteAudio": false}
var system_info := {}
## Parameters the game was launched with through an invite link (empty when none).
var invite_params := {}
## True when the simulator, not the browser SDK, answers.
var is_simulated := false
## While an ad plays (ad_started .. ad_finished / ad_error) the autoload sets `get_tree().paused` and restores the previous
## value afterwards. The autoload itself keeps processing (PROCESS_MODE_ALWAYS). Set to false to pause the game yourself.
var pause_game_during_ads := true
## Same for the Master audio bus (bus 0): muted during an ad, the previous mute state (or the portal's mute setting) restored after.
var mute_audio_during_ads := true
## Apply the portal's mute setting (`settings.muteAudio`) to the Master bus after init and on every change. Set to false to
## handle `settings_changed` yourself.
var follow_portal_mute := true

var _bridge: JavaScriptObject
var _sink: JavaScriptObject  # keep a reference or the callback is garbage collected
var _next_id := 1
var _pending := {}
var _initializing := false
var _init_waiters: Array[Callable] = []
var _ad_active := false
var _ad_was_paused := false
var _ad_was_muted := false

# simulator state
var _sim_data := {}
var _sim_logged_in := false
var _sim_ad_playing := false
var _sim_auth_open := false
var _sim_banner_at := {}
var _sim_achievements := {}
var _sim_room_state := {}
var _sim_room_rev := 0
var _sim_room_seq := 0

# screenshot provider (SDK 1.4.0)
var _screenshot_provider: Callable = Callable()
var _screenshot_provider_off := false
var _screenshot_registered := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- init

## Initialise once at startup. Waits for the SDK; safe to call repeatedly.
func init(callback: Callable = Callable()) -> void:
	if is_initialized:
		if callback.is_valid():
			callback.call({"ok": true, "result": null})
		return
	if callback.is_valid():
		_init_waiters.append(callback)
	if _initializing:
		return
	_initializing = true
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface(BRIDGE_NAME)
	if _bridge != null:
		_sink = JavaScriptBridge.create_callback(_on_sink)
		_bridge.setSink(_sink)
		is_simulated = false
	else:
		if OS.has_feature("web"):
			push_warning("ZokoGames: window.%s not found. Use addons/zokogames/export/zokogames_shell.html as the custom HTML shell. Falling back to the simulator." % BRIDGE_NAME)
		is_simulated = true
		_sim_load()
	_call("init", {}, _on_init_done)


## Awaitable init(): sets up the JavaScript bridge (or the simulator) exactly like init(), then returns the same result Dictionary.
func init_async() -> Dictionary:
	var req := _Req.new()
	var box := {"done": false, "res": {}}
	var cb := func(res: Dictionary) -> void:
		box.done = true
		box.res = res
		req.completed.emit()
	init(cb)
	if not box.done:
		await req.completed
	return box.res


func _on_init_done(res: Dictionary) -> void:
	_initializing = false
	if res.ok:
		var r: Dictionary = res.result
		environment = str(r.get("environment", "disabled"))
		is_qa_tool = bool(r.get("isQaTool", false))
		settings = r.get("settings", settings)
		system_info = r.get("systemInfo", {}) if r.get("systemInfo") != null else {}
		is_user_account_available = bool(r.get("isUserAccountAvailable", false))
		is_instant_multiplayer = bool(r.get("isInstantMultiplayer", false))
		is_instant_join = is_instant_multiplayer
		is_offline = bool(r.get("isOffline", false))
		is_store_available = bool(r.get("storeAvailable", false))
		game_id = str(r.get("gameId", ""))
		invite_params = r.get("inviteParams", {}) if r.get("inviteParams") != null else {}
		is_initialized = true
		_apply_portal_mute()
		_register_screenshot_provider()
	var waiters := _init_waiters.duplicate()
	_init_waiters.clear()
	for w in waiters:
		if w.is_valid():
			w.call(res)
	initialized.emit(res.ok)


## True when initialised and the SDK is not disabled.
func is_available() -> bool:
	return is_initialized and environment != "disabled"


# ---------------------------------------------------------------- transport

func _call(method: String, args: Dictionary, callback: Callable = Callable(), on_event: Callable = Callable()) -> void:
	if method != "init":
		if not is_initialized:
			_defer_finish(callback, _fail("sdkNotInitialized", "Call ZokoGames.init() and wait for it to finish"))
			return
		if environment == "disabled":
			_defer_finish(callback, _fail("sdkDisabled", "The SDK is disabled in this environment"))
			return
	var id := _next_id
	_next_id += 1
	_pending[id] = {"done": callback, "event": on_event}
	if is_simulated:
		_sim(id, method, args)
	else:
		_bridge.invoke(id, method, JSON.stringify(args))


func _call_async(method: String, args: Dictionary) -> Dictionary:
	var req := _Req.new()
	var box := {"done": false, "res": {}}
	var cb := func(res: Dictionary) -> void:
		box.done = true
		box.res = res
		req.completed.emit()
	_call(method, args, cb)
	if not box.done:
		await req.completed
	return box.res


func _call_sync(method: String, args: Dictionary) -> Dictionary:
	if not is_available():
		return _fail("sdkNotInitialized" if not is_initialized else "sdkDisabled", "The SDK is not available")
	if is_simulated:
		return _sim_sync(method, args)
	var parsed: Variant = JSON.parse_string(str(_bridge.invokeSync(method, JSON.stringify(args))))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("other", "Bad bridge response")
	return {"ok": true, "result": parsed.get("result")} if parsed.get("ok", false) else {"ok": false, "error": parsed.get("error", {})}


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}


func _defer_finish(callback: Callable, res: Dictionary) -> void:
	if not callback.is_valid():
		return
	await get_tree().process_frame
	callback.call(res)


func _finish(id: int, res: Dictionary) -> void:
	var p: Variant = _pending.get(id)
	if p == null:
		return
	_pending.erase(id)
	var cb: Callable = p.done
	if cb.is_valid():
		cb.call(res)


func _emit_event(id: int, event_name: String, data: Variant) -> void:
	var p: Variant = _pending.get(id)
	if p != null and p.event.is_valid():
		p.event.call(event_name, data)


func _on_global(event_name: String, data: Variant) -> void:
	match event_name:
		"settingsChange":
			settings = data if typeof(data) == TYPE_DICTIONARY else settings
			_apply_portal_mute()
			settings_changed.emit(settings)
		"offlineChange":
			var off := bool(data)
			if off != is_offline:
				is_offline = off
				offline_changed.emit(off)
		"auth":
			# A typed `user: Dictionary` handler would fail on null, so a signed-out user arrives as {}.
			auth_changed.emit(data if typeof(data) == TYPE_DICTIONARY else {})
		"joinRoom":
			# invite_params is a typed Dictionary; assigning null to it is a runtime error.
			invite_params = data if typeof(data) == TYPE_DICTIONARY else {}
			join_room.emit(invite_params)
		"achievementUnlocked":
			achievement_unlocked.emit(data)
		"roomMessage":
			room_message.emit(data)
		"roomState":
			room_state.emit(data.get("state", {}), data.get("change", {}))
		"roomMembers":
			room_members.emit(data if typeof(data) == TYPE_ARRAY else [])
		"roomHost":
			var host_id: Variant = data.get("hostId")
			room_host_changed.emit(str(host_id) if host_id != null else "", bool(data.get("isHost", false)))
		"roomError":
			room_error.emit(data)
		"roomLeft":
			var left_room_id: Variant = data.get("roomId") if typeof(data) == TYPE_DICTIONARY else null
			room_left.emit(str(data.get("reason", "")) if typeof(data) == TYPE_DICTIONARY else "", str(left_room_id) if left_room_id != null else "")
		"screenshotRequest":
			_answer_screenshot()
		"mirrorError":
			mirror_error.emit(data)


## Receives one JSON string per message from window.ZokoBridge.
func _on_sink(args: Array) -> void:
	var msg: Variant = JSON.parse_string(str(args[0]))
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("kind", "")):
		"global":
			_on_global(str(msg.name), msg.get("data"))
		"event":
			_emit_event(int(msg.id), str(msg.name), msg.get("data"))
		"done":
			if msg.get("ok", false):
				_finish(int(msg.id), {"ok": true, "result": msg.get("result")})
			else:
				_finish(int(msg.id), {"ok": false, "error": msg.get("error", {})})


func _norm_rect(window_rect: Rect2) -> Dictionary:
	var win := Vector2(maxf(1.0, float(get_window().size.x)), maxf(1.0, float(get_window().size.y)))
	return {
		"nx": window_rect.position.x / win.x, "ny": window_rect.position.y / win.y,
		"nw": window_rect.size.x / win.x, "nh": window_rect.size.y / win.y,
	}


# ---------------------------------------------------------------- Ad

## Request a "midgame" or "rewarded" ad. While it plays the tree is paused and Master is muted (see
## `pause_game_during_ads` and `mute_audio_during_ads`); both are restored on ad_finished / ad_error.
## `callbacks` may hold Callables under "ad_started", "ad_finished" and "ad_error" (receives the error).
func request_ad(type: String = "midgame", callbacks: Dictionary = {}) -> void:
	# Only a request whose ad started releases the pause and mute: a second request refused while an ad plays
	# ("Another ad request is already in progress") must not resume the game under the first ad.
	# A Dictionary, because a lambda captures a bool by value.
	var state := {"started": false}
	var on_event := func(event_name: String, data: Variant) -> void:
		match event_name:
			"adStarted":
				state.started = true
				_ad_begin()
				ad_started.emit()
				if callbacks.has("ad_started"): callbacks["ad_started"].call()
			"adFinished":
				if state.started: _ad_end()
				ad_finished.emit()
				if callbacks.has("ad_finished"): callbacks["ad_finished"].call()
			"adError":
				if state.started: _ad_end()
				ad_error.emit(data)
				if callbacks.has("ad_error"): callbacks["ad_error"].call(data)
	var on_done := func(res: Dictionary) -> void:
		if not res.ok:
			if state.started: _ad_end()
			ad_error.emit(res.error)
			if callbacks.has("ad_error"): callbacks["ad_error"].call(res.error)
	_call("ad.requestAd", {"type": type}, on_done, on_event)


## Completes after the ad ends: {"ok": true} when finished, {"ok": false, "error": ...} otherwise.
func request_ad_async(type: String = "midgame") -> Dictionary:
	var req := _Req.new()
	var box := {"done": false, "res": {}}
	var fin := func(res: Dictionary) -> void:
		if box.done:
			return
		box.done = true
		box.res = res
		req.completed.emit()
	request_ad(type, {
		"ad_finished": func() -> void: fin.call({"ok": true, "result": null}),
		"ad_error": func(e: Dictionary) -> void: fin.call({"ok": false, "error": e}),
	})
	if not box.done:
		await req.completed
	return box.res


func _ad_begin() -> void:
	if _ad_active:
		return
	_ad_active = true
	_ad_was_paused = get_tree().paused
	_ad_was_muted = AudioServer.is_bus_mute(0)
	if pause_game_during_ads:
		get_tree().paused = true
	if mute_audio_during_ads:
		AudioServer.set_bus_mute(0, true)


func _ad_end() -> void:
	if not _ad_active:
		return
	_ad_active = false
	if pause_game_during_ads:
		get_tree().paused = _ad_was_paused
	if mute_audio_during_ads:
		AudioServer.set_bus_mute(0, _ad_was_muted or (follow_portal_mute and bool(settings.get("muteAudio", false))))


## Applies settings.muteAudio to the Master bus (unless an ad holds it muted; then it is applied when the ad ends).
func _apply_portal_mute() -> void:
	if not follow_portal_mute:
		return
	var muted := bool(settings.get("muteAudio", false))
	if _ad_active:
		_ad_was_muted = muted
		return
	AudioServer.set_bus_mute(0, muted)


func has_adblock(callback: Callable) -> void:
	_call("ad.hasAdblock", {}, callback)


func has_adblock_async() -> Dictionary:
	return await _call_async("ad.hasAdblock", {})


# ---------------------------------------------------------------- Ad


# ---------------------------------------------------------------- Banner

## Static banner (728x90, 300x250, 320x50, 468x60 or 320x100) centred in window_rect (window pixels).
func request_banner(id: String, width: int, height: int, window_rect: Rect2, callback: Callable = Callable()) -> void:
	_call("banner.requestBanner", {"id": id, "width": width, "height": height, "rect": _norm_rect(window_rect)}, callback)

func request_banner_async(id: String, width: int, height: int, window_rect: Rect2) -> Dictionary:
	return await _call_async("banner.requestBanner", {"id": id, "width": width, "height": height, "rect": _norm_rect(window_rect)})

## Largest supported size that fits window_rect.
func request_responsive_banner(id: String, window_rect: Rect2, callback: Callable = Callable()) -> void:
	_call("banner.requestResponsiveBanner", {"id": id, "rect": _norm_rect(window_rect)}, callback)

func request_responsive_banner_async(id: String, window_rect: Rect2) -> Dictionary:
	return await _call_async("banner.requestResponsiveBanner", {"id": id, "rect": _norm_rect(window_rect)})

func clear_banner(id: String, callback: Callable = Callable()) -> void:
	_call("banner.clearBanner", {"id": id}, callback)

func clear_banner_async(id: String) -> Dictionary:
	return await _call_async("banner.clearBanner", {"id": id})

func clear_all_banners(callback: Callable = Callable()) -> void:
	_call("banner.clearAllBanners", {}, callback)

func clear_all_banners_async() -> Dictionary:
	return await _call_async("banner.clearAllBanners", {})

## Hides every banner without clearing it (SDK 1.8.0).
func hide_all_banners(callback: Callable = Callable()) -> void:
	_call("banner.hideAllBanners", {}, callback)

func hide_all_banners_async() -> Dictionary:
	return await _call_async("banner.hideAllBanners", {})

## Shows the banners hidden by hide_all_banners (SDK 1.8.0).
func show_all_banners(callback: Callable = Callable()) -> void:
	_call("banner.showAllBanners", {}, callback)

func show_all_banners_async() -> Dictionary:
	return await _call_async("banner.showAllBanners", {})


# ---------------------------------------------------------------- Game

func gameplay_start(callback: Callable = Callable()) -> void:
	_call("game.gameplayStart", {}, callback)

func gameplay_start_async() -> Dictionary:
	return await _call_async("game.gameplayStart", {})

func gameplay_stop(callback: Callable = Callable()) -> void:
	_call("game.gameplayStop", {}, callback)

func gameplay_stop_async() -> Dictionary:
	return await _call_async("game.gameplayStop", {})

func loading_start(callback: Callable = Callable()) -> void:
	_call("game.loadingStart", {}, callback)

func loading_start_async() -> Dictionary:
	return await _call_async("game.loadingStart", {})

func loading_stop(callback: Callable = Callable()) -> void:
	_call("game.loadingStop", {}, callback)

func loading_stop_async() -> Dictionary:
	return await _call_async("game.loadingStop", {})

## Optional in-game load progress, 0 to 100, between loading_start and loading_stop. Safe to call every frame.
func loading_progress(percentage: float, callback: Callable = Callable()) -> void:
	_call("game.loadingProgress", {"percentage": percentage}, callback)

func loading_progress_async(percentage: float) -> Dictionary:
	return await _call_async("game.loadingProgress", {"percentage": percentage})

func happytime(callback: Callable = Callable()) -> void:
	_call("game.happytime", {}, callback)

func happytime_async() -> Dictionary:
	return await _call_async("game.happytime", {})

func left_room(callback: Callable = Callable()) -> void:
	_call("game.leftRoom", {}, callback)

func left_room_async() -> Dictionary:
	return await _call_async("game.leftRoom", {})

## 0 to 100.
func report_game_completed_percentage(percentage: float, callback: Callable = Callable()) -> void:
	_call("game.reportGameCompletedPercentage", {"percentage": percentage}, callback)

func report_game_completed_percentage_async(percentage: float) -> Dictionary:
	return await _call_async("game.reportGameCompletedPercentage", {"percentage": percentage})

## Values must be String, int, float or bool.
func set_game_context(context: Dictionary, callback: Callable = Callable()) -> void:
	_call("game.setGameContext", {"context": context}, callback)

func set_game_context_async(context: Dictionary) -> Dictionary:
	return await _call_async("game.setGameContext", {"context": context})

func clear_game_context(callback: Callable = Callable()) -> void:
	_call("game.clearGameContext", {}, callback)

func clear_game_context_async() -> Dictionary:
	return await _call_async("game.clearGameContext", {})

## Keys: roomId (String), isJoinable (bool), isPublic (bool, SDK 1.6.0: friends can join; host only, ignored in kids mode),
## inviteParams (Dictionary of Strings).
func update_room(update: Dictionary, callback: Callable = Callable()) -> void:
	_call("game.updateRoom", {"update": update}, callback)

func update_room_async(update: Dictionary) -> Dictionary:
	return await _call_async("game.updateRoom", {"update": update})

## Result is the link String.
func invite_link(params: Dictionary, callback: Callable = Callable()) -> void:
	_call("game.inviteLink", {"params": params}, callback)

func invite_link_async(params: Dictionary) -> Dictionary:
	return await _call_async("game.inviteLink", {"params": params})

## Deprecated: use update_room({"isJoinable": true, "inviteParams": ...}). Result is the link String.
func show_invite_button(params: Dictionary, callback: Callable = Callable()) -> void:
	_call("game.showInviteButton", {"params": params}, callback)

func show_invite_button_async(params: Dictionary) -> Dictionary:
	return await _call_async("game.showInviteButton", {"params": params})

## Deprecated: use update_room({"isJoinable": false}).
func hide_invite_button(callback: Callable = Callable()) -> void:
	_call("game.hideInviteButton", {}, callback)

func hide_invite_button_async() -> Dictionary:
	return await _call_async("game.hideInviteButton", {})


# ---------------------------------------------------------------- User

## result is null when logged out.
func get_user(callback: Callable = Callable()) -> void:
	_call("user.getUser", {}, callback)

func get_user_async() -> Dictionary:
	return await _call_async("user.getUser", {})

## page is 1-based, size 1 to 50. Result: friends, page, size, hasMore, total.
func list_friends(page: int, size: int, callback: Callable = Callable()) -> void:
	_call("user.listFriends", {"page": page, "size": size}, callback)

func list_friends_async(page: int, size: int) -> Dictionary:
	return await _call_async("user.listFriends", {"page": page, "size": size})

## signing_key_type: "", "IN_GAME_AUTH" or "IN_GAME_AUTH_LEGACY".
func get_user_token(signing_key_type: String = "", callback: Callable = Callable()) -> void:
	_call("user.getUserToken", {"signingKeyType": signing_key_type}, callback)

func get_user_token_async(signing_key_type: String = "") -> Dictionary:
	return await _call_async("user.getUserToken", {"signingKeyType": signing_key_type})

## Token for the third-party payment provider configured for this game (userNotAuthenticated for guests).
## Deprecated: use store_get_purchase_token.
func get_xsolla_user_token(callback: Callable = Callable()) -> void:
	store_get_purchase_token(callback)

func get_xsolla_user_token_async() -> Dictionary:
	return await store_get_purchase_token_async()

func show_auth_prompt(callback: Callable = Callable()) -> void:
	_call("user.showAuthPrompt", {}, callback)

func show_auth_prompt_async() -> Dictionary:
	return await _call_async("user.showAuthPrompt", {})

## Result: {response: "yes" | "no"}.
func show_account_link_prompt(callback: Callable = Callable()) -> void:
	_call("user.showAccountLinkPrompt", {}, callback)

func show_account_link_prompt_async() -> Dictionary:
	return await _call_async("user.showAccountLinkPrompt", {})

func submit_score(encrypted_score: String, score: float, callback: Callable = Callable()) -> void:
	_call("user.submitScore", {"encryptedScore": encrypted_score, "score": score}, callback)

func submit_score_async(encrypted_score: String, score: float) -> Dictionary:
	return await _call_async("user.submitScore", {"encryptedScore": encrypted_score, "score": score})

## SDK 1.8.0. Result is the base64 payload String to pass to submit_score (userNotAuthenticated for guests, invalidArgument for a bad score or key).
## earned_at is the Unix time in ms that seals a delayed copy of the score; 0 means a live run.
func encrypt_score(score: float, key: String, callback: Callable = Callable(), earned_at: int = 0) -> void:
	_call("user.encryptScore", {"score": score, "key": key, "earnedAt": earned_at}, callback)

func encrypt_score_async(score: float, key: String, earned_at: int = 0) -> Dictionary:
	return await _call_async("user.encryptScore", {"score": score, "key": key, "earnedAt": earned_at})


# ---------------------------------------------------------------- Store
## In-game purchases. Check `is_store_available` before showing purchase UI and verify ownership on your server.
## Catalogue items: {sku, name, description, imageUrl, price: {amount, currency} or null, consumable}.
## Inventory items: {sku, name, description, imageUrl, quantity (null when not counted)}.

## Routes later store calls to the provider sandbox (test payments). Returns {"ok": ...}.
func store_set_sandbox(sandbox: bool) -> Dictionary:
	return _call_sync("store.setSandbox", {"sandbox": sandbox})

## limit 1..50, offset 0 or more. Result is an Array of catalogue items.
func store_get_catalog_items(callback: Callable = Callable(), limit: int = 50, offset: int = 0) -> void:
	_call("store.getCatalogItems", {"limit": limit, "offset": offset}, callback)

func store_get_catalog_items_async(limit: int = 50, offset: int = 0) -> Dictionary:
	return await _call_async("store.getCatalogItems", {"limit": limit, "offset": offset})

func store_get_player_inventory(callback: Callable = Callable(), limit: int = 50, offset: int = 0) -> void:
	_call("store.getPlayerInventory", {"limit": limit, "offset": offset}, callback)

func store_get_player_inventory_async(limit: int = 50, offset: int = 0) -> Dictionary:
	return await _call_async("store.getPlayerInventory", {"limit": limit, "offset": offset})

## Opens the portal checkout (one purchase at a time). Result is {"itemId": String} once paid.
func store_buy_item(item_id: String, callback: Callable = Callable()) -> void:
	var done := func(res: Dictionary) -> void:
		_emit_purchase(res)
		if callback.is_valid():
			callback.call(res)
	_call("store.buyItem", {"itemId": item_id}, done)

func store_buy_item_async(item_id: String) -> Dictionary:
	var res := await _call_async("store.buyItem", {"itemId": item_id})
	_emit_purchase(res)
	return res

func _emit_purchase(res: Dictionary) -> void:
	if res.get("ok", false):
		purchase_completed.emit(str(res.result.get("itemId", "")))
	else:
		purchase_failed.emit(res.get("error", {}))

## True when a result Dictionary failed with the given code: `ZokoGames.has_error_code(res, "purchaseCancelled")`.
func has_error_code(res: Dictionary, code: String) -> bool:
	return not res.get("ok", false) and res.get("error", {}).get("code", "") == code

## Signed token listing what the player owns, for your server to verify (userNotAuthenticated for guests). Result is the token String.
func store_get_purchase_token(callback: Callable = Callable()) -> void:
	_call("store.getPurchaseToken", {}, callback)

func store_get_purchase_token_async() -> Dictionary:
	return await _call_async("store.getPurchaseToken", {})

func store_consume_item(sku: String, quantity: int, callback: Callable = Callable()) -> void:
	_call("store.consumeItem", {"sku": sku, "quantity": quantity}, callback)

func store_consume_item_async(sku: String, quantity: int) -> Dictionary:
	return await _call_async("store.consumeItem", {"sku": sku, "quantity": quantity})


# ---------------------------------------------------------------- Achievements

## Result is an Array of achievement Dictionaries (key, name, description, iconUrl, points, hidden, unlocked, unlockedAt).
func achievements_list(callback: Callable = Callable()) -> void:
	_call("achievements.list", {}, callback)

func achievements_list_async() -> Dictionary:
	return await _call_async("achievements.list", {})

## key must match ^[a-z0-9_-]{1,40}$. Result is {"ok": true, "unlocked": bool, "achievement": {...}} or {"ok": false, "reason": "guest" | "not_found" | "not_live" | "rate_limited" | "error"}.
func achievements_unlock(key: String, callback: Callable = Callable()) -> void:
	_call("achievements.unlock", {"key": key}, callback)

func achievements_unlock_async(key: String) -> Dictionary:
	return await _call_async("achievements.unlock", {"key": key})


# ---------------------------------------------------------------- Room data channel (SDK 1.3.0)
## `game.room`: small JSON messages between the players of one room plus a host-written shared state. Game data, not text chat.
## The room exists after update_room(...) (or after joining from an invite) and ends with left_room(). Limits: 8 KB per message or
## patch, 20 messages per second, 64 KB of state, state keys of 1 to 40 characters of A-Z a-z 0-9 _ . : -
## Payloads are JSON (Dictionary, Array, String, int/float, bool, null); numbers come back as float. Events arrive as the room_* signals.

## Send any JSON value to every other member, or only to member `to` (an id from room_get_members()). Callback receives {"ok": ...}.
func room_send(data: Variant, to: String = "", callback: Callable = Callable()) -> void:
	_call("room.send", _room_send_args(data, to), callback)


func room_send_async(data: Variant, to: String = "") -> Dictionary:
	return await _call_async("room.send", _room_send_args(data, to))


## Send to one member only.
func room_send_to(member_id: String, data: Variant, callback: Callable = Callable()) -> void:
	_call("room.send", _room_send_args(data, member_id), callback)


func _room_send_args(data: Variant, to: String) -> Dictionary:
	var args := {"data": data}
	if to != "":
		args["to"] = to
	return args


## Host only. Merge `patch` into the shared state; a null value removes the key. It applies once the platform confirms it:
## read it from the room_state signal or room_get_state(), not straight after this call.
func room_set_state(patch: Dictionary, callback: Callable = Callable()) -> void:
	_call("room.setState", {"patch": patch}, callback)


func room_set_state_async(patch: Dictionary) -> Dictionary:
	return await _call_async("room.setState", {"patch": patch})


## Copy of the shared state (empty when not in a room).
func room_get_state() -> Dictionary:
	var r := _call_sync("room.getState", {})
	if r.ok and typeof(r.get("result")) == TYPE_DICTIONARY:
		return r.result
	return {}


## One value of the shared state, or `default` when the key is not set.
func room_get_state_value(key: String, default: Variant = null) -> Variant:
	return room_get_state().get(key, default)


## Players in the room including this one: Array of {"id", "username", "profilePictureUrl"}. Empty when not in a room.
func room_get_members() -> Array:
	var r := _call_sync("room.members", {})
	if r.ok and typeof(r.get("result")) == TYPE_ARRAY:
		return r.result
	return []


## True when this player is the room host (the first member).
func room_is_host() -> bool:
	var r := _call_sync("room.isHost", {})
	return r.ok and bool(r.get("result", false))


## Platform id of this player, or "" when not in a room.
func room_self_id() -> String:
	var r := _call_sync("room.selfId", {})
	if r.ok and r.get("result") != null:
		return str(r.result)
	return ""


# ---------------------------------------------------------------- Chat reports and screenshots (SDK 1.4.0)

## Report one chat message to the portal's moderators (JS: game.reportChat). Keys of `report`: reportedName (String, 1 to 40 characters),
## message (String, 1 to 500), reason ("abuse", "spam", "cheating" or "other"), and optionally reportedUserId (String), roomId (String, at most 64)
## and context (Array of {"name", "text"}, oldest first, the newest 10 are kept). Fails with invalidArgument, rateLimited or unexpectedError.
func report_chat(report: Dictionary, callback: Callable = Callable()) -> void:
	_call("game.reportChat", {"report": report}, callback)

func report_chat_async(report: Dictionary) -> Dictionary:
	return await _call_async("game.reportChat", {"report": report})

## Supply the picture the portal's feedback form attaches (JS: game.onScreenshotRequest). `provider` takes no arguments and returns an Image
## (or a Texture2D, or null for "no picture"); it runs right after a frame was drawn. The addon scales the image to SCREENSHOT_MAX_EDGE,
## encodes it as JPG and answers within the SDK's 3 second limit. Without a provider (or with an empty Callable) the addon sends the root
## viewport: get_viewport().get_texture().get_image(). It is registered automatically after init().
func set_screenshot_provider(provider: Callable = Callable()) -> void:
	_screenshot_provider = provider
	_screenshot_provider_off = false
	_register_screenshot_provider()

## Stop answering from Godot. The JS SDK then falls back to its own canvas capture, which can be blank on WebGL; prefer the default.
func clear_screenshot_provider() -> void:
	_screenshot_provider = Callable()
	_screenshot_provider_off = true
	if _screenshot_registered:
		_screenshot_registered = false
		_call_sync("game.setScreenshotProvider", {"enabled": false})

## Capture a picture now, the way an answer to the portal is made, and call `callback` with a "data:image/jpeg;base64,..." String
## ("" when nothing could be captured). Works in the editor too, so a provider can be tested without the portal.
func capture_screenshot(callback: Callable) -> void:
	await RenderingServer.frame_post_draw
	var url := _screenshot_url_now()
	if callback.is_valid():
		callback.call(url)

func _register_screenshot_provider() -> void:
	if _screenshot_provider_off or not is_available():
		return
	_screenshot_registered = bool(_call_sync("game.setScreenshotProvider", {"enabled": true}).get("ok", false))

func _answer_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var url := _screenshot_url_now()
	var data_url: Variant = null  # null tells the SDK "no picture"
	if url != "":
		data_url = url
	_call_sync("game.answerScreenshot", {"dataUrl": data_url})

func _screenshot_url_now() -> String:
	var img: Image = null
	if _screenshot_provider.is_valid():
		var got: Variant = _screenshot_provider.call()
		if got is Image:
			img = got
		elif got is Texture2D:
			img = got.get_image()
		elif typeof(got) == TYPE_STRING and str(got).begins_with("data:image/"):
			return str(got)  # the provider already encoded the picture (the README allows a data URL)
	else:
		img = get_viewport().get_texture().get_image()
	if img == null or img.get_width() < 1 or img.get_height() < 1:
		return ""
	var work := img.duplicate() as Image  # never change the game's own image
	if work.is_compressed():
		work.decompress()
	var longest := maxi(work.get_width(), work.get_height())
	if longest > SCREENSHOT_MAX_EDGE:
		var k := float(SCREENSHOT_MAX_EDGE) / float(longest)
		work.resize(maxi(1, roundi(work.get_width() * k)), maxi(1, roundi(work.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	if work.get_format() != Image.FORMAT_RGB8:
		work.convert(Image.FORMAT_RGB8)
	var bytes := work.save_jpg_to_buffer(SCREENSHOT_JPG_QUALITY)
	if bytes.size() == 0:
		return ""
	return "data:image/jpeg;base64," + Marshalls.raw_to_base64(bytes)


# ---------------------------------------------------------------- Analytics

## order is any JSON-serialisable value.
func track_order(provider: String, order: Variant, callback: Callable = Callable()) -> void:
	_call("analytics.trackOrder", {"provider": provider, "order": order}, callback)

func track_order_async(provider: String, order: Variant) -> Dictionary:
	return await _call_async("analytics.trackOrder", {"provider": provider, "order": order})

## SDK 1.7.0. name matches ^[a-z][a-z0-9_]{0,39}$; params is a flat Dictionary of String, int, float or bool values (max 10).
func track(event_name: String, params: Dictionary = {}, callback: Callable = Callable()) -> void:
	_call("analytics.track", _track_args(event_name, params), callback)

func track_async(event_name: String, params: Dictionary = {}) -> Dictionary:
	return await _call_async("analytics.track", _track_args(event_name, params))

func _track_args(event_name: String, params: Dictionary) -> Dictionary:
	var a := {"name": event_name}
	if not params.is_empty():
		a["params"] = params
	return a

# ---------------------------------------------------------------- synchronous accessors

## One invite parameter, or null.
func get_invite_param(key: String) -> Variant:
	var r := _call_sync("game.getInviteParam", {"key": key})
	return r.get("result") if r.ok else null


# ---------------------------------------------------------------- Data (cloud save, synchronous)
## Reads come from a preloaded copy and writes upload in the background (1 MiB total).
## All values are Strings, like localStorage.

func data_get_item(key: String, default: Variant = null) -> Variant:
	var r := _call_sync("data.getItem", {"key": key})
	if r.ok and r.get("result") != null:
		return r.result
	return default


func data_has_key(key: String) -> bool:
	return data_get_item(key) != null


## Returns an error Dictionary-shaped result: {"ok": true} or {"ok": false, "error": {...}} (e.g. dataLimitExceeded).
func data_set_item(key: String, value: String) -> Dictionary:
	return _call_sync("data.setItem", {"key": key, "value": value})


func data_remove_item(key: String) -> Dictionary:
	return _call_sync("data.removeItem", {"key": key})


func data_clear() -> Dictionary:
	return _call_sync("data.clear", {})

## Copy the browser page's localStorage writes into the cloud save and restore newer cloud values into it (JS: data.mirrorLocalStorage).
## Only for JavaScript-side storage (a custom HTML shell or a script that calls localStorage.setItem). Godot's own files under user://
## are kept in the browser's IndexedDB, not in localStorage, so this mirror never sees them: save those with data_set_item instead.
## `options`, all optional: keys (Array of String, exact names), prefix (String), pattern (String, a JavaScript regular expression source).
## Call it right after init(). Returns {"ok": true} or {"ok": false, "error": {...}}. Failures later arrive as the mirror_error signal.
func mirror_local_storage(options: Dictionary = {}) -> Dictionary:
	return _call_sync("data.mirrorLocalStorage", {"keys": options.get("keys", []), "prefix": str(options.get("prefix", "")), "pattern": str(options.get("pattern", ""))})


## Stop mirroring (JS: the function mirrorLocalStorage returns).
func stop_mirror_local_storage() -> Dictionary:
	return _call_sync("data.stopMirrorLocalStorage", {})


## The game id the portal sent at init (JS: game.gameId). Empty before init.
func get_game_id() -> String:
	return game_id


## Stop the IndexedDB mirror started by the HTML shell option ZOKO_MIRROR_INDEXEDDB (JS: the stop function of data.mirrorIndexedDB).
func stop_mirror_indexed_db() -> Dictionary:
	return _call_sync("data.stopMirrorIndexedDB", {})



# ---------------------------------------------------------------- simulator

func _sim_setting(key: String, default: Variant) -> Variant:
	return ProjectSettings.get_setting("zokogames/simulator/" + key, default)


func _sim_log(text: String) -> void:
	if _sim_setting("verbose", true):
		print("[ZokoGames simulator] ", text)


func _sim_load() -> void:
	_sim_logged_in = bool(_sim_setting("logged_in", true)) and bool(_sim_setting("account_available", true))
	if FileAccess.file_exists(SIM_SAVE_PATH):
		var f := FileAccess.open(SIM_SAVE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_sim_data = parsed


func _sim_persist() -> void:
	var f := FileAccess.open(SIM_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_sim_data))


func _sim_user() -> Dictionary:
	return {"username": _sim_setting("username", "SimPlayer"), "profilePictureUrl": "", "__dangerousUserId": _sim_setting("user_id", "sim-user-1")}


func _sim_settings() -> Dictionary:
	var kids = bool(_sim_setting("kids_mode", false))
	return {"disableChat": kids or bool(_sim_setting("disable_chat", false)), "kidsMode": kids, "muteAudio": bool(_sim_setting("mute_audio", false))}


func _sim_ok(id: int, value: Variant = null) -> void:
	_finish(id, {"ok": true, "result": value})


func _sim_err(id: int, code: String, message: String) -> void:
	_finish(id, _fail(code, message))


## The limits the JS SDK enforces on game.reportChat; returns the problem, or "" when the report is fine.
func _sim_chat_report_problem(report: Variant) -> String:
	if typeof(report) != TYPE_DICTIONARY:
		return "report must be an object"
	var rname := str(report.get("reportedName", ""))
	if rname.length() < 1 or rname.length() > 40:
		return "reportedName must be 1 to 40 characters"
	var text := str(report.get("message", ""))
	if text.length() < 1 or text.length() > 500:
		return "message must be 1 to 500 characters"
	if not ["abuse", "spam", "cheating", "other"].has(str(report.get("reason", ""))):
		return "reason must be one of abuse, spam, cheating, other"
	if report.has("roomId") and (str(report.roomId).length() < 1 or str(report.roomId).length() > 64):
		return "roomId must be 1 to 64 characters"
	return ""


func _sim_sync(method: String, args: Dictionary) -> Dictionary:
	match method:
		"game.getSettings":
			return {"ok": true, "result": _sim_settings()}
		"game.getInviteParams":
			return {"ok": true, "result": invite_params}
		"game.getInviteParam":
			return {"ok": true, "result": invite_params.get(str(args.get("key", "")))}
		"data.getItem":
			return {"ok": true, "result": _sim_data.get(str(args.get("key", "")))}
		"data.setItem":
			var next := _sim_data.duplicate()
			next[str(args.get("key", ""))] = str(args.get("value", ""))
			if JSON.stringify(next).to_utf8_buffer().size() > DATA_LIMIT_BYTES:
				return _fail("dataLimitExceeded", "Saved data would exceed %d bytes" % DATA_LIMIT_BYTES)
			_sim_data = next
			_sim_persist()
			return {"ok": true, "result": null}
		"data.removeItem":
			if _sim_data.erase(str(args.get("key", ""))):
				_sim_persist()
			return {"ok": true, "result": null}
		"data.clear":
			_sim_data.clear()
			_sim_persist()
			return {"ok": true, "result": null}
		"game.setScreenshotProvider":
			_sim_log("game.setScreenshotProvider enabled=" + str(args.get("enabled", true)))
			return {"ok": true, "result": null}
		"game.answerScreenshot":
			_sim_log("game.answerScreenshot " + ("(picture)" if typeof(args.get("dataUrl")) == TYPE_STRING else "(none)"))
			return {"ok": true, "result": null}
		"data.mirrorLocalStorage":
			_sim_log("data.mirrorLocalStorage ignored (no browser localStorage in the editor or on desktop)")
			return {"ok": true, "result": null}
		"data.stopMirrorLocalStorage":
			return {"ok": true, "result": null}
		"data.stopMirrorIndexedDB":
			return {"ok": true, "result": null}
		"room.selfId":
			return {"ok": true, "result": SIM_ROOM_SELF_ID}
		"room.isHost":
			return {"ok": true, "result": true}
		"room.members":
			return {"ok": true, "result": [{"id": SIM_ROOM_SELF_ID, "username": _sim_setting("username", "SimPlayer"), "profilePictureUrl": ""}]}
		"room.getState":
			return {"ok": true, "result": _sim_room_state.duplicate(true)}
		"store.isAvailable":
			return {"ok": true, "result": bool(_sim_setting("store_available", true))}
		"store.setSandbox":
			# The JS SDK only stores the flag (it does not check store availability).
			return {"ok": true, "result": null}
	return _fail("unknownMethod", "Unknown sync method " + method)


const _SIM_CATALOG := [
	{"sku": "sim_coins_100", "name": "100 Coins", "description": "A small pile of coins", "consumable": true},
	{"sku": "sim_coins_500", "name": "500 Coins", "description": "A big pile of coins", "consumable": true},
	{"sku": "sim_no_ads", "name": "Remove Ads", "description": "One-time purchase", "consumable": false},
]
const _SIM_INVENTORY_PATH := "user://zoko_sim_inventory.json"


func _sim_inventory() -> Dictionary:
	if FileAccess.file_exists(_SIM_INVENTORY_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_SIM_INVENTORY_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


func _sim_save_inventory(inv: Dictionary) -> void:
	var f := FileAccess.open(_SIM_INVENTORY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(inv))


func _sim_store(method: String, args: Dictionary) -> Dictionary:
	if not bool(_sim_setting("store_available", true)):
		return _fail("other", "The store is not available")
	var limit := int(args.get("limit", 50))
	var offset := int(args.get("offset", 0))
	if limit < 1 or limit > 50:
		return _fail("invalidArgument", "limit must be an integer between 1 and 50")
	if offset < 0:
		return _fail("invalidArgument", "offset must be an integer >= 0")
	var inv := _sim_inventory()
	match method:
		"store.getCatalogItems":
			var out := []
			for i in range(offset, mini(offset + limit, _SIM_CATALOG.size())):
				var c: Dictionary = _SIM_CATALOG[i]
				out.append({"sku": c.sku, "name": c.name, "description": c.description, "imageUrl": "",
					"price": {"amount": 0.99 + i, "currency": "USD"}, "consumable": c.consumable})
			return {"ok": true, "result": out}
		"store.getPlayerInventory":
			var owned := []
			for c in _SIM_CATALOG:
				if inv.has(c.sku):
					owned.append({"sku": c.sku, "name": c.name, "description": c.description, "imageUrl": "", "quantity": int(inv[c.sku])})
			return {"ok": true, "result": owned.slice(offset, offset + limit)}
		"store.buyItem":
			var item_id := str(args.get("itemId", ""))
			if item_id == "":
				return _fail("invalidArgument", "itemId must be a non-empty string")
			for c in _SIM_CATALOG:
				if c.sku == item_id:
					inv[item_id] = int(inv.get(item_id, 0)) + 1
					_sim_save_inventory(inv)
					_sim_log("simulated purchase of " + item_id)
					return {"ok": true, "result": {"itemId": item_id}}
			return _fail("purchaseInitFailed", "No catalogue item " + item_id)
	var sku := str(args.get("sku", ""))
	var qty := int(args.get("quantity", 0))
	if sku == "":
		return _fail("invalidArgument", "sku must be a non-empty string")
	if qty < 1:
		return _fail("invalidArgument", "quantity must be an integer >= 1")
	if int(inv.get(sku, 0)) < qty:
		return _fail("insufficientItemQuantity", "Not enough of " + sku)
	var left := int(inv[sku]) - qty
	if left <= 0:
		inv.erase(sku)
	else:
		inv[sku] = left
	_sim_save_inventory(inv)
	return {"ok": true, "result": null}


func _sim(id: int, method: String, args: Dictionary) -> void:
	await get_tree().process_frame  # always answer asynchronously, like the browser
	if method == "init":
		if bool(_sim_setting("disabled", false)):
			_sim_ok(id, {"environment": "disabled", "isQaTool": false, "settings": _sim_settings(), "systemInfo": null,
				"isUserAccountAvailable": false, "isInstantMultiplayer": false, "isOffline": false, "inviteParams": null, "storeAvailable": false, "gameId": ""})
			return
		_sim_log("init (environment local)")
		_sim_ok(id, {
			"environment": "local", "isQaTool": false, "settings": _sim_settings(),
			"systemInfo": {
				"countryCode": "US", "locale": OS.get_locale(), "device": {"type": "desktop"},
				"os": {"name": OS.get_name(), "version": OS.get_version()},
				"browser": {"name": "Godot", "version": Engine.get_version_info().string},
				"applicationType": "web",
			},
			"isUserAccountAvailable": bool(_sim_setting("account_available", true)),
			"isInstantMultiplayer": false, "isOffline": bool(_sim_setting("offline", false)), "inviteParams": null,
			"storeAvailable": bool(_sim_setting("store_available", true)), "gameId": "simulated-game",
		})
		return
	if bool(_sim_setting("disabled", false)):
		_sim_err(id, "sdkDisabled", "The SDK is disabled in this environment")
		return
	match method:
		"ad.requestAd":
			var type := str(args.get("type", ""))
			if type != "midgame" and type != "rewarded":
				_sim_err(id, "invalidArgument", "ad type must be \"midgame\" or \"rewarded\"")
				return
			var behaviour := str(_sim_setting("ad_behaviour", "fill"))
			if _sim_ad_playing:
				_emit_event(id, "adError", {"code": "other", "message": "Another ad request is already in progress"})
				_sim_ok(id)
				return
			if behaviour == "no_fill":
				_emit_event(id, "adError", {"code": "unfilled", "message": "No ad was available"})
				_sim_ok(id)
				return
			_sim_ad_playing = true
			_emit_event(id, "adStarted", null)
			_sim_log("ad started (%s)" % type)
			await get_tree().create_timer(float(_sim_setting("ad_duration_seconds", 1.5))).timeout
			_sim_ad_playing = false
			if behaviour == "error":
				_emit_event(id, "adError", {"code": "other", "message": "Simulated ad error"})
			else:
				_emit_event(id, "adFinished", null)
			_sim_ok(id)
		"ad.hasAdblock":
			_sim_ok(id, bool(_sim_setting("adblock", false)))
		"banner.requestBanner", "banner.requestResponsiveBanner":
			var bid := str(args.get("id", ""))
			if bid == "":
				_sim_err(id, "missingId", "A container id is required")
			elif _sim_ad_playing:
				_sim_err(id, "videoAdPlaying", "A video ad is playing")
			elif method == "banner.requestBanner" and not STATIC_BANNER_SIZES.has("%dx%d" % [int(args.get("width", 0)), int(args.get("height", 0))]):
				_sim_err(id, "invalidSize", "%dx%d is not a supported banner size" % [int(args.get("width", 0)), int(args.get("height", 0))])
			elif _sim_banner_at.has(bid) and Time.get_ticks_msec() - int(_sim_banner_at[bid]) < 30000:
				_sim_err(id, "bannerCooldown", "Banners can refresh at most every 30 seconds")
			else:
				_sim_banner_at[bid] = Time.get_ticks_msec()
				_sim_log("banner shown: " + bid)
				_sim_ok(id)
		"banner.clearBanner":
			_sim_banner_at.erase(str(args.get("id", "")))
			_sim_ok(id)
		"banner.clearAllBanners":
			_sim_banner_at.clear()
			_sim_ok(id)
		"banner.hideAllBanners", "banner.showAllBanners":
			_sim_log(method)
			_sim_ok(id)
		"game.gameplayStart", "game.gameplayStop", "game.loadingStart", "game.loadingStop", "game.hideInviteButton", "game.happytime", "game.leftRoom", "game.clearGameContext":
			_sim_log(method)
			_sim_ok(id)
		"game.loadingProgress", "game.reportGameCompletedPercentage":
			var p: Variant = args.get("percentage")
			if (typeof(p) != TYPE_FLOAT and typeof(p) != TYPE_INT) or p < 0 or p > 100:
				_sim_err(id, "invalidArgument", "percentage must be a number between 0 and 100")
			else:
				_sim_ok(id)
		"game.setGameContext":
			if typeof(args.get("context")) == TYPE_DICTIONARY:
				_sim_ok(id)
			else:
				_sim_err(id, "invalidArgument", "context must be an object of string, number or boolean values")
		"game.reportChat":
			var problem := _sim_chat_report_problem(args.get("report"))
			if problem == "":
				_sim_log("game.reportChat " + JSON.stringify(args.get("report")))
				_sim_ok(id)
			else:
				_sim_err(id, "invalidArgument", problem)
		"game.updateRoom":
			if typeof(args.get("update")) == TYPE_DICTIONARY:
				_sim_ok(id)
			else:
				_sim_err(id, "invalidArgument", "update must be an object")
		"game.inviteLink", "game.showInviteButton":
			var parts: Array[String] = []
			var ip: Dictionary = args.get("params", {})
			for k in ip:
				parts.append("%s=%s" % [str(k).uri_encode(), str(ip[k]).uri_encode()])
			_sim_ok(id, "https://zokogames.com/play/simulated" + ("?" + "&".join(parts) if parts.size() > 0 else ""))
		"user.getUser":
			if _sim_logged_in:
				_sim_ok(id, _sim_user())
			else:
				_sim_ok(id, null)
		"user.listFriends":
			var page := int(args.get("page", 0))
			var size := int(args.get("size", 0))
			var total := int(_sim_setting("friend_count", 12))
			if page < 1:
				_sim_err(id, "invalidArgument", "page must be an integer >= 1")
			elif size < 1 or size > 50:
				_sim_err(id, "invalidArgument", "size must be an integer between 1 and 50")
			else:
				var friends := []
				var start := (page - 1) * size
				for i in range(start, mini(start + size, total)):
					friends.append({"id": "sim-friend-%d" % (i + 1), "username": "Friend %d" % (i + 1), "profilePictureUrl": ""})
				_sim_ok(id, {"friends": friends, "page": page, "size": size, "hasMore": start + size < total, "total": total})
		"user.getUserToken":
			if not _sim_logged_in:
				_sim_err(id, "userNotAuthenticated", "No user is signed in")
			else:
				_sim_ok(id, "simulated.%s.unsigned" % Marshalls.utf8_to_base64(str(_sim_setting("user_id", "sim-user-1"))))
		"store.getPurchaseToken", "user.getXsollaUserToken":
			if not _sim_logged_in:
				_sim_err(id, "userNotAuthenticated", "No user is signed in")
			else:
				_sim_ok(id, "simulated-purchase.%s" % Marshalls.utf8_to_base64(str(_sim_setting("user_id", "sim-user-1"))))
		"user.showAuthPrompt":
			if _sim_auth_open:
				_sim_err(id, "showAuthPromptInProgress", "The auth prompt is already open")
			elif _sim_logged_in:
				_sim_err(id, "userAlreadySignedIn", "A user is already signed in")
			else:
				_sim_auth_open = true
				await get_tree().create_timer(0.4).timeout
				_sim_auth_open = false
				_sim_logged_in = true
				_on_global("auth", _sim_user())
				_sim_ok(id, _sim_user())
		"user.showAccountLinkPrompt":
			_sim_ok(id, {"response": "yes" if _sim_logged_in else "no"})
		"user.encryptScore":
			var es: Variant = args.get("score")
			if not _sim_logged_in:
				_sim_err(id, "userNotAuthenticated", "No user is signed in")
			elif (typeof(es) != TYPE_FLOAT and typeof(es) != TYPE_INT) or is_nan(float(es)) or is_inf(float(es)):
				_sim_err(id, "invalidArgument", "score must be a finite number")
			elif typeof(args.get("key")) != TYPE_STRING or str(args.get("key")) == "":
				_sim_err(id, "invalidArgument", "key must be a non-empty string")
			else:
				var es_at := int(args.get("earnedAt", 0))
				if es_at <= 0:
					es_at = int(Time.get_unix_time_from_system() * 1000.0)
				_sim_ok(id, "simulated-score." + Marshalls.utf8_to_base64("%s|%d" % [str(es), es_at]))
		"user.submitScore":
			# Like the JS SDK: encryptedScore must be a String (an empty one is accepted for boards without an encryption key)
			# and score a finite number.
			var sc: Variant = args.get("score")
			if typeof(args.get("encryptedScore")) != TYPE_STRING or (typeof(sc) != TYPE_FLOAT and typeof(sc) != TYPE_INT) or is_nan(float(sc)) or is_inf(float(sc)):
				_sim_err(id, "invalidArgument", "submitScore needs { encryptedScore: string, score: number }")
			else:
				_sim_ok(id)
		"store.getCatalogItems", "store.getPlayerInventory", "store.buyItem", "store.consumeItem":
			_finish(id, _sim_store(method, args))
		"achievements.list":
			_sim_ok(id, _sim_achievements.values())
		"achievements.unlock":
			var ach_key := str(args.get("key", ""))
			var ach_re := RegEx.create_from_string("^[a-z0-9_-]{1,40}$")
			if typeof(args.get("key")) != TYPE_STRING or ach_re.search(ach_key) == null:
				_sim_err(id, "invalidArgument", "key must match ^[a-z0-9_-]{1,40}$")
			elif not _sim_logged_in:
				_sim_ok(id, {"ok": false, "reason": "guest"})
			elif _sim_achievements.has(ach_key):
				_sim_ok(id, {"ok": true, "unlocked": false, "achievement": _sim_achievements[ach_key]})
			else:
				var ach := {"key": ach_key, "name": ach_key, "description": "", "iconUrl": null, "points": 0, "hidden": false, "unlocked": true, "unlockedAt": Time.get_datetime_string_from_system(true) + "Z"}
				_sim_achievements[ach_key] = ach
				_on_global("achievementUnlocked", ach)
				_sim_ok(id, {"ok": true, "unlocked": true, "achievement": ach})
		"room.send":
			var room_bytes := JSON.stringify(args.get("data")).to_utf8_buffer().size()
			var room_to: Variant = args.get("to")
			if room_bytes > ROOM_MAX_PAYLOAD_BYTES:
				_sim_err(id, "payloadTooLarge", "data is %d bytes; the limit is %d" % [room_bytes, ROOM_MAX_PAYLOAD_BYTES])
			elif room_to != null and (typeof(room_to) != TYPE_STRING or str(room_to) == ""):
				_sim_err(id, "invalidArgument", "to must be a member id")
			elif room_to != null and str(room_to) != SIM_ROOM_SELF_ID:
				_sim_err(id, "unknownMember", "No member %s in the simulated room" % str(room_to))
			else:
				_sim_ok(id)
				# Loop back locally (a real portal never echoes your own messages).
				_sim_room_seq += 1
				_on_global("roomMessage", {
					"data": args.get("data"), "direct": room_to != null, "from": SIM_ROOM_SELF_ID,
					"seq": _sim_room_seq, "ts": int(Time.get_unix_time_from_system() * 1000.0),
				})
		"room.setState":
			var room_patch: Variant = args.get("patch")
			var key_re := RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,40}$")
			var bad_key := false
			if typeof(room_patch) == TYPE_DICTIONARY:
				for pk in room_patch:
					if key_re.search(str(pk)) == null:
						bad_key = true
			if typeof(room_patch) != TYPE_DICTIONARY or room_patch.is_empty() or bad_key:
				_sim_err(id, "invalidArgument", "patch needs at least one key; keys are 1-40 characters of A-Z a-z 0-9 _ . : -")
			elif JSON.stringify(room_patch).to_utf8_buffer().size() > ROOM_MAX_PAYLOAD_BYTES:
				_sim_err(id, "payloadTooLarge", "patch is larger than %d bytes" % ROOM_MAX_PAYLOAD_BYTES)
			else:
				var room_next := _sim_room_state.duplicate(true)
				var room_keys: Array = []
				for pk in room_patch:
					room_keys.append(str(pk))
					if room_patch[pk] == null:
						room_next.erase(str(pk))
					else:
						room_next[str(pk)] = room_patch[pk]
				if JSON.stringify(room_next).to_utf8_buffer().size() > ROOM_MAX_STATE_BYTES:
					_sim_err(id, "stateTooLarge", "The shared state would exceed %d bytes" % ROOM_MAX_STATE_BYTES)
				else:
					_sim_room_state = room_next
					_sim_room_rev += 1
					_sim_ok(id)
					_on_global("roomState", {
						"state": _sim_room_state.duplicate(true),
						"change": {"by": SIM_ROOM_SELF_ID, "keys": room_keys, "rev": _sim_room_rev},
					})
		"analytics.track":
			var track_name := str(args.get("name", ""))
			var track_params: Variant = args.get("params", {})
			var track_ok := track_name.length() > 0 and track_name.length() <= 40 and track_name[0] >= "a" and track_name[0] <= "z"
			for ch in track_name:
				if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
					track_ok = false
			if not track_ok:
				_sim_err(id, "invalidArgument", "name must match ^[a-z][a-z0-9_]{0,39}$")
			elif typeof(track_params) != TYPE_DICTIONARY or track_params.size() > 10:
				_sim_err(id, "invalidArgument", "params must be a flat object with at most 10 keys")
			else:
				_sim_ok(id)
		"analytics.trackOrder":
			if str(args.get("provider", "")) == "":
				_sim_err(id, "invalidArgument", "provider must be a non-empty string")
			else:
				_sim_ok(id)
		_:
			var r := _sim_sync(method, args)
			_finish(id, r)
