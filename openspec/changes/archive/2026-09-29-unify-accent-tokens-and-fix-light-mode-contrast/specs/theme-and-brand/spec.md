## MODIFIED Requirements

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
