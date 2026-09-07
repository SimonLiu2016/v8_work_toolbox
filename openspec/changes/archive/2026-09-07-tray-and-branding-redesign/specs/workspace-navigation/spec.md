## MODIFIED Requirements

### Requirement: Status bar tray presence and interactions
The application SHALL maintain a permanent status item in the macOS system menu bar using `NSStatusItem.squareLength` and a dedicated template tray icon (without variable text labels to avoid notch or overflow truncation), supporting left-click toggle of the main window and right-click secondary menu for quick actions and quitting.

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
