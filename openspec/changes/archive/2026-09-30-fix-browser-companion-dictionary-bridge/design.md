## Context

See `proposal.md` — Why for the measured evidence. This section covers only the constraints that shape the approach.

Current state relevant to the design:

- The extension's dictionary path is `content.js` → `chrome.runtime.sendMessage` → `background.js:handleFetchDictionary` → two external endpoints. Both are unusable from extension context (403 / 522, measured).
- The desktop application's dictionary path is independent and healthy: `v8toolbox://lookup?text=…` → `macos/Runner/AppDelegate.swift:handleIncomingUrl` → `ContextServicesBridge` → `LookupWindowLauncher` → `YoudaoService.lookupFull` (no `Origin` header, ~300ms).
- The desktop application already supervises one local subprocess and one local TCP listener — `MihomoProcessManager` (mixed-port 7890, external-controller 9090 on `127.0.0.1`) — but binds its own ports from config rather than asking the OS.
- Window lifecycle is centralized: `WindowServices.initFor(WindowKind)` per window kind, plus `runShutdownCleanup()` shared by `onWindowClose` and `ProcessSignal.sigterm`.
- Persistent app-level preferences are plain JSON via `SettingsStore` (`app.json`), with `ValueNotifier` broadcast for reactive reads (`themeModeNotifier` is the established pattern).
- Chrome terminates an MV3 service worker when a `fetch()` response takes longer than 30 seconds. The current fallback chain (403 → 20s FreeDict) sits at ~21s with no abort, so it can strand the bubble in a loading state.

**Deployment context (decided by the user):** this application runs on a single machine for its owner — it is not a distributed product. Threat model is therefore "accidental or opportunistic local use", not "a local attacker". This is why the bridge's shared secret is a constant copied into `background.js` rather than a runtime-delivered credential; see Decision 2.

## Goals / Non-Goals

**Goals:**
- Move the single dictionary implementation behind the desktop application, so the extension is a thin client and there is exactly one place where dictionary parsing lives.
- Make the bubble's outcome independent of third-party CORS policy and of host-page CSP.
- Bound every service worker request so the bubble can never hang.
- Keep the bridge's blast radius to the loopback interface and to authenticated callers.
- Preserve every existing desktop path (deep links, `⌥D`, macOS Services) byte-for-byte.

**Non-Goals:**
- Serving note capture through the bridge — `v8toolbox://savenote` already works and is untouched.
- Exposing any dictionary write path (vocab book mutations) over the bridge; read-only.
- Replacing `YoudaoService`'s parsing or its caching.
- A general RPC layer. One endpoint, one verb.

## Decisions

### Decision 1: Local HTTP bridge rather than switching dictionary providers

- **Choice**: The desktop application hosts a loopback HTTP endpoint; the extension calls it.
- **Alternatives considered**:
  - **Swap to a CORS-friendly public API** (`api.datamuse.com` returns a permissive `Access-Control-Allow-Origin` for our origin; `translate.googleapis.com` returns `*`). Rejected: datamuse is English-only definitions — it cannot serve the primary use case (EN→ZH). It would also fork dictionary logic into a second implementation in JavaScript, so the extension and desktop app could drift, and make the bubble hostage to another third party's rate limits and uptime.
  - **`declarativeNetRequest` `modifyHeaders` to strip `Origin`**. Rejected: the operation enum is `append` / `set` / `remove`, and `set` is the only way to change `Origin` — Chrome reserves that for the network stack, and `fetch` from a service worker is not the `webRequest` path DNR intercepts. Even if it worked, it would be fighting the platform rather than working with it.
  - **Keep direct external fetch and add retries**. Rejected: the failure is deterministic, not transient. Retrying a 403 twenty times stays a 403.
- **Rationale**: The bridge inverts the dependency. The extension stops being a network client and becomes a UI shell; the desktop application remains the only thing that talks to Youdao. Loopback is also the cheapest CORS story available: we author the response headers.

### Decision 2: Secret delivered as a persistent value shared by both sides

- **Choice**: The desktop application generates the secret once, persists it in `SettingsStore` (`app.json`), and the extension carries the same value as a constant in `background.js`. A mismatch is an authorization failure, not silent.
- **Alternatives considered**:
  - **Native messaging host** to hand the secret over at runtime. Rejected **for this deployment context**: it adds an installer, a manifest, and a native host binary to solve a problem a single-machine, single-owner setup does not have. Revisit only if the bridge ever grows a write path — at which point the value at stake is no longer "dictionary data on one box".
  - **No secret at all**, relying on loopback being unreachable. Rejected: any local process (or any web page you visit that can reach `127.0.0.1` with a fetch) could then use the bridge. A static shared secret does not make the bridge private, but it does stop accidental and opportunistic use — and the spec can require the behavior without over-promising the security.
- **Known cost, accepted**: the secret is a hand-synced constant. Reinstall or migrate the desktop app, delete `~/Library/Application Support/V8WorkToolbox/`, or regenerate the key, and the bubble will read 「本地词典桥拒绝访问」 until someone re-copies `localBridgeSecret` from `app.json` into `background.js`. That is a one-time manual step in three rare situations — acceptable for a single-user box, and it fails *loudly* rather than silently, which is the property that matters.
- **Rationale**: Matches the project's existing posture — `SettingsStore` already holds app-level config as JSON, and `themeMode` shows the established `ValueNotifier` + `app.json` pattern.

