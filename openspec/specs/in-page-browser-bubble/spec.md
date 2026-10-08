# in-page-browser-bubble Specification

## Purpose
Provides a high-fidelity in-page selection bubble for web browsers that displays immediate dictionary definitions and note capture actions anchored directly above or below selected text.
## Requirements
### Requirement: In-page DOM selection bubble
The browser companion extension SHALL inject an in-page floating bubble into web pages, positioned directly adjacent to the user's text selection range.

#### Scenario: User selects an English word on a web page
- **WHEN** the user selects a word or phrase in Chrome or Edge
- **THEN** the extension calculates the bounding client rect of the selection and renders an in-page card directly above or below the selection without launching an external OS window.

#### Scenario: Selection bubble displays dictionary result
- **WHEN** the selection bubble appears for a valid word
- **THEN** it displays the phonetic transcription, audio speaker icon, Chinese definitions, and part-of-speech chips within 500 milliseconds.

#### Scenario: Definitions are grouped by part of speech
- **WHEN** the dictionary result contains part-of-speech groupings
- **THEN** the bubble renders each part of speech with its own definitions beneath it, rather than a single flat list where the part of speech is only a prefix of the first definition
- **AND** the part of speech is presented as a distinct label for the group, not as text that reads as part of the definition.

#### Scenario: Examples are shown when the dictionary provides them
- **WHEN** the dictionary result contains examples for a resolved term
- **THEN** the bubble shows those examples with the term's definitions, bounded so the bubble remains usable at its fixed width
- **AND** when the result contains no examples the bubble omits the example area entirely rather than showing an empty placeholder.

#### Scenario: Bubble falls back to flat definitions when groupings are absent
- **WHEN** the dictionary response carries only a flat definition list and no grouped meanings (for example a bridge version that predates grouped responses)
- **THEN** the bubble renders the flat list exactly as it did before this capability existed, so an older desktop application does not degrade the bubble.

#### Scenario: Adding to the vocabulary book carries examples
- **WHEN** the user activates the bubble's add-to-vocabulary action for a term whose dictionary result contained examples
- **THEN** the examples are sent along with the word, phonetic, and definitions, so the stored entry carries the same information the bubble showed.

#### Scenario: Commonly used phrases are not silently expected
- **WHEN** the bubble renders a dictionary result for a single word
- **THEN** the bubble does not present a "commonly used phrases" section, because the dictionary source does not provide phrase data
- **AND** this is a deliberate absence rather than a dropped field, so a future reader does not re-investigate it as a defect; supplying phrase data requires a source that carries it and is out of this capability's scope.

#### Scenario: User triggers note capture from bubble
- **WHEN** the user clicks "保存笔记" on the in-page bubble
- **THEN** the selected text, page title, and URL are dispatched to V8 Work Toolbox via deep link or background sync, and the bubble displays a saved confirmation checkmark.

