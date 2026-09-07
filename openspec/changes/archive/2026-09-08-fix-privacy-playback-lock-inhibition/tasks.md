## 1. Security Service Playback Inhibitor & Idle Logic

- [x] 1.1 Add `PlaybackInhibitor` registration (`registerPlaybackInhibitor` / `unregisterPlaybackInhibitor`) and suppression check to `PrivacySecurityService`
- [x] 1.2 Add unit tests for playback inhibitor preventing auto-lock and resuming countdown once stopped

## 2. Activity Tracking & Media Player Coordination

- [x] 2.1 Wrap `PrivateMediaPlayerPage` in a translucent `Listener` to capture pointer hover, scroll, and click events for activity refresh
- [x] 2.2 Connect `PrivatePlayerController.isPlaying` with `PrivacySecurityService` lock inhibitor
- [x] 2.3 Auto-pause media playback when `PrivacySecurityService` enters locked state

## 3. Verification & Testing

- [x] 3.1 Run `flutter test test/private_player_test.dart` and verify all security/player tests pass
- [x] 3.2 Run `flutter analyze` and project-wide `flutter test` to ensure clean build
