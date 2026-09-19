## ADDED Requirements

### Requirement: Custom attachment block in editor

The notebook editor SHALL render a custom attachment block (`AttachmentBlock`) when the document contains an attachment reference, displaying the file name, human-readable file size, and a file-type icon. The block SHALL identify its file by attachment record ID and resolve the file's location from the attachment store rather than from a path cached in the document, so that the block always points at the application-managed copy. The block SHALL provide clickable actions to reveal the file in Finder and to save-as to a user-chosen directory. Multiple attachment blocks MAY coexist in a single note, each independently operable. An "添加附件" button SHALL be present in the editor toolbar, allowing the user to select one or more files to insert as attachment blocks.

#### Scenario: Attachment block renders file metadata

- **WHEN** a note contains one or more attachment references
- **THEN** each attachment renders as a distinct block showing the original filename, formatted file size (e.g. "1.2 MB"), and a type-specific icon

#### Scenario: Attachment block points at the application-managed copy

- **WHEN** a file is added as an attachment and the block is rendered
- **THEN** the block's actions operate on the copy held in the application's attachment storage, not on the user's original source path

#### Scenario: Reveal attachment in Finder

- **WHEN** user clicks the "在访达中显示" action on an attachment block
- **THEN** the system opens Finder with the attachment file selected and revealed

#### Scenario: Save attachment as

- **WHEN** user clicks the "另存为" action on an attachment block
- **THEN** the system presents a save dialog and copies the attachment to the chosen destination

#### Scenario: Add attachment from toolbar

- **WHEN** user clicks the "添加附件" button in the editor toolbar and selects one or more files
- **THEN** each selected file is copied to the note's attachments directory, an attachment record is created, and an attachment block referencing that record is inserted at the current cursor position in the document

#### Scenario: Attachment unavailable after record removal

- **WHEN** an attachment block's referenced record no longer exists
- **THEN** the block renders an explicit unavailable state without offering file actions
