## Purpose

Provides a secure, lightweight browser companion extension for Google Chrome and Chromium browsers that offers in-page word lookup bubbles, CORS-resilient dictionary queries via service worker delegation, and one-click note capturing into V8 Work Toolbox.

## ADDED Requirements

### Requirement: Service worker delegated dictionary lookups
The browser companion SHALL execute all external dictionary queries (`dict.youdao.com`, `api.dictionaryapi.dev`) through its background service worker (`background.js`) via Chrome runtime messaging, and declare explicit `host_permissions` in `manifest.json`.

#### Scenario: In-page word lookup bypassing webpage CSP and CORS
- **WHEN** user selects an English word on any webpage (e.g. Baidu Baike, GitHub, Medium) and clicks the V8 floating action icon
- **THEN** the content script sends a message to the background service worker, which fetches definitions, phonetics, and audio URLs without being blocked by host page CSP or CORS, and returns structured data to the in-page bubble within 800ms.

#### Scenario: Query fallback on dictionary failure
- **WHEN** the background service worker cannot find the word in primary dictionary APIs
- **THEN** the bubble displays an informative state with an option to open the desktop V8 Work Toolbox for AI deep analysis.
