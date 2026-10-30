# Bridge Secret: Fixed Shared Constant

## Why

The browser companion extension's in-page lookup bubble reports 「本地词典桥未连接 / 请先启动 V8 工作工具箱」 and, after the desktop app is started, 「本地词典桥拒绝访问」, even though the bridge is running. Root cause: the desktop app **randomly generates** the bridge secret and persists it (`SettingsStore.ensureLocalDictionaryBridgeSecret`), while the extension **hard-codes** one secret in `background.js`. The two can only match when the hard-coded value happens to equal a random 24-byte value — effectively never. Every desktop reinstall / app.json reset / migration silently breaks pairing, and no sync mechanism exists despite `background.js` comments implying one.

The tool is single-user. The bridge's own threat model (documented at the top of `local_dictionary_bridge.dart`) already excludes "attackers who can read local files or source code" — it guards against misuse and opportunistic calls only. A fixed shared constant is consistent with that model.

## What Changes

- **BREAKING** (security posture, single-user only): The bridge secret becomes a **fixed shared constant** in two places — `lib/services/settings_store.dart` (Dart, desktop side) and `extensions/v8-browser-companion/background.js` (extension side). Remove the random generation path.
- `SettingsStore.ensureLocalDictionaryBridgeSecret()` returns the constant instead of generating + persisting one; `localDictionaryBridgeSecretOrEmpty` returns the same constant; `_generateBridgeSecret()` is deleted.
- The stale `localBridgeSecret` key already present in an existing `app.json` becomes inert (ignored, not deleted).
- The two copies of the constant cross-reference each other with a comment, so a one-sided edit is caught.
- The infinite-canvas asset bridge (port 8798) reuses the same getter and therefore the same constant automatically.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `local-dictionary-bridge`: the "Bridge access authentication" requirement changes from "persisted randomly-generated secret" to "fixed shared constant". The persistence scenario ("Secret persists across desktop application restarts") is replaced by a constant-match scenario.

## Impact

- `lib/services/settings_store.dart` — secret generation removed, getters return constant.
- `lib/services/local_dictionary_bridge.dart` — no code change (reads getter); behavior changes implicitly.
- `lib/tools/infinite_canvas/services/infinite_canvas_bridge_server.dart` — no code change (reads getter); asset bridge now requires the same fixed secret. Its plugin client (`infinite_canvas_canvas_plugin_source.dart`) already prompts once and caches in localStorage, so one-time re-entry.
- `lib/tools/infinite_canvas/ui/infinite_canvas_studio_page.dart` — shows the same constant in the "install canvas plugin" card; no code change.
- `extensions/v8-browser-companion/background.js` — `BRIDGE_SECRET` stays, gains a cross-reference comment.
- `test/local_dictionary_bridge_test.dart` — the "secret persists across re-init" test still passes but its assertion weakens; add a comment.
- Existing `app.json` `localBridgeSecret` value becomes ignored (no migration needed).
