# Design: add-privacy-browser

## Context

The privacy space currently provides PIN-locked access to a private media player (AVKit-based with AI subtitle overlay), a yt-dlp–backed video download queue, and an AI subtitle pipeline (yt-dlp fast path + Whisper/MiMo STT fallback). The missing piece is a browser: users currently find content on the web, copy URLs, then manually queue downloads. This change closes that loop by embedding a WKWebView browser directly inside the privacy space — with native video detection, subtitle overlay, a private video library, and AI-assisted tagging and search. Target platforms: YouTube, MissAV, jav.sb, 91porn, PornHub, pornlulu.

## Goals / Non-Goals

**Goals**

- Full multi-tab WKWebView browser inside the privacy space with cross-session tab persistence.
- N-grid new-tab homepage with user-configurable shortcuts and cached favicons.
- Bookmark manager synced to the privacy space SQLite store.
- JS-level video detection with a native floating toolbar (Download, Cache & Play, Favorite, Subtitle).
- Native NSView subtitle overlay on WKWebView, driven by the same AI subtitle pipeline used in the media player.
- Private video library: multi-level category tree, multi-tag, star rating, notes, AI summary.
- AI layer: auto-tagging on favorite, manual re-analysis, semantic search, AI chat panel — all via the global AI slots.
- Proxy integration using the existing proxy-manager.

**Non-Goals**

- Browser DevTools or extension system.
- Cross-device tab/bookmark sync.
- DRM bypass or EME key extraction.
- Replacing the existing standalone download queue UI.

---

## Decisions

### 1. Tab Persistence

**Chosen:** Store tab state (URL, title, scroll position, last-visited timestamp) in the privacy space SQLite store under a `browser_tabs` table. Tabs are restored on unlock and torn down (WKWebView instances released) on lock.

**Why:** Consistent with the existing pattern of using SQLite for privacy-space data. Encrypted at rest via the same store-level protection. Lightweight — only scalar state is persisted, not page snapshots.

**Alternatives considered:**

- *In-memory only* — tabs lost on lock or app quit. Rejected: poor UX for long research sessions.
- *WKWebView session snapshot serialization* — possible via `WKWebView._sessionState` private API. Rejected: heavy per-tab payload, private API surface, and unnecessary given URL-restore is sufficient.

---

### 2. Video Detection Strategy

**Chosen:** Dual-layer detection.

- **Layer A — URL-pattern matching:** On navigation commit, match the URL against a platform registry (YouTube, MissAV, jav.sb, 91porn, PornHub, pornlulu). On match, inject a platform-specific JS adapter that locates the canonical `<video>` element and posts its metadata (src, duration, title) to the native layer via `WKScriptMessageHandler`.
- **Layer B — Generic MutationObserver:** For unrecognized domains, a baseline observer script watches for `<video>` element insertion and posts the same message structure.

The native floating toolbar is an `NSView` anchored in the window chrome above the WKWebView, not injected into the page DOM.

**Why:** Avoids CSP conflicts entirely — the toolbar never lives in the page's DOM. Platform-specific adapters handle sites that use non-standard player wrappers (e.g., custom Shadow DOM). The generic observer catches everything else.

**Alternatives considered:**

- *Inject toolbar into page DOM* — simpler coordination but breaks on sites with strict CSP (`script-src`, `frame-ancestors`) or those that actively remove foreign DOM nodes. Rejected.
- *Single generic observer only* — insufficient for platforms that delay `<video>` insertion behind complex async rendering. Rejected.

---

### 3. Subtitle Overlay Architecture

**Chosen:** An `NSView` overlay is positioned over the WKWebView frame and kept in sync via frame-change notifications. A JS script injected at `document-start` polls `video.currentTime` at 250 ms intervals and posts it to the native layer via `WKScriptMessageHandler("subtitleSync")`. The native layer performs subtitle cue lookup and renders text via the same `CATextLayer`-based renderer used by the private media player's AVPlayer overlay.

**Why:** Architecturally identical to the existing AVPlayer subtitle overlay, minimizing new surface area. Native rendering gives full control over font, shadow, and positioning without fighting page styles.

**Alternatives considered:**

- *Inject subtitle rendering into page DOM* — rejected for the same CSP reasons as the toolbar. Additionally, platform players sometimes cover injected DOM nodes with their own overlay layers.
- *Poll at 100 ms* — available as a tunable constant if 250 ms proves too coarse for fast subtitle sequences, but 250 ms is the default to avoid excessive IPC traffic.

---

### 4. Video Library Storage

**Chosen:** A dedicated SQLite database file (`VideoLibrary.sqlite`) in the privacy space application support directory, separate from the main privacy-space store. Schema:

```
categories(id, parent_id, name, sort_order)
tags(id, name)
video_bookmarks(id, url, title, platform, thumbnail_path, duration_s, rating, notes, ai_summary, ai_tags_json, category_id, created_at, updated_at)
bookmark_tags(bookmark_id, tag_id)
```

Full-text search (FTS5) virtual table on `title || ' ' || notes`. `ai_tags_json` stores the LLM tag array as JSON for schema flexibility.

