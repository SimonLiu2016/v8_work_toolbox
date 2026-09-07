## Context

The private media player currently renders inside a nested tab within `PrivateMediaPlayerPage`, surrounded by the application navigation sidebar and tab bar. See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Provide a smooth, one-click / double-click / shortcut-driven transition into full screen.
- Synchronize in-app 100% viewport coverage with macOS native window fullscreen via `media_kit_video`'s `defaultEnterNativeFullscreen()` and `defaultExitNativeFullscreen()`.
- Ensure subtitle rendering, custom controls, and playback state remain unbroken across fullscreen transitions.
- Support standard media desktop shortcuts (`F`, `Escape`, `Space`, Arrow Left/Right).

**Non-Goals:**
- Custom multi-window picture-in-picture floating panels (out of scope for this change).
- Custom macOS menu bar override.

## Decisions

### 1. Dual-Layer Fullscreen Coordination
- **Decision**: Trigger both **In-App Immersive Layer** and **macOS Native Window Fullscreen** simultaneously.
  - When entering fullscreen:
    1. Set `isFullscreen = true` (or push a root fullscreen route) so the player fills the entire app window, hiding all surrounding chrome.
    2. Call `defaultEnterNativeFullscreen()`.
  - When exiting fullscreen:
    1. Call `defaultExitNativeFullscreen()`.
    2. Revert `isFullscreen = false` (or pop root route) to restore embedded tab presentation.
- **Alternatives considered**:
  - *Only macOS Window Fullscreen*: Keeps the sidebar and tab bar visible inside the maximized window, which is not true video fullscreen.
  - *Only In-App Fullscreen*: Leaves macOS dock and top menu bar visible, not taking full advantage of desktop display space.
  - *Decision Rationale*: Combining both gives the exact experience users expect from modern video apps (e.g. Bilibili desktop, YouTube, IINA).

### 2. Video Texture Continuity
- **Decision**: Manage the fullscreen transition in `PrivateMediaPlayerPage` by elevating `PrivatePlayerView` to an overlay or conditionally expanding it across the page body, or passing `isFullscreen` callback down to the controller/page. This ensures the underlying texture handle from `media_kit` does not recreate, avoiding frame drop or texture reload.
- **Alternatives considered**:
  - *Creating a new Video widget in a new Route*: Can cause slight texture re-initialization flicker. Using an in-place `Stack` overlay in `PrivateMediaPlayerPage` or `AppShell` keeps the widget tree alive without re-initializing the texture.

### 3. Keyboard & Gesture Handling
- **Decision**: Use a dedicated `Focus` widget with an active `FocusNode` wrapping `PrivatePlayerView` and `onKeyEvent` / `KeyboardListener`.
  - `LogicalKeyboardKey.keyF` / `LogicalKeyboardKey.enter`: toggle fullscreen.
  - `LogicalKeyboardKey.escape`: if fullscreen, exit fullscreen.
  - `LogicalKeyboardKey.space`: toggle play/pause.
  - `LogicalKeyboardKey.arrowLeft` / `arrowRight`: seek backward/forward 10s.
  - Double-tap via `GestureDetector.onDoubleTap` toggles fullscreen.

## Risks / Trade-offs

- [Risk] If the user exits native fullscreen via macOS window green button, the in-app fullscreen state might get out of sync.
  → **Mitigation**: Detect window size changes or provide an explicit `[退出全屏]` button, and support `Esc` key at all times.
- [Risk] Keyboard events may conflict with text input if an input field is active.
  → **Mitigation**: Only respond to shortcuts when `PrivatePlayerView` has direct focus and no modal dialog is active.
