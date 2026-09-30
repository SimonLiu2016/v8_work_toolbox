## Why

When users select words on webpages and click the floating lookup bubble, the popup consistently displays "查询失败或网络不通" even though the network is connected. This is caused by Chrome Manifest V3 Content Script cross-origin (CORS) and Content Security Policy (CSP) enforcement blocking direct external fetches from injected scripts.
Additionally, while light and dark styling was previously prepared for lookup popovers, the main application and all sub-windows lack global theme mode switching. Users require a unified theme preference (System Follow, Light Mode, Dark Mode) configurable from Settings and applied dynamically across the entire application.

## What Changes

1. **Browser Companion Network Architecture**:
   - Add `host_permissions` for dictionary APIs (`dict.youdao.com`, `api.dictionaryapi.dev`) to `manifest.json`.
   - Migrate in-page dictionary fetching logic from `content.js` to `background.js` via `chrome.runtime.sendMessage`. The background service worker executes queries and returns structured data, bypassing webpage CSP and CORS restrictions.
2. **Global Application Theme Mode**:
   - Add `themeMode` (`system`, `light`, `dark`) persistence and a reactive `ValueNotifier<ThemeMode>` in `SettingsStore`.
   - Update `V8WorkToolboxApp` and all sub-windows in `lib/main.dart` to bind dynamically to `themeMode` with both `AppTheme.lightTheme` and `AppTheme.darkTheme`.
   - Add an Appearance & Theme configuration section in `SettingsDialog` with selectable options (跟随系统、浅色模式、深色模式).
   - Ensure AppShell and key workspace components adapt cleanly to light/dark themes without hardcoded dark background artifacts.

## Capabilities

### New Capabilities
- `browser-companion-extension`: Browser extension companion delivering in-page selection bubbles, native desktop bridge links, and CORS-resilient dictionary queries.

### Modified Capabilities
- `theme-and-brand`: Support dynamic global theme mode switching (system follow, light, dark) applied across the main application and all sub-windows.
- `settings-storage`: Persist and broadcast global `themeMode` configuration with reactive change notifications.

## Impact

- `extensions/v8-browser-companion/manifest.json`: Add `host_permissions`.
- `extensions/v8-browser-companion/background.js`: Add dictionary lookup message handler.
- `extensions/v8-browser-companion/content.js`: Delegate fetching to background messaging.
- `lib/services/settings_store.dart`: Add `themeMode` getters, setters, and notifier.
- `lib/shell/settings_dialog.dart`: Add Appearance & Theme selection UI.
- `lib/main.dart`: Bind `MaterialApp` themeMode reactively for main and sub-windows.
- `lib/theme/app_theme.dart`: Ensure semantic theme color accessibility for both light and dark modes.
