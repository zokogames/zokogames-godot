# Changelog

## 1.7.0 (2026-11-23)

- Matches the JavaScript SDK 1.7.0 (additive). New signal `room_left(reason: String, room_id: String)` for `game.room.addLeftListener` (`reason` is `left`, `kicked`, `closed` or `disconnected`).
- New `track(name, params, cb)` / `track_async(name, params)` for `analytics.track` (fire-and-forget; the simulator validates the name and the params).
- The plugin now targets SDK 1.7.0; the wrapper constant `ZokoGames.VERSION` now reads `"1.7.0"`.
- `data.mirrorIndexedDB` is not bound yet: it must run in the page before the engine boots. `game.gameId` is still not bound.

## 1.6.4 of the JavaScript SDK (source only, 2026-11-23)

- No plugin change: targets SDK 1.6.4 (delayed scores are not wrapped). The only SDK change a plugin can notice: in local mode the mock now refuses a midgame ad with `adCooldown` until the game has called gameplay start (or 30 seconds of visible page time have passed), so call `gameplayStart` when play begins, before the first midgame ad. The wrapper constant that reports the SDK version now reads `"1.6.4"` in this source; the published zips keep reporting the version they were built with until the next plugin release. Nothing to do for games already built with the plugin.

## 1.6.3 of the JavaScript SDK (source only, 2026-11-22)

- Targets the JavaScript SDK 1.6.3 (messages and console warnings only, plus one fix: `ad.requestAd` resolves when the callbacks object cannot be read; no wrapper API change and no wrapper change is needed). The wrapper constant that reports the SDK version now reads `"1.6.3"` in this source; the published zips keep reporting the version they were built with until the next plugin release. Nothing to do for games already built with the plugin.

## Unreleased

- Targets the JavaScript SDK 1.6.2 (additive: one-time console notices, reserved host labels at any depth, read-only `SDK.game.gameId`, which the wrapper does not expose yet; no wrapper change is needed). The wrapper constant that reports the SDK version now reads `"1.6.2"` in this source; the published zips report `"1.6.1"` until the next plugin release. Nothing to do for games already built with this plugin.

## 1.6.2 (2026-11-21)

- Targets the JavaScript SDK 1.6.1 (a security hardening of the SDK itself: init is answered only by portal pages, a local page counts only for a local game; no wrapper API change). The constant that reports the SDK release now reads `"1.6.1"` (`ZokoGames.VERSION`). Nothing to do for games already built with this plugin.
- The shared bridge core (`export/zokogames_shell.html`) validates like the SDK: store page `limit` / `offset` reach the SDK unchanged (an invalid one is now `invalidArgument` instead of the default page), the user-token call passes the key type on (`""` keeps the default), a room send target must be a member id, a room state change refuses a `remove` that is not a list of keys and a `patch` that is not an object, and the store sandbox flag must be a boolean (the wrapper converts its own argument).
- Fix: a second ad request while an ad plays is refused by the SDK with an ad error ("Another ad request is already in progress"). That refused request released the wrapper's pause and Master mute, so the game resumed and was heard under the ad still on screen. Only the request whose ad started releases it now; the refused request still reports its error.
- Simulator fixes found by checking every wrapper against the SDK source:
- Fix: the simulator rejected `submit_score("", score)`; the SDK accepts an empty `encrypted_score` (boards without an encryption key) and only requires a String and a finite number. The simulator now applies the same rule.
- Fix: in the simulator `store_set_sandbox()` failed when `store_available` was off; the SDK only stores the flag, so it now always returns `{"ok": true}`.

## 1.6.1 (2026-11-20)

- Still targets the JavaScript SDK 1.6.0 (`ZokoGames.VERSION` stays `"1.6.0"`); this release fixes plugin code only. Run headless in the official Godot 4.3 and 4.7.2 editors (import, plugin enable, every public method in simulator mode, Web export).
- Fix: typed `for` loop variables (`for key: String in ...`) are a parse error before Godot 4.2; the three loops in `plugin.gd` and `zokogames.gd` are untyped now, so the addon loads in 4.0 and 4.1 again.
- Fix: the `ZokoGames` autoload was removed from `project.godot` whenever the editor closed (`_exit_tree`). It is now added in `_enable_plugin` and removed in `_disable_plugin`; `_enter_tree` re-adds it when missing, which repairs projects set up by 1.6.0 and older.
- Fix: a null `joinRoom` or `auth` payload no longer raises a runtime error (falls back to an empty Dictionary).
- Fix: a screenshot provider that returns a `data:image/` URL is passed through, as the README states.
- Fix: `zokogames.gd` raised GDScript warnings in a real editor (parameters `name` shadowing `Node.name`, `invite_params` shadowing the member of the same name, and two ternaries mixing a Dictionary or String with `null`). With warnings as errors, or with addon warnings switched on, the autoload failed to compile. The parameters are renamed (`event_name`, `key`, `params`; call sites are unchanged) and the ternaries are plain `if`s.
- Fix: `examples/zoko_demo.gd` had an unused lambda parameter (warning) and its `auth_changed` handler read `u.username`, which fails for a signed-out player (`{}`); it uses `u.get("username", ...)` now.
- Docs: builds that run on the portal need Godot 4.3 or newer with Thread Support off (4.0 to 4.2 web exports always use `SharedArrayBuffer`).

