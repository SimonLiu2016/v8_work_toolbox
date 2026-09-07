## Context

See `proposal.md` for background. The current `PrivacySecurityService` monitors a 15-second tick against `_lastActiveTime`. Because media consumption is passive and no pointer listeners existed inside the privacy view, the idle threshold triggers during playback.

## Goals / Non-Goals

**Goals:**
- Zero interruptions during continuous video or audio playback.
- Instant user-activity recognition via pointer hover/tap events.
- Sound privacy protection: immediate playback pause upon manual or idle lock.
- Clean decoupling between `PrivacySecurityService` and `PrivatePlayerController`.

**Non-Goals:**
- Altering PIN hashing or encryption storage.
- Preventing OS-level sleep (macOS screensaver/sleep settings remain untouched).

## Decisions

### Decision 1: Callable/Listenable Lock Inhibitor in PrivacySecurityService
`PrivacySecurityService` exposes a registration mechanism:
```dart
typedef PlaybackInhibitor = bool Function();
void registerPlaybackInhibitor(PlaybackInhibitor inhibitor);
void unregisterPlaybackInhibitor(PlaybackInhibitor inhibitor);
```
During the periodic idle check:
```dart
final isAnyInhibited = _playbackInhibitors.any((fn) => fn());
if (isAnyInhibited) {
  _lastActiveTime = DateTime.now(); // Keep active
  return;
}
```
*Rationale*: This decouples the security service from specific player implementations and allows multiple media players or long-running private tasks (like AI batch transcription) to suppress auto-lock.

### Decision 2: Pointer Event Listener in Privacy View
Wrap `PrivateMediaPlayerPage` (or the privacy branch in `AppShell`) in a Flutter `Listener`:
```dart
Listener(
  behavior: HitTestBehavior.translucent,
  onPointerHover: (_) => PrivacySecurityService.instance.recordActivity(),
  onPointerDown: (_) => PrivacySecurityService.instance.recordActivity(),
  onPointerSignal: (_) => PrivacySecurityService.instance.recordActivity(),
  child: ...,
)
```
*Rationale*: `HitTestBehavior.translucent` captures mouse hovering and trackpad gestures without interfering with child interactive elements (like scrub sliders and volume controls).

### Decision 3: Reactive Auto-Pause on Lock
In `PrivateMediaPlayerPageState`, listen to `PrivacySecurityService.instance.isUnlockedNotifier`:
```dart
_privacyService.isUnlockedNotifier.addListener(_onPrivacyLockChanged);

void _onPrivacyLockChanged() {
  if (!_privacyService.isUnlocked && _playerController.isPlaying) {
    _playerController.pause();
  }
}
```
*Rationale*: Ensures audio never leaks in the background when the user locks the privacy space.

## Risks / Trade-offs

- **[Risk] Long video left playing indefinitely unattended**
  → *Mitigation*: Once video finishes and enters paused/completed state, the inhibitor returns `false` and the 5-minute idle countdown automatically takes effect.
