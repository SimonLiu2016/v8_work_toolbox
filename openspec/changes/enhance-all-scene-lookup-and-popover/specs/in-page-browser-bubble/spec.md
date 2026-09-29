## Purpose

Provides a high-fidelity in-page selection bubble for web browsers that displays immediate dictionary definitions and note capture actions anchored directly above or below selected text.

## ADDED Requirements

### Requirement: In-page DOM selection bubble
The browser companion extension SHALL inject an in-page floating bubble into web pages, positioned directly adjacent to the user's text selection range.

#### Scenario: User selects an English word on a web page
- **WHEN** the user selects a word or phrase in Chrome or Edge
- **THEN** the extension calculates the bounding client rect of the selection and renders an in-page card directly above or below the selection without launching an external OS window.

#### Scenario: Selection bubble displays dictionary result
- **WHEN** the selection bubble appears for a valid word
- **THEN** it displays the phonetic transcription, audio speaker icon, Chinese definitions, and part-of-speech chips within 500 milliseconds.

#### Scenario: User triggers note capture from bubble
- **WHEN** the user clicks "保存笔记" on the in-page bubble
- **THEN** the selected text, page title, and URL are dispatched to V8 Work Toolbox via deep link or background sync, and the bubble displays a saved confirmation checkmark.
