## Purpose

Defines the live caption overlay presentation contract, specifying native window transparency driving, dynamic window opacity adjustment, and visual feedback for subtitle recording states.

## ADDED Requirements

### Requirement: Native Floating Window Transparency and Window Opacity Driving
The live caption overlay system SHALL ensure the native macOS floating window is non-opaque (`isOpaque = false`, `backgroundColor = NSColor.clear`) upon being opened or unhidden from the host process. When the user adjusts the opacity selector in the overlay toolbar (cycling 35%, 50%, 70%, 90%), the system SHALL apply the selected opacity directly to the native window compositor (`windowManager.setOpacity`) and persist the value to local configuration.

#### Scenario: User toggles overlay opacity
- **WHEN** the user clicks the opacity adjustment button in the live caption toolbar
- **THEN** the floating window's native opacity immediately changes to the selected level, allowing underlying desktop applications or editors to be visible through the floating window at the chosen transparency.

#### Scenario: Subtitle overlay launched from host
- **WHEN** the user opens or re-opens the live caption overlay from the main window
- **THEN** the host process triggers native window styling to guarantee transparent background and absence of native traffic light controls.

### Requirement: Responsive Subtitle Recording State Feedback
The live caption overlay toolbar SHALL reflect the current subtitle recording state in real time based on the state pushed from the host coordinator. When recording is active, the recording button SHALL display an active recording indicator (e.g. stop circle / active recording badge) with a tooltip indicating recording is ongoing; when recording is inactive, it SHALL display an idle state icon with a tooltip indicating start of recording.

#### Scenario: Recording is active
- **WHEN** subtitle recording is enabled either from the floating overlay or the main window
- **THEN** the overlay toolbar recording button updates its visual state to indicate active recording and provides an action to stop recording.

#### Scenario: Recording is stopped
- **WHEN** subtitle recording is stopped
- **THEN** the overlay toolbar recording button returns to the idle icon state and provides an action to begin recording.
