## ADDED Requirements

### Requirement: Custom attachment block in editor

The notebook editor SHALL render a custom attachment block (`AttachmentBlock`) when the document contains an attachment reference, displaying the file name, human-readable file size, and a file-type icon. The block SHALL provide clickable actions to reveal the file in Finder and to save-as to a user-chosen directory. Multiple attachment blocks MAY coexist in a single note, each independently operable.

#### Scenario: Attachment block renders file metadata

- **WHEN** a note contains one or more attachment references
- **THEN** each attachment renders as a distinct block showing the original filename, formatted file size (e.g. "1.2 MB"), and a type-specific icon

#### Scenario: Reveal attachment in Finder

- **WHEN** user clicks the "在访达中显示" action on an attachment block
- **THEN** the system opens Finder with the attachment file selected and revealed

#### Scenario: Save attachment as

- **WHEN** user clicks the "另存为" action on an attachment block
- **THEN** the system presents a save dialog and copies the attachment to the chosen destination

## MODIFIED Requirements

### Requirement: Attachment storage
The system SHALL store file attachments associated with notes, saved to the local filesystem. The system SHALL provide an API for users to add one or more files as attachments to an existing note: each file is copied into the application's own attachment storage under the note's subdirectory, and a reference is stored in the attachments table linked to the note. Multiple files MAY be added in a single action. The attachment's original filename, MIME type, and copied local path MUST be persisted. The application MUST NOT retain a dependency on the user's source file location: after the attachment is added, deleting the original source file MUST NOT affect the note's attachment.

#### Scenario: Attach a file to a note

- **WHEN** user inserts an image or file into a note
- **THEN** the file is copied to the attachments directory, and a reference is stored in the attachments table linked to the note.

#### Scenario: User adds multiple files as attachments

- **WHEN** user selects one or more files via the "添加附件" button in the editor toolbar
- **THEN** each file is copied to `attachmentsDir/<noteId>/`, an attachment record is created for each, and an attachment block is inserted into the note document for each file

#### Scenario: Attachment filename and metadata persisted

- **WHEN** a file is added as an attachment
- **THEN** the original filename, detected MIME type, and copied local path are stored in the attachments table

#### Scenario: Attachment survives deletion of the source file

- **WHEN** user adds a file located on the Desktop as an attachment and subsequently deletes that Desktop file
- **THEN** the note's attachment block remains fully functional — the file is still openable, revealable in Finder, and saveable to a new location — because it references the application's own copy rather than the original source location

#### Scenario: Import-created attachment is visible in the note

- **WHEN** user imports a document with the "保留原文件为附件" option checked
- **THEN** the created note contains an attachment block for the original file, and the block exposes the same reveal-in-Finder and save-as actions as a manually added attachment

## ADDED Requirements

### Requirement: Attachment reference integrity

An attachment block in a note document SHALL identify its file by attachment record ID and MUST NOT be the authoritative store of the file's location. The file's location SHALL be resolved from the attachments table at render time, so that a single source of truth governs where the attachment lives. When the attachment record cannot be resolved (e.g. it was deleted), the block SHALL render a clearly-labelled unavailable state rather than a broken or silently missing reference.

#### Scenario: Attachment block resolves its file from the attachment record

- **WHEN** an attachment block is rendered in the editor
- **THEN** the block resolves the file path from the attachments table using the attachment ID stored in the block, and renders the file's metadata and actions from that record

#### Scenario: Attachment record deleted

- **WHEN** the attachments table no longer contains the record referenced by an attachment block
- **THEN** the block renders an explicit unavailable state, and no file operation is offered on it

#### Scenario: Legacy attachment block with cached path

- **WHEN** an attachment block was written by an earlier version that cached a file path directly in the block data
- **THEN** the block remains renderable: it resolves through the attachment record when available, and falls back to the cached path only when no record can be found

### Requirement: Multi-format document import to notes

The notebook SHALL support importing documents in `.pdf`, `.docx`, `.xlsx`, `.md`, and `.txt` formats to create new notes. For `.md` and `.txt`, the content is read directly and converted to editor blocks via the Markdown converter. For `.pdf` and `.docx`, the system SHALL extract text with best-effort format preservation—DOCX headings, bold, lists, and tables SHALL be converted to Markdown before conversion to editor blocks; PDF text SHALL be extracted with structural restoration via per-run typographic attributes (font size), mapping relative font sizes to heading levels and preserving paragraph structure so the imported note is readable and copyable. For `.xlsx`, each worksheet SHALL be converted to a Markdown table and concatenated into the note body. The user MAY optionally choose to retain the original file as an attachment to the created note; when retained, the attachment SHALL be visible as an attachment block in the created note. Unsupported formats SHALL be rejected with a clear error message naming the supported formats.

#### Scenario: Import a Markdown file

- **WHEN** user selects a `.md` or `.txt` file for import
- **THEN** the file content is read, converted to editor blocks via MarkdownConverter, and a new note is created in the currently selected notebook

#### Scenario: Import a Word document with format preservation

- **WHEN** user selects a `.docx` file for import
- **THEN** the system converts the DOCX to Markdown preserving headings, bold, italic, lists, and tables, then converts the Markdown to editor blocks and creates a new note

#### Scenario: Import a PDF document with structural restoration

- **WHEN** user selects a `.pdf` file for import
- **THEN** the system extracts per-page text with typographic attributes, infers heading levels from relative font sizes, preserves paragraph boundaries, filters page-number and running-header noise, converts the result to Markdown, then to editor blocks, and creates a new note whose text is selectable and copyable

#### Scenario: Import a PDF whose text cannot be extracted

- **WHEN** user selects a `.pdf` file that contains no extractable text (e.g. a scanned image-only document)
- **THEN** the system reports a clear error indicating no text layer was found, and informs the user that retaining the original file as an attachment is available instead

#### Scenario: Import an Excel spreadsheet

- **WHEN** user selects a `.xlsx` file for import
- **THEN** each worksheet is converted to a Markdown table, tables are concatenated with sheet-name headings, the result is converted to editor blocks, and a new note is created

#### Scenario: Import with "retain original file as attachment" option

- **WHEN** user checks the "保留原文件为附件" option during import
- **THEN** the original file is copied to the note's attachments directory and an attachment record is created, in addition to the extracted text becoming the note content

#### Scenario: Unsupported format rejected

- **WHEN** user selects a file with an unsupported extension (e.g. `.pptx`, `.rtf`)
- **THEN** the system displays an error message naming the supported formats (.pdf, .docx, .xlsx, .md, .txt) and does not create a note

#### Scenario: Extracted text appears exactly once per source paragraph

- **WHEN** a document is imported and converted to editor blocks
- **THEN** every source line or paragraph appears exactly once in the resulting document — no paragraph is duplicated during Markdown-to-editor-block conversion

#### Scenario: Failed import leaves no half-built note

- **WHEN** import of a file fails after the note has already been created (for example the extracted text was written but retaining the original file as an attachment did not complete)
- **THEN** the partially created note, any attachment record and copied file it produced, and its full-text-search entry are all removed, so the reported failure matches the stored state — no orphan note, attachment file, or search hit is left behind
