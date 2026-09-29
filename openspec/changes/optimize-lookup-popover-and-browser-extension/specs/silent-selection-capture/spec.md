## Purpose

Enables reliable, zero-leak selection capture across macOS applications and silent background note saving without focus theft or character pollution.

## ADDED Requirements

### Requirement: Leak-free text selection extraction
The system SHALL capture text currently selected by the user without leaking hotkey modifier characters (`\D`, `ß`) into the active document or search input field.

#### Scenario: Selection capture via Accessibility API
- **WHEN** the user selects text in an Accessibility-supported application (e.g. Safari, TextEdit, Pages) and presses `⌥D` or `⌥S`
- **THEN** the system reads the selection value directly via Accessibility attributes (`kAXSelectedTextAttribute`) without altering system clipboard or sending simulated keystrokes.

#### Scenario: Fallback keystroke simulation without modifier leak
- **WHEN** the active application does not support Accessibility selection extraction and system falls back to simulated copy
- **THEN** the system releases or isolates the Option modifier key before issuing `⌘C` so that no dead characters (such as `\D` or `ß`) are typed into input fields.

### Requirement: Silent note capture with non-intrusive notification
The system SHALL save captured notes silently in the background when `⌥S` is pressed, without bringing the main window to the front.

#### Scenario: Background note capture
- **WHEN** the user presses `⌥S` on selected text in any supported application
- **THEN** the note is parsed, markdown formatted, and committed to the designated notebook in the background while displaying a macOS native notification or HUD banner upon completion.

#### Scenario: Missing default notebook guidance
- **WHEN** no default notebook is configured for capture
- **THEN** the system prompts the user to select or designate a default notebook once, persisting the choice for subsequent silent captures.
