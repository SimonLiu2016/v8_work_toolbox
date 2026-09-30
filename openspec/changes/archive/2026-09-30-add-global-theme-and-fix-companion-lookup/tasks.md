## 1. Browser Companion Network Architecture Fix

- [x] 1.1 Add `host_permissions` for dictionary endpoints (`https://dict.youdao.com/*`, `https://api.dictionaryapi.dev/*`) in `extensions/v8-browser-companion/manifest.json`
- [x] 1.2 Implement `fetchDictionary` message listener in `extensions/v8-browser-companion/background.js` to execute queries in background context
- [x] 1.3 Update `extensions/v8-browser-companion/content.js` to dispatch `fetchDictionary` via `chrome.runtime.sendMessage` and render bubble results

## 2. Settings Store Theme Mode Extension

- [x] 2.1 Add `themeMode` string getter/setter (`'system'`, `'light'`, `'dark'`) and reactive `ValueNotifier<ThemeMode> themeModeNotifier` in `lib/services/settings_store.dart`
- [x] 2.2 Update `SettingsStore` tests to verify `themeMode` defaults to `system` and persists properly across loads

## 3. Global Theme Binding in Main & Sub-windows

- [x] 3.1 Bind `V8WorkToolboxApp` in `lib/main.dart` to `SettingsStore.instance.themeModeNotifier` with both `AppTheme.lightTheme` and `AppTheme.darkTheme`
- [x] 3.2 Bind sub-window apps (`_PasswordVaultWindowApp`, `_NotebookWindowApp`, `_OpsToolWindowApp`, `_SingleNoteWindowApp`, `LookupWindowApp`) to the dynamic theme mode

## 4. Appearance & Theme Selection in SettingsDialog

- [x] 4.1 Add Appearance & Theme configuration section in `lib/shell/settings_dialog.dart` with radio options for 跟随系统、浅色模式、深色模式
- [x] 4.2 Wire theme option taps to `SettingsStore.instance.setThemeMode()` with instant feedback

## 5. UI Theme Polish & Verification

- [x] 5.1 Verify and polish `AppShell` container colors and dividers for consistent presentation across light and dark modes
- [x] 5.2 Run unit tests and verify full compilation
