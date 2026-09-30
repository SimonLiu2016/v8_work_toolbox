## ADDED Requirements

### Requirement: Dynamic global theme mode switching
The application SHALL support dynamic theme mode switching between system follow (`ThemeMode.system`), explicit light mode (`ThemeMode.light`), and explicit dark mode (`ThemeMode.dark`) across the main workspace and all sub-windows without requiring an application restart.

#### Scenario: Switching theme mode from settings
- **WHEN** user selects "浅色模式" (Light Mode) or "深色模式" (Dark Mode) in SettingsDialog
- **THEN** all open windows (main window, notebook, password vault, ops tool, and lookup panel) immediately re-render using the corresponding color palette and contrast rules.

#### Scenario: Follow system appearance
- **WHEN** user selects "跟随系统" (Follow System) in SettingsDialog
- **THEN** the application automatically tracks the macOS system appearance changes between light and dark modes in real time.
