# notebook-clipboard-image-paste Delta

## MODIFIED Requirements

### Requirement: Text pasting behaviour is preserved when the paste command is taken over
Taking over the editor's paste command SHALL NOT degrade pasting plain text. When the clipboard holds no image in any recognised form, the paste SHALL fall through to a plain-text insert — never silently doing nothing. The text insert SHALL split multi-line clipboard content into paragraphs, insert it at the cursor, replace any current selection, and inherit the inline attributes at the cursor. A URL or phone number pasted as text SHALL remain plain text, matching the behaviour of the paste command that was taken over.

#### Scenario: Plain text is pasted when the clipboard holds no image
- **WHEN** the user pastes while the clipboard holds neither a bitmap image, an image URL, nor a local image path
- **THEN** the clipboard text is inserted into the document at the cursor, with any current selection replaced and the cursor's inline attributes inherited
- **AND** the keystroke is not swallowed: the insertion either happens or the user is told why it could not.

#### Scenario: Text paste is not lost when the clipboard holds neither text nor image
- **WHEN** the user pastes while the clipboard holds no text and no image in any recognised form
- **THEN** the editor is left unchanged, and the keystroke is offered back to the system's own paste handling rather than being consumed silently.

#### Scenario: Multi-line text splits into paragraphs
- **WHEN** the user pastes clipboard text containing line breaks while the clipboard holds no image
- **THEN** the text is split into separate paragraph nodes, with any carriage returns stripped and trailing whitespace trimmed, matching the line structure of the pasted content.

#### Scenario: A pasted URL stays plain text
- **WHEN** the user pastes a URL or phone number as clipboard text
- **THEN** the URL or phone number is inserted as plain text, not converted into a hyperlink, because the taken-over command never converted it either
- **AND** treating this as unchanged behaviour is required so a future change does not claim to "restore" link conversion that never existed.

#### Scenario: Image takes priority over text when both are present
- **WHEN** the clipboard holds both a bitmap image and text
- **THEN** the image is inserted, because an image paste is the more specific intent.

#### Scenario: Text paste does not read the clipboard twice
- **WHEN** the paste handler has already read the clipboard text in order to decide whether it holds an image
- **THEN** the plain-text branch reuses that reading rather than fetching the clipboard a second time, so the two branches cannot disagree about what the clipboard contained.