**Why:** SQLite is already used throughout the app; FTS5 is bundled. A dedicated file keeps the library portable and restorable independently of other privacy-space data.

**Alternatives considered:**

- *Core Data* — heavier migration story, less portable for future export features. Rejected.
- *Shared SQLite store with media player history* — library data has a different lifecycle and access pattern. Rejected for separation of concerns.

---

### 5. AI Tagging Trigger

**Chosen:** On bookmark creation (Favorite button tap), a fire-and-forget `Task` is dispatched that calls the global Text LLM slot with: `title`, `platform`, URL-derived domain, and `og:description` (extracted from page metadata before navigation, if available). The LLM prompt requests a JSON response: `{ "tags": [string], "category": string }`. A spinner badge on the bookmark row indicates pending state. On completion, `ai_tags_json` and optionally `category_id` are written back. Manual re-analysis replaces the stored tags.

**Why:** Asynchronous and non-blocking. The Text LLM slot is already used elsewhere; no new AI infrastructure needed. JSON-structured prompt output is straightforward to parse.

**Alternatives considered:**

- *Tag at download time* — not all favorited items are downloaded. Rejected.
- *Synchronous tagging before bookmark save* — blocks the UI. Rejected.

---

### 6. Semantic Search Implementation

**Chosen:** On semantic search query, first apply FTS5 to retrieve the top 200 bookmarks by text relevance. Pass the query plus the title+tags of those 200 bookmarks to the Text LLM slot, requesting a ranked JSON array of matching IDs. Display results in ranked order.

**Why:** No embeddings infrastructure required. Acceptable latency for a library of fewer than 10k items. FTS5 pre-filtering keeps LLM context size bounded.

**Alternatives considered:**

- *Local embedding model + ANN index* — better precision at scale, but requires a bundled embedding model and vector store. Deferred as a future option once library sizes warrant it.
- *Pass all bookmarks to LLM* — context window limits and latency make this impractical beyond a few hundred items. Rejected.

---

### 7. Proxy Integration

**Chosen:** Implement a `WKURLSchemeHandler`-based interceptor that routes HTTP/HTTPS requests through `URLSession` configured with the proxy host, port, and credentials from the existing proxy-manager. This approach works without relying on private `WKWebViewConfiguration` proxy APIs.

For HTTPS, the interceptor uses `URLSession` with a custom `URLSessionTaskDelegate` that handles the CONNECT tunnel. The proxy-manager already exposes `ProxyConfiguration` (host, port, authCredential).

**Why:** The private API `_setProxyConfiguration` on `WKWebViewConfiguration` has an undocumented signature that varies across macOS versions. The URLSession interceptor is fully documented and gives the same result.

**Alternatives considered:**

- *`WKWebViewConfiguration._setProxyConfiguration` private API* — simpler if stable, but the API name and argument types have changed across macOS releases. Retained as a future fast path if Apple formalizes it.
- *System-level proxy settings* — affects all app traffic, not scoped to the privacy browser. Rejected.

---

### 8. N-Grid Homepage

**Chosen:** A SwiftUI view rendered as the WKWebView's initial content for new tabs (not a web page loaded into the WebView). Shortcuts are stored in a `homepage_shortcuts(id, name, url, favicon_url, favicon_cache_path, sort_order)` table in the video library SQLite. Favicons are fetched asynchronously on shortcut creation and cached to disk. The grid column count is a user preference (default: 5).

**Why:** A native SwiftUI view has no CSP constraints, renders instantly without a network round-trip, and integrates naturally with the privacy space's design language. Caching favicons locally avoids repeated network requests.

**Alternatives considered:**

- *Load a local HTML file into WKWebView* — adds an unnecessary indirection layer and makes layout changes require HTML/CSS edits. Rejected.
- *Fetch favicons on every open* — adds latency and unnecessary network traffic. Rejected.

---

## Risks / Trade-offs

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CSP / JS injection failures on some platforms | Medium | Low | Native toolbar and subtitle overlay never depend on page-side injection succeeding; Layer B observer is best-effort only |
| `WKURLSchemeHandler` proxy interceptor missing edge cases (WebSocket, QUIC) | Medium | Medium | Proxy interceptor covers HTTP/HTTPS; WebSocket proxying deferred; QUIC disabled via `WKWebView` preference flag |
| AI tagging quality degrading for non-English titles | High | Low | Tags are surfaced as suggestions with one-tap dismiss; users can edit or re-run analysis |
| Subtitle sync drift at 250 ms polling interval | Low | Low | 250 ms is acceptable for typical video; polling interval is a named constant (`SubtitleSyncIntervalMs`) trivially reducible to 100 ms |
| Semantic search quality degrading beyond a few thousand bookmarks | Low (near-term) | Medium | FTS5 pre-filter caps LLM input at 200 items; local embedding model path deferred for future scale |
| WKWebView memory pressure with many tabs | Medium | Medium | Tabs beyond a configurable limit (default: 10) are suspended (WKWebView released, state preserved in SQLite); restored on activation |

## Open Questions

None that block implementation.
