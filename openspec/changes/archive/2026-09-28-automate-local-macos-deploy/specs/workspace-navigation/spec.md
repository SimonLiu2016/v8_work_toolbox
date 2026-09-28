## MODIFIED Requirements

### Requirement: Status bar tray presence and interactions
The application SHALL maintain a permanent status item in the macOS system menu bar using `NSStatusItem.squareLength` and a dedicated template tray icon (without variable text labels to avoid notch or overflow truncation), supporting left-click toggle of the main window and right-click secondary menu for quick actions and quitting. Application shutdown SHALL be reachable from multiple entry points (window close, tray quit) and SHALL also run its cleanup when the process receives an OS termination signal, so that a signal-driven exit leaves no orphaned child processes.

#### Scenario: Window appearance on launch
- **WHEN** the application window is created and displayed
- **THEN** the native grey titlebar is invisible, content extends to the top window edge, and window control buttons (close, minimize, zoom) float directly over the dark sidebar area with proper padding.

#### Scenario: Switching tool categories
- **WHEN** user clicks a category icon in the Activity Bar
- **THEN** the Tool Panel immediately switches to show only the tools assigned to that category, with search filtering scoped to the active view.

#### Scenario: Collapsing tool panel
- **WHEN** user toggles panel collapse or double-clicks the separator
- **THEN** the Tool Panel folds into an icon-only compact mode (~50px) to give maximum screen width to the tool content.

#### Scenario: Lazy tool mounting
- **WHEN** the application starts up
- **THEN** only the initially active tool view is instantiated in the content stack, preventing unselected heavy tools from blocking startup frames.

#### Scenario: Clicking menu bar icon when hidden
- **WHEN** user clicks the menu bar tray icon while the main application window is hidden
- **THEN** the application activates and brings the main window into frontmost focus.

#### Scenario: Clicking menu bar icon when active
- **WHEN** user clicks the menu bar tray icon while the main application window is already active and frontmost
- **THEN** the main window hides to the background without terminating the process.

#### Scenario: Right-clicking menu bar icon
- **WHEN** user right-clicks the menu bar tray icon
- **THEN** the application displays a contextual popup menu containing items to open the main window and quit the application.

#### Scenario: Menu bar theme adaptation
- **WHEN** user switches between macOS Light Mode and Dark Mode
- **THEN** the menu bar template icon automatically adapts contrast without inverted colors or visual artifacts.

#### Scenario: Termination signal runs the same cleanup as tray quit
- **WHEN** the application process receives an OS termination signal while running
- **THEN** the application runs the same child-process cleanup as the tray quit path, then exits
- **AND** no orphaned child process remains after the application process has exited.
