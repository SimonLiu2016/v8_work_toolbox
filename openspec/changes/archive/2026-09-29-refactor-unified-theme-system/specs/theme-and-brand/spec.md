## MODIFIED Requirements

### Requirement: Neutral dark grey color token system
The theme system SHALL implement a unified dynamic token hierarchy supporting both light and dark modes. In dark mode, it SHALL maintain the neutral dark grey palette across Activity Bar (#333333), Sidebar (#252526), Content area (#1E1E1E), and Card surfaces (#2D2D30). In light mode, it SHALL render a clean, high-contrast macOS/Apple palette across Window/Content (#F8FAFC / #FFFFFF), Sidebar (#F1F5F9), Cards (#FFFFFF), and selected accents. All surfaces and text tokens SHALL dynamically adapt to the active theme mode via inherited context resolution.

#### Scenario: Visual layer contrast verification
- **WHEN** the application renders the main workspace in either light or dark mode
- **THEN** borders, cards, panels, inputs, and activity bar layers are visually distinct and text labels maintain WCAG AA compliance against their respective backgrounds.

## ADDED Requirements

### Requirement: Dynamic theme inheritance for reusable components
Common UI components (including list items, cards, text fields, buttons, and badges) SHALL resolve their background, border, hover, and selection colors dynamically from the active theme context rather than compile-time static constants.

#### Scenario: List item selection and hover in light mode
- **WHEN** the user hovers over or selects a tool item in the "All Tools" panel while in light mode
- **THEN** the item background displays the light mode hover/selected tint (#F8FAFC / #E2E8F0) and the title text renders high-contrast dark text (#0F172A) instead of dark grey or faint grey.

#### Scenario: Modal and dialog presentation in light mode
- **WHEN** the user opens settings, log viewer, or tool pages in light mode
- **THEN** the dialog and page backgrounds render the light surface color and child controls inherit light-mode input and border styling.

### Requirement: High-contrast typography across theme modes
All typography definitions and text elements SHALL automatically contrast with the container background, rendering high-contrast dark text in light mode and high-contrast light text in dark mode.

#### Scenario: Text legibility verification
- **WHEN** body, title, headline, or secondary text is rendered in light mode
- **THEN** the text color evaluates to high-contrast dark tokens (#0F172A / #475569) without faded or washed-out appearance.
