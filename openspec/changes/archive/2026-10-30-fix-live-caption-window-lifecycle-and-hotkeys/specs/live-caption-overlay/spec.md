## Purpose

Defines the presentation, window lifecycle, and global hotkey control requirements for the macOS live caption floating overlay, including native window transparency, non-destructive window hiding/showing, and instantaneous speaker switching.

## ADDED Requirements

### Requirement: Native Floating Window Transparency and User Opacity Setting
The macOS live caption overlay window SHALL configure the native NSWindow to be transparent by setting `isOpaque = false`, `backgroundColor = NSColor.clear`, and hiding standard window traffic light buttons (close, minimize, zoom). The overlay toolbar SHALL provide an opacity selector allowing users to cycle through background opacity levels (e.g., 35%, 50%, 70%, 90%), persisting the preference to local settings.

#### Scenario: Subtitle overlay renders with true translucent background
- **WHEN** the live caption overlay window is displayed over desktop content
- **THEN** underlying desktop content or windows are softly visible through the translucent caption container without being blocked by an opaque solid black background.

#### Scenario: User adjusts background opacity
- **WHEN** the user clicks the opacity toggle button in the caption toolbar
- **THEN** the overlay background opacity immediately updates to the next preset level and persists across sessions.

### Requirement: Non-destructive Window Lifecycle Preservation
The live caption window SHALL handle the window close action by invoking `windowManager.hide()` rather than destroying the native NSWindow, preserving the bidirectional `WindowMethodChannel` pairing. Re-opening the caption window from the main window SHALL unhide and focus the existing window instance without allocating a redundant window or triggering channel limit errors.

#### Scenario: Re-opening the caption overlay after closing
- **WHEN** the user closes the caption overlay window and subsequently clicks "打开字幕窗" in the main window
- **THEN** the existing caption overlay window is unhidden and brought to front at its configured size and position without window distortion, traffic light button leakage, or IPC channel registration failure.

#### Scenario: Subtitles continue delivering on re-opened window
- **WHEN** the user re-opens the caption overlay window while speech transcription is running
- **THEN** newly transcribed subtitle segments are received and rendered in real time through the intact IPC bridge.

### Requirement: Dedicated Hotkey Channel and Instantaneous Speaker Switching
Global hotkeys (⌥1, ⌥2, ⌥3 for speakers 1-3, ⌥T for toggle) SHALL communicate over a dedicated native method channel (`v8_work_toolbox/live_caption_hotkeys`) independent of the subwindow RPC channel. Switching the active speaker via hotkey or overlay button SHALL immediately update the coordinator state, assign the new speaker slot to any currently transcribing in-flight speech segment, and display a colored speaker badge in the subtitle view.

#### Scenario: Pressing speaker hotkey switches active speaker immediately
- **WHEN** the user presses ⌥2 while speech is being recognized
- **THEN** the active speaker changes to Speaker 2, the overlay toolbar speaker button 2 is highlighted, and subsequent (as well as in-flight) transcribed segments display the Speaker 2 identity.
