## 1. Fullscreen State & Controls Integration

- [x] 1.1 Add fullscreen state management and callback hooks in `PrivatePlayerView` and `PrivatePlayerController`
- [x] 1.2 Add `[全屏 / 退出全屏]` toggle button to the bottom control bar in `PrivatePlayerView`
- [x] 1.3 Add double-click gesture handler on the video display viewport to toggle fullscreen

## 2. Desktop Keyboard Shortcuts

- [x] 2.1 Implement `Focus` node and keyboard listeners for `F` / `Enter` (fullscreen toggle) and `Escape` (exit fullscreen)
- [x] 2.2 Implement playback keyboard shortcuts for `Space` (play/pause) and `ArrowLeft` / `ArrowRight` (seek -10s / +10s)

## 3. In-App Immersive View & Native Window Coordination

- [x] 3.1 Implement full-window presentation in `PrivateMediaPlayerPage` to hide AppShell sidebar and top navigation tabs when fullscreen is active
- [x] 3.2 Coordinate with `defaultEnterNativeFullscreen()` and `defaultExitNativeFullscreen()` from `media_kit_video`
- [x] 3.3 Ensure auto-hiding controls and subtitle font size adapt seamlessly in fullscreen mode

## 4. Verification & Testing

- [x] 4.1 Add unit tests in `test/private_player_test.dart` verifying fullscreen state transitions and controller callbacks
- [x] 4.2 Run `flutter analyze` and `flutter test` to ensure zero warnings or errors
