# light-and-system-theme-adaptation Specification

## Purpose
Provides a clean macOS-native light theme for lookup cards and enables automatic appearance following based on the system theme mode.
## Requirements
### Requirement: Native light theme for popover cards
The system SHALL support a light theme color palette with crisp white background, subtle border, diffused elevation shadow, and dark legible typography.

#### Scenario: Display popover in light mode
- **WHEN** the system or application theme is set to light
- **THEN** the popover renders with a clean white card background, light border (`#E2E8F0`), and dark text (`#0F172A`).

### Requirement: System theme synchronization
The popover and application views SHALL automatically adapt their appearance to match the current macOS system appearance (light or dark).

#### Scenario: System switches from dark to light mode
- **WHEN** macOS transitions from dark mode to light mode
- **THEN** the popover dynamically switches its theme tokens without requiring an application restart.

