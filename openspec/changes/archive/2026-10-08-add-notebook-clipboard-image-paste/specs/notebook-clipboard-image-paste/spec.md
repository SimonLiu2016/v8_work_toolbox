## Purpose

Lets the user paste a clipboard image into a note with ⌘V or a toolbar button, treating it exactly like an image inserted from a file, so that screenshot-driven note taking (WeChat, QQ, macOS Grab) works as the single most natural path rather than a feature that silently does nothing.

## ADDED Requirements

### Requirement: Clipboard bitmap pasted as an inline image block
When the clipboard holds a bitmap image and the user pastes into the notebook editor, the note SHALL contain an inline image block whose storage and rendering are identical to an image inserted through the toolbar's insert-image action.

#### Scenario: WeChat screenshot pasted with ⌘V
- **WHEN** the user takes a screenshot with WeChat (leaving a bitmap on the macOS clipboard) and presses ⌘V with the note editor focused
- **THEN** the image is written into the note's attachment storage, an image block referencing it is inserted at the cursor position in the document body, and the image renders inline where the cursor was.

#### Scenario: Pasted image is not an attachment card and not an external link
- **WHEN** an image is added by pasting
- **THEN** it appears as an inline image block in the document, not as an attachment card, not as a remote URL reference, and not left behind in a temporary directory.

#### Scenario: Same storage path as the insert-image button
- **WHEN** an image is added by pasting instead of by the toolbar button
- **THEN** it lands in the same attachment storage location and is referenced from the note body through the same mechanism, so the two paths cannot diverge in how the image is stored or later resolved.

#### Scenario: Image persists across reopening the note
- **WHEN** the user closes and reopens a note containing a pasted image
- **THEN** the image still renders, because its bytes live in the note's attachment storage rather than depending on the clipboard or a temporary file.

### Requirement: Any source application produces the same result
Because the image is taken from what the clipboard contains rather than from which application put it there, pasting an image SHALL behave identically regardless of the software that produced the screenshot.

#### Scenario: Different screenshot tools
- **WHEN** the user pastes images produced by WeChat, QQ, the macOS screenshot shortcut, or Preview's copy command
- **THEN** each is inserted as an inline image block through the same path, with no per-application special casing.

#### Scenario: Image copied from a web page
- **WHEN** the user copies an image in a browser, which places an image URL rather than a bitmap on the clipboard, and pastes into the editor
- **THEN** the image is downloaded from that URL, stored locally, and inserted as an inline image block, so that copying from a browser is not a second-class case.

#### Scenario: File path on the clipboard
- **WHEN** the clipboard holds the path of a local image file (for example copied from Finder)
- **THEN** that file is stored into the note and inserted as an inline image block, preserving the behaviour that already exists for this case.

### Requirement: Paste by keyboard shortcut and by explicit button
Pasting an image SHALL be reachable both by keyboard shortcut and from an explicit toolbar control, so the feature does not depend on a single invisible path.

#### Scenario: Toolbar paste-image button
- **WHEN** the user clicks the toolbar's paste-image button while the clipboard holds an image
- **THEN** the same image is inserted at the cursor as would be inserted by ⌘V, and the button's tooltip makes clear it operates on the clipboard.

#### Scenario: Paste works even if the shortcut layer changes
- **WHEN** the underlying editor component is upgraded and its own command handling changes
- **THEN** the toolbar button continues to work, because it does not route through the editor's command table.

### Requirement: Text pasting behaviour is preserved when the paste command is taken over
Taking over the editor's paste command SHALL NOT degrade pasting plain text: multi-line splitting, URL and phone auto-detection, inheriting the selection's inline attributes, and replacing the current selection are all preserved.

#### Scenario: Plain text paste unchanged
- **WHEN** the user pastes text containing no image and no markup into the editor
- **THEN** the text is inserted with the same line structure, link detection, and formatting inheritance as before this capability existed, and any selected content is replaced.

#### Scenario: Image takes priority over text when both are present
- **WHEN** the clipboard holds both a bitmap image and text
- **THEN** the image is inserted, because an image paste is the more specific intent.

### Requirement: Paste failures are visible
Every stage of pasting an image SHALL report a distinguishable, human-readable failure rather than doing nothing — except the case where the clipboard holds no image at all, which is the normal text-paste case and must stay silent.

#### Scenario: Clipboard without any image form pastes as text, silently
- **WHEN** the user pastes while the clipboard holds neither a bitmap image, an image URL, nor a local image path
- **THEN** the paste proceeds as a plain-text paste and no image-related message is shown, because pressing ⌘V with no image on the clipboard is the ordinary text-paste case and not a failure.

#### Scenario: Bitmap present but unreadable is reported
- **WHEN** the clipboard holds a bitmap image that cannot be read out
- **THEN** the user is told the clipboard image could not be read, with a hint about automation permission, and the editor is left unchanged.

#### Scenario: Image URL download fails
- **WHEN** the clipboard holds an image URL that cannot be downloaded (unreachable host, non-image response, timeout)
- **THEN** the user is told the image could not be fetched, with the reason, and the editor is left unchanged rather than half-updated.

#### Scenario: Image beyond the size cap is reported
- **WHEN** the clipboard holds an image URL whose response exceeds the size cap
- **THEN** the user is told the image exceeded the cap and the paste was cancelled, rather than a partial write arriving in the note.

#### Scenario: Writing the image into note storage fails
- **WHEN** the image was obtained but could not be written into the note's attachment storage
- **THEN** the user is told the save failed, and no dangling reference is left in the document body.

#### Scenario: Image URL fetching is unaffected by proxy settings
- **WHEN** the user has a proxy configured for the application's other network paths
- **THEN** the image URL is still fetched directly, because images are typically served from CDNs that are reachable without a proxy; routing them through one would only add latency.

### Requirement: Paste is scoped to the note being edited
Pasting an image SHALL associate the stored image with the note that is open at the time of the paste.

#### Scenario: Image lands in the open note
- **WHEN** the user pastes an image while a specific note is open
- **THEN** the stored image is recorded against that note, so it is cleaned up and resolved with that note rather than with whichever note happened to be open earlier.
