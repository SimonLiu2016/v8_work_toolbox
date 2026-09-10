## Purpose

Manages the desktop multi-window presentation for the Notebook tool, ensuring centered positioning, proper dimensions, and an immersive titlebar appearance matching the main window.

## ADDED Requirements

### Requirement: Centered sub-window initialization
The system SHALL center the newly created notebook sub-window on the screen with a default size of 1200x750 (minimum 960x640), avoiding opening at the bottom-left coordinate origin.

#### Scenario: Open notebook window
- **WHEN** user clicks the Notebook tool in the sidebar or tools grid
- **THEN** the independent notebook window opens centered on the user's display with dimensions 1200x750.

### Requirement: Immersive borderless window styling
The system SHALL apply macOS immersive transparent titlebar styling to the notebook sub-window, hiding the native window title bar while enabling window dragging by background.

#### Scenario: Inspect notebook window style
- **WHEN** the notebook sub-window is launched
- **THEN** the window presents a full-size content view without a native gray titlebar, matching the main application shell's design.
