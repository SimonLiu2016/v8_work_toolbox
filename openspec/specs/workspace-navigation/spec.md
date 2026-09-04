## Purpose

Provides a cohesive three-column workspace navigation architecture, immersive borderless window presentation on macOS, and reliable menu bar status item presence.

## Requirements

### Requirement: Immersive borderless window layout
The application window on macOS SHALL display without the standard grey titlebar strip by configuring transparent titlebar and full-size content view, while retaining standard window control traffic lights overlaid seamlessly on the dark workspace canvas.

#### Scenario: Window appearance on launch
- **WHEN** the application window is created and displayed
- **THEN** the native grey titlebar is invisible, content extends to the top window edge, and window control buttons (close, minimize, zoom) float directly over the dark sidebar area with proper padding.

### Requirement: Activity bar and tool panel split navigation
The workspace SHALL divide navigation into an Activity Bar and a Tool Panel, and the content container SHALL lazily instantiate tool views on demand so tools are only mounted when navigated to by the user.

#### Scenario: Switching tool categories
- **WHEN** user clicks a category icon in the Activity Bar
- **THEN** the Tool Panel immediately switches to show only the tools assigned to that category, with search filtering scoped to the active view.

#### Scenario: Collapsing tool panel
- **WHEN** user toggles panel collapse or double-clicks the separator
- **THEN** the Tool Panel folds into an icon-only compact mode (~50px) to give maximum screen width to the tool content area.

#### Scenario: Lazy tool mounting
- **WHEN** the application starts up
- **THEN** only the initially active tool view is instantiated in the content stack, preventing unselected heavy tools from blocking startup frames.

### Requirement: Status bar tray presence and interactions
The application SHALL maintain a permanent status item in the macOS system menu bar with an explicit 18x18 template icon, supporting left-click toggle of the main window and a secondary menu for quitting.

#### Scenario: Clicking menu bar icon when hidden
- **WHEN** user clicks the menu bar tray icon while the main application window is hidden
- **THEN** the application activates and brings the main window into frontmost focus.

#### Scenario: Clicking menu bar icon when active
- **WHEN** user clicks the menu bar tray icon while the main application window is already active and frontmost
- **THEN** the main window hides to the background without terminating the process.