## 1.6.0 (2026-11-19)

- Matches the JavaScript SDK 1.6.0 (additive): `update_room` passes `isPublic` (bool) through like every other key (doc comment only, no code change).

## 1.5.0 (2026-11-19)

- Matches the JavaScript SDK 1.5.0 (additive): `game.settings` carries `kidsMode` (true when the game runs in kids mode: no chat, rooms, sign-in prompts or personalised ads). A portal that predates it does not send the field; keep honouring `disableChat`. The simulator/editor mock reports `kidsMode: false` unless kids mode is switched on, and then also turns chat off, like the portal. The SDK's new `LeaderboardEntry` type (leaderboard rows: `isYou`, opaque per-game `userId`) is type only and has no wrapper binding, as the SDK has no leaderboard read call. No existing API changes.
- `ZokoGames.settings` holds `kidsMode` (read it with `settings.get("kidsMode", false)`). Simulator project setting `zokogames/simulator/kids_mode`.

## 1.4.1 (2026-11-19)

- Matches the JavaScript SDK 1.4.1 (a fix release with no API change: inside the portal the handshake waits up to 15 s instead of 1.5 s, per-key user tokens, game calls that resolve with a warning when the portal does not answer, cheaper cloud-save writes with retried syncs). No wrapper API change from the SDK side.

- After an ad, the sign-in or account-link prompt or a checkout, keyboard focus is handed back to the game frame and its canvas (shared bridge core), so keys work without a click.
- New `pause_game_during_ads`, `mute_audio_during_ads` and `follow_portal_mute` (all default true), as in the Godot 3 addon: the tree is paused and the Master bus muted from `ad_started` to `ad_finished` / `ad_error`, and the portal's mute setting is applied to Master. Set them to false to keep handling it yourself.
- README: the `request_ad` callback keys are `"ad_started"`, `"ad_finished"`, `"ad_error"` (the table said `started` / `finished` / `error`); rows for the ad callbacks, `ERROR_CODE_DESCRIPTIONS`, `SDK_VERSION`. New `TESTING.md`.

## 1.4.0

- Fixes `init_async()`: it now goes through `init()`, so the bridge is connected and `is_initialized` is set.

- Matches the JavaScript SDK 1.4.0 (`game.reportChat`, `game.onScreenshotRequest`, `data.mirrorLocalStorage`, all additive). Real engine bindings for all three: chat reports, a screenshot provider (with a default end-of-frame capture) and the localStorage mirror, each with editor/mock behaviour and tests. The mirror only sees browser localStorage, not the IndexedDB saves most engines use. No existing API changes.

## 1.3.1

- Matches the JavaScript SDK 1.3.1 (a fix release: the ad request times out after 30 s when the host never answers, malformed host messages are ignored, `SDK.init()` is safe without `window`, loading the script twice keeps the first instance, and `ERROR_CODE_DESCRIPTIONS` is exported). No wrapper API change.

## 1.3.0

- Matches the JavaScript SDK 1.3.0: adds the room data channel (`game.room`): `room_send`, `room_send_to`, `room_set_state`, `room_get_state`, `room_get_members`, `room_is_host`, `room_self_id` (callback and `_async` forms) and the signals `room_message`, `room_state`, `room_members`, `room_host_changed`, `room_error`, with a simulator that loops messages and state changes back. `ERROR_CODES` gains `room`.

## 1.2.0

- Matches the JavaScript SDK 1.2.0: adds offline awareness, a read-only offline flag plus a change notification (see the README coverage table for `game.isOffline`, `game.addOfflineListener`, `game.removeOfflineListener`).
- Adds the achievements module (additive): `achievements_list`, `achievements_unlock` (callback and `_async` forms) and the `achievement_unlocked` signal, with simulator support.

## 1.1.1

- Matches the JavaScript SDK 1.1.1: the banner refresh floor now holds across clear and request cycles, and local mode reads invite parameters from the page URL.

## 1.1.0

- Matches the JavaScript SDK 1.1.0: `store.getPurchaseToken` (`user.getXsollaUserToken` stays as a deprecated alias) and the `ERROR_CODES` tables, with a purchases example.

## 1.0.0

- Full coverage of the JavaScript SDK 1.0.0: ad, banner, game, user, data, store, analytics, events and error codes.
- New in this release: `game.loadingProgress`, `game.showInviteButton` / `hideInviteButton`, `game.isInstantJoin`,
  `store.getPurchaseToken` (`user.getXsollaUserToken` kept as a deprecated alias), the `ERROR_CODES` tables, the whole `store` module (catalogue, inventory, buy, consume, sandbox).
- Added the `VERSION` constant, the `examples/zoko_demo.gd` sample, store simulator, and loading progress in the export shell.
- Coverage is enforced: `node tools/check-coverage.mjs` fails when this README's API table misses a JS SDK member.
