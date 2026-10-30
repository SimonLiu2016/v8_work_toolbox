# Tasks: Bridge Secret Fixed Shared Constant

## 1. Desktop: fixed shared constant

- [x] 1.1 In `lib/services/settings_store.dart`, add `static const String kLocalBridgeSecret = '1rVOk7DvbImjMqu2nxzjxQ4UtDxFNkwK';` with a comment naming `extensions/v8-browser-companion/background.js` as the counterpart that must stay in sync.
- [x] 1.2 Change `ensureLocalDictionaryBridgeSecret()` to return `kLocalBridgeSecret` (no generation, no persistence branch).
- [x] 1.3 Change `localDictionaryBridgeSecretOrEmpty` to return `kLocalBridgeSecret`.
- [x] 1.4 Delete `_generateBridgeSecret()` and the now-unused `Random`/`base64Url` imports if no other code uses them.

## 2. Extension: cross-reference comment

- [x] 2.1 In `extensions/v8-browser-companion/background.js`, update the `BRIDGE_SECRET` comment to name `lib/services/settings_store.dart` as the counterpart that must stay in sync. Value stays `1rVOk7DvbImjMqu2nxzjxQ4UtDxFNkwK`.

## 3. Tests

- [x] 3.1 In `test/local_dictionary_bridge_test.dart`, add a comment to the "secret persists across re-init" test noting the assertion now checks a constant against itself.
- [x] 3.2 Run `flutter analyze` and `flutter test test/local_dictionary_bridge_test.dart` — all green.

## 4. Verification

- [x] 4.1 Rebuild and deploy: `./scripts/deploy_local.sh`; reload the extension at `chrome://extensions`.
- [x] 4.2 Confirm a lookup in the browser bubble returns real definitions (secret now matches, bridge returns 200).
- [ ] 4.3 Confirm the infinite-canvas plugin still authorizes (re-enter the fixed secret once if it prompts on 401). — 依赖用户打开「无限画布工作室」工具页并操作 Figma 插件，本机无法自动触发。资产桥 8798 是工具页按需启动（`infinite_canvas_studio_page.dart:56`），非应用级常驻。插件侧 401 时 prompt 一次、输入 `kLocalBridgeSecret` 即可，此后永不失效。
