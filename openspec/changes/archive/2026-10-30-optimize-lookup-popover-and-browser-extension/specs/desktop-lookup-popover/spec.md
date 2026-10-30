## Purpose

Provides a lightweight, borderless, non-activating floating lookup popover that appears near the cursor for instant dictionary and AI lookup without disrupting ongoing user work.

## ADDED Requirements

### Requirement: Cursor-anchored floating popover
The system SHALL display the floating lookup popover directly adjacent to the current mouse cursor location upon invocation, adjusting automatically to avoid screen boundaries.

#### Scenario: Trigger lookup with mouse at arbitrary position
- **WHEN** the user triggers lookup (`⌥D` or service) while reading text
- **THEN** the popover window opens adjacent to the mouse pointer on the active screen display, without flashing or jumping to the top-left screen corner.

#### Scenario: Trigger lookup near display edge
- **WHEN** the mouse cursor is located near the bottom or right edge of the screen display
- **THEN** the popover flips positioning upward or to the left to remain fully visible within display boundaries.

### Requirement: Non-activating borderless popover window
The floating lookup popover SHALL use a borderless, floating window style without macOS titlebar controls (close, minimize, zoom traffic lights) and without bringing the main application window to the foreground.

#### Scenario: Lookup does not interrupt main window
- **WHEN** the user triggers lookup from any external application
- **THEN** the main application window remains hidden or in its previous state, and no screen flashing occurs.

#### Scenario: Popover appearance
- **WHEN** the lookup popover is displayed
- **THEN** it renders with rounded card corners, subtle drop shadow, search input at the top without traffic-light overlap, single clear button, and dictionary result view.

### Requirement: Dismissal on blur and escape
The system SHALL dismiss the lookup popover immediately when the user presses `Escape` or clicks outside the popover window.

#### Scenario: User presses Escape key
- **WHEN** the popover is active and user presses `Escape`
- **THEN** the popover closes silently and focus returns to the previously active application.

#### Scenario: User clicks outside popover
- **WHEN** the popover is active and user clicks anywhere outside its frame
- **THEN** the popover dismisses without requiring explicit window close button interactions.
