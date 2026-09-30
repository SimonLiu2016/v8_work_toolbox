# structured-note-delta-formatting Specification

## Purpose
Ensures captured notes parse Markdown syntax into rich AppFlowy Delta AST nodes, displaying styled elements rather than literal Markdown characters.
## Requirements
### Requirement: Structured rich-text note generation
The note capture service SHALL parse Markdown source text into AppFlowy Delta nodes representing headings, bold text, divider lines, and hyperlinks.

#### Scenario: Note containing divider and source metadata
- **WHEN** a note containing `---` and `**来源：** [URL]` is captured
- **THEN** the notebook editor renders an actual horizontal divider line, bold text for "来源：", and an active clickable hyperlink, with no raw `---` or `**` syntax characters visible.

