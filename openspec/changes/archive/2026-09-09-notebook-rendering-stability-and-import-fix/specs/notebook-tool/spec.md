## Purpose

Provides resilient note viewing and editing, ensuring that notes with hyperlinks, embeds, and web-clipped content render reliably without crash, while supporting accurate Evernote code blocks and media conversions.

## ADDED Requirements

### Requirement: Editor Title Row Seamless Light Styling
The note editor title row SHALL render seamlessly on the white paper canvas without inherited dark theme background rectangles.

#### Scenario: Display note title
- **WHEN** user opens any note in the right editor panel
- **THEN** the title text input background is fully transparent and blends with the paper canvas without dark grey borders or fills.

### Requirement: Editor Style Resilience and Fallback
The Quill editor configuration SHALL provide comprehensive fallbacks for all rich text attributes (including links, lists, code, headers) to prevent null-pointer exceptions during widget build.

#### Scenario: Render note with external hyperlinks
- **WHEN** user selects a note containing links (e.g., Docker repository URLs)
- **THEN** the note content renders in full with clickable links, cursor is focusable, and no solid grey error widget is shown.

### Requirement: Robust Evernote Code Block Conversion
The Evernote import pipeline SHALL extract full multiline code blocks regardless of inner tag nesting, dash syntax variations, or web clipping structure.

#### Scenario: Import note containing multiline code
- **WHEN** importing Evernote notes with single-dash `-en-codeblock` or nested `div` lines
- **THEN** all code lines are preserved and converted into fenced markdown code blocks and native Quill code-block attributes.

### Requirement: Strict Media Type Verification for Image Embeds
The Evernote import service SHALL strictly verify resource MIME types before generating block image embeds.

#### Scenario: Import note with mixed attachments
- **WHEN** importing a note that contains both image files and non-image files (such as .dat, .plist, or source code)
- **THEN** only verified image attachments are inserted as in-line image embeds, and non-image files are preserved as note attachments without crashing image decoders.
