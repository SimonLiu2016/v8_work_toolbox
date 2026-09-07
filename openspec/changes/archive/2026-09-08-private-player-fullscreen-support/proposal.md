## Why

The current private media player (`PrivatePlayerView`) only operates embedded inside the `TabBarView` and `AppShell` layout. Users lack a dedicated fullscreen toggle button, double-click gestures, and keyboard shortcuts (`F`, `Escape`, `Space`) to enter immersive fullscreen mode, which restricts viewing experience on desktop displays.

## What Changes

- Add a dedicated Fullscreen toggle button (`Icons.fullscreen_rounded` / `Icons.fullscreen_exit_rounded`) on the right side of the player control bar.
- Add double-click mouse gesture support (`GestureDetector.onDoubleTap`) on the video viewport to quickly toggle fullscreen mode.
- Add desktop keyboard shortcuts support via `Focus` / `Shortcuts` / `Actions` / `KeyboardListener`:
  - `F` / `Enter`: Toggle fullscreen mode.
  - `Escape`: Exit fullscreen mode.
  - `Space`: Toggle play/pause.
  - `ArrowLeft` / `ArrowRight`: Seek backward/forward 10 seconds.
- Provide combined fullscreen presentation:
  - **In-App Immersive Overlay**: The player view expands to occupy 100% of the window area, hiding the AppShell navigation sidebar and the top category tabs.
  - **macOS Window Native Fullscreen**: Simultaneously coordinate with `media_kit_video`'s `defaultEnterNativeFullscreen()` and `defaultExitNativeFullscreen()` to enter/exit macOS native window full screen.
- Maintain auto-hiding control overlays (3s timer) and subtitle visibility throughout fullscreen transitions without disrupting playback or audio pitch.

## Capabilities

### Modified Capabilities
- `private-media-player`: Enhance fullscreen presentation requirements with double-click gestures, control bar toggle button, keyboard shortcuts (`F`, `Esc`, `Space`, Arrows), and native window fullscreen coordination.

## Impact

- Affected files:
  - `lib/tools/private_player/ui/private_player_view.dart`: Add fullscreen button, double-click handler, keyboard listener, and fullscreen state handling.
  - `lib/tools/private_player/ui/private_media_player_page.dart`: Provide full-window immersive container/route when player is in fullscreen mode.
- Dependencies: Uses `defaultEnterNativeFullscreen()` and `defaultExitNativeFullscreen()` from existing `media_kit_video` package.
