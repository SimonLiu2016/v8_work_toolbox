## Purpose

Provides a browser companion extension delivering first-level context menu items with V8 branding, icon display, and in-page selection actions.

## ADDED Requirements

### Requirement: First-level browser context menu with V8 branding
The browser companion extension SHALL register a first-level context menu item with the V8 brand icon and nested submenus in Chromium-based browsers (Chrome, Edge, Brave, etc.).

#### Scenario: User opens context menu on selected web text
- **WHEN** the user selects text on any web page and right-clicks
- **THEN** a first-level context menu labeled "V8 Work Toolbox" appears with the V8 icon, containing submenus: "查词 (Lookup in V8)" and "保存笔记 (Save to V8 Notes)".

#### Scenario: Trigger lookup from context menu
- **WHEN** the user clicks "查词 (Lookup in V8)"
- **THEN** the word/selection is immediately passed to V8's lookup service or displayed in an in-page popover bubble.

#### Scenario: Trigger note save from context menu
- **WHEN** the user clicks "保存笔记 (Save to V8 Notes)"
- **THEN** the selection along with page URL, title, and HTML structure is sent to V8 note capture service silently.

### Requirement: Desktop app communication bridge
The browser companion extension SHALL establish communication with the desktop V8 Work Toolbox application via deep link protocol (`v8toolbox://`) or local loopback HTTP service.

#### Scenario: Deep link execution
- **WHEN** a browser context menu action is invoked
- **THEN** the extension dispatches the query payload to the V8 desktop application via registered custom URL scheme or local API bridge, bringing up the lookup popover or saving note.
