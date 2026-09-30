## Purpose

Defines the neutral dark grey color token hierarchy and production application icon assets for V8 Work Toolbox.
## Requirements
### Requirement: Neutral dark grey color token system
The theme system SHALL implement a unified dynamic token hierarchy supporting both light and dark modes. In dark mode, it SHALL maintain the neutral dark grey palette across Activity Bar (#333333), Sidebar (#252526), Content area (#1E1E1E), and Card surfaces (#2D2D30). In light mode, it SHALL render a clean, high-contrast macOS/Apple palette across Window/Content (#F8FAFC / #FFFFFF), Sidebar (#F1F5F9), Cards (#FFFFFF), and selected accents. All surfaces and text tokens SHALL dynamically adapt to the active theme mode via inherited context resolution.

#### Scenario: Visual layer contrast verification
- **WHEN** the application renders the main workspace in either light or dark mode
- **THEN** borders, cards, panels, inputs, and activity bar layers are visually distinct and text labels maintain WCAG AA compliance against their respective backgrounds.

### Requirement: Dedicated V8 brand icon assets
The application bundle SHALL include custom high-resolution macOS application icons, in-app brand logos, and menu bar template icons featuring the modern VS Code-style origami Möbius ribbon V8 logo, replacing legacy mechanical placeholders.

#### Scenario: Dock and Launchpad icon presentation
- **WHEN** the application is installed and launched on macOS
- **THEN** the Dock and App Switcher display the custom VS Code-style flowing ribbon V8 icon with standard macOS squircle continuous curvature without rectangular background clipping.

#### Scenario: In-app brand presentation
- **WHEN** the user views the ActivityBar or About dialog
- **THEN** the application renders the matching clean origami ribbon V8 brand symbol seamlessly integrated with the dark UI theme.

### Requirement: Elevated button contrast default
Elevated buttons rendered with the theme accent background SHALL default to high-contrast white text and icons under the dark theme, ensuring all primary action buttons remain readable.

#### Scenario: Elevated button default contrast
- **WHEN** an elevated button is rendered in the dark theme
- **THEN** its text and icon foreground colors contrast against the accent background with visible white foreground.

### Requirement: Dynamic theme inheritance for reusable components
Common UI components (including list items, cards, text fields, buttons, and badges) SHALL resolve their background, border, hover, and selection colors dynamically from the active theme context rather than compile-time static constants.

This dynamic resolution SHALL apply not only to the shared component library but to **every** tool view, dialog, drawer, and page surface rendered inside the application — including the internal views of individual tools (operations, password vault, private media player, notebook, disk slimmer, unattended approver, vocabulary book, AI assistant, lookup panel) and the standalone entry-point tools. A widget rendered in light mode MUST NOT paint a color derived from a dark-mode constant, and vice versa.

The dynamic set SHALL cover the accent color series as well as the neutral surface series: `accentText`, `accentSolid`, `onAccentSolid`, and `accentSubtle` SHALL resolve from the active theme context, so that selected-state labels, tab labels, option tiles, status badges, and accent-colored body text all flip with the mode without per-page special-casing.

#### Scenario: No static dark-mode token reachable from widget code
- **WHEN** the application's widget source tree is scanned for compile-time references to the static dark-mode color tokens (`AppTheme.bgCard`, `AppTheme.textPrimary`, `AppTheme.borderSubtle`, and their siblings)
- **THEN** no widget-layer file contains such a reference, the only surviving references being inside the theme definition module that supplies both the light and dark presets.

#### Scenario: No static accent token reachable from widget code
- **WHEN** the widget source tree is scanned for compile-time references to the static accent constants (`AppTheme.accent`, `AppTheme.accentLight`, `AppTheme.accentDark`, `AppTheme.accentSubtle`)
- **THEN** no widget-layer file contains such a reference
- **AND** the same source guard enforces this rule as enforces the neutral-token rule.

#### Scenario: Tool page interior follows the theme
- **WHEN** a user switches to light mode and opens any tool page (for example the operations tool, the password vault, or the private media player)
- **THEN** the tool's internal surfaces — section containers, tables, form inputs, empty-state placeholders, dividers, status labels and chips — render light-mode surface, border, and text colors, with no dark-grey card, faint-grey text, or near-invisible border remaining.

#### Scenario: Scaffold background inherited from the theme
- **WHEN** any tool page presents its root scaffold
- **THEN** the scaffold background derives from the active theme's scaffold background color rather than an explicitly supplied dark-mode constant, so a future tool page added without any color code still renders correctly in both modes.

#### Scenario: List item selection and hover in light mode
- **WHEN** the user hovers over or selects a tool item in the "All Tools" panel while in light mode
- **THEN** the item background displays the light mode hover/selected tint (#F8FAFC / #E2E8F0) and the title text renders high-contrast dark text (#0F172A) instead of dark grey or faint grey.

#### Scenario: Modal and dialog presentation in light mode
- **WHEN** the user opens settings, log viewer, or tool pages in light mode
- **THEN** the dialog and page backgrounds render the light surface color and child controls inherit light-mode input and border styling.

#### Scenario: Migration preserves the original color role
- **WHEN** a color reference is migrated from a static constant to a theme token
- **THEN** the three roles — solid fill, foreground text, and translucent wash — remain distinct, and none is substituted for another
- **AND** a widget that previously painted a translucent wash still paints a translucent derivative of the corresponding solid, not the solid value and not the text value.

### Requirement: High-contrast typography across theme modes
All typography definitions and text elements SHALL automatically contrast with the container background, rendering high-contrast dark text in light mode and high-contrast light text in dark mode.

#### Scenario: Text legibility verification
- **WHEN** body, title, headline, or secondary text is rendered in light mode
- **THEN** the text color evaluates to high-contrast dark tokens (#0F172A / #475569) without faded or washed-out appearance.

### Requirement: Dynamic global theme mode switching
The application SHALL support dynamic theme mode switching between system follow (`ThemeMode.system`), explicit light mode (`ThemeMode.light`), and explicit dark mode (`ThemeMode.dark`) across the main workspace and all sub-windows without requiring an application restart.

#### Scenario: Switching theme mode from settings
- **WHEN** user selects "浅色模式" (Light Mode) or "深色模式" (Dark Mode) in SettingsDialog
- **THEN** all open windows (main window, notebook, password vault, ops tool, and lookup panel) immediately re-render using the corresponding color palette and contrast rules.

#### Scenario: Follow system appearance
- **WHEN** user selects "跟随系统" (Follow System) in SettingsDialog
- **THEN** the application automatically tracks the macOS system appearance changes between light and dark modes in real time.

