# Design: Bridge Secret Fixed Shared Constant

## Context

See `proposal.md` — Why. The failure is observed in the field: the bubble shows 「本地词典桥未连接」 when the app is closed, and 「本地词典桥拒绝访问」 when the app is open, because the desktop side randomly generates + persists a secret (`SettingsStore._generateBridgeSecret`, 24 random bytes) while the extension hard-codes `BRIDGE_SECRET = '1rVOk7...'` in `background.js`. Verified: `curl` with the extension's value returns 401; with the persisted `app.json` value returns 200.

## Goals / Non-Goals

**Goals:**
- Make the desktop-accepted secret **always equal** the extension's hard-coded value, so pairing can never drift.
- Keep the bridge's fail-soft lifecycle and single-location dictionary logic untouched.
- Keep existing tests green without weakening their coverage meaningfully.

**Non-Goals:**
- No pairing handshake, no secret-rotation UI, no secret disclosure endpoint.
- No migration of the existing stale `app.json` `localBridgeSecret` value (it becomes inert).
- No change to the threat model or the bridge's read/write surface (`/dictionary`, `/vocab`).

## Decisions

**Decision 1: A single fixed constant in two files, cross-referenced by comment.**
Dart and JS cannot share one compile-time constant across language boundaries. The constant is declared in `settings_store.dart` (source of truth) and duplicated in `background.js`. Each copy carries a comment naming the other file, so a one-sided edit is visible in review. Alternative considered: `GET /hello` unauthenticated secret disclosure — rejected because it puts the secret on the loopback for any local process to read, and because the threat model (documented at `local_dictionary_bridge.dart:14`) already excludes local-file readers.

**Decision 2: Desktop adopts the extension's existing value (`1rVOk7...`), not a new value.**
Changing the extension value instead would require every installed extension to be reloaded with a new secret; keeping the extension untouched means zero extension-side churn and the existing `app.json` value simply becomes ignored.

**Decision 3: Keep `ensureLocalDictionaryBridgeSecret()` as the single entry point, now returning the constant.**
Both bridges (`LocalDictionaryBridge` port 8797 and `InfiniteCanvasBridgeServer` port 8798) and the canvas plugin UI read the secret through `SettingsStore` getters. Collapsing the getters to the constant propagates to all three automatically, so no caller changes. The infinite-canvas plugin client (`infinite_canvas_canvas_plugin_source.dart`) prompts once and caches in `localStorage`; with a fixed value it prompts exactly once ever, which is an improvement over the current random-on-every-install.

**Decision 4: Delete `_generateBridgeSecret()` and drop the persistence branch.**
`ensureLocalDictionaryBridgeSecret()` becomes `async => kLocalBridgeSecret`; `localDictionaryBridgeSecretOrEmpty` becomes `=> kLocalBridgeSecret`. The `localBridgeSecret` key is never read again and is not written by `_defaultAppConfig()`.

## Risks / Trade-offs

- **[Secret readable from source code]** → Acceptable: the threat model already excludes source-code/local-file readers; `/vocab` only writes the vocabulary store (no ciphertext, no password vault), and `/dictionary` is read-only. Single-user tool.
- **[Someone edits one side only]** → Mitigation: cross-referencing comments in both files name the counterpart; the pairing is single-user, so breakage surfaces immediately on first lookup.
- **[Existing `app.json` holds a now-dead `localBridgeSecret`]** → Inert, never read; not worth a migration. Left in place.
- **[Asset bridge (8798) switches to the fixed value]** → Its plugin client already handles a 401 by prompting and caching, so one-time re-entry of the fixed value; no code change on the Dart side (it reads the same getter).

## Migration Plan

1. Edit `settings_store.dart`: add `kLocalBridgeSecret`, collapse both getters, delete `_generateBridgeSecret`.
2. Add the cross-reference comment to `background.js` (its `BRIDGE_SECRET` value is unchanged).
3. Add a comment to `test/local_dictionary_bridge_test.dart` near the "secret persists across re-init" test noting the assertion is now constant-vs-constant.
4. Rebuild + `./scripts/deploy_local.sh`; reload the extension; verify a lookup returns definitions. No extension reload of the value is needed because the value itself is unchanged — only the desktop side changes.
