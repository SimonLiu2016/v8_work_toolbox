## Why

When watching a video or listening to audio in the privacy media player, users remain physically idle without touching the mouse or keyboard. The privacy space's 5-minute idle timer currently misinterprets this as user absence, abruptly popping up the 6-digit PIN lock screen and tearing down the player view in the middle of playback.

## What Changes

- Add a **Playback Lock Inhibitor** to `PrivacySecurityService`: auto-lock timer is suppressed while media is actively playing.
- Add **User Gesture & Activity Tracking** across the privacy space container: mouse movement, scrolling, clicks, and keyboard strokes reset the idle activity timer.
- Add **Auto-pause on Manual Lock**: when the user explicitly locks the privacy space via the lock button, active media playback is immediately paused to prevent sound leakage.
- Restore the idle countdown only after media playback is paused or completed.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `privacy-space`: Inhibit auto-lock when media is actively playing; refresh activity timestamp on user interaction; pause media on manual lock.
- `private-media-player`: Expose playback activity/state to the privacy security service.

## Impact

- `lib/services/privacy_security_service.dart`: Added `registerInhibitor` / `isPlaying` check to idle timer check.
- `lib/shell/app_shell.dart` and `lib/tools/private_player/ui/private_media_player_page.dart`: Wrap privacy view in `Listener` for activity tracking; trigger pause on lock.
- `lib/tools/private_player/services/private_player_controller.dart`: Expose active playing state to lock inhibitor.
