## Purpose

Provides a Bob/PopClip-style floating action icon that automatically appears next to the cursor when text is selected in external desktop applications such as PDF readers and Word processors.

## ADDED Requirements

### Requirement: Floating action icon on desktop text selection
The system SHALL monitor text selection changes across macOS applications and display a lightweight, non-activating floating action button near the cursor.

#### Scenario: Text selected in PDF reader or Word
- **WHEN** the user selects text and releases the left mouse button in Preview, Microsoft Word, or a text editor
- **THEN** a compact floating icon (V8 emblem) appears within 24 pixels of the cursor without stealing focus from the host application.

#### Scenario: User clicks floating action icon
- **WHEN** the user clicks the floating icon
- **THEN** the full lookup/note popover expands at that cursor position immediately.

#### Scenario: User ignores floating action icon
- **WHEN** the user clicks elsewhere or moves the mouse away without interacting with the icon
- **THEN** the floating action icon fades out and dismisses automatically within 2 seconds.
