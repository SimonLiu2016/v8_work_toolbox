## Context

The initial context menu and popover implementation exposed major cross-platform friction:
- In browsers, external OS windows fail to provide the seamless in-page bubble experience of Doubao;
- In external documents (PDF, Word), macOS right-click menus are suppressed or disabled;
- The dictionary engine hung for 8+ seconds due to blocked foreign API endpoints and prematurely triggered slow AI models;
- Popovers were locked into a dark aesthetic;
- Notes rendered raw Markdown punctuation instead of rich-text formatting.

## Goals / Non-Goals

**Goals:**
- Provide a 1:1 Doubao-style in-page floating bubble inside Chromium browsers.
- Provide a Bob/PopClip-style floating action icon on text selection across all macOS apps.
- Achieve sub-500ms dictionary lookup by using high-availability domestic endpoints without auto-fallback to AI.
- Introduce native light theme styling and automatic macOS system appearance following.
- Parse captured notes using `MarkdownConverter` to produce formatted rich-text delta nodes.

**Non-Goals:**
- Injecting code into third-party application address spaces (violating macOS SIP).
- Rewriting the notebook storage schema.

## Decisions

### 1. In-Page Browser DOM Bubble via Shadow DOM
- **Decision**: In `extensions/v8-browser-companion`, inject `content.js` and `content.css` using Shadow DOM (`attachShadow({ mode: 'open' })`) to isolate popup styling from host web pages.
- **Rationale**: Guarantees zero CSS pollution from host websites, anchors directly to `range.getBoundingClientRect()`, and renders instantly.

### 2. Desktop Floating Action Button via Global Event Monitor
- **Decision**: In `AppDelegate.swift`, monitor `leftMouseUp` events globally. If `getSystemSelectedText()` yields non-empty text, display a lightweight, floating 28x28 `NSPanel` icon adjacent to `NSEvent.mouseLocation`. Clicking unfolds the card.
- **Rationale**: Bypasses the complete absence of right-click menus in Microsoft Word and Preview without invasive system modifications.

### 3. Domestic Fast Dictionary Engine & On-Demand AI
- **Decision**: Promote `YoudaoService` to the primary dictionary engine with rich definitions, phonetic audio, and sub-300ms latency. Remove automatic AI escalation in `LookupCoordinator`; present a prominent "使用 AI 深度解析" button for user-driven invocation.
- **Rationale**: Solves the 8-15 second spinner issue completely.

### 4. Dual-Theme Architecture with System Following
- **Decision**: Add `AppTheme.lightTheme` with clean white canvas (`#FFFFFF`), light border (`#E2E8F0`), and dark typography (`#0F172A`). Wire `ThemeMode.system` across `LookupWindowApp`.
- **Rationale**: Matches macOS appearance cleanly during daytime reading.

### 5. Rich Note Delta AST Generation
- **Decision**: In `NoteCaptureService`, pipe `fullContent` through `MarkdownConverter.markdownToDelta()`.
- **Rationale**: Generates native AppFlowy Delta AST with bold, link, heading, and divider block types, eliminating raw syntax characters.

## Risks / Trade-offs

- **[Risk] High-frequency selection events on desktop**: Fast selecting/clicking could spawn floating buttons repeatedly.
  - **Mitigation**: Add a 150ms debounce and require minimum selection length (>= 2 characters).
- **[Risk] Shadow DOM isolation in browser**: Certain aggressive webpage styles may affect fixed positioning.
  - **Mitigation**: Use `position: fixed` relative to viewport bounding rects.
