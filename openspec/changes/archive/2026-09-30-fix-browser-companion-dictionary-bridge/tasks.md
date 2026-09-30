## 1. Desktop: Local Dictionary Bridge service

- [x] 1.1 Create `lib/services/local_dictionary_bridge.dart`: a singleton holding an `HttpServer` bound to `127.0.0.1`, exposing a loopback-only getter for the currently bound port (or null when not listening)
- [x] 1.2 Implement the dictionary route (`GET`, one word/phrase query param) mapping `YoudaoService.lookupFull` into the flat bridge schema: `word`, `phonetic`, `definitions`, `audioUrl`, `matched`
- [x] 1.3 Implement secret checking: reject requests whose `Authorization` header (or query secret) does not match the persisted secret with an authorization failure response, performing no dictionary lookup
- [x] 1.4 Persist the bridge secret and port through `SettingsStore` (`app.json`), generating the secret once on first read so it survives desktop application restarts
- [x] 1.5 Fail-soft startup: when the port is already occupied, log a diagnostic identifying the bridge and keep the application starting normally with every other lookup path intact
- [x] 1.6 Respond with `Access-Control-Allow-Origin` reflecting the requester and `Vary: Origin`, so the route is usable from extension context
- [x] 1.7 Handle malformed requests (bad JSON, bad path) with a client-error response while keeping the listener available for subsequent requests

## 2. Desktop: lifecycle wiring

- [x] 2.1 Start the bridge in `lib/main.dart` main-window init after `SettingsStore` is ready, guarded so a bridge failure never blocks startup
- [x] 2.2 Stop the bridge in `runShutdownCleanup()` and `_MainWindowCloseListener.onWindowClose()` so no orphan listener holds the port on window close or SIGTERM (mirroring the mihomo cleanup contract)
- [x] 2.3 Verify sub-window kinds (`lookupPanel`, `notebook`, `singleNote`, `opsTool`, `passwordVault`) do not start a second bridge instance on the same port — all five sub-window branches `return` before the main-window tail that calls `start()`, and `_MainWindowCloseListener` is only registered on the main-window path

## 3. Extension: query the bridge instead of external APIs

- [x] 3.1 In `extensions/v8-browser-companion/background.js`, replace both external fetches in `handleFetchDictionary` with a single request to `http://127.0.0.1:${BRIDGE_PORT}/dictionary?q=…` carrying the shared secret as an `Authorization` header
- [x] 3.2 Wrap the request in `AbortSignal.timeout(2500)` so the service worker never exceeds the MV3 30-second response ceiling
- [x] 3.3 Map bridge outcomes to three distinct results the bubble can render differently: `bridge_offline` / `bridge_timeout` / `bridge_unauthorized` / `bridge_error` as failure reasons, and `matched: false` as a genuine no-match
- [x] 3.4 Remove the now-dead Free Dictionary API fallback path and its console warning
- [x] 3.5 In `manifest.json`, replace the `dict.youdao.com` / `api.dictionaryapi.dev` host permissions with `http://127.0.0.1:8797/*`, and bump `version` to `1.2.0`

## 4. Extension bubble: honest failure states

- [x] 4.1 In `extensions/v8-browser-companion/content.js`, split the single `!response.success` branch into distinct renderings for bridge offline (`bridge_offline` / `bridge_unreachable` / `bridge_error` → 「本地词典桥未连接」), authorization failure (`bridge_unauthorized` → 「本地词典桥拒绝访问」), and timeout (`bridge_timeout` → 「本地词典桥响应超时」)
- [x] 4.2 Keep the existing deep-link escape hatch on every failure state — `在桌面端打开` on all three failure renderings, `问 AI 深度解析` on the no-match rendering
- [x] 4.3 Ensure no branch can leave the bubble showing `查询中…` indefinitely: `fetchDictionary` is the last statement of `showBubble()`, and all four callback exits write to `#v8-content` (three via `renderFailure`, one for no-match, one for results)

## 5. Tests

- [x] 5.1 Unit test the bridge route: known word returns non-empty definitions with `matched: true`; nonsense term returns `matched: false` with empty definitions
- [x] 5.2 Unit test secret enforcement: request without the secret and with a wrong secret both return 401 and never invoke dictionary resolution
- [x] 5.3 Unit test loopback binding and the port-in-use fail-soft path (occupied port does not throw out of startup); also covers `stop()` releasing the port and idempotency
- [x] 5.4 Unit test the schema mapping, including the audio URL the bubble's speaker button needs
- [x] 5.5 Run `flutter analyze` and the existing lookup-related test suite for regressions

## 6. Deployment: eliminate the stale-extension trap

- [x] 6.1 Update `scripts/deploy_local.sh` with an explicit `remind_extension_reload` step printed after a successful launch: go to `chrome://extensions`, enable Developer mode, hit the reload button on the extension card
- [x] 6.2 Note in the same instructions — and in `README.md` — that an unpacked extension keeps the service worker registered at install time until reloaded, so code changes on disk take effect only after a reload, and restarting the desktop app is not enough
- [x] 6.3 Run `./scripts/deploy_local.sh`, restart the desktop app, reload the extension in Chrome, and confirm the bubble shows real definitions for a word whose external endpoint returns 403 (e.g. `prospective`)
- [x] 6.4 Confirm the offline case: quit the desktop app, trigger a lookup, verify the bubble reports the bridge as offline rather than a lookup failure, and that reopening the app restores lookups without an extension reload
