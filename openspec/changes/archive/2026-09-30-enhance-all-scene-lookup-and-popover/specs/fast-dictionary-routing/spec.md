## Purpose

Ensures sub-second dictionary lookup speed using domestic high-availability endpoints, preventing slow AI fallbacks and making AI translation an explicit user-initiated choice.

## ADDED Requirements

### Requirement: Sub-second high-availability dictionary resolution
The system SHALL query domestic high-availability dictionary endpoints for words and short phrases, returning phonetics, definitions, and audio links in under 500 milliseconds.

#### Scenario: Lookup word with dictionary entry
- **WHEN** a valid English word is queried
- **THEN** the system returns dictionary results within 500ms without initiating overseas network requests or AI completion calls.

### Requirement: Manual on-demand AI escalation
The system SHALL NOT automatically invoke slow AI completion when dictionary resolution yields no matches.

#### Scenario: Lookup query not found in dictionary
- **WHEN** the queried term is not found in the dictionary
- **THEN** the interface displays an empty search state and a prominent "使用 AI 深度解析" button.

#### Scenario: User clicks AI analysis button
- **WHEN** the user explicitly clicks the "使用 AI 深度解析" button
- **THEN** the system issues the AI completion request and displays streamed or finished AI analysis.
