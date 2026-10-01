## ADDED Requirements

### Requirement: Deep-link lookup popover does not activate the host application
Opening a lookup popover in response to a browser deep link SHALL NOT bring the desktop application — and with it the main window — to the foreground. The popover is a lightweight bubble over whatever the user is reading, not an application switch.

#### Scenario: Deep link from the browser does not surface the main window
- **WHEN** the user triggers "问 AI 深度解析" or "在桌面端打开" in the browser companion while the desktop app is in the background
- **THEN** the lookup popover appears, and the desktop app's main window is not brought forward or activated.

#### Scenario: The popover remains usable without activating the app
- **WHEN** the popover is shown this way
- **THEN** it is visible and interactive over the browser, and the browser does not lose foreground status.

#### Scenario: Popover still appears even though the app is not activated
- **WHEN** the popover is created without activating the application
- **THEN** the popover is still shown — suppressing the activation does not suppress the window.

#### Scenario: Other entry points behave the same way
- **WHEN** the lookup popover is opened by hotkey, by macOS service, or by the extension's right-click fallback
- **THEN** it likewise does not activate the desktop application, since all entry points share one launcher.

#### Scenario: Other sub-windows are unaffected
- **WHEN** the user opens a notebook, single-note, ops tool, or password vault window
- **THEN** that window activates the application as before — for those, activation is the expected result of an explicit open request. This requirement is scoped to the lookup popover.