### Decision 3: Port from `SettingsStore`, not from the OS

- **Choice**: Persist a port (default a fixed constant, e.g. `8797`) in `app.json`; the bridge binds `127.0.0.1:<port>`. If the bind fails (port taken), log a diagnostic and continue — the application must still start.
- **Alternatives considered**:
  - **Ephemeral port from the OS**, published to a file the extension reads. Rejected: the extension cannot read the desktop filesystem, so it cannot discover an ephemeral port.
  - **Retry a port range on conflict**. Rejected as scope; the fixed-port failure path is observable and diagnosable, and a range adds a discovery problem back.

### Decision 4: Reuse `YoudaoService`, add no new dictionary code

- **Choice**: The bridge's handler calls the same dictionary resolution the desktop lookup panel uses, and maps it to a flat JSON schema (`word`, `phonetic`, `definitions`, `audioUrl`, `matched`).
- **Rationale**: Keeps one parser. The `matched: false` field is what lets the bubble distinguish "no match" from "transport error", which the current code cannot do — today a dead fallback chain and a genuine miss both render as a failure.

### Decision 5: Timeout in the bridge's caller, not only in the service worker

- **Choice**: Both sides get bounds — `AbortSignal.timeout(...)` on the extension's fetch (~2.5s, under the 30s worker ceiling with room for the desktop app's own 4s dictionary timeout plus HTTPS), and a bounded desktop-side lookup that already exists (`YoudaoService._timeout = 4s`).
- **Rationale**: The bubble must resolve in under ~3.5s worst case to stay inside the 30s worker ceiling even with retries. 2.5s client + 4s server ≈ 6.5s leaves a large margin.

### Decision 6: Bump the extension version to force a reload

- **Choice**: `manifest.json` version `1.1.0` → `1.2.0`, plus a reload note in the deploy script/README.
- **Rationale**: This is the bug that hid the previous fix. An unpacked extension keeps the service worker registered at install time; only a reload (or version bump that the user acts on) pulls new code. Making the reload a documented step in deployment prevents the same silent staleness from recurring.

## Risks / Trade-offs

- **[Risk] A stale bridge on a dead port produces "bridge offline" for users who left the desktop app closed.** → The bubble's offline state names the cause and offers to open the desktop app; it does not silently fall back to an external endpoint that cannot work.
- **[Risk] The shared secret in `background.js` is readable by anyone with the unpacked extension directory.** → Accepted: loopback-only, read-only, dictionary data only. The secret's job is to stop accidental use, not to withstand an attacker who already has local file access. The bridge shall not be extended to write paths without revisiting this decision.
- **[Risk] Port collision with another local tool.** → Fail-soft with a diagnostic log; other lookup paths (hotkey, services, deep links) are unaffected. Port is configurable in settings if it ever bites.
- **[Risk] Users on a browser other than Chrome/Chromium (Safari/Firefox).** → The extension is Chrome/Chromium-targeted by design; other browsers keep the deep-link fallback, which already works.
- **[Risk] The bridge adds an always-on listener while the app runs.** → `HttpServer` on loopback with one route; bound to the main window's lifecycle and closed in `runShutdownCleanup()`, which already handles the mihomo orphan problem and SIGTERM.

## Migration Plan

1. Desktop side: add the bridge service, wire it into `main()` init (after `SettingsStore`) and `runShutdownCleanup()`. Ship and restart the desktop app.
2. Extension side: point `background.js` at the bridge, add timeouts, distinguish failure states, bump the version.
3. **Pair the secret (one-time, manual)**: read `localBridgeSecret` from `~/Library/Application Support/V8WorkToolbox/app.json` and paste it into `background.js`'s `BRIDGE_SECRET`. Until this is done every lookup returns 401 → 「本地词典桥拒绝访问」. See Decision 2 for when it must be redone.
4. **User action**: `chrome://extensions` → reload the unpacked extension. Until this happens the browser keeps running the old service worker — this is the step whose absence caused the current bug.
5. Rollback: revert the extension to the previous version (back to broken lookups) and/or disable the bridge in settings; the desktop app's own lookups are never affected.

## Open Questions

- Whether to surface "bridge 未启动" as an actionable banner in the desktop app when the bridge fails to bind — currently it is a debug log only. Deferrable; does not change the specs or the task list.
- Whether the bridge should also serve the vocabulary book's read path (list/filter) so a future browser UI could show existing entries. Deferrable; the capability spec is written so a second route can be added without redefining the capability.

**Resolved — not an open question.** Whether to move the bridge secret to a runtime-delivered credential (native messaging host). Decided: no. This is a single-machine, single-owner deployment; a hand-synced constant plus a loud authorization failure is the right amount of machinery, and it fails in a state the user can diagnose rather than silently. The condition that would reopen it is stated in Decision 2 — the bridge growing a write path.

