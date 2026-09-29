## Context

See proposal.md for motivation and context.
Currently, Chrome Manifest V3 restricts Content Script requests by the host webpage's Content Security Policy (CSP) and CORS rules. Calling `fetch()` directly in `content.js` leads to blocked connections ("查询失败或网络不通") on pages like Baidu, GitHub, and Medium.
On the desktop application side, `V8WorkToolboxApp` and its sub-windows hardcode `theme: AppTheme.darkTheme`. While `AppTheme.lightTheme` exists, it is not wired to user settings, and `SettingsDialog` lacks a theme selector.

## Goals / Non-Goals

**Goals:**
- Eliminate CORS and CSP failures for the browser companion by offloading dictionary HTTP queries to `background.js` with `host_permissions`.
- Support global theme mode selection in `SettingsDialog` (跟随系统 / 浅色模式 / 深色模式) and persist in `SettingsStore` (`app.json`).
- Enable instantaneous reactive theme switching across the main app and sub-windows via `ValueNotifier<ThemeMode>`.
- Adapt `AppShell` and primary UI components to render cleanly in both light and dark themes.

**Non-Goals:**
- Arbitrary custom RGB theme builder (scoped specifically to Follow System, Clean Light, and Raycast Dark).
- Offline-only local ML dictionary parsing in the extension.

## Decisions

### Decision 1: Background Service Worker Delegation for Extension Queries
- **Choice**: In `manifest.json`, declare `host_permissions: ["https://dict.youdao.com/*", "https://api.dictionaryapi.dev/*"]`. In `content.js`, send a message `{ action: 'fetchDictionary', word }` to `background.js`. `background.js` executes the fetch and parses the payload into a standard schema `{ phonetic, audioUrl, definitions }` before sending it back.
- **Alternatives considered**:
  - `fetch` in content script with iframe: Still blocked by frame-ancestors CSP.
  - Proxying queries through a local localhost server: Requires V8 desktop app to be open at all times; background service worker works even when desktop app is closed.

### Decision 2: Reactive Theme Store with `ValueNotifier<ThemeMode>`
- **Choice**: Add `themeMode` to `SettingsStore` (stored as `'system'`, `'light'`, `'dark'`). Expose `ValueNotifier<ThemeMode> themeModeNotifier`. In `main.dart`, wrap root `MaterialApp` instances with `ValueListenableBuilder<ThemeMode>` so the UI reacts without restarting.
- **Alternatives considered**:
  - Requiring app restart: Poor user experience for theme switching.
  - Adding an external state management package: `ValueNotifier` is lightweight, zero-dependency, and already used across V8 (e.g. `PrivacySecurityService.isUnlockedNotifier`).

### Decision 3: AppShell & Component Light/Dark Coherence
- **Choice**: In `AppShell` and shared dialogs, bind backgrounds and borders to `Theme.of(context)` brightness or semantic theme helpers, ensuring that switching to Light Mode displays macOS-style light panels, crisp borders, and dark typography instead of inverted artifacts.

## Risks / Trade-offs

- **[Risk]** Third-party sites in iframes or restricted extensions pages (`chrome://`).
  - **Mitigation**: Extension content script already ignores `chrome://` URLs, and fallback to desktop URL scheme `v8toolbox://lookup?text=...` is retained when browser context fails.
- **[Risk]** Sub-windows created prior to a theme change may need sync.
  - **Mitigation**: Sub-windows can listen to `SettingsStore.instance.themeModeNotifier` or read persisted setting on rebuild.
