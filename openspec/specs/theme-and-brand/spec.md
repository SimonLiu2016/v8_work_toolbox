## Purpose

Defines the neutral dark grey color token hierarchy and production application icon assets for V8 Work Toolbox.
## Requirements
### Requirement: Neutral dark grey color token system
The theme system SHALL implement a neutral dark grey palette without excessive black or blue-tint bias, maintaining clear visual depth across Activity Bar (#333333), Panel (#252526), Content area (#1E1E1E), and Card surfaces (#2D2D30).

#### Scenario: Visual layer contrast verification
- **WHEN** the application renders the main workspace
- **THEN** borders, cards, panels, and activity bar distinct layers are distinguishable under standard macOS display profiles with WCAG AA compliance for text labels.

### Requirement: Dedicated V8 brand icon assets
The application bundle SHALL include custom high-resolution macOS application icons, in-app brand logos, and menu bar template icons featuring the modern VS Code-style origami Möbius ribbon V8 logo, replacing legacy mechanical placeholders.

#### Scenario: Dock and Launchpad icon presentation
- **WHEN** the application is installed and launched on macOS
- **THEN** the Dock and App Switcher display the custom VS Code-style flowing ribbon V8 icon with standard macOS squircle continuous curvature without rectangular background clipping.

#### Scenario: In-app brand presentation
- **WHEN** the user views the ActivityBar or About dialog
- **THEN** the application renders the matching clean origami ribbon V8 brand symbol seamlessly integrated with the dark UI theme.

